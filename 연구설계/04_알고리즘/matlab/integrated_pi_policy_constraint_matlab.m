%% 통합 PI 정책 제약 시뮬레이션
% 목적:
%   전체 예산·물량 제약만 적용한 통합형 ILP와,
%   설비유형별 연간 최소 교체대수 또는 연간 최소 투자예산 하한을 추가한 정책 제약형 통합형 ILP를 비교한다.
%
% 논문 해석 관점:
%   - 기준안은 전체 시스템 관점에서 통합 PI를 최대화하는 순수 효율 최적화이다.
%   - 정책 제약안은 특정 설비유형에 연도별 최소한의 투자 또는 교체가 요구되는 상황을 모사한다.
%   - 두 결과의 차이는 정책적 배분 제약이 통합 PI, 투자가치, 리스크 저감량, SAIDI에 미치는 영향을 보여준다.
%
% 실행:
%   run("연구설계/04_알고리즘/matlab/integrated_pi_policy_constraint_matlab.m")
%
% 주요 환경변수:
%   POLICY_METHODS                : 비교할 목적함수. 기본 "investment_value_ilp,integrated_pi_ilp"
%   POLICY_MIN_TYPE_COUNT_RATES   : 설비유형별 보유대수 대비 연간 최소 교체 비율. 예: "0.01,0.015,...,0.045"
%   POLICY_MIN_TYPE_BUDGET_RATES  : 설비유형별 자산가액 대비 연간 최소 투자 비율. 예: "0.01,0.015,...,0.035"
%   POLICY_MIN_TYPE_COUNT_VECTOR  : 사용자 지정 연간 최소 교체대수 벡터. 예: "5,3,3,2,4,2"
%   POLICY_MIN_TYPE_BUDGET_VECTOR : 사용자 지정 연간 최소 예산 벡터(kKRW). 예: "100000,80000,50000,50000,70000,70000"
%   POLICY_ILP_MAX_TIME           : ILP 시간 제한(초). 기본 300
%   POLICY_ILP_REL_GAP            : ILP 상대 갭 허용값. 기본 0.001

clear; clc;

baseDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
dataDir = fullfile(baseDir, "02_입력데이터");
piDir = fullfile(baseDir, "05_PI_산출결과");
resultRoot = fullfile(baseDir, "06_시뮬레이션결과", "정책제약_통합PI");
runStamp = char(string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
runDir = fullfile(resultRoot, ['integrated_pi_policy_constraint_' runStamp]);
mkdir(runDir);

diary(fullfile(runDir, "integrated_pi_policy_constraint.log"));
diary on;
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

years = [2026 2027 2028 2029 2030];
assetTypes = ["pole_transformer", "ground_transformer", "overhead_switch", ...
    "underground_switch", "overhead_line", "underground_cable"];
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", ...
    "지중개폐기", "가공배전선로", "지중케이블"];

budgetRate = 0.04;
capacityRate = 0.05;
discountRate = 0.05;
candidateQuantile = 0.70;

fprintf("=== 통합 PI 정책 제약 시뮬레이션 시작 ===\n");
fprintf("결과 폴더: %s\n", runDir);

