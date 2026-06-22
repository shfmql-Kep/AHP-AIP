%% 로컬 PI 기반 투자 최적화 - MATLAB 버전
% 목적:
% 1) 개선된 Local PI 산출 결과를 사용하여 5개년 교체 포트폴리오를 최적화한다.
% 2) AHP 기반 Local PI와 Fuzzy 보정 Local PI를 동일 제약조건에서 비교한다.
% 3) 통합설비 PI는 본 파일에서 다루지 않는다.
%
% 공통 제약:
% - 후보군: candidate_top30_current = 1
% - 각 설비는 계획기간 중 최대 1회 교체
% - 연도별 예산 제약
% - 연도별 물량 제약
%
% 목적함수:
% Maximize Σ_i Σ_t LocalPI_i,t × x_i,t

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputDir = fullfile(baseDir, "outputs");
if ~isfolder(outputDir)
    mkdir(outputDir);
end

pofFile = fullfile(dataDir, "pof_5yr_output.xlsx");
piFile = fullfile(outputDir, "local_pi_matlab.xlsx");
outputFile = fullfile(outputDir, "local_pi_optimization_matlab.xlsx");
runLogFile = fullfile(outputDir, "local_pi_optimization_matlab.log");

years = [2026 2027 2028 2029 2030];
nYears = numel(years);
discountRate = 0.05;
budgetRate = 0.04;
capacityRate = 0.05;
candidateFlag = "candidate_top30_current";

if isfile(runLogFile)
    delete(runLogFile);
end
diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off")); %#ok<NASGU>

fprintf("local PI optimization - MATLAB\n");
fprintf("PoF input: %s\n", pofFile);
fprintf("Local PI input: %s\n", piFile);

if ~isfile(pofFile)
    error("PoF 출력 파일을 찾을 수 없습니다: %s", pofFile);
end
if ~isfile(piFile)
    error("Local PI 산출 파일을 찾을 수 없습니다: %s", piFile);
end

%% 1. 입력 로드
pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
piWide = readtable(piFile, "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
weightsAHP = readtable(piFile, "Sheet", "ahp_sub_weights", "VariableNamingRule", "preserve");
weightsFuzzy = readtable(piFile, "Sheet", "fuzzy_adjusted_weights", "VariableNamingRule", "preserve");

if height(pof) ~= height(piWide)
    error("PoF 출력과 Local PI 출력의 행 수가 다릅니다. PoF=%d, PI=%d", height(pof), height(piWide));
end
if ~all(string(pof.asset_id) == string(piWide.asset_id))
    error("PoF 출력과 Local PI 출력의 asset_id 순서가 일치하지 않습니다.");
end

nAssets = height(pof);
candidateMask = logical(pof.(candidateFlag));
candidateIdx = find(candidateMask);
nCandidates = numel(candidateIdx);

totalAssetValueKkrw = sum(pof.("replacement_cost_2026_kkrw"), "omitnan");
annualBudgetBaseKkrw = totalAssetValueKkrw * budgetRate;
budgets = annualBudgetBaseKkrw ./ ((1 + discountRate) .^ (0:nYears-1));
annualCapacity = round(nAssets * capacityRate);
capacities = repmat(annualCapacity, 1, nYears);

fprintf("assets: %d\n", nAssets);
fprintf("candidate assets: %d\n", nCandidates);
fprintf("annual budget base: %.3f kKRW\n", annualBudgetBaseKkrw);
fprintf("annual capacity: %d assets\n", annualCapacity);

%% 2. 후보군 행렬 구성
costMat = zeros(nCandidates, nYears);
riskReductionMat = zeros(nCandidates, nYears);
investmentValueMat = zeros(nCandidates, nYears);
saidiMat = zeros(nCandidates, nYears);
pofMat = zeros(nCandidates, nYears);
piAhpMat = zeros(nCandidates, nYears);
piFuzzyMat = zeros(nCandidates, nYears);

for y = 1:nYears
    year = years(y);
    costMat(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year))(candidateIdx);
    riskReductionMat(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year))(candidateIdx);
    investmentValueMat(:, y) = pof.(sprintf("investment_value_%d_kkrw", year))(candidateIdx);
    saidiMat(:, y) = pof.(sprintf("saidi_%d_min", year))(candidateIdx);
    pofMat(:, y) = pof.(sprintf("pof_%d", year))(candidateIdx);
    piAhpMat(:, y) = piWide.(sprintf("local_pi_ahp_%d", year))(candidateIdx);
    piFuzzyMat(:, y) = piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(candidateIdx);
