%% 박사논문 민감도 분석 알고리즘 - 본문용 강건성 검증 버전
% 목적: 논문 핵심 명제가 예산·물량·KPI 제약·운영목표 가중치 변화에도 유지되는지 확인한다.
%       전체 격자 탐색이 아닌 대표 조건 기반 강건성 분석으로, 결과는 논문 본문에 직접 활용 가능하다.
%
% 실행:
%   run("code/sensitivity_analysis_fast.m")
%
% 기본값 (환경변수로 덮어쓸 수 있음):
%   예산 배율:     [0.5, 0.75, 1.0, 1.25, 1.5]  (5단계)
%   물량 배율:     [0.5, 1.0, 1.5]              (3단계)
%   SAIDI 상한:    [Inf, 1.00, 0.98, 0.95]      (4단계)
%   Risk 상한:     [Inf, 1.15, 1.10, 1.05]      (4단계)
%   운영목표 가중치: 전문가 평균 포함 7개 시나리오 (격자 비활성화)
%   ILP 시간 제한: 60초  (기존 600초)
%   ILP 갭 허용:   0.5% (기존 0.1%)
%   추가 옵션:     greedy 초기해 제공 + 전처리 강화 (수렴 가속)
%   scope당 시나리오: 약 82개 / 총 246개
%
% 추가 출력 시트:
%   09_rank_by_scenario   : 시나리오별 방법 투자가치 순위
%   10_robustness_summary : 방법별 평균·중앙값·표준편차·변동계수
%   11_baseline_improvement: 기준조건 대비 개선율
%   12_feasibility_summary: 제약 충족률 (%)
%   13_conclusion_check   : 논문 핵심 명제 유지율 (%)

clear; clc;

% ── 본문용 기본 ILP 설정 (환경변수가 없을 때만 적용됨) ───────────────────
if isempty(strtrim(getenv("SENS_ILP_MAX_TIME")))
    setenv("SENS_ILP_MAX_TIME", "60");
end
if isempty(strtrim(getenv("SENS_ILP_REL_GAP")))
    setenv("SENS_ILP_REL_GAP", "0.005");
end
setenv("SENS_WEIGHT_GRID_STEP", "0.1");  % 원본과 동일한 246개 시나리오 유지 (ILP 속도 개선으로 커버)

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputRoot = fullfile(baseDir, "outputs");
runStamp = char(string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
runDir = fullfile(outputRoot, ['sensitivity_analysis_fast_' runStamp]);
figureDir = fullfile(runDir, "figures");
mkdir(runDir);
mkdir(figureDir);

figureFontName = "Malgun Gothic";
set(groot, "defaultAxesFontName", figureFontName);
set(groot, "defaultTextFontName", figureFontName);
set(groot, "defaultLegendFontName", figureFontName);

diary(fullfile(runDir, "sensitivity_analysis_fast.log"));
diary on;
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

years = [2026 2027 2028 2029 2030];
assetTypes = ["pole_transformer", "ground_transformer", "overhead_switch", ...
    "underground_switch", "overhead_line", "underground_cable"];
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", ...
    "지중개폐기", "가공배전선로", "지중케이블"];

baseBudgetRate = 0.04;
baseCapacityRate = 0.05;
discountRate = 0.05;
candidateQuantile = 0.70;

% 시나리오 기본값: 전체 버전과 동일하게 유지 (그래프 해상도 확보)
% ILP 속도 개선(초기해·전처리·갭 완화)으로 실행 시간을 단축한다.
budgetMultipliers   = readVectorEnv("SENS_BUDGET_MULTIPLIERS",   0.5:0.1:1.5);
capacityMultipliers = readVectorEnv("SENS_CAPACITY_MULTIPLIERS", 0.5:0.1:1.5);
saidiCapRates       = readVectorEnv("SENS_SAIDI_CAP_RATES",      [Inf 1.00 0.98 0.95]);
riskCapRates        = readVectorEnv("SENS_RISK_CAP_RATES",       [Inf 1.15 1.10 1.05]);
fullGrid = readLogicalEnv("SENS_FULL_GRID", false);
methodList = readStringListEnv("SENS_METHODS", ...
    ["investment_value_ilp", "local_pi_ilp", "integrated_pi_ilp"]);
methodOverride = strlength(strtrim(string(getenv("SENS_METHODS")))) > 0;
scopeList = readStringListEnv("SENS_SCOPES", ...
    ["risk_value_screening", "local_pi_portfolio", "integrated_pi_portfolio"]);
includeWeightScenarios = readLogicalEnv("SENS_INCLUDE_WEIGHT_SCENARIOS", true);

fprintf("=== Fast 민감도 분석 시작 ===\n");
fprintf("runDir: %s\n", runDir);
fprintf("ILP 시간 제한: %s초 / 갭 허용: %s%%\n", getenv("SENS_ILP_MAX_TIME"), getenv("SENS_ILP_REL_GAP"));
writeStatus(runDir, "Fast 민감도 분석 시작");

