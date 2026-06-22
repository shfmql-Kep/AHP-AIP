%% 로컬 PI 산출 알고리즘 - MATLAB 버전
% 목적:
% 1) PoF 5개년 출력파일에서 개별 설비의 6개 하위지표를 구성한다.
% 2) 전문가 20명 설문 응답으로 AHP 하위지표 가중치를 산정한다.
% 3) Fuzzy 절대영향도는 AHP 가중치의 보정·강건성 검토로만 사용한다.
% 4) 통합설비 PI는 본 파일에서 계산하지 않는다.
%
% 로컬 PI 공식:
% PI_AHP(i,t) = Σ_k w_k^AHP × S_k(i,t)
% PI_FuzzyAdj(i,t) = Σ_k w_k^F × S_k(i,t)
% w_k^F = w_k^AHP × Wa_k / Σ_j(w_j^AHP × Wa_j)
%
% 6개 하위지표:
% - 경제성: 투자가치, 투자효율
% - 신뢰도: SAIDI 저감, 고장예측 저감(PoF proxy)
% - 안전·환경: 안전 기대영향(PoF×CoF_safety), 환경 기대영향(PoF×CoF_environment)

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
surveyDir = fullfile(baseDir, "Survey");
outputDir = fullfile(baseDir, "outputs");
if ~isfolder(outputDir)
    mkdir(outputDir);
end

pofFile = fullfile(dataDir, "pof_5yr_output.xlsx");
surveyFile = fullfile(surveyDir, "통합설비_FuzzyAHP_설문지_v2_응답완료_20명.xlsx");
outputFile = fullfile(outputDir, "local_pi_matlab.xlsx");
runLogFile = fullfile(outputDir, "local_pi_matlab.log");

years = 2026:2030;
scalePercentile = 95;
candidateFlag = "candidate_top30_current";

if isfile(runLogFile)
    delete(runLogFile);
end
diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off")); %#ok<NASGU>

fprintf("로컬 PI 산출 - MATLAB\n");
fprintf("PoF 입력: %s\n", pofFile);
fprintf("설문 입력: %s\n", surveyFile);

if ~isfile(pofFile)
    error("PoF 출력 파일을 찾을 수 없습니다: %s", pofFile);
end
if ~isfile(surveyFile)
    error("설문 응답 파일을 찾을 수 없습니다: %s", surveyFile);
end

%% 1. 데이터 로드
pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
raw = readtable(surveyFile, "Sheet", "응답_RAW", "VariableNamingRule", "preserve");
nAssets = height(pof);
fprintf("자산 수: %d\n", nAssets);
fprintf("설문 RAW 행 수: %d\n", height(raw));

assetMap = buildAssetMap();
pof.asset_label = strings(nAssets, 1);
pof.asset_group = strings(nAssets, 1);
for i = 1:nAssets
    [label, group] = mapAssetType(string(pof.asset_type(i)), assetMap);
    pof.asset_label(i) = label;
    pof.asset_group(i) = group;
end

if ismember(candidateFlag, string(pof.Properties.VariableNames))
    candidateMask = logical(pof.(candidateFlag));
else
    candidateMask = true(nAssets, 1);
end

%% 2. 설문 기반 가중치 산정
weightResult = calculateLocalWeights(raw);
fprintf("AHP 기준 CR: %.6f\n", weightResult.criteriaCR);
fprintf("AHP 하위지표 가중치 합계: %.6f\n", sum(weightResult.ahpWeights.weight));
fprintf("Fuzzy 보정 가중치 합계: %.6f\n", sum(weightResult.fuzzyWeights.fuzzy_adjusted_weight));

%% 3. 6개 하위지표 구성 및 정규화
metrics = buildLocalMetricMatrices(pof, years);
[scores, normalizationSummary] = normalizeMetricMatrices(metrics, years, scalePercentile);
metricDefinition = buildMetricDefinitionTable();

%% 4. 로컬 PI 산출
[piWide, piLong, piSummaryYear, piSummaryTypeYear] = buildLocalPiTables( ...
    pof, metrics, scores, weightResult, years, candidateMask);

fprintf("Local PI 산출 완료: wide %d행, long %d행\n", height(piWide), height(piLong));

%% 5. 결과 저장
if isfile(outputFile)
    delete(outputFile);
end

