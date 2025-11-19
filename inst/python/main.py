import numpy as np
import pandas as pd
import math as math
from re import search as search_python
from re import findall
from init import init_Hmat, init_TRmat, init_TCmat, init_traceMat
from score import TSW_scoreMat, find_best_score
from align import align_TSW
from tqdm import tqdm

pd.options.display.max_columns = None


def find_gaps(pat, seq):
    gaps_init = search_python(pat, seq)
    if gaps_init is not None:
        gaps = len(findall("__", gaps_init[0]))
    else:
        gaps = 0

    return gaps


def encode_py(str_seq: str):
    """
    Encode a semicolon-separated string of drug records into structured pairs.

    Each element of the input string has the form "x.y" (e.g., "0.c").
    The function splits on ';' and then splits each element on '.'.

    Parameters
    ----------
    str_seq : str
        Input string of drug records, e.g. "0.c;0.c;1.a;1.b;1.c".
        A trailing semicolon is allowed and will be ignored.

    Returns
    -------
    list of list of str
        Encoded records, where each record is represented as [x, y].

    Examples
    --------
    >>> encode_py("0.c;0.c;1.a;1.b;1.c;")
    [['0', 'c'], ['0', 'c'], ['1', 'a'], ['1', 'b'], ['1', 'c']]
    """
    # Remove trailing ';' if present and split by ';'
    s_temp = str_seq.rstrip(";").split(";")

    s_encoded = []

    for item in s_temp:
        # Split each "x.y" into [x, y]
        t_vec = item.split(".")
        s_encoded.append(t_vec)

    return s_encoded


def make_matrix(val1, val2):
    """
    Generate similarity matrix for a given set of drug records.
    Same drugs will have similarity of 1, all others -1.

    Parameters
    ----------
    val1 : list
        Encoded drug records (output of encode_py).
    val2 : list
        Encoded drug records (output of encode_py).

    Returns
    -------
    pandas.DataFrame
        Similarity matrix.
    """
    all_second = [item[1] for item in val1] + [item[1] for item in val2]

    # Keep unique elements
    unique_vals = list(dict.fromkeys(all_second))
    n = len(unique_vals)
    mat = np.identity(n, dtype=np.float64)
    mat[mat == 0] = -1.1

    # Build DataFrame with row/col labels
    df = pd.DataFrame(mat, index=unique_vals, columns=unique_vals)
    return df


