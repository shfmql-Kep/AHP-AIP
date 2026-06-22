%% BWM 기반 설비 단위 PI 산출 알고리즘
% 목적:
% 1) 기존 AHP/Fuzzy 설문 응답을 바탕으로 응답자별 선호구조를 읽는다.
% 2) 각 응답자의 AHP 지표 가중치에서 Best/Worst 기준을 도출한다.
% 3) Best-to-Others, Others-to-Worst 비교값을 BWM 1~9 척도로 재구성한다.
% 4) 동일한 PoF 출력과 동일한 정규화 점수에 BWM 가중치를 적용하여 PI를 산정한다.
%
% 주의:
% - 본 파일은 독립 BWM 설문 결과가 아니라, 기존 AHP 응답 기반 BWM 재구성 비교군이다.
% - 논문 본문에서는 "BWM 전용 설문"이 아니라 "AHP 응답 기반 BWM 재구성 비교"로 설명해야 한다.

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
outputFile = fullfile(outputDir, "bwm_pi_matlab.xlsx");
runLogFile = fullfile(outputDir, "bwm_pi_matlab.log");

years = 2026:2030;
scalePercentile = 95;
candidateFlag = "candidate_top30_current";

if isfile(runLogFile)
    delete(runLogFile);
end
diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off")); %#ok<NASGU>

fprintf("BWM 기반 설비 단위 PI 산출 시작\n");
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
rawSheet = getLastSheetName(surveyFile);
raw = readtable(surveyFile, "Sheet", rawSheet, "VariableNamingRule", "preserve");

nAssets = height(pof);
fprintf("자산 수: %d\n", nAssets);
fprintf("설문 RAW 시트: %s, 행 수: %d\n", rawSheet, height(raw));

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

%% 2. BWM 가중치 산정
weightResult = calculateBwmWeights(raw);
fprintf("BWM 응답자 수: %d\n", height(weightResult.respondentWeights));
fprintf("BWM 최종 가중치 합계: %.6f\n", sum(weightResult.bwmWeights.weight));
fprintf("BWM 평균 xi: %.6f\n", mean(weightResult.respondentWeights.xi, "omitnan"));

%% 3. 6개 하위지표 구성 및 정규화
metrics = buildLocalMetricMatrices(pof, years);
[scores, normalizationSummary] = normalizeMetricMatrices(metrics, years, scalePercentile);
metricDefinition = buildMetricDefinitionTable();

%% 4. BWM PI 산출
[piWide, piLong, piSummaryYear, piSummaryTypeYear] = buildBwmPiTables( ...
    pof, metrics, scores, weightResult, years, candidateMask);

fprintf("BWM PI 산출 완료: wide %d행, long %d행\n", height(piWide), height(piLong));

%% 5. 결과 저장
if isfile(outputFile)
    delete(outputFile);
end

writetable(metricDefinition, outputFile, "Sheet", "metric_definition");
writetable(weightResult.bwmWeights, outputFile, "Sheet", "bwm_weights");
writetable(weightResult.respondentWeights, outputFile, "Sheet", "respondent_bwm_weights");
writetable(weightResult.comparisonTable, outputFile, "Sheet", "bwm_comparisons");
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

function sheetName = getLastSheetName(filePath)
% 한글 시트명을 코드에 직접 쓰지 않기 위해 마지막 시트를 사용한다.
names = sheetnames(filePath);
sheetName = string(names(end));
end

function assetMap = buildAssetMap()
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

function result = calculateBwmWeights(raw)
requiredVars = ["respondent", "section", "item", "value"];
for i = 1:numel(requiredVars)
    if ~ismember(requiredVars(i), string(raw.Properties.VariableNames))
        error("설문 RAW 시트에 필요한 컬럼이 없습니다: %s", requiredVars(i));
    end
end

raw.section = string(raw.section);
raw.item = string(raw.item);
raw.value = double(raw.value);

if any(~isfinite(raw.value)) || any(raw.value <= 0)
    error("설문 응답값에 누락 또는 비양수 값이 있습니다.");
end

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
    "SAIDI 저감"
    "고장예측 저감"
    "안전 영향"
    "환경 영향"
    ];