writetable(metricDefinition, outputFile, "Sheet", "metric_definition");
writetable(weightResult.criteriaWeights, outputFile, "Sheet", "criteria_weights");
writetable(weightResult.ahpWeights, outputFile, "Sheet", "ahp_sub_weights");
writetable(weightResult.fuzzyWeights, outputFile, "Sheet", "fuzzy_adjusted_weights");
writetable(weightResult.fuzzyScores, outputFile, "Sheet", "fuzzy_scores");
writetable(weightResult.validationSummary, outputFile, "Sheet", "validation_summary");
writetable(normalizationSummary, outputFile, "Sheet", "normalization_summary");
writetable(piSummaryYear, outputFile, "Sheet", "pi_summary_year");
writetable(piSummaryTypeYear, outputFile, "Sheet", "pi_summary_type_year");
writetable(piWide, outputFile, "Sheet", "local_pi_asset_wide");
writetable(piLong, outputFile, "Sheet", "local_pi_asset_year");

fprintf("저장 완료: %s\n", outputFile);

%% =========================================================================
% 지역 함수
% =========================================================================

function assetMap = buildAssetMap()
% 영문 asset_type을 논문상 설비유형 및 설비군으로 매핑한다.
assetMap = table( ...
    ["pole_transformer"; "ground_transformer"; "overhead_switch"; "underground_switch"; "overhead_line"; "underground_cable"], ...
    ["주상변압기"; "지상변압기"; "가공개폐기"; "지중개폐기"; "가공배전선로"; "지중케이블"], ...
    ["변압설비"; "변압설비"; "개폐설비"; "개폐설비"; "선로설비"; "선로설비"], ...
    'VariableNames', {'asset_type', 'asset_label', 'asset_group'});
end

function [label, group] = mapAssetType(assetType, assetMap)
idx = string(assetMap.asset_type) == assetType;
if ~any(idx)
    label = assetType;
    group = "미분류";
else
    label = string(assetMap.asset_label(find(idx, 1)));
    group = string(assetMap.asset_group(find(idx, 1)));
end
end

function metricDefinition = buildMetricDefinitionTable()
metric_id = [
    "investment_value"
    "investment_efficiency"
    "saidi_reduction"
    "failure_probability"
    "safety_effect"
    "environment_effect"
    ];
metric_name = [
    "투자가치"
    "투자효율"
    "SAIDI 저감"
    "고장예측 저감"
    "안전 영향"
    "환경 영향"
    ];
parent_criterion = [
    "경제성"
    "경제성"
    "신뢰도"
    "신뢰도"
    "안전·환경"
    "안전·환경"
    ];
raw_formula = [
    "investment_value_YYYY_kkrw"
    "investment_efficiency_YYYY 또는 bcr_YYYY"
    "saidi_YYYY_min"
    "pof_YYYY"
    "pof_YYYY × cof_safety_kkrw"
    "pof_YYYY × cof_environment_adjusted_kkrw"
    ];
normalization = repmat("P95 기준 0~1 상한 정규화", 6, 1);

metricDefinition = table(metric_id, metric_name, parent_criterion, raw_formula, normalization);
end

function result = calculateLocalWeights(raw)
% 설문 RAW에서 AHP 가중치와 Fuzzy 보정가중치를 산정한다.
requiredVars = ["respondent", "section", "item", "value"];
for i = 1:numel(requiredVars)
    if ~ismember(requiredVars(i), string(raw.Properties.VariableNames))
        error("설문 RAW 시트에 필요한 컬럼이 없습니다: %s", requiredVars(i));
    end
end

raw.section = string(raw.section);
raw.item = string(raw.item);
raw.value = double(raw.value);

missingCount = sum(~isfinite(raw.value));
nonpositiveCount = sum(isfinite(raw.value) & raw.value <= 0);
if missingCount > 0 || nonpositiveCount > 0
    error("설문 응답값에 누락 또는 비양수 값이 있습니다. 누락=%d, 비양수=%d", missingCount, nonpositiveCount);
end

criteriaItems = ["경제성", "신뢰도", "안전·환경"];
criteriaLeft = ["경제성"; "경제성"; "신뢰도"];
criteriaRight = ["신뢰도"; "안전·환경"; "안전·환경"];
criteriaValues = [
    getGeomean(raw, "AHP기준", "경제/신뢰")
    getGeomean(raw, "AHP기준", "경제/안전환경")
    getGeomean(raw, "AHP기준", "신뢰/안전환경")
    ];