%% 1. 입력 데이터 로드
pof = readtable(fullfile(dataDir, "pof_5yr_output.xlsx"), ...
    "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
localPi = readtable(fullfile(piDir, "local_pi_matlab.xlsx"), ...
    "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
integratedPi = readtable(fullfile(piDir, "integrated_pi_matlab.xlsx"), ...
    "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");

if height(pof) ~= height(localPi) || any(string(pof.asset_id) ~= string(localPi.asset_id))
    error("PoF 출력과 설비 단위 PI 파일의 asset_id가 일치하지 않습니다.");
end
if height(pof) ~= height(integratedPi) || any(string(pof.asset_id) ~= string(integratedPi.asset_id))
    error("PoF 출력과 통합 PI 파일의 asset_id가 일치하지 않습니다.");
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
candidateIdx = find(candidateMask);
allAssetIdx = (1:height(pof))';

baseConstraints = buildBaseConstraints(pof, allAssetIdx, years, budgetRate, capacityRate, discountRate);
candidateSummary = buildCandidateSummary(pof, assetTypes, assetLabels, candidateMask);
methodList = readStringListEnv("POLICY_METHODS", ["investment_value_ilp", "integrated_pi_ilp"]);
scenarioList = buildPolicyScenarios(pof, assetTypes, years, discountRate);
scenarioTable = scenarioListToTable(scenarioList, assetTypes, assetLabels, years);
configTable = table( ...
    string(runStamp), "annual_type_policy_constraints_v2", "annual", ...
    budgetRate, capacityRate, discountRate, candidateQuantile, ...
    strjoin(methodList, ","), sum(baseConstraints.budgets), sum(baseConstraints.capacities), ...
    'VariableNames', {'run_stamp', 'code_version', 'type_policy_constraint_scope', ...
    'budget_rate', 'capacity_rate', 'discount_rate', ...
    'candidate_quantile', 'methods', 'five_year_budget_kkrw', 'five_year_capacity'});

resultFile = fullfile(runDir, "integrated_pi_policy_constraint_results.xlsx");
writetable(configTable, resultFile, "Sheet", "00_run_config");
writetable(candidateSummary, resultFile, "Sheet", "01_candidate_summary");
writetable(scenarioTable, resultFile, "Sheet", "02_policy_scenarios");

%% 2. 시나리오별 통합형 ILP 수행
mats = buildMatrices(pof, candidateIdx, years);
candidateAssetTypes = string(pof.asset_type(candidateIdx));

annualParts = {};
totalParts = {};
typeParts = {};
constraintParts = {};
selectedParts = {};
solverRows = {};

for s = 1:numel(scenarioList)
    scenario = scenarioList(s);
    fprintf("\n[%02d/%02d] %s 실행\n", s, numel(scenarioList), scenario.scenario_id);
    constraints = baseConstraints;
    constraints.minTypeCount = scenario.minTypeCount;
    constraints.minTypeBudget = scenario.minTypeBudget;

    for m = 1:numel(methodList)
        method = methodList(m);
        [objectiveName, scoreMat] = getPolicyScoreMatrix(method, mats);
        fprintf("  - %s 실행\n", method);
        tic;
        [choiceLocal, solverInfo] = runPolicyIlp(scoreMat, mats, constraints, candidateAssetTypes, assetTypes);
        elapsed = toc;

        choiceGlobal = zeros(height(pof), 1, "int16");
        choiceGlobal(candidateIdx) = choiceLocal;

        [annual, total, typeSummary, constraintCheck, selectedAssets] = summarizePolicyChoice( ...
            pof, choiceGlobal, scenario, method, objectiveName, constraints, years, assetTypes, assetLabels);

        annualParts{end + 1} = annual; %#ok<AGROW>
        totalParts{end + 1} = total; %#ok<AGROW>
        typeParts{end + 1} = typeSummary; %#ok<AGROW>
        constraintParts{end + 1} = constraintCheck; %#ok<AGROW>
        selectedParts{end + 1} = selectedAssets; %#ok<AGROW>

        solverRows(end + 1, :) = { ...
            string(scenario.scenario_id), string(scenario.scenario_name), string(scenario.scenario_group), ...
            method, objectiveName, string(solverInfo.solver), ...
            solverInfo.exitflag, string(solverInfo.message), solverInfo.objective, ...
            numel(candidateIdx), sum(choiceGlobal > 0), elapsed}; %#ok<AGROW>

        fprintf("    선택 %d대, 통합 PI %.2f, 투자가치 %.2f억 원, %.1f초\n", ...
            total.selected_count(1), total.integrated_pi(1), total.investment_value_kkrw(1) / 100000, elapsed);
    end
end

annualSummary = vertcat(annualParts{:});
totalSummary = vertcat(totalParts{:});
typeSummary = vertcat(typeParts{:});
constraintCheck = vertcat(constraintParts{:});
selectedAssets = vertcat(selectedParts{:});
solverStatus = cell2table(solverRows, 'VariableNames', {'scenario_id', 'scenario_name', ...
    'scenario_group', 'method', 'objective', 'solver', 'exitflag', 'message', ...
    'objective_value', 'candidate_count', 'selected_count', 'elapsed_seconds'});
tradeoffSummary = buildTradeoffSummary(totalSummary);

writetable(annualSummary, resultFile, "Sheet", "03_annual_summary");
writetable(totalSummary, resultFile, "Sheet", "04_total_comparison");
writetable(typeSummary, resultFile, "Sheet", "05_type_summary");
writetable(constraintCheck, resultFile, "Sheet", "06_constraint_check");
writetable(selectedAssets, resultFile, "Sheet", "07_selected_assets");
writetable(solverStatus, resultFile, "Sheet", "08_solver_status");
writetable(tradeoffSummary, resultFile, "Sheet", "09_tradeoff_vs_base");

fprintf("\n=== 통합 PI 정책 제약 시뮬레이션 완료 ===\n");
fprintf("결과 파일: %s\n", resultFile);

%% =========================================================================
% 로컬 함수
% =========================================================================

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
    riskValues = pof.risk_2026_kkrw(idx);
    valueValues = pof.investment_value_2026_kkrw(idx);
    riskThreshold = quantile(riskValues(isfinite(riskValues)), candidateQuantile);
    valueThreshold = quantile(valueValues(isfinite(valueValues)), candidateQuantile);
    candidateMask(idx) = riskValues >= riskThreshold | valueValues >= valueThreshold;
end
end

function constraints = buildBaseConstraints(pof, assetIdx, years, budgetRate, capacityRate, discountRate)
assetValue = sum(pof.replacement_cost_2026_kkrw(assetIdx), "omitnan");
baseBudget = assetValue * budgetRate;
nYears = numel(years);
budgets = zeros(1, nYears);
for y = 1:nYears
    budgets(y) = baseBudget / ((1 + discountRate) ^ (y - 1));
end
constraints.budgets = budgets;
constraints.capacities = repmat(max(1, ceil(numel(assetIdx) * capacityRate)), 1, nYears);
constraints.minTypeCount = [];
constraints.minTypeBudget = [];
constraints.baselineRisk = zeros(1, nYears);
constraints.baselineSaidi = zeros(1, nYears);
for y = 1:nYears
    year = years(y);
    constraints.baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year))(assetIdx), "omitnan");
    constraints.baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year))(assetIdx), "omitnan");
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

