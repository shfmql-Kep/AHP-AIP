#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
운영목표 가중치 민감도 3D Scatter 그래프
x=경제성, y=신뢰도, z=안전·환경 가중치 / 색상=투자가치 or SAIDI
폰트: KoPubDotum Bold / 축 제목 20pt / 내용 15pt
출력: 연구설계/07_그림자료/generated/chapter4/fig4_10_operating_goal_weight_sensitivity.png
"""

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import matplotlib.colors as mcolors
from mpl_toolkits.mplot3d import Axes3D          # noqa: F401
from pathlib import Path

# ── 경로 ──────────────────────────────────────────────────────────────
BASE = Path(r"C:\Users\shfmq\codexwork\AHP_AIP")
XLSX = (BASE / "연구설계/06_시뮬레이션결과/민감도_강건성"
        / "sensitivity_analysis_fast_20260624_100129"
        / "sensitivity_analysis_results_final.xlsx")
OUT_DIR = BASE / "연구설계/07_그림자료/generated/chapter4"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── 폰트 ──────────────────────────────────────────────────────────────
FONT     = 'KoPubDotum'
PT_AXIS  = 20
PT_TICK  = 15
PT_TITLE = 16
PT_CBAR  = 15

matplotlib.rc('font', family=FONT)
matplotlib.rc('axes', unicode_minus=False)

# ── 데이터 로드 ────────────────────────────────────────────────────────
df4 = pd.read_excel(XLSX, sheet_name='04_total_summary')
df3 = pd.read_excel(XLSX, sheet_name='03_annual_summary')

METHOD = 'integrated_pi_ilp'
SCOPE  = 'integrated_pi_portfolio'
GROUP  = 'operating_goal_weight_sweep'

# 투자가치
iv_df = df4[
    (df4['scenario_group'] == GROUP) &
    (df4['method'] == METHOD) &
    (df4['simulation_scope'] == SCOPE)
][['w_economy', 'w_reliability', 'w_safety_environment',
   'investment_value_kkrw']].dropna().copy()
iv_df['iv_억원'] = iv_df['investment_value_kkrw'] / 100000

# SAIDI 저감 (5개년 누적 최종 연도)
saidi_df = df3[
    (df3['scenario_group'] == GROUP) &
    (df3['method'] == METHOD) &
    (df3['simulation_scope'] == SCOPE)
]
saidi_df = (saidi_df.sort_values('year')
            .groupby(['w_economy', 'w_reliability', 'w_safety_environment'])
            .last().reset_index()
            [['w_economy', 'w_reliability', 'w_safety_environment',
              'saidi_removed_cumulative_min']].dropna())

# ── 기준 시나리오 가중치 (AHP 결과) ──────────────────────────────────
W_BASE = dict(economy=0.3541, reliability=0.2616, safety=0.3842)

def find_base_row(src_df, val_col):
    row = src_df[
        (np.abs(src_df['w_economy']          - W_BASE['economy'])    < 0.005) &
        (np.abs(src_df['w_reliability']      - W_BASE['reliability'])< 0.005) &
        (np.abs(src_df['w_safety_environment']- W_BASE['safety'])    < 0.005)
    ]
    return row[val_col].values[0] if not row.empty else None

base_iv    = find_base_row(iv_df,    'iv_억원')
base_saidi = find_base_row(saidi_df, 'saidi_removed_cumulative_min')

# ── 그림 ──────────────────────────────────────────────────────────────
fig = plt.figure(figsize=(22/2.54 * 2.0, 12/2.54 * 1.8))

PANELS = [
    {
        'idx':    1,
        'src_df': iv_df,
        'val_col':'iv_억원',
        'base_val': base_iv,
        'cmap':   'plasma',
        'clabel': '투자가치 (억원)',
        'title':  '(a) 투자가치',
    },
    {
        'idx':    2,
        'src_df': saidi_df,
        'val_col':'saidi_removed_cumulative_min',
        'base_val': base_saidi,
        'cmap':   'viridis',
        'clabel': 'SAIDI 저감 (분)',
        'title':  '(b) SAIDI 저감',
    },
]

for p in PANELS:
    ax  = fig.add_subplot(1, 2, p['idx'], projection='3d')
    src = p['src_df']
    x   = src['w_economy'].values.astype(float)
    y   = src['w_reliability'].values.astype(float)
    z   = src['w_safety_environment'].values.astype(float)
    c   = src[p['val_col']].values.astype(float)

    vmin, vmax = c.min(), c.max()
    norm  = mcolors.Normalize(vmin=vmin, vmax=vmax)
    cmap  = cm.get_cmap(p['cmap'])
    colors = cmap(norm(c))

    sc = ax.scatter(x, y, z,
                    c=c, cmap=p['cmap'], norm=norm,
                    s=120, edgecolors='white', linewidths=0.4,
                    depthshade=True, zorder=5)

    # 기준 시나리오 마커
    if p['base_val'] is not None:
        ax.plot([W_BASE['economy']], [W_BASE['reliability']], [W_BASE['safety']],
                marker='*', color='crimson', markersize=22,
                markeredgecolor='darkred', markeredgewidth=0.8,
                linestyle='None', zorder=100, label='기준 시나리오')
        ax.legend(fontsize=PT_TICK, loc='upper left',
                  prop={'family': FONT, 'weight': 'bold', 'size': PT_TICK})

    # 축 범위
    ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.set_zlim(0, 1)
    ax.set_xticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax.set_yticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax.set_zticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])

    # 축 레이블
    ax.set_xlabel('경제성 가중치', fontsize=PT_AXIS,
                  fontfamily=FONT, fontweight='bold', labelpad=18)
    ax.set_ylabel('신뢰도 가중치', fontsize=PT_AXIS,
                  fontfamily=FONT, fontweight='bold', labelpad=18)
    ax.set_zlabel('안전·환경 가중치', fontsize=PT_AXIS,
                  fontfamily=FONT, fontweight='bold', labelpad=18)
    ax.set_title(p['title'], fontsize=PT_TITLE,
                 fontfamily=FONT, fontweight='bold', pad=12)

    # 눈금 폰트
    for lbl in (ax.get_xticklabels() + ax.get_yticklabels()
                + ax.get_zticklabels()):
        lbl.set_fontsize(PT_TICK)
        lbl.set_fontfamily(FONT)
        lbl.set_fontweight('bold')
    ax.tick_params(axis='both', labelsize=PT_TICK, pad=5)

    # 컬러바
    cbar = fig.colorbar(sc, ax=ax, pad=0.1, shrink=0.52, aspect=16)
    cbar.set_label(p['clabel'], fontsize=PT_CBAR,
                   fontfamily=FONT, fontweight='bold', labelpad=10)
    cbar.ax.tick_params(labelsize=PT_CBAR)
    for lbl in cbar.ax.get_yticklabels():
        lbl.set_fontfamily(FONT)
        lbl.set_fontweight('bold')

    # 시점 (예시 그림과 유사하게)
    ax.view_init(elev=20, azim=-50)
    ax.dist = 11

fig.subplots_adjust(left=0.02, right=0.96, wspace=0.15)

out = OUT_DIR / "fig4_10_operating_goal_weight_sensitivity.png"
fig.savefig(out, dpi=300, bbox_inches='tight')
print(f"저장 완료: {out}")