[criteriaWeightsVector, criteriaCR] = ahpWeightsFromPairs(criteriaItems, criteriaLeft, criteriaRight, criteriaValues);

criteria_id = ["economy"; "reliability"; "safety_environment"];
criteria_name = criteriaItems';
criteria_weight = criteriaWeightsVector;
criteriaWeights = table(criteria_id, criteria_name, criteria_weight);

metricIds = [
    "investment_value"
    "investment_efficiency"
    "saidi_reduction"
    "failure_probability"
    "safety_effect"
    "environment_effect"
    ];
metricNames = [
    "투자가치"
    "투자효율"
    "SAIDI저감"
    "고장예측저감"
    "안전영향"
    "환경영향"
    ];
parentCriterion = [
    "경제성"
    "경제성"
    "신뢰도"
    "신뢰도"
    "안전·환경"
    "안전·환경"
    ];

subPairs = {
    "경제성", "NPV/BCR", "투자가치", "투자효율";
    "신뢰도", "SAIDI/고장", "SAIDI저감", "고장예측저감";
    "안전·환경", "안전/환경", "안전영향", "환경영향";
    };

ahpWeightValues = zeros(numel(metricIds), 1);
localWeightValues = zeros(numel(metricIds), 1);
for p = 1:size(subPairs, 1)
    parent = string(subPairs{p, 1});
    item = string(subPairs{p, 2});
    left = string(subPairs{p, 3});
    right = string(subPairs{p, 4});
    pairValue = getGeomean(raw, "AHP하위", item);
    localWeights = twoItemAhpWeights(pairValue);
    parentWeight = criteriaWeights.criteria_weight(criteriaWeights.criteria_name == parent);

    leftIdx = metricNames == left;
    rightIdx = metricNames == right;
    localWeightValues(leftIdx) = localWeights(1);
    localWeightValues(rightIdx) = localWeights(2);
    ahpWeightValues(leftIdx) = parentWeight * localWeights(1);
    ahpWeightValues(rightIdx) = parentWeight * localWeights(2);
end

ahpWeights = table(metricIds, metricNames, parentCriterion, localWeightValues, ahpWeightValues, ...
    'VariableNames', {'metric_id', 'metric_name', 'parent_criterion', 'local_weight_within_parent', 'weight'});

fuzzyAverageScore = zeros(numel(metricIds), 1);
fuzzyWa = zeros(numel(metricIds), 1);
for i = 1:numel(metricIds)
    values = raw.value(raw.section == "퍼지측도" & raw.item == metricNames(i));
    if isempty(values)
        error("퍼지측도 응답을 찾지 못했습니다: %s", metricNames(i));
    end
    fuzzyAverageScore(i) = mean(values, "omitnan");
    fuzzyWa(i) = fuzzyAverageScore(i) / 6.0;
end

fuzzyAdjusted = ahpWeightValues .* fuzzyWa;
fuzzyAdjusted = fuzzyAdjusted / sum(fuzzyAdjusted);

fuzzyScores = table(metricIds, metricNames, fuzzyAverageScore, fuzzyWa, ...
    'VariableNames', {'metric_id', 'metric_name', 'average_score_0_6', 'wa_score_over_6'});

fuzzyWeights = table(metricIds, metricNames, parentCriterion, ahpWeightValues, fuzzyWa, fuzzyAdjusted, ...
    'VariableNames', {'metric_id', 'metric_name', 'parent_criterion', 'ahp_weight', 'wa_score_over_6', 'fuzzy_adjusted_weight'});

validationSummary = table( ...
    ["respondent_count"; "raw_row_count"; "missing_value_count"; "nonpositive_value_count"; ...
     "criteria_cr"; "ahp_weight_sum"; "fuzzy_adjusted_weight_sum"; "sum_wa"], ...
    [numel(unique(raw.respondent)); height(raw); missingCount; nonpositiveCount; ...
     criteriaCR; sum(ahpWeightValues); sum(fuzzyAdjusted); sum(fuzzyWa)], ...
    'VariableNames', {'check_item', 'value'});

result.criteriaWeights = criteriaWeights;
result.criteriaCR = criteriaCR;
result.ahpWeights = ahpWeights;
result.fuzzyScores = fuzzyScores;
result.fuzzyWeights = fuzzyWeights;
result.validationSummary = validationSummary;
end

