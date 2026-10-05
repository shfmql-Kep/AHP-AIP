from __future__ import annotations

from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "연구설계" / "07_그림자료" / "generated" / "chapter4"

FONT_REGULAR = Path("C:/Windows/Fonts/batang.ttc")
FONT_BOLD = Path("C:/Windows/Fonts/HANBatangB.ttf")

NAVY = "#0B2A5B"
BLUE = "#EAF2FF"
BLUE_LINE = "#2F80ED"
GREEN = "#EAF7F1"
GREEN_LINE = "#2FA66A"
ORANGE = "#FFF4E8"
ORANGE_LINE = "#F2994A"
PURPLE = "#F2EEFF"
PURPLE_LINE = "#7B61FF"
GRAY = "#F7F8FA"
GRAY_LINE = "#6B7280"
TEXT = "#111827"
SUBTEXT = "#6B7280"
LIGHT_LINE = "#CBD5E1"
CREAM = "#FFFDF4"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_BOLD if bold and FONT_BOLD.exists() else FONT_REGULAR
    return ImageFont.truetype(str(path), size)


def new_canvas(width: int = 2400, height: int = 1350) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    return image, draw


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont) -> tuple[int, int]:
    bbox = draw.multiline_textbbox((0, 0), text, font=fnt, spacing=8)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def center_text(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    text: str,
    size: int = 34,
    color: str = TEXT,
    bold: bool = False,
    spacing: int = 8,
) -> None:
    fnt = font(size, bold)
    w, h = text_size(draw, text, fnt)
    x0, y0, x1, y1 = box
    x = x0 + (x1 - x0 - w) / 2
    y = y0 + (y1 - y0 - h) / 2
    draw.multiline_text((x, y), text, font=fnt, fill=color, align="center", spacing=spacing)


def left_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    size: int = 30,
    color: str = TEXT,
    bold: bool = False,
    spacing: int = 7,
) -> None:
    draw.multiline_text(xy, text, font=font(size, bold), fill=color, spacing=spacing)