%% 1. 입력 데이터 로드
pof = readtable(fullfile(dataDir, "pof_5yr_output.xlsx"), ...
    "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
localPi = readtable(fullfile(outputRoot, "local_pi_matlab.xlsx"), ...
    "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
criteriaWeights = readtable(fullfile(outputRoot, "local_pi_matlab.xlsx"), ...
    "Sheet", "criteria_weights", "VariableNamingRule", "preserve");
ahpSubWeights = readtable(fullfile(outputRoot, "local_pi_matlab.xlsx"), ...
    "Sheet", "ahp_sub_weights", "VariableNamingRule", "preserve");
integratedPi = readtable(fullfile(outputRoot, "integrated_pi_matlab.xlsx"), ...
    "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");

if height(pof) ~= height(localPi) || any(string(pof.asset_id) ~= string(localPi.asset_id))
    error("PoF 출력과 Local PI 파일의 asset_id가 일치하지 않습니다.");
end
if height(pof) ~= height(integratedPi) || any(string(pof.asset_id) ~= string(integratedPi.asset_id))
    error("PoF 출력과 Integrated PI 파일의 asset_id가 일치하지 않습니다.");
end

pof.asset_type_label = mapAssetLabels(string(pof.asset_type), assetTypes, assetLabels);
if ismember("w_type_alpha_0_5", integratedPi.Properties.VariableNames)
    pof.w_type_alpha_0_5 = integratedPi.w_type_alpha_0_5;
else
    pof.w_type_alpha_0_5 = ones(height(pof), 1);
end

for y = 1:numel(years)
    year = years(y);
    pof.(sprintf("local_pi_%d", year)) = localPi.(sprintf("local_pi_ahp_%d", year));
    pof.(sprintf("integrated_pi_%d", year)) = integratedPi.(sprintf("integrated_pi_ahp_alpha_0_5_%d", year));
end

candidateMask = buildTypeCandidateMask(pof, assetTypes, candidateQuantile);
pof.candidate_type_top30_current = candidateMask;

baselineKpi = buildBaselineKpiTable(pof, years);
weightScenarioTable = buildWeightScenarioTable(criteriaWeights, includeWeightScenarios);
scopeTable = buildScopeTable(scopeList);
scenarioTable = buildScenarioTable(budgetMultipliers, capacityMultipliers, saidiCapRates, riskCapRates, fullGrid, weightScenarioTable, scopeTable);
configTable = buildConfigTable(runStamp, baseBudgetRate, baseCapacityRate, discountRate, ...
    candidateQuantile, fullGrid, methodList, includeWeightScenarios, scopeList);

resultFile = fullfile(runDir, "sensitivity_analysis_results.xlsx");
writeResultTable(configTable, resultFile, "00_run_config", "error");
writeResultTable(baselineKpi, resultFile, "01_baseline_kpi", "error");
writeResultTable(scopeTable, resultFile, "02_scope_definition", "error");
writeResultTable(weightScenarioTable, resultFile, "02_weight_scenarios", "error");
writeResultTable(scenarioTable, resultFile, "02b_scenarios", "error");

%% 2. 시나리오별 ILP 수행
annualParts = {};
totalParts = {};
typeParts = {};
constraintParts = {};
solverParts = {};

allAssetIdx = (1:height(pof))';

for s = 1:height(scenarioTable)
    scenario = scenarioTable(s, :);
    pofScenario = applyWeightScenarioToPof(pof, localPi, ahpSubWeights, scenario, years);

    scenarioIdText = char(string(scenario.scenario_id));
    fprintf("\n[시나리오 %03d/%03d] %s\n", s, height(scenarioTable), scenarioIdText);
    writeStatus(runDir, sprintf("시나리오 %03d/%03d 실행: %s", s, height(scenarioTable), scenarioIdText));

    currentMethods = methodsForScope(string(scenario.simulation_scope), methodList, methodOverride);
    for m = 1:numel(currentMethods)
        method = currentMethods(m);
        fprintf("  - %s 실행\n", method);
        tic;
        [choiceGlobal, solverInfo, objectiveName, constraints] = runScopeMethod( ...
            pofScenario, candidateMask, allAssetIdx, assetTypes, years, scenario, method, ...
            baseBudgetRate, baseCapacityRate, discountRate);
        elapsedSec = toc;

        [annual, total, typeSummary, constraintCheck] = summarizeSensitivityChoice( ...
            pofScenario, choiceGlobal, scenario, method, objectiveName, constraints, years, assetTypes, assetLabels);

        solverRow = cell2table({ ...
            string(scenario.scenario_id), string(scenario.scenario_group), ...
            string(scenario.simulation_scope), string(scenario.simulation_name), method, objectiveName, ...
            string(scenario.weight_scenario_id), string(scenario.weight_scenario_name), ...
            scenario.w_economy, scenario.w_reliability, scenario.w_safety_environment, ...
            string(solverInfo.solver), solverInfo.exitflag, string(solverInfo.message), ...
            solverInfo.objective, elapsedSec}, ...
            'VariableNames', {'scenario_id', 'scenario_group', 'simulation_scope', 'simulation_name', 'method', 'objective', ...
            'weight_scenario_id', 'weight_scenario_name', 'w_economy', 'w_reliability', 'w_safety_environment', ...
            'solver', 'exitflag', 'message', 'objective_value', 'elapsed_sec'});

        annualParts{end + 1} = annual; %#ok<AGROW>
        totalParts{end + 1} = total; %#ok<AGROW>
        typeParts{end + 1} = typeSummary; %#ok<AGROW>
        constraintParts{end + 1} = constraintCheck; %#ok<AGROW>
        solverParts{end + 1} = solverRow; %#ok<AGROW>
    end

    if mod(s, 5) == 0 || s == height(scenarioTable)
        writeIntermediateResults(resultFile, annualParts, totalParts, typeParts, constraintParts, solverParts);
    end
end

annualSummary = vertcat(annualParts{:});
totalSummary = vertcat(totalParts{:});
typeSummary = vertcat(typeParts{:});
constraintCheck = vertcat(constraintParts{:});
solverStatus = vertcat(solverParts{:});

figureManifest = saveSensitivityFiguresV2(totalSummary, annualSummary, typeSummary, constraintCheck, figureDir);

%% 3. 강건성 요약 시트 생성
fprintf("\n강건성 요약 시트 생성 중...\n");
rankTable       = buildRankTable(totalSummary);
robustness      = buildRobustnessSummary(totalSummary);
baselineImprove = buildBaselineImprovement(totalSummary, annualSummary);
feasibility     = buildFeasibilitySummary(constraintCheck, totalSummary);
conclusionCheck = buildConclusionCheck(totalSummary, annualSummary);

finalResultFile = fullfile(runDir, "sensitivity_analysis_results_final.xlsx");
finalResultFile = writeResultTable(configTable, finalResultFile, "00_run_config", "fallback");
finalResultFile = writeResultTable(baselineKpi, finalResultFile, "01_baseline_kpi", "fallback");
finalResultFile = writeResultTable(scopeTable, finalResultFile, "02_scope_definition", "fallback");
finalResultFile = writeResultTable(weightScenarioTable, finalResultFile, "02_weight_scenarios", "fallback");
finalResultFile = writeResultTable(scenarioTable, finalResultFile, "02b_scenarios", "fallback");
finalResultFile = writeResultTable(annualSummary, finalResultFile, "03_annual_summary", "fallback");
finalResultFile = writeResultTable(totalSummary, finalResultFile, "04_total_summary", "fallback");
finalResultFile = writeResultTable(typeSummary, finalResultFile, "05_type_summary", "fallback");
finalResultFile = writeResultTable(constraintCheck, finalResultFile, "06_constraint_check", "fallback");
finalResultFile = writeResultTable(solverStatus, finalResultFile, "07_solver_status", "fallback");
finalResultFile = writeResultTable(figureManifest, finalResultFile, "08_figure_manifest", "fallback");
finalResultFile = writeResultTable(rankTable, finalResultFile, "09_rank_by_scenario", "fallback");
finalResultFile = writeResultTable(robustness, finalResultFile, "10_robustness_summary", "fallback");
finalResultFile = writeResultTable(baselineImprove, finalResultFile, "11_baseline_improvement", "fallback");
finalResultFile = writeResultTable(feasibility, finalResultFile, "12_feasibility_summary", "fallback");
finalResultFile = writeResultTable(conclusionCheck, finalResultFile, "13_conclusion_check", "fallback");

writeStatus(runDir, "강건성 검증 분석 완료");
fprintf("\n=== 강건성 검증 분석 완료 ===\n");
fprintf("중간 저장 파일: %s\n", resultFile);
fprintf("최종 결과 파일: %s\n", finalResultFile);
if ~isempty(conclusionCheck) && ismember("pass_rate_pct", conclusionCheck.Properties.VariableNames)
    fprintf("\n[핵심 명제 유지율]\n");
    for ci = 1:height(conclusionCheck)
        fprintf("  %s: %.1f%% (%d/%d 시나리오)\n", ...
            char(conclusionCheck.simulation_name(ci)), ...
            conclusionCheck.pass_rate_pct(ci), ...
            conclusionCheck.scenarios_pass(ci), ...
            conclusionCheck.total_scenarios(ci));
    end
end

%% 지역 함수

function values = readVectorEnv(name, defaultValues)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    values = defaultValues;
    return;
end
parts = strtrim(split(raw, ","));
values = str2double(parts)';
if any(isnan(values))
    error("%s 환경변수는 쉼표로 구분된 숫자여야 합니다: %s", name, raw);
end
end

function value = readLogicalEnv(name, defaultValue)
raw = lower(strtrim(string(getenv(name))));
if strlength(raw) == 0
    value = defaultValue;
else
    value = any(raw == ["1", "true", "yes", "y"]);
end
end

function values = readStringListEnv(name, defaultValues)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    values = defaultValues;
else
    values = strtrim(split(raw, ","))';
end
end

function labels = mapAssetLabels(types, assetTypes, assetLabels)
labels = strings(numel(types), 1);
for i = 1:numel(types)
    idx = find(assetTypes == types(i), 1);
    if isempty(idx)
        labels(i) = types(i);
    else
        labels(i) = assetLabels(idx);
    end
end
end

function candidateMask = buildTypeCandidateMask(pof, assetTypes, candidateQuantile)
candidateMask = false(height(pof), 1);
for t = 1:numel(assetTypes)
    idx = find(string(pof.asset_type) == assetTypes(t));
    if isempty(idx)
        continue;
    end
    risk = pof.risk_2026_kkrw(idx);
    value = pof.investment_value_2026_kkrw(idx);
    riskThreshold = quantile(risk(isfinite(risk)), candidateQuantile);
    valueThreshold = quantile(value(isfinite(value)), candidateQuantile);
    candidateMask(idx) = risk >= riskThreshold | value >= valueThreshold;
end
end

function tableOut = buildBaselineKpiTable(pof, years)
rows = {};
for y = 1:numel(years)
    year = years(y);
    rows(end + 1, :) = {year, ...
        sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan"), ...
        sum(pof.(sprintf("saidi_%d_min", year)), "omitnan"), ...
        sum(pof.(sprintf("pof_%d", year)), "omitnan"), ...
        sum(pof.(sprintf("replacement_cost_%d_kkrw", year)), "omitnan")}; %#ok<AGROW>
end
tableOut = cell2table(rows, 'VariableNames', ...
    {'year', 'baseline_risk_kkrw', 'baseline_saidi_min', ...
    'baseline_expected_failures', 'asset_value_kkrw'});
end

function scopeTable = buildScopeTable(scopeList)
allScopes = [
    "risk_value_screening", "위험도–투자가치 선별 시뮬레이션", "설비군별 Risk 우선순위, 투자가치 우선순위, 투자가치 ILP 비교"
    "local_pi_portfolio", "Local PI 포트폴리오 시뮬레이션", "설비군별 투자가치 ILP, Local PI 우선순위, Local PI ILP 비교"
    "integrated_pi_portfolio", "통합 PI 포트폴리오 시뮬레이션", "전체 설비 기준 투자가치 ILP, Local PI ILP, Integrated PI ILP 비교"
];
keep = ismember(allScopes(:, 1), scopeList);
if ~any(keep)
    error("SENS_SCOPES에 유효한 시뮬레이션 scope가 없습니다.");
end
scopeTable = array2table(allScopes(keep, :), 'VariableNames', ...
    {'simulation_scope', 'simulation_name', 'simulation_description'});
end

function scenarioTable = buildScenarioTable(budgetMultipliers, capacityMultipliers, saidiCapRates, riskCapRates, fullGrid, weightScenarioTable, scopeTable)
rows = {};
scenarioNo = 0;
baseWeight = weightScenarioTable(1, :);
for sc = 1:height(scopeTable)
    scopeRow = scopeTable(sc, :);
    if fullGrid
        for b = budgetMultipliers
            for c = capacityMultipliers
                for s = saidiCapRates
                    for r = riskCapRates
                        scenarioNo = scenarioNo + 1;
                        rows(end + 1, :) = buildScenarioRow(sprintf("FG_%03d", scenarioNo), ...
                            "full_grid", b, c, s, r, baseWeight, scopeRow); %#ok<AGROW>
                    end
                end
            end
        end
    else
        for b = budgetMultipliers
            scenarioNo = scenarioNo + 1;
            rows(end + 1, :) = buildScenarioRow(sprintf("BUD_%03d", scenarioNo), ...
                "budget_sweep", b, 1.0, Inf, Inf, baseWeight, scopeRow); %#ok<AGROW>
        end
        for c = capacityMultipliers
            scenarioNo = scenarioNo + 1;
            rows(end + 1, :) = buildScenarioRow(sprintf("CAP_%03d", scenarioNo), ...
                "capacity_sweep", 1.0, c, Inf, Inf, baseWeight, scopeRow); %#ok<AGROW>
        end
        for s = saidiCapRates
            scenarioNo = scenarioNo + 1;
            rows(end + 1, :) = buildScenarioRow(sprintf("SAIDI_%03d", scenarioNo), ...
                "saidi_cap_sweep", 1.0, 1.0, s, Inf, baseWeight, scopeRow); %#ok<AGROW>
        end
        for r = riskCapRates
            scenarioNo = scenarioNo + 1;
            rows(end + 1, :) = buildScenarioRow(sprintf("RISK_%03d", scenarioNo), ...
                "risk_cap_sweep", 1.0, 1.0, Inf, r, baseWeight, scopeRow); %#ok<AGROW>
        end
        for s = saidiCapRates(isfinite(saidiCapRates))
            for r = riskCapRates(isfinite(riskCapRates))
                scenarioNo = scenarioNo + 1;
                rows(end + 1, :) = buildScenarioRow(sprintf("KPI_%03d", scenarioNo), ...
                    "kpi_combined", 1.0, 1.0, s, r, baseWeight, scopeRow); %#ok<AGROW>
            end
        end
    end

    % 운영목표별 AHP 가중치 민감도는 예산·물량·KPI 제약을 기준조건으로 고정하고,
    % 경제성·신뢰도·안전환경 가중치만 변화시킨다.
    for w = 1:height(weightScenarioTable)
        scenarioNo = scenarioNo + 1;
        weightRow = weightScenarioTable(w, :);
        rows(end + 1, :) = buildScenarioRow(sprintf("WGHT_%03d", scenarioNo), ...
            "operating_goal_weight_sweep", 1.0, 1.0, Inf, Inf, weightRow, scopeRow); %#ok<AGROW>
    end
end

scenarioTable = cell2table(rows, 'VariableNames', ...
    {'scenario_id', 'scenario_group', 'simulation_scope', 'simulation_name', ...
    'budget_multiplier', ...
    'capacity_multiplier', 'saidi_cap_rate', 'risk_cap_rate', ...
    'weight_scenario_id', 'weight_scenario_name', 'w_economy', ...
    'w_reliability', 'w_safety_environment'});
end

function row = buildScenarioRow(scenarioId, scenarioGroup, budgetMultiplier, capacityMultiplier, ...
    saidiCapRate, riskCapRate, weightRow, scopeRow)
row = {string(scenarioId), string(scenarioGroup), string(scopeRow.simulation_scope), ...
    string(scopeRow.simulation_name), budgetMultiplier, capacityMultiplier, ...
    saidiCapRate, riskCapRate, string(weightRow.weight_scenario_id), ...
    string(weightRow.weight_scenario_name), weightRow.w_economy, ...
    weightRow.w_reliability, weightRow.w_safety_environment};
end

function weightScenarioTable = buildWeightScenarioTable(criteriaWeights, includeWeightScenarios)
baseEconomy = criteriaWeights.criteria_weight(string(criteriaWeights.criteria_id) == "economy");
baseReliability = criteriaWeights.criteria_weight(string(criteriaWeights.criteria_id) == "reliability");
baseSafety = criteriaWeights.criteria_weight(string(criteriaWeights.criteria_id) == "safety_environment");
if isempty(baseEconomy) || isempty(baseReliability) || isempty(baseSafety)
    error("criteria_weights 시트에 economy, reliability, safety_environment 가중치가 모두 있어야 합니다.");
end

rows = {
    "expert_mean", "전문가 평균", baseEconomy, baseReliability, baseSafety
};

if includeWeightScenarios
    rows = [
        rows
        {"balanced", "균형형", 1/3, 1/3, 1/3}
        {"economy_centered", "경제성 중심", 0.50, 0.30, 0.20}
        {"reliability_centered", "신뢰도 중심", 0.25, 0.50, 0.25}
        {"safety_environment_centered", "안전·환경 중심", 0.25, 0.25, 0.50}
        {"economy_reliability_centered", "경제성·신뢰도 중심", 0.45, 0.40, 0.15}
        {"reliability_safety_centered", "신뢰도·안전환경 중심", 0.15, 0.45, 0.40}
    ];
end

gridStep = str2double(string(getenv("SENS_WEIGHT_GRID_STEP")));
if isnan(gridStep)
    gridStep = 0;
end
gridMin = str2double(string(getenv("SENS_WEIGHT_GRID_MIN")));
if isnan(gridMin)
    gridMin = 0.1;
end
if includeWeightScenarios && gridStep > 0
    gridNo = 0;
    tolerance = gridStep / 100;
    for wEconomy = 0:gridStep:1
        for wReliability = 0:gridStep:(1 - wEconomy)
            wSafety = 1 - wEconomy - wReliability;
            if wEconomy + tolerance < gridMin || wReliability + tolerance < gridMin || wSafety + tolerance < gridMin
                continue;
            end
            gridNo = gridNo + 1;
            rows(end + 1, :) = { ...
                string(sprintf("weight_grid_%03d", gridNo)), ...
                string(sprintf("가중치 격자 %03d", gridNo)), ...
                wEconomy, wReliability, wSafety}; %#ok<AGROW>
        end
    end
end

weightScenarioTable = cell2table(rows, 'VariableNames', ...
    {'weight_scenario_id', 'weight_scenario_name', 'w_economy', ...
    'w_reliability', 'w_safety_environment'});
weightSum = weightScenarioTable.w_economy + weightScenarioTable.w_reliability + weightScenarioTable.w_safety_environment;
weightScenarioTable.w_economy = weightScenarioTable.w_economy ./ weightSum;
weightScenarioTable.w_reliability = weightScenarioTable.w_reliability ./ weightSum;
weightScenarioTable.w_safety_environment = weightScenarioTable.w_safety_environment ./ weightSum;
end

function configTable = buildConfigTable(runStamp, baseBudgetRate, baseCapacityRate, discountRate, ...
    candidateQuantile, fullGrid, methodList, includeWeightScenarios, scopeList)
configTable = table( ...
    string(runStamp), baseBudgetRate, baseCapacityRate, discountRate, ...
    candidateQuantile, fullGrid, includeWeightScenarios, strjoin(scopeList, ","), strjoin(methodList, ","), ...
    string(getenv("SENS_ILP_MAX_TIME")), string(getenv("SENS_ILP_REL_GAP")), ...
    'VariableNames', {'run_stamp', 'base_budget_rate', 'base_capacity_rate', ...
    'discount_rate', 'candidate_quantile', 'full_grid', 'include_weight_scenarios', 'scopes', 'methods', ...
    'env_ilp_max_time', 'env_ilp_rel_gap'});
end

function pofScenario = applyWeightScenarioToPof(pof, localPi, ahpSubWeights, scenario, years)
pofScenario = pof;
metricIds = ["investment_value", "investment_efficiency", "saidi_reduction", ...
    "failure_probability", "safety_effect", "environment_effect"];

metricWeights = zeros(numel(metricIds), 1);
for m = 1:numel(metricIds)
    idx = find(string(ahpSubWeights.metric_id) == metricIds(m), 1);
    if isempty(idx)
        error("ahp_sub_weights 시트에 %s 항목이 없습니다.", char(metricIds(m)));
    end
    parent = string(ahpSubWeights.parent_criterion(idx));
    localWeight = ahpSubWeights.local_weight_within_parent(idx);
    if parent == "경제성"
        parentWeight = scenario.w_economy;
    elseif parent == "신뢰도"
        parentWeight = scenario.w_reliability;
    elseif parent == "안전·환경"
        parentWeight = scenario.w_safety_environment;
    else
        error("지원하지 않는 상위 기준입니다: %s", parent);
    end
    metricWeights(m) = parentWeight * localWeight;
end
if abs(sum(metricWeights) - 1) > 1e-4
    warning("sensitivity:weightSum", "metricWeights 합이 1에서 %.4f 벗어남 — 재정규화 적용", ...
        abs(sum(metricWeights) - 1));
end
metricWeights = metricWeights ./ sum(metricWeights);

for y = 1:numel(years)
    year = years(y);
    pi = zeros(height(pofScenario), 1);
    for m = 1:numel(metricIds)
        scoreColumn = sprintf("score_%s_%d", char(metricIds(m)), year);
        if ~ismember(scoreColumn, localPi.Properties.VariableNames)
            error("local_pi_asset_wide 시트에 %s 컬럼이 없습니다.", scoreColumn);
        end
        pi = pi + localPi.(scoreColumn) .* metricWeights(m);
    end
    pofScenario.(sprintf("local_pi_%d", year)) = pi;
    pofScenario.(sprintf("integrated_pi_%d", year)) = pi .* pofScenario.w_type_alpha_0_5;
end
end

function mats = buildMatrices(pof, assetIdx, years)
n = numel(assetIdx);
nYears = numel(years);
fields = ["cost", "risk", "riskReduction", "investmentValue", "saidi", "pof", "localPi", "integratedPi"];
for f = 1:numel(fields)
    mats.(fields(f)) = zeros(n, nYears);
end
for y = 1:nYears
    year = years(y);
    mats.cost(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year))(assetIdx);
    mats.risk(:, y) = pof.(sprintf("risk_%d_kkrw", year))(assetIdx);
    mats.riskReduction(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year))(assetIdx);
    mats.investmentValue(:, y) = pof.(sprintf("investment_value_%d_kkrw", year))(assetIdx);
    mats.saidi(:, y) = pof.(sprintf("saidi_%d_min", year))(assetIdx);
    mats.pof(:, y) = pof.(sprintf("pof_%d", year))(assetIdx);
    mats.localPi(:, y) = pof.(sprintf("local_pi_%d", year))(assetIdx);
    mats.integratedPi(:, y) = pof.(sprintf("integrated_pi_%d", year))(assetIdx);