function gm = getGeomean(raw, sectionName, itemName)
values = raw.value(raw.section == sectionName & raw.item == itemName);
if isempty(values)
    error("설문 문항을 찾지 못했습니다: %s / %s", sectionName, itemName);
end
gm = exp(mean(log(values), "omitnan"));
end

function [weights, cr] = ahpWeightsFromPairs(items, leftItems, rightItems, values)
% 쌍대비교 행렬을 만들고 행 기하평균법으로 가중치를 계산한다.
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
% 두 항목 비교에서 왼쪽/오른쪽 가중치를 계산한다.
if ~isfinite(value) || value <= 0
    error("2항목 AHP 값이 유효하지 않습니다.");
end
weights = [value; 1.0] / (value + 1.0);
end

function metrics = buildLocalMetricMatrices(pof, years)
% PoF 출력에서 로컬 PI용 6개 하위지표 행렬을 만든다.
requiredBase = ["cof_safety_kkrw", "cof_environment_adjusted_kkrw"];
for i = 1:numel(requiredBase)
    if ~ismember(requiredBase(i), string(pof.Properties.VariableNames))
        error("PoF 출력 파일에 필요한 컬럼이 없습니다: %s", requiredBase(i));
    end
end

nAssets = height(pof);
nYears = numel(years);
metrics.metricIds = [
    "investment_value"
    "investment_efficiency"
    "saidi_reduction"
    "failure_probability"
    "safety_effect"
    "environment_effect"
    ];
metrics.metricNames = [
    "투자가치"
    "투자효율"
    "SAIDI저감"
    "고장예측저감"
    "안전영향"
    "환경영향"
    ];

for m = 1:numel(metrics.metricIds)
    metrics.(metrics.metricIds(m)) = zeros(nAssets, nYears);
end
metrics.replacement_cost = zeros(nAssets, nYears);
metrics.risk_reduction = zeros(nAssets, nYears);
metrics.age = zeros(nAssets, nYears);

for y = 1:nYears
    year = years(y);
    pofYear = cleanNonnegative(pof.(sprintf("pof_%d", year)));

    metrics.investment_value(:, y) = cleanNonnegative(pof.(sprintf("investment_value_%d_kkrw", year)));
    metrics.investment_efficiency(:, y) = cleanNonnegative(pof.(sprintf("investment_efficiency_%d", year)));
    metrics.saidi_reduction(:, y) = cleanNonnegative(pof.(sprintf("saidi_%d_min", year)));
    metrics.failure_probability(:, y) = pofYear;
    metrics.safety_effect(:, y) = pofYear .* cleanNonnegative(pof.cof_safety_kkrw);
    metrics.environment_effect(:, y) = pofYear .* cleanNonnegative(pof.cof_environment_adjusted_kkrw);

    metrics.replacement_cost(:, y) = cleanNonnegative(pof.(sprintf("replacement_cost_%d_kkrw", year)));
    metrics.risk_reduction(:, y) = cleanNonnegative(pof.(sprintf("risk_reduction_%d_kkrw", year)));
    metrics.age(:, y) = cleanNonnegative(pof.(sprintf("age_%d", year)));
end
end

function x = cleanNonnegative(x)
x = double(x);
x(~isfinite(x)) = 0;
x = max(x, 0);
end

function [scores, summaryTable] = normalizeMetricMatrices(metrics, years, scalePercentile)
% 각 하위지표를 전체 자산·전체 연도 기준 P95로 정규화한다.
rows = {};
scores = struct();
for m = 1:numel(metrics.metricIds)
    metricId = metrics.metricIds(m);
    metricName = metrics.metricNames(m);
    X = metrics.(metricId);
    scale = percentileScale(X(:), scalePercentile);
    S = X / scale;
    S(~isfinite(S)) = 0;
    S = max(min(S, 1), 0);
    scores.(metricId) = S;
    rows(end+1, :) = {metricId, metricName, scalePercentile, scale, min(X(:)), max(X(:)), mean(X(:), "omitnan")}; %#ok<AGROW>
end
summaryTable = cell2table(rows, ...
    'VariableNames', {'metric_id', 'metric_name', 'scale_percentile', 'scale_value', 'raw_min', 'raw_max', 'raw_mean'});
summaryTable.years = repmat(strjoin(string(years), ","), height(summaryTable), 1);
end

function scale = percentileScale(x, percentileValue)
% Toolbox 의존성을 피하기 위해 직접 백분위수를 계산한다.
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

