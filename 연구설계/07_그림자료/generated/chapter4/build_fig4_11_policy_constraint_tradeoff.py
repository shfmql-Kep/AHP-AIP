from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html
import math


OUT_DIR = Path(__file__).resolve().parent
PNG_PATH = OUT_DIR / "fig4_11_policy_allocation_constraint_tradeoff.png"
SVG_PATH = OUT_DIR / "fig4_11_policy_allocation_constraint_tradeoff.svg"


# 통합형 ILP 기준 정책 제약 강도별 통합 PI 변화율(%)
count_levels = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]
count_pi_change = [-0.72, -1.33, -2.21, -3.60, -5.82, -10.71, -17.61, -27.39]
budget_levels = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
budget_pi_change = [-0.52, -1.07, -2.36, -6.51, -13.54, -21.98]


W, H = 1500, 900
left, top, right, bottom = 150, 110, 1370, 720
plot_w, plot_h = right - left, bottom - top

COL_AXIS = "#222222"
COL_GRID = "#D9D9D9"
COL_TEXT = "#111111"
COL_COUNT = "#ED7D31"
COL_BUDGET = "#5B9BD5"
COL_ZERO = "#666666"

font_regular = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 26)
font_small = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 22)
font_bold = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 28)
font_title = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 32)

img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)

d.rectangle([70, 60, W - 70, H - 70], outline=COL_AXIS, width=2)
d.rectangle([left, top, right, bottom], outline=COL_AXIS, width=2)

x_min, x_max = 1.0, 4.5
y_min, y_max = -30.0, 5.0


def x_pos(x):
    return left + (x - x_min) / (x_max - x_min) * plot_w


def y_pos(y):
    return bottom - (y - y_min) / (y_max - y_min) * plot_h


# y축 눈금
for y in [-30, -25, -20, -15, -10, -5, 0, 5]:
    py = y_pos(y)
    width = 2 if y == 0 else 1
    color = COL_ZERO if y == 0 else COL_GRID
    d.line([left, py, right, py], fill=color, width=width)
    label = f"{y:.0f}"
    bbox = d.textbbox((0, 0), label, font=font_small)
    d.text((left - 18 - (bbox[2] - bbox[0]), py - 12), label, fill=COL_TEXT, font=font_small)

# x축 눈금
for x in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]:
    px = x_pos(x)
    d.line([px, bottom, px, bottom + 8], fill=COL_AXIS, width=2)
    label = f"{x:.1f}"
    bbox = d.textbbox((0, 0), label, font=font_small)
    d.text((px - (bbox[2] - bbox[0]) / 2, bottom + 18), label, fill=COL_TEXT, font=font_small)


def draw_line(levels, values, color):
    pts = [(x_pos(x), y_pos(y)) for x, y in zip(levels, values)]
    for p0, p1 in zip(pts[:-1], pts[1:]):
        d.line([p0[0], p0[1], p1[0], p1[1]], fill=color, width=4)
    for x, y in pts:
        d.ellipse([x - 8, y - 8, x + 8, y + 8], fill=color, outline=color)
    return pts


count_pts = draw_line(count_levels, count_pi_change, COL_COUNT)
budget_pts = draw_line(budget_levels, budget_pi_change, COL_BUDGET)

# 주요 값 라벨
for x, y, txt in [
    (count_levels[4], count_pi_change[4], "-5.8%"),
    (count_levels[-1], count_pi_change[-1], "-27.4%"),
    (budget_levels[4], budget_pi_change[4], "-13.5%"),
    (budget_levels[-1], budget_pi_change[-1], "-22.0%"),
]:
    px, py = x_pos(x), y_pos(y)
    d.text((px + 10, py - 32), txt, fill=COL_TEXT, font=font_small)

# 범례
legend_x, legend_y = left + 250, 72
d.line([legend_x, legend_y + 15, legend_x + 48, legend_y + 15], fill=COL_COUNT, width=4)
d.ellipse([legend_x + 18, legend_y + 7, legend_x + 32, legend_y + 21], fill=COL_COUNT)
d.text((legend_x + 60, legend_y), "최소 물량 제약", fill=COL_TEXT, font=font_regular)

legend_x += 300
d.line([legend_x, legend_y + 15, legend_x + 48, legend_y + 15], fill=COL_BUDGET, width=4)
d.ellipse([legend_x + 18, legend_y + 7, legend_x + 32, legend_y + 21], fill=COL_BUDGET)
d.text((legend_x + 60, legend_y), "최소 투자 제약", fill=COL_TEXT, font=font_regular)

# 축 제목
xlabel = "정책 제약 수준 [%]"
bbox = d.textbbox((0, 0), xlabel, font=font_bold)
d.text((left + plot_w / 2 - (bbox[2] - bbox[0]) / 2, H - 125), xlabel, fill=COL_TEXT, font=font_bold)

