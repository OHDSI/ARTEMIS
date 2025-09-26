# cython: boundscheck=False, wraparound=False, nonecheck=True, cdivision=True, language_level=3

import numpy as np
cimport numpy as np
from libc.math cimport floor

def find_best_score(
    np.ndarray[np.float64_t, ndim=2] H,
    int s1_len,
    int s2_len,
    int mem,
    int verbose
):
    cdef:
        np.ndarray[np.float64_t, ndim=1] mem_score
        np.ndarray[np.int32_t, ndim=2] mem_index
        np.ndarray[np.float64_t, ndim=1] sorted_scores
        np.ndarray[np.int32_t, ndim=2] sorted_indices
        float max_score
        int max_idx, i, k, n
        int final_j, final_i
        float mem_min

    # Extract scores for the last column of H (s1_len column)
    mem_score = H[:, s1_len].copy()  # shape (s2_len+1,)

    # Create index matrix (s2_idx, s1_len)
    mem_index = np.empty((s2_len + 1, 2), dtype=np.int32)
    for i in range(s2_len + 1):
        mem_index[i, 0] = i
        mem_index[i, 1] = s1_len

    # Get max score and index
    max_idx = int(np.argmax(mem_score))
    max_score = float(mem_score[max_idx])
    final_j, final_i = mem_index[max_idx, 0], mem_index[max_idx, 1]
    final_index = (final_j, final_i)

    # Sort scores and indices by score
    sorted_idx = np.argsort(mem_score)
    sorted_scores = mem_score[sorted_idx]
    sorted_indices = mem_index[sorted_idx]

    # Memory logic
    if mem == -1:
        mem = max(1, int(floor(s2_len / s1_len)))
        mem_min = sorted_scores[-mem] * 0.9

        # Count how many meet the 90% threshold
        n = 0
        for i in range(s2_len + 1):
            if sorted_scores[i] >= mem_min:
                n = s2_len + 1 - i
                break

        mem_score = sorted_scores[-n:].copy()
        mem_index = sorted_indices[-n:].copy()

        if verbose == 2:
            print("Calculated mem:", mem)

    elif mem == 0:
        mem_score = np.zeros((0,), dtype=np.float64)
        mem_index = np.zeros((0, 2), dtype=np.int32)

    else:  # mem >= 1
        mem_min = sorted_scores[-mem] * 0.9

        # Count how many meet the 90% threshold
        n = 0
        for i in range(s2_len + 1):
            if sorted_scores[i] >= mem_min:
                n = s2_len + 1 - i

    return max_score, final_index, mem_index, mem_score

