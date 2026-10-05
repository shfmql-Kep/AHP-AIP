# -*- coding: utf-8 -*-
"""IAM Figure 6 구조를 유지한 깨끗한 한글 번역 복원본을 생성한다."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


OUT_DIR = Path("figures/source")
OUT_DIR.mkdir(parents=True, exist_ok=True)

FONT_PATH = Path("C:/Windows/Fonts/malgun.ttf")
BOLD_PATH = Path("C:/Windows/Fonts/malgunbd.ttf")


def font(size, bold=False):
    return ImageFont.truetype(str(BOLD_PATH if bold else FONT_PATH), size)


def center_text(draw, xy, lines, fonts, fills, gap=8):
    x1, y1, x2, y2 = xy
    if isinstance(lines, str):
        lines = lines.split("\n")
    if not isinstance(fonts, list):
        fonts = [fonts] * len(lines)
    if not isinstance(fills, list):
        fills = [fills] * len(lines)
    boxes = [draw.textbbox((0, 0), line, font=fnt) for line, fnt in zip(lines, fonts)]
    heights = [b[3] - b[1] for b in boxes]
    total_h = sum(heights) + gap * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, fnt, fill, box, h in zip(lines, fonts, fills, boxes, heights):
        w = box[2] - box[0]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + gap


def shadow_rect(draw, xy, fill, radius=0, outline=None, width=2, shadow=True):
    x1, y1, x2, y2 = xy
    if shadow:
        if radius:
            draw.rounded_rectangle((x1 + 12, y1 + 12, x2 + 12, y2 + 12), radius=radius, fill=(0, 0, 0, 34))
        else:
            draw.rectangle((x1 + 12, y1 + 12, x2 + 12, y2 + 12), fill=(0, 0, 0, 30))
    if radius:
        draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)
    else:
        draw.rectangle(xy, fill=fill, outline=outline, width=width)


def box(draw, xy, text, fill, text_fill="white", radius=0, fnt=None, shadow=True):
    shadow_rect(draw, xy, fill, radius=radius, shadow=shadow)
    center_text(draw, xy, text, fnt or font(34, True), text_fill, gap=10)


def arrow(draw, start, end, color, width=30, head=55):
    sx, sy = start
    ex, ey = end
    draw.line((sx, sy, ex, ey), fill=color, width=width)
    angle = math.atan2(ey - sy, ex - sx)
    pts = [
        (ex, ey),
        (ex - head * math.cos(angle - math.pi / 6), ey - head * math.sin(angle - math.pi / 6)),
        (ex - head * math.cos(angle + math.pi / 6), ey - head * math.sin(angle + math.pi / 6)),
    ]
    draw.polygon(pts, fill=color)


def dashed_round_rect(draw, xy, radius=14, outline="#4a4a4a", width=3, dash=12, gap=9):
    x1, y1, x2, y2 = xy
    # 배경 외곽은 얇은 실선으로 잡고, 그 위에 점선을 찍는다.
    draw.rounded_rectangle(xy, radius=radius, outline="#dddddd", width=width)
    for x in range(x1 + radius, x2 - radius, dash + gap):
        draw.line((x, y1, min(x + dash, x2 - radius), y1), fill=outline, width=width)
        draw.line((x, y2, min(x + dash, x2 - radius), y2), fill=outline, width=width)
    for y in range(y1 + radius, y2 - radius, dash + gap):
        draw.line((x1, y, x1, min(y + dash, y2 - radius)), fill=outline, width=width)
        draw.line((x2, y, x2, min(y + dash, y2 - radius)), fill=outline, width=width)


def vertical_label(base, xy, text):
    x1, y1, x2, y2 = xy
    label = Image.new("RGBA", (y2 - y1, x2 - x1), (255, 255, 255, 0))
    d = ImageDraw.Draw(label)
    fnt = font(30, True)
    b = d.textbbox((0, 0), text, font=fnt)
    d.text(((label.width - (b[2] - b[0])) / 2, (label.height - (b[3] - b[1])) / 2), text, font=fnt, fill="#3b3b3b")
    label = label.rotate(90, expand=True)
    base.paste(label, (x1, y1), label)


def lifecycle(draw, cx, cy, r):
    # 원본 Figure 6의 4단계 생애주기 흐름을 단순하고 선명하게 복원한다.
    colors = ["#0f6fae", "#3d7fbd", "#5f95ca", "#8fb0d7"]
    starts = [-50, 40, 130, 220]
    for start, color in zip(starts, colors):
        draw.pieslice((cx - r, cy - r, cx + r, cy + r), start, start + 83, fill=color)

    heads = [
        [(cx + 15, cy - r - 18), (cx + 96, cy - r + 62), (cx - 6, cy - r + 75)],
        [(cx + r + 18, cy + 15), (cx + r - 62, cy + 96), (cx + r - 75, cy - 6)],
        [(cx - 15, cy + r + 18), (cx - 96, cy + r - 62), (cx + 6, cy + r - 75)],
        [(cx - r - 18, cy - 15), (cx - r + 62, cy - 96), (cx - r + 75, cy + 6)],
    ]
    for pts, color in zip(heads, colors):
        draw.polygon(pts, fill=color)

    draw.ellipse((cx - 92, cy - 92, cx + 92, cy + 92), fill="white")
    center_text(draw, (cx - 92, cy - 78, cx + 92, cy + 78), "생애주기\n실행", font(30, True), "#333333", gap=4)

    labels = [
        ("취득", cx - 112, cy - 112),
        ("운영", cx + 112, cy - 40),
        ("유지관리", cx + 78, cy + 112),
        ("폐기", cx - 112, cy + 58),
    ]
    for text, x, y in labels:
        b = draw.textbbox((0, 0), text, font=font(25))
        draw.text((x - (b[2] - b[0]) / 2, y - (b[3] - b[1]) / 2), text, font=font(25), fill="white")


def main():
    w, h = 2200, 1500
    img = Image.new("RGB", (w, h), "white")
    draw = ImageDraw.Draw(img, "RGBA")

    # 원본 IAM Figure 6의 색감에 가까운 팔레트
    grey = "#a8a9ad"
    red = "#cf1728"
    orange = "#f4a313"
    green = "#57b52a"
    purple = "#5f2378"
    risk_orange = "#f04b18"
    magenta = "#c00064"

    # 상단 이해관계자
    for x, label in [(420, "고객"), (755, "법·제도"), (1090, "투자자"), (1425, "상업적\n환경")]:
        box(draw, (x - 130, 150, x + 130, 255), label, grey, radius=10, fnt=font(28))
        arrow(draw, (x, 255), (x, 325), "#c8c8c8", width=22, head=45)

    box(draw, (250, 330, 1880, 450), "조직 전략계획", grey, radius=10, fnt=font(34, True))
    arrow(draw, (720, 450), (720, 565), "#eeeeee", width=40, head=62)
    arrow(draw, (1690, 570), (1690, 475), "#f7c6a4", width=40, head=60)

    # 자산관리 범위
    scope = (175, 510, 1975, 1260)
    dashed_round_rect(draw, scope)
    vertical_label(img, (205, 680, 250, 1040), "자산관리 범위")

    # 주요 박스
    box(draw, (295, 650, 520, 1160), "조직\n·\n인력", red, fnt=font(32, True))
    box(draw, (610, 650, 960, 805), "전략·계획", orange, fnt=font(32, True))
    box(draw, (610, 875, 960, 1030), "자산관리\n의사결정", green, fnt=font(31, True))
    box(draw, (610, 1110, 1500, 1240), "자산정보", purple, fnt=font(32, True))
    box(draw, (1650, 650, 1875, 1160), "리스크\n검토", risk_orange, fnt=font(32, True))

    # 흐름 화살표
    arrow(draw, (520, 735), (605, 735), "#f3b7a7", width=28, head=42)
    arrow(draw, (520, 950), (605, 950), "#f3b7a7", width=28, head=42)
    arrow(draw, (520, 1178), (605, 1178), "#f3b7a7", width=28, head=42)
    arrow(draw, (960, 735), (1045, 735), "#fde1ad", width=28, head=42)
    arrow(draw, (960, 950), (1045, 885), "#cfe6bf", width=28, head=42)
    arrow(draw, (785, 875), (785, 815), "#cfe6bf", width=28, head=42)
    arrow(draw, (785, 1110), (785, 1040), "#c5acd0", width=28, head=42)
    arrow(draw, (1215, 1110), (1215, 1040), "#c5acd0", width=28, head=42)
    arrow(draw, (1500, 1175), (1645, 1175), "#d7c2df", width=34, head=48)
    arrow(draw, (1460, 945), (1645, 945), "#d8e2f3", width=34, head=48)
    arrow(draw, (1650, 735), (1555, 735), "#f7c6a4", width=34, head=48)

    lifecycle(draw, 1220, 870, 215)

    # 출처와 내부 캡션
    source = "© Copyright 2014 Institute of Asset Management (www.theIAM.org/copyright). 한글 번역: 본 연구."
    b = draw.textbbox((0, 0), source, font=font(24))
    draw.text(((w - (b[2] - b[0])) / 2, 1300), source, font=font(24), fill="#333333")

    caption = "그림 6: IAM의 6-box 개념적 자산관리 모델"
    b = draw.textbbox((0, 0), caption, font=font(38, True))
    draw.text(((w - (b[2] - b[0])) / 2, 1380), caption, font=font(38, True), fill=magenta)

    out = OUT_DIR / "fig_iam_6box_asset_management_model_ko_clean.png"
    img.save(out, quality=96, optimize=True)
    print(f"생성 완료: {out}")


if __name__ == "__main__":
    main()