end

%% 3. 최적화 실행
fprintf("running investment value greedy...\n");
choiceValueGreedy = runGreedy(nAssets, candidateIdx, costMat, investmentValueMat, budgets, capacities);

fprintf("running investment value ILP...\n");
[choiceValueIlp, statusValueIlp] = runIlp(nAssets, candidateIdx, costMat, investmentValueMat, budgets, capacities);

fprintf("running local PI AHP greedy...\n");
choiceAhpGreedy = runGreedy(nAssets, candidateIdx, costMat, piAhpMat, budgets, capacities);

fprintf("running local PI AHP ILP...\n");
[choiceAhpIlp, statusAhpIlp] = runIlp(nAssets, candidateIdx, costMat, piAhpMat, budgets, capacities);

fprintf("running local PI Fuzzy-adjusted greedy...\n");
choiceFuzzyGreedy = runGreedy(nAssets, candidateIdx, costMat, piFuzzyMat, budgets, capacities);

fprintf("running local PI Fuzzy-adjusted ILP...\n");
[choiceFuzzyIlp, statusFuzzyIlp] = runIlp(nAssets, candidateIdx, costMat, piFuzzyMat, budgets, capacities);

methodNames = [
    "investment_value_greedy"
    "investment_value_ilp"
    "local_pi_ahp_greedy"
    "local_pi_ahp_ilp"
    "local_pi_fuzzy_adjusted_greedy"
    "local_pi_fuzzy_adjusted_ilp"
    ];
choices = {choiceValueGreedy; choiceValueIlp; choiceAhpGreedy; choiceAhpIlp; choiceFuzzyGreedy; choiceFuzzyIlp};
objectiveNames = [
    "investment_value"
    "investment_value"
    "local_pi_ahp"
    "local_pi_ahp"
    "local_pi_fuzzy_adjusted"
    "local_pi_fuzzy_adjusted"
    ];

%% 4. 결과표 생성
candidateSummary = buildCandidateSummary(pof, candidateMask, budgetRate, capacityRate);
constraints = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, ...
    annualBudgetBaseKkrw, annualCapacity, budgets, capacities, years);
weightSummary = buildWeightSummary(weightsAHP, weightsFuzzy);
annualSummary = buildAnnualSummary(methodNames, objectiveNames, choices, pof, piWide, years, budgets, capacities);
totalSummary = buildTotalSummary(methodNames, annualSummary);
selectedAssets = buildSelectedAssets(methodNames, objectiveNames, choices, pof, piWide, years);
assetTypeSummary = buildAssetTypeSummary(selectedAssets);
feasibility = buildFeasibility(methodNames, choices, pof, years, budgets, capacities, candidateMask);
solverStatus = buildSolverStatus(methodNames, statusValueIlp, statusAhpIlp, statusFuzzyIlp);

%% 5. 저장
if isfile(outputFile)
    delete(outputFile);
end
writetable(candidateSummary, outputFile, "Sheet", "candidate_summary");
writetable(constraints, outputFile, "Sheet", "constraints");
writetable(weightSummary, outputFile, "Sheet", "weight_summary");
writetable(totalSummary, outputFile, "Sheet", "total_summary");
writetable(annualSummary, outputFile, "Sheet", "annual_summary");
writetable(assetTypeSummary, outputFile, "Sheet", "asset_type_summary");
writetable(selectedAssets, outputFile, "Sheet", "selected_assets");
writetable(feasibility, outputFile, "Sheet", "feasibility");
writetable(solverStatus, outputFile, "Sheet", "solver_status");

