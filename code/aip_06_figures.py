"""
AIP Step 6 -- 논문용 그래프 생성
===================================
출력: figures/ 폴더에 PNG 파일 저장
"""

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.gridspec import GridSpec
from pathlib import Path

# -- 한글 폰트 설정
import matplotlib.font_manager as fm
_fonts = [f.name for f in fm.fontManager.ttflist]
for _cand in ['Malgun Gothic', 'NanumGothic', 'AppleGothic', 'DejaVu Sans']:
    if _cand in _fonts:
        plt.rcParams['font.family'] = _cand
        break
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams['figure.dpi'] = 150

FIGURES_DIR = Path(__file__).resolve().parent.parent / "figures"
FIGURES_DIR.mkdir(exist_ok=True)

# ======================================================================
# 시뮬레이션 결과 데이터 (aip_04_ilp.py 실행 결과)
# ======================================================================

METHODS = ['B1\n유형별\nRisk-Greedy', 'B2\n유형별\nNPV-Greedy',
           'B3\n유형별\nRisk-ILP', 'B4\n유형별\nNPV-ILP',
           'P1\n통합\nAHP-ILP', 'P2\n통합\nAHP-GA']
METHODS_SHORT = ['B1', 'B2', 'B3', 'B4', 'P1', 'P2']

# 3% 시나리오
SC3 = {
    '선택수':    [6459,  6459,  6459,  6459,  8696,  7787],
    '총NPV':     [2517,  2527,  2516,  2527,  2736,  2670],   # 억원
    'BCR':       [3.348, 3.363, 3.347, 3.363, 3.638, 3.550],
    'Risk저감':  [4981,  4941,  4981,  4941,  5132,  5083],   # 백만원/년
    'SAIDI':     [6603,  6586,  6603,  6586,  6480,  6476],   # 천
    '혼합가치':  [1911,  1898,  1911,  1898,  2091,  2029],
}
# 5% 시나리오
SC5 = {
    '선택수':    [7001,  7001,  7001,  7001,  9331,  8286],
    '총NPV':     [2753,  2773,  2753,  2773,  3011,  2879],
    'BCR':       [3.391, 3.415, 3.391, 3.415, 3.706, 3.543],
    'Risk저감':  [5373,  5305,  5373,  5305,  5565,  5455],
    'SAIDI':     [7164,  7172,  7164,  7172,  7201,  6949],
    '혼합가치':  [2064,  2040,  2064,  2040,  2253,  2174],
}
# 7% 시나리오
SC7 = {
    '선택수':    [7542,  7542,  7542,  7542,  9806,  8717],
    '총NPV':     [2974,  3001,  2974,  3001,  3227,  3084],
    'BCR':       [3.410, 3.442, 3.410, 3.442, 3.697, 3.534],
    'Risk저감':  [5735,  5643,  5735,  5643,  5945,  5785],
    'SAIDI':     [7637,  7665,  7637,  7665,  7634,  7308],
    '혼합가치':  [2210,  2177,  2210,  2177,  2399,  2305],
}

SCENARIOS = {'3%': SC3, '5%': SC5, '7%': SC7}

# 색상: Baseline 계열(회색톤) / Proposed 계열(청록·주황)
COLORS = ['#9E9E9E', '#B0BEC5', '#607D8B', '#455A64', '#1565C0', '#E65100']
HATCH  = ['', '', '//', '//', '', '']

# ======================================================================
# Fig 1: 5% 시나리오 주요 KPI 비교 (4개 서브플롯)
# ======================================================================

