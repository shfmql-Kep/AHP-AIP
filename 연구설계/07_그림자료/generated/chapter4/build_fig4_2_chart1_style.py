from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import html


ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = ROOT / "07_그림자료" / "generated" / "chapter4"
PNG_PATH = OUT_DIR / "fig4_2_aggregate_performance_value_methods.png"
SVG_PATH = OUT_DIR / "fig4_2_aggregate_performance_value_methods.svg"


# 그림 4.2 데이터: 리스크 및 투자가치 기반 방식 전체 합산 결과
methods = ["Risk Greedy", "IV Greedy", "IV ILP", "IV GA"]
risk_reduction = [1642.58, 1753.59, 1786.34, 1781.42]
investment_cost = [759.98, 760.70, 761.10, 761.66]
investment_value = [882.60, 992.89, 1025.24, 1019.76]
investment_eff = [2.161, 2.305, 2.347, 2.339]


# Chart1.crtx에서 확인한 색상 체계
COL_RISK = "#FFC000"   # accent4
COL_COST = "#5B9BD5"   # accent1
COL_VALUE = "#ED7D31"  # accent2
COL_LINE = "#0000FF"
COL_AXIS = "#222222"
COL_GRID = "#D9D9D9"
COL_TEXT = "#111111"


W, H = 1650, 980
plot_left, plot_top = 150, 110
plot_right, plot_bottom = 1500, 810
plot_w, plot_h = plot_right - plot_left, plot_bottom - plot_top


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


font_regular = font("C:/Windows/Fonts/malgun.ttf", 28)
font_small = font("C:/Windows/Fonts/malgun.ttf", 24)
font_tiny = font("C:/Windows/Fonts/malgun.ttf", 21)
font_bold = font("C:/Windows/Fonts/malgunbd.ttf", 30)
font_label = font("C:/Windows/Fonts/malgunbd.ttf", 24)


img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)


# 차트 외곽 및 플롯 영역
d.rectangle([70, 55, W - 70, H - 70], outline=COL_AXIS, width=2)
d.rectangle([plot_left, plot_top, plot_right, plot_bottom], outline=COL_AXIS, width=2)


# 축 범위
money_max = 2000
eff_max = 3.0
money_ticks = [0, 500, 1000, 1500, 2000]
eff_ticks = [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]


def y_money(v: float) -> float:
    return plot_bottom - (v / money_max) * plot_h


def y_eff(v: float) -> float:
    return plot_bottom - (v / eff_max) * plot_h


# 그리드 및 좌측 축 눈금
for tick in money_ticks:
    y = y_money(tick)
    d.line([plot_left, y, plot_right, y], fill=COL_GRID, width=1)
    label = "-" if tick == 0 else f"{tick:,}"
    bbox = d.textbbox((0, 0), label, font=font_small)
    d.text((plot_left - 18 - (bbox[2] - bbox[0]), y - 13), label, fill=COL_TEXT, font=font_small)


# 우측 축 눈금
for tick in eff_ticks:
    y = y_eff(tick)
    label = f"{tick:.1f}"
    d.text((plot_right + 18, y - 13), label, fill=COL_LINE, font=font_small)


# 축 제목
left_label = "금액 [억 원]"
right_label = "투자효율 [-]"