function [piWide, piLong, piSummaryYear, piSummaryTypeYear] = buildLocalPiTables( ...
    pof, metrics, scores, weightResult, years, candidateMask)

nAssets = height(pof);
nYears = numel(years);
metricIds = metrics.metricIds;

ahpWeight = zeros(numel(metricIds), 1);
fuzzyWeight = zeros(numel(metricIds), 1);
for m = 1:numel(metricIds)
    idxA = string(weightResult.ahpWeights.metric_id) == metricIds(m);
    idxF = string(weightResult.fuzzyWeights.metric_id) == metricIds(m);
    ahpWeight(m) = weightResult.ahpWeights.weight(idxA);
    fuzzyWeight(m) = weightResult.fuzzyWeights.fuzzy_adjusted_weight(idxF);
end

piAHP = zeros(nAssets, nYears);
piFuzzy = zeros(nAssets, nYears);
for m = 1:numel(metricIds)
    S = scores.(metricIds(m));
    piAHP = piAHP + ahpWeight(m) * S;
    piFuzzy = piFuzzy + fuzzyWeight(m) * S;
end

piWide = pof(:, {'asset_id', 'asset_type', 'asset_code', 'asset_label', 'asset_group'});
piWide.candidate_top30_current = candidateMask;

for y = 1:nYears
    year = years(y);
    for m = 1:numel(metricIds)
        metricId = metricIds(m);
        piWide.(sprintf("score_%s_%d", metricId, year)) = scores.(metricId)(:, y);
    end
    piWide.(sprintf("local_pi_ahp_%d", year)) = piAHP(:, y);
    piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year)) = piFuzzy(:, y);
end

nLongRows = nAssets * nYears;
long_asset_id = strings(nLongRows, 1);
long_asset_type = strings(nLongRows, 1);
long_asset_code = strings(nLongRows, 1);
long_asset_label = strings(nLongRows, 1);
long_asset_group = strings(nLongRows, 1);
long_year = zeros(nLongRows, 1);
long_candidate = false(nLongRows, 1);
long_age = zeros(nLongRows, 1);
long_cost = zeros(nLongRows, 1);
long_risk_reduction = zeros(nLongRows, 1);
long_investment_value = zeros(nLongRows, 1);
long_investment_efficiency = zeros(nLongRows, 1);
long_saidi = zeros(nLongRows, 1);
long_pof = zeros(nLongRows, 1);
long_safety_effect = zeros(nLongRows, 1);
long_environment_effect = zeros(nLongRows, 1);
long_score_investment_value = zeros(nLongRows, 1);
long_score_investment_efficiency = zeros(nLongRows, 1);
long_score_saidi_reduction = zeros(nLongRows, 1);
long_score_failure_probability = zeros(nLongRows, 1);
long_score_safety_effect = zeros(nLongRows, 1);
long_score_environment_effect = zeros(nLongRows, 1);
long_local_pi_ahp = zeros(nLongRows, 1);
long_local_pi_fuzzy_adjusted = zeros(nLongRows, 1);

base_asset_id = string(pof.asset_id);
base_asset_type = string(pof.asset_type);
base_asset_code = string(pof.asset_code);
base_asset_label = string(pof.asset_label);
base_asset_group = string(pof.asset_group);

for y = 1:nYears
    rowStart = (y - 1) * nAssets + 1;
    rowEnd = rowStart + nAssets - 1;
    rr = rowStart:rowEnd;

    long_asset_id(rr) = base_asset_id;
    long_asset_type(rr) = base_asset_type;
    long_asset_code(rr) = base_asset_code;
    long_asset_label(rr) = base_asset_label;
    long_asset_group(rr) = base_asset_group;
    long_year(rr) = years(y);
    long_candidate(rr) = candidateMask;
    long_age(rr) = metrics.age(:, y);
    long_cost(rr) = metrics.replacement_cost(:, y);
    long_risk_reduction(rr) = metrics.risk_reduction(:, y);
    long_investment_value(rr) = metrics.investment_value(:, y);
    long_investment_efficiency(rr) = metrics.investment_efficiency(:, y);
    long_saidi(rr) = metrics.saidi_reduction(:, y);
    long_pof(rr) = metrics.failure_probability(:, y);
    long_safety_effect(rr) = metrics.safety_effect(:, y);
    long_environment_effect(rr) = metrics.environment_effect(:, y);
    long_score_investment_value(rr) = scores.investment_value(:, y);
    long_score_investment_efficiency(rr) = scores.investment_efficiency(:, y);
    long_score_saidi_reduction(rr) = scores.saidi_reduction(:, y);
    long_score_failure_probability(rr) = scores.failure_probability(:, y);
    long_score_safety_effect(rr) = scores.safety_effect(:, y);
    long_score_environment_effect(rr) = scores.environment_effect(:, y);
    long_local_pi_ahp(rr) = piAHP(:, y);
    long_local_pi_fuzzy_adjusted(rr) = piFuzzy(:, y);
