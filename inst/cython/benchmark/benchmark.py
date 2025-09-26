import pandas as pd
import math as math

import sys 

sys.path.append("../../python")
from init import *
from score import *
from align import *
from score import TSW_scoreMat_cleaned as python_func

# ADD TSW_Package to path
from TSW_Package import TSWc as cython_func

from sampling import generate

# measure time
import time

def timit(tag, func, data):
    start = time.perf_counter()
    func(*data)
    end = time.perf_counter()
    print(f"{tag} - Execution time: {end - start:.6f} seconds")

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


def run_benchmark(s1, s2, s, print_mat=False):

    g = 0.4
    T = 0.5
    method = "PropDiff"

    s1_len = len(s1)
    s2_len = len(s2)
    # ------------------ python -------------------

    # Initialise the 3 score matrices and the traceback matrix
    H = init_Hmat(s1_len, s2_len, g)
    TR = init_TRmat(s1, s1_len, s2, s2_len)
    TC = init_TCmat(s1, s1_len, s2, s2_len)
    traceMat = init_traceMat(s1_len, s2_len)

    timit("PYTHON", python_func, [s1, s1_len, s2, s2_len, g, T, H, TR, TC, traceMat, s, method])

    if print_mat:
        print("H =\n", H)
        print("TR =\n", TR)
        print("TC =\n", TC)
        print("traceMat =\n", traceMat)


    # ------------------ cython -------------------

    ## IMPORTANT ! Adding prep steps

    # This step prepare inputs for cythonized call make sure it has correct data and dtypes
    drug2idx = {k: i for i, k in enumerate(s.keys())}
    s_df = pd.DataFrame(s, index=["a", "b", "c"])
    s_arr = np.ascontiguousarray(s_df.to_numpy(dtype=np.float64))  # matrix for cython
    s1_times = np.ascontiguousarray([float(t) for t, d in s1], dtype=np.float64)
    s2_times = np.ascontiguousarray([float(t) for t, d in s2], dtype=np.float64)
    s1_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s1], dtype=np.int32)
    s2_drugs = np.ascontiguousarray([drug2idx[d] for t, d in s2], dtype=np.int32)

    # Re-Initialise the 3 score matrices and the traceback matrix
    H = init_Hmat(s1_len, s2_len, g)
    TR = init_TRmat(s1, s1_len, s2, s2_len)
    TC = init_TCmat(s1, s1_len, s2, s2_len)
    traceMat = init_traceMat(s1_len, s2_len)

    # Set dtypes
    H        = np.ascontiguousarray(H, dtype=np.float64)
    TR       = np.ascontiguousarray(TR, dtype=np.float64)
    TC       = np.ascontiguousarray(TC, dtype=np.float64)
    traceMat = np.ascontiguousarray(traceMat, dtype=np.int32)
    s_arr    = np.ascontiguousarray(s_arr, dtype=np.float64)

    timit("CYTHON", cython_func, [s1_times, s1_drugs, s1_len,
        s2_times, s2_drugs, s2_len,
        g, T, H, TR, TC, traceMat,
        s_arr, method])

    if print_mat:
        print("H =\n", H)
        print("TR =\n", TR)
        print("TC =\n", TC)
        print("traceMat =\n", traceMat)

if __name__ == "__main__":

    print("Small test:")
    s1,s2,s = test()

    run_benchmark(s1,s2,s)

    print("Medium test:")
    s, s1,s2 =  generate(
            n_labels=6,
            seq_length=5,     # your default request
            n_times=3,        # three repetitions of s1
            noise_block_len=(18,100),
            seed=123
        )
    
    run_benchmark(s1,s2,s)

    
    print("Large test:")
    s, s1,s2 =  generate(
            n_labels=20,
            seq_length=30,     # your default request
            n_times=5,        # three repetitions of s1
            noise_block_len=(180,1000),
            seed=123
        )
    
    print(s.shape)
    print(len(s1), len(s1[1]))
    print(len(s2), len(s2[1]))

    
    run_benchmark(s1,s2,s)

    print("Huge test:")
    s, s1,s2 =  generate(
            n_labels=20,
            seq_length=30,     # your default request
            n_times=10,        # three repetitions of s1
            noise_block_len=(2000,10000),
            seed=123
        )
    
    print(s.shape)
    print(len(s1), len(s1[1]))
    print(len(s2), len(s2[1]))
    
    run_benchmark(s1,s2,s)