fprintf("saved: %s\n", outputFile);

%% =========================================================================
% 지역 함수
% =========================================================================

function choice = runGreedy(nAssets, candidateIdx, costMat, scoreMat, budgets, capacities)
% 연도별 예산·물량 제약 하에서 점수 내림차순으로 선택한다.
nYears = numel(budgets);
choice = zeros(nAssets, 1);
remaining = true(numel(candidateIdx), 1);
for y = 1:nYears
    budgetLeft = budgets(y);
    capacityLeft = capacities(y);
    [~, order] = sort(scoreMat(:, y), "descend");
    for ii = 1:numel(order)
        k = order(ii);
        if ~remaining(k) || scoreMat(k, y) <= 0
            continue;
        end
        itemCost = costMat(k, y);
        if itemCost <= budgetLeft && capacityLeft > 0
            choice(candidateIdx(k)) = y;
            remaining(k) = false;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
        if budgetLeft <= 0 || capacityLeft <= 0
            break;
        end
    end
end
end

function [choice, status] = runIlp(nAssets, candidateIdx, costMat, scoreMat, budgets, capacities)
% Local PI 총합을 최대화하는 0-1 정수계획법.
nCandidates = numel(candidateIdx);
nYears = numel(budgets);
nVars = nCandidates * nYears;

f = -scoreMat(:);
intcon = 1:nVars;
lb = zeros(nVars, 1);
ub = ones(nVars, 1);

% 각 후보 설비는 최대 1회만 교체 가능하다.
AAsset = kron(ones(1, nYears), speye(nCandidates));
bAsset = ones(nCandidates, 1);

% 연도별 예산·물량 제약.
ABudget = sparse(nYears, nVars);
ACapacity = sparse(nYears, nVars);
for y = 1:nYears
    cols = ((y - 1) * nCandidates + 1):(y * nCandidates);
    ABudget(y, cols) = costMat(:, y)';
    ACapacity(y, cols) = 1;
end

A = [AAsset; ABudget; ACapacity];
b = [bAsset; budgets(:); capacities(:)];

options = optimoptions("intlinprog", ...
    "Display", "final");

fprintf("ILP variables: %d\n", nVars);
fprintf("ILP constraints: %d\n", size(A, 1));
fprintf("ILP time limit: none\n");

[x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);

choice = zeros(nAssets, 1);
if ~isempty(x)
    xMat = reshape(x, nCandidates, nYears);
    for y = 1:nYears
        selectedLocal = find(xMat(:, y) > 0.5);
        choice(candidateIdx(selectedLocal)) = y;
    end
end

status.exitflag = exitflag;
status.objective_pi = -fval;
status.message = string(output.message);
status.relative_gap = getOptionalField(output, "relativegap");
status.absolute_gap = getOptionalField(output, "absolutegap");
status.nodes = getOptionalField(output, "numnodes");
status.iterations = getOptionalField(output, "iterations");
end

function value = getOptionalField(s, fieldName)
% MATLAB 버전에 따라 intlinprog output 필드명이 다를 수 있어 안전하게 읽는다.
if isfield(s, fieldName)
    value = s.(fieldName);
else
    value = NaN;
end
end

function T = buildCandidateSummary(pof, candidateMask, budgetRate, capacityRate)
% 후보군과 기본 제약 설정 요약.
nAssets = height(pof);
candidateCount = sum(candidateMask);
items = [
    "total_assets"
    "risk_top30_current_assets"
    "investment_value_top30_current_assets"
    "optimization_candidate_assets"
    "optimization_candidate_ratio"
    "budget_rate"
    "capacity_rate"
    "ilp_time_limit"
    ];