function summary = buildCandidateSummary(pof, assetTypes, assetLabels, candidateMask)
rows = {};
for t = 1:numel(assetTypes)
    typeIdx = find(string(pof.asset_type) == assetTypes(t));
    candIdx = typeIdx(candidateMask(typeIdx));
    rows(end + 1, :) = {assetTypes(t), assetLabels(t), numel(typeIdx), numel(candIdx), ...
        safeDivide(numel(candIdx), numel(typeIdx)), ...
        sum(pof.replacement_cost_2026_kkrw(typeIdx), "omitnan"), ...
        sum(pof.replacement_cost_2026_kkrw(candIdx), "omitnan")}; %#ok<AGROW>
end
summary = cell2table(rows, 'VariableNames', {'asset_type', 'asset_type_label', ...
    'asset_count', 'candidate_count', 'candidate_ratio', ...
    'asset_value_2026_kkrw', 'candidate_asset_value_2026_kkrw'});
end

function scenarioList = buildPolicyScenarios(pof, assetTypes, years, discountRate)
nTypes = numel(assetTypes);
nYears = numel(years);
typeAssetCounts = zeros(1, nTypes);
typeAssetValues = zeros(1, nTypes);
for t = 1:nTypes
    typeIdx = find(string(pof.asset_type) == assetTypes(t));
    typeAssetCounts(t) = numel(typeIdx);
    typeAssetValues(t) = sum(pof.replacement_cost_2026_kkrw(typeIdx), "omitnan");
end
scenarioList = struct('scenario_id', {}, 'scenario_name', {}, 'scenario_group', {}, ...
    'minTypeCount', {}, 'minTypeBudget', {});

scenarioList(end + 1) = makeScenario("baseline_budget_only", "전체 예산·물량 제약", ...
    "baseline", zeros(nTypes, nYears), zeros(nTypes, nYears));

countRates = readVectorEnv("POLICY_MIN_TYPE_COUNT_RATES", 0.01:0.005:0.045);
for k = 1:numel(countRates)
    rate = max(0, countRates(k));
    minCounts = repmat(ceil(typeAssetCounts(:) * rate), 1, nYears);
    scenarioList(end + 1) = makeScenario( ...
        sprintf("min_count_rate_%03d", round(rate * 1000)), ...
        sprintf("설비유형별 보유대수 %.1f%% 이상 연간 교체", rate * 100), ...
        "min_count_rate", minCounts, zeros(nTypes, nYears)); %#ok<AGROW>
end

budgetRates = readVectorEnv("POLICY_MIN_TYPE_BUDGET_RATES", 0.01:0.005:0.035);
for k = 1:numel(budgetRates)
    rate = max(0, budgetRates(k));
    minBudget = zeros(nTypes, nYears);
    for y = 1:nYears
        minBudget(:, y) = typeAssetValues(:) * rate / ((1 + discountRate) ^ (y - 1));
    end
    scenarioList(end + 1) = makeScenario( ...
        sprintf("min_budget_%03d_each", round(rate * 1000)), ...
        sprintf("설비유형별 자산가액 %.1f%% 이상 연간 투자", rate * 100), ...
        "min_budget_rate", zeros(nTypes, nYears), minBudget); %#ok<AGROW>