respondents = unique(raw.respondent, "stable");
W = zeros(numel(respondents), numel(metricIds));
Xi = zeros(numel(respondents), 1);
bestMetric = strings(numel(respondents), 1);
worstMetric = strings(numel(respondents), 1);
comparisonRows = {};

for r = 1:numel(respondents)
    respondentId = respondents(r);
    rraw = raw(raw.respondent == respondentId, :);
    ahpWeight = respondentAHPWeights(rraw);

    [bwmWeight, xi, bestIdx, worstIdx, bestToOthers, othersToWorst] = bwmFromSourceWeights(ahpWeight);
    W(r, :) = bwmWeight(:)';
    Xi(r) = xi;
    bestMetric(r) = metricIds(bestIdx);
    worstMetric(r) = metricIds(worstIdx);

    for m = 1:numel(metricIds)
        comparisonRows(end+1, :) = { ...
            respondentId, metricIds(m), metricNames(m), ...
            metricIds(bestIdx), metricIds(worstIdx), ...
            bestToOthers(m), othersToWorst(m), ahpWeight(m), bwmWeight(m), xi}; %#ok<AGROW>
    end
end

geoWeight = exp(mean(log(max(W, eps)), 1));
geoWeight = geoWeight(:) / sum(geoWeight);

bwmWeights = table(metricIds, metricNames, geoWeight, ...
    'VariableNames', {'metric_id', 'metric_name', 'weight'});

respondentWeights = table(respondents, bestMetric, worstMetric, Xi, ...
    'VariableNames', {'respondent', 'best_metric_id', 'worst_metric_id', 'xi'});
for m = 1:numel(metricIds)
    respondentWeights.(sprintf("w_%s", metricIds(m))) = W(:, m);
end

comparisonTable = cell2table(comparisonRows, 'VariableNames', { ...
    'respondent', 'metric_id', 'metric_name', 'best_metric_id', 'worst_metric_id', ...
    'best_to_others', 'others_to_worst', 'source_ahp_weight', 'bwm_weight', 'xi'});

validationSummary = table( ...
    ["respondent_count"; "mean_xi"; "max_xi"; "weight_sum"; "source"], ...
    [numel(respondents); mean(Xi, "omitnan"); max(Xi); sum(geoWeight); NaN], ...
    ["명"; "BWM 평균 오차"; "BWM 최대 오차"; "최종 가중치 합"; "AHP 응답 기반 BWM 재구성"], ...
    'VariableNames', {'item', 'value', 'note'});

result.bwmWeights = bwmWeights;
result.respondentWeights = respondentWeights;
result.comparisonTable = comparisonTable;
result.validationSummary = validationSummary;
end

function weights = respondentAHPWeights(rraw)
criteriaItems = ["경제성", "신뢰도", "안전·환경"];
criteriaLeft = ["경제성"; "경제성"; "신뢰도"];
criteriaRight = ["신뢰도"; "안전·환경"; "안전·환경"];
criteriaValues = [
    getValue(rraw, "AHP기준", "경제/신뢰")
    getValue(rraw, "AHP기준", "경제/안전환경")
    getValue(rraw, "AHP기준", "신뢰/안전환경")
    ];
[criteriaWeights, ~] = ahpWeightsFromPairs(criteriaItems, criteriaLeft, criteriaRight, criteriaValues);

metricWeights = zeros(6, 1);

econLocal = twoItemWeights(getValue(rraw, "AHP하위", "NPV/BCR"));
relLocal = twoItemWeights(getValue(rraw, "AHP하위", "SAIDI/고장"));
seLocal = twoItemWeights(getValue(rraw, "AHP하위", "안전/환경"));

metricWeights(1:2) = criteriaWeights(1) * econLocal;
metricWeights(3:4) = criteriaWeights(2) * relLocal;
metricWeights(5:6) = criteriaWeights(3) * seLocal;
weights = metricWeights / sum(metricWeights);
end

function value = getValue(raw, sectionName, itemName)
idx = raw.section == sectionName & raw.item == itemName;
if ~any(idx)
    error("응답값을 찾을 수 없습니다: %s / %s", sectionName, itemName);
end
value = double(raw.value(find(idx, 1)));
if ~isfinite(value) || value <= 0
    error("응답값이 유효하지 않습니다: %s / %s", sectionName, itemName);
end
end

