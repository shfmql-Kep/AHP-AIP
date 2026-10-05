from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "연구설계" / "07_그림자료" / "generated" / "chapter4"
MIRROR_DIR = ROOT / "figures" / "generated" / "chapter4"

COLORS = {
    "navy": "#0B2A5B",
    "blue": "#2F80ED",
    "green": "#2EAD72",
    "orange": "#F2994A",
    "purple": "#7B61FF",
    "red": "#D64545",
    "gray": "#6B7280",
    "light": "#F7F9FC",
    "grid": "#E5E7EB",
    "black": "#111827",
}

ASSET_ORDER = ["주상변압기", "지상변압기", "가공개폐기", "지중개폐기", "가공배전선로", "지중케이블"]
ASSET_COLORS = {
    "주상변압기": "#4E79A7",
    "지상변압기": "#F28E2B",
    "가공개폐기": "#59A14F",
    "지중개폐기": "#E15759",
    "가공배전선로": "#B07AA1",
    "지중케이블": "#9C755F",
}

METHOD_LABELS = {
    "risk_greedy": "Risk\nGreedy",
    "investment_value_greedy": "IV\nGreedy",
    "investment_value_ilp": "IV\nILP",
    "investment_value_ga": "IV\nGA",
    "pi_greedy": "PI\nGreedy",
    "pi_ilp": "PI\nILP",
    "pi_ga": "PI\nGA",
    "integrated_post_type_weight_ilp": "Post\nIntegrated\nILP",
    "integrated_pre_type_weight_ilp": "Pre\nIntegrated\nILP",
}


def find_latest(name: str, must_contain: str | None = None) -> Path:
    files = sorted(ROOT.rglob(name), key=lambda p: p.stat().st_mtime, reverse=True)
    if must_contain:
        files = [p for p in files if must_contain in str(p)]
    if not files:
        raise FileNotFoundError(name)
    return files[0]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/HANBatangB.ttf" if bold else "C:/Windows/Fonts/HANBatang.ttf"),
        Path("C:/Windows/Fonts/batang.ttc"),
        Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf"),
    ]
    for p in candidates:
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


F_TITLE = font(34, True)
F_SUB = font(22, False)
F_LABEL = font(21, False)
F_LABEL_B = font(21, True)
F_SMALL = font(18, False)
F_TINY = font(15, False)


def ensure_dirs() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    MIRROR_DIR.mkdir(parents=True, exist_ok=True)


def save(img: Image.Image, filename: str) -> None:
    ensure_dirs()
    path = OUT_DIR / filename
    img.save(path, quality=96)
    shutil.copy2(path, MIRROR_DIR / filename)


def draw_center(draw: ImageDraw.ImageDraw, xy, text: str, fnt, fill=COLORS["black"], anchor="mm") -> None:
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def draw_multiline_center(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, fnt, fill=COLORS["black"], line_gap=5) -> None:
    lines = text.split("\n")
    heights = [draw.textbbox((0, 0), line, font=fnt)[3] for line in lines]
    total = sum(heights) + line_gap * (len(lines) - 1)
    cy = y - total // 2
    for line, h in zip(lines, heights):
        bbox = draw.textbbox((0, 0), line, font=fnt)
        draw.text((x - (bbox[2] - bbox[0]) / 2, cy), line, font=fnt, fill=fill)
        cy += h + line_gap


def chart_area(draw, x0, y0, x1, y1, y_max, y_ticks=5, y_unit="") -> None:
    draw.line((x0, y1, x1, y1), fill=COLORS["black"], width=2)
    draw.line((x0, y0, x0, y1), fill=COLORS["black"], width=2)
    for i in range(y_ticks + 1):
        y = y1 - (y1 - y0) * i / y_ticks
        draw.line((x0, y, x1, y), fill=COLORS["grid"], width=1)
        val = y_max * i / y_ticks
        label = f"{val:,.0f}{y_unit}"
        draw.text((x0 - 12, y), label, font=F_TINY, fill=COLORS["gray"], anchor="rm")


