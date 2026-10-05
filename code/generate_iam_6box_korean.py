# -*- coding: utf-8 -*-
"""IAM 6-box 개념적 자산관리 모델의 한글 번역 그림을 생성한다."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import html


OUT_DIR = Path("figures/source")
OUT_DIR.mkdir(parents=True, exist_ok=True)

FONT_PATH = Path("C:/Windows/Fonts/malgun.ttf")
BOLD_PATH = Path("C:/Windows/Fonts/malgunbd.ttf")


def font(size, bold=False):
    return ImageFont.truetype(str(BOLD_PATH if bold else FONT_PATH), size)


def text_box(draw, xy, text, fill, outline=None, radius=22, text_fill="white", fnt=None, width=0, align="center"):
    x1, y1, x2, y2 = xy
    shadow = (x1 + 12, y1 + 12, x2 + 12, y2 + 12)
    draw.rounded_rectangle(shadow, radius=radius, fill=(0, 0, 0, 45))
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

    fnt = fnt or font(30, True)
    lines = text.split("\n")
    line_heights = []
    widths = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=fnt)
        widths.append(bbox[2] - bbox[0])
        line_heights.append(bbox[3] - bbox[1])
    total_h = sum(line_heights) + 12 * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, h, w in zip(lines, line_heights, widths):
        if align == "center":
            x = x1 + (x2 - x1 - w) / 2
        else:
            x = x1 + 28
        draw.text((x, y), line, font=fnt, fill=text_fill)
        y += h + 12


def rect_box(draw, xy, text, fill, text_fill="white", fnt=None):
    x1, y1, x2, y2 = xy
    draw.rectangle((x1 + 10, y1 + 10, x2 + 10, y2 + 10), fill=(0, 0, 0, 35))
    draw.rectangle(xy, fill=fill)
    fnt = fnt or font(30, True)
    lines = text.split("\n")
    heights = [draw.textbbox((0, 0), line, font=fnt)[3] for line in lines]
    total_h = sum(heights) + 10 * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, h in zip(lines, heights):
        bbox = draw.textbbox((0, 0), line, font=fnt)
        w = bbox[2] - bbox[0]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=text_fill)
        y += h + 10


def arrow(draw, start, end, color, width=22, head=42):
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


def down_arrow(draw, x, y1, y2, color="#c9c9c9"):
    arrow(draw, (x, y1), (x, y2), color, width=18, head=44)


def draw_lifecycle(draw, cx, cy, r):
    colors = ["#0f76b8", "#2b8dc6", "#5b9bd5", "#8fb4d9"]
    start_angles = [-50, 40, 130, 220]
    labels = [
        ("취득/창출", cx - 95, cy - 115),
        ("운영", cx + 95, cy - 20),
        ("유지관리", cx + 50, cy + 105),
        ("폐기", cx - 120, cy + 25),
    ]

    for start, color in zip(start_angles, colors):
        draw.pieslice((cx - r, cy - r, cx + r, cy + r), start, start + 82, fill=color)
    draw.ellipse((cx - 82, cy - 82, cx + 82, cy + 82), fill="white")

    # 회전 흐름을 보이기 위한 화살촉
    arrow_points = [
        [(cx + 78, cy - 170), (cx + 145, cy - 120), (cx + 55, cy - 90)],
        [(cx + 178, cy + 62), (cx + 125, cy + 130), (cx + 100, cy + 40)],
        [(cx - 55, cy + 175), (cx - 130, cy + 120), (cx - 40, cy + 95)],
        [(cx - 175, cy - 55), (cx - 118, cy - 132), (cx - 90, cy - 38)],
    ]
    for pts, color in zip(arrow_points, colors):
        draw.polygon(pts, fill=color)

    center_font = font(25, True)
    bbox1 = draw.textbbox((0, 0), "생애주기", font=center_font)
    bbox2 = draw.textbbox((0, 0), "실행", font=center_font)
    draw.text((cx - (bbox1[2] - bbox1[0]) / 2, cy - 28), "생애주기", font=center_font, fill="#333333")
    draw.text((cx - (bbox2[2] - bbox2[0]) / 2, cy + 8), "실행", font=center_font, fill="#333333")

    label_font = font(22, False)
    for label, tx, ty in labels:
        bbox = draw.textbbox((0, 0), label, font=label_font)
        draw.text((tx - (bbox[2] - bbox[0]) / 2, ty - (bbox[3] - bbox[1]) / 2), label, font=label_font, fill="white")


def svg_rect(x, y, w, h, fill, text, text_color="white", rx=18, size=30, weight=700):
    lines = text.split("\n")
    text_parts = []
    base_y = y + h / 2 - (len(lines) - 1) * size * 0.65
    for i, line in enumerate(lines):
        text_parts.append(
            f'<tspan x="{x + w / 2}" dy="{0 if i == 0 else size * 1.25}">{html.escape(line)}</tspan>'
        )
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>\n'
        f'<text x="{x + w / 2}" y="{base_y}" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" '
        f'font-size="{size}" font-weight="{weight}" fill="{text_color}">' + "".join(text_parts) + "</text>"
    )


def save_svg():
    svg = """<svg xmlns="http://www.w3.org/2000/svg" width="2200" height="1500" viewBox="0 0 2200 1500">
