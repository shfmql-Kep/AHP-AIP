# -*- coding: utf-8 -*-
"""IAM 원본 Figure 6 위에 한글 번역 라벨을 덮어쓴 그림을 생성한다."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math


PAGE_IMAGE = Path("tmp/iam_page-032.png")
OUT_DIR = Path("figures/source")
OUT_DIR.mkdir(parents=True, exist_ok=True)

FONT_PATH = Path("C:/Windows/Fonts/malgun.ttf")
BOLD_PATH = Path("C:/Windows/Fonts/malgunbd.ttf")


def font(size, bold=False):
    return ImageFont.truetype(str(BOLD_PATH if bold else FONT_PATH), size)


def center_text(draw, xy, text, fnt, fill="white", line_gap=6):
    x1, y1, x2, y2 = xy
    lines = text.split("\n")
    heights = []
    widths = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=fnt)
        widths.append(bbox[2] - bbox[0])
        heights.append(bbox[3] - bbox[1])
    total_h = sum(heights) + line_gap * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, w, h in zip(lines, widths, heights):
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + line_gap


def cover_and_text(draw, xy, text, color, fnt, fill="white", radius=0, pad=0):
    x1, y1, x2, y2 = xy
    box = (x1 - pad, y1 - pad, x2 + pad, y2 + pad)
    if radius > 0:
        draw.rounded_rectangle(box, radius=radius, fill=color)
    else:
        draw.rectangle(box, fill=color)
    center_text(draw, box, text, fnt, fill)


def simple_arrow(draw, start, end, color, width=20, head=38):
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


def draw_lifecycle_overlay(draw, cx, cy, r):
    """원본 생애주기 원형부의 영어 라벨을 덮기 위해 원형부를 다시 그린다."""
    colors = ["#0f6fb3", "#3d7fbd", "#5f95ca", "#8fb0d7"]
    starts = [-52, 38, 128, 218]
    for start, color in zip(starts, colors):
        draw.pieslice((cx - r, cy - r, cx + r, cy + r), start, start + 84, fill=color)

    # 원형 흐름을 강조하는 화살촉
    arrow_shapes = [
        [(cx + 10, cy - r - 22), (cx + 88, cy - r + 58), (cx - 5, cy - r + 72)],
        [(cx + r + 22, cy + 5), (cx + r - 58, cy + 88), (cx + r - 72, cy - 5)],
        [(cx - 10, cy + r + 22), (cx - 88, cy + r - 58), (cx + 5, cy + r - 72)],
        [(cx - r - 22, cy - 5), (cx - r + 58, cy - 88), (cx - r + 72, cy + 5)],
    ]
    for pts, color in zip(arrow_shapes, colors):
        draw.polygon(pts, fill=color)

    draw.ellipse((cx - 80, cy - 80, cx + 80, cy + 80), fill="white")
    center_text(draw, (cx - 80, cy - 62, cx + 80, cy + 62), "생애주기\n실행", font(25, True), fill="#333333", line_gap=4)

    labels = [
        ("취득", cx - 100, cy - 95),
        ("운영", cx + 105, cy - 35),
        ("유지관리", cx + 70, cy + 100),
        ("폐기", cx - 105, cy + 60),
    ]
    for label, x, y in labels:
        bbox = draw.textbbox((0, 0), label, font=font(21, False))
        draw.text((x - (bbox[2] - bbox[0]) / 2, y - (bbox[3] - bbox[1]) / 2), label, font=font(21, False), fill="white")


def rotated_label(base, xy, text):
    x1, y1, x2, y2 = xy
    label = Image.new("RGBA", (y2 - y1, x2 - x1), (255, 255, 255, 0))
    draw = ImageDraw.Draw(label)
    fnt = font(24, True)
    bbox = draw.textbbox((0, 0), text, font=fnt)
    draw.text(
        ((label.width - (bbox[2] - bbox[0])) / 2, (label.height - (bbox[3] - bbox[1])) / 2),
        text,
        font=fnt,
        fill="#333333",
    )
    label = label.rotate(90, expand=True)
    base.paste(label, (x1, y1), label)


def main():
    if not PAGE_IMAGE.exists():
        raise FileNotFoundError("tmp/iam_page-032.png 파일이 필요하다. IAM Anatomy PDF 32쪽을 먼저 렌더링해야 한다.")

    page = Image.open(PAGE_IMAGE).convert("RGB")
    # IAM Anatomy v4 32쪽의 Figure 6 영역만 크롭한다.
    img = page.crop((220, 1180, 1640, 2395)).convert("RGB")
    draw = ImageDraw.Draw(img)

    # 색상은 원본 Figure 6의 박스 색상에 맞춘 근사값이다.
    grey = "#a9a9ab"
    red = "#cf1728"
    orange = "#f5a414"
    green = "#59b82a"
    purple = "#5f2378"
    risk_orange = "#f04b18"
    magenta = "#c00064"

    # 상단 외부 요인
    cover_and_text(draw, (140, 24, 365, 130), "고객", grey, font(28, False), radius=10)
    cover_and_text(draw, (425, 24, 650, 130), "법·제도", grey, font(28, False), radius=10)
    cover_and_text(draw, (715, 24, 940, 130), "투자자", grey, font(28, False), radius=10)
    cover_and_text(draw, (985, 24, 1240, 130), "상업적\n환경", grey, font(25, False), radius=10)

    # 조직 전략계획
    cover_and_text(draw, (85, 190, 1250, 300), "조직 전략계획", grey, font(29, True), radius=10)

    # 자산관리 범위
    draw.rectangle((25, 210, 70, 600), fill="white")
    rotated_label(img, (25, 235, 65, 555), "자산관리 범위")

    # 주요 역량 박스
    cover_and_text(draw, (75, 405, 250, 995), "조직\n·\n인력", red, font(28, True))
    cover_and_text(draw, (310, 405, 600, 560), "전략·계획", orange, font(28, True))
    cover_and_text(draw, (310, 625, 600, 795), "자산관리\n의사결정", green, font(27, True))
    cover_and_text(draw, (310, 860, 1005, 1000), "자산정보", purple, font(28, True))
    cover_and_text(draw, (1080, 405, 1250, 995), "리스크\n검토", risk_orange, font(27, True))

    # 생애주기 원형 영역
    draw.rectangle((600, 350, 1060, 835), fill="white")
    simple_arrow(draw, (600, 480), (662, 480), "#fde1ad", width=26, head=42)
    simple_arrow(draw, (600, 710), (665, 650), "#cfe6bf", width=26, head=42)
    simple_arrow(draw, (820, 860), (820, 812), "#c5acd0", width=26, head=42)
    simple_arrow(draw, (1015, 640), (1075, 640), "#d9e2f3", width=26, head=42)
    draw_lifecycle_overlay(draw, 820, 615, 205)

    # 그림 내부 캡션
    draw.rectangle((0, 1125, img.width, 1215), fill="white")
    caption = "그림 6: IAM의 6-box 개념적 자산관리 모델"
    bbox = draw.textbbox((0, 0), caption, font=font(31, True))
    draw.text(((img.width - (bbox[2] - bbox[0])) / 2, 1162), caption, font=font(31, True), fill=magenta)

    # 한글 번역 표기
    note = "한글 번역: 본 연구"
    bbox = draw.textbbox((0, 0), note, font=font(18, False))
    draw.text((img.width - (bbox[2] - bbox[0]) - 210, 1090), note, font=font(18, False), fill="#555555")

    out = OUT_DIR / "fig_iam_6box_asset_management_model_ko_original.png"
    img.save(out, quality=96, optimize=True)
    print(f"생성 완료: {out}")


if __name__ == "__main__":
    main()
