%% MCDM/PI 산출 알고리즘 - MATLAB 버전
% 목적:
% 1) 기존 PoF 5개년 출력파일에서 Risk, 신뢰도, 경제성 점수를 산출한다.
% 2) 추가 AHP 설문 20명 응답을 기하평균으로 집계하여 설비군/설비유형 가중치를 계산한다.
% 3) 설비유형을 고려하지 않은 MCDM PI와 설비유형 계층 AHP를 반영한 Integrated PI를 함께 산출한다.
%
% 주의:
% - 경제성/신뢰도/Risk 기준 자체의 가중치 W_c는 기존 AHP/Fuzzy-AHP/BWM 결과가 확정되면
%   loadCriteriaWeightScenarios() 함수의 expert_average 행에 반영한다.
% - 본 파일의 운영목표별 시나리오는 민감도 분석용 예시이며, 실제 전문가 평균 가중치와 구분한다.

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputDir = fullfile(baseDir, "outputs");
if ~isfolder(outputDir)
    mkdir(outputDir);
end

pofFile = fullfile(dataDir, "pof_5yr_output.xlsx");
surveyFile = fullfile(baseDir, "통합설비_AHP_추가설문지_응답완료_20명.xlsx");
if ~isfile(surveyFile)
    surveyFile = fullfile(dataDir, "incoming", "통합설비_AHP_전문가20명_응답완성.xlsx");
end

outputFile = fullfile(outputDir, "mcdm_pi_matlab.xlsx");
runLogFile = fullfile(outputDir, "mcdm_pi_matlab.log");

years = 2026:2030;
scalePercentile = 95;
candidateFlag = "candidate_top30_current";

if isfile(runLogFile)
    delete(runLogFile);
end
diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off")); %#ok<NASGU>

fprintf("MCDM/PI 산출 - MATLAB\n");
fprintf("PoF 입력: %s\n", pofFile);
fprintf("추가 AHP 설문: %s\n", surveyFile);

if ~isfile(pofFile)
    error("PoF 출력 파일을 찾을 수 없습니다: %s", pofFile);
end
if ~isfile(surveyFile)
    error("추가 AHP 설문 파일을 찾을 수 없습니다: %s", surveyFile);
end

%% 1. 입력 데이터 로드
pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
nAssets = height(pof);
fprintf("자산 수: %d\n", nAssets);

assetMap = buildAssetMap();
pof.asset_label = strings(nAssets, 1);
pof.asset_group = strings(nAssets, 1);
for i = 1:nAssets
    [label, group] = mapAssetType(string(pof.asset_type(i)), assetMap);
    pof.asset_label(i) = label;
    pof.asset_group(i) = group;
end

if ismember(candidateFlag, string(pof.Properties.VariableNames))
    candidateMask = pof.(candidateFlag) == 1;
else
    candidateMask = true(nAssets, 1);
end

%% 2. 추가 AHP 설문 분석
surveyResult = analyzeAdditionalAhpSurvey(surveyFile);
fprintf("추가 AHP 응답 검증: 총 %d개 응답, 누락 %d개, 비양수 %d개\n", ...
    surveyResult.validation.total_response_count, ...
    surveyResult.validation.missing_response_count, ...
    surveyResult.validation.nonpositive_response_count);
fprintf("전문가별 설비군 3x3 행렬: CR<=0.1 %d개, CR>0.1 %d개\n", ...
    surveyResult.validation.group_cr_valid_count, ...
    surveyResult.validation.group_cr_invalid_count);

criteriaScenarios = loadCriteriaWeightScenarios();
typeWeightsByScenario = buildTypeWeightsByScenario(surveyResult, criteriaScenarios);

%% 3. Risk, 신뢰도, 경제성 점수 산출
metrics = buildMetricMatrices(pof, years);
[globalScores, globalScaleSummary] = normalizeMetricsGlobal(metrics, years, scalePercentile);
[typeScores, typeScaleSummary] = normalizeMetricsByType(metrics, pof.asset_type, years, scalePercentile);

%% 4. MCDM PI 및 Integrated PI 산출
[piWide, piLong, piSummary] = buildPiTables( ...
    pof, metrics, globalScores, typeScores, typeWeightsByScenario, ...
    criteriaScenarios, years, assetMap, candidateMask);

fprintf("PI 산출 완료: wide %d행, long %d행\n", height(piWide), height(piLong));