values = [
    nAssets
    sum(pof.("risk_top30_current"))
    sum(pof.("investment_value_top30_current"))
    candidateCount
    candidateCount / nAssets
    budgetRate
    capacityRate
    NaN
    ];
notes = [
    "all assets in pof_5yr_output"
    "top 30% by risk_2026_kkrw"
    "top 30% by investment_value_2026_kkrw"
    "candidate_top30_current = 1"
    "candidate assets / total assets"
    "annual budget ratio"
    "annual construction capacity ratio"
    "none"
    ];
T = table(items, values, notes, 'VariableNames', {'item', 'value', 'note'});
end

function T = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, annualBudgetBaseKkrw, ...
    annualCapacity, budgets, capacities, years)
% 제약조건 요약.
items = ["total_asset_value_proxy_kkrw"; "budget_rate"; "capacity_rate"; ...
    "annual_budget_base_2026_kkrw"; "annual_capacity_assets"];
values = [totalAssetValueKkrw; budgetRate; capacityRate; annualBudgetBaseKkrw; annualCapacity];
notes = ["sum of replacement_cost_2026_kkrw"; "annual budget ratio"; ...
    "annual capacity ratio"; "base annual budget before discounting"; ...
    "round(total assets * capacity rate)"];
for y = 1:numel(years)
    items(end + 1, 1) = "budget_" + years(y) + "_kkrw"; %#ok<AGROW>
    values(end + 1, 1) = budgets(y); %#ok<AGROW>
    notes(end + 1, 1) = "annual budget discounted to PV"; %#ok<AGROW>
    items(end + 1, 1) = "capacity_" + years(y) + "_assets"; %#ok<AGROW>
    values(end + 1, 1) = capacities(y); %#ok<AGROW>
    notes(end + 1, 1) = "annual construction capacity"; %#ok<AGROW>
end
T = table(items, values, notes, 'VariableNames', {'item', 'value', 'note'});
end

function T = buildWeightSummary(weightsAHP, weightsFuzzy)
% 최적화에 사용한 PI 가중치 요약.
metricId = string(weightsAHP.metric_id);
metricName = string(weightsAHP.metric_name);
parentCriterion = string(weightsAHP.parent_criterion);
ahpWeight = double(weightsAHP.weight);
fuzzyAdjustedWeight = zeros(height(weightsAHP), 1);
for i = 1:height(weightsAHP)
    idx = string(weightsFuzzy.metric_id) == metricId(i);
    fuzzyAdjustedWeight(i) = weightsFuzzy.fuzzy_adjusted_weight(idx);
end
difference = fuzzyAdjustedWeight - ahpWeight;
T = table(metricId, metricName, parentCriterion, ahpWeight, fuzzyAdjustedWeight, difference, ...
    'VariableNames', {'metric_id', 'metric_name', 'parent_criterion', ...
    'ahp_weight', 'fuzzy_adjusted_weight', 'difference'});
end

function T = buildAnnualSummary(methodNames, objectiveNames, choices, pof, piWide, years, budgets, capacities)
% 방법별·연도별 투자효과 요약.
rows = {};
baselineSaidi = zeros(1, numel(years));
baselineFailures = zeros(1, numel(years));
baselineRisk = zeros(1, numel(years));
for y = 1:numel(years)
    year = years(y);
    baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year)), "omitnan");
    baselineFailures(y) = sum(pof.(sprintf("pof_%d", year)), "omitnan");
    baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan");
end

