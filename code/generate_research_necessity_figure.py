from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def font(size: int, bold: bool = False):
    path = r"C:\Windows\Fonts\malgunbd.ttf" if bold else r"C:\Windows\Fonts\malgun.ttf"
    return ImageFont.truetype(path, size)


def text_center(draw, box, text, fnt, fill, spacing=6):
    x1, y1, x2, y2 = box
    lines = text.split("\n")
    heights = [draw.textbbox((0, 0), line, font=fnt)[3] for line in lines]
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, h in zip(lines, heights):
        bbox = draw.textbbox((0, 0), line, font=fnt)
        w = bbox[2] - bbox[0]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + spacing


def rounded_box(draw, box, fill, outline, width=3, radius=26):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def arrow(draw, start, end, color, width=8):
    x1, y1 = start
    x2, y2 = end
    draw.line((x1, y1, x2, y2), fill=color, width=width)
    # arrow head
    size = 18
    draw.polygon([(x2, y2), (x2 - size, y2 - size * 0.7), (x2 - size, y2 + size * 0.7)], fill=color)


def main():
    out = Path("figures/generated/fig_intro_research_necessity.png")
    out.parent.mkdir(parents=True, exist_ok=True)

    W, H = 2000, 1080
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)

    navy = (8, 33, 73)
    blue = (36, 101, 184)
    teal = (0, 112, 140)
    orange = (219, 112, 43)
    purple = (112, 72, 148)
    gray = (72, 78, 88)
    light_bg = (248, 251, 254)
    line = (196, 205, 218)

    title = font(56, True)
    subtitle = font(28)
    head = font(30, True)
    body = font(25)
    small = font(23)

    # title
    tb = d.textbbox((0, 0), "Research Necessity of Asset Investment Planning Framework", font=title)
    d.text(((W - (tb[2] - tb[0])) / 2, 45), "Research Necessity of Asset Investment Planning Framework", font=title, fill=navy)
    sb = d.textbbox((0, 0), "노후화·수요증가·탄소중립 투자 압박을 다기준 포트폴리오 의사결정 문제로 전환", font=subtitle)
    d.text(((W - (sb[2] - sb[0])) / 2, 125), "노후화·수요증가·탄소중립 투자 압박을 다기준 포트폴리오 의사결정 문제로 전환", font=subtitle, fill=gray)
    d.line((140, 190, W - 140, 190), fill=navy, width=4)

    # boxes
    y0, y1 = 265, 670
    boxes = [
        (105, y0, 495, y1),
        (590, y0, 980, y1),
        (1075, y0, 1465, y1),
        (1560, y0, 1950, y1),
    ]
    fills = [(242, 248, 255), (242, 252, 248), (255, 249, 241), (248, 244, 253)]
    outlines = [blue, teal, orange, purple]
    titles = ["투자 압박", "의사결정 제약", "기존 접근의 한계", "본 연구의 필요성"]
    bodies = [
        "노후 설비 교체\n전력수요 증가\n탄소중립 전력망 투자",
        "연도별 예산 제한\n시공능력 제한\n설비별 최대 1회 교체",
        "노후도·Risk 단일 기준\n설비군별 분리 판단\n다년 누적효과 미반영",
        "다기준 PI 산정\n이종설비 통합 비교\n5개년 투자계획 최적화",
    ]
    for box, fill, outline, t, b in zip(boxes, fills, outlines, titles, bodies):
        rounded_box(d, box, fill, outline)
        d.text((box[0] + 28, box[1] + 34), t, font=head, fill=outline)
        d.line((box[0] + 28, box[1] + 88, box[2] - 28, box[1] + 88), fill=line, width=2)
        text_center(d, (box[0] + 28, box[1] + 115, box[2] - 28, box[3] - 35), b, body, (40, 48, 58), spacing=13)

    for i in range(3):
        arrow(d, (boxes[i][2] + 20, (y0 + y1) / 2), (boxes[i + 1][0] - 22, (y0 + y1) / 2), navy)

    # bottom synthesis
    bottom = (220, 785, 1780, 950)
    rounded_box(d, bottom, (250, 252, 255), navy, width=3, radius=28)
    d.text((bottom[0] + 45, bottom[1] + 35), "핵심 연구문제", font=head, fill=navy)
    d.text(
        (bottom[0] + 300, bottom[1] + 34),
        "제한된 투자재원 아래 어떤 설비를, 어느 시점에 교체해야\nRisk·투자가치·신뢰도·안전환경 성과를 균형 있게 개선할 수 있는가?",
        font=body,
        fill=(32, 40, 52),
        spacing=10,
    )

    d.text((140, 1000), "자료: 본 연구 작성.", font=small, fill=gray)
    img.save(out, quality=96)


if __name__ == "__main__":
    main()
