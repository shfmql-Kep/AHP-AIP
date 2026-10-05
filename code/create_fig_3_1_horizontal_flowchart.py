from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "연구설계" / "07_그림자료"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PATH = OUT_DIR / "fig_3_1_horizontal_flowchart.png"


W, H = 3400, 1200
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)

NAVY = "#0B2A5B"
LIGHT_BLUE = "#EEF6FF"
LIGHT_BLUE2 = "#F6FAFF"
ORANGE = "#C86A00"
LIGHT_ORANGE = "#FFF6EA"
GREY = "#606060"
BLACK = "#111111"

FONT_PATH = r"C:\Windows\Fonts\malgunbd.ttf"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size=size)


F_TITLE = font(34)
F_SUB = font(22)
F_SMALL = font(20)
F_LABEL = font(24)
F_START = font(34)


def multiline_center(text, box, fnt, fill=BLACK, spacing=7):
    x1, y1, x2, y2 = box
    lines = text.split("\n")
    heights = []
    widths = []
    for line in lines:
        bb = d.textbbox((0, 0), line, font=fnt)
        widths.append(bb[2] - bb[0])
        heights.append(bb[3] - bb[1])
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2 - 2
    for line, h, w in zip(lines, heights, widths):
        x = x1 + (x2 - x1 - w) / 2
        d.text((x, y), line, font=fnt, fill=fill)
        y += h + spacing


def process_box(x, y, w, h, title, sub="", fill=LIGHT_BLUE):
    r = 22
    d.rounded_rectangle((x, y, x + w, y + h), radius=r, fill=fill, outline=NAVY, width=4)
    if sub:
        multiline_center(title, (x + 12, y + 16, x + w - 12, y + 65), F_TITLE)
        multiline_center(sub, (x + 12, y + 68, x + w - 12, y + h - 12), F_SUB)
    else:
        multiline_center(title, (x + 12, y + 10, x + w - 12, y + h - 10), F_START)


def terminal_box(x, y, w, h, text):
    d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill="white", outline=NAVY, width=4)
    multiline_center(text, (x, y, x + w, y + h), F_START)


