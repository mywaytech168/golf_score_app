#!/usr/bin/env python3
"""Remove static-archive members that define duplicate TFLite C API symbols.

MediaPipeTasksCommon 的 graph library 內含 TFLite C API objects，與
TensorFlowLiteC.framework 撞名（48 duplicate symbols）。但 .a 裡有同名成員
（GPU/Metal 也有 common.o / types.o），不能用 `ar -d` 盲刪——它只刪第一個。
本腳本解析 ar 格式，對候選成員逐一用 `nm` 檢查，只移除「真的定義了
指定 TFLite C 符號」的成員，GPU/Metal 同名成員保留。
模擬器版 .a 是 fat binary（多架構），先用 lipo 拆 slice 處理後再合併。

Usage: strip_tflite_dups.py <archive.a> <symbol> [<symbol> ...]
由 Podfile post_install 呼叫；重複執行無害（已移除就不再匹配）。
"""
import os
import subprocess
import sys
import tempfile

CANDIDATES = {"xnnpack_delegate.o", "common.o", "types.o",
              "telemetry_setting_internal.o"}
AR_MAGIC = b"!<arch>\n"


def strip_archive(path, syms):
    """處理單一（thin）ar 檔，回傳移除的成員數。"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != AR_MAGIC:
        sys.exit(f"{path}: not an ar archive")

    out = [data[:8]]
    pos = 8
    removed = 0
    while pos + 60 <= len(data):
        hdr = data[pos:pos + 60]
        name = hdr[:16].decode().rstrip()
        size = int(hdr[48:58])
        body = data[pos + 60:pos + 60 + size]
        raw = data[pos:pos + 60 + size + (size & 1)]
        pos += 60 + size + (size & 1)

        obj = body
        if name.startswith("#1/"):  # BSD extended name：實際名稱在資料開頭
            n = int(name[3:])
            name = body[:n].rstrip(b"\x00").decode()
            obj = body[n:]

        if name.startswith("__.SYMDEF"):
            continue  # 符號表丟棄，結尾由 ranlib 重建

        if os.path.basename(name) in CANDIDATES:
            fd, tmp = tempfile.mkstemp(suffix=".o")
            try:
                os.write(fd, obj)
                os.close(fd)
                nm = subprocess.run(["nm", "-gU", tmp],
                                    capture_output=True, text=True).stdout
            finally:
                os.unlink(tmp)
            defined = {l.split()[-1] for l in nm.splitlines() if l.strip()}
            if defined & syms:
                removed += 1
                continue

        out.append(raw)

    with open(path, "wb") as f:
        f.write(b"".join(out))
    subprocess.run(["ranlib", path], check=True)
    return removed


def main():
    path, syms = sys.argv[1], set(sys.argv[2:])
    with open(path, "rb") as f:
        magic = f.read(8)

    if magic == AR_MAGIC:
        removed = strip_archive(path, syms)
    else:
        # fat binary（模擬器版 arm64 + x86_64）：lipo 拆 slice → 各自處理 → 合併
        archs = subprocess.run(["lipo", path, "-archs"],
                               capture_output=True, text=True, check=True)
        archs = archs.stdout.split()
        if not archs:
            sys.exit(f"{path}: not an ar archive nor a fat binary")
        removed = 0
        thins = []
        try:
            for arch in archs:
                fd, thin = tempfile.mkstemp(suffix=f"_{arch}.a")
                os.close(fd)
                thins.append(thin)
                subprocess.run(["lipo", path, "-thin", arch,
                                "-output", thin], check=True)
                removed += strip_archive(thin, syms)
            subprocess.run(["lipo", "-create", *thins, "-output", path],
                           check=True)
        finally:
            for thin in thins:
                if os.path.exists(thin):
                    os.unlink(thin)

    print(f"strip_tflite_dups: removed {removed} member(s) "
          f"from {os.path.basename(path)}")


if __name__ == "__main__":
    main()
