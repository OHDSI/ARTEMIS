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


cdef double score(
    double[:, :] s,
    int x, 
    int y
):
    """
    Look up the score for (x, y) in the scoring matrix/dict `s`.
    Returns a float (converted to double).
    """
    return float(s[x][y])


# ----------------------------
# Core Scoring Function
# Will be called with python headers
# python callable
# (entrypoint in main)
# ----------------------------
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
):
    """
    Cython-accelerated version with separated time and drug lists.
    Inputs:
        s1_time, s2_time : float or double arrays/lists
        s1_drugs, s2_drugs : lists of strings or comparable objects
        H, TR, TC, traceMat : Python nested lists (matrices)
    """
    cdef int i, j, k
    cdef double tp = 0.0
    cdef double tpx, tpy
    cdef double s2_time_i, s1_time_j
    cdef object score_match, Hup, Hmid, Hbot
    cdef int traceVal
    cdef double matVal

    i = 1
    while i < s2_len + 1:
        j = 1
        while j < s1_len + 1:
            s2_time_i = s2_time[i - 1]
            s1_time_j = s1_time[j - 1]

            # Dynamic re-ordering
            if i > 1 and i < s2_len:
                if min(s1_time_j, s2_time_i) == 0.0:
                    if s1_drugs[j - 1] == s2_drugs[i - 1]:
                        # Start of regimen case
                        if j == 1 and s2_time_i == 0.0:
                            k = i - 1
                            tmp = s2_drugs[i - 1]
                            s2_drugs[i - 1] = s2_drugs[k - 1]
                            s2_drugs[k - 1] = tmp
                            i -= 1
                            continue

                        # End of regimen case
                        elif j == s1_len and s2_time_i == 0.0:
                            k = i + 1
                            if s2_time[k - 1] == 0.0:
                                tmp = s2_drugs[i - 1]
                                s2_drugs[i - 1] = s2_drugs[k - 1]
                                s2_drugs[k - 1] = tmp
                                i -= 1
                                continue

            # Time penalty
            if i == 1 and j == 1:
                tp = 0.0
            else:
                tpx = s2_time_i + float(TR[i - 1][j - 1])
                tpy = s1_time_j + float(TC[i - 1][j - 1])
                tp = float(lossFunction(T, tpx, tpy, method, i, j))

            # Score
            score_match = score(s, s1_drugs[j - 1], s2_drugs[i - 1])

            # Candidate scores
            Hup = H[i - 1][j - 1] + score_match - tp
            Hmid = H[i - 1][j] - g
            Hbot = H[i][j - 1] - g

            # Select move
            H[i][j] = max([0, Hup, Hmid, Hbot])
            traceMat[i][j] = [0, Hup, Hmid, Hbot].index(H[i][j])

            traceVal = int(traceMat[i][j])
            matVal = float(H[i][j])

            # DIAGONAL
            if traceVal == 1:
                TR[i][j] = 0
                TC[i][j] = 0
            # HORIZONTAL
            elif traceVal == 2:
                TR[i][j] = TR[i - 1][j] + s2_time_i
                TC[i][j] = TC[i - 1][j]
            # VERTICAL
            elif traceVal == 3:
                TR[i][j] = TC[i][j - 1]
                TC[i][j] = TC[i][j - 1] + s1_time_j

            # Edge penalty
            if j == s1_len and i < s2_len:
                if s2_time[i] < s1_time[0]:
                    H[i][j] = max(
                        H[i][j]
                        - lossFunction(T, s2_time[i], s1_time[0], method, i, j),
                        0,
                    )

            j += 1
        i += 1

