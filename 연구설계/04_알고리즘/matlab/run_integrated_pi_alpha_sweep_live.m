%% 통합 PI α 민감도 분석
% 목적:
%   기존 본문 시뮬레이션과 동일한 후보군·예산·물량·할인율 조건에서
%   통합 PI의 혼합비율 α만 변경하여 통합형 ILP 결과 변화를 확인한다.
%
% 실행:
%   run("연구설계/04_알고리즘/matlab/run_integrated_pi_alpha_sweep_live.m")
%
% 선택 환경변수:
%   ALPHA_SWEEP_VALUES : α 목록. 예) "0,0.3,0.5,0.7,1"
%   ALPHA_OUTPUT_TAG   : 결과 폴더명 뒤에 붙일 태그

clear; clc;

%% 1. 경로 및 기준 조건
scriptDir = fileparts(mfilename("fullpath"));
if strlength(scriptDir) == 0
    scriptDir = pwd;
end
researchDir = detectResearchDir(scriptDir);

dataDir = fullfile(researchDir, "02_입력데이터");
piDir = fullfile(researchDir, "05_PI_산출결과");
resultRoot = fullfile(researchDir, "06_시뮬레이션결과", "알파민감도_통합PI");

runStamp = char(string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
outputTag = strtrim(string(getenv("ALPHA_OUTPUT_TAG")));
if strlength(outputTag) > 0
    runName = "integrated_pi_alpha_sweep_" + outputTag + "_" + string(runStamp);
else
    runName = "integrated_pi_alpha_sweep_" + string(runStamp);
end
runDir = fullfile(resultRoot, char(runName));
figureDir = fullfile(runDir, "figures");
selectedDir = fullfile(runDir, "selected_assets");
mkdir(runDir); mkdir(figureDir); mkdir(selectedDir);

diary(fullfile(runDir, "integrated_pi_alpha_sweep.log"));
diary on;
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

years = [2026 2027 2028 2029 2030];
assetTypes = ["pole_transformer", "ground_transformer", "overhead_switch", ...
    "underground_switch", "overhead_line", "underground_cable"];
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", ...
    "지중개폐기", "가공배전선로", "지중케이블"];