end

piLong = table( ...
    long_asset_id, long_asset_type, long_asset_code, long_asset_label, long_asset_group, ...
    long_year, long_candidate, long_age, long_cost, long_risk_reduction, ...
    long_investment_value, long_investment_efficiency, long_saidi, long_pof, ...
    long_safety_effect, long_environment_effect, ...
    long_score_investment_value, long_score_investment_efficiency, ...
    long_score_saidi_reduction, long_score_failure_probability, ...
    long_score_safety_effect, long_score_environment_effect, ...
    long_local_pi_ahp, long_local_pi_fuzzy_adjusted, ...
    'VariableNames', { ...
    'asset_id', 'asset_type', 'asset_code', 'asset_label', 'asset_group', ...
    'year', 'candidate_top30_current', 'age', 'replacement_cost_kkrw', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'investment_efficiency', 'saidi_min', 'pof', ...
    'safety_effect_kkrw', 'environment_effect_kkrw', ...
    'score_investment_value', 'score_investment_efficiency', ...
    'score_saidi_reduction', 'score_failure_probability', ...
    'score_safety_effect', 'score_environment_effect', ...
    'local_pi_ahp', 'local_pi_fuzzy_adjusted'});

summaryRows = {};
for y = 1:nYears
    year = years(y);
    summaryRows(end+1, :) = { ...
        year, ...
        sum(piAHP(:, y), "omitnan"), mean(piAHP(:, y), "omitnan"), ...
        sum(piFuzzy(:, y), "omitnan"), mean(piFuzzy(:, y), "omitnan"), ...
        sum(piAHP(candidateMask, y), "omitnan"), sum(piFuzzy(candidateMask, y), "omitnan"), ...
        mean(scores.investment_value(:, y), "omitnan"), ...
        mean(scores.investment_efficiency(:, y), "omitnan"), ...
        mean(scores.saidi_reduction(:, y), "omitnan"), ...
        mean(scores.failure_probability(:, y), "omitnan"), ...
        mean(scores.safety_effect(:, y), "omitnan"), ...
        mean(scores.environment_effect(:, y), "omitnan")}; %#ok<AGROW>
end
piSummaryYear = cell2table(summaryRows, 'VariableNames', { ...
    'year', 'sum_local_pi_ahp', 'avg_local_pi_ahp', ...
    'sum_local_pi_fuzzy_adjusted', 'avg_local_pi_fuzzy_adjusted', ...
    'candidate_sum_local_pi_ahp', 'candidate_sum_local_pi_fuzzy_adjusted', ...
    'avg_score_investment_value', 'avg_score_investment_efficiency', ...
    'avg_score_saidi_reduction', 'avg_score_failure_probability', ...
    'avg_score_safety_effect', 'avg_score_environment_effect'});

typeRows = {};
assetTypes = unique(base_asset_type, "stable");
for y = 1:nYears
    for t = 1:numel(assetTypes)
        idx = base_asset_type == assetTypes(t);
        typeRows(end+1, :) = { ...
            years(y), assetTypes(t), base_asset_label(find(idx, 1)), base_asset_group(find(idx, 1)), ...
            sum(idx), sum(candidateMask(idx)), ...
            mean(piAHP(idx, y), "omitnan"), sum(piAHP(idx, y), "omitnan"), ...
            mean(piFuzzy(idx, y), "omitnan"), sum(piFuzzy(idx, y), "omitnan")}; %#ok<AGROW>
    end
end
piSummaryTypeYear = cell2table(typeRows, 'VariableNames', { ...
    'year', 'asset_type', 'asset_label', 'asset_group', ...
    'asset_count', 'candidate_count', ...
    'avg_local_pi_ahp', 'sum_local_pi_ahp', ...
    'avg_local_pi_fuzzy_adjusted', 'sum_local_pi_fuzzy_adjusted'});
end