end

customCount = readVectorEnv("POLICY_MIN_TYPE_COUNT_VECTOR", []);
if numel(customCount) == nTypes
    scenarioList(end + 1) = makeScenario("custom_min_count", ...
        "사용자 지정 설비유형별 연간 최소 교체대수", ...
        "custom_min_count", repmat(max(0, round(customCount(:))), 1, nYears), zeros(nTypes, nYears)); %#ok<AGROW>
end

customBudget = readVectorEnv("POLICY_MIN_TYPE_BUDGET_VECTOR", []);
if numel(customBudget) == nTypes
    scenarioList(end + 1) = makeScenario("custom_min_budget", ...
        "사용자 지정 설비유형별 연간 최소 투자예산", ...
        "custom_min_budget", zeros(nTypes, nYears), repmat(max(0, customBudget(:)), 1, nYears)); %#ok<AGROW>
end
end

function scenario = makeScenario(id, name, group, minTypeCount, minTypeBudget)
scenario = struct( ...
    "scenario_id", string(id), ...
    "scenario_name", string(name), ...
    "scenario_group", string(group), ...
    "minTypeCount", double(minTypeCount), ...
    "minTypeBudget", double(minTypeBudget));
end

function scenarioTable = scenarioListToTable(scenarioList, assetTypes, assetLabels, years)
rows = {};
for s = 1:numel(scenarioList)
    scenario = scenarioList(s);
    for t = 1:numel(assetTypes)
        for y = 1:numel(years)
            rows(end + 1, :) = {scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
                years(y), assetTypes(t), assetLabels(t), ...
                scenario.minTypeCount(t, y), scenario.minTypeBudget(t, y)}; %#ok<AGROW>
        end
    end
end
scenarioTable = cell2table(rows, 'VariableNames', {'scenario_id', 'scenario_name', ...
    'scenario_group', 'year', 'asset_type', 'asset_type_label', ...
    'min_selected_count', 'min_investment_budget_kkrw'});
end

function values = readVectorEnv(name, defaultValues)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    values = defaultValues;
    return;
end
parts = split(raw, [",", ";", " "]);
parts = parts(strlength(strtrim(parts)) > 0);
values = zeros(1, numel(parts));
for i = 1:numel(parts)
    values(i) = str2double(parts(i));
end
values = values(isfinite(values));
if isempty(values)
    values = defaultValues;
end
end

function values = readStringListEnv(name, defaultValues)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    values = defaultValues;
    return;
end
parts = strtrim(split(raw, [",", ";"]));
parts = parts(strlength(parts) > 0);
if isempty(parts)
    values = defaultValues;
else
    values = string(parts(:)');
end
end

function [objectiveName, scoreMat] = getPolicyScoreMatrix(method, mats)
switch string(method)
    case "investment_value_ilp"
        objectiveName = "investment_value";
        scoreMat = mats.investmentValue;
    case "integrated_pi_ilp"
        objectiveName = "integrated_pi";
        scoreMat = mats.integratedPi;
    otherwise
        error("지원하지 않는 정책 제약 시뮬레이션 방법입니다: %s", method);
end
end

function [choice, solverInfo] = runPolicyIlp(scoreMat, mats, constraints, candidateAssetTypes, assetTypes)
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
        "message", "선택 가능한 양수 점수 변수가 없어 ILP를 건너뜀", "objective", 0);
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

% 설비유형별·연도별 최소 교체대수 하한:
% sum x_type,year >= min_count(type,year)이므로
% intlinprog 형식에 맞춰 -sum x_type,year <= -min_count(type,year)로 둔다.
if ~isempty(constraints.minTypeCount)
    for t = 1:numel(assetTypes)
        for y = 1:nYears
            minCount = constraints.minTypeCount(t, y);
            if minCount > 0
                typeYearMask = (candidateAssetTypes(assetKeep) == assetTypes(t)) & (yearKeep == y);
                coeff = double(typeYearMask)';
                A = [A; sparse(1, 1:nKeep, -coeff, 1, nKeep)]; %#ok<AGROW>
                b = [b; -minCount]; %#ok<AGROW>
            end
        end
    end
end

