# cython: boundscheck=False, wraparound=False, nonecheck=True, cdivision=True, language_level=3

import numpy as np
cimport numpy as np
from libc.math cimport fabs, fmax
from cpython.unicode cimport PyUnicode_AsUTF8AndSize

# ---- helper must be at top-level ----
cdef inline int count_trailing_gaps(str seq):
    cdef:
        const char* data
        Py_ssize_t length
        int i, count = 0

    data = PyUnicode_AsUTF8AndSize(seq, &length)
    if data == NULL:
        return 0  # safety fallback

    i = <int>length - 1
    while i >= 1:
        if data[i] == ord('_') and data[i-1] == ord('_'):
            count += 1
            i -= 2
            if i >= 0 and data[i] == ord(';'):
                i -= 1
        else:
            break
    return count


cdef aTSW (
    int[:, :] traceMat,
    double[:] s1_times,
    int[:] s1_drugs,
    int s1_len,
    double[:] s2_times,
    int[:] s2_drugs,
    int s2_len,
    np.ndarray[np.int32_t, ndim=2] mem_index,
    np.ndarray[np.float64_t, ndim=1] mem_score,
    np.ndarray[object, ndim=1] drug_names
):
    cdef:
        int n = mem_index.shape[0]
        int idx
        int max_j, max_i, i, j
        int totAligned
        int drug_id_1, drug_id_2
        float time_1, time_2
        int t1, t2
        str s1_aligned, s2_aligned, temp_s1_aligned, temp_s2_aligned
        int s_f_len, s1_end_gaps, s1_end, s2_end
        int s1_start, s2_start
        double adjustedS

    cdef object[:, :] results = np.empty((n, 10), dtype=object)

    for idx in range(n):
        max_j = mem_index[idx, 0]
        max_i = mem_index[idx, 1]
        i = s1_len
        j = s2_len
        totAligned = 0
        s1_aligned = ""
        s2_aligned = ""


        # ---- traceback loop ----
        while traceMat[max_j, max_i] > 0:
            if traceMat[max_j, max_i] == 1:
                time_1 = s1_times[max_i - 1]
                drug_id_1 = s1_drugs[max_i - 1]
                time_2 = s2_times[max_j - 1]
                drug_id_2 = s2_drugs[max_j - 1]
                t1 = <int>time_1
                t2 = <int>time_2
                temp_s1_aligned = f"{t1}.{drug_names[drug_id_1]}"
                temp_s2_aligned = f"{t2}.{drug_names[drug_id_2]}"
                max_i -= 1
                max_j -= 1
                i -= 1
                j -= 1
                totAligned += 1
            elif traceMat[max_j, max_i] == 3:
                time_1 = s1_times[max_i - 1]
                t1 = <int>time_1
                drug_id_1 = s1_drugs[max_i - 1]
                temp_s1_aligned = f"{t1}.{drug_names[drug_id_1]}"
                temp_s2_aligned = "__"
                max_i -= 1
                i -= 1
            elif traceMat[max_j, max_i] == 2:
                time_2 = s2_times[max_j - 1]
                t2 = <int>time_2
                drug_id_2 = s2_drugs[max_j - 1]
                temp_s1_aligned = "__"
                temp_s2_aligned = f"{t2}.{drug_names[drug_id_2]}"
                max_j -= 1
                j -= 1
            s1_aligned = f"{temp_s1_aligned};{s1_aligned}"
            s2_aligned = f"{temp_s2_aligned};{s2_aligned}"

        if max_i != 0 and max_j != 0:
            time_1 = s1_times[max_i - 1]
            drug_id_1 = s1_drugs[max_i - 1]
            time_2 = s2_times[max_j - 1]
            drug_id_2 = s2_drugs[max_j - 1]
            t1 = <int>time_1
            t2 = <int>time_2
            temp_s1_aligned = f"{t1}.{drug_names[drug_id_1]}"
            temp_s2_aligned = f"{t2}.{drug_names[drug_id_2]}"
            max_i -= 1
            max_j -= 1
            i -= 1
            j -= 1
            totAligned += 1
            s1_aligned = f"{temp_s1_aligned};{s1_aligned}"
            s2_aligned = f"{temp_s2_aligned};{s2_aligned}"

        # ---- post metrics ----
        s1_aligned_t = s1_aligned[:-1]
        s2_aligned_t = s2_aligned[:-1]

        s_f_len = max(s1_aligned.count('.'), s2_aligned.count('.'))

        s1_end_gaps = count_trailing_gaps(s1_aligned_t)
        
        s1_end = mem_index[idx, 1]
        
        s2_end = mem_index[idx, 0] - s1_end_gaps
        
        s1_start = max_i
        s2_start = max_j
        if (s1_start + 1) > 1:
            totAligned = totAligned + (s1_end - (s1_start + 1))     
            s_f_len = s_f_len + (s1_end - (s1_start + 1))

        adjustedS = mem_score[idx] / totAligned

        # ---- save row ----
        results[idx, 0] = s1_aligned_t       
        results[idx, 1] = s2_aligned_t       
        results[idx, 2] = mem_score[idx]     
        results[idx, 3] = adjustedS          
        results[idx, 4] = s1_start + 1       
        results[idx, 5] = s1_end             
        results[idx, 6] = s2_start + 1       
        results[idx, 7] = s2_end             
        results[idx, 8] = s_f_len            
        results[idx, 9] = totAligned         

    return np.asarray(results)