end
end

function constraints = buildSensitivityConstraints(pof, allAssetIdx, candidateIdx, years, ...
    baseBudgetRate, baseCapacityRate, discountRate, budgetMultiplier, capacityMultiplier, ...
    saidiCapRate, riskCapRate)
assetValue = sum(pof.replacement_cost_2026_kkrw(allAssetIdx), "omitnan");
baseBudget = assetValue * baseBudgetRate * budgetMultiplier;
nYears = numel(years);
budgets = zeros(1, nYears);
for y = 1:nYears
    budgets(y) = baseBudget / ((1 + discountRate) ^ (y - 1));
end

constraints.budgets = budgets;
constraints.capacities = repmat(max(1, ceil(numel(allAssetIdx) * baseCapacityRate * capacityMultiplier)), 1, nYears);
constraints.candidateIdx = candidateIdx;
constraints.baselineRisk = zeros(1, nYears);
constraints.baselineSaidi = zeros(1, nYears);
for y = 1:nYears
    year = years(y);
    constraints.baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year))(allAssetIdx), "omitnan");
    constraints.baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year))(allAssetIdx), "omitnan");
end

constraints.riskCapRate = riskCapRate;
constraints.saidiCapRate = saidiCapRate;
if isfinite(riskCapRate)
    constraints.riskCap = constraints.baselineRisk(1) * riskCapRate;
else
    constraints.riskCap = Inf;
end
if isfinite(saidiCapRate)
    constraints.saidiCap = constraints.baselineSaidi(1) * saidiCapRate;
else
    constraints.saidiCap = Inf;
end
end

function [objectiveName, scoreMat] = getScoreMatrix(method, mats)
switch string(method)
    case "risk_greedy"
        objectiveName = "risk";
        scoreMat = mats.risk;
    case "investment_value_greedy"
        objectiveName = "investment_value";
        scoreMat = mats.investmentValue;
    case "investment_value_ilp"
        objectiveName = "investment_value";
        scoreMat = mats.investmentValue;
    case "local_pi_greedy"
        objectiveName = "local_pi";
        scoreMat = mats.localPi;
    case "local_pi_ilp"
        objectiveName = "local_pi";
        scoreMat = mats.localPi;
    case "integrated_pi_ilp"
        objectiveName = "integrated_pi";
        scoreMat = mats.integratedPi;
    otherwise
        error("지원하지 않는 민감도 분석 방법입니다: %s", method);
end
end

function methods = methodsForScope(scope, methodList, methodOverride)
if methodOverride
    methods = methodList;
    return;
end
switch string(scope)
    case "risk_value_screening"
        methods = ["risk_greedy", "investment_value_greedy", "investment_value_ilp"];
    case "local_pi_portfolio"
        methods = ["investment_value_ilp", "local_pi_greedy", "local_pi_ilp"];
    case "integrated_pi_portfolio"
        methods = ["investment_value_ilp", "local_pi_ilp", "integrated_pi_ilp"];
    otherwise
        error("지원하지 않는 시뮬레이션 scope입니다: %s", scope);
end
end

function [choiceGlobal, solverInfo, objectiveName, constraintsForSummary] = runScopeMethod( ...
    pof, candidateMask, allAssetIdx, assetTypes, years, scenario, method, ...
    baseBudgetRate, baseCapacityRate, discountRate)