% 설비유형별·연도별 최소 투자예산 하한:
% sum cost*x_type,year >= min_budget(type,year)이므로
% -sum cost*x_type,year <= -min_budget(type,year)로 둔다.
if ~isempty(constraints.minTypeBudget)
    for t = 1:numel(assetTypes)
        for y = 1:nYears
            minBudget = constraints.minTypeBudget(t, y);
            if minBudget > 0
                typeYearMask = (candidateAssetTypes(assetKeep) == assetTypes(t)) & (yearKeep == y);
                coeff = costKeep(:)' .* double(typeYearMask)';
                A = [A; sparse(1, 1:nKeep, -coeff, 1, nKeep)]; %#ok<AGROW>
                b = [b; -minBudget]; %#ok<AGROW>
            end
        end
    end
end

lb = zeros(nKeep, 1);
ub = ones(nKeep, 1);
intcon = 1:nKeep;
options = buildIlpOptions();

fprintf("  [ILP] 유효 변수 %d / 전체 변수 %d, 제약식 %d개\n", nKeep, nVars, size(A, 1));

% 정책 하한이 있는 경우 실현가능해 탐색 자체가 오래 걸릴 수 있으므로,
% 설비유형별 최소 조건을 먼저 채우는 그리디 초기해를 제공한다.
greedyChoice = runPolicyGreedy(scoreMat, mats, constraints, candidateAssetTypes, assetTypes);
x0Full = choiceToBinaryVector(greedyChoice, n, nYears);
x0 = x0Full(validIdx);
greedyFeasible = ~isempty(x0) && all(A * x0 <= b + 1e-6);
if ~greedyFeasible
    x0 = [];
end

try
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
        if greedyFeasible
            choice = greedyChoice;
        else
            choice = zeros(n, 1, "int16");
        end
    else
        xFull = zeros(nVars, 1);
        xFull(validIdx) = x;
        xMat = reshape(xFull, n, nYears);
        [maxVal, yearIdx] = max(xMat, [], 2);
        choice = int16(yearIdx .* (maxVal >= 0.5));
        if sum(choice > 0) == 0 && greedyFeasible
            choice = greedyChoice;
        end
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
    if choiceScore(choice, scoreMat) > 0 && (isempty(fval) || ~isfinite(fval) || objectiveValue == 0)
        objectiveValue = choiceScore(choice, scoreMat);
    end
    solverInfo = struct("solver", "intlinprog", "exitflag", exitflag, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, outMessage), ...
        "objective", objectiveValue);
catch ME
    if greedyFeasible
        choice = greedyChoice;
        solverName = "intlinprog_failed_policy_greedy_fallback";
        objectiveValue = choiceScore(choice, scoreMat);
    else
        choice = zeros(n, 1, "int16");
        solverName = "intlinprog_failed";
        objectiveValue = NaN;
    end
    solverInfo = struct("solver", solverName, "exitflag", -999, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, string(ME.message)), ...
        "objective", objectiveValue);
end
end

function choice = runPolicyGreedy(scoreMat, mats, constraints, candidateAssetTypes, assetTypes)
[n, nYears] = size(scoreMat);
choice = zeros(n, 1, "int16");
budgetLeft = constraints.budgets(:)';
capacityLeft = constraints.capacities(:)';

% 1단계: 설비유형별·연도별 최소 교체대수·최소 예산을 먼저 충족한다.
for y = 1:nYears
    for t = 1:numel(assetTypes)
        while true
            typeYearSelected = find(choice == y & candidateAssetTypes == assetTypes(t));
            typeYearCost = selectedCost(choice, mats, typeYearSelected);
            countNeed = ~isempty(constraints.minTypeCount) && ...
                numel(typeYearSelected) < constraints.minTypeCount(t, y);
            budgetNeed = ~isempty(constraints.minTypeBudget) && ...
                typeYearCost + 1e-6 < constraints.minTypeBudget(t, y);
            if ~(countNeed || budgetNeed)
                break;
            end

            [bestAsset, bestYear] = bestFeasibleOption(scoreMat, mats, choice, budgetLeft, capacityLeft, ...
                candidateAssetTypes, assetTypes(t), y);
            if bestAsset == 0
                break;
            end
            choice(bestAsset) = int16(bestYear);
            budgetLeft(bestYear) = budgetLeft(bestYear) - mats.cost(bestAsset, bestYear);
            capacityLeft(bestYear) = capacityLeft(bestYear) - 1;
        end
    end
end

% 2단계: 남은 예산·물량 안에서 통합 PI가 큰 설비-연도 조합을 추가한다.
pairs = [];
for y = 1:nYears
    for i = 1:n
        if isfinite(scoreMat(i, y)) && scoreMat(i, y) > 0 && isfinite(mats.cost(i, y)) && mats.cost(i, y) > 0
            pairs(end + 1, :) = [i, y, scoreMat(i, y)]; %#ok<AGROW>
        end
    end