def scale_y(v, y0, y1, v_min, v_max):
    if v_max == v_min:
        return (y0 + y1) / 2
    return y1 - (v - v_min) / (v_max - v_min) * (y1 - y0)


def eok(v):
    return v / 100000.0


def nice_max(v: float) -> float:
    if v <= 0:
        return 1.0
    base = 10 ** (len(str(int(v))) - 1)
    return float(np.ceil(v / base * 1.12) * base)


def load_paths():
    return (
        find_latest("simulation_chapter_v2_results.xlsx", "20260624_094857"),
        find_latest("pof_5yr_output.xlsx"),
        find_latest("03_integrated_selected_assets.csv", "20260624_094857"),
    )


def fig4_2(pof_file: Path) -> None:
    df = pd.read_excel(pof_file)
    cand = df[df["candidate_top30_current"].eq(1)].copy()
    cand["iv_eok"] = eok(cand["investment_value_2026_kkrw"])
    vals = cand.sort_values("iv_eok", ascending=False)["iv_eok"].to_numpy()
    pos = int((vals >= 0).sum())

    w, h = 1800, 940
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    draw_center(d, (w // 2, 58), "Investment Value Distribution of Candidate Assets", F_TITLE, COLORS["navy"])
    d.text((120, 110), f"후보군 {len(vals):,}기 · 양의 투자가치 {pos:,}기 · 음의 투자가치 {len(vals)-pos:,}기", font=F_SUB, fill=COLORS["gray"])

    x0, y0, x1, y1 = 130, 185, 1700, 800
    v_min, v_max = min(vals.min(), 0), max(vals.max(), 0)
    pad = (v_max - v_min) * 0.08
    v_min -= pad
    v_max += pad
    zero_y = scale_y(0, y0, y1, v_min, v_max)
    d.line((x0, y1, x1, y1), fill=COLORS["black"], width=2)
    d.line((x0, y0, x0, y1), fill=COLORS["black"], width=2)
    for i in range(6):
        y = y1 - (y1 - y0) * i / 5
        val = v_min + (v_max - v_min) * i / 5
        d.line((x0, y, x1, y), fill=COLORS["grid"], width=1)
        d.text((x0 - 15, y), f"{val:,.0f}", font=F_TINY, fill=COLORS["gray"], anchor="rm")
    d.line((x0, zero_y, x1, zero_y), fill=COLORS["black"], width=2)

    n = len(vals)
    max_points = 1400
    step = max(1, n // max_points)
    points = []
    for idx in range(0, n, step):
        x = x0 + (x1 - x0) * idx / (n - 1)
        y = scale_y(vals[idx], y0, y1, v_min, v_max)
        points.append((x, y))
    # 양수/음수 영역을 폴리곤으로 나누어 채움
    pos_points = [(x0, zero_y)] + [(x, y) for x, y in points if y <= zero_y] + [(x0 + (x1 - x0) * max(pos - 1, 0) / (n - 1), zero_y)]
    neg_points = [(x0 + (x1 - x0) * max(pos, 0) / (n - 1), zero_y)] + [(x, y) for x, y in points if y > zero_y] + [(x1, zero_y)]
    if len(pos_points) > 2:
        d.polygon(pos_points, fill="#8FC5FF")
    if len(neg_points) > 2:
        d.polygon(neg_points, fill="#C6CDD7")
    if len(points) > 1:
        d.line(points, fill=COLORS["blue"], width=3)

    d.text((x0 - 55, (y0 + y1) // 2), "투자가치(억원)", font=F_LABEL_B, fill=COLORS["black"], anchor="mm")
    d.text(((x0 + x1) // 2, y1 + 55), "후보 설비 순번(투자가치 내림차순)", font=F_LABEL, fill=COLORS["black"], anchor="mm")
    d.rectangle((1280, 210, 1660, 300), fill="white", outline=COLORS["grid"])
    d.rectangle((1300, 235, 1335, 255), fill="#8FC5FF")
    d.text((1345, 226), "양의 투자가치", font=F_SMALL, fill=COLORS["black"])
    d.rectangle((1500, 235, 1535, 255), fill="#C6CDD7")
    d.text((1545, 226), "음의 투자가치", font=F_SMALL, fill=COLORS["black"])
    save(img, "fig4_2_investment_value_distribution.png")


def fig4_3(sim_file: Path) -> None:
    df = pd.read_excel(sim_file, "03_value_combined_total").set_index("method")
    order = ["risk_greedy", "investment_value_greedy", "investment_value_ilp", "investment_value_ga"]
    df = df.loc[order]
    labels = [METHOD_LABELS[m] for m in order]
    risk = eok(df["risk_reduction_kkrw"].to_numpy())
    iv = eok(df["investment_value_kkrw"].to_numpy())
    eff = df["investment_efficiency"].to_numpy()

    w, h = 1900, 980
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    draw_center(d, (w // 2, 58), "Aggregated Performance Comparison of Risk and Investment-Value Methods", F_TITLE, COLORS["navy"])

    x0, y0, x1, y1 = 120, 160, 1250, 785
    y_max = nice_max(max(risk.max(), iv.max()))
    chart_area(d, x0, y0, x1, y1, y_max)
    group_w = (x1 - x0) / len(order)
    bar_w = 75
    for i, lab in enumerate(labels):
        cx = x0 + group_w * (i + 0.5)
        for j, (val, color) in enumerate([(risk[i], COLORS["blue"]), (iv[i], COLORS["green"])]):
            bh = (y1 - y0) * val / y_max
            bx0 = cx - bar_w - 8 + j * (bar_w + 16)
            by0 = y1 - bh
            d.rectangle((bx0, by0, bx0 + bar_w, y1), fill=color)
            d.text((bx0 + bar_w / 2, by0 - 8), f"{val:,.0f}", font=F_TINY, fill=COLORS["black"], anchor="mb")
        draw_multiline_center(d, int(cx), y1 + 60, lab, F_TINY)
    d.text((x0 - 52, (y0 + y1) // 2), "금액(억원)", font=F_LABEL_B, fill=COLORS["black"], anchor="mm")
    d.rectangle((930, 180, 1220, 250), fill="white", outline=COLORS["grid"])
    d.rectangle((950, 202, 982, 222), fill=COLORS["blue"])
    d.text((995, 195), "Risk 저감량", font=F_SMALL, fill=COLORS["black"])
    d.rectangle((1100, 202, 1132, 222), fill=COLORS["green"])
    d.text((1145, 195), "투자가치", font=F_SMALL, fill=COLORS["black"])

    # 투자효율 보조 패널
    bx0, by0, bx1, by1 = 1375, 210, 1810, 785
    y_max2 = max(3.0, nice_max(eff.max()))
    chart_area(d, bx0, by0, bx1, by1, y_max2)
    bw = 65
    for i, lab in enumerate(labels):
        cx = bx0 + (bx1 - bx0) * (i + 0.5) / len(labels)
        bh = (by1 - by0) * eff[i] / y_max2
        d.rectangle((cx - bw / 2, by1 - bh, cx + bw / 2, by1), fill=COLORS["orange"])
        d.text((cx, by1 - bh - 8), f"{eff[i]:.2f}", font=F_TINY, fill=COLORS["black"], anchor="mb")
        draw_multiline_center(d, int(cx), by1 + 60, lab, F_TINY)
    d.text((1592, 160), "Investment Efficiency", font=F_LABEL_B, fill=COLORS["navy"], anchor="mm")
    d.text((1322, (by0 + by1) // 2), "Risk/Cost", font=F_SMALL, fill=COLORS["black"], anchor="mm")
    save(img, "fig4_3_aggregate_performance_value_methods.png")


def simple_bar_comparison(filename: str, title: str, labels: list[str], series: list[tuple[str, list[float], str]], ylabel: str) -> None:
    w, h = 1800, 950
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    draw_center(d, (w // 2, 58), title, F_TITLE, COLORS["navy"])
    x0, y0, x1, y1 = 140, 165, 1660, 760
    y_max = nice_max(max(max(vals) for _, vals, _ in series))
    chart_area(d, x0, y0, x1, y1, y_max)
    group_w = (x1 - x0) / len(labels)
    bar_w = min(80, group_w / (len(series) + 1))
    for i, lab in enumerate(labels):
        cx = x0 + group_w * (i + 0.5)
        start = cx - (len(series) * bar_w + (len(series) - 1) * 12) / 2
        for j, (_, vals, color) in enumerate(series):
            val = vals[i]
            bh = (y1 - y0) * val / y_max
            bx = start + j * (bar_w + 12)
            d.rectangle((bx, y1 - bh, bx + bar_w, y1), fill=color)
            d.text((bx + bar_w / 2, y1 - bh - 8), f"{val:,.1f}" if val < 10 else f"{val:,.0f}", font=F_TINY, fill=COLORS["black"], anchor="mb")
        draw_multiline_center(d, int(cx), y1 + 60, lab, F_TINY)
    d.text((x0 - 58, (y0 + y1) // 2), ylabel, font=F_LABEL_B, fill=COLORS["black"], anchor="mm")
    lx, ly = x0 + 30, 105
    for name, _, color in series:
        d.rectangle((lx, ly, lx + 34, ly + 20), fill=color)
        d.text((lx + 45, ly - 4), name, font=F_SMALL, fill=COLORS["black"])
        lx += 230
    save(img, filename)


def fig4_5(sim_file: Path) -> None:
    final = pd.read_excel(sim_file, "07_final_comparison").set_index("method")
    iv = final.loc["investment_value_ilp"]
    pi = final.loc["pi_ilp"]
    labels = ["투자가치\n(억원)", "SAIDI\n저감(분×1000)", "설비 단위\nPI", "통합\nPI"]
    iv_vals = [eok(iv["investment_value_kkrw"]), iv["saidi_reduction_min"] * 1000, iv["local_pi"], iv["integrated_pi"]]
    pi_vals = [eok(pi["investment_value_kkrw"]), pi["saidi_reduction_min"] * 1000, pi["local_pi"], pi["integrated_pi"]]
    simple_bar_comparison(
        "fig4_5_iv_ilp_vs_pi_ilp_performance.png",
        "Performance Trade-off between Investment-Value ILP and PI ILP",
        labels,
        [("IV ILP", iv_vals, COLORS["green"]), ("PI ILP", pi_vals, COLORS["purple"])],
        "지표값",
    )


def fig4_7(sim_file: Path) -> None:
    final = pd.read_excel(sim_file, "07_final_comparison").set_index("method")
    methods = ["investment_value_ilp", "pi_ilp", "integrated_post_type_weight_ilp"]
    labels = ["IV\nILP", "PI\nILP", "Post\nIntegrated\nPI ILP"]
    int_pi = final.loc[methods, "integrated_pi"].to_numpy()
    saidi = final.loc[methods, "saidi_reduction_min"].to_numpy() * 1000
    simple_bar_comparison(
        "fig4_7_integration_method_kpi_comparison.png",
        "Methodology Phase Comparison in SAIDI and Integrated PI",
        labels,
        [("통합 PI", list(int_pi), COLORS["blue"]), ("SAIDI 저감×1000", list(saidi), COLORS["red"])],
        "지표값",
    )


def fig4_8(sim_file: Path, selected_file: Path) -> None:
    value_type = pd.read_excel(sim_file, "02_value_type_total")
    pi_type = pd.read_excel(sim_file, "04_pi_type_total")
    integ = pd.read_csv(selected_file, encoding="utf-8-sig")
    data = {
        "IV ILP": value_type[value_type["method"].eq("investment_value_ilp")].set_index("asset_type_label")["selected_count"],
        "PI ILP": pi_type[pi_type["method"].eq("pi_ilp")].set_index("asset_type_label")["selected_count"],
        "Post\nIntegrated\nPI ILP": integ[integ["method"].eq("integrated_post_type_weight_ilp")].groupby("asset_type_label")["asset_id"].count(),
        "Pre\nIntegrated\nPI ILP": integ[integ["method"].eq("integrated_pre_type_weight_ilp")].groupby("asset_type_label")["asset_id"].count(),
    }
    methods = list(data)
    totals = [sum(data[m].get(a, 0) for a in ASSET_ORDER) for m in methods]
    w, h = 1850, 980
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    draw_center(d, (w // 2, 58), "Asset-Type Selection Distribution by Method", F_TITLE, COLORS["navy"])
    x0, y0, x1, y1 = 160, 165, 1660, 765
    y_max = nice_max(max(totals))
    chart_area(d, x0, y0, x1, y1, y_max)
    group_w = (x1 - x0) / len(methods)
    bar_w = 150
    for i, m in enumerate(methods):
        cx = x0 + group_w * (i + 0.5)
        bottom_y = y1
        for asset in ASSET_ORDER:
            val = data[m].get(asset, 0)
            bh = (y1 - y0) * val / y_max
            d.rectangle((cx - bar_w / 2, bottom_y - bh, cx + bar_w / 2, bottom_y), fill=ASSET_COLORS[asset])
            bottom_y -= bh
        d.text((cx, bottom_y - 10), f"{int(totals[i]):,}", font=F_TINY, fill=COLORS["black"], anchor="mb")
        draw_multiline_center(d, int(cx), y1 + 72, m, F_TINY)
    d.text((x0 - 62, (y0 + y1) // 2), "선택 설비 수(대)", font=F_LABEL_B, fill=COLORS["black"], anchor="mm")
    lx, ly = 290, 850
    for idx, asset in enumerate(ASSET_ORDER):
        x = lx + (idx % 3) * 420
        y = ly + (idx // 3) * 42
        d.rectangle((x, y, x + 34, y + 22), fill=ASSET_COLORS[asset])
        d.text((x + 45, y - 2), asset, font=F_SMALL, fill=COLORS["black"])
    save(img, "fig4_8_asset_type_selection_distribution.png")


def fig4_9(sim_file: Path) -> None:
    ga = pd.read_excel(sim_file, "09_ga_progress")
    value_ga = ga[(ga["phase"].eq("value_phase")) & (ga["method"].eq("investment_value_ga"))]
    by = value_ga.groupby("generation", as_index=False).agg(best=("best_score", "sum"), mean=("population_mean", "sum"))
    by["best"] = eok(by["best"])
    by["mean"] = eok(by["mean"])
    w, h = 1750, 920
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    draw_center(d, (w // 2, 58), "GA Convergence Process for Investment-Value Optimization", F_TITLE, COLORS["navy"])
    x0, y0, x1, y1 = 150, 165, 1600, 760
    vals = np.r_[by["best"].to_numpy(), by["mean"].to_numpy()]
    v_min, v_max = vals.min() * 0.995, vals.max() * 1.005
    d.line((x0, y1, x1, y1), fill=COLORS["black"], width=2)
    d.line((x0, y0, x0, y1), fill=COLORS["black"], width=2)
    for i in range(6):
        y = y1 - (y1 - y0) * i / 5
        val = v_min + (v_max - v_min) * i / 5
        d.line((x0, y, x1, y), fill=COLORS["grid"], width=1)
        d.text((x0 - 15, y), f"{val:,.0f}", font=F_TINY, fill=COLORS["gray"], anchor="rm")
    def px(g): return x0 + (x1 - x0) * (g - by["generation"].min()) / (by["generation"].max() - by["generation"].min())
    def py(v): return scale_y(v, y0, y1, v_min, v_max)
    best_pts = [(px(g), py(v)) for g, v in zip(by["generation"], by["best"])]
    mean_pts = [(px(g), py(v)) for g, v in zip(by["generation"], by["mean"])]
    d.line(best_pts, fill=COLORS["blue"], width=5)
    d.line(mean_pts, fill=COLORS["gray"], width=4)
    for x, y in best_pts:
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=COLORS["blue"])
    d.text((x0 - 60, (y0 + y1) // 2), "투자가치(억원)", font=F_LABEL_B, fill=COLORS["black"], anchor="mm")
    d.text(((x0 + x1) // 2, y1 + 55), "세대(Generation)", font=F_LABEL, fill=COLORS["black"], anchor="mm")
    d.rectangle((1190, 190, 1560, 275), fill="white", outline=COLORS["grid"])
    d.line((1215, 220, 1270, 220), fill=COLORS["blue"], width=5)
    d.text((1285, 207), "세대별 최선해", font=F_SMALL, fill=COLORS["black"])
    d.line((1215, 252, 1270, 252), fill=COLORS["gray"], width=4)
    d.text((1285, 239), "개체군 평균", font=F_SMALL, fill=COLORS["black"])
    d.text((1200, 815), f"최종 GA 투자가치: {by['best'].iloc[-1]:,.1f}억 원", font=F_SMALL, fill=COLORS["navy"])
    save(img, "fig4_9_ga_convergence.png")


def copy_and_compose_sensitivity() -> None:
    sens_dirs = sorted([p for p in ROOT.rglob("sensitivity_analysis_fast_20260624_100129") if p.is_dir()], key=lambda p: p.stat().st_mtime, reverse=True)
    if not sens_dirs:
        return
    src_dir = sens_dirs[0] / "figures"
    if not src_dir.exists():
        return
    src10 = src_dir / "integrated_pi_portfolio_weight_3d_integrated_pi_ilp_integrated_pi.png"
    if src10.exists():
        img = Image.open(src10).convert("RGB")
        save(img, "fig4_10_operating_goal_weight_sensitivity.png")
    saidi = src_dir / "integrated_pi_portfolio__saidi_cap_sweep_kpi_saidi_after_cumulative_min.png"
    risk = src_dir / "integrated_pi_portfolio__risk_cap_sweep_kpi_risk_after_cumulative_kkrw.png"
    if saidi.exists() and risk.exists():
        im1 = Image.open(saidi).convert("RGB")
        im2 = Image.open(risk).convert("RGB")
        target_h = 760
        def resize_h(im):
            return im.resize((int(im.width * target_h / im.height), target_h))
        im1, im2 = resize_h(im1), resize_h(im2)
        pad = 50
        title_h = 90
        out = Image.new("RGB", (im1.width + im2.width + pad * 3, target_h + title_h + pad), "white")
        d = ImageDraw.Draw(out)
        draw_center(d, (out.width // 2, 50), "SAIDI and Risk Constraint Sensitivity", F_TITLE, COLORS["navy"])
        out.paste(im1, (pad, title_h))
        out.paste(im2, (im1.width + pad * 2, title_h))
        save(out, "fig4_11_saidi_risk_constraint_feasibility.png")


def main() -> None:
    ensure_dirs()
    sim_file, pof_file, selected_file = load_paths()
    print(f"SIM: {sim_file}")
    print(f"POF: {pof_file}")
    print(f"SELECTED: {selected_file}")
    fig4_2(pof_file)
    fig4_3(sim_file)
    fig4_5(sim_file)
    fig4_7(sim_file)
    fig4_8(sim_file, selected_file)
    fig4_9(sim_file)
    copy_and_compose_sensitivity()
    print(f"저장 완료: {OUT_DIR}")


if __name__ == "__main__":
    main()
