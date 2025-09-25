import numpy as np
import pandas as pd
import math as math
from re import search as search_python
from re import findall
from numpy import append
from init import init_Hmat, init_TRmat, init_TCmat, init_traceMat
from score import TSW_scoreMat, find_best_score
from align import align_TSW
from utils import timeit
from TSW_Package import TSWc, fbs, aTSW


pd.options.display.max_columns = None


def find_gaps(pat, seq):
    gaps_init = search_python(pat, seq)
    if gaps_init is not None:
        gaps = len(findall("__", gaps_init[0]))
    else:
        gaps = 0

    return gaps


def temporal_alignment(
    s1, s2, g, T, s, verbose, mem=-1, removeOverlap=0, method="PropDiff"
): 
    s1_len = len(s1)
    s2_len = len(s2)

    # Initialise the 3 score matrices and the traceback matrix
    H = init_Hmat(s1_len, s2_len)
    TR = init_TRmat(s1, s1_len, s2, s2_len)
    TC = init_TCmat(s1, s1_len, s2, s2_len)
    traceMat = init_traceMat(s1_len, s2_len)

    # Setup pattern for detecting sequence lengths, by number of "."s (Aligned drugs)
    pat = "\."
    # Setup pattern for detecting sequence gaps, by number of "__"s (Aligned gaps)
    pat_end_gap = "(__;)+__$|__$"

    # Init return Dat
    returnDat = np.empty(10)

    # Impute score matrix, retrieve relevant vars - python
    # TSW_scoreMat()
    # timit("PYTHON", TSW_scoreMat, [s1, s1_len, s2, s2_len, g, T, H, TR, TC, traceMat, s, method])

    # ------------------ NEW CALL -------------------
    # Impute score matrix, retrieve relevant vars - C
    # Re-Initialise the 3 score matrices and the traceback matrix
    # H = init_Hmat(s1_len, s2_len)
    # TR = init_TRmat(s1, s1_len, s2, s2_len)
    # TC = init_TCmat(s1, s1_len, s2, s2_len)
    # traceMat = init_traceMat(s1_len, s2_len)

    # This step prepare inputs for faster call - need to make sure it has correct data and dtypes
    drug2idx = {k: i for i, k in enumerate(s.keys())}
    s1_times = np.ascontiguousarray([float(t) for t, d in s1], dtype=np.float64)
    s2_times = np.ascontiguousarray([float(t) for t, d in s2], dtype=np.float64)
    s1_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s1], dtype=np.int32)
    s2_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s2], dtype=np.int32)

    # Set dtypes
    s_arr = np.ascontiguousarray(s.to_numpy(dtype=np.float64))  # converting to matrix
    H        = np.ascontiguousarray(H, dtype=np.float64)
    TR       = np.ascontiguousarray(TR, dtype=np.float64)
    TC       = np.ascontiguousarray(TC, dtype=np.float64)
    traceMat = np.ascontiguousarray(traceMat, dtype=np.int32)
    s_arr    = np.ascontiguousarray(s_arr, dtype=np.float64)

    # TSWc(s1_times, s1_drugs, s1_len,
    #     s2_times, s2_drugs, s2_len,
    #     g, T, H, TR, TC, traceMat,
    #     s_arr, method)
    
    # timit("C", TSWc, [s1_times, s1_drugs, s1_len,
    #     s2_times, s2_drugs, s2_len,
    #     g, T, H, TR, TC, traceMat,
    #     s_arr, method])
    TSWc(s1_times, s1_drugs, s1_len,
        s2_times, s2_drugs, s2_len,
        g, T, H, TR, TC, traceMat,
        s_arr, method)


    # Find best scoring cell
    # finalScore, finalIndex, mem_index, mem_score = find_best_score(
    #     H, s1_len, s2_len, mem, verbose
    # )
    finalScore, finalIndex, mem_index, mem_score = fbs(
        H, s1_len, s2_len, mem, verbose
    )
    
        
    for i in range(0, len(mem_index)):
        # s1_aligned_t, s2_aligned_t, totAligned_t = align_TSW(
            # traceMat, s1, s2, s1_len, s2_len, mem_index[i]
            # )
        max_index = mem_index[i]
        s1_aligned_t, s2_aligned_t, totAligned_t = aTSW(
           traceMat, 
           s1_times, s1_drugs, s1_len, 
           s2_times, s2_drugs, s2_len, 
           max_index
        )

        s_f_len = max(len(findall(pat, s2_aligned_t)), len(findall(pat, s1_aligned_t)))

        s1_end_gaps = find_gaps(pat_end_gap, s1_aligned_t)

        s1_end = mem_index[i][1]
        s2_end = mem_index[i][0] - s1_end_gaps

        if (s1_start + 1) > 1:
            totAligned_t = totAligned_t + (s1_end - (s1_start + 1))
            s_f_len = s_f_len + (s1_end - (s1_start + 1))

        adjustedS = mem_score[i] / totAligned_t

        returnDat = append(
            returnDat,
            [
                s1_aligned_t,
                s2_aligned_t,
                mem_score[i],
                adjustedS,
                s1_start + 1,
                s1_end,
                s2_start + 1,
                s2_end,
                s_f_len,
                totAligned_t,
            ],
            axis=0,
        )

    # Reshape return array to account for secondary alignments
    returnDat = returnDat.reshape(len(mem_index) + 1, 10)
    returnDat = pd.DataFrame(returnDat)

    return returnDat