end
if isempty(pairs)
    return;
end
[~, order] = sort(pairs(:, 3), "descend");
pairs = pairs(order, :);
for k = 1:size(pairs, 1)
    i = pairs(k, 1);
    y = pairs(k, 2);
    if choice(i) > 0 || capacityLeft(y) <= 0
        continue;
    end
    if mats.cost(i, y) <= budgetLeft(y)
        choice(i) = int16(y);
        budgetLeft(y) = budgetLeft(y) - mats.cost(i, y);
        capacityLeft(y) = capacityLeft(y) - 1;
    end
end
end

function [bestAsset, bestYear] = bestFeasibleOption(scoreMat, mats, choice, budgetLeft, capacityLeft, candidateAssetTypes, targetType, targetYear)
[n, nYears] = size(scoreMat);
if nargin < 8
    targetYear = 0;
end
bestAsset = 0;
bestYear = 0;
bestScore = -Inf;
for i = 1:n
    if choice(i) > 0 || candidateAssetTypes(i) ~= targetType
        continue;
    end
    for y = 1:nYears
        if targetYear > 0 && y ~= targetYear
            continue;
        end
        if capacityLeft(y) <= 0 || mats.cost(i, y) > budgetLeft(y)
            continue;
        end
        score = scoreMat(i, y);
        if isfinite(score) && score > bestScore
            bestScore = score;
            bestAsset = i;
            bestYear = y;
        end
    end
end
end

function cost = selectedCost(choice, mats, selectedIdx)
cost = 0;
for k = 1:numel(selectedIdx)
    i = selectedIdx(k);
    y = double(choice(i));
    if y > 0
        cost = cost + mats.cost(i, y);
    end
end
end

function xFull = choiceToBinaryVector(choice, n, nYears)
xFull = zeros(n * nYears, 1);
for i = 1:n
    y = double(choice(i));
    if y > 0
        xFull((y - 1) * n + i) = 1;
    end
end
end

function options = buildIlpOptions()
displayMode = strtrim(string(getenv("POLICY_ILP_DISPLAY")));
if strlength(displayMode) == 0
    displayMode = "iter";
end
options = optimoptions("intlinprog", "Display", char(displayMode));

relGap = str2double(string(getenv("POLICY_ILP_REL_GAP")));
if isnan(relGap)
    relGap = 1e-3;
end
try
    options.RelativeGapTolerance = relGap;
catch ME
    warning("policy:optionIgnored", "ILP 옵션 RelativeGapTolerance 설정 실패: %s", ME.message);
end

maxTime = str2double(string(getenv("POLICY_ILP_MAX_TIME")));
if isnan(maxTime)
    maxTime = 300;
end
if maxTime > 0
    try
        options.MaxTime = maxTime;
    catch ME
        warning("policy:optionIgnored", "ILP 옵션 MaxTime 설정 실패: %s", ME.message);
    end
end

try
    options.Heuristics = "advanced";
catch
end
try
    options.CutGeneration = "advanced";
catch
end
end

function [annual, total, typeSummary, constraintCheck, selectedAssets] = summarizePolicyChoice( ...
    pof, choice, scenario, method, objectiveName, constraints, years, assetTypes, assetLabels)
annualRows = {};
typeRows = {};
selectedRows = {};

for y = 1:numel(years)
    year = years(y);
    selected = find(choice == y);
    cumulative = find(choice > 0 & choice <= y);

    cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
    riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
    investmentValue = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
    saidiReduction = sum(pof.(sprintf("saidi_%d_min", year))(selected), "omitnan");
    expectedFailures = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
    localPi = sum(pof.(sprintf("local_pi_%d", year))(selected), "omitnan");
    integratedPi = sum(pof.(sprintf("integrated_pi_%d", year))(selected), "omitnan");

    removedRisk = sum(pof.(sprintf("risk_%d_kkrw", year))(cumulative), "omitnan");
    removedSaidi = sum(pof.(sprintf("saidi_%d_min", year))(cumulative), "omitnan");
    riskAfter = constraints.baselineRisk(y) - removedRisk;
    saidiAfter = constraints.baselineSaidi(y) - removedSaidi;

    annualRows(end + 1, :) = {scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
        method, objectiveName, ...
        year, numel(selected), cost, riskReduction, investmentValue, saidiReduction, ...
        expectedFailures, localPi, integratedPi, ...
        constraints.baselineRisk(y), removedRisk, riskAfter, ...
        constraints.baselineSaidi(y), removedSaidi, saidiAfter, ...
        constraints.budgets(y), constraints.capacities(y), ...
        safeDivide(cost, constraints.budgets(y)), safeDivide(numel(selected), constraints.capacities(y))}; %#ok<AGROW>

    for r = 1:numel(selected)
        idx = selected(r);
        selectedRows(end + 1, :) = {scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
            method, objectiveName, ...
            string(pof.asset_id(idx)), string(pof.asset_type(idx)), string(pof.asset_type_label(idx)), year, ...
            pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
            pof.(sprintf("risk_%d_kkrw", year))(idx), ...
            pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
            pof.(sprintf("investment_value_%d_kkrw", year))(idx), ...
            pof.(sprintf("saidi_%d_min", year))(idx), ...
            pof.(sprintf("local_pi_%d", year))(idx), ...
            pof.(sprintf("integrated_pi_%d", year))(idx), ...
            pof.w_type_alpha_0_5(idx)}; %#ok<AGROW>
    end