function [weights, cr] = ahpWeightsFromPairs(items, leftItems, rightItems, values)
n = numel(items);
A = eye(n);
for k = 1:numel(values)
    leftIdx = find(items == leftItems(k), 1);
    rightIdx = find(items == rightItems(k), 1);
    if isempty(leftIdx) || isempty(rightIdx)
        error("AHP 항목 매핑 실패: %s / %s", leftItems(k), rightItems(k));
    end
    A(leftIdx, rightIdx) = values(k);
    A(rightIdx, leftIdx) = 1 / values(k);
end
geoMean = exp(mean(log(A), 2));
weights = geoMean / sum(geoMean);

lambdaMax = mean((A * weights) ./ weights);
ci = (lambdaMax - n) / max(n - 1, 1);
riTable = containers.Map({1, 2, 3, 4, 5, 6}, {0, 0, 0.58, 0.90, 1.12, 1.24});
if riTable(n) == 0
    cr = 0;
else
    cr = ci / riTable(n);
end
end

function weights = twoItemWeights(value)
weights = [value; 1.0] / (value + 1.0);
end

function [bwmWeight, xi, bestIdx, worstIdx, bestToOthers, othersToWorst] = bwmFromSourceWeights(sourceWeight)
% 기존 응답에서 얻은 가중치를 BWM 1~9 비교척도로 변환한다.
% 정확한 비율을 그대로 쓰면 AHP와 BWM이 거의 동일해지므로,
% BWM의 표준 응답척도에 맞춰 가장 가까운 1~9 정수로 압축한다.
n = numel(sourceWeight);
[~, bestIdx] = max(sourceWeight);
[~, worstIdx] = min(sourceWeight);

bestToOthers = round(sourceWeight(bestIdx) ./ sourceWeight);
othersToWorst = round(sourceWeight ./ sourceWeight(worstIdx));
bestToOthers = min(max(bestToOthers, 1), 9);
othersToWorst = min(max(othersToWorst, 1), 9);
bestToOthers(bestIdx) = 1;
othersToWorst(worstIdx) = 1;

[bwmWeight, xi] = solveLinearBwm(bestIdx, worstIdx, bestToOthers, othersToWorst);
end

function [w, xi] = solveLinearBwm(bestIdx, worstIdx, bestToOthers, othersToWorst)
n = numel(bestToOthers);
f = [zeros(n, 1); 1];
A = [];
b = [];

for j = 1:n
    row = zeros(1, n + 1);
    row(bestIdx) = 1;
    row(j) = row(j) - bestToOthers(j);
    row(end) = -1;
    A(end+1, :) = row; %#ok<AGROW>
    b(end+1, 1) = 0; %#ok<AGROW>

    row = zeros(1, n + 1);
    row(bestIdx) = -1;
    row(j) = row(j) + bestToOthers(j);
    row(end) = -1;
    A(end+1, :) = row; %#ok<AGROW>
    b(end+1, 1) = 0; %#ok<AGROW>

    row = zeros(1, n + 1);
    row(j) = 1;
    row(worstIdx) = row(worstIdx) - othersToWorst(j);
    row(end) = -1;
    A(end+1, :) = row; %#ok<AGROW>
    b(end+1, 1) = 0; %#ok<AGROW>

    row = zeros(1, n + 1);
    row(j) = -1;
    row(worstIdx) = row(worstIdx) + othersToWorst(j);
    row(end) = -1;
    A(end+1, :) = row; %#ok<AGROW>
    b(end+1, 1) = 0; %#ok<AGROW>
end

Aeq = [ones(1, n), 0];
beq = 1;
lb = [zeros(n, 1); 0];
ub = [];

try
    opts = optimoptions("linprog", "Display", "none");
    [x, ~, exitflag] = linprog(f, A, b, Aeq, beq, lb, ub, opts);
    if exitflag <= 0 || isempty(x)
        error("linprog failed");
    end
    w = x(1:n);
    xi = x(end);
catch
    % Optimization Toolbox가 없거나 실패하면 비교척도의 기하평균 근사로 대체한다.
    approx = sqrt((1 ./ bestToOthers(:)) .* othersToWorst(:));
    approx(~isfinite(approx) | approx <= 0) = eps;
    w = approx / sum(approx);
    xi = NaN;
end

w = max(w(:), 0);
if sum(w) <= 0
    w = ones(n, 1) / n;
else
    w = w / sum(w);
