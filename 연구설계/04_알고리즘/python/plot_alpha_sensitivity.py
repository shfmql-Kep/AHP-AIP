from __future__ import annotations

import base64
from pathlib import Path

import pandas as pd
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(r"C:\Users\shfmq\codexwork\AHP_AIP")
RESULT_FILE = (
    ROOT
    / "연구설계"
    / "06_시뮬레이션결과"
    / "알파민감도_통합PI"
    / "integrated_pi_alpha_sweep_20260628_114357"
    / "integrated_pi_alpha_sweep_results.xlsx"
)
OUTPUT_DIR = ROOT / "연구설계" / "07_그림자료" / "generated" / "chapter4"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SVG_FILE = OUTPUT_DIR / "fig4_alpha_sensitivity.svg"
PNG_FILE = OUTPUT_DIR / "fig4_alpha_sensitivity.png"
FONT_FILE = Path(
    r"C:\Users\shfmq\AppData\Local\Microsoft\Windows\Fonts\KoPub Dotum Bold.ttf"
)


def eok(value):
    """천원 단위를 억 원으로 변환한다."""
    return value / 100000.0


def fmt_num(value, decimals=0):
    if decimals == 0:
        return f"{value:,.0f}"
    return f"{value:,.{decimals}f}"


def polyline(points, color, width=5, dash=None):
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    d = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
    return (
        f'<polyline points="{d}" fill="none" stroke="{color}" '
        f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"{dash_attr}/>'
    )


def marker(x, y, shape, color, size=10):
    if shape == "circle":
        return f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{size}" fill="{color}" stroke="white" stroke-width="2"/>'
    if shape == "square":
        s = size * 1.7
        return f'<rect x="{x - s / 2:.2f}" y="{y - s / 2:.2f}" width="{s:.2f}" height="{s:.2f}" fill="{color}" stroke="white" stroke-width="2"/>'
    if shape == "triangle":
        s = size * 2.0
        pts = [
            (x, y - s / 2),
            (x - s / 2, y + s / 2),
            (x + s / 2, y + s / 2),
        ]
        p = " ".join(f"{px:.2f},{py:.2f}" for px, py in pts)
        return f'<polygon points="{p}" fill="{color}" stroke="white" stroke-width="2"/>'
    if shape == "diamond":
        s = size * 1.8
        pts = [(x, y - s / 2), (x + s / 2, y), (x, y + s / 2), (x - s / 2, y)]
        p = " ".join(f"{px:.2f},{py:.2f}" for px, py in pts)
        return f'<polygon points="{p}" fill="{color}" stroke="white" stroke-width="2"/>'
    raise ValueError(shape)


def text(x, y, value, size=15, anchor="middle", rotate=None, color="#000000"):
    rot = f' transform="rotate({rotate} {x:.2f} {y:.2f})"' if rotate else ""
    return (
        f'<text x="{x:.2f}" y="{y:.2f}" text-anchor="{anchor}" '
        f'font-size="{size}pt" fill="{color}"{rot}>{value}</text>'
    )


def line(x1, y1, x2, y2, color="#000000", width=2, dash=None):
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
        f'stroke="{color}" stroke-width="{width}"{dash_attr}/>'
    )


def legend(x, y, items):
    row_h = 42
    w = 330
    h = 28 + row_h * len(items)
    parts = [
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white" fill-opacity="0.86" stroke="#CFCFCF" stroke-width="2" rx="8"/>'
    ]
    for idx, item in enumerate(items):
        yy = y + 36 + idx * row_h
        parts.append(polyline([(x + 24, yy - 5), (x + 88, yy - 5)], item["color"], 5, item.get("dash")))
        parts.append(marker(x + 56, yy - 5, item["shape"], item["color"], 8))
        parts.append(text(x + 110, yy + 4, item["label"], 15, anchor="start"))
    return "\n".join(parts)


