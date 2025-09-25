import time
def timeit(tag, func, data):
    start = time.perf_counter()
    func(*data)
    end = time.perf_counter()
    print(f"{tag} - Execution time: {end - start:.6f} seconds")