ylabel = "통합 PI 변화율 [%]"
tmp = Image.new("RGBA", (300, 60), (255, 255, 255, 0))
td = ImageDraw.Draw(tmp)
td.text((0, 8), ylabel, fill=COL_TEXT, font=font_bold)
rot = tmp.rotate(90, expand=1)
img.paste(rot, (35, top + plot_h // 2 - rot.height // 2), rot)

# 주석
note = "기준: 정책 제약 없는 통합형 ILP"
d.text((left, H - 105), note, fill="#555555", font=font_small)

img.save(PNG_PATH, quality=95)


svg = []
svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
svg.append('<rect width="100%" height="100%" fill="white"/>')
svg.append(f'<rect x="70" y="60" width="{W-140}" height="{H-130}" fill="none" stroke="{COL_AXIS}" stroke-width="2"/>')
svg.append(f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" fill="none" stroke="{COL_AXIS}" stroke-width="2"/>')

for y in [-30, -25, -20, -15, -10, -5, 0, 5]:
    py = y_pos(y)
    width = 2 if y == 0 else 1
    color = COL_ZERO if y == 0 else COL_GRID
    svg.append(f'<line x1="{left}" y1="{py:.1f}" x2="{right}" y2="{py:.1f}" stroke="{color}" stroke-width="{width}"/>')
    svg.append(f'<text x="{left-18}" y="{py+8:.1f}" text-anchor="end" font-family="Malgun Gothic" font-size="22" fill="{COL_TEXT}">{y:.0f}</text>')

for x in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]:
    px = x_pos(x)
    svg.append(f'<line x1="{px:.1f}" y1="{bottom}" x2="{px:.1f}" y2="{bottom+8}" stroke="{COL_AXIS}" stroke-width="2"/>')
    svg.append(f'<text x="{px:.1f}" y="{bottom+45}" text-anchor="middle" font-family="Malgun Gothic" font-size="22" fill="{COL_TEXT}">{x:.1f}</text>')


def svg_poly(levels, values, color):
    pts = " ".join([f"{x_pos(x):.1f},{y_pos(y):.1f}" for x, y in zip(levels, values)])
    svg.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="4"/>')
    for x, y in zip(levels, values):
        svg.append(f'<circle cx="{x_pos(x):.1f}" cy="{y_pos(y):.1f}" r="8" fill="{color}"/>')


svg_poly(count_levels, count_pi_change, COL_COUNT)
svg_poly(budget_levels, budget_pi_change, COL_BUDGET)

for x, y, txt in [
    (count_levels[4], count_pi_change[4], "-5.8%"),
    (count_levels[-1], count_pi_change[-1], "-27.4%"),
    (budget_levels[4], budget_pi_change[4], "-13.5%"),
    (budget_levels[-1], budget_pi_change[-1], "-22.0%"),
]:
    svg.append(f'<text x="{x_pos(x)+10:.1f}" y="{y_pos(y)-14:.1f}" font-family="Malgun Gothic" font-size="22" fill="{COL_TEXT}">{html.escape(txt)}</text>')

legend_x, legend_y = left + 250, 72
svg.append(f'<line x1="{legend_x}" y1="{legend_y+15}" x2="{legend_x+48}" y2="{legend_y+15}" stroke="{COL_COUNT}" stroke-width="4"/>')
svg.append(f'<circle cx="{legend_x+25}" cy="{legend_y+15}" r="7" fill="{COL_COUNT}"/>')
svg.append(f'<text x="{legend_x+60}" y="{legend_y+24}" font-family="Malgun Gothic" font-size="26" fill="{COL_TEXT}">최소 물량 제약</text>')
legend_x += 300
svg.append(f'<line x1="{legend_x}" y1="{legend_y+15}" x2="{legend_x+48}" y2="{legend_y+15}" stroke="{COL_BUDGET}" stroke-width="4"/>')
svg.append(f'<circle cx="{legend_x+25}" cy="{legend_y+15}" r="7" fill="{COL_BUDGET}"/>')
svg.append(f'<text x="{legend_x+60}" y="{legend_y+24}" font-family="Malgun Gothic" font-size="26" fill="{COL_TEXT}">최소 투자 제약</text>')

svg.append(f'<text x="{left+plot_w/2}" y="{H-108}" text-anchor="middle" font-family="Malgun Gothic" font-size="28" font-weight="700" fill="{COL_TEXT}">{xlabel}</text>')
svg.append(f'<text x="58" y="{top+plot_h/2}" transform="rotate(-90 58 {top+plot_h/2})" text-anchor="middle" font-family="Malgun Gothic" font-size="28" font-weight="700" fill="{COL_TEXT}">{ylabel}</text>')
svg.append(f'<text x="{left}" y="{H-102}" font-family="Malgun Gothic" font-size="22" fill="#555555">{note}</text>')
svg.append("</svg>")

SVG_PATH.write_text("\n".join(svg), encoding="utf-8")
print(PNG_PATH)
print(SVG_PATH)
