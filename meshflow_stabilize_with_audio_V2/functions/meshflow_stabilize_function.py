import cv2
import math
import numpy as np
import statistics
import tqdm
import subprocess
from pathlib import Path


class MeshFlowStabilizer:
    ADAPTIVE_WEIGHTS_DEFINITION_ORIGINAL = 0
    ADAPTIVE_WEIGHTS_DEFINITION_FLIPPED = 1
    ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_HIGH = 2
    ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_LOW = 3

    ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_HIGH_VALUE = 100
    ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_LOW_VALUE = 1

    def __init__(
        self,
        mesh_row_count=16,
        mesh_col_count=16,
        mesh_outlier_subframe_row_count=4,
        mesh_outlier_subframe_col_count=4,
        feature_ellipse_row_count=10,
        feature_ellipse_col_count=10,
        homography_min_number_corresponding_features=4,
        temporal_smoothing_radius=10,
        optimization_num_iterations=80,
        color_outside_image_area_bgr=(0, 0, 255),
        visualize=False,
        warp_downscale=0.5
    ):
        self.mesh_col_count = mesh_col_count
        self.mesh_row_count = mesh_row_count
        self.mesh_outlier_subframe_row_count = mesh_outlier_subframe_row_count
        self.mesh_outlier_subframe_col_count = mesh_outlier_subframe_col_count
        self.feature_ellipse_row_count = feature_ellipse_row_count
        self.feature_ellipse_col_count = feature_ellipse_col_count
        self.homography_min_number_corresponding_features = homography_min_number_corresponding_features
        self.temporal_smoothing_radius = temporal_smoothing_radius
        self.optimization_num_iterations = optimization_num_iterations
        self.color_outside_image_area_bgr = color_outside_image_area_bgr
        self.visualize = visualize
        self.warp_downscale = warp_downscale
        self.feature_detector = cv2.FastFeatureDetector_create()

    # =========================
    # Public API (方案1入口)
    # =========================
    def stabilize_segment_only(
        self,
        input_path,
        output_path,
        adaptive_weights_definition=ADAPTIVE_WEIGHTS_DEFINITION_ORIGINAL,
        # ---- 方案1：晃動段偵測參數 ----
        AUTO_SHAKE_SEGMENT=True,
        SHAKE_SMOOTH_WIN=7,          # score 平滑視窗(odd)
        SHAKE_THRESH_K=3.0,          # threshold = median + K * MAD(robust)
        SHAKE_PAD_FRAMES=10,         # 晃動段前後多抓幾幀（避免邊界抖動）
        SHAKE_MIN_SEG_LEN=12,        # 最短晃動段（太短就當沒必要）
        # ---- 若不自動，手動指定 ----
        MANUAL_START=None,
        MANUAL_END=None,
    ):
        frames, num_frames, fps = self._get_unstabilized_frames_and_video_features(input_path)
        Hh, Ww = frames[0].shape[:2]

        # 先算全片的 unstab disp + homography（這步相對 warping 便宜，且可用來偵測晃動段）
        unstab_disp, homographies = self._get_unstabilized_vertex_displacements_and_homographies(num_frames, frames)

        # 1) 找出「晃動段」
        if AUTO_SHAKE_SEGMENT:
            scores = self._compute_shake_scores(homographies, Ww, Hh)
            scores_s = self._smooth_1d(scores, win=SHAKE_SMOOTH_WIN)

            seg = self._pick_shake_segment(
                scores_s,
                pad=SHAKE_PAD_FRAMES,
                k=SHAKE_THRESH_K,
                min_len=SHAKE_MIN_SEG_LEN,
            )

            if seg is None:
                # 沒偵測到明顯晃動：直接全片原樣輸出（仍保音訊 copy）
                self._write_video_and_copy_audio(input_path, output_path, fps, frames)
                return {
                    "mode": "no_shake_detected_copy_only",
                    "segment": None,
                    "output": str(output_path),
                }

            start, end = seg
        else:
            if MANUAL_START is None or MANUAL_END is None:
                raise ValueError("AUTO_SHAKE_SEGMENT=False 時，需提供 MANUAL_START / MANUAL_END")
            start = int(max(0, MANUAL_START))
            end = int(min(num_frames - 1, MANUAL_END))
            if end <= start:
                raise ValueError("MANUAL_END must be > MANUAL_START")

        # 2) 只對 [start, end] 做 MeshFlow
        sub_frames = frames[start : end + 1]

        # slice unstab disp 並做 baseline 置零，確保子序列從 0 開始
        sub_unstab = unstab_disp[start : end + 1].copy()
        sub_unstab -= sub_unstab[0]

        # slice homographies：最後一幀設 identity（子序列最後沒有下一幀）
        sub_H = homographies[start : end + 1].copy()
        sub_H[-1] = np.identity(3, dtype=np.float32)

        sub_num = len(sub_frames)

        # stabilized displacements（只在子段）
        sub_stab = self._get_stabilized_vertex_displacements(
            sub_num,
            sub_frames,
            adaptive_weights_definition,
            sub_unstab,
            sub_H,
        )

        # warp 只做子段
        sub_stabilized_uncropped, crop_boundaries = self._get_stabilized_frames_and_crop_boundaries(
            sub_num,
            sub_frames,
            sub_unstab,
            sub_stab,
        )

        # 3) 組回全片（uncropped），把晃動段替換成 stabilized_uncropped
        merged_uncropped = list(frames)  # shallow copy ok (frames are numpy arrays)
        merged_uncropped[start : end + 1] = sub_stabilized_uncropped

        # 4) 用同一組 crop_boundaries 對全片做 crop+resize（便宜，且避免視野/大小跳動）
        merged_cropped = self._crop_frames(merged_uncropped, crop_boundaries)

        # 5) 寫檔：video encode + audio copy
        self._write_video_and_copy_audio(input_path, output_path, fps, merged_cropped)

        if self.visualize:
            self._display_unstablilized_and_cropped_video_loop(num_frames, fps, frames, merged_cropped)

        return {
            "mode": "segment_meshflow",
            "segment": (start, end),
            "crop_boundaries": crop_boundaries,
            "output": str(output_path),
        }

    # =========================
    # IO
    # =========================
    def _get_unstabilized_frames_and_video_features(self, input_path):
        cap = cv2.VideoCapture(input_path)
        if not cap.isOpened():
            raise IOError(f"Cannot open video: {input_path}")
        num_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = float(cap.get(cv2.CAP_PROP_FPS))

        frames = []
        with tqdm.trange(num_frames) as t:
            t.set_description(f"Reading video from <{input_path}>")
            for i in t:
                ok, frame = cap.read()
                if not ok or frame is None:
                    raise IOError(f"Video missing frame {i}/{num_frames}")
                frames.append(frame)
        cap.release()
        return frames, num_frames, fps

    # =========================
    # Shake segment detection (方案1核心)
    # =========================
    def _compute_shake_scores(self, homographies, W, H):
        """
        先算 raw motion，再轉成『高通 shake energy』，用來抓突然變大的晃動段。
        """
        alpha = 0.7
        raw = np.zeros((len(homographies),), dtype=np.float32)

        for i, M in enumerate(homographies):
            if M is None:
                continue
            M = M.astype(np.float32)
            tx = float(M[0, 2]) / max(W, 1)
            ty = float(M[1, 2]) / max(H, 1)
            trans = math.sqrt(tx * tx + ty * ty)

            A = M.copy()
            A[2] = [0, 0, 1]
            d = A - np.eye(3, dtype=np.float32)
            aff = float(np.sqrt(np.sum(d[:2, :2] * d[:2, :2])))

            raw[i] = trans + alpha * aff

        if len(raw) >= 2:
            raw[-1] = raw[-2]

        # 高通：raw - median_filter(raw)
        base = self._smooth_1d(raw, win=9)         # baseline（低頻）
        hp = np.abs(raw - base)                    # 高頻能量（抖動感）

        # 再平滑一下避免零碎
        hp_s = self._smooth_1d(hp, win=7)
        return hp_s

    def _smooth_1d(self, x, win=7):
        win = int(win)
        if win < 3:
            return x
        if win % 2 == 0:
            win += 1
        pad = win // 2
        xp = np.pad(x, (pad, pad), mode="edge")
        out = np.empty_like(x)
        for i in range(len(x)):
            out[i] = np.median(xp[i : i + win])
        return out

    def _pick_shake_segment(self, scores, pad=10, k=4.0, min_len=12):
        """
        用高通後 scores（多數幀會接近 0），robust threshold 抓連續區段。
        threshold = median + k * MAD
        """
        s = scores.astype(np.float32)
        med = float(np.median(s))
        mad = float(np.median(np.abs(s - med))) + 1e-9
        thr = med + k * mad

        mask = s > thr
        if not np.any(mask):
            return None

        # 找所有連續區段，取「最長」那段（避免零碎觸發）
        idx = np.where(mask)[0]
        segs = []
        start = idx[0]
        prev = idx[0]
        for v in idx[1:]:
            if v == prev + 1:
                prev = v
            else:
                segs.append((start, prev))
                start = v
                prev = v
        segs.append((start, prev))

        # 取最長段
        segs.sort(key=lambda ab: (ab[1] - ab[0] + 1), reverse=True)
        start, end = segs[0]

        start = max(0, start - int(pad))
        end = min(len(s) - 1, end + int(pad))

        if (end - start + 1) < int(min_len):
            return None
        return start, end

    # =========================
    # Motion estimation
    # =========================
    def _get_unstabilized_vertex_displacements_and_homographies(self, num_frames, frames):
        disp = np.empty((num_frames, self.mesh_row_count + 1, self.mesh_col_count + 1, 2), dtype=np.float32)
        disp[0].fill(0)

        homographies = np.empty((num_frames, 3, 3), dtype=np.float32)
        homographies[-1] = np.identity(3, dtype=np.float32)

        with tqdm.trange(num_frames - 1) as t:
            t.set_description("Computing unstabilized mesh displacements")
            for idx in t:
                f0, f1 = frames[idx], frames[idx + 1]
                vel, H = self._get_unstabilized_vertex_velocities(f0, f1)
                if H is None:
                    H = np.identity(3, dtype=np.float32)
                disp[idx + 1] = disp[idx] + vel
                homographies[idx] = H
        return disp, homographies

    def _get_unstabilized_vertex_velocities(self, early_frame, late_frame):
        early_features, late_features, H = self._get_matched_features_and_homography(early_frame, late_frame)
        if H is None:
            H = np.identity(3, dtype=np.float32)
        else:
            H = H.astype(np.float32)

        h, w = early_frame.shape[:2]
        vertex_xy = self._get_vertex_x_y(w, h)

        global_vel = cv2.perspectiveTransform(vertex_xy, H) - vertex_xy
        global_vel = global_vel.reshape((self.mesh_row_count + 1, self.mesh_col_count + 1, 2))
        gvx = global_vel[:, :, 0]
        gvy = global_vel[:, :, 1]

        resx_lists, resy_lists = self._get_vertex_nearby_feature_residual_velocities(w, h, early_features, late_features, H)

        rvx = np.array([[statistics.median(xs) if xs else 0 for xs in row] for row in resx_lists], dtype=np.float32)
        rvy = np.array([[statistics.median(ys) if ys else 0 for ys in row] for row in resy_lists], dtype=np.float32)

        vx = (gvx + rvx).astype(np.float32)
        vy = (gvy + rvy).astype(np.float32)

        vx = cv2.medianBlur(vx, 3)
        vy = cv2.medianBlur(vy, 3)

        return np.dstack((vx, vy)).astype(np.float32), H

    def _get_vertex_nearby_feature_residual_velocities(self, frame_width, frame_height, early_features, late_features, H):
        x_lists = [[[] for _ in range(self.mesh_col_count + 1)] for _ in range(self.mesh_row_count + 1)]
        y_lists = [[[] for _ in range(self.mesh_col_count + 1)] for _ in range(self.mesh_row_count + 1)]

        if early_features is None:
            return x_lists, y_lists

        predicted_late = cv2.perspectiveTransform(early_features, H)
        residual = late_features - predicted_late
        pos_and_vel = np.c_[early_features, residual]  # (N,1,4)

        for item in pos_and_vel:
            fx, fy, rvx, rvy = item[0]
            feature_row = (fy / frame_height) * self.mesh_row_count
            feature_col = (fx / frame_width) * self.mesh_col_count

            top = max(0, math.ceil(feature_row - self.feature_ellipse_row_count / 2))
            bottom_excl = 1 + min(self.mesh_row_count, math.floor(feature_row + self.feature_ellipse_row_count / 2))

            for vr in range(top, bottom_excl):
                inside = (1 / 4) - ((vr - feature_row) / self.feature_ellipse_row_count) ** 2
                if inside <= 0:
                    continue
                half_w = self.feature_ellipse_col_count * math.sqrt(inside)
                left = max(0, math.ceil(feature_col - half_w))
                right_excl = 1 + min(self.mesh_col_count, math.floor(feature_col + half_w))

                for vc in range(left, right_excl):
                    x_lists[vr][vc].append(float(rvx))
                    y_lists[vr][vc].append(float(rvy))
        return x_lists, y_lists

    def _get_matched_features_and_homography(self, early_frame, late_frame):
        h, w = early_frame.shape[:2]
        sub_w = math.ceil(w / self.mesh_outlier_subframe_col_count)
        sub_h = math.ceil(h / self.mesh_outlier_subframe_row_count)

        early_list = []
        late_list = []

        for lx in range(0, w, sub_w):
            for ty in range(0, h, sub_h):
                e_sub = early_frame[ty : ty + sub_h, lx : lx + sub_w]
                l_sub = late_frame[ty : ty + sub_h, lx : lx + sub_w]
                offset = [lx, ty]
                ef, lf = self._get_features_in_subframe(e_sub, l_sub, offset)
                if ef is not None and lf is not None and len(ef) > 0:
                    early_list.append(ef)
                    late_list.append(lf)

        if len(early_list) == 0 or len(late_list) == 0:
            return None, None, None

        early_features = np.concatenate(early_list, axis=0)
        late_features = np.concatenate(late_list, axis=0)

        if len(early_features) < self.homography_min_number_corresponding_features:
            return None, None, None

        Hm, _ = cv2.findHomography(early_features, late_features)
        return early_features, late_features, Hm

    def _get_features_in_subframe(self, early_subframe, late_subframe, offset):
        ef_all, lf_all = self._get_all_matched_features_between_subframes(early_subframe, late_subframe)
        if ef_all is None:
            return None, None

        _, mask = cv2.findHomography(ef_all, lf_all, method=cv2.RANSAC)
        if mask is None:
            return None, None

        inlier = mask.flatten().astype(bool)
        ef = ef_all[inlier]
        lf = lf_all[inlier]

        if len(ef) < self.homography_min_number_corresponding_features:
            return None, None

        return ef + offset, lf + offset

    def _get_all_matched_features_between_subframes(self, early_subframe, late_subframe):
        e = cv2.cvtColor(early_subframe, cv2.COLOR_BGR2GRAY) if early_subframe.ndim == 3 else early_subframe
        l = cv2.cvtColor(late_subframe, cv2.COLOR_BGR2GRAY) if late_subframe.ndim == 3 else late_subframe

        kps = self.feature_detector.detect(e)
        if kps is None or len(kps) < self.homography_min_number_corresponding_features:
            return None, None

        e_pts = np.float32(cv2.KeyPoint_convert(kps)[:, np.newaxis, :])
        l_pts, st, _ = cv2.calcOpticalFlowPyrLK(e, l, e_pts, None)

        if st is None:
            return None, None

        good = st.flatten().astype(bool)
        ef = e_pts[good]
        lf = l_pts[good]

        if len(ef) < self.homography_min_number_corresponding_features:
            return None, None

        return ef, lf

    # =========================
    # Temporal smoothing (Jacobi)
    # =========================
    def _get_stabilized_vertex_displacements(self, num_frames, frames, adaptive_def, unstab_disp, homographies):
        h, w = frames[0].shape[:2]
        off_diag, on_diag = self._get_jacobi_method_input(num_frames, w, h, adaptive_def, homographies)

        unstab_by_coord = np.moveaxis(unstab_disp, 0, 2)  # (R,C,T,2)
        stab_by_coord = np.empty_like(unstab_by_coord)

        total_vertices = (self.mesh_row_count + 1) * (self.mesh_col_count + 1)
        with tqdm.trange(total_vertices) as t:
            t.set_description("Computing stabilized mesh displacements (segment)")
            for idx in t:
                r = idx // (self.mesh_col_count + 1)
                c = idx % (self.mesh_col_count + 1)
                x0 = unstab_by_coord[r, c]  # (T,2)
                x = self._get_jacobi_method_output(off_diag, on_diag, x0, x0)
                stab_by_coord[r, c] = x

        return np.moveaxis(stab_by_coord, 2, 0)  # (T,R,C,2)

    def _get_jacobi_method_input(self, num_frames, frame_width, frame_height, adaptive_def, homographies):
        ri, ci = np.indices((num_frames, num_frames))
        w_tr = np.exp(-np.square((3 / self.temporal_smoothing_radius) * (ri - ci))).astype(np.float32)

        lam = self._get_adaptive_weights(num_frames, frame_width, frame_height, adaptive_def, homographies)
        combined = (np.diag(lam) @ w_tr).astype(np.float32)

        off_diag = (-2 * combined).astype(np.float32)
        on_diag = (1 + 2 * np.sum(combined, axis=1)).astype(np.float32)

        mask = np.zeros_like(off_diag, dtype=np.float32)
        for k in range(-self.temporal_smoothing_radius, self.temporal_smoothing_radius + 1):
            mask += np.diag(np.ones(num_frames - abs(k), dtype=np.float32), k)
        off_diag = np.where(mask > 0, off_diag, 0.0).astype(np.float32)

        return off_diag, on_diag

    def _get_adaptive_weights(self, num_frames, frame_width, frame_height, adaptive_def, homographies):
        if adaptive_def in (self.ADAPTIVE_WEIGHTS_DEFINITION_ORIGINAL, self.ADAPTIVE_WEIGHTS_DEFINITION_FLIPPED):
            Hs = homographies.copy().astype(np.float32)
            Hs[:, 2, :] = [0, 0, 1]

            lam = np.empty((num_frames,), dtype=np.float32)
            for t in range(num_frames):
                H = Hs[t]
                try:
                    eig = np.sort(np.abs(np.linalg.eigvals(H)))
                    te = math.sqrt((H[0, 2] / frame_width) ** 2 + (H[1, 2] / frame_height) ** 2)
                    ac = float(eig[-2] / eig[-1]) if eig[-1] != 0 else 1.0
                    c1 = -1.93 * te + 0.95
                    if adaptive_def == self.ADAPTIVE_WEIGHTS_DEFINITION_ORIGINAL:
                        c2 = 5.83 * ac + 4.88
                    else:
                        c2 = 5.83 * ac - 4.88
                    lam[t] = max(min(c1, c2), 0.0)
                except Exception:
                    lam[t] = 0.0
            if num_frames >= 2:
                lam[-1] = lam[-2]
            return lam

        if adaptive_def == self.ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_HIGH:
            return np.full((num_frames,), self.ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_HIGH_VALUE, dtype=np.float32)
        return np.full((num_frames,), self.ADAPTIVE_WEIGHTS_DEFINITION_CONSTANT_LOW_VALUE, dtype=np.float32)

    def _get_jacobi_method_output(self, off_diag, on_diag, x_start, b):
        x = x_start.copy()
        invD = np.diag(np.reciprocal(on_diag)).astype(np.float32)
        for _ in range(self.optimization_num_iterations):
            x = invD @ (b - off_diag @ x)
        return x.astype(np.float32)

    # =========================
    # Warping & cropping
    # =========================
    def _get_vertex_x_y(self, frame_width, frame_height):
        return np.array(
            [
                [[math.ceil((frame_width - 1) * (col / self.mesh_col_count)),
                  math.ceil((frame_height - 1) * (row / self.mesh_row_count))]]
                for row in range(self.mesh_row_count + 1)
                for col in range(self.mesh_col_count + 1)
            ],
            dtype=np.float32,
        )

    def _get_stabilized_frames_and_crop_boundaries(self, num_frames, frames, unstab_disp, stab_disp):
        h, w = frames[0].shape[:2]

        unstab_vertex_xy = self._get_vertex_x_y(w, h)
        unstab_rc_xy = unstab_vertex_xy.reshape((self.mesh_row_count + 1, self.mesh_col_count + 1, 2))

        motion = (stab_disp - unstab_disp).reshape((num_frames, -1, 1, 2)).astype(np.float32)

        map_x_template = np.full((h, w), w + 1, dtype=np.float32)
        map_y_template = np.full((h, w), h + 1, dtype=np.float32)

        grid_xy = np.swapaxes(np.indices((w, h), dtype=np.float32), 0, 2)  # (h,w,2) (x,y)
        grid_xy_flat = grid_xy.reshape((-1, 1, 2))

        left_crop = np.full(num_frames, 0, dtype=np.int32)
        right_crop = np.full(num_frames, w - 1, dtype=np.int32)
        top_crop = np.full(num_frames, 0, dtype=np.int32)
        bottom_crop = np.full(num_frames, h - 1, dtype=np.int32)

        stabilized_frames = []
        with tqdm.trange(num_frames) as t:
            t.set_description("Warping frames (segment only)")
            for fi in t:
                frame = frames[fi]
                map_x = map_x_template.copy()
                map_y = map_y_template.copy()

                stab_vertex_xy = unstab_vertex_xy + motion[fi]
                stab_rc_xy = stab_vertex_xy.reshape((self.mesh_row_count + 1, self.mesh_col_count + 1, 2))

                for r in range(self.mesh_row_count):
                    for c in range(self.mesh_col_count):
                        unstab_cell = unstab_rc_xy[r : r + 2, c : c + 2].reshape(-1, 2)
                        stab_cell = stab_rc_xy[r : r + 2, c : c + 2].reshape(-1, 2)

                        H_us, _ = cv2.findHomography(unstab_cell, stab_cell)
                        H_su, _ = cv2.findHomography(stab_cell, unstab_cell)
                        if H_us is None or H_su is None:
                            continue

                        xs = unstab_cell[:, 0]
                        ys = unstab_cell[:, 1]
                        lx, rx = int(math.floor(xs.min())), int(math.ceil(xs.max()))
                        ty, by = int(math.floor(ys.min())), int(math.ceil(ys.max()))
                        lx = max(0, min(w - 1, lx))
                        rx = max(0, min(w - 1, rx))
                        ty = max(0, min(h - 1, ty))
                        by = max(0, min(h - 1, by))

                        mask = np.zeros((h, w), dtype=np.uint8)
                        mask[ty : by + 1, lx : rx + 1] = 255
                        stab_mask = cv2.warpPerspective(mask, H_us, (w, h), flags=cv2.INTER_NEAREST)
                        stab_mask = (stab_mask > 127)

                        cell_unstab_xy = cv2.perspectiveTransform(grid_xy_flat, H_su).reshape((h, w, 2))
                        cell_map_x = cell_unstab_xy[:, :, 0]
                        cell_map_y = cell_unstab_xy[:, :, 1]

                        map_x = np.where(stab_mask, cell_map_x, map_x)
                        map_y = np.where(stab_mask, cell_map_y, map_y)

                stabilized = cv2.remap(
                    frame,
                    map_x.reshape((h, w, 1)),
                    map_y.reshape((h, w, 1)),
                    interpolation=cv2.INTER_LINEAR,
                    borderValue=self.color_outside_image_area_bgr,
                )

                # crop boundaries (原本方法 + fallback bbox)
                xs_left = np.where(np.abs(map_x - 0) < 1)[1]
                if xs_left.size > 0:
                    left_crop[fi] = int(np.max(xs_left))
                xs_right = np.where(np.abs(map_x - (w - 1)) < 1)[1]
                if xs_right.size > 0:
                    right_crop[fi] = int(np.min(xs_right))
                ys_top = np.where(np.abs(map_y - 0) < 1)[0]
                if ys_top.size > 0:
                    top_crop[fi] = int(np.max(ys_top))
                ys_bottom = np.where(np.abs(map_y - (h - 1)) < 1)[0]
                if ys_bottom.size > 0:
                    bottom_crop[fi] = int(np.min(ys_bottom))

                valid = (map_x >= 0) & (map_x <= w - 1) & (map_y >= 0) & (map_y <= h - 1)
                if np.any(valid):
                    ys, xs = np.where(valid)
                    left_crop[fi] = max(left_crop[fi], int(xs.min()))
                    right_crop[fi] = min(right_crop[fi], int(xs.max()))
                    top_crop[fi] = max(top_crop[fi], int(ys.min()))
                    bottom_crop[fi] = min(bottom_crop[fi], int(ys.max()))

                stabilized_frames.append(stabilized)

        left = int(np.max(left_crop))
        right = int(np.min(right_crop))
        top = int(np.max(top_crop))
        bottom = int(np.min(bottom_crop))

        left = max(0, min(w - 2, left))
        right = max(left + 1, min(w - 1, right))
        top = max(0, min(h - 2, top))
        bottom = max(top + 1, min(h - 1, bottom))

        return stabilized_frames, (left, top, right, bottom)

    def _crop_frames(self, frames, crop_boundaries):
        h, w = frames[0].shape[:2]
        left, top, right, bottom = crop_boundaries

        uncropped_aspect = w / h
        cropped_aspect = (right + 1 - left) / (bottom + 1 - top)

        if cropped_aspect >= uncropped_aspect:
            scale = h / (bottom + 1 - top)
        else:
            scale = w / (right + 1 - left)

        out = []
        for f in frames:
            roi = f[top : bottom + 1, left : right + 1]
            out.append(cv2.resize(roi, (w, h), fx=scale, fy=scale))
        return out

    # =========================
    # Output: video + audio copy
    # =========================
    def _write_video_and_copy_audio(self, input_path, output_path, fps, frames_bgr):
        """
        1) OpenCV 寫 temp AVI（無音訊, MJPG/XVID）
        2) ffmpeg: temp video encode h264 + 原音訊 copy -> mp4
        """
        in_path = Path(input_path)
        out_path = Path(output_path)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        if out_path.suffix.lower() != ".mp4":
            raise ValueError("output_path must be .mp4 (per your requirement)")

        temp_avi = out_path.with_suffix(".tmp_video_only.avi")

        h, w = frames_bgr[0].shape[:2]
        fps_use = float(fps) if fps and fps > 1e-6 else 30.0

        fourcc = cv2.VideoWriter_fourcc(*"MJPG")
        writer = cv2.VideoWriter(str(temp_avi), fourcc, fps_use, (w, h))
        if not writer.isOpened():
            fourcc2 = cv2.VideoWriter_fourcc(*"XVID")
            writer = cv2.VideoWriter(str(temp_avi), fourcc2, fps_use, (w, h))
            if not writer.isOpened():
                raise IOError(f"OpenCV VideoWriter failed for temp AVI: {temp_avi}")

        with tqdm.trange(len(frames_bgr)) as t:
            t.set_description(f"Writing temp video (no audio) to <{temp_avi}>")
            for i in t:
                writer.write(frames_bgr[i])
        writer.release()

        cmd_with_audio = [
            "ffmpeg", "-y",
            "-i", str(temp_avi),
            "-i", str(in_path),
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
            "-c:a", "copy",            # ✅ 音訊不變
            "-shortest",
            str(out_path),
        ]
        cmd_no_audio = [
            "ffmpeg", "-y",
            "-i", str(temp_avi),
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
            "-an",
            str(out_path),
        ]

        try:
            p = subprocess.run(cmd_with_audio, capture_output=True, text=True)
            if p.returncode != 0:
                # 原片沒音訊時
                p2 = subprocess.run(cmd_no_audio, capture_output=True, text=True)
                if p2.returncode != 0:
                    raise RuntimeError(
                        "ffmpeg failed.\n"
                        f"[with audio stderr]\n{p.stderr}\n\n"
                        f"[no audio stderr]\n{p2.stderr}"
                    )
        finally:
            try:
                if temp_avi.exists():
                    temp_avi.unlink()
            except Exception:
                pass

    # =========================
    # Visualize
    # =========================
    def _display_unstablilized_and_cropped_video_loop(self, num_frames, fps, unstabilized_frames, cropped_frames):
        ms = int(1000 / max(fps, 1e-6))
        while True:
            for i in range(num_frames):
                show = np.vstack((unstabilized_frames[i], cropped_frames[i]))
                cv2.imshow("unstabilized and stabilized video", show)
                if cv2.waitKey(ms) & 0xFF == ord("q"):
                    cv2.destroyAllWindows()
                    return


def main():
    VIDEO_PATH = r"./output/history/trace_test/hit_006.mp4"
    OUTPUT_PATH = r"./output/history/trace_test/hit_006_stabilized.mp4"

    stabilizer = MeshFlowStabilizer(
        visualize=False,
        mesh_row_count=16,
        mesh_col_count=16,
        temporal_smoothing_radius=10,
        optimization_num_iterations=80,
    )

    result = stabilizer.stabilize_segment_only(
        VIDEO_PATH,
        OUTPUT_PATH,
        adaptive_weights_definition=MeshFlowStabilizer.ADAPTIVE_WEIGHTS_DEFINITION_ORIGINAL,
        AUTO_SHAKE_SEGMENT=True,
        # SHAKE_SMOOTH_WIN=7,
        # SHAKE_THRESH_K=3.0,
        # SHAKE_PAD_FRAMES=10,
        # SHAKE_MIN_SEG_LEN=12,
        SHAKE_THRESH_K=4.0,
        SHAKE_PAD_FRAMES=8,
        SHAKE_MIN_SEG_LEN=8,
        SHAKE_SMOOTH_WIN=7,
    )

    print("\n=== RESULT ===")
    print(result)


if __name__ == "__main__":
    main()