def temporal_alignment(
    s1, s2, g=0.4, T=0.5, s=None, verbose=0, mem=-1, removeOverlap=1, method="PropDiff"
):
    """
    Align s1 to s2.

    Parameters
    ----------
    s1 : list
        Encoded drug records (output of encode_py).
    s2 : list
        Encoded drug records (output of encode_py).
    g : float, optional
        Gap penalty, by default 0.4.
    T : float, optional
        Time penalty, by default 0.5.
    s : pandas.DataFrame, optional
        Similarity matrix, by default None.
    verbose : int, optional
        Verbosity level, by default 0.
    mem : int, optional
        Number of top alignments to return, by default -1 (all).
    removeOverlap : int, optional
        Whether to remove overlapping drugs in s1 after each alignment, by default 1 (True
        in R).
    method : str, optional
        Method for time penalty calculation, by default "PropDiff".

    Returns
    -------
    pandas.DataFrame
        Aligned sequences.
    """
    if s is None:
        s = make_matrix(s1, s2)

    s1_len = len(s1)
    s2_len = len(s2)

    # Initialise the 3 score matrices and the traceback matrix
    H = init_Hmat(s1_len, s2_len)
    TR = init_TRmat(s1, s1_len, s2, s2_len)
    TC = init_TCmat(s1, s1_len, s2, s2_len)
    traceMat = init_traceMat(s1_len, s2_len)

    # Setup pattern for detecting sequence lengths, by number of "."s (Aligned drugs)
    pat = r"\."
    # Setup pattern for detecting sequence gaps, by number of "__"s (Aligned gaps)
    pat_end_gap = r"(__;)+__$|__$"

    # Init return Dat
    returnDat = []

    # Impute score matrix, retrieve relevant vars
    TSW_scoreMat(s1, s1_len, s2, s2_len, g, T, H, TR, TC, traceMat, s, method)

    # Find best scoring cell
    mem_index, mem_score = find_best_score(H, s1_len, s2_len, mem, verbose)

    for i in range(0, len(mem_index)):
        s1_aligned_t, s2_aligned_t, totAligned_t, s1_start, s2_start = align_TSW(
            traceMat, s1, s2, s1_len, s2_len, mem_index[i]
        )

        s_f_len = max(len(findall(pat, s2_aligned_t)), len(findall(pat, s1_aligned_t)))

        s1_end_gaps = find_gaps(pat_end_gap, s1_aligned_t)

        s1_end = mem_index[i][1]
        s2_end = mem_index[i][0] - s1_end_gaps

        if (s1_start + 1) > 1:
            totAligned_t = totAligned_t + (s1_end - (s1_start + 1))
            s_f_len = s_f_len + (s1_end - (s1_start + 1))

        adjustedS = mem_score[i] / totAligned_t

        row = {
            "Regimen": s1_aligned_t,
            "DrugRecord": s2_aligned_t,
            "Score": mem_score[i],
            "adjustedS": adjustedS,
            "regimen_Start": s1_start + 1,
            "regimen_End": s1_end,
            "drugRec_Start": s2_start + 1,
            "drugRec_End": s2_end,
            "Aligned_Seq_len": s_f_len,
            "totAlign": totAligned_t,
        }
        returnDat.append(row)
    returnDat = pd.DataFrame(returnDat)

    return returnDat


def align_patients_regimens(
    patients,
    regimens,
    col_name_patient_id="person_id",
    col_name_patient_record="seq",
    col_name_regimens="shortString",
    col_name_regName="regName",
    g=0.4,
    T=0.5,
    s=None,
    verbose=0,
    mem=-1,
    removeOverlap=1,
    method="PropDiff",
):
    dfs = []

    for i, row1 in tqdm(
        patients.iterrows(), desc="Processing patients", total=patients.shape[0]
    ):
        s1 = encode_py(row1[col_name_patient_record])
        s1_drugs = set(item[1] for item in s1)

        for j, row2 in regimens.iterrows():
            s2 = encode_py(row2[col_name_regimens])
            s2_drugs = set(item[1] for item in s2)

            # Condition: all drugs from regimen in patient record
            if s2_drugs.issubset(s1_drugs):
                # Avoid modifying original s1 within temporal_alignment
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

                df["regName"] = row2[col_name_regName]
                df["Regimen_full"] = row2[col_name_regimens]
                df["personID"] = row1[col_name_patient_id]
                df["DrugRecord_full"] = row1[col_name_patient_record]
                dfs.append(df)
    if not dfs:
        return pd.DataFrame()  # Return empty DataFrame if no alignments found

    result = pd.concat(dfs, ignore_index=True)
    return result


def main():
    # Example input for testing
    # patients = pd.read_csv("example_patients.csv")
    # regimens = pd.read_csv("example_regimens.csv")
    patients = pd.DataFrame(
        {
            "person_id": ["test1"],
            "seq": [
                "0.cisplatin;0.pemetrexed;21.cisplatin;0.pemetrexed;42.cisplatin;0.pemetrexed;"
            ],
        }
    )

    regimens = pd.DataFrame(
        {
            "regName": ["Regimen1"],
            "shortString": ["14.pemetrexed;14.pemetrexed;"],
        }
    )

    df = align_patients_regimens(patients, regimens)
    # print(df)
    print("Python module loaded successfully.")


# This ensures the main function runs only when the script is executed directly
if __name__ == "__main__":
    main()
