# -*- coding: utf-8 -*-
"""논문 삽입용 개념도 PNG 생성 스크립트."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math
import textwrap
import html


OUT_DIR = Path("figures/generated")
OUT_DIR.mkdir(parents=True, exist_ok=True)

FONT_PATH = Path("C:/Windows/Fonts/malgun.ttf")
BOLD_PATH = Path("C:/Windows/Fonts/malgunbd.ttf")

FONT = ImageFont.truetype(str(FONT_PATH), 28)
FONT_S = ImageFont.truetype(str(FONT_PATH), 23)
FONT_XS = ImageFont.truetype(str(FONT_PATH), 19)
FONT_B = ImageFont.truetype(str(BOLD_PATH), 32)
FONT_SB = ImageFont.truetype(str(BOLD_PATH), 24)

BLUE = "#1f4e79"
LIGHT_BLUE = "#d9eaf7"
ORANGE = "#f4b183"
GREEN = "#d9ead3"
GRAY = "#f2f2f2"
DARK = "#222222"
LINE = "#4a4a4a"
WHITE = "#ffffff"


def hex_to_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def rounded_rect_with_shadow(draw, xy, radius, fill, outline=None, width=2, shadow=True):
    x1, y1, x2, y2 = xy
    if shadow:
        for i, alpha in enumerate([34, 22, 13]):
            offset = 10 + i * 5
            shadow_color = (36, 62, 89, alpha)
            draw.rounded_rectangle(
                (x1 + offset, y1 + offset, x2 + offset, y2 + offset),
                radius=radius,
                fill=shadow_color,
            )
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def center_text(draw, xy, lines, fonts, fills, line_gap=10):
    x1, y1, x2, y2 = xy
    if not isinstance(fonts, list):
        fonts = [fonts] * len(lines)
    if not isinstance(fills, list):
        fills = [fills] * len(lines)
    heights = [draw.textbbox((0, 0), line, font=font)[3] for line, font in zip(lines, fonts)]
    total_height = sum(heights) + line_gap * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_height) / 2
    for line, font, fill, height in zip(lines, fonts, fills, heights):
        bbox = draw.textbbox((0, 0), line, font=font)
        w = bbox[2] - bbox[0]
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=font, fill=fill)
        y += height + line_gap


def draw_poly_arrow(draw, points, color, width=5, head=20):
    draw.line(points, fill=color, width=width, joint="curve")
    sx, sy = points[-2]
    ex, ey = points[-1]
    angle = math.atan2(ey - sy, ex - sx)
    arrow_points = [
        (ex, ey),
        (ex - head * math.cos(angle - math.pi / 6), ey - head * math.sin(angle - math.pi / 6)),
        (ex - head * math.cos(angle + math.pi / 6), ey - head * math.sin(angle + math.pi / 6)),
    ]
    draw.polygon(arrow_points, fill=color)


def svg_text(x, y, lines, size=30, weight=400, fill="#1f2937", anchor="middle", gap=1.25):
    parts = [f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" font-weight="{weight}" fill="{fill}" font-family="Malgun Gothic, Apple SD Gothic Neo, Arial, sans-serif">']
    for i, line in enumerate(lines):
        dy = 0 if i == 0 else size * gap
        parts.append(f'<tspan x="{x}" dy="{dy}">{html.escape(line)}</tspan>')
    parts.append("</text>")
    return "\n".join(parts)


def save_asset_management_concept_svg():
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1350" viewBox="0 0 2400 1350">
<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="16" stdDeviation="16" flood-color="#12324f" flood-opacity="0.18"/>
  </filter>
  <linearGradient id="core" x1="0" x2="1" y1="0" y2="1">
    <stop offset="0%" stop-color="#eaf4fb"/>
    <stop offset="100%" stop-color="#d5e8f5"/>
  </linearGradient>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="10" markerHeight="10" orient="auto-start-reverse">
    <path d="M 0 0 L 10 5 L 0 10 z" fill="#245b89"/>
  </marker>
</defs>
<rect width="2400" height="1350" fill="#f8fafc"/>
<text x="120" y="105" font-size="54" font-weight="700" fill="#163f63" font-family="Malgun Gothic, Arial, sans-serif">ISO 55000·IAM 기반 자산관리 개념 구조</text>
<text x="120" y="160" font-size="28" fill="#64748b" font-family="Malgun Gothic, Arial, sans-serif">Asset management as value-oriented, risk-informed, whole-life decision-making</text>
<line x1="120" y1="195" x2="2280" y2="195" stroke="#163f63" stroke-width="5"/>

<rect x="825" y="390" width="750" height="310" rx="44" fill="url(#core)" stroke="#1f4e79" stroke-width="4" filter="url(#shadow)"/>
{svg_text(1200, 495, ["자산관리 의사결정"], 48, 700, "#0f2f4a")}
{svg_text(1200, 565, ["Asset Management Decision-making"], 34, 700, "#1f4e79")}
{svg_text(1200, 635, ["가치 · 위험 · 성능 · 비용의 균형"], 31, 500, "#334155")}

<rect x="875" y="245" width="650" height="90" rx="45" fill="#e7f3df" stroke="#4d7c32" stroke-width="3" filter="url(#shadow)"/>
{svg_text(1200, 302, ["가치 실현  Value Realization"], 31, 700, "#23421e")}
<path d="M1200 335 L1200 390" stroke="#245b89" stroke-width="5" marker-end="url(#arrow)"/>

<rect x="170" y="345" width="470" height="125" rx="30" fill="#ffffff" stroke="#245b89" stroke-width="3" filter="url(#shadow)"/>
{svg_text(405, 397, ["조직 목표 정렬", "Alignment"], 30, 700, "#163f63")}
<path d="M640 408 C720 420 760 442 825 490" stroke="#245b89" stroke-width="5" fill="none" marker-end="url(#arrow)"/>

<rect x="1760" y="345" width="470" height="125" rx="30" fill="#ffffff" stroke="#245b89" stroke-width="3" filter="url(#shadow)"/>
{svg_text(1995, 397, ["전생애주기 관점", "Whole-of-life"], 30, 700, "#163f63")}
<path d="M1760 408 C1680 420 1640 442 1575 490" stroke="#245b89" stroke-width="5" fill="none" marker-end="url(#arrow)"/>

<rect x="235" y="700" width="510" height="140" rx="32" fill="#fff1e6" stroke="#c4632f" stroke-width="3" filter="url(#shadow)"/>
{svg_text(490, 760, ["리스크·보증", "Risk & Assurance"], 30, 700, "#7c2d12")}
<path d="M745 770 C825 735 825 680 885 650" stroke="#245b89" stroke-width="5" fill="none" marker-end="url(#arrow)"/>

<rect x="1655" y="700" width="510" height="140" rx="32" fill="#fff1e6" stroke="#c4632f" stroke-width="3" filter="url(#shadow)"/>
{svg_text(1910, 760, ["정보·데이터 기반", "Information & Data"], 30, 700, "#7c2d12")}
<path d="M1655 770 C1575 735 1575 680 1515 650" stroke="#245b89" stroke-width="5" fill="none" marker-end="url(#arrow)"/>

<rect x="780" y="800" width="840" height="145" rx="34" fill="#fff7d6" stroke="#b7791f" stroke-width="4" filter="url(#shadow)"/>
{svg_text(1200, 858, ["AIP: 제한된 예산에서 가치·위험·성과를 균형화"], 32, 700, "#7c4a03")}
{svg_text(1200, 905, ["5개년 투자 포트폴리오 최적화"], 28, 500, "#7c4a03")}
<path d="M1200 700 L1200 800" stroke="#b7791f" stroke-width="6" marker-end="url(#arrow)"/>

<rect x="190" y="1035" width="2020" height="130" rx="34" fill="#eef6ff" stroke="#9bbbd4" stroke-width="2"/>
{svg_text(1200, 1092, ["본 연구 적용: 상태·PoF·CoF 데이터 → Risk·투자가치·PI 산정 → ILP·GA 기반 투자대상 선정"], 31, 700, "#1e3a5f")}
{svg_text(1200, 1140, ["자료: ISO 55000:2024 및 IAM Asset Management - An Anatomy v4를 바탕으로 본 연구 재구성"], 24, 400, "#64748b")}
</svg>'''
    (OUT_DIR / "fig_asset_management_concept_iso_iam.svg").write_text(svg, encoding="utf-8")


def text_size(draw, text, font):
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def wrap_text(text, width):
    lines = []
    for part in text.split("\n"):
        if len(part) <= width:
            lines.append(part)
        else:
            lines.extend(textwrap.wrap(part, width=width, break_long_words=False))
    return lines


def draw_box(draw, xy, text, fill, outline=BLUE, radius=18, font=None, color=DARK, width=2, wrap=12):
    font = font or FONT_S
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)
    lines = wrap_text(text, wrap)
    heights = [text_size(draw, line, font)[1] for line in lines]
    total_height = sum(heights) + 8 * (len(lines) - 1)
    y = y1 + (y2 - y1 - total_height) / 2
    for line, height in zip(lines, heights):
        w, _ = text_size(draw, line, font)
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=font, fill=color)
        y += height + 8


def draw_arrow(draw, start, end, color=LINE, width=4):
    draw.line([start, end], fill=color, width=width)
    sx, sy = start
    ex, ey = end
    angle = math.atan2(ey - sy, ex - sx)
    size = 13
    points = [
        (ex, ey),
        (ex - size * math.cos(angle - math.pi / 6), ey - size * math.sin(angle - math.pi / 6)),
        (ex - size * math.cos(angle + math.pi / 6), ey - size * math.sin(angle + math.pi / 6)),
    ]
    draw.polygon(points, fill=color)


def draw_title(draw, text):
    draw.text((50, 35), text, font=FONT_B, fill=BLUE)
    draw.line([(50, 85), (1550, 85)], fill=BLUE, width=3)


def save_asset_management_concept():
    save_asset_management_concept_svg()

    width, height = 2400, 1350
    img = Image.new("RGBA", (width, height), "#f8fafc")
    draw = ImageDraw.Draw(img, "RGBA")

    font_title = ImageFont.truetype(str(BOLD_PATH), 58)
    font_subtitle = ImageFont.truetype(str(FONT_PATH), 30)
    font_core_kr = ImageFont.truetype(str(BOLD_PATH), 52)
    font_core_en = ImageFont.truetype(str(BOLD_PATH), 36)
    font_core_desc = ImageFont.truetype(str(FONT_PATH), 32)
    font_card = ImageFont.truetype(str(BOLD_PATH), 32)
    font_card_small = ImageFont.truetype(str(FONT_PATH), 29)
    font_bottom = ImageFont.truetype(str(BOLD_PATH), 32)
    font_source = ImageFont.truetype(str(FONT_PATH), 24)

    for y in range(height):
        r1, g1, b1 = hex_to_rgb("#f8fafc")
        r2, g2, b2 = hex_to_rgb("#eef6fb")
        ratio = y / height
        color = (
            int(r1 + (r2 - r1) * ratio),
            int(g1 + (g2 - g1) * ratio),
            int(b1 + (b2 - b1) * ratio),
            255,
        )
        draw.line([(0, y), (width, y)], fill=color)

    draw.text((120, 70), "ISO 55000·IAM 기반 자산관리 개념 구조", font=font_title, fill="#163f63")
    draw.text((122, 132), "Asset management as value-oriented, risk-informed, whole-life decision-making", font=font_subtitle, fill="#64748b")
    draw.line([(120, 195), (2280, 195)], fill="#163f63", width=5)

    core = (825, 390, 1575, 700)
    rounded_rect_with_shadow(draw, core, 44, "#dff0fb", "#1f4e79", 4)
    center_text(
        draw,
        core,
        ["자산관리 의사결정", "Asset Management Decision-making", "가치 · 위험 · 성능 · 비용의 균형"],
        [font_core_kr, font_core_en, font_core_desc],
        ["#0f2f4a", "#1f4e79", "#334155"],
        18,
    )

    cards = [
        ((875, 245, 1525, 335), "#e7f3df", "#4d7c32", ["가치 실현  Value Realization"], "#23421e"),
        ((170, 345, 640, 470), "#ffffff", "#245b89", ["조직 목표 정렬", "Alignment"], "#163f63"),
        ((1760, 345, 2230, 470), "#ffffff", "#245b89", ["전생애주기 관점", "Whole-of-life"], "#163f63"),
        ((235, 700, 745, 840), "#fff1e6", "#c4632f", ["리스크·보증", "Risk & Assurance"], "#7c2d12"),
        ((1655, 700, 2165, 840), "#fff1e6", "#c4632f", ["정보·데이터 기반", "Information & Data"], "#7c2d12"),
    ]
    for xy, fill, outline, lines, text_color in cards:
        rounded_rect_with_shadow(draw, xy, 32, fill, outline, 3)
        center_text(draw, xy, lines, [font_card] + [font_card_small] * (len(lines) - 1), text_color, 12)

    arrow_color = "#245b89"
    draw_poly_arrow(draw, [(1200, 335), (1200, 390)], arrow_color, 5, 20)
    draw_poly_arrow(draw, [(640, 408), (720, 420), (760, 442), (825, 490)], arrow_color, 5, 20)
    draw_poly_arrow(draw, [(1760, 408), (1680, 420), (1640, 442), (1575, 490)], arrow_color, 5, 20)
    draw_poly_arrow(draw, [(745, 770), (825, 735), (825, 680), (885, 650)], arrow_color, 5, 20)
    draw_poly_arrow(draw, [(1655, 770), (1575, 735), (1575, 680), (1515, 650)], arrow_color, 5, 20)

    aip = (780, 800, 1620, 945)
    rounded_rect_with_shadow(draw, aip, 34, "#fff7d6", "#b7791f", 4)
    center_text(
        draw,
        aip,
        ["AIP: 제한된 예산에서 가치·위험·성과를 균형화", "5개년 투자 포트폴리오 최적화"],
        [font_bottom, font_card_small],
        ["#7c4a03", "#7c4a03"],
        14,
    )
    draw_poly_arrow(draw, [(1200, 700), (1200, 800)], "#b7791f", 6, 22)

    bottom = (190, 1035, 2210, 1165)
    rounded_rect_with_shadow(draw, bottom, 34, "#eef6ff", "#9bbbd4", 2, shadow=False)
    center_text(
        draw,
        bottom,
        [
            "본 연구 적용: 상태·PoF·CoF 데이터 → Risk·투자가치·PI 산정 → ILP·GA 기반 투자대상 선정",
            "자료: ISO 55000:2024 및 IAM Asset Management - An Anatomy v4를 바탕으로 본 연구 재구성",
        ],
        [font_bottom, font_source],
        ["#1e3a5f", "#64748b"],
        15,
    )

    img.convert("RGB").save(OUT_DIR / "fig_asset_management_concept_iso_iam.png", quality=96, optimize=True)


def save_research_framework():
    img = Image.new("RGB", (1600, 900), WHITE)
    draw = ImageDraw.Draw(img)
    draw_title(draw, "본 연구의 개념적 틀")

    cols = [
        ("문제 인식", "노후 배전설비 증가\n예산·물량 제약\n단일 Risk 우선순위 한계"),
        ("상태·위험도 산정", "CNAIM 기반 PoF\nCoF·Risk\nSAIDI·고장예측"),
        ("다기준 투자가치", "AHP 가중치\nFuzzy 보정\nPriority Number"),
        ("포트폴리오 최적화", "개별설비 최적화\n통합설비 최적화\nILP·GA 비교"),
        ("투자효과 평가", "Risk 저감량\n투자가치·투자효율\nSAIDI 개선"),
    ]

    x = 70
    previous = None
    for head, body in cols:
        draw_box(draw, (x, 180, x + 250, 285), head, BLUE, BLUE, 12, FONT_SB, WHITE, wrap=9)
        draw_box(draw, (x, 320, x + 250, 610), body, GRAY, BLUE, 16, FONT_S, wrap=11)
        if previous:
            draw_arrow(draw, (previous + 20, 455), (x - 20, 455), BLUE)
        previous = x + 250
        x += 300

    draw_box(
        draw,
        (450, 710, 1150, 810),
        "핵심 기여: 설비별 상태평가 결과를 5개년 투자 포트폴리오 의사결정으로 연결",
        "#e2f0d9",
        "#548235",
        20,
        FONT_S,
        wrap=34,
    )
    draw.text((70, 850), "자료: 본 연구 작성", font=FONT_XS, fill="#555555")
    img.save(OUT_DIR / "fig_research_framework.png")


def save_proposed_methodology():
    img = Image.new("RGB", (1700, 1050), WHITE)
    draw = ImageDraw.Draw(img)
    draw_title(draw, "제안 방법론의 전체 절차")

    steps = [
        ("입력자료", "자산 재원\n상태평가 입력\nCoF·고객수·복구시간"),
        ("CNAIM 산정", "HI/Health Score\nPoF 2026-2030\nRisk 산정"),
        ("후보지표", "Risk 저감량\n투자가치·BCR\nSAIDI·고장확률"),
        ("PI 산정", "AHP 상대가중치\nFuzzy 절대영향도 보정\nLocal PI"),
        ("최적화", "Risk/투자가치/PI\nILP·GA\n연도별 예산·물량 제약"),
        ("평가", "투자대수·비용\nRisk 저감량\n투자가치·SAIDI·PI"),
    ]

    x = 60
    for i, (head, body) in enumerate(steps):
        draw_box(draw, (x, 170, x + 240, 275), head, BLUE, BLUE, 12, FONT_SB, WHITE, wrap=9)
        draw_box(draw, (x, 315, x + 240, 640), body, "#f7f9fb", BLUE, 16, FONT_S, wrap=11)
        if i < len(steps) - 1:
            draw_arrow(draw, (x + 245, 475), (x + 295, 475), BLUE)
        x += 275

    draw_box(draw, (320, 760, 725, 900), "개별설비 최적화\n설비유형 내부 우선순위", "#d9ead3", "#548235", 18, FONT_S, wrap=16)
    draw_box(draw, (975, 760, 1380, 900), "통합설비 최적화\n설비유형 간 정규화·비교", "#fff2cc", "#bf9000", 18, FONT_S, wrap=17)
    draw_arrow(draw, (735, 830), (965, 830), "#666666")
    draw.text((65, 980), "자료: 본 연구 작성", font=FONT_XS, fill="#555555")
    img.save(OUT_DIR / "fig_proposed_methodology.png")


def save_asset_type_mapping():
    img = Image.new("RGB", (1600, 900), WHITE)
    draw = ImageDraw.Draw(img)
    draw_title(draw, "CNAIM 자산군과 본 연구 대상 설비 매핑")

    pairs = [
        ("HV Transformer (PM)", "주상변압기"),
        ("HV Transformer (GM)", "지상변압기"),
        ("HV Switchgear", "가공개폐기"),
        ("HV Switchgear", "지중개폐기"),
        ("OHL Conductor", "가공배전선로"),
        ("Underground Cable", "지중케이블"),
    ]
    for i, (cnaim, target) in enumerate(pairs):
        y = 150 + i * 105
        draw_box(draw, (120, y, 560, y + 70), cnaim, "#ddebf7", BLUE, 12, FONT_S, wrap=22)
        draw_box(draw, (1040, y, 1480, y + 70), target, "#e2f0d9", "#548235", 12, FONT_S, wrap=18)
        draw_arrow(draw, (570, y + 35), (1030, y + 35), BLUE)

    draw_box(draw, (635, 365, 965, 535), "국내 배전 주요 설비군으로\n분석 범위 단순화", "#fff2cc", "#bf9000", 16, FONT_S, wrap=16)
    draw.text((120, 820), "자료: CNAIM v2.1의 Health Index Asset Category 체계를 바탕으로 본 연구 적용 대상에 맞게 재구성", font=FONT_XS, fill="#555555")
    img.save(OUT_DIR / "fig_asset_type_mapping.png")


def save_pi_structure():
    img = Image.new("RGB", (1600, 950), WHITE)
    draw = ImageDraw.Draw(img)
    draw_title(draw, "Priority Number(PI) 산정 구조")

    criteria = [
        ("경제성", "투자가치\n투자효율"),
        ("신뢰도", "SAIDI 저감\n고장확률"),
        ("안전·환경", "CoF 안전\nCoF 환경"),
    ]
    for x, (head, body) in zip([170, 650, 1130], criteria):
        draw_box(draw, (x, 160, x + 300, 260), head, BLUE, BLUE, 15, FONT_SB, WHITE, wrap=10)
        draw_box(draw, (x, 300, x + 300, 470), body, GRAY, BLUE, 15, FONT_S, wrap=10)
        draw_arrow(draw, (x + 150, 470), (800, 620), BLUE)

    draw_box(draw, (560, 600, 1040, 720), "AHP 상대가중치 Wr\n+ Fuzzy 절대영향도 Wa", "#fff2cc", "#bf9000", 20, FONT_S, wrap=20)
    draw_arrow(draw, (800, 720), (800, 805), "#bf9000")
    draw_box(draw, (590, 805, 1010, 895), "Local PI / PI_통합\n최적화 목적함수로 활용", "#e2f0d9", "#548235", 18, FONT_S, wrap=18)
    draw.text((70, 920), "자료: 본 연구 작성", font=FONT_XS, fill="#555555")
    img.save(OUT_DIR / "fig_pi_structure.png")


def save_integrated_options():
    img = Image.new("RGB", (1600, 930), WHITE)
    draw = ImageDraw.Draw(img)
    draw_title(draw, "통합설비 최적화 비교 구조")

    draw_box(draw, (90, 150, 420, 260), "PoF_output\n개별 자산 후보군", GRAY, BLUE, 15, FONT_S, wrap=14)
    draw_box(draw, (620, 120, 980, 230), "A안: 사후 가중 방식\nPI 개별최적화 선택 후보", "#d9ead3", "#548235", 15, FONT_S, wrap=16)
    draw_box(draw, (620, 320, 980, 430), "B안: 사전 PI_통합 방식\n전체 후보에 유형가중 적용", "#fff2cc", "#bf9000", 15, FONT_S, wrap=17)
    draw_arrow(draw, (420, 205), (620, 175), BLUE)
    draw_arrow(draw, (420, 205), (620, 375), BLUE)
    draw_box(draw, (1170, 215, 1500, 340), "전체설비 기준\nILP·GA 포트폴리오 최적화", LIGHT_BLUE, BLUE, 15, FONT_S, wrap=16)
    draw_arrow(draw, (980, 175), (1170, 260), BLUE)
    draw_arrow(draw, (980, 375), (1170, 300), BLUE)
    draw_box(draw, (460, 610, 1140, 760), "비교 관점: 투자대수·투자비용·Risk 저감량·투자가치·SAIDI·PI_통합", "#f7f9fb", BLUE, 18, FONT_S, wrap=36)
    draw_arrow(draw, (1335, 340), (1000, 610), BLUE)
    draw.text((90, 860), "자료: 본 연구 작성", font=FONT_XS, fill="#555555")
    img.save(OUT_DIR / "fig_integrated_optimization_options.png")


def main():
    save_asset_management_concept()
    save_research_framework()
    save_proposed_methodology()
    save_asset_type_mapping()
    save_pi_structure()
    save_integrated_options()
    print("논문 삽입용 그림 생성 완료")


if __name__ == "__main__":
    main()