%% 5. 결과 저장
if isfile(outputFile)
    delete(outputFile);
end

writetable(criteriaScenarios, outputFile, "Sheet", "criteria_scenarios");
writetable(surveyResult.pairTable, outputFile, "Sheet", "survey_pairs");
writetable(surveyResult.groupWeights, outputFile, "Sheet", "group_weights");
writetable(surveyResult.typeConditionalWeights, outputFile, "Sheet", "type_cond_weights");
writetable(typeWeightsByScenario, outputFile, "Sheet", "type_weights_scenario");
writetable(surveyResult.validationTable, outputFile, "Sheet", "validation_summary");
writetable(globalScaleSummary, outputFile, "Sheet", "normalization_global");
writetable(typeScaleSummary, outputFile, "Sheet", "normalization_type");
writetable(piSummary, outputFile, "Sheet", "pi_summary");
writetable(piWide, outputFile, "Sheet", "pi_asset_wide");
writetable(piLong, outputFile, "Sheet", "pi_asset_year");

fprintf("저장 완료: %s\n", outputFile);

%% =========================================================================
% 지역 함수
% =========================================================================

function assetMap = buildAssetMap()
% 영문 asset_type과 논문상 설비유형/설비군을 연결한다.
assetMap = table( ...
    ["pole_transformer"; "ground_transformer"; "overhead_switch"; "underground_switch"; "overhead_line"; "underground_cable"], ...
    ["주상변압기"; "지상변압기"; "가공개폐기"; "지중개폐기"; "가공배전선로"; "지중케이블"], ...
    ["변압설비"; "변압설비"; "개폐설비"; "개폐설비"; "선로설비"; "선로설비"], ...
    'VariableNames', {'asset_type', 'asset_label', 'asset_group'});
end

function [label, group] = mapAssetType(assetType, assetMap)
idx = strcmp(string(assetMap.asset_type), assetType);
if ~any(idx)
    label = assetType;
    group = "미분류";
else
    label = string(assetMap.asset_label(find(idx, 1)));
    group = string(assetMap.asset_group(find(idx, 1)));
end
end

function criteriaScenarios = loadCriteriaWeightScenarios()
% W_c: 경제성, 신뢰도, Risk 기준 자체의 가중치.
% expert_average는 기존 AHP/Fuzzy-AHP/BWM 결과가 확정되면 이 행의 값을 교체한다.
scenario_id = [
    "balanced_default"
    "economy_centered"
    "reliability_centered"
    "risk_centered"
    "public_service"
    ];

scenario_name = [
    "균형 기본"
    "경제성 중심"
    "신뢰도 중심"
    "Risk 중심"
    "공공서비스 균형"
    ];

weight_economy = [1/3; 0.60; 0.20; 0.20; 0.30];
weight_reliability = [1/3; 0.20; 0.60; 0.20; 0.40];
weight_risk = [1/3; 0.20; 0.20; 0.60; 0.30];

source_note = [
    "기준 가중치 확정 전 기본 균형 시나리오"
    "운영목표별 민감도 분석용 예시"
    "운영목표별 민감도 분석용 예시"
    "운영목표별 민감도 분석용 예시"
    "운영목표별 민감도 분석용 예시"
    ];

criteriaScenarios = table(scenario_id, scenario_name, ...
    weight_economy, weight_reliability, weight_risk, source_note);
end

function surveyResult = analyzeAdditionalAhpSurvey(surveyFile)
sheetName = findSurveySummarySheet(surveyFile);
raw = readcell(surveyFile, "Sheet", sheetName);

headerRow = 3;
firstDataRow = 4;
lastDataRow = 21;
expertFirstCol = 6;
expertLastCol = 25;

questionIds = strings(lastDataRow - firstDataRow + 1, 1);
criteria = strings(numel(questionIds), 1);
levels = strings(numel(questionIds), 1);
leftItems = strings(numel(questionIds), 1);
rightItems = strings(numel(questionIds), 1);
responseMat = nan(numel(questionIds), expertLastCol - expertFirstCol + 1);

for r = firstDataRow:lastDataRow
    k = r - firstDataRow + 1;
    questionIds(k) = string(raw{r, 1});
    criteria(k) = mapQuestionCriterion(questionIds(k));
    levels(k) = normalizeLabel(raw{r, 3});
    leftItems(k) = normalizeLabel(raw{r, 4});
    rightItems(k) = normalizeLabel(raw{r, 5});

    for c = expertFirstCol:expertLastCol
        responseMat(k, c - expertFirstCol + 1) = toDouble(raw{r, c});
    end
