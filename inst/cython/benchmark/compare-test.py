#########################################################
### This code was used to run tests with synthetic data
### for the purpose of measuring speed improvments
### Works w/o R environment
#########################################################
import numpy as np
import pandas as pd
import math as math
from re import search as search_python
from re import findall
from numpy import append
from tqdm import tqdm
import time


import sys, os
sys.path.append(os.path.abspath("../../python"))
## !!!
## !! Make sure to add TSW_Package into sys path ### 
## !! sys.path.append(os.path.asbpath("../"))

from init import init_Hmat, init_TRmat, init_TCmat, init_traceMat
from score import TSW_scoreMat, find_best_score
from align import align_TSW
from TSW_Package import TSWc, fbs, aTSW

from sampling import generate

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

    ### TSWc timed ###    
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


    ### ------ TEST ORIGINAL BLOCK ---
    stime = time.perf_counter()
    for i in tqdm(range(0, len(mem_index))):
        mj, mi = mem_index[i]

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
        def f ( my_list ):
            summ = 0 
            for i in my_list:
                summ+=1
    
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
    etime = time.perf_counter()
    print(f"Execution time for align_TSW (Py): {end - start:.6f} seconds")

    ### ------ UPDATED CY BLOCK ---
    drug_names = np.array(list(drug2idx.keys()), dtype=object)  
    start = time.perf_counter()
    returnDat2 = aTSW(traceMat, 
           s1_times, s1_drugs, s1_len, 
           s2_times, s2_drugs, s2_len, 
           mem_index, mem_score, drug_names) 
    end = time.perf_counter()
    print(f"Execution time for align_TSW (C): {end - start:.6f} seconds")
    
    # Reshape return array to account for secondary alignments
    # ------ Exact broadcasting -----
    returnDat_bloat = np.concatenate([returnDat[:10], returnDat2.ravel()], axis=0) # Placeholder bloat takeup, later just initiate to exact match. Line-55
    
    # ----- Exact format processing -----
    returnDat = returnDat.reshape(len(mem_index) + 1, 10)
    returnDat = pd.DataFrame(returnDat)
    
    returnDat_bloat = returnDat_bloat.reshape(len(mem_index) + 1, 10)
    returnDat_bloat = pd.DataFrame(returnDat_bloat)
    
    # Force dtype equality # TODO: (Optional) match dtypes
    returnDat_str = returnDat.astype(str)
    returnDat_bloat_str = returnDat_bloat.astype(str)
    pd.testing.assert_frame_equal(returnDat_str, returnDat_bloat_str)

    return returnDat



def test():
    s1 = [
        ["1", "a"],
        ["1", "a"],
    ]
    s2 = [
        ["0", "a"],
        ["10", "a"],
        ["11", "a"],
    ]


    s = {
        "a": [1.0, -1.1, -1.1],
        "b": [-1.1, 1.0, -1.1],
        "c": [-1.1, -1.1, 1.0],
    }
    s = pd.DataFrame(s, index=["a", "b", "c"])
    return s1,s2,s 

if __name__ == "__main__":

    g = 0.4
    T = 0.5
    method = "PropDiff"
    verbose = 2

    print("Small test:")
    s1,s2,s = test()

    temporal_alignment(s1, s2, g, T, s, verbose, mem=-1, removeOverlap=0, method="PropDiff")

    print("Medium test:")
    s, s1,s2 =  generate(
            n_labels=6,
            seq_length=5,   
            n_times=3,      
            noise_block_len=(18,100),
            seed=123
        )

    print("Large test:")
    s, s1,s2 =  generate(
            n_labels=15,
            seq_length=20,   
            n_times=10,      
            noise_block_len=(500,2000),
            seed=123
        )
    
    print(s.shape)
    print(len(s1), len(s1[1]))
    print(len(s2), len(s2[1]))
    
    temporal_alignment(s1, s2, g, T, s, verbose, mem=-1, removeOverlap=0, method="PropDiff")

    