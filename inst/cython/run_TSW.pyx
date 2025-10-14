# cython: boundscheck=False, wraparound=False, nonecheck=True, cdivision=True, language_level=3
import numpy as np
cimport numpy as np
import pandas as pd
import math as math
from tqdm import tqdm

# --- ADD TSW_Package to sys.path
import sys, os

# Full path to the current script
#current_file = os.path.abspath(__file__)
#current_dir = os.path.dirname(current_file)

# Build absolute path to ../cython/TSW_Package (or compiled .so)
#cython_dir = os.path.abspath(current_dir)  # normalize path

# Add to Python path so you can import
#sys.path.append(cython_dir)
from init_TSW cimport init_Hmat, init_TCmat, init_TRmat, init_traceMat
from TSW_scoreMat cimport TSW_scoreMat as TSWc
from find_best_score cimport find_best_score as fbs
from align_TSW cimport aTSW



cpdef object make_matrix(object val1, object val2):
    """
    Generate a similarity matrix for a given set of drug records.
    Same drugs will have similarity of 1, all others -1.

    Parameters
    ----------
    val1 : list
        Encoded drug records (each element like [time, drug]).
    val2 : list
        Encoded drug records (each element like [time, drug]).

    Returns
    -------
    pandas.DataFrame
        Similarity matrix.
    """
    cdef Py_ssize_t i, n1, n2, n
    cdef list all_second, unique_vals
    cdef np.ndarray[np.float64_t, ndim=2] mat

    n1 = len(val1)
    n2 = len(val2)

    # Build combined list of second elements (drug identifiers)
    all_second = [val1[i][1] for i in range(n1)] + [val2[i][1] for i in range(n2)]

    # Remove duplicates while preserving order
    unique_vals = list(dict.fromkeys(all_second))
    n = len(unique_vals)

    # Create identity matrix with 1 on diagonal, -1.1 elsewhere
    mat = np.identity(n, dtype=np.float64)
    mat[mat == 0] = -1.1

    # Build labeled DataFrame
    return mat, unique_vals


cpdef object temporal_alignment(
    object s1,
    object s2,
    double g,
    double T,
    object s,
    bint verbose,
    int mem=-1,
    int removeOverlap=0,
    object method="PropDiff"
):
    """
    Perform temporal alignment between two drug records using the TSW algorithm.

    Parameters
    ----------
    s1, s2 : list of [time, drug] pairs
    g, T   : float penalties
    s      : similarity matrix (or None)
    verbose : bool
    mem, removeOverlap : optional alignment controls
    method : str
    """
    cdef int s1_len = len(s1)
    cdef int s2_len = len(s2)

    # Create similarity matrix if not provided
    if s is None:
        s, labels = make_matrix(s1, s2)

    # Create matrices (H, TR, TC, traceMat)
    H = init_Hmat(s1_len, s2_len)

    TR = init_TRmat(s1_len, s2_len)
    TC = init_TCmat(s1_len, s2_len)
    traceMat = init_traceMat(s1_len, s2_len)

    # Map drugs to numeric indices
    cdef dict drug2idx = {k: i for i, k in enumerate(labels)}
    cdef double[:] s1_times = np.ascontiguousarray([float(t) for t, d in s1], dtype=np.float64)
    cdef double[:] s2_times = np.ascontiguousarray([float(t) for t, d in s2], dtype=np.float64)
    cdef int[:] s1_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s1], dtype=np.int32)
    cdef int[:] s2_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s2], dtype=np.int32)

    # Call temporal scoring function (TSWc)
    TSWc(
        s1_times,
        s1_drugs,
        s1_len,
        s2_times,
        s2_drugs,
        s2_len,
        g,
        T,
        H,
        TR,
        TC,
        traceMat,
        s,
        method,
    )

    # Find best scoring cells (within 10% of max)
    mem_index, mem_score = fbs(H, s1_len, s2_len, mem, verbose)

    # Perform alignment reconstruction
    drug_names = np.array(list(drug2idx.keys()), dtype=object)

    returnDat = aTSW(
        traceMat,
        s1_times,
        s1_drugs,
        s1_len,
        s2_times,
        s2_drugs,
        s2_len,
        mem_index,
        mem_score,
        drug_names,
    )

    # Return as DataFrame
    returnDat = pd.DataFrame(returnDat)
    returnDat.columns = [
        "Regimen",
        "DrugRecord",
        "Score",
        "adjustedS",
        "regimen_Start",
        "regimen_End",
        "drugRec_Start",
        "drugRec_End",
        "Aligned_Seq_len",
        "totAlign",
    ]

    return returnDat


cdef list encode_c(str str_seq):
    """
    Encode a semicolon-separated string of drug records into structured pairs.
    """
    cdef list s_encoded = []
    cdef list s_temp
    cdef list t_vec
    cdef str item

    s_temp = str_seq.rstrip(";").split(";")

    for item in s_temp:
        t_vec = item.split(".")
        s_encoded.append(t_vec)

    return s_encoded


def align_patients_regimens_fast(
    patients,
    regimens,
    str col_name_patient_id="person_id",
    str col_name_patient_record="seq",
    str col_name_regimens="shortString",
    str col_name_regName="regName",
    double g=0.4,
    double T=0.5,
    s=None,
    int verbose=0,
    int mem=-1,
    int removeOverlap=1,
    str method="PropDiff",
):
    """
    Fast version using NumPy arrays instead of Pandas iteration.
    """

    # --- Extract arrays ---
    cdef np.ndarray patient_ids = patients[col_name_patient_id].to_numpy(dtype=object)
    cdef np.ndarray patient_records = patients[col_name_patient_record].to_numpy(dtype=object)
    cdef Py_ssize_t n_patients = patient_records.shape[0]

    cdef np.ndarray regimen_names = regimens[col_name_regName].to_numpy(dtype=object)
    cdef np.ndarray regimen_seqs = regimens[col_name_regimens].to_numpy(dtype=object)
    cdef Py_ssize_t n_regimens = regimen_seqs.shape[0]

    # --- Initialize results list ---
    cdef list dfs = []
    cdef object s1, s2, s1_copy, df
    cdef set s1_drugs, s2_drugs
    cdef str patient_seq, regimen_seq
    cdef Py_ssize_t i, j

    # --- Main loop ---
    for i in tqdm(range(n_patients), desc="Processing patients"):
        patient_seq = patient_records[i]
        s1 = encode_c(patient_seq)
        s1_drugs = set(item[1] for item in s1)

        for j in range(n_regimens):
            regimen_seq = regimen_seqs[j]
            s2 = encode_c(regimen_seq)
            s2_drugs = set(item[1] for item in s2)

            if s2_drugs.issubset(s1_drugs):
                s1_copy = [x[:] for x in s1]

                df = temporal_alignment(
                    s2,
                    s1_copy,
                    g=g,
                    T=T,
                    s=s,
                    verbose=verbose,
                    mem=mem,
                    removeOverlap=removeOverlap,
                    method=method,
                )

                df["regName"] = regimen_names[j]
                df["Regimen_full"] = regimen_seq
                df["personID"] = patient_ids[i]
                df["DrugRecord_full"] = patient_seq

                dfs.append(df)

    # --- Combine all DataFrames ---
    if dfs:
        result = pd.concat(dfs, ignore_index=True)
    else:
        result = pd.DataFrame()

    return result