end

expertIds = strings(1, expertLastCol - expertFirstCol + 1);
for c = expertFirstCol:expertLastCol
    expertIds(c - expertFirstCol + 1) = string(raw{headerRow, c});
end

missingCount = sum(~isfinite(responseMat), "all");
nonpositiveCount = sum(isfinite(responseMat) & responseMat <= 0, "all");
if missingCount > 0 || nonpositiveCount > 0
    error("추가 AHP 응답에 누락 또는 비양수 값이 있습니다. 누락=%d, 비양수=%d", missingCount, nonpositiveCount);
end

geomeanValues = exp(mean(log(responseMat), 2));

pairTable = table(questionIds, criteria, levels, leftItems, rightItems, geomeanValues, ...
    'VariableNames', {'question_id', 'criterion', 'level', 'left_item', 'right_item', 'geomean_value'});

criterionCodes = ["economy", "reliability", "risk"];
criterionNames = ["경제성", "신뢰도", "Risk"];
groups = ["변압설비", "개폐설비", "선로설비"];
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", "지중개폐기", "가공배전선로", "지중케이블"];
assetGroups = ["변압설비", "변압설비", "개폐설비", "개폐설비", "선로설비", "선로설비"];

groupRows = {};
typeRows = {};

groupCrPerExpert = {};

for cIdx = 1:numel(criterionCodes)
    criterionCode = criterionCodes(cIdx);
    criterionName = criterionNames(cIdx);

    idxGroup = criteria == criterionCode & levels == "설비군";
    [groupW, groupCR, groupPCM] = ahpWeightsFromPairs(groups, leftItems(idxGroup), rightItems(idxGroup), geomeanValues(idxGroup)); %#ok<ASGLU>

    for g = 1:numel(groups)
        groupRows(end+1, :) = {criterionCode, criterionName, groups(g), groupW(g), groupCR}; %#ok<AGROW>
    end

    for e = 1:numel(expertIds)
        valuesE = responseMat(idxGroup, e);
        [~, crE] = ahpWeightsFromPairs(groups, leftItems(idxGroup), rightItems(idxGroup), valuesE);
        groupCrPerExpert(end+1, :) = {criterionCode, criterionName, expertIds(e), crE, crE <= 0.1}; %#ok<AGROW>
    end

    idxType = criteria == criterionCode & levels == "설비유형";
    for rr = find(idxType)'
        leftLabel = leftItems(rr);
        rightLabel = rightItems(rr);
        value = geomeanValues(rr);
        pairGroup = assetGroups(assetLabels == leftLabel);
        if isempty(pairGroup)
            pairGroup = assetGroups(assetLabels == rightLabel);
        end
        if isempty(pairGroup)
            error("설비유형의 설비군을 찾지 못했습니다: %s / %s", leftLabel, rightLabel);
        end
        pairGroup = pairGroup(1);
        groupWeight = groupW(groups == pairGroup);

        localWeights = twoItemAhpWeights(value);
        typeRows(end+1, :) = {criterionCode, criterionName, pairGroup, leftLabel, groupWeight, localWeights(1), groupWeight * localWeights(1)}; %#ok<AGROW>
        typeRows(end+1, :) = {criterionCode, criterionName, pairGroup, rightLabel, groupWeight, localWeights(2), groupWeight * localWeights(2)}; %#ok<AGROW>
    end
end

groupWeights = cell2table(groupRows, ...
    'VariableNames', {'criterion', 'criterion_name', 'asset_group', 'group_weight', 'group_cr'});

typeConditionalWeights = cell2table(typeRows, ...
    'VariableNames', {'criterion', 'criterion_name', 'asset_group', 'asset_label', ...
    'group_weight', 'within_group_weight', 'conditional_type_weight'});

groupCrTable = cell2table(groupCrPerExpert, ...
    'VariableNames', {'criterion', 'criterion_name', 'expert_id', 'cr', 'valid_cr'});

validation = struct();
validation.total_response_count = numel(responseMat);
validation.missing_response_count = missingCount;
validation.nonpositive_response_count = nonpositiveCount;
validation.group_cr_matrix_count = height(groupCrTable);
validation.group_cr_valid_count = sum(groupCrTable.valid_cr);
validation.group_cr_invalid_count = sum(~groupCrTable.valid_cr);