left_txt = Image.new("RGBA", (260, 60), (255, 255, 255, 0))
ld = ImageDraw.Draw(left_txt)
ld.text((0, 8), left_label, fill=COL_TEXT, font=font_bold)
left_rot = left_txt.rotate(90, expand=1)
img.paste(left_rot, (32, plot_top + plot_h // 2 - left_rot.height // 2), left_rot)

right_txt = Image.new("RGBA", (260, 60), (255, 255, 255, 0))
rd = ImageDraw.Draw(right_txt)
rd.text((0, 8), right_label, fill=COL_LINE, font=font_bold)
right_rot = right_txt.rotate(270, expand=1)
img.paste(right_rot, (W - 80, plot_top + plot_h // 2 - right_rot.height // 2), right_rot)


# 범례
legend_items = [
    ("리스크 저감량", COL_RISK, "bar"),
    ("투자비용", COL_COST, "bar"),
    ("투자가치", COL_VALUE, "bar"),
    ("투자효율", COL_LINE, "line"),
]

legend_x = plot_left + 210
legend_y = 72
for name, color, kind in legend_items:
    if kind == "bar":
        d.rectangle([legend_x, legend_y + 5, legend_x + 32, legend_y + 25], fill=color, outline=COL_AXIS, width=1)
        text_color = COL_TEXT
    else:
        d.line([legend_x, legend_y + 15, legend_x + 34, legend_y + 15], fill=color, width=4)
        d.ellipse([legend_x + 13, legend_y + 7, legend_x + 27, legend_y + 21], fill=color, outline=color)
        text_color = COL_LINE
    d.text((legend_x + 42, legend_y - 2), name, fill=text_color, font=font_small)
    legend_x += 235


# 막대와 라인
n = len(methods)
group_w = plot_w / n
bar_w = 48
bar_gap = 14
series = [(risk_reduction, COL_RISK), (investment_cost, COL_COST), (investment_value, COL_VALUE)]
line_pts = []

for i, method in enumerate(methods):
    cx = plot_left + group_w * (i + 0.5)
    start_x = cx - (3 * bar_w + 2 * bar_gap) / 2

    for j, (vals, color) in enumerate(series):
        v = vals[i]
        x0 = start_x + j * (bar_w + bar_gap)
        x1 = x0 + bar_w
        y0 = y_money(v)
        d.rectangle([x0, y0, x1, plot_bottom], fill=color, outline=COL_AXIS, width=1)

        lab = f"{v:,.0f}"
        bbox = d.textbbox((0, 0), lab, font=font_tiny)
        d.text((x0 + bar_w / 2 - (bbox[2] - bbox[0]) / 2, y0 - 28), lab, fill=COL_TEXT, font=font_tiny)

    bbox = d.textbbox((0, 0), method, font=font_small)
    d.text((cx - (bbox[2] - bbox[0]) / 2, plot_bottom + 22), method, fill=COL_TEXT, font=font_small)
    line_pts.append((cx, y_eff(investment_eff[i])))


# 점선 라인
for (x0, y0), (x1, y1) in zip(line_pts[:-1], line_pts[1:]):
    dx, dy = x1 - x0, y1 - y0
    dist = math.hypot(dx, dy)
    dash, gap = 18, 12
    ux, uy = dx / dist, dy / dist
    cur = 0
    while cur < dist:
        end = min(cur + dash, dist)
        d.line([x0 + ux * cur, y0 + uy * cur, x0 + ux * end, y0 + uy * end], fill=COL_LINE, width=4)
        cur += dash + gap


for (x, y), v in zip(line_pts, investment_eff):
    d.ellipse([x - 8, y - 8, x + 8, y + 8], fill=COL_LINE, outline=COL_LINE)
    lab = f"{v:.2f}"
    bbox = d.textbbox((0, 0), lab, font=font_label)
    d.text((x - (bbox[2] - bbox[0]) / 2, y - 42), lab, fill=COL_LINE, font=font_label)


# x축 제목
xlabel = "최적화 기법"
bbox = d.textbbox((0, 0), xlabel, font=font_bold)
d.text((plot_left + plot_w / 2 - (bbox[2] - bbox[0]) / 2, H - 120), xlabel, fill=COL_TEXT, font=font_bold)


img.save(PNG_PATH, quality=95)


# SVG도 함께 생성: 한글 텍스트 편집 가능
svg = []
svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
svg.append('<rect width="100%" height="100%" fill="white"/>')
svg.append(f'<rect x="70" y="55" width="{W - 140}" height="{H - 125}" fill="none" stroke="{COL_AXIS}" stroke-width="2"/>')
svg.append(f'<rect x="{plot_left}" y="{plot_top}" width="{plot_w}" height="{plot_h}" fill="none" stroke="{COL_AXIS}" stroke-width="2"/>')

for tick in money_ticks:
    y = y_money(tick)
    label = "-" if tick == 0 else f"{tick:,}"
    svg.append(f'<line x1="{plot_left}" y1="{y:.1f}" x2="{plot_right}" y2="{y:.1f}" stroke="{COL_GRID}" stroke-width="1"/>')
    svg.append(f'<text x="{plot_left - 20}" y="{y + 8:.1f}" text-anchor="end" font-family="Malgun Gothic" font-size="24" fill="{COL_TEXT}">{label}</text>')

for tick in eff_ticks:
    y = y_eff(tick)
    svg.append(f'<text x="{plot_right + 18}" y="{y + 8:.1f}" font-family="Malgun Gothic" font-size="24" fill="{COL_LINE}">{tick:.1f}</text>')

svg.append(f'<text x="54" y="{plot_top + plot_h / 2}" transform="rotate(-90 54 {plot_top + plot_h / 2})" text-anchor="middle" font-family="Malgun Gothic" font-size="30" font-weight="700" fill="{COL_TEXT}">{left_label}</text>')
svg.append(f'<text x="{W - 48}" y="{plot_top + plot_h / 2}" transform="rotate(90 {W - 48} {plot_top + plot_h / 2})" text-anchor="middle" font-family="Malgun Gothic" font-size="30" font-weight="700" fill="{COL_LINE}">{right_label}</text>')

legend_x = plot_left + 210
legend_y = 75
for name, color, kind in legend_items:
    if kind == "bar":
        svg.append(f'<rect x="{legend_x}" y="{legend_y + 3}" width="32" height="20" fill="{color}" stroke="{COL_AXIS}" stroke-width="1"/>')
        text_color = COL_TEXT
    else:
        svg.append(f'<line x1="{legend_x}" y1="{legend_y + 13}" x2="{legend_x + 34}" y2="{legend_y + 13}" stroke="{color}" stroke-width="4"/>')
        svg.append(f'<circle cx="{legend_x + 20}" cy="{legend_y + 13}" r="7" fill="{color}"/>')
        text_color = COL_LINE
    svg.append(f'<text x="{legend_x + 42}" y="{legend_y + 20}" font-family="Malgun Gothic" font-size="24" fill="{text_color}">{html.escape(name)}</text>')
    legend_x += 235

for i, method in enumerate(methods):
    cx = plot_left + group_w * (i + 0.5)
    start_x = cx - (3 * bar_w + 2 * bar_gap) / 2
    for j, (vals, color) in enumerate(series):
        v = vals[i]
        x0 = start_x + j * (bar_w + bar_gap)
        y0 = y_money(v)
        height = plot_bottom - y0
        svg.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{bar_w}" height="{height:.1f}" fill="{color}" stroke="{COL_AXIS}" stroke-width="1"/>')
        svg.append(f'<text x="{x0 + bar_w / 2:.1f}" y="{y0 - 9:.1f}" text-anchor="middle" font-family="Malgun Gothic" font-size="21" fill="{COL_TEXT}">{v:,.0f}</text>')
    svg.append(f'<text x="{cx:.1f}" y="{plot_bottom + 55}" text-anchor="middle" font-family="Malgun Gothic" font-size="24" fill="{COL_TEXT}">{html.escape(method)}</text>')

points_str = " ".join([f"{x:.1f},{y:.1f}" for x, y in line_pts])
svg.append(f'<polyline points="{points_str}" fill="none" stroke="{COL_LINE}" stroke-width="4" stroke-dasharray="18 12" stroke-linecap="round"/>')

for (x, y), v in zip(line_pts, investment_eff):
    svg.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="8" fill="{COL_LINE}"/>')
    svg.append(f'<text x="{x:.1f}" y="{y - 25:.1f}" text-anchor="middle" font-family="Malgun Gothic" font-size="24" font-weight="700" fill="{COL_LINE}">{v:.2f}</text>')

svg.append(f'<text x="{plot_left + plot_w / 2}" y="{H - 112}" text-anchor="middle" font-family="Malgun Gothic" font-size="30" font-weight="700" fill="{COL_TEXT}">{xlabel}</text>')
svg.append("</svg>")
SVG_PATH.write_text("\n".join(svg), encoding="utf-8")

print(PNG_PATH)
print(SVG_PATH)
