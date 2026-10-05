"""설비유형 가중치를 반영한 통합 PI 산정 스크립트.

이 스크립트는 MATLAB에서 산정한 설비 단위 PI(local_pi_matlab.xlsx)에
설비유형별 가중치와 비용 규모 보정계수를 결합하여 통합 PI를 산정한다.

입력:
    연구설계/05_PI_산출결과/local_pi_matlab.xlsx
    연구설계/03_설문조사/*FuzzyAHP*20*.xlsx

출력:
    연구설계/05_PI_산출결과/integrated_pi_matlab.xlsx
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


BASE_DIR = Path(__file__).resolve().parents[2]
SURVEY_DIR = BASE_DIR / "03_설문조사"
OUTPUT_DIR = BASE_DIR / "05_PI_산출결과"
LOCAL_PI_FILE = OUTPUT_DIR / "local_pi_matlab.xlsx"
OUTPUT_FILE = OUTPUT_DIR / "integrated_pi_matlab.xlsx"
YEARS = [2026, 2027, 2028, 2029, 2030]

ASSET_TYPE_LABELS = {
    "pole_transformer": "주상변압기",
    "ground_transformer": "지상변압기",
    "overhead_switch": "가공개폐기",
    "underground_switch": "지중개폐기",
    "overhead_line": "가공배전선로",
    "underground_cable": "지중케이블",
}

# 통합정규화 시트의 표 행 순서.
# 해당 시트는 한글 인코딩이 깨져도 숫자 행 위치는 유지되므로 이 순서로 매핑한다.
TYPE_WEIGHT_ROW_ORDER = [
    "pole_transformer",
    "overhead_switch",
    "overhead_line",
    "underground_switch",
    "underground_cable",
    "ground_transformer",
]


def find_survey_file() -> Path:
    """설문 폴더에서 20명 응답 완료 파일을 우선적으로 찾는다."""
    candidates = sorted(
        [path for path in SURVEY_DIR.glob("*.xlsx") if not path.name.startswith("~$")],
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(f"설문 응답 파일을 찾을 수 없습니다: {SURVEY_DIR}")

    priority = [path for path in candidates if "20" in path.stem]
    return priority[0] if priority else candidates[0]


def select_type_weight_sheet(excel_file: pd.ExcelFile) -> str:
    """통합정규화 시트를 찾는다. 실패 시 11번째 시트를 사용한다."""
    for sheet_name in excel_file.sheet_names:
        if "통합" in sheet_name and "정규" in sheet_name:
            return sheet_name
    if len(excel_file.sheet_names) > 10:
        return excel_file.sheet_names[10]
    raise ValueError("통합정규화 시트를 찾을 수 없습니다.")


def load_type_weights() -> pd.DataFrame:
    """설문 파일의 통합정규화 시트에서 설비유형 가중치를 읽는다."""
    survey_file = find_survey_file()
    excel_file = pd.ExcelFile(survey_file)
    sheet_name = select_type_weight_sheet(excel_file)
    raw = pd.read_excel(survey_file, sheet_name=sheet_name, header=None)

    numeric_mask = (
        pd.to_numeric(raw.iloc[:, 1], errors="coerce").notna()
        & pd.to_numeric(raw.iloc[:, 2], errors="coerce").notna()
    )
    table = raw.loc[numeric_mask].iloc[: len(TYPE_WEIGHT_ROW_ORDER), 0:8].copy()
    if len(table) != len(TYPE_WEIGHT_ROW_ORDER):
        raise ValueError("통합정규화 시트에서 설비유형 가중치 6개 행을 찾지 못했습니다.")

    table.columns = [
        "source_label",
        "avg_cost_10k_krw",
        "w_type_expert",
        "w_type_alpha_0_0",
        "w_type_alpha_0_3",
        "w_type_alpha_0_5",
        "w_type_alpha_0_7",
        "w_type_alpha_1_0",
    ]

    for col in table.columns[1:]:
        table[col] = pd.to_numeric(table[col], errors="coerce")

    table["asset_type"] = TYPE_WEIGHT_ROW_ORDER
    table["asset_type_label"] = table["asset_type"].map(ASSET_TYPE_LABELS)

    required_numeric = [
        "avg_cost_10k_krw",
        "w_type_expert",
        "w_type_alpha_0_0",
        "w_type_alpha_0_3",
        "w_type_alpha_0_5",
        "w_type_alpha_0_7",
        "w_type_alpha_1_0",
    ]
    if table[required_numeric].isna().any().any():
        raise ValueError("설비유형 가중치 표에 숫자로 변환할 수 없는 값이 있습니다.")

    return table[
        [
            "asset_type",
            "asset_type_label",
            "source_label",
            "avg_cost_10k_krw",
            "w_type_expert",
            "w_type_alpha_0_0",
            "w_type_alpha_0_3",
            "w_type_alpha_0_5",
            "w_type_alpha_0_7",
            "w_type_alpha_1_0",
        ]
    ].reset_index(drop=True)


def build_integrated_pi(type_weights: pd.DataFrame) -> dict[str, pd.DataFrame]:
    """설비 단위 PI와 설비유형 가중치를 결합한다."""
    if not LOCAL_PI_FILE.exists():
        raise FileNotFoundError(f"설비 단위 PI 파일을 찾을 수 없습니다: {LOCAL_PI_FILE}")

    local = pd.read_excel(LOCAL_PI_FILE, sheet_name="local_pi_asset_wide")
    merged = local.merge(type_weights, on="asset_type", how="left", validate="many_to_one")
    if merged["w_type_alpha_0_5"].isna().any():
        missing = sorted(merged.loc[merged["w_type_alpha_0_5"].isna(), "asset_type"].unique())
        raise ValueError(f"설비유형 가중치가 없는 asset_type이 있습니다: {missing}")

    alpha_cols = {
        "alpha_0_0": "w_type_alpha_0_0",
        "alpha_0_3": "w_type_alpha_0_3",
        "alpha_0_5": "w_type_alpha_0_5",
        "alpha_0_7": "w_type_alpha_0_7",
        "alpha_1_0": "w_type_alpha_1_0",
    }
    for year in YEARS:
        for alpha_name, weight_col in alpha_cols.items():
            merged[f"integrated_pi_ahp_{alpha_name}_{year}"] = (
                merged[f"local_pi_ahp_{year}"] * merged[weight_col]
            )
            merged[f"integrated_pi_fuzzy_adjusted_{alpha_name}_{year}"] = (
                merged[f"local_pi_fuzzy_adjusted_{year}"] * merged[weight_col]
            )

    default_cols = [
        "asset_id",
        "asset_type",
        "asset_type_label",
        "source_label",
        "w_type_expert",
        "w_type_alpha_0_5",
    ]
    for year in YEARS:
        default_cols.extend(
            [
                f"local_pi_ahp_{year}",
                f"local_pi_fuzzy_adjusted_{year}",
                f"integrated_pi_ahp_alpha_0_5_{year}",
                f"integrated_pi_fuzzy_adjusted_alpha_0_5_{year}",
            ]
        )
    wide_default = merged[default_cols].copy()

    summary_rows = []
    for asset_type, sub in merged.groupby("asset_type", dropna=False):
        for year in YEARS:
            summary_rows.append(
                {
                    "asset_type": asset_type,
                    "asset_type_label": ASSET_TYPE_LABELS.get(asset_type, asset_type),
                    "year": year,
                    "asset_count": len(sub),
                    "sum_local_pi_ahp": sub[f"local_pi_ahp_{year}"].sum(),
                    "sum_integrated_pi_ahp_alpha_0_5": sub[
                        f"integrated_pi_ahp_alpha_0_5_{year}"
                    ].sum(),
                    "mean_local_pi_ahp": sub[f"local_pi_ahp_{year}"].mean(),
                    "mean_integrated_pi_ahp_alpha_0_5": sub[
                        f"integrated_pi_ahp_alpha_0_5_{year}"
                    ].mean(),
                }
            )

    return {
        "type_weights": type_weights,
        "integrated_pi_asset_wide": wide_default,
        "integrated_pi_summary_type_year": pd.DataFrame(summary_rows),
    }


def write_workbook(sheets: dict[str, pd.DataFrame]) -> None:
    """엑셀 파일로 저장하고 기본 서식을 적용한다."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(OUTPUT_FILE, engine="openpyxl") as writer:
        for sheet_name, df in sheets.items():
            df.to_excel(writer, sheet_name=sheet_name[:31], index=False)

    wb = load_workbook(OUTPUT_FILE)
    header_fill = PatternFill("solid", fgColor="1F4E79")
    for ws in wb.worksheets:
        ws.freeze_panes = "A2"
        for cell in ws[1]:
            cell.fill = header_fill
            cell.font = Font(color="FFFFFF", bold=True)
            cell.alignment = Alignment(horizontal="center", vertical="center")
        for col in ws.columns:
            max_len = max(len(str(cell.value)) if cell.value is not None else 0 for cell in col)
            ws.column_dimensions[get_column_letter(col[0].column)].width = min(max(max_len + 2, 10), 35)
    wb.save(OUTPUT_FILE)


def main() -> None:
    type_weights = load_type_weights()
    sheets = build_integrated_pi(type_weights)
    write_workbook(sheets)
    print(f"saved: {OUTPUT_FILE}")
    print(type_weights.to_string(index=False))


if __name__ == "__main__":
    main()
