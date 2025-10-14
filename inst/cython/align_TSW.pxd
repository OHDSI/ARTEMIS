# cython: boundscheck=False, wraparound=False, nonecheck=True, cdivision=True, language_level=3

import numpy as np
cimport numpy as np


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
)