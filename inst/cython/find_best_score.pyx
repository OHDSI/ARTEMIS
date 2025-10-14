# distutils: extra_compile_args=-O3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
import numpy as np
cimport numpy as np
import math


cdef find_best_score(
    double[:, :] H,
    int s1_len,
    int s2_len,
    int mem,  # mem is often used as a control flow variable, keeping as 'int' is fine
    int verbose
):
    """
    Cythonized version of find_best_score.
    Calculates best score and a list of potential alignment endpoints.
    """
    cdef np.ndarray[np.float64_t, ndim=1] mem_score
    cdef np.ndarray[np.float64_t, ndim=1] mem_score_sorted
    cdef np.ndarray[np.int32_t, ndim=2] mem_index
    cdef np.ndarray[np.int32_t, ndim=2] mem_index_sorted
    cdef np.ndarray[np.float64_t, ndim=1] mem_score_final
    cdef np.ndarray[np.int32_t, ndim=2] mem_index_final

    cdef double max_score
    cdef int max_idx, i
    cdef tuple max_index
    cdef double mem_min

    # 1. Get score and index arrays
    mem_score = np.asarray(H[:, s1_len].copy())

    mem_index = np.empty((s2_len + 1, 2), dtype=np.int32)
    
    for i in range(s2_len + 1):
        mem_index[i, 0] = i
        mem_index[i, 1] = s1_len


    # 2. Find max score
    max_idx = np.argmax(mem_score)
    max_score = mem_score[max_idx]
    max_index = (max_idx, s1_len)


    # 3. Sort arrays based on score
    sort_indices = mem_score.argsort()
    # Apply the sort indices to both arrays
    mem_score_sorted = mem_score[sort_indices]
    mem_index_sorted = mem_index[sort_indices]

    # 4. Filtering Logic
    if mem == -1:
        which_mem = max(1, math.floor(s2_len / s1_len))
        # Get the score of the N-th best alignment (using negative index on sorted array)
        mem_min = mem_score_sorted[-which_mem]
        
        # Create a boolean mask for filtering
        mask = mem_score_sorted >= mem_min * 0.9

        # Apply the mask to both arrays (these slices remain 1D/2D typed arrays)
        mem_score_final = mem_score_sorted[mask]
        mem_index_final = mem_index_sorted[mask]
        
        if verbose == 2:
            print("Calculated mem: ")
            print(mem)

    elif mem == 0:
        # Return empty 2D int array and 1D float array
        mem_index_final = np.empty((0, 2), dtype=np.int32)
        mem_score_final = np.empty((0,), dtype=np.float64)

    else: # mem >= 1
        mem_min = mem_score_sorted[-mem]
        
        mask = mem_score_sorted >= mem_min * 0.9
        
        mem_score_final = mem_score_sorted[mask]
        mem_index_final = mem_index_sorted[mask]


    # 5. Reverse the order (highest score first)
    # The arrays are currently sorted ascending by score; reverse to get descending.
    mem_score_final = mem_score_final[::-1]
    mem_index_final = mem_index_final[::-1]

    return mem_index_final, mem_score_final
