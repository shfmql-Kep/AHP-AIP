from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "연구설계" / "07_그림자료"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PATH = OUT_DIR / "slide_제안방법론_전체구조.png"

W, H = 1920, 1080
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)

NAVY = "#0B2A5B"
BLUE = "#1F5FA8"
LIGHT_BLUE = "#EEF6FF"
LIGHT_BLUE2 = "#DDEEFF"
CORE_BLUE = "#D7EAFB"
GREY = "#4D4D4D"
LIGHT_GREY = "#F4F6F8"
BLACK = "#111111"

FONT_BOLD = r"C:\Windows\Fonts\malgunbd.ttf"
FONT_REG = r"C:\Windows\Fonts\malgun.ttf"


def f(size, bold=False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size=size)


def text_center(text, box, font, fill=BLACK, spacing=6):
    x1, y1, x2, y2 = box
    lines = text.split("\n")
    dims = [d.textbbox((0, 0), line, font=font) for line in lines]
    widths = [bb[2] - bb[0] for bb in dims]
    heights = [bb[3] - bb[1] for bb in dims]
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2 - 2
    for line, w, h in zip(lines, widths, heights):
        x = x1 + (x2 - x1 - w) / 2
        d.text((x, y), line, font=font, fill=fill)
        y += h + spacing


def rounded_box(x, y, w, h, title, sub, fill=LIGHT_BLUE, edge=NAVY, width=4):
    d.rounded_rectangle((x, y, x + w, y + h), radius=24, fill=fill, outline=edge, width=width)
    text_center(title, (x + 15, y + 20, x + w - 15, y + 70), f(28, True), fill=BLACK)
    text_center(sub, (x + 15, y + 78, x + w - 15, y + h - 18), f(18), fill=GREY, spacing=4)


def arrow(x1, y1, x2, y2, color=NAVY, width=8):
    import math

    d.line((x1, y1, x2, y2), fill=color, width=width)
    ang = math.atan2(y2 - y1, x2 - x1)
    size = 24
    p1 = (
        x2 - size * math.cos(ang) + size * 0.55 * math.sin(ang),
        y2 - size * math.sin(ang) - size * 0.55 * math.cos(ang),
    )
    p2 = (
        x2 - size * math.cos(ang) - size * 0.55 * math.sin(ang),
        y2 - size * math.sin(ang) + size * 0.55 * math.cos(ang),
    )
    d.polygon([(x2, y2), p1, p2], fill=color)


# 상단 제목 영역
d.rectangle((0, 0, W, 112), fill="#F7FAFD")
d.rectangle((0, 108, W, 112), fill=NAVY)
d.text((92, 35), "제안 방법론의 전체 구조", font=f(46, True), fill=NAVY)

# 본문 3줄
bullet_x = 120
bullet_y = 165
bullets = [
    "산정된 리스크 정보를 투자가치, SAIDI, 안전·환경 지표로 전환",
    "AHP·Fuzzy 기반 다기준 투자우선순위 지수(PI) 산정",
    "예산·물량 제약 하에서 5개년 투자 포트폴리오 최적화 수행",
]
for i, line in enumerate(bullets):
    y = bullet_y + i * 54
    d.ellipse((bullet_x, y + 11, bullet_x + 14, y + 25), fill=BLUE)
    d.text((bullet_x + 30, y), line, font=f(30), fill=BLACK)

# 중앙 프로세스
box_y = 455
box_w = 285
box_h = 160
gap = 62
start_x = 120

steps = [
    ("리스크 정보", "PoF·CoF·Risk"),
    ("투자효과 평가", "투자가치·SAIDI\n안전·환경"),
    ("다기준 PI 산정", "AHP·Fuzzy\n가중치 반영"),
    ("포트폴리오\n최적화", "예산·물량 제약"),
    ("투자계획\n의사결정", "5개년 교체계획"),
]

for i, (title, sub) in enumerate(steps):
    x = start_x + i * (box_w + gap)
    fill = CORE_BLUE if i in (2, 3) else LIGHT_BLUE
    edge_width = 6 if i in (2, 3) else 4
    rounded_box(x, box_y, box_w, box_h, title, sub, fill=fill, width=edge_width)
    if i < len(steps) - 1:
        arrow(x + box_w + 12, box_y + box_h // 2, x + box_w + gap - 12, box_y + box_h // 2)

# 핵심 단계 강조 라벨
label_y = box_y + box_h + 34
d.rounded_rectangle((start_x + 2 * (box_w + gap) - 12, label_y, start_x + 4 * (box_w + gap) + box_w + 12, label_y + 48),
                    radius=18, fill="#EAF2FF", outline="#7BA7D8", width=2)
text_center("연구 핵심: 다기준 PI와 포트폴리오 최적화의 결합",
            (start_x + 2 * (box_w + gap) - 12, label_y, start_x + 4 * (box_w + gap) + box_w + 12, label_y + 48),
            f(23, True), fill=NAVY)

# 하단 메시지 바
bar_x, bar_y, bar_w, bar_h = 130, 840, 1660, 92
d.rounded_rectangle((bar_x, bar_y, bar_x + bar_w, bar_y + bar_h), radius=22,
                    fill=LIGHT_GREY, outline="#B7C2CC", width=2)
text_center("리스크 평가 결과를 투자계획 의사결정으로 연결하는 다기준 포트폴리오 최적화 절차",
            (bar_x + 30, bar_y, bar_x + bar_w - 30, bar_y + bar_h), f(27, True), fill=NAVY)

img.save(OUT_PATH, quality=95)
print(OUT_PATH)