<rect width="2200" height="1500" fill="white"/>
<text x="1100" y="90" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="46" font-weight="700" fill="#c00064">IAM의 6-box 개념적 자산관리 모델</text>
<rect x="230" y="405" width="1740" height="850" rx="10" fill="none" stroke="#555" stroke-width="3" stroke-dasharray="8 8"/>
<text x="260" y="825" transform="rotate(-90 260 825)" font-family="Malgun Gothic, Arial, sans-serif" font-size="26" font-weight="700" fill="#555">자산관리 범위</text>
""" 
    for x, label in [(455, "고객"), (785, "법·제도"), (1115, "투자자"), (1445, "상업적\n환경")]:
        svg += svg_rect(x - 125, 230, 250, 90, "#a8a9ad", label, "white", 12, 24)
        svg += f'<path d="M{x} 320 L{x} 390" stroke="#c8c8c8" stroke-width="16" marker-end="url(#arrowgray)"/>\n'
    svg += """<defs><marker id="arrowgray" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#c8c8c8"/></marker></defs>"""
    svg += svg_rect(310, 390, 1560, 105, "#a8a9ad", "조직 전략계획", "white", 10, 29)
    svg += svg_rect(310, 620, 220, 540, "#ce1b2a", "조직\n·\n사람", "white", 0, 27)
    svg += svg_rect(585, 620, 350, 125, "#f5a915", "전략·계획", "white", 0, 29)
    svg += svg_rect(585, 825, 350, 125, "#70ad47", "자산관리\n의사결정", "white", 0, 27)
    svg += svg_rect(585, 1040, 920, 125, "#6b287d", "자산정보", "white", 0, 29)
    svg += svg_rect(1590, 620, 220, 540, "#f15a24", "위험\n·\n검토", "white", 0, 29)
    svg += '<circle cx="1185" cy="820" r="160" fill="#1f7fbd"/><circle cx="1185" cy="820" r="77" fill="white"/>\n'
    svg += '<text x="1185" y="805" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="25" font-weight="700" fill="#333">생애주기</text><text x="1185" y="840" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="25" font-weight="700" fill="#333">실행</text>\n'
    svg += '<text x="1105" y="715" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="23" fill="white">취득/창출</text><text x="1290" y="745" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="23" fill="white">운영</text><text x="1260" y="930" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="23" fill="white">유지관리</text><text x="1075" y="900" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="23" fill="white">폐기/갱신</text>\n'
    svg += '<text x="1100" y="1300" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="26" fill="#333">© Copyright 2014 Institute of Asset Management (www.theIAM.org/copyright). 한글 번역: 본 연구.</text>\n'
    svg += '<text x="1100" y="1370" text-anchor="middle" font-family="Malgun Gothic, Arial, sans-serif" font-size="34" font-style="italic" font-weight="700" fill="#c00064">그림: IAM의 6-box 개념적 자산관리 모델</text>\n'
    svg += "</svg>"
    (OUT_DIR / "fig_iam_6box_asset_management_model_ko.svg").write_text(svg, encoding="utf-8")