for m = 1:numel(methodNames)
    method = methodNames(m);
    objectiveName = objectiveNames(m);
    choice = choices{m};
    for y = 1:numel(years)
        year = years(y);
        selected = find(choice == y);
        cumulativeSelected = find(choice > 0 & choice <= y);
        cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
        riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
        value = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
        saidiAtSelection = sum(pof.(sprintf("saidi_%d_min", year))(selected), "omitnan");
        pofAtSelection = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
        objectiveScore = sum(getObjectiveVector(pof, piWide, objectiveName, year, selected), "omitnan");

        saidiReductionCumulative = sum(pof.(sprintf("saidi_%d_min", year))(cumulativeSelected), "omitnan");
        failuresReductionCumulative = sum(pof.(sprintf("pof_%d", year))(cumulativeSelected), "omitnan");
        saidiAfter = baselineSaidi(y) - saidiReductionCumulative;
        failuresAfter = baselineFailures(y) - failuresReductionCumulative;

        rows(end + 1, :) = {method, objectiveName, year, numel(selected), capacities(y), ...
            safeDivide(numel(selected), capacities(y)), cost, budgets(y), safeDivide(cost, budgets(y)), ...
            riskReduction, value, safeDivide(riskReduction, cost), saidiAtSelection, pofAtSelection, ...
            objectiveScore, baselineRisk(y), baselineSaidi(y), saidiReductionCumulative, saidiAfter, ...
            baselineFailures(y), failuresReductionCumulative, failuresAfter}; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', {'method', 'objective', 'year', 'selected_count', ...
    'capacity_limit', 'capacity_used_pct', 'investment_cost_kkrw', ...
    'budget_limit_kkrw', 'budget_used_pct', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'investment_efficiency', 'saidi_at_selection_min', ...
    'expected_failures_at_selection', 'objective_score', 'baseline_risk_kkrw', ...
    'baseline_saidi_min', 'saidi_reduction_cumulative_min', 'saidi_after_cumulative_min', ...
    'baseline_expected_failures', 'expected_failures_reduction_cumulative', ...
    'expected_failures_after_cumulative'});
end

function T = buildTotalSummary(methodNames, annualSummary)
% 방법별 합계 요약.
rows = {};
for m = 1:numel(methodNames)
    method = methodNames(m);
    sub = annualSummary(annualSummary.method == method, :);
    totalCount = sum(sub.selected_count);
    totalCost = sum(sub.investment_cost_kkrw, "omitnan");
    totalRiskReduction = sum(sub.risk_reduction_kkrw, "omitnan");
    totalValue = sum(sub.investment_value_kkrw, "omitnan");
    totalSaidiAtSelection = sum(sub.saidi_at_selection_min, "omitnan");
    totalFailuresAtSelection = sum(sub.expected_failures_at_selection, "omitnan");
    totalObjectiveScore = sum(sub.objective_score, "omitnan");
    finalSaidiAfter = sub.saidi_after_cumulative_min(sub.year == max(sub.year));
    finalFailuresAfter = sub.expected_failures_after_cumulative(sub.year == max(sub.year));
    rows(end + 1, :) = {method, string(sub.objective(1)), totalCount, totalCost, ...
        totalRiskReduction, totalValue, safeDivide(totalRiskReduction, totalCost), ...
        totalSaidiAtSelection, totalFailuresAtSelection, totalObjectiveScore, ...
        finalSaidiAfter(1), finalFailuresAfter(1), ...
        mean(sub.budget_used_pct, "omitnan"), mean(sub.capacity_used_pct, "omitnan")}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'method', 'objective', 'total_selected_count', ...
    'total_investment_cost_kkrw', 'total_risk_reduction_kkrw', ...
    'total_investment_value_kkrw', 'total_investment_efficiency', ...
    'total_saidi_at_selection_min', 'total_expected_failures_at_selection', ...
    'total_objective_score', 'final_2030_saidi_after_cumulative_min', ...
    'final_2030_expected_failures_after_cumulative', ...
    'avg_budget_used_pct', 'avg_capacity_used_pct'});
T = sortrows(T, {'objective', 'total_objective_score'}, {'ascend', 'descend'});
end