def fig_kpi_5pct():
    fig, axes = plt.subplots(2, 2, figsize=(13, 9))
    fig.suptitle('그림 5.1  비교방법론별 주요 KPI (예산 5% 시나리오)',
                 fontsize=13, fontweight='bold', y=1.01)

    kpis = [
        ('총NPV', SC5['총NPV'], '총 투자가치 NPV (억원)', '억원'),
        ('BCR',   SC5['BCR'],   '편익비용비율 (BCR)',     ''),
        ('Risk저감', SC5['Risk저감'], '총 Risk 저감량 (백만원/년)', '백만원/년'),
        ('혼합가치', SC5['혼합가치'], '혼합가치 합계 (V)', ''),
    ]

    for ax, (key, vals, title, unit) in zip(axes.flat, kpis):
        bars = ax.bar(METHODS_SHORT, vals, color=COLORS, edgecolor='white',
                      linewidth=0.8, width=0.6)
        # hatch for ILP variants
        for bar, h in zip(bars, HATCH):
            bar.set_hatch(h)

        # 최고값 강조
        best = np.argmax(vals)
        bars[best].set_edgecolor('#FF6F00')
        bars[best].set_linewidth(2.5)

        # 값 레이블
        for bar, v in zip(bars, vals):
            ypos = bar.get_height() * 1.01
            fmt  = f'{v:.3f}' if key == 'BCR' else f'{v:,.0f}'
            ax.text(bar.get_x() + bar.get_width()/2, ypos, fmt,
                    ha='center', va='bottom', fontsize=8.5)

        ax.set_title(title, fontsize=10, pad=6)
        if unit:
            ax.set_ylabel(unit, fontsize=9)
        ax.set_ylim(0, max(vals) * 1.15)
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.tick_params(axis='x', labelsize=8)
        ax.tick_params(axis='y', labelsize=8)

        # 구분선 (B/P 경계)
        ax.axvline(x=3.5, color='gray', linestyle='--', linewidth=0.8, alpha=0.6)
        ax.text(1.5, ax.get_ylim()[1]*0.97, 'Baseline (관행)',
                ha='center', fontsize=7.5, color='gray')
        ax.text(4.5, ax.get_ylim()[1]*0.97, 'Proposed',
                ha='center', fontsize=7.5, color='#1565C0')

    plt.tight_layout()
    out = FIGURES_DIR / "fig1_kpi_5pct.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 2: 예산 민감도 분석 — 3시나리오 × NPV / 혼합가치
# ======================================================================

def fig_sensitivity():
    fig, axes = plt.subplots(1, 3, figsize=(16, 6))
    fig.suptitle('그림 5.4  예산 시나리오별 핵심 KPI 비교 (3% / 5% / 7%)',
                 fontsize=12, fontweight='bold', y=1.02)

    kpi_sets = [
        ('총NPV',   '총 투자가치 NPV (억원)'),
        ('BCR',     '편익비용비율 (BCR)'),
        ('혼합가치','혼합가치 합계 (V)'),
    ]

    patches = [mpatches.Patch(facecolor=c, label=m, hatch=h, edgecolor='gray')
               for m, c, h in zip(METHODS_SHORT, COLORS, HATCH)]

    for ax, (key, ylabel) in zip(axes, kpi_sets):
        x  = np.arange(3)
        w  = 0.13
        sc_data = [SC3[key], SC5[key], SC7[key]]

        for mi, (ms, col, hch) in enumerate(zip(METHODS_SHORT, COLORS, HATCH)):
            vals = [sc[mi] for sc in sc_data]
            ax.bar(x + (mi - 2.5)*w, vals, w*0.9,
                   label=ms, color=col, hatch=hch,
                   edgecolor='white', linewidth=0.5)

        # B/P 구분 배경
        ax.axvspan(-0.5, 2.5 - 0.5*w, alpha=0.04, color='gray')
        ax.axvspan(2.5 - 0.5*w, 2.5 + 0.5*w + w*3, alpha=0.06, color='#1565C0')

        ax.set_xticks(x)
        ax.set_xticklabels(['3%\n시나리오', '5%\n시나리오', '7%\n시나리오'], fontsize=9)
        ax.set_ylabel(ylabel, fontsize=9)
        ax.set_title(ylabel, fontsize=10, pad=8)
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.tick_params(axis='y', labelsize=8)
        # P1·P2 수치 레이블
        for si, sc in enumerate([SC3, SC5, SC7]):
            for mi in [4, 5]:
                v = sc[key][mi]
                fmt = f'{v:.3f}' if key == 'BCR' else f'{v:,}'
                xpos = si + (mi - 2.5) * w
                ax.text(xpos, v * 1.005, fmt,
                        ha='center', va='bottom', fontsize=6.5,
                        color='#1565C0' if mi == 4 else '#E65100', fontweight='bold')

    # 공통 범례 — 우측 상단
    fig.legend(handles=patches, loc='upper right',
               bbox_to_anchor=(1.02, 0.92), fontsize=9,
               title='방법론', title_fontsize=9, framealpha=0.9)

    plt.tight_layout()
    out = FIGURES_DIR / "fig2_sensitivity.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 3: B4 대비 P1 향상률 (시나리오별)