def main():
    w, h = 2200, 1500
    img = Image.new("RGB", (w, h), "white")
    draw = ImageDraw.Draw(img, "RGBA")

    # 제목
    title = "IAM의 6-box 개념적 자산관리 모델"
    tb = draw.textbbox((0, 0), title, font=font(50, True))
    draw.text(((w - (tb[2] - tb[0])) / 2, 55), title, font=font(50, True), fill="#c00064")

    # 외부 이해관계자 및 환경
    for x, label in [(455, "고객"), (785, "법·제도"), (1115, "투자자"), (1445, "상업적\n환경")]:
        text_box(draw, (x - 130, 220, x + 130, 315), label, "#a8a9ad", radius=12, fnt=font(25, False))
        down_arrow(draw, x, 315, 390)

    # 조직 전략계획
    text_box(draw, (310, 390, 1870, 500), "조직 전략계획", "#a8a9ad", radius=10, fnt=font(31, True))
    down_arrow(draw, 760, 500, 615, "#ededed")
    arrow(draw, (1720, 620), (1720, 535), "#f6c7a6", width=32, head=55)

    # 자산관리 범위
    scope = (230, 540, 1970, 1255)
    draw.rounded_rectangle(scope, radius=10, outline="#555555", width=3)
    # 점선 느낌 보강
    for i in range(0, scope[2] - scope[0], 24):
        draw.line((scope[0] + i, scope[1], min(scope[0] + i + 12, scope[2]), scope[1]), fill="white", width=4)
        draw.line((scope[0] + i, scope[3], min(scope[0] + i + 12, scope[2]), scope[3]), fill="white", width=4)
    for i in range(0, scope[3] - scope[1], 24):
        draw.line((scope[0], scope[1] + i, scope[0], min(scope[1] + i + 12, scope[3])), fill="white", width=4)
        draw.line((scope[2], scope[1] + i, scope[2], min(scope[1] + i + 12, scope[3])), fill="white", width=4)
    draw.rounded_rectangle(scope, radius=10, outline="#555555", width=3)
    label_img = Image.new("RGBA", (220, 50), (255, 255, 255, 0))
    label_draw = ImageDraw.Draw(label_img)
    label_draw.text((110, 25), "자산관리 범위", font=font(25, True), fill="#555555", anchor="mm")
    label_img = label_img.rotate(90, expand=True)
    img.paste(label_img, (245, 760), label_img)

    # 주요 구성요소
    rect_box(draw, (310, 675, 530, 1165), "조직\n·\n인력", "#ce1b2a", fnt=font(27, True))
    rect_box(draw, (585, 675, 935, 805), "전략·계획", "#f5a915", fnt=font(30, True))
    rect_box(draw, (585, 875, 935, 1005), "자산관리\n의사결정", "#70ad47", fnt=font(28, True))
    rect_box(draw, (585, 1080, 1505, 1210), "자산정보", "#6b287d", fnt=font(30, True))
    rect_box(draw, (1590, 675, 1810, 1165), "리스크\n·\n검토", "#f15a24", fnt=font(30, True))

    # 구성요소 간 흐름
    arrow(draw, (530, 745), (580, 745), "#f4c7ad", width=24, head=42)
    arrow(draw, (530, 940), (580, 940), "#f4c7ad", width=24, head=42)
    arrow(draw, (530, 1140), (580, 1140), "#f4c7ad", width=24, head=42)
    arrow(draw, (935, 745), (1000, 745), "#fde1ad", width=24, head=42)
    arrow(draw, (935, 940), (1000, 875), "#cfe6bf", width=24, head=42)
    arrow(draw, (760, 1080), (760, 1010), "#cfe6bf", width=24, head=42)
    arrow(draw, (760, 875), (760, 810), "#e4d4ea", width=24, head=42)
    arrow(draw, (1185, 1080), (1185, 990), "#d9c7e2", width=24, head=42)
    arrow(draw, (1505, 1145), (1585, 1145), "#d9c7e2", width=30, head=45)

    # 생애주기 실행과 위험·검토 방향
    draw_lifecycle(draw, 1185, 860, 185)
    arrow(draw, (1375, 910), (1585, 910), "#d9e2f3", width=30, head=45)
    arrow(draw, (1585, 745), (1510, 745), "#fbd1b2", width=30, head=45)

    # 저작권 및 캡션
    copyright_text = "© Copyright 2014 Institute of Asset Management (www.theIAM.org/copyright). 한글 번역: 본 연구."
    cb = draw.textbbox((0, 0), copyright_text, font=font(22, False))
    draw.text(((w - (cb[2] - cb[0])) / 2, 1285), copyright_text, font=font(22, False), fill="#333333")
    caption = "그림: IAM의 6-box 개념적 자산관리 모델"
    capb = draw.textbbox((0, 0), caption, font=font(34, True))
    draw.text(((w - (capb[2] - capb[0])) / 2, 1360), caption, font=font(34, True), fill="#c00064")

    out = OUT_DIR / "fig_iam_6box_asset_management_model_ko.png"
    img.save(out, quality=96, optimize=True)
    save_svg()
    print(f"생성 완료: {out}")


if __name__ == "__main__":
    main()