validationTable = table( ...
    ["total_response_count"; "missing_response_count"; "nonpositive_response_count"; ...
     "group_cr_matrix_count"; "group_cr_valid_count"; "group_cr_invalid_count"], ...
    [validation.total_response_count; validation.missing_response_count; validation.nonpositive_response_count; ...
     validation.group_cr_matrix_count; validation.group_cr_valid_count; validation.group_cr_invalid_count], ...
    'VariableNames', {'check_item', 'value'});

surveyResult.pairTable = pairTable;
surveyResult.groupWeights = groupWeights;
surveyResult.typeConditionalWeights = typeConditionalWeights;
surveyResult.groupCrTable = groupCrTable;
surveyResult.validation = validation;
surveyResult.validationTable = validationTable;
end

function sheetName = findSurveySummarySheet(surveyFile)
sheets = string(sheetnames(surveyFile));
candidates = ["AHP집계분석", "집계분석", "연구자용_분석"];
sheetName = "";
for i = 1:numel(candidates)
    if any(sheets == candidates(i))
        sheetName = candidates(i);
        return
    end
end
for i = 1:numel(sheets)
    raw = readcell(surveyFile, "Sheet", sheets(i), "Range", "A1:Z5");
    if size(raw, 1) >= 3 && string(raw{3, 1}) == "문항"
        sheetName = sheets(i);
        return
    end
end
error("추가 AHP 설문 집계 시트를 찾지 못했습니다.");
end

function criterion = mapQuestionCriterion(questionId)
q = char(questionId);
numPart = str2double(q(2:end));
if startsWith(q, "G")
    if numPart <= 3
        criterion = "economy";
    elseif numPart <= 6
        criterion = "reliability";
    else
        criterion = "risk";
    end
elseif startsWith(q, "A")
    if numPart <= 3
        criterion = "economy";
    elseif numPart <= 6
        criterion = "reliability";
    else
        criterion = "risk";
    end
else
    error("알 수 없는 문항 코드입니다: %s", questionId);
end
end

function s = normalizeLabel(x)
if ismissingValue(x)
    s = "";
else
    s = strtrim(string(x));
end
s = replace(s, "지중개폐기_RMU", "지중개폐기");
s = replace(s, "RMU", "");
s = replace(s, "__", "_");
s = strtrim(s);
end

function tf = ismissingValue(x)
try
    tf = isempty(x) || ismissing(x);
catch
    tf = isempty(x);
end
end

function v = toDouble(x)
if isnumeric(x)
    v = double(x);
elseif isstring(x) || ischar(x)
    txt = strtrim(string(x));
    if txt == ""
        v = NaN;
    else
        v = str2double(txt);
    end
else
    try
        v = str2double(string(x));
    catch
        v = NaN;
    end
end
end

function [weights, cr, PCM] = ahpWeightsFromPairs(items, leftItems, rightItems, values)
n = numel(items);
PCM = eye(n);
for k = 1:numel(values)
    v = values(k);
    if ~isfinite(v) || v <= 0
        error("AHP 쌍대비교 값이 유효하지 않습니다.");
    end
    i = find(items == leftItems(k), 1);
    j = find(items == rightItems(k), 1);
    if isempty(i) || isempty(j)
        error("AHP 항목 매핑 실패: %s / %s", leftItems(k), rightItems(k));
    end
    PCM(i, j) = v;
    PCM(j, i) = 1 / v;
end

geoMean = exp(mean(log(PCM), 2));
weights = geoMean / sum(geoMean);
cr = calcCR(PCM);
end

function cr = calcCR(PCM)
n = size(PCM, 1);
if n <= 2
    cr = 0;
    return
end
eigVals = eig(PCM);
lambdaMax = max(real(eigVals));
CI = (lambdaMax - n) / (n - 1);
RI = [0, 0, 0.58, 0.90, 1.12, 1.24, 1.32, 1.41, 1.45];
ri = RI(min(n, numel(RI)));
if ri <= 0
    cr = 0;
else
    cr = CI / ri;
end
end

function weights = twoItemAhpWeights(value)
if ~isfinite(value) || value <= 0
    error("2항목 AHP 값이 유효하지 않습니다.");
end
weights = [sqrt(value); sqrt(1 / value)];
weights = weights / sum(weights);
end

