from __future__ import annotations

import math
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "연구설계" / "07_그림자료" / "generated" / "chapter4"
MIRROR = ROOT / "figures" / "generated" / "chapter4"

NAVY = "#0B2A5B"
BLUE = "#2F80ED"
SKY = "#EAF3FF"
GREEN = "#2EAD72"
LGREEN = "#EAF8F1"
ORANGE = "#F2994A"
LORANGE = "#FFF4E6"
PURPLE = "#7B61FF"
LPURPLE = "#F0EDFF"
RED = "#D64545"
GRAY = "#6B7280"
DARK_GRAY = "#374151"
GRID = "#E5E7EB"
BLACK = "#111827"
LIGHT = "#F8FAFC"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/HANBatangB.ttf" if bold else "C:/Windows/Fonts/HANBatang.ttf"),
        Path("C:/Windows/Fonts/batang.ttc"),
        Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


F_TITLE = font(48, True)
F_SUB = font(28)
F_BOX = font(31, True)
F_TEXT = font(26)
F_SMALL = font(22)
F_TINY = font(19)


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    MIRROR.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    img.save(path, quality=100)
    shutil.copy2(path, MIRROR / name)


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = draw.multiline_textbbox((0, 0), text, font=fnt, spacing=8, align="center")
    return box[2] - box[0], box[3] - box[1]


def center_text(draw: ImageDraw.ImageDraw, box, text: str, fnt: ImageFont.FreeTypeFont, fill=BLACK) -> None:
    x0, y0, x1, y1 = box
    w, h = text_size(draw, text, fnt)
    draw.multiline_text(((x0 + x1 - w) / 2, (y0 + y1 - h) / 2), text, font=fnt, fill=fill, spacing=8, align="center")


def rounded_box(draw: ImageDraw.ImageDraw, box, fill, outline=NAVY, width=4, radius=28, title=None, body=None, title_color=BLACK) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    x0, y0, x1, y1 = box
    if title and body:
        draw.text(((x0 + x1) / 2, y0 + 34), title, font=F_BOX, fill=title_color, anchor="mm")
        center_text(draw, (x0 + 25, y0 + 75, x1 - 25, y1 - 20), body, F_TEXT, DARK_GRAY)
    elif title:
        center_text(draw, box, title, F_BOX, title_color)


def arrow(draw: ImageDraw.ImageDraw, start, end, color=NAVY, width=6) -> None:
    x0, y0 = start
    x1, y1 = end
    draw.line((x0, y0, x1, y1), fill=color, width=width)
    angle = math.atan2(y1 - y0, x1 - x0)
    length = 28
    half_width = 14
    p1 = (x1 - length * math.cos(angle) + half_width * math.sin(angle), y1 - length * math.sin(angle) - half_width * math.cos(angle))
    p2 = (x1 - length * math.cos(angle) - half_width * math.sin(angle), y1 - length * math.sin(angle) + half_width * math.cos(angle))
    draw.polygon([(x1, y1), p1, p2], fill=color)


def scale_x(value, x0, x1, vmin, vmax):
    return x0 + (value - vmin) / (vmax - vmin) * (x1 - x0) if vmax != vmin else (x0 + x1) / 2


def scale_y(value, y0, y1, vmin, vmax):
    return y1 - (value - vmin) / (vmax - vmin) * (y1 - y0) if vmax != vmin else (y0 + y1) / 2


def chart_axes(draw: ImageDraw.ImageDraw, x0, y0, x1, y1, ymin, ymax, ticks=5, ylabel="") -> None:
    draw.line((x0, y1, x1, y1), fill=BLACK, width=3)
    draw.line((x0, y0, x0, y1), fill=BLACK, width=3)
    for idx in range(ticks + 1):
        y = y1 - (y1 - y0) * idx / ticks
        val = ymin + (ymax - ymin) * idx / ticks
        draw.line((x0, y, x1, y), fill=GRID, width=1)
        label = f"{val:,.0f}" if abs(val) >= 10 else f"{val:.2f}"
        draw.text((x0 - 18, y), label, font=F_TINY, fill=GRAY, anchor="rm")
    if ylabel:
        draw.text((x0 - 90, (y0 + y1) / 2), ylabel, font=F_SMALL, fill=BLACK, anchor="mm")