function T = buildSelectedAssets(methodNames, objectiveNames, choices, pof, piWide, years)
% 선택 자산 상세표.
rows = {};
for m = 1:numel(methodNames)
    choice = choices{m};
    method = methodNames(m);
    objectiveName = objectiveNames(m);
    for y = 1:numel(years)
        year = years(y);
        selected = find(choice == y);
        for ii = 1:numel(selected)
            idx = selected(ii);
            ahpPi = piWide.(sprintf("local_pi_ahp_%d", year))(idx);
            fuzzyPi = piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(idx);
            objectiveScore = getObjectiveScalar(pof, piWide, objectiveName, year, idx);
            rows(end + 1, :) = {method, objectiveName, string(pof.("asset_id")(idx)), ...
                string(pof.("asset_type")(idx)), string(piWide.("asset_label")(idx)), ...
                string(piWide.("asset_group")(idx)), pof.("risk_top30_current")(idx), ...
                pof.("investment_value_top30_current")(idx), pof.("candidate_top30_current")(idx), ...
                year, pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
                pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
                pof.(sprintf("investment_value_%d_kkrw", year))(idx), ...
                pof.(sprintf("bcr_%d", year))(idx), ...
                pof.(sprintf("saidi_%d_min", year))(idx), ...
                pof.(sprintf("pof_%d", year))(idx), ahpPi, fuzzyPi, objectiveScore}; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    T = table();
else
    T = cell2table(rows, 'VariableNames', {'method', 'objective', 'asset_id', 'asset_type', ...
        'asset_label', 'asset_group', 'risk_top30_current', 'investment_value_top30_current', ...
        'candidate_top30_current', 'replacement_year', 'replacement_cost_kkrw', ...
        'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
        'saidi_at_replacement_min', 'pof_at_replacement', ...
        'local_pi_ahp', 'local_pi_fuzzy_adjusted', 'objective_score'});
    T = sortrows(T, {'method', 'replacement_year', 'objective_score'}, ...
        {'ascend', 'ascend', 'descend'});
    T.selection_rank = groupRank(T.method, T.replacement_year);
    T = movevars(T, 'selection_rank', 'Before', 1);
end
end

function ranks = groupRank(methods, years)
% method-year 그룹별 선택 순위.
ranks = zeros(numel(methods), 1);
keys = string(methods) + "_" + string(years);
uniqueKeys = unique(keys, "stable");
for i = 1:numel(uniqueKeys)
    idx = find(keys == uniqueKeys(i));
    ranks(idx) = (1:numel(idx))';
end
end

function T = buildAssetTypeSummary(selectedAssets)
% 설비유형별 선택 결과.
if isempty(selectedAssets) || height(selectedAssets) == 0
    T = table();
    return;
end
[G, method, objective, replacementYear, assetType, assetLabel, assetGroup] = findgroups( ...
    selectedAssets.method, selectedAssets.objective, selectedAssets.replacement_year, ...
    selectedAssets.asset_type, selectedAssets.asset_label, selectedAssets.asset_group);
selectedCount = splitapply(@numel, selectedAssets.asset_id, G);
cost = splitapply(@sum, selectedAssets.replacement_cost_kkrw, G);
riskReduction = splitapply(@sum, selectedAssets.risk_reduction_kkrw, G);
value = splitapply(@sum, selectedAssets.investment_value_kkrw, G);
saidi = splitapply(@sum, selectedAssets.saidi_at_replacement_min, G);
failures = splitapply(@sum, selectedAssets.pof_at_replacement, G);
objectiveScore = splitapply(@sum, selectedAssets.objective_score, G);
efficiency = riskReduction ./ max(cost, 1);
T = table(method, objective, replacementYear, assetType, assetLabel, assetGroup, ...
    selectedCount, cost, riskReduction, value, efficiency, saidi, failures, objectiveScore, ...
    'VariableNames', {'method', 'objective', 'replacement_year', 'asset_type', ...
    'asset_label', 'asset_group', 'selected_count', 'investment_cost_kkrw', ...
    'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
    'saidi_at_selection_min', 'expected_failures_at_selection', 'objective_score'});