function typeWeightsByScenario = buildTypeWeightsByScenario(surveyResult, criteriaScenarios)
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", "지중개폐기", "가공배전선로", "지중케이블"];
rows = {};
TC = surveyResult.typeConditionalWeights;
for s = 1:height(criteriaScenarios)
    scenarioId = string(criteriaScenarios.scenario_id(s));
    scenarioName = string(criteriaScenarios.scenario_name(s));
    wcEconomy = criteriaScenarios.weight_economy(s);
    wcReliability = criteriaScenarios.weight_reliability(s);
    wcRisk = criteriaScenarios.weight_risk(s);

    rawWeights = zeros(numel(assetLabels), 1);
    for a = 1:numel(assetLabels)
        label = assetLabels(a);
        idxE = string(TC.asset_label) == label & string(TC.criterion) == "economy";
        idxR = string(TC.asset_label) == label & string(TC.criterion) == "reliability";
        idxK = string(TC.asset_label) == label & string(TC.criterion) == "risk";
        rawWeights(a) = ...
            wcEconomy * TC.conditional_type_weight(idxE) + ...
            wcReliability * TC.conditional_type_weight(idxR) + ...
            wcRisk * TC.conditional_type_weight(idxK);
    end
    rawWeights = rawWeights / sum(rawWeights);

    for a = 1:numel(assetLabels)
        rows(end+1, :) = {scenarioId, scenarioName, assetLabels(a), rawWeights(a)}; %#ok<AGROW>
    end
end

typeWeightsByScenario = cell2table(rows, ...
    'VariableNames', {'scenario_id', 'scenario_name', 'asset_label', 'type_weight'});
end

function metrics = buildMetricMatrices(pof, years)
nAssets = height(pof);
nYears = numel(years);
metrics.riskReduction = zeros(nAssets, nYears);
metrics.reliability = zeros(nAssets, nYears);
metrics.economy = zeros(nAssets, nYears);
metrics.investmentValue = zeros(nAssets, nYears);
metrics.cost = zeros(nAssets, nYears);
metrics.age = zeros(nAssets, nYears);

for y = 1:nYears
    year = years(y);
    metrics.riskReduction(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year));
    metrics.reliability(:, y) = pof.(sprintf("saidi_%d_min", year));
    metrics.economy(:, y) = pof.(sprintf("investment_efficiency_%d", year));
    metrics.investmentValue(:, y) = pof.(sprintf("investment_value_%d_kkrw", year));
    metrics.cost(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year));
    metrics.age(:, y) = pof.(sprintf("age_%d", year));
end

metrics.riskReduction = cleanNonnegative(metrics.riskReduction);
metrics.reliability = cleanNonnegative(metrics.reliability);
metrics.economy = cleanNonnegative(metrics.economy);
metrics.investmentValue(~isfinite(metrics.investmentValue)) = 0;
metrics.cost = cleanNonnegative(metrics.cost);
metrics.age(~isfinite(metrics.age)) = 0;
end

function x = cleanNonnegative(x)
x(~isfinite(x)) = 0;
x = max(x, 0);
end

function [scores, summaryTable] = normalizeMetricsGlobal(metrics, years, scalePercentile)
metricNames = ["risk_reduction", "reliability_saidi", "economy_efficiency"];
metricFields = ["riskReduction", "reliability", "economy"];
scores = struct();
rows = {};
for m = 1:numel(metricNames)
    fieldName = metricFields(m);
    X = metrics.(fieldName);
    scale = percentileScale(X(:), scalePercentile);
    S = X / scale;
    S(~isfinite(S)) = 0;
    S = max(min(S, 1), 0);
    scores.(fieldName) = S;
    rows(end+1, :) = {"global", metricNames(m), scalePercentile, scale}; %#ok<AGROW>
end
summaryTable = cell2table(rows, ...
    'VariableNames', {'scope', 'metric', 'scale_percentile', 'scale_value'});
summaryTable.years = repmat(strjoin(string(years), ","), height(summaryTable), 1);
end

function [scores, summaryTable] = normalizeMetricsByType(metrics, assetTypes, years, scalePercentile)
metricNames = ["risk_reduction", "reliability_saidi", "economy_efficiency"];
metricFields = ["riskReduction", "reliability", "economy"];
uniqueTypes = unique(string(assetTypes), "stable");