# ======================================================================

def fig_improvement():
    fig, ax = plt.subplots(figsize=(9, 5))
    fig.suptitle('그림 5.5  관행 최선(B4) 대비 제안 방법론(P1) 향상률',
                 fontsize=12, fontweight='bold')

    kpi_keys   = ['총NPV', 'BCR', 'Risk저감', '혼합가치']
    kpi_labels = ['총 NPV', 'BCR', 'Risk 저감량', '혼합가치']
    sc_labels  = ['3%', '5%', '7%']
    sc_data    = [SC3, SC5, SC7]
    sc_colors  = ['#42A5F5', '#1565C0', '#0D47A1']

    x = np.arange(len(kpi_keys))
    w = 0.22

    for si, (sc, slabel, col) in enumerate(zip(sc_data, sc_labels, sc_colors)):
        b4_idx = 3  # B4 인덱스
        p1_idx = 4  # P1 인덱스
        improvements = []
        for key in kpi_keys:
            vB = sc[key][b4_idx]
            vP = sc[key][p1_idx]
            improvements.append((vP - vB) / abs(vB) * 100)

        bars = ax.bar(x + (si - 1)*w, improvements, w*0.9,
                      label=f'{slabel} 시나리오', color=col,
                      edgecolor='white', linewidth=0.5)
        for bar, v in zip(bars, improvements):
            ax.text(bar.get_x() + bar.get_width()/2,
                    bar.get_height() + 0.1,
                    f'+{v:.1f}%', ha='center', va='bottom', fontsize=8)

    ax.axhline(0, color='black', linewidth=0.8)
    ax.set_xticks(x)
    ax.set_xticklabels(kpi_labels, fontsize=10)
    ax.set_ylabel('향상률 (%)', fontsize=10)
    ax.set_ylim(0, 15)
    ax.legend(fontsize=9)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    plt.tight_layout()
    out = FIGURES_DIR / "fig3_improvement.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 4: 자산유형별 예산 배분 비율 (비용 비례)
# ======================================================================

