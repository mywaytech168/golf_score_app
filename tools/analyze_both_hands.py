#!/usr/bin/env python3
# 雙手判斷 ADB 實錄驗證：以真實 hit 切片骨架 CSV，量「擊球禎雙手命中率」。
#
# 每片：用歸一化座標（對齊 LiveSwingDetector 語意）算左右腕速度 → 取主導腕
# 速度峰值當擊球禎 → 檢查該禎雙手可見/同調，並模擬雙手閘門是否仍會觸發。
#
# 用法: python tools/analyze_both_hands.py <csv_dir>

import sys, os, glob, math

MIN_VIS = 0.1
SECOND_FACTOR = 0.5         # 第二手放寬比例（同 LiveSwingDetector._secondHandFactor）
MIN_THR = 0.012             # 同 LiveSwingDetector._minThreshold
IMPACT_WIN = 2              # 擊球禎 ±窗（幀），容忍峰值/弧底差

# 歸一化座標欄位：3 + i*6 + {0:x,1:y,3:vis}
L = 15; R = 16
def cols(i): return (3 + i*6 + 0, 3 + i*6 + 1, 3 + i*6 + 3)
LX, LY, LV = cols(L)
RX, RY, RV = cols(R)

def parse(path):
    rows = []
    with open(path, encoding='utf-8', errors='ignore') as f:
        next(f, None)
        for line in f:
            c = line.rstrip('\n').split(',')
            if len(c) <= RV: continue
            def g(i):
                try: return float(c[i])
                except: return float('nan')
            rows.append({
                'lx': g(LX), 'ly': g(LY), 'lv': g(LV),
                'rx': g(RX), 'ry': g(RY), 'rv': g(RV),
            })
    return rows

def speeds(rows, kx, ky, kv):
    """回傳 (speed[], valid[]) ；無效幀速度 0、valid False。"""
    n = len(rows)
    sp = [0.0]*n; va = [False]*n
    for i in range(n):
        va[i] = rows[i][kv] >= MIN_VIS and not math.isnan(rows[i][kx])
    for i in range(1, n):
        if va[i] and va[i-1]:
            dx = rows[i][kx]-rows[i-1][kx]; dy = rows[i][ky]-rows[i-1][ky]
            sp[i] = math.hypot(dx, dy)
    return sp, va

def thr_of(sp):
    v = sorted(s for s in sp if s > 0)
    if len(v) < 5: return MIN_THR
    idx = min(len(v)-1, round(0.80*(len(v)-1)))
    return max(MIN_THR, v[idx]*1.8)

def analyze(path):
    rows = parse(path)
    if len(rows) < 10: return None
    rsp, rva = speeds(rows, 'rx', 'ry', 'rv')
    lsp, lva = speeds(rows, 'lx', 'ly', 'lv')
    dom = [max(rsp[i], lsp[i]) for i in range(len(rows))]
    # 擊球禎 = 主導腕速度峰值（忽略前 0.3s ≈ 9 幀邊界）
    lo = min(9, len(rows)//4)
    peak = max(range(lo, len(rows)), key=lambda i: dom[i])
    thr = thr_of(dom)

    # 擊球禎 ±窗內：雙手是否都可見、是否同調、閘門是否觸發
    both_vis = one_vis = none_vis = coh = gate_fire = False
    for i in range(max(1, peak-IMPACT_WIN), min(len(rows), peak+IMPACT_WIN+1)):
        rv, lv = rva[i], lva[i]
        if rv and lv:
            both_vis = True
            # 同調：兩腕速度向量夾角 < 90°
            rdx = rows[i]['rx']-rows[i-1]['rx']; rdy = rows[i]['ry']-rows[i-1]['ry']
            ldx = rows[i]['lx']-rows[i-1]['lx']; ldy = rows[i]['ly']-rows[i-1]['ly']
            if (rdx*ldx + rdy*ldy) > 0: coh = True
            # 雙手閘門：雙有效需 min ≥ thr*factor
            if dom[i] > thr and min(rsp[i], lsp[i]) >= thr*SECOND_FACTOR: gate_fire = True
        elif rv or lv:
            one_vis = True
            if dom[i] > thr: gate_fire = True   # 單手遮擋退回
    if not both_vis and not one_vis: none_vis = True
    return {
        'peak_vis_both': rva[peak] and lva[peak],
        'win_both_vis': both_vis,
        'win_one_only': (one_vis and not both_vis),
        'win_none': none_vis,
        'coherent': coh,
        'gate_fire': gate_fire,
        'single_fire': dom[peak] > thr,   # 單手模式一定會觸發（峰值>thr）
    }

def main():
    d = sys.argv[1] if len(sys.argv) > 1 else '/tmp/orvia_csv'
    files = sorted(glob.glob(os.path.join(d, '*.csv')))
    res = [r for r in (analyze(f) for f in files) if r]
    n = len(res)
    if not n:
        print('無有效切片'); return
    def pct(k): return 100.0*sum(1 for r in res if r[k])/n
    print(f'樣本切片數: {n}\n')
    print(f'擊球禎雙手都可見       : {pct("peak_vis_both"):5.1f}%')
    print(f'擊球窗(±{IMPACT_WIN}f)雙手可見  : {pct("win_both_vis"):5.1f}%')
    print(f'擊球窗僅單手可見(遮擋)  : {pct("win_one_only"):5.1f}%')
    print(f'擊球窗雙手皆無效        : {pct("win_none"):5.1f}%')
    print(f'雙手可見且同調          : {pct("coherent"):5.1f}%')
    print('-'*40)
    print(f'雙手閘門(含遮擋退回)觸發: {pct("gate_fire"):5.1f}%   ← recall')
    print(f'單手模式觸發            : {pct("single_fire"):5.1f}%   ← 基準')
    miss = [r for r in res if r['single_fire'] and not r['gate_fire']]
    print(f'\n雙手模式會漏掉(單手能抓): {len(miss)} / {n}  ({100.0*len(miss)/n:.1f}%)')

if __name__ == '__main__':
    main()