scope = string(scenario.simulation_scope);
choiceGlobal = zeros(height(pof), 1, "int16");

if scope == "integrated_pi_portfolio"
    candidateIdx = find(candidateMask);
    constraints = buildSensitivityConstraints(pof, allAssetIdx, candidateIdx, years, ...
        baseBudgetRate, baseCapacityRate, discountRate, scenario.budget_multiplier, ...
        scenario.capacity_multiplier, scenario.saidi_cap_rate, scenario.risk_cap_rate);
    mats = buildMatrices(pof, candidateIdx, years);
    [objectiveName, scoreMat] = getScoreMatrix(method, mats);
    [choiceLocal, solverInfo] = runSingleMethod(method, scoreMat, mats, constraints);
    solverInfo.objective = scalarObjective(solverInfo, choiceLocal, scoreMat);
    choiceGlobal(candidateIdx) = choiceLocal;
    constraintsForSummary = constraints;
    return;
end

solverMessages = strings(numel(assetTypes), 1);
solverObjectives = zeros(numel(assetTypes), 1);
solverExitFlags = zeros(numel(assetTypes), 1);
for t = 1:numel(assetTypes)
    typeAllIdx = find(string(pof.asset_type) == assetTypes(t));
    typeCandidateIdx = typeAllIdx(candidateMask(typeAllIdx));
    constraints = buildSensitivityConstraints(pof, typeAllIdx, typeCandidateIdx, years, ...
        baseBudgetRate, baseCapacityRate, discountRate, scenario.budget_multiplier, ...
        scenario.capacity_multiplier, scenario.saidi_cap_rate, scenario.risk_cap_rate);
    mats = buildMatrices(pof, typeCandidateIdx, years);
    [objectiveName, scoreMat] = getScoreMatrix(method, mats);
    [choiceLocal, localSolver] = runSingleMethod(method, scoreMat, mats, constraints);
    choiceGlobal(typeCandidateIdx) = max(choiceGlobal(typeCandidateIdx), choiceLocal);
    solverMessages(t) = sprintf("%s:%s", assetTypes(t), string(localSolver.message));
    solverObjectives(t) = scalarObjective(localSolver, choiceLocal, scoreMat);
    solverExitFlags(t) = localSolver.exitflag;
end

constraintsForSummary = buildSensitivityConstraints(pof, allAssetIdx, find(candidateMask), years, ...
    baseBudgetRate, baseCapacityRate, discountRate, scenario.budget_multiplier, ...
    scenario.capacity_multiplier, scenario.saidi_cap_rate, scenario.risk_cap_rate);
solverInfo = struct("solver", sprintf("%s_by_asset_type", solverNameFromMethod(method)), ...
    "exitflag", min(solverExitFlags), ...
    "message", strjoin(solverMessages, " | "), ...
    "objective", sum(solverObjectives, "omitnan"));
end

function [choice, solverInfo] = runSingleMethod(method, scoreMat, mats, constraints)
if contains(string(method), "greedy")
    choice = runSensitivityGreedy(scoreMat, mats, constraints);
    solverInfo = struct("solver", "greedy", "exitflag", NaN, ...
        "message", "우선순위 기반 greedy", "objective", choiceScore(choice, scoreMat));
else
    [choice, solverInfo] = runSensitivityIlp(scoreMat, mats, constraints);
end
end

function solverName = solverNameFromMethod(method)
if contains(string(method), "greedy")
    solverName = "greedy";
else
    solverName = "ilp";
end
end

function choice = runSensitivityGreedy(scoreMat, mats, constraints)
[n, nYears] = size(scoreMat);
choice = zeros(n, 1, "int16");
for y = 1:nYears
    budgetLeft = constraints.budgets(y);
    capacityLeft = constraints.capacities(y);
    remaining = find(choice == 0);
    score = scoreMat(remaining, y);
    score(~isfinite(score)) = -Inf;
    [~, orderLocal] = sort(score, "descend");
    order = remaining(orderLocal);
    for k = 1:numel(order)
        if capacityLeft <= 0
            break;
        end
        idx = order(k);
        itemCost = mats.cost(idx, y);
        if isfinite(itemCost) && itemCost > 0 && itemCost <= budgetLeft && scoreMat(idx, y) > 0
            choice(idx) = y;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
end
end

function value = choiceScore(choice, scoreMat)
value = 0;
choice = choice(:);
for i = 1:numel(choice)
    y = double(choice(i));
    if y > 0
        value = value + double(scoreMat(i, y));
    end
end
value = double(value);
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = NaN;
end
end

function value = scalarObjective(solverInfo, choice, scoreMat)
% 일부 intlinprog 실행은 시간 제한, infeasible, early stop 상황에서 fval이 빈 배열로 반환될 수 있다.
% 이 경우 solverInfo.objective를 그대로 합산하면 스칼라 대입 오류가 발생하므로,
% 선택 결과가 있으면 선택 점수로 재계산하고, 그래도 불가능하면 NaN으로 둔다.
value = NaN;
if isstruct(solverInfo) && isfield(solverInfo, "objective")
    rawValue = solverInfo.objective;
    if ~isempty(rawValue) && isnumeric(rawValue)
        rawValue = rawValue(:);
        rawValue = rawValue(isfinite(rawValue));
        if ~isempty(rawValue)
            value = double(rawValue(1));
        end
    end
end
if isnan(value)
    value = choiceScore(choice, scoreMat);
end
end

function [choice, solverInfo] = runSensitivityIlp(scoreMat, mats, constraints)
[n, nYears] = size(scoreMat);
nVars = n * nYears;
score = double(scoreMat(:));
cost = double(mats.cost(:));
assetVec = repmat((1:n)', nYears, 1);
yearVec = repelem((1:nYears)', n);

valid = isfinite(score) & isfinite(cost) & score > 0 & cost > 0;
for y = 1:nYears
    valid(yearVec == y & cost > constraints.budgets(y)) = false;
end
validIdx = find(valid);
nKeep = numel(validIdx);

if nKeep == 0
    choice = zeros(n, 1, "int16");
    solverInfo = struct("solver", "intlinprog_skipped", "exitflag", 0, ...
        "message", "선택 가능한 후보 변수가 없어 ILP를 건너뜀", "objective", 0);
    return;
end

f = -score(validIdx);
assetKeep = assetVec(validIdx);
yearKeep = yearVec(validIdx);
costKeep = cost(validIdx);
colIdx = (1:nKeep)';

Aasset = sparse(assetKeep, colIdx, 1, n, nKeep);
Abudget = sparse(yearKeep, colIdx, costKeep, nYears, nKeep);
Acapacity = sparse(yearKeep, colIdx, 1, nYears, nKeep);
A = [Aasset; Abudget; Acapacity];
b = [ones(n, 1); constraints.budgets(:); constraints.capacities(:)];

% SAIDI와 Risk 총량은 잔여량 상한으로 해석한다.
% baseline_y - cumulative_removed_y <= cap 이므로
% cumulative_removed_y >= baseline_y - cap 로 변환한 뒤, intlinprog의 A*x<=b 형태에 맞춰 음수 부호를 적용한다.
if isfinite(constraints.saidiCap)
    for y = 1:nYears
        requiredReduction = constraints.baselineSaidi(y) - constraints.saidiCap;
        if requiredReduction > 0
            contrib = zeros(n, nYears);
            for selectYear = 1:y
                contrib(:, selectYear) = mats.saidi(:, y);
            end
            A = [A; sparse(1, 1:nKeep, -double(contrib(validIdx)), 1, nKeep)]; %#ok<AGROW>
            b = [b; -requiredReduction]; %#ok<AGROW>
        end
    end
end

if isfinite(constraints.riskCap)
    for y = 1:nYears
        requiredReduction = constraints.baselineRisk(y) - constraints.riskCap;
        if requiredReduction > 0
            contrib = zeros(n, nYears);
            for selectYear = 1:y
                contrib(:, selectYear) = mats.risk(:, y);
            end
            A = [A; sparse(1, 1:nKeep, -double(contrib(validIdx)), 1, nKeep)]; %#ok<AGROW>
            b = [b; -requiredReduction]; %#ok<AGROW>
        end
    end
end

lb = zeros(nKeep, 1);
ub = ones(nKeep, 1);
intcon = 1:nKeep;
options = buildIlpOptions();

% greedy 초기해: 좋은 시작점을 제공해 B&B 탐색 범위를 줄임
greedyChoice = runSensitivityGreedy(scoreMat, mats, constraints);
x0Full = zeros(nVars, 1);
for gi = 1:n
    yi = greedyChoice(gi);
    if yi > 0
        x0Full((yi - 1) * n + gi) = 1;
    end
end
x0 = x0Full(validIdx);

% greedy 초기해 feasible 검사: 예산·물량·SAIDI·Risk 제약을 하나라도 위반하면 폐기
if ~isempty(x0) && ~isempty(A) && ~isempty(b)
    if any(A * x0 > b + 1e-6)
        x0 = [];
    end
end

try
    % x0 포함 호출 → MATLAB 버전이 x0를 미지원하면 x0 없이 fallback
    if ~isempty(x0)
        try
            [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, x0, options);
        catch
            [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
        end
    else
        [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
    end
    if isempty(x)
        choice = zeros(n, 1, "int16");
    else
        xFull = zeros(nVars, 1);
        xFull(validIdx) = x;
        xMat = reshape(xFull, n, nYears);
        [maxVal, yearIdx] = max(xMat, [], 2);
        choice = int16(yearIdx .* (maxVal >= 0.5));
    end
    if isfield(output, "message")
        outMessage = string(output.message);
    else
        outMessage = "";
    end
    if isempty(fval) || ~isscalar(fval) || ~isfinite(fval)
        objectiveValue = choiceScore(choice, scoreMat);
    else
        objectiveValue = -double(fval);
    end
    solverInfo = struct("solver", "intlinprog", "exitflag", exitflag, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, outMessage), "objective", objectiveValue);
catch ME
    choice = zeros(n, 1, "int16");
    solverInfo = struct("solver", "intlinprog_failed", "exitflag", -999, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, string(ME.message)), "objective", NaN);
end
end

function options = buildIlpOptions()
displayMode = strtrim(string(getenv("SENS_ILP_DISPLAY")));
if strlength(displayMode) == 0
    displayMode = "off";
end
options = optimoptions("intlinprog", "Display", char(displayMode));

% 강건성 버전 기본값: 0.5% 갭 허용 (전체 버전 0.1% 대비 완화)
relGap = str2double(string(getenv("SENS_ILP_REL_GAP")));
if isnan(relGap)
    relGap = 5e-3;
end
try
    options.RelativeGapTolerance = relGap;
catch ME
    warning("sensitivity:optionIgnored", "ILP 옵션 RelativeGapTolerance 설정 실패 (MATLAB 버전 확인 필요): %s", ME.message);
end

% 강건성 버전 기본값: 60초 (전체 버전 600초 대비 단축)
maxTime = str2double(string(getenv("SENS_ILP_MAX_TIME")));
if isnan(maxTime)
    maxTime = 60;
end
if maxTime > 0
    try
        options.MaxTime = maxTime;
    catch ME
        warning("sensitivity:optionIgnored", "ILP 옵션 MaxTime 설정 실패 (MATLAB 버전 확인 필요): %s", ME.message);
    end
end

% 수렴 가속 옵션: 전처리 강화 + RINS 발견적 탐색
try
    options.PresolveLevel = 1;
catch
end
try
    options.Heuristics = "rins";
catch
end
end

function [annual, total, typeSummary, constraintCheck] = summarizeSensitivityChoice( ...
    pof, choice, scenario, method, objectiveName, constraints, years, assetTypes, assetLabels)
annualRows = {};
typeRows = {};
constraintRows = {};

for y = 1:numel(years)
    year = years(y);
    selected = find(choice == y);
    cumulative = find(choice > 0 & choice <= y);

    % 당해 연도 투자 경제성 지표 (selected 기준)
    cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
    riskReductionEcon = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
    investmentValue = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
    expectedFailures = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
    localPi = sum(pof.(sprintf("local_pi_%d", year))(selected), "omitnan");
    integratedPi = sum(pof.(sprintf("integrated_pi_%d", year))(selected), "omitnan");

    % y년도 KPI: 2026~y년 누적 교체 설비의 y년 기여도 합산
    removedRisk = sum(pof.(sprintf("risk_%d_kkrw", year))(cumulative), "omitnan");
    removedSaidi = sum(pof.(sprintf("saidi_%d_min", year))(cumulative), "omitnan");
    riskAfter = constraints.baselineRisk(y) - removedRisk;
    saidiAfter = constraints.baselineSaidi(y) - removedSaidi;
    budgetLimit = constraints.budgets(y);
    capacityLimit = constraints.capacities(y);

    annualRows(end + 1, :) = {string(scenario.scenario_id), string(scenario.scenario_group), ...
        string(scenario.simulation_scope), string(scenario.simulation_name), ...
        scenario.budget_multiplier, scenario.capacity_multiplier, scenario.saidi_cap_rate, scenario.risk_cap_rate, ...
        string(scenario.weight_scenario_id), string(scenario.weight_scenario_name), ...
        scenario.w_economy, scenario.w_reliability, scenario.w_safety_environment, ...
        method, objectiveName, year, numel(selected), numel(cumulative), cost, riskReductionEcon, ...
        removedRisk, investmentValue, safeDivide(riskReductionEcon, cost), removedSaidi, ...
        expectedFailures, localPi, integratedPi, ...
        constraints.baselineRisk(y), riskAfter, constraints.riskCap, ...
        constraints.baselineSaidi(y), saidiAfter, constraints.saidiCap, ...
        budgetLimit, capacityLimit, safeDivide(cost, budgetLimit), safeDivide(numel(selected), capacityLimit)}; %#ok<AGROW>

    constraintRows(end + 1, :) = {string(scenario.scenario_id), method, year, ...
        cost <= budgetLimit + 1e-6, numel(selected) <= capacityLimit, ...
        ~isfinite(constraints.saidiCap) || saidiAfter <= constraints.saidiCap + 1e-9, ...
        ~isfinite(constraints.riskCap) || riskAfter <= constraints.riskCap + 1e-6, ...
        cost, budgetLimit, numel(selected), capacityLimit, saidiAfter, constraints.saidiCap, riskAfter, constraints.riskCap}; %#ok<AGROW>

    for t = 1:numel(assetTypes)
        typeIdx = selected(string(pof.asset_type(selected)) == assetTypes(t));
        typeRows(end + 1, :) = {string(scenario.scenario_id), string(scenario.scenario_group), ...
            string(scenario.simulation_scope), string(scenario.simulation_name), ...
            string(scenario.weight_scenario_id), string(scenario.weight_scenario_name), ...
            scenario.w_economy, scenario.w_reliability, scenario.w_safety_environment, ...
            method, objectiveName, year, assetTypes(t), assetLabels(t), numel(typeIdx), ...
            sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(typeIdx), "omitnan"), ...
            sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(typeIdx), "omitnan"), ...
            sum(pof.(sprintf("investment_value_%d_kkrw", year))(typeIdx), "omitnan"), ...
            sum(pof.(sprintf("saidi_%d_min", year))(typeIdx), "omitnan"), ...
            sum(pof.(sprintf("local_pi_%d", year))(typeIdx), "omitnan"), ...
            sum(pof.(sprintf("integrated_pi_%d", year))(typeIdx), "omitnan")}; %#ok<AGROW>
    end
