#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
예산·물량 배율 민감도 그래프 생성
폰트: KoPubDotum Bold / 축 제목 20pt / 내부 내용 15pt
출력: 연구설계/07_그림자료/generated/chapter4/fig4_8_budget_capacity_sensitivity.png
"""

import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from pathlib import Path

# ── 경로 ──────────────────────────────────────────────────────────────
BASE = Path(r"C:\Users\shfmq\codexwork\AHP_AIP")
XLSX = (BASE / "연구설계/06_시뮬레이션결과/민감도_강건성"
        / "sensitivity_analysis_fast_20260624_100129"
        / "sensitivity_analysis_results_final.xlsx")
OUT_DIR = BASE / "연구설계/07_그림자료/generated/chapter4"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── 폰트 설정 ──────────────────────────────────────────────────────────
FONT_BOLD   = 'KoPubDotum'   # Bold 계열 패밀리명
PT_AXIS_LBL = 20             # 축 제목
PT_TICK     = 15             # 눈금 숫자
PT_LEGEND   = 15             # 범례
PT_TITLE    = 16             # 서브플롯 제목

matplotlib.rc('font', family=FONT_BOLD)
matplotlib.rc('axes', unicode_minus=False)

# ── 데이터 로드 ────────────────────────────────────────────────────────
df = pd.read_excel(XLSX, sheet_name='04_total_summary')

# ── 방법론 설정 ────────────────────────────────────────────────────────
METHOD_CFG = {
    'risk_greedy':          {'label': '리스크 그리디', 'color': '#888888', 'marker': 'D', 'ls': '--'},
    'investment_value_ilp': {'label': 'IV ILP',       'color': '#1f77b4', 'marker': 'o', 'ls': '-'},
    'local_pi_ilp':         {'label': 'PI ILP',       'color': '#d62728', 'marker': 's', 'ls': '-'},
    'integrated_pi_ilp':    {'label': '통합형 ILP',   'color': '#2ca02c', 'marker': '^', 'ls': '-'},
}
SCOPE_MAP = {
    'risk_greedy':          'risk_value_screening',
    'investment_value_ilp': 'risk_value_screening',
    'local_pi_ilp':         'local_pi_portfolio',
    'integrated_pi_ilp':    'integrated_pi_portfolio',
}

# ── 그림 ──────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(22/2.54 * 1.5, 12/2.54 * 1.5))

PANELS = [
    {
        'ax':     axes[0],
        'group':  'budget_sweep',
        'x_col':  'budget_multiplier',
        'xlabel': '예산 배율 (기준 대비)',
        'title':  '(a) 예산 배율 민감도',
    },
    {
        'ax':     axes[1],
        'group':  'capacity_sweep',
        'x_col':  'capacity_multiplier',
        'xlabel': '물량 배율 (기준 대비)',
        'title':  '(b) 물량 배율 민감도',
    },
]

for p in PANELS:
    ax   = p['ax']
    grp  = df[df['scenario_group'] == p['group']].copy()
    xcol = p['x_col']

    for method, cfg in METHOD_CFG.items():
        scope = SCOPE_MAP[method]
        sub = grp[(grp['method'] == method) & (grp['simulation_scope'] == scope)]
        if sub.empty:
            continue
        sub = sub.sort_values(xcol)
        y = sub['investment_value_kkrw'] / 100000  # 억원

        ax.plot(sub[xcol].values, y.values,
                color=cfg['color'], marker=cfg['marker'],
                linestyle=cfg['ls'], linewidth=2.0,
                markersize=7, label=cfg['label'],
                markeredgecolor='white', markeredgewidth=0.5)

    ax.axvline(1.0, color='gray', linestyle=':', linewidth=1.2,
               label='기준(×1.0)')

    ax.set_xlabel(p['xlabel'], fontsize=PT_AXIS_LBL,
                  fontfamily=FONT_BOLD, fontweight='bold', labelpad=8)
    ax.set_ylabel('투자가치 (억원)', fontsize=PT_AXIS_LBL,
                  fontfamily=FONT_BOLD, fontweight='bold', labelpad=8)
    ax.set_title(p['title'], fontsize=PT_TITLE,
                 fontfamily=FONT_BOLD, fontweight='bold', pad=10)

    ax.xaxis.set_major_locator(mticker.MultipleLocator(0.1))
    ax.xaxis.set_major_formatter(mticker.FormatStrFormatter('%.1f'))
    ax.tick_params(axis='both', labelsize=PT_TICK)
    for lbl in ax.get_xticklabels() + ax.get_yticklabels():
        lbl.set_fontfamily(FONT_BOLD)
        lbl.set_fontweight('bold')

    ax.yaxis.set_major_formatter(
        mticker.FuncFormatter(lambda x, _: f'{x:,.0f}'))

    ax.grid(True, linestyle='--', linewidth=0.6, alpha=0.55)
    ax.set_axisbelow(True)
    ax.legend(fontsize=PT_LEGEND, loc='upper left', framealpha=0.85,
              prop={'family': FONT_BOLD, 'weight': 'bold', 'size': PT_LEGEND})

fig.tight_layout(pad=2.0)

out = OUT_DIR / "fig4_8_budget_capacity_sensitivity.png"
fig.savefig(out, dpi=300, bbox_inches='tight')
print(f"저장 완료: {out}")