def round_box(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    fill: str,
    outline: str = NAVY,
    width: int = 4,
    radius: int = 28,
) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def diamond(
    draw: ImageDraw.ImageDraw,
    center: tuple[int, int],
    width: int,
    height: int,
    fill: str,
    outline: str = NAVY,
    line_width: int = 4,
) -> list[tuple[int, int]]:
    cx, cy = center
    pts = [(cx, cy - height // 2), (cx + width // 2, cy), (cx, cy + height // 2), (cx - width // 2, cy)]
    draw.polygon(pts, fill=fill)
    draw.line(pts + [pts[0]], fill=outline, width=line_width, joint="curve")
    return pts


def arrow(
    draw: ImageDraw.ImageDraw,
    start: tuple[int, int],
    end: tuple[int, int],
    color: str = NAVY,
    width: int = 6,
    head: int = 22,
) -> None:
    x0, y0 = start
    x1, y1 = end
    draw.line((x0, y0, x1, y1), fill=color, width=width)
    import math

    angle = math.atan2(y1 - y0, x1 - x0)
    left = (x1 - head * math.cos(angle - math.pi / 6), y1 - head * math.sin(angle - math.pi / 6))
    right = (x1 - head * math.cos(angle + math.pi / 6), y1 - head * math.sin(angle + math.pi / 6))
    draw.polygon([(x1, y1), left, right], fill=color)


def label_pill(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str, fill: str, outline: str) -> None:
    round_box(draw, box, fill, outline, width=3, radius=22)
    center_text(draw, box, text, size=25, color=outline, bold=True)


def save(image: Image.Image, filename: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    image.save(OUT_DIR / filename, dpi=(300, 300), quality=95)


def draw_fig4_1() -> None:
    image, draw = new_canvas()

    center_text(draw, (0, 40, 2400, 105), "최적화 시뮬레이션의 단계별 검증 구조", 48, NAVY, True)
    center_text(
        draw,
        (0, 110, 2400, 155),
        "동일 후보군과 제약조건 하에서 Risk·투자가치, 설비 단위 PI, 통합 PI의 투자효과를 순차 비교",
        28,
        SUBTEXT,
    )

    # 입력 및 후보군
    input_box = (110, 230, 560, 390)
    candidate_box = (765, 230, 1255, 390)
    constraint_box = (1785, 230, 2290, 390)
    round_box(draw, input_box, BLUE, NAVY)
    round_box(draw, candidate_box, ORANGE, ORANGE_LINE)
    round_box(draw, constraint_box, GRAY, GRAY_LINE)
    center_text(draw, (110, 245, 560, 295), "입력 데이터", 31, TEXT, True)
    center_text(draw, (130, 295, 540, 380), "CNAIM 적용 데이터\n교체비용 · SAIDI · PI 산출자료", 26, SUBTEXT)
    center_text(draw, (765, 245, 1255, 295), "후보군 구성", 31, TEXT, True)
    center_text(draw, (790, 295, 1230, 380), "기준연도 Risk 상위 30%\n투자가치 상위 30%의 합집합", 26, SUBTEXT)
    center_text(draw, (1785, 245, 2290, 295), "공통 제약조건", 31, TEXT, True)
    center_text(draw, (1810, 295, 2265, 380), "연도별 예산·물량\n동일 설비 최대 1회 교체", 26, SUBTEXT)
    arrow(draw, (560, 310), (765, 310))
    arrow(draw, (1255, 310), (1785, 310))

    # 단계별 분석
    stage_y0, stage_y1 = 545, 745
    boxes = [
        ((130, stage_y0, 660, stage_y1), BLUE, BLUE_LINE, "1단계", "Risk·투자가치 기반\n우선순위 및 최적화 비교", "Risk Greedy\nIV Greedy · ILP · GA"),
        ((935, stage_y0, 1465, stage_y1), GREEN, GREEN_LINE, "2단계", "설비 단위 PI 기반\n포트폴리오 최적화", "PI Greedy · ILP · GA\nIV ILP와 비교"),
        ((1740, stage_y0, 2270, stage_y1), PURPLE, PURPLE_LINE, "3단계", "통합 PI 기반\n시스템 단위 최적화", "설비유형 가중 적용\n통합 포트폴리오 구성"),
    ]
    for box, fill, line, step, main, sub in boxes:
        round_box(draw, box, fill, line, width=5, radius=32)
        label_pill(draw, (box[0] + 24, box[1] - 42, box[0] + 150, box[1] + 8), step, "white", line)
        center_text(draw, (box[0], box[1] + 18, box[2], box[1] + 95), main, 31, TEXT, True)
        center_text(draw, (box[0] + 20, box[1] + 105, box[2] - 20, box[3] - 18), sub, 25, SUBTEXT)
    arrow(draw, (660, 645), (935, 645))
    arrow(draw, (1465, 645), (1740, 645))
    arrow(draw, (1005, 390), (390, 545), color=GRAY_LINE, width=4, head=18)
    arrow(draw, (2035, 390), (2005, 545), color=GRAY_LINE, width=4, head=18)

    # 민감도 및 결과
    sensitivity = (360, 890, 2040, 1010)
    result = (570, 1120, 1830, 1235)
    round_box(draw, sensitivity, CREAM, ORANGE_LINE, width=4, radius=28)
    center_text(draw, sensitivity, "민감도 및 강건성 검증: 예산 · 물량 · SAIDI · Risk 총량 · 운영목표 가중치", 31, TEXT, True)
    for x in [395, 1200, 2005]:
        arrow(draw, (x, stage_y1), (x, 890), color=GRAY_LINE, width=4, head=18)
    round_box(draw, result, "white", NAVY, width=4, radius=26)
    center_text(draw, result, "최종 비교: 투자대수 · 투자비용 · Risk 저감량 · 투자가치 · SAIDI · PI", 31, TEXT, True)
    arrow(draw, (1200, 1010), (1200, 1120), color=NAVY, width=6)

    save(image, "fig4_1_overall_simulation_procedure.png")


def draw_fig4_4() -> None:
    image, draw = new_canvas()

    center_text(draw, (0, 45, 2400, 110), "다기준 성능지표(PI)의 계층 구조", 50, NAVY, True)
    center_text(draw, (0, 115, 2400, 155), "경제성·신뢰도·안전·환경 기준을 설비-연도별 표준화 점수로 통합", 27, SUBTEXT)

    top = (760, 210, 1640, 340)
    round_box(draw, top, "white", NAVY, width=5, radius=30)
    center_text(draw, top, "다기준 성능지표\nPI(i,t)", 34, TEXT, True)

    groups = [
        ((150, 470, 690, 610), BLUE, BLUE_LINE, "경제성\nW_E", [("투자가치", "w1"), ("투자효율", "w2")]),
        ((930, 470, 1470, 610), GREEN, GREEN_LINE, "신뢰도\nW_R", [("SAIDI 저감", "w3"), ("고장예측대수 저감", "w4")]),
        ((1710, 470, 2250, 610), ORANGE, ORANGE_LINE, "안전·환경\nW_S", [("안전 영향 저감", "w5"), ("환경 영향 저감", "w6")]),
    ]

    for box, fill, line, title, metrics in groups:
        round_box(draw, box, fill, line, width=5, radius=26)
        center_text(draw, box, title, 31, TEXT, True)
        arrow(draw, ((top[0] + top[2]) // 2, top[3]), ((box[0] + box[2]) // 2, box[1]), color=NAVY, width=5)
        y = 720
        for metric, weight in metrics:
            mbox = (box[0] + 40, y, box[2] - 40, y + 115)
            round_box(draw, mbox, "white", line, width=4, radius=18)
            center_text(draw, mbox, metric, 31, TEXT, True)
            circle_center = (box[2] - 70, y + 28)
            draw.ellipse(
                (circle_center[0] - 42, circle_center[1] - 42, circle_center[0] + 42, circle_center[1] + 42),
                fill=GRAY,
                outline=GRAY_LINE,
                width=3,
            )
            center_text(draw, (circle_center[0] - 42, circle_center[1] - 42, circle_center[0] + 42, circle_center[1] + 42), weight, 26, TEXT, True)
            arrow(draw, ((box[0] + box[2]) // 2, box[3]), ((box[0] + box[2]) // 2, y), color=line, width=4, head=16)
            y += 155

    formula = (575, 1105, 1825, 1215)
    round_box(draw, formula, GRAY, GRAY_LINE, width=4, radius=22)
    center_text(draw, formula, "PI(i,t) = Σ w_k × score_k(i,t)", 36, TEXT, True)
    center_text(draw, (0, 1230, 2400, 1285), "주: 전역가중치는 AHP 상대가중치와 Fuzzy 절대영향도 보정 결과를 결합하여 산정", 24, SUBTEXT)

    save(image, "fig4_4_asset_level_pi_weight_structure.png")


def draw_fig4_6() -> None:
    image, draw = new_canvas()

    center_text(draw, (0, 45, 2400, 110), "통합 PI 산정 및 시스템 포트폴리오 적용 절차", 50, NAVY, True)
    center_text(draw, (0, 115, 2400, 155), "설비 단위 PI에 설비유형 중요도와 비용 규모 보정을 결합하여 이종 설비를 단일 의사결정 공간에서 비교", 27, SUBTEXT)

    # 상단 입력 흐름
    boxes = [
        ((110, 260, 560, 430), BLUE, BLUE_LINE, "설비 단위 PI", "개별 설비의\n다기준 성능 점수"),
        ((705, 260, 1155, 430), GREEN, GREEN_LINE, "설비유형 가중치", "전문가 설문 기반\n설비군 상대 중요도"),
        ((1300, 260, 1750, 430), ORANGE, ORANGE_LINE, "비용 규모 보정", "유형별 교체비용 차이\nScale Factor 반영"),
        ((1895, 260, 2290, 430), PURPLE, PURPLE_LINE, "통합 PI", "PI × 유형가중치\n× 비용 보정"),
    ]
    for box, fill, line, title, subtitle in boxes:
        round_box(draw, box, fill, line, width=5, radius=30)
        center_text(draw, (box[0], box[1] + 15, box[2], box[1] + 70), title, 31, TEXT, True)
        center_text(draw, (box[0] + 20, box[1] + 78, box[2] - 20, box[3] - 20), subtitle, 25, SUBTEXT)
    for a, b in [((560, 345), (705, 345)), ((1155, 345), (1300, 345)), ((1750, 345), (1895, 345))]:
        arrow(draw, a, b)

    formula = (465, 535, 1935, 655)
    round_box(draw, formula, GRAY, GRAY_LINE, width=4, radius=24)
    center_text(draw, formula, "Integrated PI(i,t) = PI(i,t) × W*(a(i))     |     W* = f(전문가 가중치, 비용보정계수, α)", 30, TEXT, True)

    # 하단 적용 구조
    left = (260, 790, 980, 975)
    right = (1420, 790, 2140, 975)
    final = (620, 1110, 1780, 1230)
    round_box(draw, left, BLUE, NAVY, width=4, radius=26)
    center_text(draw, (left[0], left[1] + 18, left[2], left[1] + 76), "대표 방식: 사후 통합", 31, TEXT, True)
    center_text(draw, (left[0] + 35, left[1] + 88, left[2] - 35, left[3] - 18), "설비 단위 PI 포트폴리오 후보군을 구성한 뒤\n통합 PI 기준으로 시스템 포트폴리오 재선정", 25, SUBTEXT)

    round_box(draw, right, "white", GRAY_LINE, width=4, radius=26)
    center_text(draw, (right[0], right[1] + 18, right[2], right[1] + 76), "비교 시나리오: 사전 통합", 31, TEXT, True)
    center_text(draw, (right[0] + 35, right[1] + 88, right[2] - 35, right[3] - 18), "전체 후보군에 통합 PI를 먼저 산정한 뒤\n통합 PI 목적함수로 직접 최적화", 25, SUBTEXT)

    arrow(draw, (2092, 430), (1810, 535), color=PURPLE_LINE, width=5)
    arrow(draw, (1200, 655), (620, 790), color=NAVY, width=5)
    arrow(draw, (1200, 655), (1780, 790), color=GRAY_LINE, width=4)

    round_box(draw, final, CREAM, ORANGE_LINE, width=4, radius=28)
    center_text(draw, final, "결과 비교: 선택 설비유형 분포 · 통합 PI · SAIDI · Risk 저감량 · 투자가치", 31, TEXT, True)
    arrow(draw, ((left[0] + left[2]) // 2, left[3]), (950, 1110), color=NAVY, width=5)
    arrow(draw, ((right[0] + right[2]) // 2, right[3]), (1450, 1110), color=GRAY_LINE, width=4)

    center_text(draw, (0, 1260, 2400, 1305), "주: 본문 대표 결과는 설비 단위 PI 최적화 이후 설비유형 가중치를 적용하는 사후 통합 방식을 중심으로 해석", 24, SUBTEXT)

    save(image, "fig4_6_integrated_pi_calculation_procedure.png")


def main() -> None:
    draw_fig4_1()
    draw_fig4_4()
    draw_fig4_6()
    print(OUT_DIR)


if __name__ == "__main__":
    main()