end
end

function metrics = buildLocalMetricMatrices(pof, years)
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
    "SAIDI 저감"
    "고장예측 저감"
    "안전 영향"
    "환경 영향"
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

function [piWide, piLong, piSummaryYear, piSummaryTypeYear] = buildBwmPiTables( ...
    pof, metrics, scores, weightResult, years, candidateMask)

nAssets = height(pof);
nYears = numel(years);
metricIds = metrics.metricIds;

bwmWeight = zeros(numel(metricIds), 1);
for m = 1:numel(metricIds)
    idx = string(weightResult.bwmWeights.metric_id) == metricIds(m);
    bwmWeight(m) = weightResult.bwmWeights.weight(idx);
end

piBwm = zeros(nAssets, nYears);
for m = 1:numel(metricIds)
    piBwm = piBwm + bwmWeight(m) * scores.(metricIds(m));
end

piWide = pof(:, {'asset_id', 'asset_type', 'asset_code', 'asset_label', 'asset_group'});
piWide.candidate_top30_current = candidateMask;
for y = 1:nYears
    year = years(y);
    for m = 1:numel(metricIds)
        metricId = metricIds(m);
        piWide.(sprintf("score_%s_%d", metricId, year)) = scores.(metricId)(:, y);
    end
    piWide.(sprintf("local_pi_bwm_%d", year)) = piBwm(:, y);
    % 기존 시뮬레이션 코드를 그대로 재사용하기 위한 호환 컬럼이다.
    piWide.(sprintf("local_pi_ahp_%d", year)) = piBwm(:, y);
    piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year)) = piBwm(:, y);
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
long_local_pi_bwm = zeros(nLongRows, 1);

base_asset_id = string(pof.asset_id);
base_asset_type = string(pof.asset_type);
base_asset_code = string(pof.asset_code);
base_asset_label = string(pof.asset_label);
base_asset_group = string(pof.asset_group);

for y = 1:nYears
    rr = ((y - 1) * nAssets + 1):(y * nAssets);
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
    long_local_pi_bwm(rr) = piBwm(:, y);
end

piLong = table( ...
    long_asset_id, long_asset_type, long_asset_code, long_asset_label, long_asset_group, ...
    long_year, long_candidate, long_age, long_cost, long_risk_reduction, ...
    long_investment_value, long_investment_efficiency, long_saidi, long_pof, ...
    long_safety_effect, long_environment_effect, long_local_pi_bwm, long_local_pi_bwm, long_local_pi_bwm, ...
    'VariableNames', { ...
    'asset_id', 'asset_type', 'asset_code', 'asset_label', 'asset_group', ...
    'year', 'candidate_top30_current', 'age', 'replacement_cost_kkrw', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'investment_efficiency', 'saidi_min', 'pof', ...
    'safety_effect_kkrw', 'environment_effect_kkrw', ...
    'local_pi_bwm', 'local_pi_ahp', 'local_pi_fuzzy_adjusted'});

summaryRows = {};
for y = 1:nYears
    summaryRows(end+1, :) = { ...
        years(y), sum(piBwm(:, y), "omitnan"), mean(piBwm(:, y), "omitnan"), ...
        sum(piBwm(candidateMask, y), "omitnan")}; %#ok<AGROW>
end
piSummaryYear = cell2table(summaryRows, 'VariableNames', { ...
    'year', 'sum_local_pi_bwm', 'avg_local_pi_bwm', 'candidate_sum_local_pi_bwm'});

typeRows = {};
assetTypes = unique(base_asset_type, "stable");
for y = 1:nYears
    for t = 1:numel(assetTypes)
        idx = base_asset_type == assetTypes(t);
        typeRows(end+1, :) = { ...
            years(y), assetTypes(t), base_asset_label(find(idx, 1)), base_asset_group(find(idx, 1)), ...
            sum(idx), sum(candidateMask(idx)), ...
            mean(piBwm(idx, y), "omitnan"), sum(piBwm(idx, y), "omitnan")}; %#ok<AGROW>
    end
end
piSummaryTypeYear = cell2table(typeRows, 'VariableNames', { ...
    'year', 'asset_type', 'asset_label', 'asset_group', ...
    'asset_count', 'candidate_count', 'avg_local_pi_bwm', 'sum_local_pi_bwm'});
end
