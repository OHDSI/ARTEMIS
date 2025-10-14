import numpy as np
cimport numpy as np


cdef find_best_score(
    double[:, :] H,
    int s1_len,
    int s2_len,
    int mem,  # mem is often used as a control flow variable, keeping as 'int' is fine
    int verbose
)