end

annual = cell2table(annualRows, 'VariableNames', ...
    {'scenario_id', 'scenario_group', 'simulation_scope', 'simulation_name', ...
    'budget_multiplier', 'capacity_multiplier', ...
    'saidi_cap_rate', 'risk_cap_rate', 'weight_scenario_id', 'weight_scenario_name', ...
    'w_economy', 'w_reliability', 'w_safety_environment', ...
    'method', 'objective', 'year', ...
    'selected_count', 'cumulative_count', 'investment_cost_kkrw', 'risk_reduction_econ_kkrw', ...
    'risk_removed_cumulative_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
    'saidi_removed_cumulative_min', ...
    'expected_failures', 'local_pi', 'integrated_pi', 'baseline_risk_kkrw', ...
    'risk_after_cumulative_kkrw', 'risk_cap_kkrw', 'baseline_saidi_min', ...
    'saidi_after_cumulative_min', 'saidi_cap_min', 'budget_limit_kkrw', ...
    'capacity_limit', 'budget_usage_ratio', 'capacity_usage_ratio'});

% total: 연도별 누적 컬럼(risk_removed, saidi_removed)은 합산이 무의미하므로 제외
% 최종 KPI는 annual 테이블의 마지막 연도(year=2030) 행에서 확인할 것
total = groupsummary(annual, {'scenario_id', 'scenario_group', 'budget_multiplier', ...
    'simulation_scope', 'simulation_name', ...
    'capacity_multiplier', 'saidi_cap_rate', 'risk_cap_rate', ...
    'weight_scenario_id', 'weight_scenario_name', 'w_economy', 'w_reliability', 'w_safety_environment', ...
    'method', 'objective'}, "sum", ...
    {'selected_count', 'cumulative_count', 'investment_cost_kkrw', 'risk_reduction_econ_kkrw', ...
    'investment_value_kkrw', 'expected_failures', ...
    'local_pi', 'integrated_pi', 'budget_limit_kkrw', 'capacity_limit'});
total.Properties.VariableNames = erase(total.Properties.VariableNames, "sum_");
if ismember("GroupCount", total.Properties.VariableNames)
    total = removevars(total, "GroupCount");
end
total.investment_efficiency = total.risk_reduction_econ_kkrw ./ max(total.investment_cost_kkrw, 1);
total.budget_usage_ratio = total.investment_cost_kkrw ./ max(total.budget_limit_kkrw, 1);
total.capacity_usage_ratio = total.selected_count ./ max(total.capacity_limit, 1);

typeSummary = cell2table(typeRows, 'VariableNames', ...
    {'scenario_id', 'scenario_group', 'simulation_scope', 'simulation_name', ...
    'weight_scenario_id', 'weight_scenario_name', ...
    'w_economy', 'w_reliability', 'w_safety_environment', ...
    'method', 'objective', 'year', ...
    'asset_type', 'asset_type_label', 'selected_count', 'investment_cost_kkrw', ...
    'risk_reduction_kkrw', 'investment_value_kkrw', 'saidi_reduction_min', ...
    'local_pi', 'integrated_pi'});

constraintCheck = cell2table(constraintRows, 'VariableNames', ...
    {'scenario_id', 'method', 'year', 'budget_ok', 'capacity_ok', ...
    'saidi_ok', 'risk_ok', 'investment_cost_kkrw', 'budget_limit_kkrw', ...
    'selected_count', 'capacity_limit', 'saidi_after_cumulative_min', ...
    'saidi_cap_min', 'risk_after_cumulative_kkrw', 'risk_cap_kkrw'});
end

function writeIntermediateResults(resultFile, annualParts, totalParts, typeParts, constraintParts, solverParts)
if ~isempty(annualParts)
    writeResultTable(vertcat(annualParts{:}), resultFile, "03_annual_summary", "warn");
end
if ~isempty(totalParts)
    writeResultTable(vertcat(totalParts{:}), resultFile, "04_total_summary", "warn");
end
if ~isempty(typeParts)
    writeResultTable(vertcat(typeParts{:}), resultFile, "05_type_summary", "warn");
end
if ~isempty(constraintParts)
    writeResultTable(vertcat(constraintParts{:}), resultFile, "06_constraint_check", "warn");
end
if ~isempty(solverParts)
    writeResultTable(vertcat(solverParts{:}), resultFile, "07_solver_status", "warn");
end
end

function effectiveFile = writeResultTable(T, resultFile, sheetName, failMode)
% 엑셀 파일 잠금이 발생해도 시뮬레이션 전체가 중단되지 않도록 쓰기 재시도와 우회 저장을 수행한다.
effectiveFile = resultFile;
retryCount = str2double(string(getenv("SENS_WRITE_RETRY_COUNT")));
if isnan(retryCount) || retryCount < 1
    retryCount = 5;
end
retryDelay = str2double(string(getenv("SENS_WRITE_RETRY_DELAY_SEC")));
if isnan(retryDelay) || retryDelay < 0
    retryDelay = 1.0;
end

lastError = [];
for k = 1:retryCount
    try
        writetable(T, effectiveFile, "Sheet", sheetName);
        return;
    catch ME
        lastError = ME;
        if k < retryCount
            pause(retryDelay);
        end
    end
end

if failMode == "warn"
    warning("중간 저장 실패: sheet=%s, file=%s, reason=%s", sheetName, effectiveFile, lastError.message);
    return;
end

