# cython: language_level=3
"""
Simplified Cython version - avoiding complex NumPy declarations
"""

import numpy as np


def compute_nearby_residual_velocities(
    early_features,
    late_features,
    H,
    int frame_width,
    int frame_height,
    int mesh_row_count,
    int mesh_col_count,
    int feature_ellipse_row_count,
    int feature_ellipse_col_count
):
    """Quick residual velocity computation"""
    # Simple Python loop - Cython will compile this to C
    cdef int n_features = len(early_features)
    cdef int i, vr, vc, top, bottom_excl, left, right_excl
    cdef float fx, fy, rvx, rvy, feature_row, feature_col, inside, half_w
    cdef float pred_x, pred_y, h_w, sqrt_inside
    
    cdef int mesh_rows = mesh_row_count + 1
    cdef int mesh_cols = mesh_col_count + 1
    
    x_lists = [[[] for _ in range(mesh_cols)] for _ in range(mesh_rows)]
    y_lists = [[[] for _ in range(mesh_cols)] for _ in range(mesh_rows)]
    
    if n_features == 0:
        return x_lists, y_lists
    
    # Homography transformation
    predicted_late = []
    for i in range(n_features):
        pred_x = H[0, 0] * early_features[i, 0, 0] + H[0, 1] * early_features[i, 0, 1] + H[0, 2]
        pred_y = H[1, 0] * early_features[i, 0, 0] + H[1, 1] * early_features[i, 0, 1] + H[1, 2]
        h_w = H[2, 0] * early_features[i, 0, 0] + H[2, 1] * early_features[i, 0, 1] + H[2, 2]
        
        if h_w > 1e-6:
            predicted_late.append([pred_x / h_w, pred_y / h_w])
        else:
            predicted_late.append([0, 0])
    
    # Residuals
    for i in range(n_features):
        rvx = late_features[i, 0, 0] - predicted_late[i][0]
        rvy = late_features[i, 0, 1] - predicted_late[i][1]
        fx = early_features[i, 0, 0]
        fy = early_features[i, 0, 1]
        
        feature_row = (fy / frame_height) * mesh_row_count
        feature_col = (fx / frame_width) * mesh_col_count
        
        top = max(0, <int>(feature_row - feature_ellipse_row_count / 2.0 + 0.5))
        bottom_excl = 1 + min(mesh_row_count, <int>(feature_row + feature_ellipse_row_count / 2.0))
        
        for vr in range(top, bottom_excl):
            inside = 0.25 - ((vr - feature_row) / feature_ellipse_row_count) ** 2
            if inside > 0:
                sqrt_inside = inside ** 0.5
                half_w = feature_ellipse_col_count * sqrt_inside
                left = max(0, <int>(feature_col - half_w + 0.5))
                right_excl = 1 + min(mesh_col_count, <int>(feature_col + half_w))
                
                for vc in range(left, right_excl):
                    x_lists[vr][vc].append(rvx)
                    y_lists[vr][vc].append(rvy)
    
    return x_lists, y_lists


def jacobi_solve_fast(off_diag, on_diag, b, int num_iterations):
    """Fast Jacobi solver"""
    cdef int T = len(b)
    cdef int iter_i, t, s
    cdef float sum_val
    
    x = np.array(b, dtype=np.float32)
    inv_diag = 1.0 / on_diag
    
    for iter_i in range(num_iterations):
        x_new = np.zeros_like(b)
        
        for t in range(T):
            sum_val = b[t, 0]
            for s in range(T):
                if s != t:
                    sum_val -= off_diag[t, s] * x[s, 0]
            x_new[t, 0] = sum_val * inv_diag[t]
            
            sum_val = b[t, 1]
            for s in range(T):
                if s != t:
                    sum_val -= off_diag[t, s] * x[s, 1]
            x_new[t, 1] = sum_val * inv_diag[t]
        
        x = x_new
    
    return x