def draw_panel(panel, title, y_label, y_min, y_max, y_ticks, series, baseline_y=None):
    x0, y0, w, h = panel
    parts = []

    def sx(a):
        return x0 + (a - 0.0) / 1.0 * w

    def sy(v):
        return y0 + h - (v - y_min) / (y_max - y_min) * h

    parts.append(text(x0 + w / 2, y0 - 48, title, 20))

    # 격자와 축
    for t in y_ticks:
        y = sy(t)
        parts.append(line(x0, y, x0 + w, y, "#D9D9D9", 2, "6 5"))
        tick_label = f"{t:.2f}" if isinstance(t, float) and abs(t - round(t)) > 1e-9 else fmt_num(t)
        parts.append(text(x0 - 22, y + 8, tick_label, 15, anchor="end"))
    for a in [round(i * 0.1, 1) for i in range(11)]:
        x = sx(a)
        parts.append(line(x, y0, x, y0 + h, "#D9D9D9", 2, "6 5"))
        parts.append(text(x, y0 + h + 42, f"{a:.1f}", 15))

    parts.append(line(x0, y0, x0, y0 + h, "#000000", 3))
    parts.append(line(x0, y0 + h, x0 + w, y0 + h, "#000000", 3))
    parts.append(line(x0 + w, y0, x0 + w, y0 + h, "#000000", 2))
    parts.append(line(x0, y0, x0 + w, y0, "#000000", 2))

    if baseline_y is not None:
        parts.append(line(x0, sy(baseline_y), x0 + w, sy(baseline_y), "#888888", 3, "2 6"))
    parts.append(line(sx(0.5), y0, sx(0.5), y0 + h, "#777777", 3, "2 6"))

    for item in series:
        pts = [(sx(a), sy(v)) for a, v in zip(item["x"], item["y"])]
        parts.append(polyline(pts, item["color"], 5, item.get("dash")))
        for x, y in pts:
            parts.append(marker(x, y, item["shape"], item["color"], 8))

    parts.append(text(x0 + w / 2, y0 + h + 95, "α", 15))
    parts.append(text(x0 - 100, y0 + h / 2, y_label, 15, rotate=-90))
    parts.append(legend(x0 + 30, y0 + 30, series + ([{"label": "기준(α=0.5)", "color": "#777777", "shape": "circle", "dash": "2 6"}])))
    return "\n".join(parts)


df = pd.read_excel(RESULT_FILE, sheet_name="03_alpha_total").sort_values("alpha")
alpha = df["alpha"].to_list()
base = df.loc[(df["alpha"] - 0.5).abs() < 1e-9].iloc[0]

money_series = [
    {
        "label": "투자가치",
        "x": alpha,
        "y": [eok(v) for v in df["investment_value_kkrw"]],
        "color": "#1f77b4",
        "shape": "circle",
    },
]

saidi_series = [
    {
        "label": "SAIDI 저감",
        "x": alpha,
        "y": [v for v in df["saidi_reduction_sum_min"]],
        "color": "#d62728",
        "shape": "square",
    },
]

if FONT_FILE.exists():
    font_b64 = base64.b64encode(FONT_FILE.read_bytes()).decode("ascii")
    font_face = (
        "@font-face { font-family: 'KoPub Dotum Custom'; "
        f"src: url(data:font/ttf;base64,{font_b64}) format('truetype'); "
        "font-weight: 700; }"
    )
    font_family = "KoPub Dotum Custom"
else:
    font_face = ""
    font_family = "Malgun Gothic"

width, height = 3200, 1320
svg_parts = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
    "<defs><style>",
    font_face,
    f"text {{ font-family: '{font_family}', sans-serif; font-weight: 700; }}",
    "</style></defs>",
    '<rect width="100%" height="100%" fill="white"/>',
]

svg_parts.append(
    draw_panel(
        panel=(260, 150, 1150, 850),
        title="(a) α별 투자가치 민감도",
        y_label="금액 (억 원)",
        y_min=1100,
        y_max=1140,
        y_ticks=[1100, 1110, 1120, 1130, 1140],
        series=money_series,
    )
)
svg_parts.append(
    draw_panel(
        panel=(1850, 150, 1150, 850),
        title="(b) α별 SAIDI 저감 민감도",
        y_label="SAIDI 저감 (분)",
        y_min=0.74,
        y_max=0.87,
        y_ticks=[0.74, 0.77, 0.80, 0.83, 0.86],
        series=saidi_series,
    )
)

svg_parts.append("</svg>")
SVG_FILE.write_text("\n".join(svg_parts), encoding="utf-8")


def pil_font(size):
    if FONT_FILE.exists():
        return ImageFont.truetype(str(FONT_FILE), size=size)
    return ImageFont.load_default()


def draw_center(draw, xy, value, font, fill="#000000"):
    x, y = xy
    box = draw.textbbox((0, 0), value, font=font)
    draw.text((x - (box[2] - box[0]) / 2, y - (box[3] - box[1]) / 2), value, font=font, fill=fill)


def draw_right(draw, xy, value, font, fill="#000000"):
    x, y = xy
    box = draw.textbbox((0, 0), value, font=font)
    draw.text((x - (box[2] - box[0]), y - (box[3] - box[1]) / 2), value, font=font, fill=fill)


def draw_rotated_center(base, xy, value, font, angle=-90):
    tmp = Image.new("RGBA", (900, 120), (255, 255, 255, 0))
    td = ImageDraw.Draw(tmp)
    box = td.textbbox((0, 0), value, font=font)
    td.text(((900 - (box[2] - box[0])) / 2, (120 - (box[3] - box[1])) / 2), value, font=font, fill="#000000")
    rot = tmp.rotate(angle, expand=True)
    base.alpha_composite(rot, (int(xy[0] - rot.width / 2), int(xy[1] - rot.height / 2)))


def draw_dashed_line(draw, p1, p2, fill, width=3, dash=12, gap=8):
    x1, y1 = p1
    x2, y2 = p2
    length = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
    if length == 0:
        return
    dx = (x2 - x1) / length
    dy = (y2 - y1) / length
    pos = 0
    while pos < length:
        end = min(pos + dash, length)
        draw.line(
            (x1 + dx * pos, y1 + dy * pos, x1 + dx * end, y1 + dy * end),
            fill=fill,
            width=width,
        )
        pos += dash + gap


