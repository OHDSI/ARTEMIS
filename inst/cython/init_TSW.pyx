import numpy as np
cimport numpy as np


cdef init_Hmat(int s1_len, int s2_len):
    cdef np.ndarray[DTYPE_t, ndim=2] H_np = np.zeros((s2_len + 1, s1_len + 1), dtype=np.float64)
    cdef double[:, :] H = H_np  
    return H_np 


cdef init_TRmat(int s1_len, int s2_len):
    cdef np.ndarray[DTYPE_t, ndim=2] TR_np = np.zeros((s2_len + 1, s1_len + 1), dtype=np.float64)
    cdef double[:, :] TR = TR_np  # memoryview for fast C-level access
    return TR_np  # return the numpy array to Python


cdef init_TCmat(int s1_len, int s2_len):
    cdef np.ndarray[DTYPE_t, ndim=2] TC_np = np.zeros((s2_len + 1, s1_len + 1), dtype=np.float64)
    cdef double[:, :] TC = TC_np
    return TC_np


cdef init_traceMat(int s1_len, int s2_len):
    cdef np.ndarray[DTYPE_i, ndim=2] traceMat_np = np.zeros((s2_len + 1, s1_len + 1), dtype=np.int32)
    cdef int[:, :] traceMat = traceMat_np
    return traceMat_np