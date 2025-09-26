import pandas as pd
import numpy as np
import string
import random
from typing import Tuple, List

def generate(
    n_labels: int = 6,
    seq_length: int = 3,              # ← default as requested
    n_times: int = 3,                  # how many times to embed the s1 sequence in s2
    noise_block_len: Tuple[int,int] = (2, 5),   # min/max size of each noise block
    s_range: Tuple[float,float] = (-1.1, 2.1),
    seed: int = 42
):
    """
    Returns a sample for testing:
      s  : (n_labels x n_labels) similarity matrix DataFrame in [-1.1, 2.1], 2-dec, diag=1.0
      s1 : list[[ "1", label ]] of length = seq_length
      s2 : list[[ str(distance), label ]] = noise_block -> s1 -> noise_block -> s1 ... (n_times)
           distances are consecutive integers starting at 1
    """
    if n_labels < 1:
        raise ValueError("n_labels must be >= 1")
    if seq_length < 1:
        raise ValueError("seq_length must be >= 1")
    if n_times < 1:
        raise ValueError("n_times must be >= 1")
    if noise_block_len[0] < 0 or noise_block_len[1] < noise_block_len[0]:
        raise ValueError("noise_block_len must be a valid (min,max) with min>=0 and max>=min")

    random.seed(seed)
    np.random.seed(seed)

    # --- labels (ASCII) ---
    if n_labels <= 26:
        labels = list(string.ascii_lowercase[:n_labels])
    else:
        # extend beyond 'z' as aa, ab, ...
        base = list(string.ascii_lowercase)
        extra = []
        k = n_labels - 26
        i = 0
        while len(extra) < k:
            for a in base:
                for b in base:
                    extra.append(a + b)
                    if len(extra) == k:
                        break
                if len(extra) == k:
                    break
            i += 1
        labels = list(string.ascii_lowercase) + extra

    # --- similarity matrix s ---
    lo, hi = s_range
    s_values = np.round(np.random.uniform(lo, hi, size=(n_labels, n_labels)), 2)
    np.fill_diagonal(s_values, 1.0)
    s = pd.DataFrame(s_values, index=labels, columns=labels)

    # --- s1: fixed-length randomized sequence (with replacement) ---
    s1_seq: List[str] = [random.choice(labels) for _ in range(seq_length)]
    s1 = [[str(1), lbl] for lbl in s1_seq]

    # --- s2: (noise_block -> s1) repeated n_times; distances consecutive ---
    s2 = []
    d = 0
    for _ in range(n_times):
        # noise block
        nb_len = random.randint(noise_block_len[0], noise_block_len[1])
        for _ in range(nb_len):
            d += 1
            s2.append([str(d), random.choice(labels)])

        # full s1 block (shifted)
        for lbl in s1_seq:
            d += 1
            s2.append([str(d), lbl])

    return s, s1, s2


# --- Example run (seq_length=3 by default) ---
if __name__ == "__main__":
    s, s1, s2 = generate(
        n_labels=6,
        seq_length=5,     # your default request
        n_times=3,        # three repetitions of s1
        noise_block_len=(58,59),   # random integer between x, y ... 
        seed=123
    )
    print("Similarity matrix (s):")
    print(s)
    print("\nDistance-1 set (s1):", s1)
    print("\nDistance-varied set (s2):", s2)