if failMode == "fallback"
    [folder, stem, ext] = fileparts(resultFile);
    fallbackFile = fullfile(folder, sprintf("%s_autosave_%s%s", stem, datestr(now, "yyyymmdd_HHMMSS"), ext));
    for k = 1:retryCount
        try
            writetable(T, fallbackFile, "Sheet", sheetName);
            warning("결과 파일이 잠겨 있어 우회 저장 파일을 사용합니다: %s", fallbackFile);
            effectiveFile = fallbackFile;
            return;
        catch ME
            lastError = ME;
            if k < retryCount
                pause(retryDelay);
            end
        end
    end
end

rethrow(lastError);
end

function figureManifest = saveSensitivityFiguresV2(totalSummary, annualSummary, typeSummary, constraintCheck, figureDir) %#ok<INUSD>
rows = {};
fontName = "Malgun Gothic";
figureMode = lower(strtrim(string(getenv("SENS_FIGURE_MODE"))));
if strlength(figureMode) == 0
    figureMode = "core";
end
if figureMode == "off"
    figureManifest = table();
    return;
end
lastYear = max(annualSummary.year);
annualLast = annualSummary(annualSummary.year == lastYear, :);

totalSummary.plot_group = string(totalSummary.simulation_scope) + "__" + string(totalSummary.scenario_group);
annualLast.plot_group = string(annualLast.simulation_scope) + "__" + string(annualLast.scenario_group);
if ~isempty(typeSummary)
    typeSummary.plot_group = string(typeSummary.simulation_scope) + "__" + string(typeSummary.scenario_group);
end

sweepGroups = ["budget_sweep", "capacity_sweep", "saidi_cap_sweep", "risk_cap_sweep"];
xNameList = ["budget_multiplier", "capacity_multiplier", "saidi_cap_rate", "risk_cap_rate"];
xNameMap = containers.Map(cellstr(sweepGroups), cellstr(xNameList));
methodColors = lines(12);
assetTypeColors = [0.22 0.49 0.72; 0.30 0.69 0.29; 0.89 0.10 0.11;
                   0.99 0.55 0.24; 0.60 0.31 0.64; 0.65 0.34 0.14];

totalMetricsAll = ["selected_count", "investment_value_kkrw", "risk_reduction_econ_kkrw", "investment_cost_kkrw", "local_pi", "integrated_pi"];
kpiMetricsAll = ["risk_removed_cumulative_kkrw", "saidi_removed_cumulative_min", "risk_after_cumulative_kkrw", "saidi_after_cumulative_min"];
plotGroups = unique(string(totalSummary.plot_group), "stable");

for pg = 1:numel(plotGroups)
    plotGroup = plotGroups(pg);
    parts = split(plotGroup, "__");
    scopeName = parts(1);
    groupName = parts(2);
    if ~ismember(groupName, sweepGroups)
        continue;
    end
    xName = xNameMap(char(groupName));
    scopeLabel = scopeDisplayName(scopeName);
    groupLabel = scenarioGroupLabel(groupName);

    groupTotal = totalSummary(string(totalSummary.plot_group) == plotGroup, :);
    groupAnnual = annualLast(string(annualLast.plot_group) == plotGroup, :);
    methods = unique(string(groupTotal.method), "stable");
    [totalMetrics, kpiMetrics] = metricsForFigureMode(figureMode, groupName, totalMetricsAll, kpiMetricsAll);

    for metric = totalMetrics
        if ~ismember(metric, groupTotal.Properties.VariableNames)
            continue;
        end
        fig = figure("Visible", "off", "Position", [0 0 900 560]);
        hold on;
        for m = 1:numel(methods)
            d = groupTotal(string(groupTotal.method) == methods(m), :);
            [xv, ord] = sort(d.(xName));
            plot(xv, d.(metric)(ord), "-o", "LineWidth", 1.8, ...
                "Color", methodColors(m, :), "DisplayName", methodDisplayName(methods(m)));
        end
        applyKoreanFigureStyle(fontName);
        xlabel(xAxisLabel(xName));
        ylabel(metricDisplayName(metric));
        title(sprintf("%s: %s에 따른 %s", scopeLabel, groupLabel, metricDisplayName(metric)), "Interpreter", "none");
        legend("Location", "best", "Interpreter", "none");
        fileName = sprintf("%s_%s.png", plotGroup, metric);
        filePath = fullfile(figureDir, fileName);
        exportgraphics(fig, filePath, "Resolution", 220);
        close(fig);
        rows(end + 1, :) = {plotGroup, metric, string(filePath)}; %#ok<AGROW>
    end

    for metric = kpiMetrics
        if ~ismember(metric, groupAnnual.Properties.VariableNames)
            continue;
        end
        fig = figure("Visible", "off", "Position", [0 0 900 560]);
        hold on;
        for m = 1:numel(methods)
            d = groupAnnual(string(groupAnnual.method) == methods(m), :);
            [xv, ord] = sort(d.(xName));
            plot(xv, d.(metric)(ord), "-s", "LineWidth", 1.8, ...
                "Color", methodColors(m, :), "DisplayName", methodDisplayName(methods(m)));
        end
        applyKoreanFigureStyle(fontName);
        xlabel(xAxisLabel(xName));
        ylabel(metricDisplayName(metric));
        title(sprintf("%s: %s에 따른 %s(%d년 누적)", scopeLabel, groupLabel, metricDisplayName(metric), lastYear), "Interpreter", "none");
        legend("Location", "best", "Interpreter", "none");
        fileName = sprintf("%s_kpi_%s.png", plotGroup, metric);
        filePath = fullfile(figureDir, fileName);
        exportgraphics(fig, filePath, "Resolution", 220);
        close(fig);
        rows(end + 1, :) = {plotGroup, metric, string(filePath)}; %#ok<AGROW>
    end
end

% 투자가치–SAIDI 산점도: scope별로 분리
if ismember("investment_value_kkrw", totalSummary.Properties.VariableNames) && ...
        ismember("saidi_removed_cumulative_min", annualLast.Properties.VariableNames)
    saidiByScenMethod = varfun(@mean, annualLast, "InputVariables", "saidi_removed_cumulative_min", ...
        "GroupingVariables", {'scenario_id', 'method'});
    saidiByScenMethod.Properties.VariableNames{end} = 'saidi_removed_cumulative_min';
    scatterData = join(totalSummary(:, {'scenario_id', 'scenario_group', 'simulation_scope', 'method', 'investment_value_kkrw'}), ...
        saidiByScenMethod, "Keys", {'scenario_id', 'method'});
    scopes = unique(string(scatterData.simulation_scope), "stable");
    markers = {'o', 's', '^', 'd', 'v', 'p', 'h'};
    for sc = 1:numel(scopes)
        dScope = scatterData(string(scatterData.simulation_scope) == scopes(sc), :);
        methods = unique(string(dScope.method), "stable");
        groups = unique(string(dScope.scenario_group), "stable");
        fig = figure("Visible", "off", "Position", [0 0 900 620]);
        hold on;
        for m = 1:numel(methods)
            for g = 1:numel(groups)
                mask = string(dScope.method) == methods(m) & string(dScope.scenario_group) == groups(g);
                if ~any(mask), continue; end
                d = dScope(mask, :);
                marker = markers{mod(g - 1, numel(markers)) + 1};
                scatter(d.investment_value_kkrw, d.saidi_removed_cumulative_min, 70, ...
                    methodColors(m, :), marker, "filled", "MarkerFaceAlpha", 0.75, ...
                    "DisplayName", sprintf("%s / %s", methodDisplayName(methods(m)), scenarioGroupLabel(groups(g))));
            end
        end
        applyKoreanFigureStyle(fontName);
        xlabel("5개년 투자가치 합산(천원)");
        ylabel(sprintf("SAIDI 저감량 누적(%d년, 분)", lastYear));
        title(sprintf("%s: 투자가치와 SAIDI 저감량의 관계", scopeDisplayName(scopes(sc))), "Interpreter", "none");
        legend("Location", "bestoutside", "Interpreter", "none", "FontSize", 8);
        fileName = sprintf("%s_scatter_iv_vs_saidi.png", scopes(sc));
        filePath = fullfile(figureDir, fileName);
        exportgraphics(fig, filePath, "Resolution", 220);
        close(fig);
        rows(end + 1, :) = {scopes(sc), "iv_vs_saidi_scatter", string(filePath)}; %#ok<AGROW>
    end
end

% 운영목표별 가중치 3D 산점도: scope별·방법별 분리
weightDataAll = totalSummary(string(totalSummary.scenario_group) == "operating_goal_weight_sweep", :);
if ~isempty(weightDataAll)
    weightMetrics = ["investment_value_kkrw", "local_pi", "integrated_pi"];
    scopes = unique(string(weightDataAll.simulation_scope), "stable");
    for sc = 1:numel(scopes)
        weightData = weightDataAll(string(weightDataAll.simulation_scope) == scopes(sc), :);
        methods = unique(string(weightData.method), "stable");
        for metric = weightMetrics
            if ~ismember(metric, weightData.Properties.VariableNames), continue; end
            vals = weightData.(metric);
            cLim = [min(vals(isfinite(vals))), max(vals(isfinite(vals)))];
            if isempty(cLim) || any(~isfinite(cLim)), continue; end
            if cLim(1) == cLim(2), cLim = cLim + [-1, 1]; end
            for m = 1:numel(methods)
                d = weightData(string(weightData.method) == methods(m), :);
                fig = figure("Visible", "off", "Position", [0 0 850 650]);
                scatter3(d.w_reliability, d.w_safety_environment, d.w_economy, ...
                    90, d.(metric), "filled", "MarkerEdgeColor", [0.15 0.15 0.15]);
                colormap("parula"); clim(cLim);
                applyKoreanFigureStyle(fontName);
                view(135, 28);
                xlabel("신뢰도 가중치");
                ylabel("안전·환경 가중치");
                zlabel("경제성 가중치");
                cb = colorbar;
                cb.Label.String = metricDisplayName(metric);
                title(sprintf("%s: 운영목표 가중치 민감도(%s, %s)", ...
                    scopeDisplayName(scopes(sc)), methodDisplayName(methods(m)), metricDisplayName(metric)), "Interpreter", "none");
                fileName = sprintf("%s_weight_3d_%s_%s.png", scopes(sc), methods(m), metric);
                filePath = fullfile(figureDir, fileName);
                exportgraphics(fig, filePath, "Resolution", 220);
                close(fig);
                rows(end + 1, :) = {scopes(sc), sprintf("weight_3d_%s", metric), string(filePath)}; %#ok<AGROW>
            end
        end
    end
end

