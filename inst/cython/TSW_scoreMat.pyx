# cython: boundscheck=False, wraparound=False, nonecheck=True, cdivision=True, language_level=3
import numpy as np
cimport numpy as np
from libc.math cimport fabs, fmax, pow, log, cosh

# ----------------------------
# Helper: Loss Function
# Fully compiled to C so cdef
# ----------------------------
cdef inline double lossFunction(double T, double t1, double t2, str method, int i, int j):
    cdef double absDiff = fabs(t1 - t2)
    cdef double maxT = fmax(t1, t2)
    cdef double tp = 0.0

    if maxT == 0.0:
        maxT = 1e-24

    if j == 1:
        return 1e-24

    if method == "PropDiff":
        if t1 == 0.0 or t2 == 0.0:
            tp = T * absDiff / (maxT + 1)
        else:
            tp = T * absDiff / maxT
    elif method == "AbsDiff":
        tp = T * absDiff
    elif method == "Quadratic":
        tp = T * pow(absDiff, 2)
    elif method == "PropQuadratic":
        tp = (T * pow(absDiff, 2)) / maxT
    elif method == "LogCosh":
        tp = cosh(log(absDiff))
    else:
        tp = 0.0
    return tp


# ----------------------------
# Core Scoring Function
# Will be called with python headers
# python callable
# (entrypoint in main)
# ----------------------------
cpdef TSW_scoreMat(
    np.ndarray[np.float64_t, ndim=1] s1_times,
    np.ndarray[np.int32_t,  ndim=1] s1_drugs,
    int s1_len,
    np.ndarray[np.float64_t, ndim=1] s2_times,
    np.ndarray[np.int32_t,  ndim=1] s2_drugs,
    int s2_len,
    double g,
    double T,
    np.ndarray[np.float64_t, ndim=2] H,
    np.ndarray[np.float64_t, ndim=2] TR,
    np.ndarray[np.float64_t, ndim=2] TC,
    np.ndarray[np.int32_t,  ndim=2] traceMat,
    np.ndarray[np.float64_t, ndim=2] s,
    str method
):
    cdef int i, j, traceVal
    cdef double tp, tpx, tpy, score_match, Hup, Hmid, Hbot, penalty

    for i in range(1, s2_len + 1):
        for j in range(1, s1_len + 1):

            if 1 < i < s2_len and s1_times[j-1] == 0.0 and s2_times[i-1] == 0.0:
                if s1_drugs[j-1] == s2_drugs[i-1]:
                    if j == 1 and s2_times[i-1] == 0.0:
                        continue
                    elif j == s1_len and s2_times[i-1] == 0.0:
                        if s2_times[i] == 0.0:
                            continue

            if i == 1 and j == 1:
                tp = 0.0
            else:
                tpx = s2_times[i - 1] + TR[i - 1, j - 1]
                tpy = s1_times[j - 1] + TC[i - 1, j - 1]
                tp = lossFunction(T, tpx, tpy, method, i, j)

            score_match = s[s1_drugs[j - 1], s2_drugs[i - 1]]

            Hup = H[i - 1, j - 1] + score_match - tp
            Hmid = H[i - 1, j] - g
            Hbot = H[i, j - 1] - g

            H[i, j] = fmax(0.0, fmax(Hup, fmax(Hmid, Hbot)))
            traceVal = [0.0, Hup, Hmid, Hbot].index(H[i, j])
            traceMat[i, j] = traceVal

            if traceVal == 1:
                TR[i, j] = 0.0
                TC[i, j] = 0.0
            elif traceVal == 2:
                TR[i, j] = TR[i - 1, j] + s2_times[i - 1]
                TC[i, j] = TC[i - 1, j]
            elif traceVal == 3:
                TR[i, j] = TC[i, j - 1]
                TC[i, j] = TC[i, j - 1] + s1_times[j - 1]

            if j == s1_len and i < s2_len:
                if s2_times[i] < s1_times[0]:
                    penalty = lossFunction(T, s2_times[i], s1_times[0], method, i, j)
                    H[i, j] = fmax(H[i, j] - penalty, 0.0)