scores = struct();
for m = 1:numel(metricFields)
    scores.(metricFields(m)) = zeros(size(metrics.(metricFields(m))));
end

rows = {};
for t = 1:numel(uniqueTypes)
    type = uniqueTypes(t);
    idx = string(assetTypes) == type;
    for m = 1:numel(metricNames)
        fieldName = metricFields(m);
        X = metrics.(fieldName);
        scale = percentileScale(X(idx, :), scalePercentile);
        S = X(idx, :) / scale;
        S(~isfinite(S)) = 0;
        S = max(min(S, 1), 0);
        scores.(fieldName)(idx, :) = S;
        rows(end+1, :) = {type, metricNames(m), scalePercentile, scale}; %#ok<AGROW>
    end
end
summaryTable = cell2table(rows, ...
    'VariableNames', {'asset_type', 'metric', 'scale_percentile', 'scale_value'});
summaryTable.years = repmat(strjoin(string(years), ","), height(summaryTable), 1);
end

function scale = percentileScale(x, percentileValue)
v = x(isfinite(x) & x > 0);
if isempty(v)
    scale = 1;
    return
end
v = sort(v(:));
n = numel(v);
if n == 1
    scale = v(1);
    return
end
pos = (percentileValue / 100) * (n - 1) + 1;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    scale = v(lo);
else
    frac = pos - lo;
    scale = v(lo) + frac * (v(hi) - v(lo));
end
if ~isfinite(scale) || scale <= 0
    scale = max(v);
end
if ~isfinite(scale) || scale <= 0
    scale = 1;
end
end

function [piWide, piLong, piSummary] = buildPiTables( ...
    pof, metrics, globalScores, typeScores, typeWeightsByScenario, ...
    criteriaScenarios, years, assetMap, candidateMask)

nAssets = height(pof);
nYears = numel(years);
nScenarios = height(criteriaScenarios);
piWide = pof(:, {'asset_id', 'asset_type', 'asset_code', 'asset_label', 'asset_group'});
piWide.candidate_top30_current = candidateMask;

summaryRows = {};

nLongRows = nAssets * nYears * nScenarios;
long_asset_id = strings(nLongRows, 1);
long_asset_type = strings(nLongRows, 1);
long_asset_label = strings(nLongRows, 1);
long_asset_group = strings(nLongRows, 1);
long_scenario_id = strings(nLongRows, 1);
long_scenario_name = strings(nLongRows, 1);
long_year = zeros(nLongRows, 1);
long_candidate = false(nLongRows, 1);
long_age = zeros(nLongRows, 1);
long_cost = zeros(nLongRows, 1);
long_risk_reduction = zeros(nLongRows, 1);
long_investment_value = zeros(nLongRows, 1);
long_investment_efficiency = zeros(nLongRows, 1);
long_saidi = zeros(nLongRows, 1);
long_score_risk = zeros(nLongRows, 1);
long_score_reliability = zeros(nLongRows, 1);
long_score_economy = zeros(nLongRows, 1);
long_local_pi = zeros(nLongRows, 1);
long_integrated_pi = zeros(nLongRows, 1);

base_asset_id = string(pof.asset_id);
base_asset_type = string(pof.asset_type);
base_asset_label = string(pof.asset_label);
base_asset_group = string(pof.asset_group);

for y = 1:nYears
    year = years(y);
    piWide.(sprintf("score_risk_%d", year)) = globalScores.riskReduction(:, y);
    piWide.(sprintf("score_reliability_%d", year)) = globalScores.reliability(:, y);
    piWide.(sprintf("score_economy_%d", year)) = globalScores.economy(:, y);
end

