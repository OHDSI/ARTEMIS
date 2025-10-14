# TSW_Package/TSW_helpers.pxd
# Cython header exposing helper matrix initialization functions

from cpython cimport bool
import numpy as np
cimport numpy as np

ctypedef np.float64_t DTYPE_t
ctypedef np.int32_t DTYPE_i

# Initialize H matrix
cdef init_Hmat(int s1_len, int s2_len)

# Initialize TR matrix
cdef init_TRmat(int s1_len, int s2_len)

# Initialize TC matrix
cdef init_TCmat(int s1_len, int s2_len)

# Initialize trace matrix
cdef init_traceMat(int s1_len, int s2_len)