def find_sim_file() -> Path:
    preferred = [p for p in ROOT.rglob("simulation_chapter_v2_results.xlsx") if "20260624_094857" in str(p)]
    if preferred:
        return preferred[0]
    return sorted(ROOT.rglob("simulation_chapter_v2_results.xlsx"), key=lambda p: p.stat().st_mtime, reverse=True)[0]


def find_sensitivity_file() -> Path:
    return sorted(ROOT.rglob("sensitivity_analysis_results.xlsx"), key=lambda p: p.stat().st_mtime, reverse=True)[0]


def fig4_1() -> None:
    img = Image.new("RGB", (2400, 1450), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1200, 70), "최적화 시뮬레이션의 단계별 검증 구조", font=F_TITLE, fill=NAVY, anchor="mm")
    draw.text((1200, 120), "동일한 후보군과 제약조건 아래에서 Risk·투자가치, 설비 단위 PI, 통합 PI를 순차 비교", font=F_SUB, fill=GRAY, anchor="mm")

    boxes = {
        "input": (110, 230, 560, 390),
        "cand": (880, 230, 1380, 390),
        "cons": (1800, 230, 2290, 390),
        "s1": (140, 620, 690, 820),
        "s2": (920, 620, 1480, 820),
        "s3": (1710, 620, 2290, 820),
        "sens": (360, 1020, 2040, 1145),
        "out": (650, 1260, 1750, 1360),
    }
    rounded_box(draw, boxes["input"], SKY, NAVY, title="입력 데이터", body="CNAIM 적용 데이터\n교체비용 · SAIDI · PI 산출자료")
    rounded_box(draw, boxes["cand"], LORANGE, ORANGE, title="후보군 구성", body="기준연도 Risk 상위 30%\n투자가치 상위 30% 합집합")
    rounded_box(draw, boxes["cons"], LIGHT, GRAY, title="공통 제약조건", body="연도별 예산·물량\n동일 설비 최대 1회 교체")
    rounded_box(draw, boxes["s1"], SKY, BLUE, title="1단계", body="Risk 및 투자가치 기반\n그리디 · ILP · GA 비교")
    rounded_box(draw, boxes["s2"], LGREEN, GREEN, title="2단계", body="설비 단위 PI 기반\n투자가치 ILP와 PI 포트폴리오 비교")
    rounded_box(draw, boxes["s3"], LPURPLE, PURPLE, title="3단계", body="통합 PI 기반\n설비유형 가중 시스템 포트폴리오")
    rounded_box(draw, boxes["sens"], "#FFFDF3", ORANGE, title="민감도 및 강건성 검증: 예산 · 물량 · SAIDI · Risk 총량 · 운영목표 가중치 변화")
    rounded_box(draw, boxes["out"], "white", NAVY, title="최종 비교: 투자대수 · 투자비용 · Risk 저감량 · 투자가치 · SAIDI · PI")

    arrow(draw, (560, 310), (880, 310))
    arrow(draw, (1380, 310), (1800, 310))
    arrow(draw, (1130, 390), (420, 620), GRAY, 4)
    arrow(draw, (2045, 390), (2010, 620), GRAY, 4)
    arrow(draw, (690, 720), (920, 720))
    arrow(draw, (1480, 720), (1710, 720))
    arrow(draw, (415, 820), (415, 1020), GRAY, 4)
    arrow(draw, (1200, 820), (1200, 1020), GRAY, 4)
    arrow(draw, (2000, 820), (2000, 1020), GRAY, 4)
    arrow(draw, (1200, 1145), (1200, 1260), NAVY, 5)
    save(img, "fig4_1_overall_simulation_procedure.png")