end

function T = buildFeasibility(methodNames, choices, pof, years, budgets, capacities, candidateMask)
% 해의 제약조건 충족 여부.
rows = {};
for m = 1:numel(methodNames)
    choice = choices{m};
    selected = find(choice > 0);
    withinCandidate = all(candidateMask(selected));
    oneReplacementOk = all(choice >= 0);
    budgetOk = true;
    capacityOk = true;
    for y = 1:numel(years)
        year = years(y);
        selectedYear = find(choice == y);
        cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selectedYear), "omitnan");
        budgetOk = budgetOk && cost <= budgets(y) + 1e-6;
        capacityOk = capacityOk && numel(selectedYear) <= capacities(y);
    end
    rows(end + 1, :) = {methodNames(m), budgetOk && capacityOk && withinCandidate && oneReplacementOk, ...
        budgetOk, capacityOk, withinCandidate, oneReplacementOk, numel(selected)}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'method', 'is_feasible', 'budget_ok', ...
    'capacity_ok', 'candidate_pool_ok', 'one_replacement_ok', 'selected_assets'});
end

function values = getObjectiveVector(pof, piWide, objectiveName, year, indices)
% 목적함수 종류에 따라 선택 자산의 목적함수 계수 벡터를 반환한다.
if objectiveName == "investment_value"
    values = pof.(sprintf("investment_value_%d_kkrw", year))(indices);
elseif objectiveName == "local_pi_ahp"
    values = piWide.(sprintf("local_pi_ahp_%d", year))(indices);
elseif objectiveName == "local_pi_fuzzy_adjusted"
    values = piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(indices);
else
    error("알 수 없는 목적함수입니다: %s", objectiveName);
end
end

function value = getObjectiveScalar(pof, piWide, objectiveName, year, idx)
% 단일 자산의 목적함수 계수를 반환한다.
value = getObjectiveVector(pof, piWide, objectiveName, year, idx);
end

function T = buildSolverStatus(methodNames, statusValueIlp, statusAhpIlp, statusFuzzyIlp)
% solver 상태 기록.
solver = ["greedy"; "intlinprog"; "greedy"; "intlinprog"; "greedy"; "intlinprog"];
exitflag = [NaN; statusValueIlp.exitflag; NaN; statusAhpIlp.exitflag; NaN; statusFuzzyIlp.exitflag];
objectiveScore = [NaN; statusValueIlp.objective_pi; NaN; statusAhpIlp.objective_pi; NaN; statusFuzzyIlp.objective_pi];
relativeGap = [NaN; statusValueIlp.relative_gap; NaN; statusAhpIlp.relative_gap; NaN; statusFuzzyIlp.relative_gap];
absoluteGap = [NaN; statusValueIlp.absolute_gap; NaN; statusAhpIlp.absolute_gap; NaN; statusFuzzyIlp.absolute_gap];
nodes = [NaN; statusValueIlp.nodes; NaN; statusAhpIlp.nodes; NaN; statusFuzzyIlp.nodes];
iterations = [NaN; statusValueIlp.iterations; NaN; statusAhpIlp.iterations; NaN; statusFuzzyIlp.iterations];
message = ["score descending heuristic"; statusValueIlp.message; ...
    "score descending heuristic"; statusAhpIlp.message; ...
    "score descending heuristic"; statusFuzzyIlp.message];
T = table(methodNames, solver, exitflag, objectiveScore, relativeGap, absoluteGap, ...
    nodes, iterations, message, ...
    'VariableNames', {'method', 'solver', 'exitflag', 'objective_score', ...
    'relative_gap', 'absolute_gap', 'nodes', 'iterations', 'message'});
end

function out = safeDivide(a, b)
% 0 나누기 방지.
if b == 0
    out = 0;
else
    out = a / b;
end
end