def diamond(cx, cy, w, h, title, sub=""):
    pts = [(cx, cy - h // 2), (cx + w // 2, cy), (cx, cy + h // 2), (cx - w // 2, cy)]
    d.polygon(pts, fill=LIGHT_ORANGE, outline=ORANGE)
    d.line(pts + [pts[0]], fill=ORANGE, width=4, joint="curve")
    multiline_center(title, (cx - w // 2 + 20, cy - h // 2 + 26, cx + w // 2 - 20, cy + 8), F_TITLE)
    multiline_center(sub, (cx - w // 2 + 20, cy + 12, cx + w // 2 - 20, cy + h // 2 - 18), F_SMALL)


def arrow(x1, y1, x2, y2, color=NAVY, width=5):
    import math

    d.line((x1, y1, x2, y2), fill=color, width=width)
    ang = math.atan2(y2 - y1, x2 - x1)
    size = 20
    p1 = (
        x2 - size * math.cos(ang) + size * 0.55 * math.sin(ang),
        y2 - size * math.sin(ang) - size * 0.55 * math.cos(ang),
    )
    p2 = (
        x2 - size * math.cos(ang) - size * 0.55 * math.sin(ang),
        y2 - size * math.sin(ang) + size * 0.55 * math.cos(ang),
    )
    d.polygon([(x2, y2), p1, p2], fill=color)


def poly_arrow(points, color=NAVY, width=5):
    for a, b in zip(points[:-2], points[1:-1]):
        d.line((a[0], a[1], b[0], b[1]), fill=color, width=width)
    arrow(points[-2][0], points[-2][1], points[-1][0], points[-1][1], color=color, width=width)


box_w, box_h = 410, 130
term_w, term_h = 230, 70

# 1행: 기존 세로 그림의 상단 절차를 순서 그대로 가로 배치
row1_y = 90
row1 = [
    (90, row1_y, term_w, term_h, "시작", "", "terminal"),
    (400, row1_y - 25, box_w, box_h, "입력 데이터 구성", "PoF·CoF·Risk, 비용,\n고객영향, 전문가 설문", "process"),
    (900, row1_y - 25, box_w, box_h, "투자효과 지표 산정", "Risk 저감량, 투자가치,\nSAIDI, 안전·환경 영향", "process"),
    (1400, row1_y - 25, box_w, box_h, "다기준 PI 산정", "AHP 가중치, Fuzzy 보정,\n설비 단위 PI, 통합 PI", "process"),
    (1900, row1_y - 25, box_w, box_h, "후보군 및 투자대안 구성", "Risk·투자가치 상위 후보군,\n설비-연도 조합", "process"),
    (2400, row1_y - 25, box_w, box_h, "목적함수·제약조건 설정", "목적함수: 투자가치 / PI / 통합 PI", "process"),
]

for x, y, w, h, title, sub, typ in row1:
    if typ == "terminal":
        terminal_box(x, y, w, h, title)
    else:
        process_box(x, y, w, h, title, sub)

for i in range(len(row1) - 1):
    x1, y1, w1, h1 = row1[i][:4]
    x2, y2, w2, h2 = row1[i + 1][:4]
    arrow(x1 + w1 + 25, y1 + h1 // 2, x2 - 25, y2 + h2 // 2)

# 2행: 탐색 및 반복 구조
row2_y = 420
process_box(420, row2_y, box_w, box_h, "후보해 생성·탐색", "그리디, ILP, GA·NSGA")
diamond(1100, row2_y + box_h // 2, 430, 190, "제약조건 만족?", "예산·물량·최대 1회 교체")
process_box(1470, row2_y, box_w, box_h, "목적함수 값 평가", "실현가능해의 성과 비교")
process_box(1960, row2_y, box_w, box_h, "최고해 갱신", "목적함수 최대 해 저장")
diamond(2700, row2_y + box_h // 2, 430, 190, "종료조건 만족?", "최적성 gap / 세대 수 / 후보 검토")

poly_arrow([(2400 + box_w // 2, row1_y - 25 + box_h), (2400 + box_w // 2, 310), (625, 310), (625, row2_y - 10)])

arrow(420 + box_w + 18, row2_y + box_h // 2, 1100 - 215 - 12, row2_y + box_h // 2)
d.text((1325, row2_y + box_h // 2 + 42), "예", font=F_LABEL, fill=NAVY)
arrow(1100 + 215 + 30, row2_y + box_h // 2, 1470 - 30, row2_y + box_h // 2)
arrow(1470 + box_w + 30, row2_y + box_h // 2, 1960 - 30, row2_y + box_h // 2)
arrow(1960 + box_w + 30, row2_y + box_h // 2, 2700 - 215 - 30, row2_y + box_h // 2)

poly_arrow([(1100, row2_y - 95), (1100, 340), (625, 340), (625, row2_y - 8)], color=GREY, width=4)
d.text((970, 318), "아니오", font=F_LABEL, fill=GREY)

poly_arrow([(2700, row2_y + box_h // 2 + 95), (2700, 720), (625, 720), (625, row2_y + box_h + 8)], color=GREY, width=4)
d.text((1640, 688), "아니오", font=F_LABEL, fill=GREY)

# 3행: 결과 확정 및 분석
row3_y = 870
process_box(1080, row3_y, 470, box_h, "최적·준최적 포트폴리오 확정", "선택 설비 및 교체연도")
process_box(1780, row3_y, 470, box_h, "투자효과 비교 및 민감도 분석", "투자비용, Risk, 투자가치, SAIDI, PI")
terminal_box(2500, row3_y + 30, term_w, term_h, "종료")

poly_arrow([(2700, row2_y + box_h // 2 + 95), (2700, 810), (1315, 810), (1315, row3_y - 10)])
d.text((2575, 792), "예", font=F_LABEL, fill=NAVY)
arrow(1550 + 30, row3_y + box_h // 2, 1780 - 30, row3_y + box_h // 2)
arrow(2250 + 30, row3_y + box_h // 2, 2500 - 30, row3_y + box_h // 2)

img.save(OUT_PATH, quality=95)
print(OUT_PATH)
