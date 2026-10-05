"""
Single-metric investment optimization
=====================================

비교 대상:
1. risk_greedy
2. investment_value_greedy
3. investment_value_ilp
4. investment_value_ga

공통 제약:
- 계획기간: 2026~2030
- 각 설비는 5년 동안 최대 1회 교체
- 연간 예산: 총 자산가액 proxy의 4%
- 연간 물량: 전체 설비 수의 5%

입력:
- data/input_assets.xlsx
- data/pof_5yr_output.xlsx

출력:
- outputs/single_metric_optimization.xlsx
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Any

import numpy as np
import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

try:
    import pulp
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "PuLP가 설치되어 있지 않습니다. "
        "다음 명령으로 설치 후 다시 실행하세요: python -m pip install pulp"
    ) from exc

import cnaim_clean_pipeline as ccp


BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "outputs"

INPUT_ASSETS = DATA_DIR / "input_assets.xlsx"
POF_OUTPUT = DATA_DIR / "pof_5yr_output.xlsx"
OUT_XLSX = OUTPUT_DIR / "single_metric_optimization.xlsx"
RUN_LOG = OUTPUT_DIR / "single_metric_optimization_run.log"
CBC_LOG = OUTPUT_DIR / "single_metric_optimization_cbc.log"

YEARS = [2026, 2027, 2028, 2029, 2030]
DISCOUNT_RATE = 0.05
BUDGET_RATE = 0.04
CAPACITY_RATE = 0.05

GA_RANDOM_SEED = 20260619
GA_POPULATION = 36
GA_GENERATIONS = 50
GA_MUTATION_RATE = 0.012
GA_TOURNAMENT_SIZE = 3

CANDIDATE_FLAG_COLUMN = "candidate_top30_current"
CBC_THREADS = 4


@dataclass
class ConstraintSet:
    total_asset_value_kkrw: float
    budget_rate: float
    capacity_rate: float
    annual_budget_base_kkrw: float
    annual_capacity_assets: int
    budgets_by_year: dict[int, float]
    capacities_by_year: dict[int, int]


def load_data() -> tuple[pd.DataFrame, pd.DataFrame]:
    """최적화 입력 데이터 로드."""
    pof_df = pd.read_excel(POF_OUTPUT, sheet_name="pof_5yr")
    input_df = pd.read_excel(INPUT_ASSETS, sheet_name="assets")
    if len(pof_df) != len(input_df):
        raise ValueError("input_assets와 pof_5yr_output의 행 수가 다릅니다.")
    if not pof_df["asset_id"].equals(input_df["asset_id"]):
        input_df = input_df.set_index("asset_id").loc[pof_df["asset_id"]].reset_index()
    return input_df, pof_df


def build_constraints(pof_df: pd.DataFrame) -> ConstraintSet:
    """기본 제약조건 생성."""
    total_asset_value = float(pof_df["replacement_cost_2026_kkrw"].sum())
    annual_budget_base = total_asset_value * BUDGET_RATE
    annual_capacity = int(round(len(pof_df) * CAPACITY_RATE))
    budgets = {
        year: annual_budget_base / ((1.0 + DISCOUNT_RATE) ** offset)
        for offset, year in enumerate(YEARS)
    }
    capacities = {year: annual_capacity for year in YEARS}
    return ConstraintSet(
        total_asset_value_kkrw=total_asset_value,
        budget_rate=BUDGET_RATE,
        capacity_rate=CAPACITY_RATE,
        annual_budget_base_kkrw=annual_budget_base,
        annual_capacity_assets=annual_capacity,
        budgets_by_year=budgets,
        capacities_by_year=capacities,
    )


def get_arrays(pof_df: pd.DataFrame) -> dict[str, np.ndarray]:
    """연도별 비용·위험도·투자가치 배열 생성."""
    arrays: dict[str, np.ndarray] = {
        "asset_id": pof_df["asset_id"].to_numpy(),
        "asset_type": pof_df["asset_type"].to_numpy(),
    }
    for year in YEARS:
        arrays[f"cost_{year}"] = pof_df[f"replacement_cost_{year}_kkrw"].to_numpy(dtype=float)
        arrays[f"risk_{year}"] = pof_df[f"risk_{year}_kkrw"].to_numpy(dtype=float)
        arrays[f"value_{year}"] = pof_df[f"investment_value_{year}_kkrw"].to_numpy(dtype=float)
        arrays[f"bcr_{year}"] = pof_df[f"bcr_{year}"].to_numpy(dtype=float)
    return arrays


def empty_choice(n: int) -> np.ndarray:
    """-1은 미선택, 0~4는 교체 연도 인덱스."""
    return np.full(n, -1, dtype=np.int16)


def current_candidate_mask(pof_df: pd.DataFrame) -> np.ndarray:
    """현재년도 Risk 또는 투자가치 상위 30% 후보군 마스크."""
    if CANDIDATE_FLAG_COLUMN not in pof_df.columns:
        raise ValueError(f"{CANDIDATE_FLAG_COLUMN} 컬럼이 pof_5yr_output.xlsx에 없습니다.")
    return pof_df[CANDIDATE_FLAG_COLUMN].astype(int).to_numpy() == 1


def candidate_summary_df(pof_df: pd.DataFrame, candidate_mask: np.ndarray) -> pd.DataFrame:
    """최적화 후보군 요약."""
    risk_count = int(pof_df["risk_top30_current"].sum()) if "risk_top30_current" in pof_df.columns else np.nan
    value_count = (
        int(pof_df["investment_value_top30_current"].sum())
        if "investment_value_top30_current" in pof_df.columns else np.nan
    )
    candidate_count = int(candidate_mask.sum())
    rows = [
        {"item": "total_assets", "value": len(pof_df), "note": "all assets in pof_5yr_output"},
        {"item": "risk_top30_current_assets", "value": risk_count, "note": "top 30% by risk_2026_kkrw"},
        {
            "item": "investment_value_top30_current_assets",
            "value": value_count,
            "note": "top 30% by investment_value_2026_kkrw",
        },
        {
            "item": "optimization_candidate_assets",
            "value": candidate_count,
            "note": "candidate_top30_current = 1",
        },
        {
            "item": "optimization_candidate_ratio",
            "value": candidate_count / len(pof_df),
            "note": "candidate assets / total assets",
        },
        {"item": "ga_population", "value": GA_POPULATION, "note": "GA speed-adjusted population"},
        {"item": "ga_generations", "value": GA_GENERATIONS, "note": "GA speed-adjusted generations"},
        {"item": "ga_mutation_rate", "value": GA_MUTATION_RATE, "note": "GA mutation probability"},
        {"item": "ilp_time_limit", "value": "none", "note": "CBC runs until optimality proof"},
        {"item": "ilp_gap_limit", "value": "none", "note": "no artificial MIP gap limit"},
        {"item": "ilp_threads", "value": CBC_THREADS, "note": "CBC parallel threads"},
    ]
    return pd.DataFrame(rows)


def greedy_optimize(
    pof_df: pd.DataFrame,
    constraints: ConstraintSet,
    score: str,
    candidate_mask: np.ndarray | None = None,
) -> np.ndarray:
    """연도별 greedy 최적화."""
    n = len(pof_df)
    choice = empty_choice(n)
    if candidate_mask is None:
        candidate_mask = np.ones(n, dtype=bool)
    remaining = candidate_mask.copy()
    candidate_indices = np.where(candidate_mask)[0]

    for year_idx, year in enumerate(YEARS):
        budget_left = constraints.budgets_by_year[year]
        capacity_left = constraints.capacities_by_year[year]
        score_col = f"{score}_{year}_kkrw" if score == "risk" else f"investment_value_{year}_kkrw"
        cost_col = f"replacement_cost_{year}_kkrw"

        score_values = pof_df[score_col].to_numpy(dtype=float)
        order = candidate_indices[np.argsort(-score_values[candidate_indices])]
        for idx in order:
            if not remaining[idx]:
                continue
            item_score = float(pof_df.at[idx, score_col])
            if item_score <= 0:
                continue
            item_cost = float(pof_df.at[idx, cost_col])
            if item_cost <= budget_left and capacity_left > 0:
                choice[idx] = year_idx
                remaining[idx] = False
                budget_left -= item_cost
                capacity_left -= 1
            if budget_left <= 0 or capacity_left <= 0:
                break
    return choice


def ilp_optimize(
    pof_df: pd.DataFrame,
    constraints: ConstraintSet,
    candidate_mask: np.ndarray,
) -> tuple[np.ndarray, str, float | None]:
    """투자가치 최대화 0-1 ILP."""
    n = len(pof_df)
    model = pulp.LpProblem("investment_value_ilp", pulp.LpMaximize)
    candidate_indices = np.where(candidate_mask)[0]

    variables: dict[tuple[int, int], Any] = {}
    objective_terms = []
    for year_idx, year in enumerate(YEARS):
        for i in candidate_indices:
            value = float(pof_df.at[i, f"investment_value_{year}_kkrw"])
            if value <= 0:
                continue
            var = pulp.LpVariable(f"x_{i}_{year}", lowBound=0, upBound=1, cat="Binary")
            variables[(i, year_idx)] = var
            objective_terms.append(value * var)

    model += pulp.lpSum(objective_terms)

    for i in candidate_indices:
        asset_vars = [variables[(i, y)] for y in range(len(YEARS)) if (i, y) in variables]
        if asset_vars:
            model += pulp.lpSum(asset_vars) <= 1, f"asset_once_{i}"

    for year_idx, year in enumerate(YEARS):
        year_vars = [variables[(i, year_idx)] for i in candidate_indices if (i, year_idx) in variables]
        if not year_vars:
            continue
        model += (
            pulp.lpSum(
                float(pof_df.at[i, f"replacement_cost_{year}_kkrw"]) * variables[(i, year_idx)]
                for i in candidate_indices if (i, year_idx) in variables
            )
            <= constraints.budgets_by_year[year],
            f"budget_{year}",
        )
        model += pulp.lpSum(year_vars) <= constraints.capacities_by_year[year], f"capacity_{year}"

    print(f"ILP variables: {len(variables):,}", flush=True)
    OUTPUT_DIR.mkdir(exist_ok=True)
    solver = pulp.PULP_CBC_CMD(
        msg=True,
        threads=CBC_THREADS,
        presolve=True,
        cuts=True,
    )
    result_status = model.solve(solver)
    status = pulp.LpStatus.get(result_status, str(result_status))
    objective = pulp.value(model.objective)

    choice = empty_choice(n)
    for (i, year_idx), var in variables.items():
        value = var.value()
        if value is not None and value > 0.5:
            choice[i] = year_idx
    return choice, status, objective


def choice_is_feasible(choice: np.ndarray, pof_df: pd.DataFrame, constraints: ConstraintSet) -> bool:
    """해 선택의 제약조건 충족 여부 확인."""
    for year_idx, year in enumerate(YEARS):
        selected = np.where(choice == year_idx)[0]
        if len(selected) > constraints.capacities_by_year[year]:
            return False
        cost = pof_df.iloc[selected][f"replacement_cost_{year}_kkrw"].sum()
        if cost > constraints.budgets_by_year[year] + 1e-6:
            return False
    return True


def repair_choice(choice: np.ndarray, pof_df: pd.DataFrame, constraints: ConstraintSet) -> np.ndarray:
    """GA 개체를 제약조건에 맞게 복구한다."""
    repaired = choice.copy()
    for year_idx, year in enumerate(YEARS):
        while True:
            selected = np.where(repaired == year_idx)[0]
            if len(selected) == 0:
                break
            cost_values = pof_df.iloc[selected][f"replacement_cost_{year}_kkrw"].to_numpy(dtype=float)
            value_values = pof_df.iloc[selected][f"investment_value_{year}_kkrw"].to_numpy(dtype=float)
            total_cost = float(cost_values.sum())
            count = len(selected)
            if count <= constraints.capacities_by_year[year] and total_cost <= constraints.budgets_by_year[year]:
                break
            efficiency = value_values / np.maximum(cost_values, 1.0)
            remove_local = int(np.argmin(efficiency))
            repaired[selected[remove_local]] = -1
    return repaired


def objective_value(choice: np.ndarray, pof_df: pd.DataFrame) -> float:
    """투자가치 목적함수값."""
    total = 0.0
    for year_idx, year in enumerate(YEARS):
        selected = np.where(choice == year_idx)[0]
        if len(selected) > 0:
            total += float(pof_df.iloc[selected][f"investment_value_{year}_kkrw"].sum())
    return total


def matrix_from_year_columns(pof_df: pd.DataFrame, column_prefix: str, column_suffix: str = "_kkrw") -> np.ndarray:
    """연도별 열을 NumPy 행렬로 변환한다."""
    return np.column_stack([
        pof_df[f"{column_prefix}_{year}{column_suffix}"].to_numpy(dtype=float)
        for year in YEARS
    ])


def objective_value_array(choice: np.ndarray, value_matrix: np.ndarray) -> float:
    """배열 기반 투자가치 목적함수값."""
    selected = np.where(choice >= 0)[0]
    if len(selected) == 0:
        return 0.0
    selected_year = choice[selected].astype(int)
    return float(value_matrix[selected, selected_year].sum())


def repair_choice_array(choice: np.ndarray, cost_matrix: np.ndarray, value_matrix: np.ndarray,
                        constraints: ConstraintSet) -> np.ndarray:
    """GA 개체를 배열 기반으로 빠르게 제약조건에 맞춘다."""
    repaired = choice.copy()
    budgets = np.array([constraints.budgets_by_year[year] for year in YEARS], dtype=float)
    capacities = np.array([constraints.capacities_by_year[year] for year in YEARS], dtype=int)
    for year_idx, _year in enumerate(YEARS):
        selected = np.where(repaired == year_idx)[0]
        if len(selected) == 0:
            continue

        costs = cost_matrix[selected, year_idx]
        values = value_matrix[selected, year_idx]
        if len(selected) <= capacities[year_idx] and float(costs.sum()) <= budgets[year_idx]:
            continue

        efficiency = values / np.maximum(costs, 1.0)
        ordered = selected[np.argsort(-efficiency)]
        keep: list[int] = []
        budget_left = float(budgets[year_idx])
        capacity_left = int(capacities[year_idx])
        for idx in ordered:
            item_cost = float(cost_matrix[idx, year_idx])
            if item_cost <= budget_left and capacity_left > 0:
                keep.append(int(idx))
                budget_left -= item_cost
                capacity_left -= 1
        repaired[selected] = -1
        if keep:
            repaired[np.array(keep, dtype=int)] = year_idx
    return repaired


def make_seed_choice_array(cost_matrix: np.ndarray, value_matrix: np.ndarray, risk_matrix: np.ndarray,
                           constraints: ConstraintSet, ranking: str,
                           rng: np.random.Generator,
                           candidate_mask: np.ndarray | None = None) -> np.ndarray:
    """GA 초기 개체를 배열 기반으로 생성한다."""
    n = cost_matrix.shape[0]
    choice = empty_choice(n)
    if candidate_mask is None:
        candidate_mask = np.ones(n, dtype=bool)
    remaining = candidate_mask.copy()
    candidate_indices = np.where(candidate_mask)[0]

    for year_idx, year in enumerate(YEARS):
        budget_left = constraints.budgets_by_year[year]
        capacity_left = constraints.capacities_by_year[year]
        cost = cost_matrix[:, year_idx]
        value = value_matrix[:, year_idx]

        if ranking == "risk":
            score = risk_matrix[:, year_idx]
        elif ranking == "value":
            score = value
        else:
            efficiency = value / np.maximum(cost, 1.0)
            score = efficiency * rng.normal(1.0, 0.10, n)

        order = candidate_indices[np.argsort(-score[candidate_indices])]
        for idx in order:
            if not remaining[idx] or value[idx] <= 0:
                continue
            item_cost = float(cost[idx])
            if item_cost <= budget_left and capacity_left > 0:
                choice[idx] = year_idx
                remaining[idx] = False
                budget_left -= item_cost
                capacity_left -= 1
            if budget_left <= 0 or capacity_left <= 0:
                break
    return choice


def make_seed_choice(pof_df: pd.DataFrame, constraints: ConstraintSet, ranking: str) -> np.ndarray:
    """GA 초기 개체 생성을 위한 greedy seed."""
    if ranking == "risk":
        return greedy_optimize(pof_df, constraints, "risk")
    if ranking == "value":
        return greedy_optimize(pof_df, constraints, "investment_value")

    n = len(pof_df)
    choice = empty_choice(n)
    remaining = np.ones(n, dtype=bool)
    rng = np.random.default_rng(GA_RANDOM_SEED + abs(hash(ranking)) % 10_000)
    for year_idx, year in enumerate(YEARS):
        budget_left = constraints.budgets_by_year[year]
        capacity_left = constraints.capacities_by_year[year]
        value = pof_df[f"investment_value_{year}_kkrw"].to_numpy(dtype=float)
        cost = pof_df[f"replacement_cost_{year}_kkrw"].to_numpy(dtype=float)
        efficiency = value / np.maximum(cost, 1.0)
        noise = rng.normal(1.0, 0.10, len(pof_df))
        order = np.argsort(-(efficiency * noise))
        for idx in order:
            if not remaining[idx] or value[idx] <= 0:
                continue
            if cost[idx] <= budget_left and capacity_left > 0:
                choice[idx] = year_idx
                remaining[idx] = False
                budget_left -= cost[idx]
                capacity_left -= 1
            if budget_left <= 0 or capacity_left <= 0:
                break
    return choice


def ga_optimize(
    pof_df: pd.DataFrame,
    constraints: ConstraintSet,
    candidate_mask: np.ndarray,
) -> tuple[np.ndarray, float]:
    """투자가치 기반 GA 최적화."""
    rng = np.random.default_rng(GA_RANDOM_SEED)
    cost_matrix = matrix_from_year_columns(pof_df, "replacement_cost")
    value_matrix = matrix_from_year_columns(pof_df, "investment_value")
    risk_matrix = matrix_from_year_columns(pof_df, "risk")
    population: list[np.ndarray] = [
        make_seed_choice_array(cost_matrix, value_matrix, risk_matrix, constraints, "value", rng, candidate_mask),
        make_seed_choice_array(cost_matrix, value_matrix, risk_matrix, constraints, "risk", rng, candidate_mask),
    ]
    while len(population) < GA_POPULATION:
        population.append(
            make_seed_choice_array(cost_matrix, value_matrix, risk_matrix, constraints,
                                   f"random_{len(population)}", rng, candidate_mask)
        )

    population = [repair_choice_array(ind, cost_matrix, value_matrix, constraints) for ind in population]
    scores = np.array([objective_value_array(ind, value_matrix) for ind in population], dtype=float)

    best_idx = int(np.argmax(scores))
    best = population[best_idx].copy()
    best_score = float(scores[best_idx])

    for _gen in range(GA_GENERATIONS):
        new_population = [best.copy()]
        while len(new_population) < GA_POPULATION:
            parent_a = tournament_select(population, scores, rng)
            parent_b = tournament_select(population, scores, rng)
            child = uniform_crossover(parent_a, parent_b, rng)
            child = mutate_choice(child, rng, candidate_mask)
            child = repair_choice_array(child, cost_matrix, value_matrix, constraints)
            new_population.append(child)
        population = new_population
        scores = np.array([objective_value_array(ind, value_matrix) for ind in population], dtype=float)
        gen_best_idx = int(np.argmax(scores))
        if float(scores[gen_best_idx]) > best_score:
            best_score = float(scores[gen_best_idx])
            best = population[gen_best_idx].copy()
    return best, best_score


def tournament_select(population: list[np.ndarray], scores: np.ndarray,
                      rng: np.random.Generator) -> np.ndarray:
    """토너먼트 선택."""
    idxs = rng.choice(len(population), size=GA_TOURNAMENT_SIZE, replace=False)
    best_idx = idxs[int(np.argmax(scores[idxs]))]
    return population[int(best_idx)]


def uniform_crossover(parent_a: np.ndarray, parent_b: np.ndarray,
                      rng: np.random.Generator) -> np.ndarray:
    """균일 교차."""
    mask = rng.random(len(parent_a)) < 0.5
    child = parent_a.copy()
    child[mask] = parent_b[mask]
    return child


def mutate_choice(choice: np.ndarray, rng: np.random.Generator,
                  candidate_mask: np.ndarray | None = None) -> np.ndarray:
    """돌연변이."""
    mutated = choice.copy()
    mutation_mask = rng.random(len(mutated)) < GA_MUTATION_RATE
    if candidate_mask is not None:
        mutation_mask &= candidate_mask
    mutation_indices = np.where(mutation_mask)[0]
    if len(mutation_indices) > 0:
        mutated[mutation_indices] = rng.choice([-1, 0, 1, 2, 3, 4], size=len(mutation_indices),
                                               p=[0.55, 0.09, 0.09, 0.09, 0.09, 0.09])
    return mutated


def selected_assets_df(method: str, choice: np.ndarray, pof_df: pd.DataFrame) -> pd.DataFrame:
    """선택 설비 상세 테이블."""
    rows = []
    for idx, year_idx in enumerate(choice):
        if year_idx < 0:
            continue
        year = YEARS[int(year_idx)]
        rows.append({
            "method": method,
            "asset_id": pof_df.at[idx, "asset_id"],
            "asset_type": pof_df.at[idx, "asset_type"],
            "risk_top30_current": pof_df.at[idx, "risk_top30_current"] if "risk_top30_current" in pof_df.columns else None,
            "investment_value_top30_current": (
                pof_df.at[idx, "investment_value_top30_current"]
                if "investment_value_top30_current" in pof_df.columns else None
            ),
            "candidate_top30_current": (
                pof_df.at[idx, "candidate_top30_current"]
                if "candidate_top30_current" in pof_df.columns else None
            ),
            "replacement_year": year,
            "replacement_cost_kkrw": pof_df.at[idx, f"replacement_cost_{year}_kkrw"],
            "risk_at_replacement_kkrw": pof_df.at[idx, f"risk_{year}_kkrw"],
            "investment_value_kkrw": pof_df.at[idx, f"investment_value_{year}_kkrw"],
            "bcr": pof_df.at[idx, f"bcr_{year}"],
            "saidi_at_replacement_min": pof_df.at[idx, f"saidi_{year}_min"],
            "pof_at_replacement": pof_df.at[idx, f"pof_{year}"],
        })
    out = pd.DataFrame(rows)
    if not out.empty:
        out = out.sort_values(["method", "replacement_year", "investment_value_kkrw"],
                              ascending=[True, True, False]).reset_index(drop=True)
        out.insert(0, "selection_rank", out.groupby(["method", "replacement_year"]).cumcount() + 1)
    return out


def compute_effect_summary(method: str, choice: np.ndarray, pof_df: pd.DataFrame,
                           input_df: pd.DataFrame, constraints: ConstraintSet) -> tuple[pd.DataFrame, pd.DataFrame]:
    """연도별 성과 요약과 설비군별 요약."""
    total_customers = float(input_df["connected_customers"].sum())
    input_by_id = input_df.set_index("asset_id")
    pof_by_id = pof_df.set_index("asset_id")

    baseline_risk = {year: float(pof_df[f"risk_{year}_kkrw"].sum()) for year in YEARS}
    baseline_saidi = {year: float(pof_df[f"saidi_{year}_min"].sum()) for year in YEARS}
    baseline_failures = {year: float(pof_df[f"pof_{year}"].sum()) for year in YEARS}
    risk_reduction = {year: 0.0 for year in YEARS}
    saidi_reduction = {year: 0.0 for year in YEARS}
    failure_reduction = {year: 0.0 for year in YEARS}

    selected_detail = selected_assets_df(method, choice, pof_df)
    if not selected_detail.empty:
        for row in selected_detail.itertuples(index=False):
            asset_id = row.asset_id
            replacement_year = int(row.replacement_year)
            replacement_offset = YEARS.index(replacement_year)
            input_row = input_by_id.loc[asset_id]
            pof_row = pof_by_id.loc[asset_id]
            state = ccp.current_asset_state(input_row)
            post_pofs = ccp.pof_series_after_replacement(input_row, replacement_offset, state)
            cof_total = float(pof_row["cof_total_kkrw"])
            connected_customers = float(pof_row["connected_customers"])
            outage_duration = float(pof_row["outage_duration_min"])
            for local_idx, future_offset in enumerate(range(replacement_offset, len(YEARS))):
                future_year = YEARS[future_offset]
                before_pof = float(pof_row[f"pof_{future_year}"])
                after_pof = float(post_pofs[local_idx])
                delta_pof = max(before_pof - after_pof, 0.0)
                failure_reduction[future_year] += delta_pof
                risk_reduction[future_year] += delta_pof * cof_total
                saidi_reduction[future_year] += (
                    delta_pof * outage_duration * connected_customers / total_customers
                )

    annual_rows = []
    for year in YEARS:
        selected_year = selected_detail[selected_detail["replacement_year"] == year] if not selected_detail.empty else pd.DataFrame()
        selected_count = int(len(selected_year))
        cost = float(selected_year["replacement_cost_kkrw"].sum()) if selected_count else 0.0
        value = float(selected_year["investment_value_kkrw"].sum()) if selected_count else 0.0
        risk_at_selection = float(selected_year["risk_at_replacement_kkrw"].sum()) if selected_count else 0.0
        saidi_at_selection = float(selected_year["saidi_at_replacement_min"].sum()) if selected_count else 0.0
        annual_rows.append({
            "method": method,
            "year": year,
            "selected_count": selected_count,
            "capacity_limit": constraints.capacities_by_year[year],
            "capacity_used_pct": selected_count / constraints.capacities_by_year[year] if constraints.capacities_by_year[year] else 0.0,
            "investment_cost_kkrw": cost,
            "budget_limit_kkrw": constraints.budgets_by_year[year],
            "budget_used_pct": cost / constraints.budgets_by_year[year] if constraints.budgets_by_year[year] else 0.0,
            "risk_at_selection_kkrw": risk_at_selection,
            "risk_reduction_kkrw": risk_reduction[year],
            "investment_value_kkrw": value,
            "bcr": value / cost if cost > 0 else 0.0,
            "baseline_risk_kkrw": baseline_risk[year],
            "post_investment_risk_kkrw": baseline_risk[year] - risk_reduction[year],
            "baseline_saidi_min": baseline_saidi[year],
            "saidi_reduction_min": saidi_reduction[year],
            "post_investment_saidi_min": baseline_saidi[year] - saidi_reduction[year],
            "baseline_expected_failures": baseline_failures[year],
            "expected_failure_reduction": failure_reduction[year],
            "post_expected_failures": baseline_failures[year] - failure_reduction[year],
        })

    annual_df = pd.DataFrame(annual_rows)

    if selected_detail.empty:
        asset_type_df = pd.DataFrame(columns=[
            "method", "replacement_year", "asset_type", "selected_count",
            "investment_cost_kkrw", "investment_value_kkrw", "risk_at_selection_kkrw",
        ])
    else:
        asset_type_df = (
            selected_detail
            .groupby(["method", "replacement_year", "asset_type"], as_index=False)
            .agg(
                selected_count=("asset_id", "count"),
                investment_cost_kkrw=("replacement_cost_kkrw", "sum"),
                investment_value_kkrw=("investment_value_kkrw", "sum"),
                risk_at_selection_kkrw=("risk_at_replacement_kkrw", "sum"),
            )
        )
    return annual_df, asset_type_df


def method_total_summary(annual_df: pd.DataFrame) -> pd.DataFrame:
    """방법별 총괄 요약."""
    rows = []
    for method, sub in annual_df.groupby("method"):
        total_cost = float(sub["investment_cost_kkrw"].sum())
        total_value = float(sub["investment_value_kkrw"].sum())
        rows.append({
            "method": method,
            "total_selected_count": int(sub["selected_count"].sum()),
            "total_investment_cost_kkrw": total_cost,
            "total_investment_value_kkrw": total_value,
            "total_bcr": total_value / total_cost if total_cost > 0 else 0.0,
            "total_risk_reduction_kkrw": float(sub["risk_reduction_kkrw"].sum()),
            "total_saidi_reduction_min": float(sub["saidi_reduction_min"].sum()),
            "total_expected_failure_reduction": float(sub["expected_failure_reduction"].sum()),
            "avg_budget_used_pct": float(sub["budget_used_pct"].mean()),
            "avg_capacity_used_pct": float(sub["capacity_used_pct"].mean()),
        })
    return pd.DataFrame(rows).sort_values("total_investment_value_kkrw", ascending=False)


def constraints_df(constraints: ConstraintSet) -> pd.DataFrame:
    """제약조건 출력 테이블."""
    rows = [{
        "item": "total_asset_value_proxy_kkrw",
        "value": constraints.total_asset_value_kkrw,
        "note": "sum of replacement_cost_2026_kkrw",
    }, {
        "item": "budget_rate",
        "value": constraints.budget_rate,
        "note": "annual budget as ratio of total asset value proxy",
    }, {
        "item": "capacity_rate",
        "value": constraints.capacity_rate,
        "note": "annual construction capacity as ratio of total asset count",
    }, {
        "item": "annual_budget_base_2026_kkrw",
        "value": constraints.annual_budget_base_kkrw,
        "note": "base annual budget before discounting",
    }, {
        "item": "annual_capacity_assets",
        "value": constraints.annual_capacity_assets,
        "note": "round(total assets * 5%)",
    }]
    for offset, year in enumerate(YEARS):
        rows.append({
            "item": f"budget_{year}_kkrw",
            "value": constraints.budgets_by_year[year],
            "note": f"annual budget discounted to PV, offset={offset}",
        })
        rows.append({
            "item": f"capacity_{year}_assets",
            "value": constraints.capacities_by_year[year],
            "note": "same capacity every year",
        })
    return pd.DataFrame(rows)


def write_results(sheets: dict[str, pd.DataFrame]) -> None:
    """결과 Excel 저장."""
    OUTPUT_DIR.mkdir(exist_ok=True)
    with pd.ExcelWriter(OUT_XLSX, engine="openpyxl") as writer:
        for sheet_name, df in sheets.items():
            df.to_excel(writer, sheet_name=sheet_name[:31], index=False)

    wb = load_workbook(OUT_XLSX)
    header_fill = PatternFill("solid", fgColor="1F4E79")
    alt_fill = PatternFill("solid", fgColor="DEEAF1")
    for ws in wb.worksheets:
        ws.freeze_panes = "A2"
        ws.row_dimensions[1].height = 28
        for cell in ws[1]:
            cell.font = Font(bold=True, color="FFFFFF", size=9)
            cell.fill = header_fill
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        for row_idx in range(2, ws.max_row + 1):
            if row_idx % 2 == 0:
                for cell in ws[row_idx]:
                    cell.fill = alt_fill
        for col_idx in range(1, ws.max_column + 1):
            header = str(ws.cell(1, col_idx).value or "")
            width = min(max(len(header) + 3, 12), 30)
            ws.column_dimensions[get_column_letter(col_idx)].width = width
            for row_idx in range(2, min(ws.max_row, 200) + 1):
                ws.cell(row_idx, col_idx).alignment = Alignment(horizontal="center", vertical="center")
    wb.save(OUT_XLSX)


def main() -> None:
    input_df, pof_df = load_data()
    constraints = build_constraints(pof_df)
    candidate_mask = current_candidate_mask(pof_df)

    print("single metric optimization", flush=True)
    print(f"assets: {len(pof_df):,}", flush=True)
    print(f"current top30 candidates: {int(candidate_mask.sum()):,}", flush=True)
    print(f"annual budget base: {constraints.annual_budget_base_kkrw:,.0f} kkrw", flush=True)
    print(f"annual capacity: {constraints.annual_capacity_assets:,} assets", flush=True)
    print(f"GA population: {GA_POPULATION}, generations: {GA_GENERATIONS}", flush=True)

    print("running risk greedy...", flush=True)
    risk_choice = greedy_optimize(pof_df, constraints, "risk", candidate_mask)
    print("running investment value greedy...", flush=True)
    value_choice = greedy_optimize(pof_df, constraints, "investment_value", candidate_mask)

    print("running ILP...", flush=True)
    ilp_choice, ilp_status, ilp_objective = ilp_optimize(pof_df, constraints, candidate_mask)
    print(f"ILP status: {ilp_status}, objective={ilp_objective}", flush=True)

    print("running GA...", flush=True)
    ga_choice, ga_objective = ga_optimize(pof_df, constraints, candidate_mask)
    print(f"GA objective={ga_objective}", flush=True)

    solutions = {
        "risk_greedy": risk_choice,
        "investment_value_greedy": value_choice,
        "investment_value_ilp": ilp_choice,
        "investment_value_ga": ga_choice,
    }

    annual_parts = []
    asset_type_parts = []
    selected_parts = []
    feasibility_rows = []
    for method, choice in solutions.items():
        annual_df, asset_type_df = compute_effect_summary(method, choice, pof_df, input_df, constraints)
        selected_df = selected_assets_df(method, choice, pof_df)
        annual_parts.append(annual_df)
        asset_type_parts.append(asset_type_df)
        selected_parts.append(selected_df)
        feasibility_rows.append({
            "method": method,
            "is_feasible": choice_is_feasible(choice, pof_df, constraints),
            "is_within_candidate_pool": bool(np.all(candidate_mask[choice >= 0])),
            "selected_assets": int((choice >= 0).sum()),
            "objective_investment_value_kkrw": objective_value(choice, pof_df),
        })

    annual_summary = pd.concat(annual_parts, ignore_index=True)
    asset_type_summary = pd.concat(asset_type_parts, ignore_index=True)
    selected_assets = pd.concat(selected_parts, ignore_index=True)
    total_summary = method_total_summary(annual_summary)
    feasibility = pd.DataFrame(feasibility_rows)
    solver_status = pd.DataFrame([
        {
            "solver": "ILP_CBC",
            "status": ilp_status,
            "objective_kkrw": ilp_objective,
            "time_limit": "none",
            "gap_limit": "none",
            "threads": CBC_THREADS,
            "log_file": str(RUN_LOG),
            "candidate_pool": CANDIDATE_FLAG_COLUMN,
        },
        {
            "solver": "GA",
            "status": "completed",
            "objective_kkrw": ga_objective,
            "time_limit": "generation_based",
            "gap_limit": "not_applicable",
            "threads": "not_applicable",
            "log_file": "not_applicable",
            "candidate_pool": CANDIDATE_FLAG_COLUMN,
        },
    ])

    write_results({
        "candidate_summary": candidate_summary_df(pof_df, candidate_mask),
        "constraints": constraints_df(constraints),
        "total_summary": total_summary,
        "annual_summary": annual_summary,
        "asset_type_summary": asset_type_summary,
        "selected_assets": selected_assets,
        "feasibility": feasibility,
        "solver_status": solver_status,
    })
    print(f"saved: {OUT_XLSX}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