def fig4_4() -> None:
    img = Image.new("RGB", (2200, 1350), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1100, 70), "다기준 성능지표(PI)의 계층 구조", font=F_TITLE, fill=NAVY, anchor="mm")
    rounded_box(draw, (700, 150, 1500, 270), "white", NAVY, title="다기준 성능지표(PI)")

    criteria = [
        ("경제성\n$W_E$", (150, 430, 600, 560), SKY, BLUE, [("투자가치", "w₁"), ("투자효율", "w₂")]),
        ("신뢰도\n$W_R$", (875, 430, 1325, 560), LGREEN, GREEN, [("SAIDI 저감", "w₃"), ("고장예측대수 저감", "w₄")]),
        ("안전·환경\n$W_S$", (1600, 430, 2050, 560), LORANGE, ORANGE, [("안전 영향 저감", "w₅"), ("환경 영향 저감", "w₆")]),
    ]
    for title, box, fill, outline, subs in criteria:
        arrow(draw, (1100, 270), ((box[0] + box[2]) // 2, 430), NAVY, 4)
        rounded_box(draw, box, fill, outline, title=title)
        for idx, (name, wlabel) in enumerate(subs):
            sb = (box[0] + 35, 650 + idx * 210, box[2] - 35, 790 + idx * 210)
            arrow(draw, ((box[0] + box[2]) // 2, 560), ((sb[0] + sb[2]) // 2, sb[1]), outline, 3)
            rounded_box(draw, sb, "white", outline, width=3, radius=18, title=name)
            cx, cy = sb[2] - 28, sb[1] + 8
            draw.ellipse((cx - 42, cy - 42, cx + 42, cy + 42), fill="#F3F4F6", outline=GRAY, width=2)
            draw.text((cx, cy), wlabel, font=F_SMALL, fill=BLACK, anchor="mm")

    rounded_box(draw, (735, 1135, 1465, 1245), "#F8FAFC", GRAY, width=3, radius=18, title="PI(i,t) = Σ wₖ × scoreₖ(i,t)")
    draw.text((1100, 1290), "주: 전역가중치는 대기준 가중치와 하위지표 국소가중치의 곱으로 산정", font=F_SMALL, fill=GRAY, anchor="mm")
    save(img, "fig4_4_asset_level_pi_weight_structure.png")


def fig4_6() -> None:
    img = Image.new("RGB", (2300, 1250), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1150, 70), "통합 PI 산정 및 적용 절차", font=F_TITLE, fill=NAVY, anchor="mm")
    xs = [180, 700, 1220, 1740]
    labels = [
        ("설비 단위 PI", "개별 설비의 경제성·신뢰도\n안전·환경 성능 점수"),
        ("설비유형 가중치", "전문가 설문 기반\n설비군 중요도"),
        ("비용 규모 보정", "설비유형별 교체비용 차이\nScale Factor 반영"),
        ("통합 PI", "설비 단위 PI × 유형가중치\n× 비용 규모 보정"),
    ]
    fills = [SKY, LGREEN, LORANGE, LPURPLE]
    outlines = [BLUE, GREEN, ORANGE, PURPLE]
    for idx, (x, (title, body)) in enumerate(zip(xs, labels)):
        rounded_box(draw, (x, 250, x + 380, 470), fills[idx], outlines[idx], title=title, body=body)
        if idx < 3:
            arrow(draw, (x + 380, 360), (xs[idx + 1], 360), NAVY, 5)

    rounded_box(draw, (790, 680, 1510, 850), "white", NAVY, title="시스템 단위 포트폴리오 최적화", body="동일 후보군과 제약조건 아래에서\n통합 PI가 높은 설비-연도 조합 선택")
    arrow(draw, (1930, 470), (1420, 680), PURPLE, 5)
    rounded_box(draw, (540, 1000, 1760, 1115), "#FFFDF3", ORANGE, title="결과 비교: 선택 설비유형 분포 · 통합 PI · SAIDI · 투자가치")
    arrow(draw, (1150, 850), (1150, 1000), NAVY, 5)
    draw.text((1150, 1190), "주: 대표 통합 방식은 설비 단위 PI 포트폴리오 이후 설비유형 가중치를 적용하는 사후 통합 방식이다.", font=F_SMALL, fill=GRAY, anchor="mm")
    save(img, "fig4_6_integrated_pi_calculation_procedure.png")


def fig4_9_budget() -> None:
    sensitivity = find_sensitivity_file()
    summary = pd.read_excel(sensitivity, "04_total_summary")
    data = summary[
        (summary["scenario_group"].eq("budget_sweep"))
        & (summary["simulation_scope"].eq("risk_value_screening"))
        & (summary["method"].eq("investment_value_ilp"))
    ].sort_values("budget_multiplier")
    x = data["budget_multiplier"].to_numpy()
    y = data["investment_value_kkrw"].to_numpy() / 100000.0

    img = Image.new("RGB", (2100, 1200), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1050, 70), "예산 배율 변화에 따른 투자가치 민감도", font=F_TITLE, fill=NAVY, anchor="mm")
    x0, y0, x1, y1 = 190, 180, 1920, 940
    ymin = max(0, y.min() * 0.92)
    ymax = y.max() * 1.08
    chart_axes(draw, x0, y0, x1, y1, ymin, ymax, 5, "투자가치(억원)")
    points = [(scale_x(a, x0, x1, x.min(), x.max()), scale_y(b, y0, y1, ymin, ymax)) for a, b in zip(x, y)]
    draw.line(points, fill=BLUE, width=7)
    for px, py, a, b in zip([p[0] for p in points], [p[1] for p in points], x, y):
        draw.ellipse((px - 9, py - 9, px + 9, py + 9), fill=BLUE)
        if abs(a - 1.0) < 1e-9 or a in [x.min(), x.max()]:
            draw.text((px, py - 22), f"{b:,.0f}", font=F_TINY, fill=BLACK, anchor="mb")
    for a in np.linspace(x.min(), x.max(), 6):
        draw.text((scale_x(a, x0, x1, x.min(), x.max()), y1 + 28), f"{a:.1f}", font=F_TINY, fill=GRAY, anchor="mm")
    draw.text(((x0 + x1) // 2, y1 + 82), "예산 배율(기준 = 1.0)", font=F_SMALL, fill=BLACK, anchor="mm")
    rounded_box(draw, (1320, 230, 1840, 350), "#F8FAFC", GRAY, width=2, radius=18, title="예산 증가에 따른 한계효과 확인")
    save(img, "fig4_9_budget_multiplier_sensitivity.png")


def fig4_10_weight() -> None:
    sensitivity = find_sensitivity_file()
    summary = pd.read_excel(sensitivity, "04_total_summary")
    data = summary[
        (summary["scenario_group"].eq("operating_goal_weight_sweep"))
        & (summary["simulation_scope"].eq("integrated_pi_portfolio"))
        & (summary["method"].eq("integrated_pi_ilp"))
    ].copy()

    img = Image.new("RGB", (2200, 1300), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1100, 70), "운영목표 가중치 변화에 따른 통합 PI 민감도", font=F_TITLE, fill=NAVY, anchor="mm")
    panels = [
        ("경제성 가중치", "w_economy", BLUE),
        ("신뢰도 가중치", "w_reliability", GREEN),
        ("안전·환경 가중치", "w_safety_environment", ORANGE),
    ]
    y_values = data["integrated_pi"].to_numpy()
    y_min, y_max = y_values.min() * 0.97, y_values.max() * 1.03
    for idx, (title, column, color) in enumerate(panels):
        x0 = 170 + idx * 670
        y0, x1, y1 = 210, x0 + 560, 960
        chart_axes(draw, x0, y0, x1, y1, y_min, y_max, 5, "")
        draw.text(((x0 + x1) // 2, y0 - 45), title, font=F_SMALL, fill=NAVY, anchor="mm")
        for xv, yv in zip(data[column].to_numpy(), y_values):
            px = scale_x(xv, x0, x1, 0, 1)
            py = scale_y(yv, y0, y1, y_min, y_max)
            draw.ellipse((px - 7, py - 7, px + 7, py + 7), fill=color, outline="white", width=1)
        for tick in [0, 0.25, 0.5, 0.75, 1.0]:
            draw.text((scale_x(tick, x0, x1, 0, 1), y1 + 28), f"{tick:.2f}", font=F_TINY, fill=GRAY, anchor="mm")
        draw.text(((x0 + x1) // 2, y1 + 78), "가중치", font=F_SMALL, fill=BLACK, anchor="mm")
    draw.text((90, 585), "통합 PI", font=F_SMALL, fill=BLACK, anchor="mm")
    rounded_box(draw, (470, 1095, 1730, 1190), "#F8FAFC", GRAY, width=2, radius=18, title="동일 제약조건 아래에서 운영목표 가중치만 변화시켜 포트폴리오 반응을 검토")
    save(img, "fig4_10_operating_goal_weight_sensitivity.png")


def fig4_11_constraints() -> None:
    sensitivity = find_sensitivity_file()
    annual = pd.read_excel(sensitivity, "03_annual_summary")
    saidi = annual[
        (annual["scenario_group"].eq("saidi_cap_sweep"))
        & (annual["simulation_scope"].eq("integrated_pi_portfolio"))
        & (annual["method"].eq("integrated_pi_ilp"))
        & (annual["year"].eq(2030))
        & (annual["saidi_cap_rate"].lt(10))
    ].sort_values("saidi_cap_rate")
    risk = annual[
        (annual["scenario_group"].eq("risk_cap_sweep"))
        & (annual["simulation_scope"].eq("integrated_pi_portfolio"))
        & (annual["method"].eq("integrated_pi_ilp"))
        & (annual["year"].eq(2030))
        & (annual["risk_cap_rate"].lt(10))
    ].sort_values("risk_cap_rate")

    img = Image.new("RGB", (2300, 1250), "white")
    draw = ImageDraw.Draw(img)
    draw.text((1150, 70), "SAIDI 및 Risk 총량 제약 민감도", font=F_TITLE, fill=NAVY, anchor="mm")

    x0, y0, x1, y1 = 180, 210, 1050, 960
    if len(saidi):
        xv = saidi["saidi_cap_rate"].to_numpy()
        yv = saidi["saidi_after_cumulative_min"].to_numpy()
        ymin, ymax = yv.min() * 0.995, yv.max() * 1.005
        chart_axes(draw, x0, y0, x1, y1, ymin, ymax, 5, "SAIDI after(분)")
        points = [(scale_x(a, x0, x1, xv.min(), xv.max()), scale_y(b, y0, y1, ymin, ymax)) for a, b in zip(xv, yv)]
        draw.line(points, fill=BLUE, width=6)
        for px, py, a, b in zip([p[0] for p in points], [p[1] for p in points], xv, yv):
            draw.ellipse((px - 8, py - 8, px + 8, py + 8), fill=BLUE)
            draw.text((px, py - 20), f"{b:.3f}", font=F_TINY, fill=BLACK, anchor="mb")
        for tick in xv:
            draw.text((scale_x(tick, x0, x1, xv.min(), xv.max()), y1 + 28), f"{tick:.2f}", font=F_TINY, fill=GRAY, anchor="mm")
        draw.text(((x0 + x1) // 2, y0 - 45), "SAIDI 상한 제약", font=F_SMALL, fill=NAVY, anchor="mm")

    x0, y0, x1, y1 = 1280, 210, 2150, 960
    if len(risk):
        xv = risk["risk_cap_rate"].to_numpy()
        yv = risk["risk_after_cumulative_kkrw"].to_numpy() / 100000.0
        ymin, ymax = yv.min() * 0.995, yv.max() * 1.005
        chart_axes(draw, x0, y0, x1, y1, ymin, ymax, 5, "Risk after(억원)")
        points = [(scale_x(a, x0, x1, xv.min(), xv.max()), scale_y(b, y0, y1, ymin, ymax)) for a, b in zip(xv, yv)]
        draw.line(points, fill=RED, width=6)
        for px, py, a, b in zip([p[0] for p in points], [p[1] for p in points], xv, yv):
            draw.ellipse((px - 8, py - 8, px + 8, py + 8), fill=RED)
            draw.text((px, py - 20), f"{b:,.1f}", font=F_TINY, fill=BLACK, anchor="mb")
        for tick in xv:
            draw.text((scale_x(tick, x0, x1, xv.min(), xv.max()), y1 + 28), f"{tick:.2f}", font=F_TINY, fill=GRAY, anchor="mm")
        draw.text(((x0 + x1) // 2, y0 - 45), "Risk 총량 상한 제약", font=F_SMALL, fill=NAVY, anchor="mm")

    rounded_box(draw, (505, 1080, 1795, 1175), "#F8FAFC", GRAY, width=2, radius=18, title="제약이 강화되어도 사후 통합 PI 포트폴리오의 KPI 충족 여부를 점검")
    save(img, "fig4_11_saidi_risk_constraint_feasibility.png")


def main() -> None:
    fig4_1()
    fig4_4()
    fig4_6()
    fig4_9_budget()
    fig4_10_weight()
    fig4_11_constraints()
    print(f"바탕체 고해상도 재작도 완료: {OUT}")


if __name__ == "__main__":
    main()
