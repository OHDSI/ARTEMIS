import numpy as np
import pandas as pd
import math as math
from re import search as search_python
from re import findall
from numpy import append
from init import init_Hmat, init_TRmat, init_TCmat, init_traceMat

# --- ADD TSW_Package to sys.path
import sys, os
sys.path.append(os.path.abspath("<PATH/TO/TSW_Package_PARENT_DIR>"))

from TSW_Package import TSWc, fbs, aTSW


pd.options.display.max_columns = None


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
    # ------ Set dtypes ------
    s_arr    = np.ascontiguousarray(s.to_numpy(dtype=np.float64))  # converting to matrix
    H        = np.ascontiguousarray(H, dtype=np.float64)
    TR       = np.ascontiguousarray(TR, dtype=np.float64)
    TC       = np.ascontiguousarray(TC, dtype=np.float64)
    traceMat = np.ascontiguousarray(traceMat, dtype=np.int32)


    # ----- Init return Dat ------
    returnDat_init = np.empty(10)

    # ------ Create inputs arrays ------
    drug2idx = {k: i for i, k in enumerate(s.keys())}
    s1_times = np.ascontiguousarray([float(t) for t, d in s1], dtype=np.float64)
    s2_times = np.ascontiguousarray([float(t) for t, d in s2], dtype=np.float64)
    s1_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s1], dtype=np.int32)
    s2_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s2], dtype=np.int32)

    # TSW_score   
    start = time.perf_counter()
    TSWc(s1_times, s1_drugs, s1_len,
        s2_times, s2_drugs, s2_len,
        g, T, H, TR, TC, traceMat,
        s_arr, method)
    end = time.perf_counter()
    print(f"Execution time for TSW_score (C): {end - start:.6f} seconds")

    # Find best scoring cell
    start = time.perf_counter()
    finalScore, finalIndex, mem_index, mem_score = fbs(
        H, s1_len, s2_len, mem, verbose
    )
    end = time.perf_counter()
    print(f"Execution time for Find Best Score (C): {end - start:.6f} seconds")

    # Align 
    drug_names = np.array(list(drug2idx.keys()), dtype=object)  
    start = time.perf_counter()
    returnDat = aTSW(traceMat, 
           s1_times, s1_drugs, s1_len, 
           s2_times, s2_drugs, s2_len, 
           mem_index, mem_score, drug_names) 
    end = time.perf_counter()
    print(f"Execution time for align_TSW (C): {end - start:.6f} seconds")
    
    # Reshape return array to account for secondary alignments
    # ------ Exact broadcasting -----
    returnDat_fin = np.concatenate([returnDat_init, returnDat.ravel()], axis=0) 
    # ----- Exact format processing -----
    returnDat_fin = returnDat_fin.reshape(len(mem_index) + 1, 10)
    returnDat_fin = pd.DataFrame(returnDat_fin)
    
    return returnDat_fin