% 설비유형 분포: scope별 기준조건 비교
if ~isempty(typeSummary)
    typeTotal = groupsummary(typeSummary, ...
        {'scenario_id', 'simulation_scope', 'method', 'asset_type_label'}, ...
        "sum", {'selected_count'});
    typeTotal.Properties.VariableNames = erase(typeTotal.Properties.VariableNames, "sum_");
    if ismember("GroupCount", typeTotal.Properties.VariableNames)
        typeTotal = removevars(typeTotal, "GroupCount");
    end
    baseMask = totalSummary.budget_multiplier == 1.0 & totalSummary.capacity_multiplier == 1.0 & ...
        ~isfinite(totalSummary.saidi_cap_rate) & ~isfinite(totalSummary.risk_cap_rate) & ...
        string(totalSummary.weight_scenario_id) == "expert_mean";
    baseScenarioIds = unique(string(totalSummary.scenario_id(baseMask)), "stable");
    assetTypeOrder = ["주상변압기", "지상변압기", "가공개폐기", "지중개폐기", "가공배전선로", "지중케이블"];
    scopes = unique(string(totalSummary.simulation_scope), "stable");
    for sc = 1:numel(scopes)
        baseType = typeTotal(ismember(string(typeTotal.scenario_id), baseScenarioIds) & ...
            string(typeTotal.simulation_scope) == scopes(sc), :);
        if isempty(baseType), continue; end
        methods = unique(string(baseType.method), "stable");
        stackMat = zeros(numel(methods), numel(assetTypeOrder));
        for m = 1:numel(methods)
            for t = 1:numel(assetTypeOrder)
                mask = string(baseType.method) == methods(m) & string(baseType.asset_type_label) == assetTypeOrder(t);
                if any(mask)
                    stackMat(m, t) = sum(baseType.selected_count(mask), "omitnan");
                end
            end
        end
        fig = figure("Visible", "off", "Position", [0 0 900 520]);
        b = bar(stackMat, "stacked");
        for ti = 1:min(numel(b), size(assetTypeColors, 1))
            if isprop(b(ti), "FaceColor")
                b(ti).FaceColor = assetTypeColors(ti, :);
            end
        end
        applyKoreanFigureStyle(fontName);
        xTickLabels = cell(numel(methods), 1);
        for mi = 1:numel(methods)
            xTickLabels{mi} = char(methodDisplayName(methods(mi)));
        end
        set(gca, "XTickLabel", xTickLabels, "XTickLabelRotation", 15);
        ylabel("5개년 합산 선택대수(대)");
        title(sprintf("%s: 기준조건 설비유형별 선택 분포", scopeDisplayName(scopes(sc))), "Interpreter", "none");
        legendCount = min(numel(b), numel(assetTypeOrder));
        if legendCount > 0
            legend(b(1:legendCount), assetTypeOrder(1:legendCount), ...
                "Location", "eastoutside", "Interpreter", "none", "FontSize", 8);
        end
        fileName = sprintf("%s_baseline_type_distribution.png", scopes(sc));
        filePath = fullfile(figureDir, fileName);
        exportgraphics(fig, filePath, "Resolution", 220);
        close(fig);
        rows(end + 1, :) = {scopes(sc), "baseline_type_distribution", string(filePath)}; %#ok<AGROW>
    end
end

if isempty(rows)
    figureManifest = table();
else
    figureManifest = cell2table(rows, 'VariableNames', {'scenario_group', 'metric', 'file_path'});
end
end

function applyKoreanFigureStyle(fontName)
grid on;
box on;
set(gca, "FontName", fontName, "FontSize", 11, "LineWidth", 0.8);
end

function [totalMetrics, kpiMetrics] = metricsForFigureMode(figureMode, groupName, totalMetricsAll, kpiMetricsAll)
if figureMode == "all"
    totalMetrics = totalMetricsAll;
    kpiMetrics = kpiMetricsAll;
    return;
end

switch string(groupName)
    case "budget_sweep"
        totalMetrics = ["investment_value_kkrw", "investment_cost_kkrw"];
        kpiMetrics = ["risk_removed_cumulative_kkrw", "saidi_removed_cumulative_min"];
    case "capacity_sweep"
        totalMetrics = ["selected_count", "investment_cost_kkrw"];
        kpiMetrics = ["risk_removed_cumulative_kkrw", "saidi_removed_cumulative_min"];
    case "saidi_cap_sweep"
        totalMetrics = ["investment_cost_kkrw", "local_pi"];
        kpiMetrics = ["saidi_after_cumulative_min", "saidi_removed_cumulative_min"];
    case "risk_cap_sweep"
        totalMetrics = ["investment_cost_kkrw", "local_pi"];
        kpiMetrics = ["risk_after_cumulative_kkrw", "risk_removed_cumulative_kkrw"];
    otherwise
        totalMetrics = ["investment_value_kkrw", "investment_cost_kkrw"];
        kpiMetrics = ["risk_removed_cumulative_kkrw", "saidi_removed_cumulative_min"];
end
end

function label = scopeDisplayName(scope)
switch string(scope)
    case "risk_value_screening"
        label = "위험도–투자가치 선별 시뮬레이션";
    case "local_pi_portfolio"
        label = "Local PI 포트폴리오 시뮬레이션";
    case "integrated_pi_portfolio"
        label = "통합 PI 포트폴리오 시뮬레이션";
    otherwise
        label = string(scope);
end
end

function label = scenarioGroupLabel(groupName)
switch string(groupName)
    case "budget_sweep"
        label = "예산 변화";
    case "capacity_sweep"
        label = "연간 시공력 변화";
    case "saidi_cap_sweep"
        label = "SAIDI 상한 변화";
    case "risk_cap_sweep"
        label = "Risk 총량 상한 변화";
    case "operating_goal_weight_sweep"
        label = "운영목표 가중치 변화";
    case "kpi_combined"
        label = "SAIDI–Risk 복합 제약";
    otherwise
        label = string(groupName);
end
end

function label = xAxisLabel(xName)
switch string(xName)
    case "budget_multiplier"
        label = "예산 배율";
    case "capacity_multiplier"
        label = "연간 시공력 배율";
    case "saidi_cap_rate"
        label = "SAIDI 상한 배율";
    case "risk_cap_rate"
        label = "Risk 총량 상한 배율";
    otherwise
        label = string(xName);
end
end

function label = metricDisplayName(metric)
switch string(metric)
    case "selected_count"
        label = "투자대수(대)";
    case "investment_value_kkrw"
        label = "투자가치(천원)";
    case "risk_reduction_econ_kkrw"
        label = "Risk 저감량(경제성 기준, 천원)";
    case "investment_cost_kkrw"
        label = "투자비용(천원)";
    case "local_pi"
        label = "Local PI";
    case "integrated_pi"
        label = "Integrated PI";
    case "risk_removed_cumulative_kkrw"
        label = "누적 Risk 제거량(천원)";
    case "saidi_removed_cumulative_min"
        label = "누적 SAIDI 저감량(분)";
    case "risk_after_cumulative_kkrw"
        label = "잔여 Risk 총량(천원)";
    case "saidi_after_cumulative_min"
        label = "잔여 SAIDI(분)";
    otherwise
        label = string(metric);
end
end

function label = methodDisplayName(method)
switch string(method)
    case "risk_greedy"
        label = "Risk 우선순위";
    case "investment_value_greedy"
        label = "투자가치 우선순위";
    case "investment_value_ilp"
        label = "투자가치 ILP";
    case "local_pi_greedy"
        label = "Local PI 우선순위";
    case "local_pi_ilp"
        label = "Local PI ILP";
    case "integrated_pi_ilp"
        label = "Integrated PI ILP";
    otherwise
        label = string(method);
end
end

% ══════════════════════════════════════════════════════════════════════════
%  강건성 요약 함수 (09~13 시트)
% ══════════════════════════════════════════════════════════════════════════

function rankTable = buildRankTable(totalSummary)
% 시나리오별 방법 투자가치 순위
rows = {};
scopes = unique(string(totalSummary.simulation_scope), "stable");
for sc = 1:numel(scopes)
    scopeData = totalSummary(string(totalSummary.simulation_scope) == scopes(sc), :);
    scenIds = unique(string(scopeData.scenario_id), "stable");
    for si = 1:numel(scenIds)
        d = scopeData(string(scopeData.scenario_id) == scenIds(si), :);
        if isempty(d), continue; end
        [~, ord] = sort(d.investment_value_kkrw, "descend");
        for r = 1:height(d)
            rows(end + 1, :) = {string(scopes(sc)), string(d.simulation_name(1)), ...
                string(d.scenario_id(ord(r))), string(d.scenario_group(ord(r))), ...
                string(d.method(ord(r))), r, d.investment_value_kkrw(ord(r))}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    rankTable = table(); return;
end
rankTable = cell2table(rows, 'VariableNames', ...
    {'simulation_scope', 'simulation_name', 'scenario_id', 'scenario_group', ...
    'method', 'rank_by_iv', 'investment_value_kkrw'});
end

function robustness = buildRobustnessSummary(totalSummary)
% 방법별 지표 통계: 평균·중앙값·표준편차·변동계수
metrics = ["investment_value_kkrw", "risk_reduction_econ_kkrw", ...
    "local_pi", "integrated_pi", "investment_cost_kkrw"];
rows = {};
scopes = unique(string(totalSummary.simulation_scope), "stable");
for sc = 1:numel(scopes)
    scopeData = totalSummary(string(totalSummary.simulation_scope) == scopes(sc), :);
    methods = unique(string(scopeData.method), "stable");
    for m = 1:numel(methods)
        mData = scopeData(string(scopeData.method) == methods(m), :);
        scopeLabel = string(scopeData.simulation_name(1));
        for metric = metrics
            if ~ismember(metric, mData.Properties.VariableNames), continue; end
            vals = mData.(metric);
            vals = vals(isfinite(vals));
            if isempty(vals), continue; end
            cv = safeDivide(std(vals), max(abs(mean(vals)), 1e-10));
            rows(end + 1, :) = {string(scopes(sc)), scopeLabel, methods(m), metric, ...
                mean(vals), median(vals), min(vals), max(vals), std(vals), cv}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    robustness = table(); return;
end
robustness = cell2table(rows, 'VariableNames', ...
    {'simulation_scope', 'simulation_name', 'method', 'metric', ...
    'mean_val', 'median_val', 'min_val', 'max_val', 'std_val', 'cv'});
end

