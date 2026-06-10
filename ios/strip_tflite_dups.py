#!/usr/bin/env python3
"""Hide TFLite C API symbols in TensorFlowLiteC that duplicate MediaPipe's.

MediaPipeTasksCommon 的 graph library（-force_load 全量載入）與
TensorFlowLiteC.framework 都內含 TFLite C API，最終連結撞 48 個符號。
MediaPipe 內建的 TFLite 版本較新（含 TfLiteTensorClone / TfLiteKernelInitFailed
等新 API），pod 上最新的 TensorFlowLiteC 2.17 沒有這些符號，所以不能刪
MediaPipe 側。改用 `ld -r -unexported_symbols_list` 把 TensorFlowLiteC 內
「與 MediaPipe 重複」的全域符號降為 local：兩份 TFLite 各自內聚——
TFLite Swift 走 TensorFlowLiteC 自己的實作（內部參照在 ld -r 時已綁定），
MediaPipe 走自己的，互不混用。

Usage: strip_tflite_dups.py <TensorFlowLiteC-binary> <mediapipe-graph.a> ...
由 Podfile post_install 呼叫；重複執行無害（交集為空就跳過）。
"""
import os
import subprocess
import sys
import tempfile


def run(*cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True,
                          check=True, **kw)


def defined_globals(path, arch=None):
    """nm -gU：列出已定義的外部符號（支援 thin/fat/archive）。"""
    cmd = ["nm", "-gU"]
    if arch:
        cmd += ["-arch", arch]
    cmd.append(path)
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    syms = set()
    for line in out.splitlines():
        parts = line.split()
        # 跳過 "path(member.o):" 標頭與空行；符號行格式為 "addr TYPE name"
        if len(parts) >= 3 and not line.endswith(":"):
            syms.add(parts[-1])
    return syms


def hide_in_slice(slice_path, conflicts, arch):
    """ld -r 將 conflicts 中的全域符號降為 local。"""
    fd, lst = tempfile.mkstemp(suffix=".syms")
    out = slice_path + ".dedup"
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(sorted(conflicts)) + "\n")
        run("ld", "-r", "-arch", arch, slice_path,
            "-unexported_symbols_list", lst, "-o", out)
        os.replace(out, slice_path)
    finally:
        os.unlink(lst)
        if os.path.exists(out):
            os.unlink(out)


def main():
    binary, graph_libs = sys.argv[1], sys.argv[2:]

    mp_syms = set()
    for lib in graph_libs:
        mp_syms |= defined_globals(lib)
    if not mp_syms:
        sys.exit(f"no symbols found in {graph_libs}")

    archs = run("lipo", binary, "-archs").stdout.split()
    total = 0
    if len(archs) <= 1:
        arch = archs[0] if archs else "arm64"
        conflicts = defined_globals(binary) & mp_syms
        if conflicts:
            hide_in_slice(binary, conflicts, arch)
            total = len(conflicts)
    else:
        thins = []
        try:
            for arch in archs:
                fd, thin = tempfile.mkstemp(suffix=f"_{arch}")
                os.close(fd)
                thins.append(thin)
                run("lipo", binary, "-thin", arch, "-output", thin)
                conflicts = defined_globals(thin) & mp_syms
                if conflicts:
                    hide_in_slice(thin, conflicts, arch)
                    total += len(conflicts)
            run("lipo", "-create", *thins, "-output", binary)
        finally:
            for thin in thins:
                if os.path.exists(thin):
                    os.unlink(thin)

    print(f"strip_tflite_dups: hid {total} duplicate symbol(s) "
          f"in {os.path.basename(os.path.dirname(binary)) or binary}")


if __name__ == "__main__":
    main()