% 기존 본문 시뮬레이션과 동일한 기준 조건
budgetRate = 0.04;
capacityRate = 0.05;
discountRate = 0.05;
candidateQuantile = 0.70;   % 상위 30% 후보군
% integrated_pi_matlab.xlsx의 type_weights 시트에 저장된 기준 α 컬럼과
% 본문 기준 시나리오(α=0.5)가 정확히 일치하도록 기본값을 설정한다.
alphaValues = readVectorEnv("ALPHA_SWEEP_VALUES", [0 0.3 0.5 0.7 1.0]);
alphaValues = unique(max(0, min(1, alphaValues(:)')), "stable");

fprintf("=== 통합 PI α 민감도 분석 시작 ===\n");
fprintf("researchDir: %s\n", researchDir);
fprintf("runDir: %s\n", runDir);
fprintf("α values: %s\n", strjoin(string(alphaValues), ", "));
fprintf("기준 조건: 예산 %.1f%%, 물량 %.1f%%, 할인율 %.1f%%, 후보군 상위 %.0f%% 합집합\n", ...
    budgetRate * 100, capacityRate * 100, discountRate * 100, (1 - candidateQuantile) * 100);

%% 2. 입력 데이터 로드
pofFile = fullfile(dataDir, "pof_5yr_output.xlsx");
localPiFile = fullfile(piDir, "local_pi_matlab.xlsx");
integratedPiFile = fullfile(piDir, "integrated_pi_matlab.xlsx");

if ~isfile(pofFile)
    error("PoF 입력 파일을 찾을 수 없습니다: %s", pofFile);
end
if ~isfile(localPiFile)
    error("설비 단위 PI 입력 파일을 찾을 수 없습니다: %s", localPiFile);
end
if ~isfile(integratedPiFile)
    error("통합 PI 입력 파일을 찾을 수 없습니다: %s", integratedPiFile);
end

pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
localPi = readtable(localPiFile, "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
integratedPi = readtable(integratedPiFile, "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");
typeWeights = readtable(integratedPiFile, "Sheet", "type_weights", "VariableNamingRule", "preserve");

if height(pof) ~= height(localPi) || any(string(pof.asset_id) ~= string(localPi.asset_id))
    error("PoF 입력과 설비 단위 PI 파일의 asset_id가 일치하지 않습니다.");
end
if height(pof) ~= height(integratedPi) || any(string(pof.asset_id) ~= string(integratedPi.asset_id))
    error("PoF 입력과 통합 PI 파일의 asset_id가 일치하지 않습니다.");
end

pof.asset_type = string(pof.asset_type);
pof.asset_type_label = mapAssetLabels(pof.asset_type, assetTypes, assetLabels);
pof.w_type_expert = integratedPi.w_type_expert;

for y = 1:numel(years)
    year = years(y);
    pof.(sprintf("local_pi_%d", year)) = localPi.(sprintf("local_pi_ahp_%d", year));
end

candidateMask = buildTypeCandidateMask(pof, assetTypes, candidateQuantile);
candidateIdx = find(candidateMask);
constraints = buildConstraints(pof, (1:height(pof))', years, budgetRate, capacityRate, discountRate);

fprintf("전체 설비 수: %d, 후보 설비 수: %d\n", height(pof), numel(candidateIdx));

%% 3. α별 통합형 ILP 수행
configTable = table(string(runStamp), budgetRate, capacityRate, discountRate, candidateQuantile, ...
    string(strjoin(string(alphaValues), ",")), numel(candidateIdx), sum(constraints.budgets), ...
    sum(constraints.capacities), ...
    'VariableNames', {'run_stamp', 'budget_rate', 'capacity_rate', 'discount_rate', ...
    'candidate_quantile', 'alpha_values', 'candidate_count', ...
    'five_year_budget_kkrw', 'five_year_capacity'});

candidateSummary = buildCandidateSummary(pof, assetTypes, assetLabels, candidateMask);
alphaWeightRows = {};
annualParts = {};
totalParts = {};
typeParts = {};
selectedParts = {};
solverRows = {};

for a = 1:numel(alphaValues)
    alpha = alphaValues(a);
    fprintf("\n[α=%.3f] 통합 PI 재계산 및 ILP 시작\n", alpha);

    weightMap = buildTypeWeightMap(typeWeights, assetTypes, alpha);
    pofAlpha = applyAlphaIntegratedPi(pof, assetTypes, weightMap, years);
    mats = buildMatrices(pofAlpha, candidateIdx, years);

    [choiceLocal, solverInfo] = runIntegratedIlp(mats.integratedPi, mats, constraints);
    if ~solverInfo.feasible
        warning("α=%.3f에서 ILP가 정상 최적해를 찾지 못해 그리디 보조해를 사용합니다.", alpha);
        choiceLocal = runIntegratedGreedy(mats.integratedPi, mats, constraints);
    end

    choiceGlobal = zeros(height(pof), 1);
    choiceGlobal(candidateIdx) = choiceLocal;
    methodName = sprintf("integrated_ilp_alpha_%.2f", alpha);
    methodName = strrep(methodName, ".", "_");

    [annual, total, selected, typeSummary] = summarizeChoice( ...
        pofAlpha, choiceGlobal, assetTypes, assetLabels, years, constraints, alpha, methodName);

    annualParts{end + 1} = annual; %#ok<SAGROW>
    totalParts{end + 1} = total; %#ok<SAGROW>
    typeParts{end + 1} = typeSummary; %#ok<SAGROW>
    selectedParts{end + 1} = selected; %#ok<SAGROW>

    for t = 1:numel(assetTypes)
        alphaWeightRows(end + 1, :) = {alpha, assetTypes(t), assetLabels(t), ...
            weightMap.expert(t), weightMap.cost(t), weightMap.applied(t)}; %#ok<SAGROW>
    end

    solverRows(end + 1, :) = {alpha, methodName, "integrated_pi", string(solverInfo.solver), ...
        solverInfo.exitflag, string(solverInfo.message), solverInfo.objective, ...
        numel(candidateIdx), sum(choiceGlobal > 0), solverInfo.elapsed_seconds}; %#ok<SAGROW>

    fprintf("[α=%.3f] 선택 %d대, 통합 PI %.2f, 투자가치 %.2f억 원, 투자비용 %.2f억 원\n", ...
        alpha, total.selected_count(1), total.integrated_pi(1), ...
        total.investment_value_kkrw(1) / 100000, total.investment_cost_kkrw(1) / 100000);
end

alphaWeightsOut = cell2table(alphaWeightRows, 'VariableNames', ...
    {'alpha', 'asset_type', 'asset_type_label', 'w_type_expert', 'w_type_cost', 'w_type_applied'});
annualOut = vertcat(annualParts{:});
totalOut = vertcat(totalParts{:});
typeOut = vertcat(typeParts{:});
selectedOut = vertcat(selectedParts{:});
solverOut = cell2table(solverRows, 'VariableNames', ...
    {'alpha', 'method', 'objective', 'solver', 'exitflag', 'message', 'objective_value', ...
    'candidate_count', 'selected_count', 'elapsed_seconds'});

%% 4. 결과 저장
resultFile = fullfile(runDir, "integrated_pi_alpha_sweep_results.xlsx");
writetable(configTable, resultFile, "Sheet", "00_run_config");
writetable(candidateSummary, resultFile, "Sheet", "01_candidate_summary");
writetable(alphaWeightsOut, resultFile, "Sheet", "02_alpha_weights");
writetable(totalOut, resultFile, "Sheet", "03_alpha_total");
writetable(annualOut, resultFile, "Sheet", "04_alpha_annual");
writetable(typeOut, resultFile, "Sheet", "05_alpha_type");
writetable(selectedOut, resultFile, "Sheet", "06_selected_assets");
writetable(solverOut, resultFile, "Sheet", "07_solver_status");

writetable(selectedOut, fullfile(selectedDir, "alpha_sweep_selected_assets.csv"));

saveAlphaFigures(figureDir, totalOut, typeOut, assetTypes, assetLabels);

fprintf("\n=== 통합 PI α 민감도 분석 완료 ===\n");
fprintf("결과 파일: %s\n", resultFile);
fprintf("그림 폴더: %s\n", figureDir);

%% 지역 함수
function researchDir = detectResearchDir(startDir)
current = string(startDir);
for k = 1:8
    if isfolder(fullfile(current, "02_입력데이터")) && isfolder(fullfile(current, "05_PI_산출결과"))
        researchDir = char(current);
        return;
    end
    parent = string(fileparts(current));
    if parent == current
        break;
    end
    current = parent;
end
error("연구설계 폴더를 찾지 못했습니다. 현재 경로: %s", startDir);
end

function values = readVectorEnv(name, defaultValues)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    values = defaultValues;
    return;
end
tokens = strtrim(split(raw, [",", ";", " "]));
tokens(tokens == "") = [];
values = str2double(tokens)';
values = values(isfinite(values));
if isempty(values)
    values = defaultValues;
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
    riskValues = pof.risk_2026_kkrw(idx);
    valueValues = pof.investment_value_2026_kkrw(idx);
    riskValuesValid = riskValues(isfinite(riskValues));
    valueValuesValid = valueValues(isfinite(valueValues));
    if isempty(riskValuesValid) || isempty(valueValuesValid)
        continue;
    end
    riskThreshold = quantile(riskValuesValid, candidateQuantile);
    valueThreshold = quantile(valueValuesValid, candidateQuantile);
    candidateMask(idx) = riskValues >= riskThreshold | valueValues >= valueThreshold;
end
end

function constraints = buildConstraints(pof, assetIdx, years, budgetRate, capacityRate, discountRate)
assetValue = sum(pof.replacement_cost_2026_kkrw(assetIdx), "omitnan");
baseBudget = assetValue * budgetRate;
budgets = zeros(1, numel(years));
for y = 1:numel(years)
    budgets(y) = baseBudget / ((1 + discountRate) ^ (y - 1));
end
constraints.budgets = budgets;
constraints.capacities = repmat(max(1, ceil(numel(assetIdx) * capacityRate)), 1, numel(years));
end

function candidateSummary = buildCandidateSummary(pof, assetTypes, assetLabels, candidateMask)
rows = {};
for t = 1:numel(assetTypes)
    typeIdx = find(string(pof.asset_type) == assetTypes(t));
    candIdx = typeIdx(candidateMask(typeIdx));
    rows(end + 1, :) = {assetTypes(t), assetLabels(t), numel(typeIdx), numel(candIdx), ...
        safeDivide(numel(candIdx), numel(typeIdx)), ...
        sum(pof.replacement_cost_2026_kkrw(typeIdx), "omitnan"), ...
        sum(pof.replacement_cost_2026_kkrw(candIdx), "omitnan")}; %#ok<AGROW>
end
candidateSummary = cell2table(rows, 'VariableNames', {'asset_type', 'asset_type_label', ...
    'asset_count', 'candidate_count', 'candidate_ratio', ...
    'asset_value_2026_kkrw', 'candidate_asset_value_2026_kkrw'});
end

function weightMap = buildTypeWeightMap(typeWeights, assetTypes, alpha)
typeNames = string(typeWeights.asset_type);
expert = zeros(numel(assetTypes), 1);
avgCost = zeros(numel(assetTypes), 1);
costFromSheet = zeros(numel(assetTypes), 1);
appliedFromSheet = nan(numel(assetTypes), 1);
alphaColumn = findAlphaWeightColumn(typeWeights, alpha);
hasCostWeight = ismember("w_type_alpha_1_0", string(typeWeights.Properties.VariableNames));
for t = 1:numel(assetTypes)
    idx = find(typeNames == assetTypes(t), 1);
    if isempty(idx)
        error("type_weights 시트에서 설비유형을 찾지 못했습니다: %s", assetTypes(t));
    end
    expert(t) = typeWeights.w_type_expert(idx);
    avgCost(t) = typeWeights.avg_cost_10k_krw(idx);
    if hasCostWeight
        costFromSheet(t) = typeWeights.w_type_alpha_1_0(idx);
    end
    if strlength(alphaColumn) > 0
        appliedFromSheet(t) = typeWeights.(alphaColumn)(idx);
    end
end
expert = expert / sum(expert, "omitnan");
if hasCostWeight && all(isfinite(costFromSheet)) && sum(costFromSheet, "omitnan") > 0
    costWeight = costFromSheet / sum(costFromSheet, "omitnan");
else
    % 기존 시트에 비용 보정 가중치가 없을 경우에만 단가 역수로 보조 계산한다.
    costRaw = 1 ./ avgCost;
    costWeight = costRaw / sum(costRaw, "omitnan");
end

% 기준 입력파일에 해당 α의 적용 가중치가 이미 저장되어 있으면 그 값을 우선 사용한다.
% 이렇게 해야 α=0.5 결과가 본문 기준 통합형 ILP와 동일한 가중치 체계를 사용한다.
if all(isfinite(appliedFromSheet)) && sum(appliedFromSheet, "omitnan") > 0
    applied = appliedFromSheet;
else
    applied = (1 - alpha) .* expert + alpha .* costWeight;
end
applied = applied / sum(applied, "omitnan");

weightMap.assetTypes = assetTypes;
weightMap.expert = expert;
weightMap.cost = costWeight;
weightMap.applied = applied;
end

function alphaColumn = findAlphaWeightColumn(typeWeights, alpha)
alphaColumn = "";
columns = string(typeWeights.Properties.VariableNames);
for c = 1:numel(columns)
    token = regexp(columns(c), "^w_type_alpha_(\d+)_(\d+)$", "tokens", "once");
    if isempty(token)
        continue;
    end
    value = str2double(token{1}) + str2double("0." + token{2});
    if abs(value - alpha) < 1e-9
        alphaColumn = columns(c);
        return;
    end
end
end

function pofAlpha = applyAlphaIntegratedPi(pof, assetTypes, weightMap, years)
pofAlpha = pof;
pofAlpha.w_type_alpha = zeros(height(pofAlpha), 1);
for t = 1:numel(assetTypes)
    idx = string(pofAlpha.asset_type) == assetTypes(t);
    pofAlpha.w_type_alpha(idx) = weightMap.applied(t);
end
for y = 1:numel(years)
    year = years(y);
    localField = sprintf("local_pi_%d", year);
    intField = sprintf("integrated_pi_%d", year);
    pofAlpha.(intField) = pofAlpha.(localField) .* pofAlpha.w_type_alpha;
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

function [choice, solverInfo] = runIntegratedIlp(scoreMat, mats, constraints)
timerStart = tic;
[n, nYears] = size(scoreMat);
[assetGrid, yearGrid] = ndgrid((1:n)', 1:nYears);
assetVec = assetGrid(:);
yearVec = yearGrid(:);
score = scoreMat(:);
cost = mats.cost(:);

valid = isfinite(score) & score > 0 & isfinite(cost) & cost > 0;
for y = 1:nYears
    valid(yearVec == y & cost > constraints.budgets(y)) = false;
end

choice = zeros(n, 1);
if ~any(valid)
    solverInfo = struct("solver", "intlinprog_skipped", "exitflag", 0, ...
        "message", "유효한 의사결정변수가 없습니다.", "objective", 0, ...
        "elapsed_seconds", toc(timerStart), "feasible", false);
    return;
end

assetKeep = assetVec(valid);
yearKeep = yearVec(valid);
scoreKeep = score(valid);
costKeep = cost(valid);
nKeep = numel(scoreKeep);
colIdx = (1:nKeep)';

Aasset = sparse(assetKeep, colIdx, 1, n, nKeep);
Abudget = sparse(yearKeep, colIdx, costKeep, nYears, nKeep);
Acapacity = sparse(yearKeep, colIdx, 1, nYears, nKeep);
A = [Aasset; Abudget; Acapacity];
b = [ones(n, 1); constraints.budgets(:); constraints.capacities(:)];

f = -scoreKeep;
intcon = 1:nKeep;
lb = zeros(nKeep, 1);
ub = ones(nKeep, 1);
options = optimoptions("intlinprog", "Display", "off");

try
    [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
    if exitflag > 0
        selectedCols = find(x > 0.5);
        choice(assetKeep(selectedCols)) = yearKeep(selectedCols);
        message = string(output.message);
        feasible = true;
    else
        fval = NaN;
        message = string(output.message);
        feasible = false;
    end
catch ME
    exitflag = -999;
    fval = NaN;
    message = string(ME.message);
    feasible = false;
end

solverInfo = struct("solver", "intlinprog", "exitflag", exitflag, ...
    "message", message, "objective", -fval, ...
    "elapsed_seconds", toc(timerStart), "feasible", feasible);
end

function choice = runIntegratedGreedy(scoreMat, mats, constraints)
[n, nYears] = size(scoreMat);
choice = zeros(n, 1);
budgetLeft = constraints.budgets(:)';
capacityLeft = constraints.capacities(:)';
[assetGrid, yearGrid] = ndgrid((1:n)', 1:nYears);
score = scoreMat(:);
cost = mats.cost(:);
assetVec = assetGrid(:);
yearVec = yearGrid(:);
valid = isfinite(score) & score > 0 & isfinite(cost) & cost > 0;
[~, order] = sort(score(valid), "descend");
validIdx = find(valid);
for k = 1:numel(order)
    linearIdx = validIdx(order(k));
    i = assetVec(linearIdx);
    y = yearVec(linearIdx);
    if choice(i) > 0
        continue;
    end
    if capacityLeft(y) <= 0 || cost(linearIdx) > budgetLeft(y)
        continue;
    end
    choice(i) = y;
    budgetLeft(y) = budgetLeft(y) - cost(linearIdx);
    capacityLeft(y) = capacityLeft(y) - 1;
end
end

function [annual, total, selected, typeSummary] = summarizeChoice( ...
    pof, choice, assetTypes, assetLabels, years, constraints, alpha, methodName)

annualRows = {};
selectedRows = {};
nYears = numel(years);

for y = 1:nYears
    year = years(y);
    selectedThisYear = find(choice == y);
    selectedCumulative = find(choice > 0 & choice <= y);

    cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selectedThisYear), "omitnan");
    riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selectedThisYear), "omitnan");
    investmentValue = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selectedThisYear), "omitnan");
    saidiReduction = sum(pof.(sprintf("saidi_%d_min", year))(selectedThisYear), "omitnan");
    localPi = sum(pof.(sprintf("local_pi_%d", year))(selectedThisYear), "omitnan");
    integratedPi = sum(pof.(sprintf("integrated_pi_%d", year))(selectedThisYear), "omitnan");

    baselineRisk = sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan");
    baselineSaidi = sum(pof.(sprintf("saidi_%d_min", year)), "omitnan");
    riskRemovedCumulative = sum(pof.(sprintf("risk_%d_kkrw", year))(selectedCumulative), "omitnan");
    saidiRemovedCumulative = sum(pof.(sprintf("saidi_%d_min", year))(selectedCumulative), "omitnan");
    riskAfter = baselineRisk - riskRemovedCumulative;
    saidiAfter = baselineSaidi - saidiRemovedCumulative;

    annualRows(end + 1, :) = {alpha, string(methodName), year, numel(selectedThisYear), ...
        cost, riskReduction, investmentValue, safeDivide(riskReduction, cost), ...
        saidiReduction, localPi, integratedPi, baselineRisk, riskAfter, ...
        baselineSaidi, saidiAfter, constraints.budgets(y), constraints.capacities(y), ...
        safeDivide(cost, constraints.budgets(y)), safeDivide(numel(selectedThisYear), constraints.capacities(y))}; %#ok<AGROW>

    for s = 1:numel(selectedThisYear)
        idx = selectedThisYear(s);
        selectedRows(end + 1, :) = {alpha, string(methodName), pof.asset_id(idx), ...
            string(pof.asset_type(idx)), string(pof.asset_type_label(idx)), year, ...
            pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
            pof.(sprintf("risk_%d_kkrw", year))(idx), ...
            pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
            pof.(sprintf("investment_value_%d_kkrw", year))(idx), ...
            pof.(sprintf("saidi_%d_min", year))(idx), ...
            pof.(sprintf("local_pi_%d", year))(idx), ...
            pof.(sprintf("integrated_pi_%d", year))(idx), ...
            pof.w_type_alpha(idx)}; %#ok<AGROW>
    end
end

annual = cell2table(annualRows, 'VariableNames', {'alpha', 'method', 'year', 'selected_count', ...
    'investment_cost_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
    'investment_efficiency', 'saidi_reduction_min', 'local_pi', 'integrated_pi', ...
    'baseline_risk_kkrw', 'risk_after_cumulative_kkrw', ...
    'baseline_saidi_min', 'saidi_after_cumulative_min', ...
    'budget_limit_kkrw', 'capacity_limit', 'budget_usage_ratio', 'capacity_usage_ratio'});

if isempty(selectedRows)
    selected = table();
else
    selected = cell2table(selectedRows, 'VariableNames', {'alpha', 'method', 'asset_id', ...
        'asset_type', 'asset_type_label', 'year', 'investment_cost_kkrw', ...
        'risk_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
        'saidi_min', 'local_pi', 'integrated_pi', 'type_weight_alpha'});
end

typeRows = {};
totalCost = sum(annual.investment_cost_kkrw, "omitnan");
totalSelected = sum(annual.selected_count, "omitnan");
for t = 1:numel(assetTypes)
    typeIdx = find(string(pof.asset_type) == assetTypes(t));
    selectedType = typeIdx(choice(typeIdx) > 0);
    typeCost = 0;
    typeRiskReduction = 0;
    typeInvestmentValue = 0;
    typeSaidi = 0;
    typeLocalPi = 0;
    typeIntegratedPi = 0;
    for k = 1:numel(selectedType)
        idx = selectedType(k);
        y = choice(idx);
        year = years(y);
        typeCost = typeCost + pof.(sprintf("replacement_cost_%d_kkrw", year))(idx);
        typeRiskReduction = typeRiskReduction + pof.(sprintf("risk_reduction_%d_kkrw", year))(idx);
        typeInvestmentValue = typeInvestmentValue + pof.(sprintf("investment_value_%d_kkrw", year))(idx);
        typeSaidi = typeSaidi + pof.(sprintf("saidi_%d_min", year))(idx);
        typeLocalPi = typeLocalPi + pof.(sprintf("local_pi_%d", year))(idx);
        typeIntegratedPi = typeIntegratedPi + pof.(sprintf("integrated_pi_%d", year))(idx);
    end
    typeRows(end + 1, :) = {alpha, string(methodName), assetTypes(t), assetLabels(t), ...
        numel(selectedType), safeDivide(numel(selectedType), totalSelected), ...
        typeCost, safeDivide(typeCost, totalCost), typeRiskReduction, typeInvestmentValue, ...
        typeSaidi, typeLocalPi, typeIntegratedPi}; %#ok<AGROW>
end
typeSummary = cell2table(typeRows, 'VariableNames', {'alpha', 'method', 'asset_type', ...
    'asset_type_label', 'selected_count', 'selected_share', ...
    'investment_cost_kkrw', 'investment_cost_share', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'saidi_reduction_min', 'local_pi', 'integrated_pi'});

risk2030 = annual.risk_after_cumulative_kkrw(annual.year == 2030);
saidi2030 = annual.saidi_after_cumulative_min(annual.year == 2030);
baselineRisk2030 = annual.baseline_risk_kkrw(annual.year == 2030);
baselineSaidi2030 = annual.baseline_saidi_min(annual.year == 2030);

total = table(alpha, string(methodName), sum(annual.selected_count), ...
    sum(annual.investment_cost_kkrw), sum(annual.risk_reduction_kkrw), ...
    sum(annual.investment_value_kkrw), safeDivide(sum(annual.risk_reduction_kkrw), sum(annual.investment_cost_kkrw)), ...
    sum(annual.saidi_reduction_min), sum(annual.local_pi), sum(annual.integrated_pi), ...
    baselineRisk2030 - risk2030, baselineSaidi2030 - saidi2030, ...
    risk2030, saidi2030, sum(annual.budget_limit_kkrw), sum(annual.capacity_limit), ...
    safeDivide(sum(annual.investment_cost_kkrw), sum(annual.budget_limit_kkrw)), ...
    safeDivide(sum(annual.selected_count), sum(annual.capacity_limit)), ...
    'VariableNames', {'alpha', 'method', 'selected_count', 'investment_cost_kkrw', ...
    'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
    'saidi_reduction_sum_min', 'local_pi', 'integrated_pi', ...
    'risk_reduction_2030_kkrw', 'saidi_reduction_2030_min', ...
    'risk_after_2030_kkrw', 'saidi_after_2030_min', ...
    'budget_limit_total_kkrw', 'capacity_limit_total', ...
    'budget_usage_ratio', 'capacity_usage_ratio'});
end

function saveAlphaFigures(figureDir, totalOut, typeOut, assetTypes, assetLabels)
try
    fig = figure("Visible", "off");
    tiledlayout(2, 2, "Padding", "compact", "TileSpacing", "compact");

    nexttile;
    plot(totalOut.alpha, totalOut.integrated_pi, "-o", "LineWidth", 1.5);
    xlabel("alpha"); ylabel("Integrated PI"); grid on;
    title("Integrated PI by alpha");

    nexttile;
    plot(totalOut.alpha, totalOut.investment_value_kkrw / 100000, "-o", "LineWidth", 1.5);
    xlabel("alpha"); ylabel("Investment Value [억원]"); grid on;
    title("Investment value by alpha");

    nexttile;
    plot(totalOut.alpha, totalOut.saidi_after_2030_min, "-o", "LineWidth", 1.5);
    xlabel("alpha"); ylabel("SAIDI after 2030 [min/customer-year]"); grid on;
    title("SAIDI after 2030 by alpha");

    nexttile;
    plot(totalOut.alpha, totalOut.selected_count, "-o", "LineWidth", 1.5);
    xlabel("alpha"); ylabel("Selected assets"); grid on;
    title("Selected assets by alpha");

    saveas(fig, fullfile(figureDir, "alpha_total_metrics.png"));
    close(fig);

    alphas = unique(typeOut.alpha, "stable");
    costShare = zeros(numel(alphas), numel(assetTypes));
    countShare = zeros(numel(alphas), numel(assetTypes));
    for a = 1:numel(alphas)
        for t = 1:numel(assetTypes)
            idx = typeOut.alpha == alphas(a) & string(typeOut.asset_type) == assetTypes(t);
            if any(idx)
                costShare(a, t) = 100 * typeOut.investment_cost_share(idx);
                countShare(a, t) = 100 * typeOut.selected_share(idx);
            end
        end
    end

    fig = figure("Visible", "off");
    bar(categorical(string(alphas)), costShare, "stacked");
    ylabel("Investment cost share [%]");
    xlabel("alpha");
    legend(assetLabels, "Location", "eastoutside");
    title("Asset type investment cost share by alpha");
    grid on;
    saveas(fig, fullfile(figureDir, "alpha_asset_type_cost_share.png"));
    close(fig);

    fig = figure("Visible", "off");
    bar(categorical(string(alphas)), countShare, "stacked");
    ylabel("Selected asset share [%]");
    xlabel("alpha");
    legend(assetLabels, "Location", "eastoutside");
    title("Asset type replacement quantity share by alpha");
    grid on;
    saveas(fig, fullfile(figureDir, "alpha_asset_type_count_share.png"));
    close(fig);
catch ME
    warning("α 민감도 그림 저장 중 오류가 발생했습니다: %s", ME.message);
end
end

function r = safeDivide(a, b)
if isempty(b) || b == 0 || ~isfinite(b)
    r = NaN;
else
    r = a ./ b;
end
end