def draw_marker(draw, x, y, shape, color, size=11):
    if shape == "circle":
        draw.ellipse((x - size, y - size, x + size, y + size), fill=color, outline="white", width=2)
    elif shape == "square":
        draw.rectangle((x - size, y - size, x + size, y + size), fill=color, outline="white", width=2)
    elif shape == "triangle":
        draw.polygon([(x, y - size), (x - size, y + size), (x + size, y + size)], fill=color, outline="white")
    elif shape == "diamond":
        draw.polygon([(x, y - size), (x + size, y), (x, y + size), (x - size, y)], fill=color, outline="white")


def draw_legend(draw, x, y, items, title_font, label_font):
    row_h = 48
    w = 360
    h = 24 + row_h * len(items)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=10, fill=(255, 255, 255, 225), outline="#CFCFCF", width=2)
    for idx, item in enumerate(items):
        yy = y + 35 + idx * row_h
        if item.get("dash"):
            draw_dashed_line(draw, (x + 28, yy), (x + 92, yy), item["color"], width=5)
        else:
            draw.line((x + 28, yy, x + 92, yy), fill=item["color"], width=5)
        draw_marker(draw, x + 60, yy, item["shape"], item["color"], size=8)
        draw.text((x + 118, yy - 20), item["label"], font=label_font, fill="#000000")


def draw_png_panel(base, panel, title, y_label, y_min, y_max, y_ticks, series, baseline_y=None):
    draw = ImageDraw.Draw(base)
    x0, y0, w, h = panel
    title_font = pil_font(56)
    label_font = pil_font(42)
    tick_font = pil_font(40)
    legend_font = pil_font(40)

    def sx(a):
        return x0 + (a - 0.0) / 1.0 * w

    def sy(v):
        return y0 + h - (v - y_min) / (y_max - y_min) * h

    draw_center(draw, (x0 + w / 2, y0 - 55), title, title_font)

    for t in y_ticks:
        y = sy(t)
        draw_dashed_line(draw, (x0, y), (x0 + w, y), "#D9D9D9", width=2, dash=8, gap=7)
        tick_label = f"{t:.2f}" if isinstance(t, float) and abs(t - round(t)) > 1e-9 else fmt_num(t)
        draw_right(draw, (x0 - 25, y), tick_label, tick_font)
    for a in [round(i * 0.1, 1) for i in range(11)]:
        x = sx(a)
        draw_dashed_line(draw, (x, y0), (x, y0 + h), "#D9D9D9", width=2, dash=8, gap=7)
        draw_center(draw, (x, y0 + h + 52), f"{a:.1f}", tick_font)

    draw.line((x0, y0, x0, y0 + h, x0 + w, y0 + h), fill="#000000", width=4)
    draw.line((x0, y0, x0 + w, y0, x0 + w, y0 + h), fill="#000000", width=3)
    if baseline_y is not None:
        draw_dashed_line(draw, (x0, sy(baseline_y)), (x0 + w, sy(baseline_y)), "#888888", width=4, dash=4, gap=9)
    draw_dashed_line(draw, (sx(0.5), y0), (sx(0.5), y0 + h), "#777777", width=4, dash=4, gap=9)

    for item in series:
        pts = [(sx(a), sy(v)) for a, v in zip(item["x"], item["y"])]
        for p1, p2 in zip(pts[:-1], pts[1:]):
            if item.get("dash"):
                draw_dashed_line(draw, p1, p2, item["color"], width=6)
            else:
                draw.line((*p1, *p2), fill=item["color"], width=6)
        for x, y in pts:
            draw_marker(draw, x, y, item["shape"], item["color"], size=12)

    draw_center(draw, (x0 + w / 2, y0 + h + 115), "α", label_font)
    draw_rotated_center(base, (x0 - 175, y0 + h / 2), y_label, label_font)
    draw_legend(draw, x0 + 30, y0 + 30, series + [{"label": "기준(α=0.5)", "color": "#777777", "shape": "circle", "dash": "2 6"}], title_font, legend_font)


png = Image.new("RGBA", (width, height), "white")
draw_png_panel(
    png,
    panel=(260, 150, 1150, 850),
    title="(a) α별 투자가치 민감도",
    y_label="금액 (억 원)",
    y_min=1100,
    y_max=1140,
    y_ticks=[1100, 1110, 1120, 1130, 1140],
    series=money_series,
)
draw_png_panel(
    png,
    panel=(1850, 150, 1150, 850),
    title="(b) α별 SAIDI 저감 민감도",
    y_label="SAIDI 저감 (분)",
    y_min=0.74,
    y_max=0.87,
    y_ticks=[0.74, 0.77, 0.80, 0.83, 0.86],
    series=saidi_series,
)
png.convert("RGB").save(PNG_FILE, quality=95)

print(SVG_FILE)
print(PNG_FILE)
