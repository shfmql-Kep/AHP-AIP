from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
OUT_JSON = ROOT / "tmp" / "ch4_simulation_chart_data.json"


METHOD_LABELS = {
    "risk_greedy": "Risk 그리디",
    "investment_value_greedy": "투자가치 그리디",
    "investment_value_ilp": "투자가치 ILP",
    "investment_value_ga": "투자가치 GA",
    "pi_greedy": "PI 그리디",
    "pi_ilp": "PI ILP",
    "pi_ga": "PI GA",
    "integrated_post_type_weight_ilp": "후보제한형 ILP",
    "integrated_pre_type_weight_ilp": "통합형 ILP",
    "integrated_post_type_weight_ga": "후보제한형 GA",
    "integrated_pre_type_weight_ga": "통합형 GA",
}

REPRESENTATIVE_METHODS = [
    "risk_greedy",
    "investment_value_ilp",
    "pi_ilp",
    "integrated_pre_type_weight_ilp",
]


def find_latest_simulation_file() -> Path:
    preferred = [
        path
        for path in ROOT.rglob("simulation_chapter_v2_results.xlsx")
        if "20260624_094857" in str(path)
    ]
    if preferred:
        return preferred[0]
    files = sorted(ROOT.rglob("simulation_chapter_v2_results.xlsx"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        raise FileNotFoundError("simulation_chapter_v2_results.xlsx")
    return files[0]


def eok(value) -> float:
    return float(value) / 100000.0


def safe_float(value):
    if pd.isna(value):
        return None
    return float(value)


def safe_int(value):
    if pd.isna(value):
        return None
    return int(value)


def records_from_df(df: pd.DataFrame, columns: list[str]) -> list[dict]:
    out = []
    for _, row in df.iterrows():
        item = {}
        for col in columns:
            value = row[col]
            if pd.isna(value):
                item[col] = None
            elif isinstance(value, (int, float)):
                item[col] = float(value)
            else:
                item[col] = str(value)
        out.append(item)
    return out


def final_comparison_rows(final_df: pd.DataFrame) -> list[dict]:
    rows = []
    for _, row in final_df.iterrows():
        method = str(row["method"])
        rows.append(
            {
                "method": method,
                "method_label": METHOD_LABELS.get(method, method),
                "selected_count": safe_int(row["selected_count"]),
                "investment_cost_eok": eok(row["investment_cost_kkrw"]),
                "risk_reduction_eok": eok(row["risk_reduction_kkrw"]),
                "investment_value_eok": eok(row["investment_value_kkrw"]),
                "saidi_reduction_min": safe_float(row["saidi_reduction_min"]),
                "asset_level_pi": safe_float(row["local_pi"]),
                "integrated_pi": safe_float(row["integrated_pi"]),
                "investment_efficiency": safe_float(row["investment_efficiency"]),
            }
        )
    return rows


def combo_rows(final_df: pd.DataFrame, methods: list[str]) -> list[dict]:
    final_df = final_df.set_index("method")
    rows = []
    for method in methods:
        if method not in final_df.index:
            continue
        row = final_df.loc[method]
        rows.append(
            {
                "method_label": METHOD_LABELS.get(method, method),
                "risk_reduction_eok": eok(row["risk_reduction_kkrw"]),
                "investment_cost_eok": eok(row["investment_cost_kkrw"]),
                "investment_value_eok": eok(row["investment_value_kkrw"]),
                "investment_efficiency": safe_float(row["investment_efficiency"]),
                "saidi_reduction_min": safe_float(row["saidi_reduction_min"]),
                "asset_level_pi": safe_float(row["local_pi"]),
                "integrated_pi": safe_float(row["integrated_pi"]),
            }
        )
    return rows


def yearly_wide_rows(annual_parts: list[pd.DataFrame], value_col: str, methods: list[str]) -> list[dict]:
    annual = pd.concat(annual_parts, ignore_index=True)
    annual = annual[annual["method"].isin(methods)].copy()
    years = sorted(annual["year"].dropna().unique().tolist())
    rows = []
    for year in years:
        item = {"year": int(year)}
        for method in methods:
            sub = annual[(annual["year"].eq(year)) & (annual["method"].eq(method))]
            if sub.empty:
                item[METHOD_LABELS.get(method, method)] = None
                continue
            val = sub[value_col].sum()
            if value_col.endswith("_kkrw"):
                val = eok(val)
            item[METHOD_LABELS.get(method, method)] = float(val)
        rows.append(item)
    return rows


def type_total_rows(type_df: pd.DataFrame, method_order: list[str]) -> list[dict]:
    order_map = {method: idx for idx, method in enumerate(method_order)}
    type_df = type_df[type_df["method"].isin(method_order)].copy()
    type_df["method_order"] = type_df["method"].map(order_map)
    type_df = type_df.sort_values(["asset_type_label", "method_order"])
    rows = []
    for _, row in type_df.iterrows():
        rows.append(
            {
                "asset_type_label": str(row["asset_type_label"]),
                "method": str(row["method"]),
                "method_label": METHOD_LABELS.get(str(row["method"]), str(row["method"])),
                "selected_count": safe_int(row["selected_count"]),
                "investment_cost_eok": eok(row["investment_cost_kkrw"]),
                "risk_reduction_eok": eok(row["risk_reduction_kkrw"]),
                "investment_value_eok": eok(row["investment_value_kkrw"]),
                "saidi_reduction_min": safe_float(row["saidi_reduction_min"]),
                "asset_level_pi": safe_float(row["local_pi"]),
                "integrated_pi": safe_float(row["integrated_pi"]),
                "investment_efficiency": safe_float(row["investment_efficiency"]),
            }
        )
    return rows


def local_pi_annual_rows(pi_annual: pd.DataFrame) -> list[dict]:
    methods = ["pi_greedy", "pi_ilp", "pi_ga"]
    pi_annual = pi_annual[pi_annual["method"].isin(methods)].copy()
    pi_annual = pi_annual.sort_values(["asset_type_label", "method", "year"])
    rows = []
    for _, row in pi_annual.iterrows():
        rows.append(
            {
                "asset_type_label": str(row["asset_type_label"]),
                "method_label": METHOD_LABELS.get(str(row["method"]), str(row["method"])),
                "year": safe_int(row["year"]),
                "selected_count": safe_int(row["selected_count"]),
                "investment_cost_eok": eok(row["investment_cost_kkrw"]),
                "risk_reduction_eok": eok(row["risk_reduction_kkrw"]),
                "investment_value_eok": eok(row["investment_value_kkrw"]),
                "saidi_reduction_min": safe_float(row["saidi_reduction_min"]),
                "asset_level_pi": safe_float(row["local_pi"]),
                "integrated_pi": safe_float(row["integrated_pi"]),
            }
        )
    return rows


def missing_check_rows(pi_total: pd.DataFrame, pi_annual: pd.DataFrame, selected_csv: Path | None) -> list[dict]:
    selected = None
    if selected_csv and selected_csv.exists():
        selected = pd.read_csv(selected_csv, encoding="utf-8-sig")

    target_assets = ["지중개폐기", "가공배전선로"]
    rows = []
    for asset in target_assets:
        total_count = int(pi_total["asset_type_label"].eq(asset).sum())
        annual_count = int(pi_annual["asset_type_label"].eq(asset).sum())
        selected_count = int(selected["asset_type_label"].eq(asset).sum()) if selected is not None else None
        rows.append(
            {
                "asset_type_label": asset,
                "asset_level_pi_total_rows": total_count,
                "asset_level_pi_annual_rows": annual_count,
                "asset_level_pi_selected_asset_rows": selected_count,
                "check_result": "정상 출력" if total_count > 0 and annual_count > 0 and (selected_count is None or selected_count > 0) else "확인 필요",
            }
        )
    return rows


def main() -> None:
    sim_file = find_latest_simulation_file()
    run_dir = sim_file.parent
    selected_csv = run_dir / "selected_assets" / "02_pi_type_selected_assets.csv"

    final = pd.read_excel(sim_file, "07_final_comparison")
    value_annual = pd.read_excel(sim_file, "03_value_combined_annual")
    pi_annual_combined = pd.read_excel(sim_file, "05_pi_combined_annual")
    integrated_annual = pd.read_excel(sim_file, "06_integrated_annual")
    value_type_total = pd.read_excel(sim_file, "02_value_type_total")
    pi_type_total = pd.read_excel(sim_file, "04_pi_type_total")
    pi_type_annual = pd.read_excel(sim_file, "04_pi_type_annual")
    integrated_type_total = pd.read_excel(sim_file, "06_integrated_total")

    yearly_parts = [value_annual, pi_annual_combined, integrated_annual]
    data = {
        "source_file": str(sim_file),
        "sheets": {
            "README": [
                {"item": "source_file", "value": str(sim_file)},
                {"item": "purpose", "value": "제4장 최적화 시뮬레이션 그림 작성용 원천 데이터"},
                {"item": "unit_cost", "value": "금액 단위는 억 원으로 변환(kkrw / 100000)"},
                {"item": "note", "value": "예시 그림처럼 엑셀에서 막대그래프/보조축 꺾은선 그래프를 작성할 수 있도록 wide/tidy 표를 함께 제공"},
            ],
            "Final_Comparison": final_comparison_rows(final),
            "Chart_Combo_대표": combo_rows(final, REPRESENTATIVE_METHODS),
            "Chart_Combo_전체": combo_rows(final, final["method"].astype(str).tolist()),
            "Yearly_Cost": yearly_wide_rows(yearly_parts, "investment_cost_kkrw", REPRESENTATIVE_METHODS),
            "Yearly_Count": yearly_wide_rows(yearly_parts, "selected_count", REPRESENTATIVE_METHODS),
            "Yearly_IV": yearly_wide_rows(yearly_parts, "investment_value_kkrw", REPRESENTATIVE_METHODS),
            "Value_Type_Total": type_total_rows(value_type_total, ["risk_greedy", "investment_value_greedy", "investment_value_ilp", "investment_value_ga"]),
            "LocalPI_Type_Total": type_total_rows(pi_type_total, ["pi_greedy", "pi_ilp", "pi_ga"]),
            "LocalPI_IV_vs_PI": type_total_rows(
                pd.concat(
                    [
                        value_type_total[value_type_total["method"].eq("investment_value_ilp")],
                        pi_type_total[pi_type_total["method"].isin(["pi_greedy", "pi_ilp", "pi_ga"])],
                    ],
                    ignore_index=True,
                ),
                ["investment_value_ilp", "pi_greedy", "pi_ilp", "pi_ga"],
            ),
            "LocalPI_Type_Annual": local_pi_annual_rows(pi_type_annual),
            "Integrated_Type_Total": type_total_rows(integrated_type_total, ["integrated_post_type_weight_ilp", "integrated_pre_type_weight_ilp"]),
            "Missing_Check": missing_check_rows(pi_type_total, pi_type_annual, selected_csv),
        },
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(OUT_JSON)


if __name__ == "__main__":
    main()