end

annual = cell2table(annualRows, 'VariableNames', {'scenario_id', 'scenario_name', 'scenario_group', ...
    'method', 'objective', ...
    'year', 'selected_count', 'investment_cost_kkrw', 'risk_reduction_econ_kkrw', ...
    'investment_value_kkrw', 'saidi_reduction_min', 'expected_failures', ...
    'local_pi', 'integrated_pi', 'baseline_risk_kkrw', 'risk_removed_cumulative_kkrw', ...
    'risk_after_cumulative_kkrw', 'baseline_saidi_min', 'saidi_removed_cumulative_min', ...
    'saidi_after_cumulative_min', 'budget_limit_kkrw', 'capacity_limit', ...
    'budget_usage_ratio', 'capacity_usage_ratio'});

selectedVarNames = {'scenario_id', 'scenario_name', 'scenario_group', ...
    'method', 'objective', ...
    'asset_id', 'asset_type', 'asset_type_label', 'replacement_year', ...
    'replacement_cost_kkrw', 'risk_kkrw', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'saidi_min', 'local_pi', 'integrated_pi', ...
    'type_weight_alpha_0_5'};
if isempty(selectedRows)
    selectedAssets = cell2table(cell(0, numel(selectedVarNames)), 'VariableNames', selectedVarNames);
else
    selectedAssets = cell2table(selectedRows, 'VariableNames', selectedVarNames);
end

for t = 1:numel(assetTypes)
    idx = find(string(pof.asset_type) == assetTypes(t) & choice > 0);
    typeCost = 0;
    typeRiskReduction = 0;
    typeInvestmentValue = 0;
    typeSaidi = 0;
    typeLocalPi = 0;
    typeIntegratedPi = 0;
    selectedByYear = zeros(1, numel(years));
    costByYear = zeros(1, numel(years));
    for r = 1:numel(idx)
        assetIdx = idx(r);
        y = double(choice(assetIdx));
        year = years(y);
        selectedByYear(y) = selectedByYear(y) + 1;
        costByYear(y) = costByYear(y) + pof.(sprintf("replacement_cost_%d_kkrw", year))(assetIdx);
        typeCost = typeCost + pof.(sprintf("replacement_cost_%d_kkrw", year))(assetIdx);
        typeRiskReduction = typeRiskReduction + pof.(sprintf("risk_reduction_%d_kkrw", year))(assetIdx);
        typeInvestmentValue = typeInvestmentValue + pof.(sprintf("investment_value_%d_kkrw", year))(assetIdx);
        typeSaidi = typeSaidi + pof.(sprintf("saidi_%d_min", year))(assetIdx);
        typeLocalPi = typeLocalPi + pof.(sprintf("local_pi_%d", year))(assetIdx);
        typeIntegratedPi = typeIntegratedPi + pof.(sprintf("integrated_pi_%d", year))(assetIdx);
    end
    minCountTotal = sum(scenario.minTypeCount(t, :), "omitnan");
    minBudgetTotal = sum(scenario.minTypeBudget(t, :), "omitnan");
    minCountOk = all(selectedByYear + 1e-6 >= scenario.minTypeCount(t, :));
    minBudgetOk = all(costByYear + 1e-6 >= scenario.minTypeBudget(t, :));
    typeRows(end + 1, :) = {scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
        method, objectiveName, ...
        assetTypes(t), assetLabels(t), numel(idx), typeCost, typeRiskReduction, ...
        typeInvestmentValue, typeSaidi, typeLocalPi, typeIntegratedPi, ...
        minCountTotal, minBudgetTotal, minCountOk, minBudgetOk}; %#ok<AGROW>
