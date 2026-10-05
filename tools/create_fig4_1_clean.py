from pathlib import Path
import math
import textwrap

from PIL import Image, ImageDraw, ImageFont


OUT = Path("figures/generated/chapter4/fig4_1_overall_simulation_procedure_clean.png")
OUT.parent.mkdir(parents=True, exist_ok=True)

W, H = 1800, 1050
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)

NAVY = (13, 43, 86)
BORDER = (10, 38, 78)
BLUE = (226, 239, 251)
ORANGE = (255, 238, 218)
GRAY = (238, 238, 238)
GREEN = (232, 247, 232)
PURPLE = (242, 231, 249)
YELLOW = (255, 248, 219)
WHITE = (250, 250, 250)
BLACK = (20, 20, 20)

font_candidates = [
    Path("C:/Windows/Fonts/batang.ttc"),
    Path("C:/Windows/Fonts/malgun.ttf"),
]
FONT_PATH = next((p for p in font_candidates if p.exists()), None)
if FONT_PATH is None:
    raise FileNotFoundError("사용 가능한 한글 글꼴을 찾지 못했습니다.")


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size)


F_TITLE = font(52)
F_BOX_TITLE = font(32)
F_TEXT = font(27)
F_TEXT_SMALL = font(25)


def rect(xy, fill, width=4):
    d.rounded_rectangle(xy, radius=0, fill=fill, outline=BORDER, width=width)


def center_text(text, box, fnt, fill=BLACK, line_gap=8, max_chars=None):
    x1, y1, x2, y2 = box
    lines = []
    for part in text.split("\n"):
        if max_chars and len(part) > max_chars:
            lines.extend(textwrap.wrap(part, width=max_chars))
        else:
            lines.append(part)

    dims = []
    for line in lines:
        bb = d.textbbox((0, 0), line, font=fnt)
        dims.append((bb[2] - bb[0], bb[3] - bb[1]))

    total_h = sum(h for _, h in dims) + line_gap * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_h) / 2
    for line, (w, h) in zip(lines, dims):
        d.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + line_gap


def left_text(title, items, box, title_font=F_BOX_TITLE, item_font=F_TEXT, fill=BLACK):
    x1, y1, x2, y2 = box
    bb = d.textbbox((0, 0), title, font=title_font)
    d.text((x1 + (x2 - x1 - (bb[2] - bb[0])) / 2, y1 + 18), title, font=title_font, fill=fill)
    y = y1 + 70
    for item in items:
        line = "• " + item
        d.text((x1 + 55, y), line, font=item_font, fill=fill)
        y += 38


def arrow(start, end, color=NAVY, width=5, head=18):
    x1, y1 = start
    x2, y2 = end
    if width > 0:
        d.line((x1, y1, x2, y2), fill=color, width=width)
    ang = math.atan2(y2 - y1, x2 - x1)
    pts = [(x2, y2)]
    for a in [ang - 0.55, ang + 0.55]:
        pts.append((x2 - head * math.cos(a), y2 - head * math.sin(a)))
    d.polygon(pts, fill=color)


def dashed_line(start, end, color=NAVY, width=3, dash=12, gap=8):
    x1, y1 = start
    x2, y2 = end
    dist = math.hypot(x2 - x1, y2 - y1)
    if dist == 0:
        return
    dx, dy = (x2 - x1) / dist, (y2 - y1) / dist
    t = 0
    while t < dist:
        t2 = min(t + dash, dist)
        d.line((x1 + dx * t, y1 + dy * t, x1 + dx * t2, y1 + dy * t2), fill=color, width=width)
        t += dash + gap


def dashed_down_arrow(x, y1, y2):
    dashed_line((x, y1), (x, y2), width=3)
    d.polygon([(x, y2), (x - 9, y2 - 15), (x + 9, y2 - 15)], fill=NAVY)


center_text("Overall Simulation Procedure", (0, 25, W, 95), F_TITLE)

# 상단 입력·후보·제약
box_in = (80, 125, 560, 345)
box_cand = (660, 125, 1140, 345)
box_const = (1240, 125, 1720, 345)
rect(box_in, BLUE)
rect(box_cand, ORANGE)
rect(box_const, GRAY)
left_text("입력 데이터", ["CNAIM 적용 데이터", "교체비용", "SAIDI", "PI 산정자료"], box_in)
left_text("후보군 구성", ["기준연도 Risk 상위 30%", "투자가치 상위 30%", "통합 후보군"], box_cand)
left_text("공통 제약조건", ["연도별 예산", "연도별 물량", "동일 설비 최대 1회 교체"], box_const)
arrow((560, 235), (660, 235))
arrow((1140, 235), (1240, 235))

# 3단계 시뮬레이션
stage_y1, stage_y2 = 445, 665
s1 = (80, stage_y1, 560, stage_y2)
s2 = (660, stage_y1, 1140, stage_y2)
s3 = (1240, stage_y1, 1720, stage_y2)
rect(s1, BLUE)
rect(s2, GREEN)
rect(s3, PURPLE)

center_text(
    "Stage 1: Risk·투자가치 기반\n포트폴리오 최적화\n\nRisk Greedy\nIV Greedy\nIV ILP\nIV GA",
    s1,
    F_TEXT_SMALL,
    max_chars=21,
)
center_text(
    "Stage 2: 설비 단위 PI 기반\n포트폴리오 최적화\n\nPI Greedy\nPI ILP\nPI GA",
    s2,
    F_TEXT_SMALL,
    max_chars=21,
)
center_text(
    "Stage 3: 통합 PI 기반 시스템 단위\n포트폴리오 최적화\n\n설비유형 가중치 적용\n통합 PI 기반 포트폴리오\n시스템 단위 성과 비교",
    s3,
    F_TEXT_SMALL,
    max_chars=23,
)

# 후보군·입력 흐름
arrow((320, 345), (320, 445))
arrow((900, 345), (900, 445))
arrow((560, 530), (660, 530), width=4, head=16)
arrow((1140, 530), (1240, 530), width=4, head=16)

# 공통 제약조건: 세 단계에 동일 적용
for target_x in [320, 900, 1480]:
    dashed_line((1480, 370), (target_x, 370), width=3)
    dashed_down_arrow(target_x, 370, 445)

# 민감도 및 강건성
sens = (80, 755, 1720, 855)
rect(sens, YELLOW)
center_text("민감도 및 강건성 검증\n예산, 물량, SAIDI, Risk 총량, 운영목표 가중치", sens, F_TEXT)
for x in [320, 900, 1480]:
    arrow((x, stage_y2), (x, 755), width=5, head=18)

# 최종 비교지표
final = (80, 915, 1720, 1000)
rect(final, WHITE)
center_text("최종 비교지표\n투자대수, 투자비용, Risk 저감량, 투자가치, SAIDI 저감량, PI", final, F_TEXT)
arrow((900, 855), (900, 915), width=5, head=18)

img.save(OUT, dpi=(300, 300))
print(OUT.resolve())
