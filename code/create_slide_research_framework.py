from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "연구설계" / "07_그림자료"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_PATH = OUT_DIR / "slide_research_framework_pi_portfolio.png"

W, H = 2240, 980  # 16:7 비율
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)

FONT_BOLD = r"C:\Windows\Fonts\malgunbd.ttf"
FONT_REG = r"C:\Windows\Fonts\malgun.ttf"


def font(size: int, bold: bool = False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size=size)


NAVY = "#1A3F6F"
BLUE = "#4A7CC7"
LIGHT_BLUE = "#EBF2FF"
GREY_BG = "#F3F4F6"
GREY_BORDER = "#9CA3AF"
GREY_TEXT = "#374151"
GREY_MUTED = "#6B7280"
GREEN = "#059669"
GREEN_BG = "#F0FDF4"
GREEN_BORDER = "#6EE7B7"
WHITE = "#FFFFFF"
PALE_GREY = "#E5E7EB"
SLATE = "#CBD5E1"


def text_center(text, box, fnt, fill=GREY_TEXT, spacing=8):
    x1, y1, x2, y2 = box
    lines = text.split("\n")
    boxes = [d.textbbox((0, 0), line, font=fnt) for line in lines]
    widths = [b[2] - b[0] for b in boxes]
    heights = [b[3] - b[1] for b in boxes]
    total_h = sum(heights) + spacing * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, w, h in zip(lines, widths, heights):
        d.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + spacing


def rounded_box(x, y, w, h, fill, outline, radius=16, width=3):
    d.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=fill, outline=outline, width=width)


def badge(cx, cy, r, fill, text, text_fill=WHITE):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=fill)
    text_center(text, (cx - r, cy - r + 1, cx + r, cy + r + 1), font(24, True), text_fill)


def arrow(x1, y1, x2, y2, color=BLUE, width=7):
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


margin_x = 70
gap = 24
top_y = 140
block_h = 600
content_w = W - 2 * margin_x - 4 * gap

ratios = [0.15, 0.22, 0.22, 0.22, 0.19]
widths = [round(content_w * r) for r in ratios]
widths[-1] = content_w - sum(widths[:-1])
xs = [margin_x]
for i in range(1, 5):
    xs.append(xs[-1] + widths[i - 1] + gap)

# 상단 작은 제목
d.text((margin_x, 52), "제안 방법론의 연구 프레임워크", font=font(44, True), fill=NAVY)
d.line((margin_x, 110, W - margin_x, 110), fill=NAVY, width=4)

# 입력 블록
x, w = xs[0], widths[0]
rounded_box(x, top_y, w, block_h, GREY_BG, GREY_BORDER, radius=14, width=2)
text_center("입력", (x, top_y + 28, x + w, top_y + 74), font(23, True), GREY_MUTED)
text_center(
    "설비 데이터\n(CNAIM 기반)\n───────────\n리스크 정보\nPoF × CoF\n(시작점으로 활용)",
    (x + 18, top_y + 105, x + w - 18, top_y + block_h - 110),
    font(23),
    GREY_TEXT,
    spacing=12,
)
d.rounded_rectangle((x + 48, top_y + block_h - 75, x + w - 48, top_y + block_h - 35),
                    radius=17, fill=PALE_GREY)
text_center("입력값", (x + 48, top_y + block_h - 75, x + w - 48, top_y + block_h - 35),
            font(18, True), GREY_MUTED)

# 모듈 1
module_data = [
    {
        "num": "①",
        "title": "다기준 가중치 산정",
        "body": "AHP 쌍대비교\nFuzzy 보정 검증\n──────────────\n경제성 35.41%\n안전·환경 38.42%\n신뢰도 26.17%",
        "foot": "Slide D에서 상세",
        "fill": LIGHT_BLUE,
        "outline": BLUE,
        "dark": False,
    },
    {
        "num": "②",
        "title": "투자우선순위 지수 설계",
        "body": "설비단위 PI\n(6개 기준 가중합)\n↓\n통합 PI\n(PI × 설비유형 가중 × α)",
        "foot": "Slide E에서 상세",
        "fill": LIGHT_BLUE,
        "outline": BLUE,
        "dark": False,
    },
    {
        "num": "③",
        "title": "포트폴리오 최적화",
        "body": "통합형 ILP\n(intlinprog)\n──────────────\n목적: 투자가치 최대화\n제약: 예산·물량·KPI",
        "foot": "Slide F에서 상세",
        "fill": NAVY,
        "outline": NAVY,
        "dark": True,
    },
]

for idx, mod in enumerate(module_data, start=1):
    x, w = xs[idx], widths[idx]
    rounded_box(x, top_y, w, block_h, mod["fill"], mod["outline"], radius=18, width=4 if mod["dark"] else 3)
    badge_fill = WHITE if mod["dark"] else BLUE
    badge_text = NAVY if mod["dark"] else WHITE
    badge(x + w // 2, top_y + 48, 32, badge_fill, mod["num"], badge_text)
    title_color = WHITE if mod["dark"] else NAVY
    body_color = WHITE if mod["dark"] else GREY_TEXT
    foot_color = SLATE if mod["dark"] else BLUE
    text_center(mod["title"], (x + 20, top_y + 90, x + w - 20, top_y + 145), font(25, True), title_color)
    text_center(mod["body"], (x + 28, top_y + 168, x + w - 28, top_y + block_h - 92),
                font(22), body_color, spacing=12)
    text_center(mod["foot"], (x + 20, top_y + block_h - 70, x + w - 20, top_y + block_h - 35),
                font(18), foot_color)

# 출력 블록
x, w = xs[4], widths[4]
rounded_box(x, top_y, w, block_h, GREEN_BG, GREEN_BORDER, radius=14, width=2)
text_center("출력", (x, top_y + 28, x + w, top_y + 74), font(23, True), GREEN)
text_center(
    "5개년 투자계획\n(2026~2030)\n───────────\n246회\n민감도 분석",
    (x + 20, top_y + 120, x + w - 20, top_y + block_h - 100),
    font(24),
    GREY_TEXT,
    spacing=14,
)

# 화살표
mid_y = top_y + block_h // 2
for i in range(4):
    color = GREEN if i == 3 else BLUE
    arrow(xs[i] + widths[i] + 7, mid_y, xs[i + 1] - 7, mid_y, color=color)

# 하단 보조 레이블
label_y = top_y + block_h + 42
labels = {
    1: "AHP / Fuzzy / BWM",
    2: "설비단위 PI / 통합 PI",
    3: "통합형 / 후보제한형",
}
for idx, label in labels.items():
    x, w = xs[idx], widths[idx]
    text_center(label, (x, label_y, x + w, label_y + 32), font(18), GREY_BORDER)

# 캡션
caption = "Research Framework for Multi-Criteria PI-Based Portfolio Optimization"
text_center(caption, (0, H - 82, W, H - 42), font(22), GREY_MUTED)

img.save(OUT_PATH, quality=95)
print(OUT_PATH)