end

typeSummary = cell2table(typeRows, 'VariableNames', {'scenario_id', 'scenario_name', ...
    'scenario_group', 'method', 'objective', 'asset_type', 'asset_type_label', 'selected_count', ...
    'investment_cost_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
    'saidi_reduction_min', 'local_pi', 'integrated_pi', ...
    'min_selected_count', 'min_investment_budget_kkrw', ...
    'min_count_ok', 'min_budget_ok'});

lastAnnual = annual(end, :);
total = table( ...
    scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
    method, objectiveName, ...
    sum(annual.selected_count), sum(annual.investment_cost_kkrw), ...
    sum(annual.risk_reduction_econ_kkrw), sum(annual.investment_value_kkrw), ...
    sum(annual.saidi_reduction_min), sum(annual.expected_failures), ...
    sum(annual.local_pi), sum(annual.integrated_pi), ...
    lastAnnual.risk_removed_cumulative_kkrw, lastAnnual.risk_after_cumulative_kkrw, ...
    lastAnnual.saidi_removed_cumulative_min, lastAnnual.saidi_after_cumulative_min, ...
    sum(constraints.budgets), sum(constraints.capacities), ...
    safeDivide(sum(annual.investment_cost_kkrw), sum(constraints.budgets)), ...
    safeDivide(sum(annual.selected_count), sum(constraints.capacities)), ...
    all(typeSummary.min_count_ok), all(typeSummary.min_budget_ok), ...
    'VariableNames', {'scenario_id', 'scenario_name', 'scenario_group', ...
    'method', 'objective', ...
    'selected_count', 'investment_cost_kkrw', 'risk_reduction_econ_kkrw', ...
    'investment_value_kkrw', 'saidi_reduction_min', 'expected_failures', ...
    'local_pi', 'integrated_pi', 'risk_removed_2030_kkrw', ...
    'risk_after_2030_kkrw', 'saidi_removed_2030_min', 'saidi_after_2030_min', ...
    'budget_limit_total_kkrw', 'capacity_limit_total', 'budget_usage_ratio', ...
    'capacity_usage_ratio', 'type_min_count_ok', 'type_min_budget_ok'});

annualBudgetOk = all(annual.investment_cost_kkrw <= annual.budget_limit_kkrw + 1e-6);
annualCapacityOk = all(annual.selected_count <= annual.capacity_limit + 1e-6);
constraintCheck = table(scenario.scenario_id, scenario.scenario_name, scenario.scenario_group, ...
    method, objectiveName, ...
    annualBudgetOk, annualCapacityOk, all(typeSummary.min_count_ok), all(typeSummary.min_budget_ok), ...
    'VariableNames', {'scenario_id', 'scenario_name', 'scenario_group', ...
    'method', 'objective', ...
    'annual_budget_ok', 'annual_capacity_ok', 'type_min_count_ok', 'type_min_budget_ok'});
end

function tradeoff = buildTradeoffSummary(totalSummary)
tradeoff = totalSummary;
metrics = ["selected_count", "investment_cost_kkrw", "risk_reduction_econ_kkrw", ...
    "investment_value_kkrw", "saidi_reduction_min", "local_pi", "integrated_pi", ...
    "risk_removed_2030_kkrw", "saidi_removed_2030_min"];
for m = 1:numel(metrics)
    metric = metrics(m);
    newCol = [char(metric) '_vs_baseline_pct'];
    tradeoff.(newCol) = NaN(height(tradeoff), 1);
    methods = unique(string(tradeoff.method), "stable");
    for k = 1:numel(methods)
        method = methods(k);
        methodRows = string(tradeoff.method) == method;
        baseline = tradeoff(methodRows & string(tradeoff.scenario_id) == "baseline_budget_only", :);
        if isempty(baseline)
            continue;
        end
        baseValue = baseline.(metric)(1);
        tradeoff.(newCol)(methodRows) = ...
            (tradeoff.(metric)(methodRows) - baseValue) ./ max(abs(baseValue), eps) * 100;
    end
end
end

function value = choiceScore(choice, scoreMat)
value = 0;
for i = 1:numel(choice)
    y = double(choice(i));
    if y > 0
        value = value + double(scoreMat(i, y));
    end
end
end

function value = safeDivide(numerator, denominator)
if denominator == 0 || isnan(denominator)
    value = NaN;
else
    value = numerator ./ denominator;
end
end
