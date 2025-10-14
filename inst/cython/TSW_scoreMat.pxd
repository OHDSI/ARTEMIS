
import numpy as np
cimport numpy as np

cdef TSW_scoreMat(
    double[:] s1_time,
    int[:] s1_drugs,
    int s1_len,
    double[:] s2_time,
    int[:] s2_drugs,
    int s2_len,
    double g,
    double T,
    double[:, :] H,
    double[:, :] TR,
    double[:, :] TC,
    int[:, :] traceMat,
    double[:, :] s,
    str method
)