def fig_asset_budget():
    labels = ['주상변압기', '가공배전선로', '지상변압기', '지중케이블',
              '지중변압기', '지중개폐기_RMU', '가공개폐기', '특고압차단기',
              '콘크리트주', '목주', '철주']
    ratios = [43.6, 13.9, 11.6, 9.3, 6.3, 6.3, 6.0, 2.3, 0.3, 0.2, 0.1]
    colors_pie = plt.cm.tab20.colors[:len(labels)]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    fig.suptitle('그림 5.2  자산유형별 비용 비례 예산 배분 구조',
                 fontsize=12, fontweight='bold')

    # 파이 차트
    explode = [0.05 if r > 5 else 0 for r in ratios]
    wedges, texts, autotexts = ax1.pie(
        ratios, labels=None, autopct='%1.1f%%',
        startangle=140, explode=explode,
        colors=colors_pie, pctdistance=0.78
    )
    for at in autotexts:
        at.set_fontsize(7.5)
    ax1.set_title('예산 배분 비율', fontsize=10)
    ax1.legend(wedges, labels, loc='lower left', fontsize=7.5,
               bbox_to_anchor=(-0.3, -0.1))

    # 수평 막대 차트
    y = np.arange(len(labels))
    bars = ax2.barh(y, ratios, color=colors_pie, edgecolor='white')
    ax2.set_yticks(y)
    ax2.set_yticklabels(labels, fontsize=9)
    ax2.set_xlabel('배분 비율 (%)', fontsize=9)
    ax2.set_title('자산유형별 비율 상세', fontsize=10)
    for bar, v in zip(bars, ratios):
        ax2.text(bar.get_width() + 0.3, bar.get_y() + bar.get_height()/2,
                 f'{v}%', va='center', fontsize=8.5)
    ax2.set_xlim(0, 52)
    ax2.spines['top'].set_visible(False)
    ax2.spines['right'].set_visible(False)
    ax2.invert_yaxis()

    plt.tight_layout()
    out = FIGURES_DIR / "fig4_asset_budget.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 5: GA 수렴 곡선 (5% 시나리오)
# ======================================================================

def fig_ga_convergence():
    gens = [30, 60, 90, 120, 150]
    vals = [464.30, 497.50, 508.02, 512.04, 512.26]

    fig, ax = plt.subplots(figsize=(8, 5))
    fig.suptitle('그림 5.3  유전 알고리즘 수렴 곡선 (예산 5% 시나리오)',
                 fontsize=12, fontweight='bold')

    ax.plot(gens, vals, 'o-', color='#E65100', linewidth=2,
            markersize=8, markerfacecolor='white', markeredgewidth=2,
            label='최적 혼합가치')
    ax.fill_between(gens, [v*0.995 for v in vals], vals,
                    alpha=0.15, color='#E65100')

    for g, v in zip(gens, vals):
        ax.annotate(f'{v:.1f}', (g, v), textcoords='offset points',
                    xytext=(0, 10), ha='center', fontsize=9)

    ax.set_xlabel('세대 (Generation)', fontsize=10)
    ax.set_ylabel('최적 혼합가치 합계 (V)', fontsize=10)
    ax.set_xlim(0, 165)
    ax.set_ylim(min(vals)*0.98, max(vals)*1.04)
    ax.set_xticks(gens)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.legend(fontsize=9)

    # 수렴 개선량 표시
    for i in range(1, len(gens)):
        imp = vals[i] - vals[i-1]
        mid_x = (gens[i] + gens[i-1]) / 2
        mid_y = (vals[i] + vals[i-1]) / 2
        ax.annotate(f'+{imp:.1f}', (mid_x, mid_y),
                    textcoords='offset points', xytext=(0, -18),
                    ha='center', fontsize=7.5, color='gray',
                    arrowprops=dict(arrowstyle='->', color='gray', lw=0.8))

    plt.tight_layout()
    out = FIGURES_DIR / "fig5_ga_convergence.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 6: 자산유형별 선택 분포 비교 (B4 vs P1, 5% 기준)
# ======================================================================