for s = 1:height(criteriaScenarios)
    scenarioId = string(criteriaScenarios.scenario_id(s));
    scenarioName = string(criteriaScenarios.scenario_name(s));
    safeScenarioId = matlab.lang.makeValidName(char(scenarioId));

    wE = criteriaScenarios.weight_economy(s);
    wR = criteriaScenarios.weight_reliability(s);
    wK = criteriaScenarios.weight_risk(s);
    wSum = wE + wR + wK;
    wE = wE / wSum;
    wR = wR / wSum;
    wK = wK / wSum;

    localPiGlobal = ...
        wK * globalScores.riskReduction + ...
        wR * globalScores.reliability + ...
        wE * globalScores.economy;

    localPiType = ...
        wK * typeScores.riskReduction + ...
        wR * typeScores.reliability + ...
        wE * typeScores.economy;

    integratedPi = zeros(nAssets, nYears);
    for y = 1:nYears
        scaleN = sum(localPiGlobal(:, y), "omitnan");
        if ~isfinite(scaleN) || scaleN <= 0
            scaleN = nAssets;
        end
        for a = 1:height(assetMap)
            assetType = string(assetMap.asset_type(a));
            assetLabel = string(assetMap.asset_label(a));
            idx = string(pof.asset_type) == assetType;
            denom = sum(localPiType(idx, y), "omitnan");
            if denom <= 0
                continue
            end
            wType = typeWeightsByScenario.type_weight( ...
                string(typeWeightsByScenario.scenario_id) == scenarioId & ...
                string(typeWeightsByScenario.asset_label) == assetLabel);
            if isempty(wType)
                error("설비유형 가중치를 찾지 못했습니다: %s / %s", scenarioId, assetLabel);
            end
            localShare = localPiType(idx, y) / denom;
            integratedPi(idx, y) = localShare * wType(1) * scaleN;
        end
    end

    for y = 1:nYears
        year = years(y);
        piWide.(sprintf("pi_%s_%d", safeScenarioId, year)) = localPiGlobal(:, y);
        piWide.(sprintf("integrated_pi_%s_%d", safeScenarioId, year)) = integratedPi(:, y);

        summaryRows(end+1, :) = { ...
            scenarioId, scenarioName, year, ...
            sum(localPiGlobal(:, y), "omitnan"), ...
            sum(integratedPi(:, y), "omitnan"), ...
            mean(localPiGlobal(:, y), "omitnan"), ...
            mean(integratedPi(:, y), "omitnan"), ...
            sum(localPiGlobal(candidateMask, y), "omitnan"), ...
            sum(integratedPi(candidateMask, y), "omitnan")}; %#ok<AGROW>

        rowStart = ((s - 1) * nYears + (y - 1)) * nAssets + 1;
        rowEnd = rowStart + nAssets - 1;
        rr = rowStart:rowEnd;

        long_asset_id(rr) = base_asset_id;
        long_asset_type(rr) = base_asset_type;
        long_asset_label(rr) = base_asset_label;
        long_asset_group(rr) = base_asset_group;
        long_scenario_id(rr) = scenarioId;
        long_scenario_name(rr) = scenarioName;
        long_year(rr) = year;
        long_candidate(rr) = candidateMask;
        long_age(rr) = metrics.age(:, y);
        long_cost(rr) = metrics.cost(:, y);
        long_risk_reduction(rr) = metrics.riskReduction(:, y);
        long_investment_value(rr) = metrics.investmentValue(:, y);
        long_investment_efficiency(rr) = metrics.economy(:, y);
        long_saidi(rr) = metrics.reliability(:, y);
        long_score_risk(rr) = globalScores.riskReduction(:, y);
        long_score_reliability(rr) = globalScores.reliability(:, y);
        long_score_economy(rr) = globalScores.economy(:, y);
        long_local_pi(rr) = localPiGlobal(:, y);
        long_integrated_pi(rr) = integratedPi(:, y);
    end
end

piLong = table( ...
    long_asset_id, long_asset_type, long_asset_label, long_asset_group, ...
    long_scenario_id, long_scenario_name, long_year, long_candidate, ...
    long_age, long_cost, long_risk_reduction, ...
    long_investment_value, long_investment_efficiency, long_saidi, ...
    long_score_risk, long_score_reliability, long_score_economy, ...
    long_local_pi, long_integrated_pi, ...
    'VariableNames', { ...
    'asset_id', 'asset_type', 'asset_label', 'asset_group', ...
    'scenario_id', 'scenario_name', 'year', 'candidate_top30_current', ...
    'age', 'replacement_cost_kkrw', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'investment_efficiency', 'saidi_min', ...
    'score_risk', 'score_reliability', 'score_economy', ...
    'local_mcdm_pi', 'integrated_pi'});

piSummary = cell2table(summaryRows, 'VariableNames', { ...
    'scenario_id', 'scenario_name', 'year', ...
    'sum_local_mcdm_pi', 'sum_integrated_pi', ...
    'avg_local_mcdm_pi', 'avg_integrated_pi', ...
    'candidate_sum_local_mcdm_pi', 'candidate_sum_integrated_pi'});
end
