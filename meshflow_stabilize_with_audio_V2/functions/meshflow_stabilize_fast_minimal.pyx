# cython: language_level=3

def jacobi_solve_fast(off_diag, on_diag, b, int num_iterations):
    """Minimal Jacobi solver - just Python loops compiled to C"""
    cdef int T = len(b)
    cdef int iter_i, t, s
    
    x = b.copy()
    
    for iter_i in range(num_iterations):
        x_new = b.copy()
        for t in range(T):
            s_sum = 0.0
            for s in range(T):
                if s != t:
                    s_sum = s_sum + off_diag[t, s] * x[s, 0]
            x_new[t, 0] = (b[t, 0] - s_sum) / on_diag[t]
            
            s_sum = 0.0
            for s in range(T):
                if s != t:
                    s_sum = s_sum + off_diag[t, s] * x[s, 1]
            x_new[t, 1] = (b[t, 1] - s_sum) / on_diag[t]
        x = x_new
    
    return x