function improvement = buildBaselineImprovement(totalSummary, annualSummary)
% 기준조건(예산 1.0, 물량 1.0, 제약 없음, 전문가 평균) 대비 투자가치 변화율
lastYear = max(annualSummary.year);
annualLast = annualSummary(annualSummary.year == lastYear, :);
baseMask = totalSummary.budget_multiplier == 1.0 & ...
    totalSummary.capacity_multiplier == 1.0 & ...
    ~isfinite(totalSummary.saidi_cap_rate) & ~isfinite(totalSummary.risk_cap_rate) & ...
    string(totalSummary.weight_scenario_id) == "expert_mean";

% SAIDI 누적 저감량 조인
saidiAgg = varfun(@mean, annualLast, "InputVariables", "saidi_removed_cumulative_min", ...
    "GroupingVariables", {'scenario_id', 'method'});
saidiAgg.Properties.VariableNames{end} = 'saidi_removed_cumulative_min';
ts = join(totalSummary, saidiAgg, "Keys", {'scenario_id', 'method'});

rows = {};
scopes = unique(string(ts.simulation_scope), "stable");
for sc = 1:numel(scopes)
    scopeBase = ts(baseMask & string(ts.simulation_scope) == scopes(sc), :);
    scopeAll  = ts(string(ts.simulation_scope) == scopes(sc), :);
    if isempty(scopeBase), continue; end
    methods = unique(string(scopeAll.method), "stable");
    for m = 1:numel(methods)
        baseRow = scopeBase(string(scopeBase.method) == methods(m), :);
        if isempty(baseRow), continue; end
        baseIV    = baseRow.investment_value_kkrw(1);
        baseSaidi = baseRow.saidi_removed_cumulative_min(1);
        allM = scopeAll(string(scopeAll.method) == methods(m), :);
        for r = 1:height(allM)
            ivChg    = safeDivide(allM.investment_value_kkrw(r) - baseIV, abs(baseIV)) * 100;
            saidiChg = safeDivide(allM.saidi_removed_cumulative_min(r) - baseSaidi, abs(max(baseSaidi, 1))) * 100;
            rows(end + 1, :) = {string(scopes(sc)), methods(m), ...
                string(allM.scenario_id(r)), string(allM.scenario_group(r)), ...
                allM.budget_multiplier(r), allM.capacity_multiplier(r), ...
                allM.saidi_cap_rate(r), allM.risk_cap_rate(r), ...
                baseIV, allM.investment_value_kkrw(r), ivChg, saidiChg}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    improvement = table(); return;
end
improvement = cell2table(rows, 'VariableNames', ...
    {'simulation_scope', 'method', 'scenario_id', 'scenario_group', ...
    'budget_multiplier', 'capacity_multiplier', 'saidi_cap_rate', 'risk_cap_rate', ...
    'baseline_iv_kkrw', 'iv_kkrw', 'iv_change_pct', 'saidi_change_pct'});
end

function feasibility = buildFeasibilitySummary(constraintCheck, totalSummary)
% 시뮬레이션·방법별 예산/물량/SAIDI/Risk 제약 충족률 (%)
if isempty(constraintCheck)
    feasibility = table(); return;
end
checkMin = groupsummary(constraintCheck, {'scenario_id', 'method'}, "min", ...
    {'budget_ok', 'capacity_ok', 'saidi_ok', 'risk_ok'});
checkMin.Properties.VariableNames = erase(checkMin.Properties.VariableNames, "min_");
if ismember("GroupCount", checkMin.Properties.VariableNames)
    checkMin = removevars(checkMin, "GroupCount");
end
checkMin.all_ok = checkMin.budget_ok & checkMin.capacity_ok & checkMin.saidi_ok & checkMin.risk_ok;

metaVars = intersect({'scenario_id', 'simulation_scope', 'simulation_name', 'scenario_group', 'method'}, ...
    totalSummary.Properties.VariableNames);
meta = unique(totalSummary(:, metaVars), 'rows');
joined = join(checkMin, meta, "Keys", {'scenario_id', 'method'});

rows = {};
scopes = unique(string(joined.simulation_scope), "stable");
for sc = 1:numel(scopes)
    sd = joined(string(joined.simulation_scope) == scopes(sc), :);
    methods = unique(string(sd.method), "stable");
    for m = 1:numel(methods)
        md = sd(string(sd.method) == methods(m), :);
        n = height(md);
        if n == 0, continue; end
        rows(end + 1, :) = {string(scopes(sc)), string(sd.simulation_name(1)), methods(m), n, ...
            sum(md.budget_ok) / n * 100, sum(md.capacity_ok) / n * 100, ...
            sum(md.saidi_ok) / n * 100, sum(md.risk_ok) / n * 100, ...
            sum(md.all_ok) / n * 100}; %#ok<AGROW>
    end
end
if isempty(rows)
    feasibility = table(); return;
end
feasibility = cell2table(rows, 'VariableNames', ...
    {'simulation_scope', 'simulation_name', 'method', 'scenario_count', ...
    'budget_ok_pct', 'capacity_ok_pct', 'saidi_ok_pct', 'risk_ok_pct', 'all_ok_pct'});
end

function conclusionCheck = buildConclusionCheck(totalSummary, annualSummary)
% 논문 핵심 명제가 몇 % 시나리오에서 유지되는지 확인
% trade-off가 나타나는 경우도 별도로 기록하여 논문 해석에 반영한다.
lastYear = max(annualSummary.year);
annualLast = annualSummary(annualSummary.year == lastYear, :);
saidiAgg = varfun(@mean, annualLast, "InputVariables", "saidi_removed_cumulative_min", ...
    "GroupingVariables", {'scenario_id', 'method'});
saidiAgg.Properties.VariableNames{end} = 'saidi_removed_cumulative_min';
ts = join(totalSummary, saidiAgg, "Keys", {'scenario_id', 'method'});

rows = {};

% 명제 1: risk_value_screening
% investment_value_ilp가 risk_greedy 대비 투자가치 또는 투자효율에서 우수
s1 = ts(string(ts.simulation_scope) == "risk_value_screening", :);
if ~isempty(s1)
    scenIds = unique(string(s1.scenario_id), "stable");
    total = 0; nPass = 0; nTradeoff = 0;
    for si = 1:numel(scenIds)
        ilpRow    = s1(string(s1.scenario_id) == scenIds(si) & string(s1.method) == "investment_value_ilp", :);
        greedyRow = s1(string(s1.scenario_id) == scenIds(si) & string(s1.method) == "risk_greedy", :);
        if isempty(ilpRow) || isempty(greedyRow), continue; end
        total = total + 1;
        ivBetter  = ilpRow.investment_value_kkrw(1) > greedyRow.investment_value_kkrw(1);
        effBetter = ilpRow.investment_efficiency(1) > greedyRow.investment_efficiency(1);
        if ivBetter || effBetter, nPass = nPass + 1; end
        if ivBetter ~= effBetter, nTradeoff = nTradeoff + 1; end
    end
    if total > 0
        rows(end + 1, :) = {"risk_value_screening", "위험도–투자가치 선별 시뮬레이션", ...
            "investment_value_ilp ≻ risk_greedy (투자가치 또는 투자효율)", ...
            total, nPass, nTradeoff, safeDivide(nPass, total) * 100, safeDivide(nTradeoff, total) * 100}; %#ok<AGROW>
    end
end

% 명제 2: local_pi_portfolio
% local_pi_ilp가 investment_value_ilp 대비 Local PI 또는 SAIDI 개선에서 우수
s2 = ts(string(ts.simulation_scope) == "local_pi_portfolio", :);
if ~isempty(s2)
    scenIds = unique(string(s2.scenario_id), "stable");
    total = 0; nPass = 0; nTradeoff = 0;
    for si = 1:numel(scenIds)
        piRow = s2(string(s2.scenario_id) == scenIds(si) & string(s2.method) == "local_pi_ilp", :);
        ivRow = s2(string(s2.scenario_id) == scenIds(si) & string(s2.method) == "investment_value_ilp", :);
        if isempty(piRow) || isempty(ivRow), continue; end
        total = total + 1;
        piBetter    = piRow.local_pi(1) > ivRow.local_pi(1);
        saidiBetter = piRow.saidi_removed_cumulative_min(1) > ivRow.saidi_removed_cumulative_min(1);
        if piBetter || saidiBetter, nPass = nPass + 1; end
        if piBetter ~= saidiBetter, nTradeoff = nTradeoff + 1; end
    end
    if total > 0
        rows(end + 1, :) = {"local_pi_portfolio", "Local PI 포트폴리오 시뮬레이션", ...
            "local_pi_ilp ≻ investment_value_ilp (Local PI 또는 SAIDI)", ...
            total, nPass, nTradeoff, safeDivide(nPass, total) * 100, safeDivide(nTradeoff, total) * 100}; %#ok<AGROW>
    end
end

% 명제 3: integrated_pi_portfolio
% integrated_pi_ilp가 local_pi_ilp 대비 Integrated PI에서 우수
s3 = ts(string(ts.simulation_scope) == "integrated_pi_portfolio", :);
if ~isempty(s3)
    scenIds = unique(string(s3.scenario_id), "stable");
    total = 0; nPass = 0;
    for si = 1:numel(scenIds)
        intRow = s3(string(s3.scenario_id) == scenIds(si) & string(s3.method) == "integrated_pi_ilp", :);
        piRow  = s3(string(s3.scenario_id) == scenIds(si) & string(s3.method) == "local_pi_ilp", :);
        if isempty(intRow) || isempty(piRow), continue; end
        total = total + 1;
        if intRow.integrated_pi(1) > piRow.integrated_pi(1), nPass = nPass + 1; end
    end
    if total > 0
        rows(end + 1, :) = {"integrated_pi_portfolio", "통합 PI 포트폴리오 시뮬레이션", ...
            "integrated_pi_ilp ≻ local_pi_ilp (Integrated PI)", ...
            total, nPass, 0, safeDivide(nPass, total) * 100, 0}; %#ok<AGROW>
    end
end

if isempty(rows)
    conclusionCheck = table(); return;
end
conclusionCheck = cell2table(rows, 'VariableNames', ...
    {'simulation_scope', 'simulation_name', 'proposition', ...
    'total_scenarios', 'scenarios_pass', 'scenarios_tradeoff', ...
    'pass_rate_pct', 'tradeoff_rate_pct'});
end

function writeStatus(runDir, message)
statusFile = fullfile(runDir, "sensitivity_status.txt");
fid = fopen(statusFile, "a", "n", "UTF-8");
if fid < 0
    warning("상태 파일을 열 수 없습니다: %s", statusFile);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "[%s] %s\n", char(string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"))), message);
end

function value = safeDivide(numerator, denominator)
if denominator == 0 || isnan(denominator)
    value = NaN;
else
    value = numerator ./ denominator;
end
end