def fig_asset_selection():
    asset_types = ['주상변압기', '지상변압기', '지중변압기', '가공개폐기',
                   '지중개폐기\nRMU', '특고압차단기', '가공배전선로',
                   '지중케이블', '목주', '콘크리트주', '철주']
    total      = [10000, 1622, 811, 3514, 1351, 811, 3514, 3514, 1622, 1892, 1351]
    b4_sel     = [3107,  595,  325, 1238,  467,  300, 751,  753,  152,  192,   71]
    p1_sel     = [3524,  658,  359, 1356,  520,  329, 1223, 1085, 278,  351,  108]

    x   = np.arange(len(asset_types))
    w   = 0.28
    fig, ax = plt.subplots(figsize=(14, 6))
    fig.suptitle('그림 5.6  자산유형별 선택 설비 수 비교 (예산 5% 시나리오)',
                 fontsize=12, fontweight='bold')

    ax.bar(x - w, total,  w, label='전체(기)', color='#ECEFF1', edgecolor='#90A4AE')
    ax.bar(x,     b4_sel, w, label='B4 유형별NPV-ILP (관행)', color='#455A64',
           edgecolor='white')
    ax.bar(x + w, p1_sel, w, label='P1 통합AHP-ILP (제안)',   color='#1565C0',
           edgecolor='white')

    ax.set_xticks(x)
    ax.set_xticklabels(asset_types, fontsize=8.5, rotation=20, ha='right')
    ax.set_ylabel('설비 수 (기)', fontsize=10)
    ax.legend(fontsize=9, loc='upper right')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    # 선택률 표시 (P1)
    for i, (b, p, t) in enumerate(zip(b4_sel, p1_sel, total)):
        rate = p / t * 100
        ax.text(x[i] + w, p + 80, f'{rate:.0f}%',
                ha='center', fontsize=7.5, color='#1565C0')

    plt.tight_layout()
    out = FIGURES_DIR / "fig6_asset_selection.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# Fig 7: AHP 가중치 비교 (3종 방법론)
# ======================================================================

def fig_ahp_weights():
    criteria = ['NPV\n(C1-1)', 'BCR\n(C1-2)', 'SAIDI\n(C2-1)', 'ENF\n(C2-2)',
                '재무Risk\n(C3-1)', '안전Risk\n(C3-2)', '환경Risk\n(C3-3)']
    classical = [0.1893, 0.1103, 0.1719, 0.0460, 0.2144, 0.1976, 0.0706]
    fuzzy     = [0.1903, 0.1200, 0.2137, 0.0000, 0.2117, 0.2117, 0.0525]
    bwm       = [0.1821, 0.1512, 0.1719, 0.0942, 0.1552, 0.1648, 0.0806]

    x = np.arange(len(criteria))
    w = 0.25
    fig, ax = plt.subplots(figsize=(11, 5.5))
    fig.suptitle('그림 4.3  AHP 방법론별 전역 가중치 비교',
                 fontsize=12, fontweight='bold')

    b1 = ax.bar(x - w, classical, w, label='Classical AHP', color='#1565C0',
                edgecolor='white')
    b2 = ax.bar(x,     fuzzy,     w, label='Fuzzy AHP',     color='#E65100',
                edgecolor='white')
    b3 = ax.bar(x + w, bwm,       w, label='BWM',           color='#2E7D32',
                edgecolor='white')

    for bars in [b1, b2, b3]:
        for bar in bars:
            h = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2, h + 0.003,
                    f'{h:.3f}', ha='center', va='bottom', fontsize=7.5)

    ax.set_xticks(x)
    ax.set_xticklabels(criteria, fontsize=9)
    ax.set_ylabel('가중치', fontsize=10)
    ax.set_ylim(0, 0.32)
    ax.axhline(1/7, color='gray', linestyle=':', linewidth=0.8, alpha=0.7,
               label='균등 가중치 (1/7)')
    ax.legend(fontsize=9)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    plt.tight_layout()
    out = FIGURES_DIR / "fig7_ahp_weights.png"
    plt.savefig(out, bbox_inches='tight')
    plt.close()
    print(f"  저장: {out.name}")


# ======================================================================
# 진입점
# ======================================================================

if __name__ == "__main__":
    print("=" * 55)
    print("  논문용 그래프 생성")
    print("=" * 55)
    print(f"\n저장 위치: {FIGURES_DIR}\n")

    fig_kpi_5pct()
    fig_sensitivity()
    fig_improvement()
    fig_asset_budget()
    fig_ga_convergence()
    fig_asset_selection()
    fig_ahp_weights()

    print("\n완료 -- figures/ 폴더 확인")
