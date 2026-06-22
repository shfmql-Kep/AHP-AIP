%% 박사논문 시뮬레이션 챕터 v2 - Matlab 모델
% 순서:
% 1. PoF_output 기반 개별설비 최적화: Risk 그리디, 투자가치 그리디, 투자가치 ILP, 투자가치 GA
% 2. 개별설비별 결과 표와 그래프 작성
% 3. 개별설비 결과 합산 비교
% 4. PI 기반 개별설비 최적화: PI 그리디, PI ILP, PI GA
% 5. PI 개별설비별 결과 표와 그래프 작성
% 6. 투자가치 최적화와 PI 최적화 합산 비교
% 7. 통합설비 최적화 2안 수행
%    - A안: 개별설비 PI 최적화 결과 후보군에 설비유형 가중치 적용 후 전체설비 기준 재선정
%    - B안: 전체 후보군에 PI_통합을 사전 계산한 뒤 전체설비 기준 최적화
% 8. 최종 비교표 작성

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputRoot = fullfile(baseDir, "outputs");
runStamp = char(string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
runDir = fullfile(outputRoot, ['simulation_chapter_v2_matlab_' runStamp]);
figureDir = fullfile(runDir, "figures");
selectedDir = fullfile(runDir, "selected_assets");
checkpointDir = fullfile(runDir, "checkpoints");
mkdir(runDir); mkdir(figureDir); mkdir(selectedDir); mkdir(checkpointDir);

diary(fullfile(runDir, "simulation_chapter_v2_matlab.log"));
diary on;
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

years = [2026 2027 2028 2029 2030];
assetTypes = ["pole_transformer", "ground_transformer", "overhead_switch", ...
    "underground_switch", "overhead_line", "underground_cable"];
assetLabels = ["주상변압기", "지상변압기", "가공개폐기", "지중개폐기", "가공배전선로", "지중케이블"];
assetTypeFilter = strtrim(string(getenv("SIM_ASSET_TYPES")));
if strlength(assetTypeFilter) > 0
    requestedTypes = strtrim(split(assetTypeFilter, ","));
    keep = ismember(assetTypes, requestedTypes);
    assetTypes = assetTypes(keep);
    assetLabels = assetLabels(keep);
    if isempty(assetTypes)
        error("SIM_ASSET_TYPES에 지정한 설비유형이 없습니다: %s", assetTypeFilter);
    end
end

budgetRate = 0.04;
capacityRate = 0.05;
discountRate = 0.05;
candidateQuantile = 0.70;
gaGenerations = readEnvNumber("SIM_GA_GENERATIONS", 200);
gaPopulation = readEnvNumber("SIM_GA_POPULATION", 80);
gaMutationRate = readEnvNumber("SIM_GA_MUTATION_RATE", 0.015);
randomSeed = 20260620;
rng(randomSeed);

fprintf("=== 박사논문 시뮬레이션 챕터 v2 - Matlab 모델 시작 ===\n");
fprintf("runDir: %s\n", runDir);
fprintf("GA generations=%d, population=%d, mutation=%.4f\n", gaGenerations, gaPopulation, gaMutationRate);
writeStatus(runDir, "시뮬레이션 시작");

%% 0. 입력 로드
pofFile = resolveInputFile("SIM_POF_FILE", fullfile(dataDir, "pof_5yr_output.xlsx"));
localPiFile = resolveInputFile("SIM_LOCAL_PI_FILE", fullfile(outputRoot, "local_pi_matlab.xlsx"));
integratedPiFile = resolveInputFile("SIM_INTEGRATED_PI_FILE", fullfile(outputRoot, "integrated_pi_matlab.xlsx"));

fprintf("PoF 입력 파일: %s\n", pofFile);
fprintf("Local PI 입력 파일: %s\n", localPiFile);
fprintf("Integrated PI 입력 파일: %s\n", integratedPiFile);

pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
localPi = readtable(localPiFile, "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
integratedPi = readtable(integratedPiFile, "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");

if height(pof) ~= height(localPi) || any(string(pof.asset_id) ~= string(localPi.asset_id))
    error("PoF 출력과 Local PI 파일의 asset_id가 일치하지 않습니다.");
end
if height(pof) ~= height(integratedPi) || any(string(pof.asset_id) ~= string(integratedPi.asset_id))
    error("PoF 출력과 Integrated PI 파일의 asset_id가 일치하지 않습니다.");
end

pof.asset_type_label = mapAssetLabels(string(pof.asset_type), assetTypes, assetLabels);
pof.w_type_alpha_0_5 = integratedPi.w_type_alpha_0_5;
pof.w_type_expert = integratedPi.w_type_expert;
for y = 1:numel(years)
    year = years(y);
    pof.(sprintf("local_pi_%d", year)) = localPi.(sprintf("local_pi_ahp_%d", year));
    pof.(sprintf("local_pi_fuzzy_%d", year)) = localPi.(sprintf("local_pi_fuzzy_adjusted_%d", year));
    pof.(sprintf("integrated_pi_%d", year)) = integratedPi.(sprintf("integrated_pi_ahp_alpha_0_5_%d", year));
end

nAssets = height(pof);
candidateMask = buildTypeCandidateMask(pof, assetTypes, candidateQuantile);
pof.candidate_type_top30_current = candidateMask;

[candidateSummary, budgetSummary] = buildCandidateAndBudgetSummary( ...
    pof, assetTypes, assetLabels, candidateMask, years, budgetRate, capacityRate, discountRate);
writetable(candidateSummary, fullfile(runDir, "simulation_chapter_v2_results.xlsx"), "Sheet", "01_candidate_summary");
writetable(budgetSummary, fullfile(runDir, "simulation_chapter_v2_results.xlsx"), "Sheet", "01_budget_summary");

configTable = table( ...
    string(runStamp), budgetRate, capacityRate, discountRate, candidateQuantile, ...
    gaGenerations, gaPopulation, gaMutationRate, randomSeed, ...
    'VariableNames', {'run_stamp', 'budget_rate', 'capacity_rate', 'discount_rate', ...
    'candidate_quantile', 'ga_generations', 'ga_population', 'ga_mutation_rate', 'random_seed'});
writetable(configTable, fullfile(runDir, "simulation_chapter_v2_results.xlsx"), "Sheet", "00_run_config");

%% 1~3. PoF 기반 개별설비 Risk·투자가치 최적화
fprintf("\n[1~3단계] PoF 기반 개별설비 Risk·투자가치 최적화 시작\n");
valueMethods = ["risk_greedy", "investment_value_greedy", "investment_value_ilp", "investment_value_ga"];
[valueChoices, valueTypeAnnual, valueTypeTotal, valueSelected, valueSolver, valueGaProgress] = runIndividualPhase( ...
    pof, assetTypes, assetLabels, candidateMask, years, budgetRate, capacityRate, discountRate, ...
    valueMethods, "value_phase", gaGenerations, gaPopulation, gaMutationRate, runDir);
[valueCombinedAnnual, valueCombinedTotal, valueCombinedSelected] = combineIndividualChoices( ...
    pof, valueChoices, assetTypes, years, valueMethods, "value_phase", budgetRate, capacityRate, discountRate);
writePhaseCheckpoint(runDir, checkpointDir, "01_value_phase", valueTypeAnnual, valueTypeTotal, ...
    valueCombinedAnnual, valueCombinedTotal, valueSolver, valueGaProgress);
writetable(valueSelected, fullfile(selectedDir, "01_value_type_selected_assets.csv"));
writetable(valueCombinedSelected, fullfile(selectedDir, "01_value_combined_selected_assets.csv"));

%% 4~6. PI 기반 개별설비 최적화
fprintf("\n[4~6단계] PI 기반 개별설비 최적화 시작\n");
piMethods = ["pi_greedy", "pi_ilp", "pi_ga"];
[piChoices, piTypeAnnual, piTypeTotal, piSelected, piSolver, piGaProgress] = runIndividualPhase( ...
    pof, assetTypes, assetLabels, candidateMask, years, budgetRate, capacityRate, discountRate, ...
    piMethods, "pi_phase", gaGenerations, gaPopulation, gaMutationRate, runDir);
[piCombinedAnnual, piCombinedTotal, piCombinedSelected] = combineIndividualChoices( ...
    pof, piChoices, assetTypes, years, piMethods, "pi_phase", budgetRate, capacityRate, discountRate);
writePhaseCheckpoint(runDir, checkpointDir, "02_pi_phase", piTypeAnnual, piTypeTotal, ...
    piCombinedAnnual, piCombinedTotal, piSolver, piGaProgress);
writetable(piSelected, fullfile(selectedDir, "02_pi_type_selected_assets.csv"));
writetable(piCombinedSelected, fullfile(selectedDir, "02_pi_combined_selected_assets.csv"));

%% 7. 통합설비 최적화 2안
fprintf("\n[7단계] 통합설비 최적화 2안 시작\n");
[integratedAnnual, integratedTotal, integratedSelected, integratedSolver, integratedGaProgress] = runIntegratedPhase( ...
    pof, assetTypes, candidateMask, piChoices, years, budgetRate, capacityRate, discountRate, ...
    gaGenerations, gaPopulation, gaMutationRate, runDir);
writePhaseCheckpoint(runDir, checkpointDir, "03_integrated_phase", integratedAnnual, integratedTotal, ...
    table(), table(), integratedSolver, integratedGaProgress);
writetable(integratedSelected, fullfile(selectedDir, "03_integrated_selected_assets.csv"));

%% 8. 최종 비교표와 그래프
fprintf("\n[8단계] 최종 비교표와 그래프 작성\n");
finalComparison = buildFinalComparison(valueCombinedTotal, piCombinedTotal, integratedTotal);
figureManifest = saveSimulationFigures(figureDir, valueCombinedTotal, piCombinedTotal, integratedTotal, valueTypeTotal, piTypeTotal);

resultFile = fullfile(runDir, "simulation_chapter_v2_results.xlsx");
writetable(valueTypeAnnual, resultFile, "Sheet", "02_value_type_annual");
writetable(valueTypeTotal, resultFile, "Sheet", "02_value_type_total");
writetable(valueCombinedAnnual, resultFile, "Sheet", "03_value_combined_annual");
writetable(valueCombinedTotal, resultFile, "Sheet", "03_value_combined_total");
writetable(piTypeAnnual, resultFile, "Sheet", "04_pi_type_annual");
writetable(piTypeTotal, resultFile, "Sheet", "04_pi_type_total");
writetable(piCombinedAnnual, resultFile, "Sheet", "05_pi_combined_annual");
writetable(piCombinedTotal, resultFile, "Sheet", "05_pi_combined_total");
writetable(integratedAnnual, resultFile, "Sheet", "06_integrated_annual");
writetable(integratedTotal, resultFile, "Sheet", "06_integrated_total");
writetable(finalComparison, resultFile, "Sheet", "07_final_comparison");
writetable([valueSolver; piSolver; integratedSolver], resultFile, "Sheet", "08_solver_status");
writetable([valueGaProgress; piGaProgress; integratedGaProgress], resultFile, "Sheet", "09_ga_progress");
writetable(figureManifest, resultFile, "Sheet", "10_figure_manifest");

fprintf("\n=== 시뮬레이션 완료 ===\n");
fprintf("결과 파일: %s\n", resultFile);
fprintf("선택 자산 상세: %s\n", selectedDir);
fprintf("그래프: %s\n", figureDir);

%% =========================================================================
% 로컬 함수
% =========================================================================

function value = readEnvNumber(name, defaultValue)
raw = strtrim(string(getenv(name)));
if strlength(raw) == 0
    value = defaultValue;
else
    parsed = str2double(raw);
    if isnan(parsed)
        value = defaultValue;
    else
        value = parsed;
    end
end
end

function filePath = resolveInputFile(envName, defaultPath)
% 환경변수로 입력 파일을 바꿔 끼울 수 있게 한다.
% 값이 없으면 기존 기본 파일을 사용한다.
raw = strtrim(string(getenv(envName)));
if strlength(raw) == 0
    filePath = defaultPath;
else
    filePath = char(raw);
end
if ~isfile(filePath)
    error("입력 파일을 찾을 수 없습니다. %s = %s", envName, string(filePath));
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
    riskValues = pof.risk_2026_kkrw(idx);
    valueValues = pof.investment_value_2026_kkrw(idx);
    riskThreshold = quantile(riskValues, candidateQuantile);
    valueThreshold = quantile(valueValues, candidateQuantile);
    candidateMask(idx) = riskValues >= riskThreshold | valueValues >= valueThreshold;
end
end

function [candidateSummary, budgetSummary] = buildCandidateAndBudgetSummary( ...
    pof, assetTypes, assetLabels, candidateMask, years, budgetRate, capacityRate, discountRate)
candidateRows = {};
budgetRows = {};
for t = 1:numel(assetTypes)
    typeIdx = find(string(pof.asset_type) == assetTypes(t));
    candidateIdx = typeIdx(candidateMask(typeIdx));
    constraints = buildConstraints(pof, typeIdx, years, budgetRate, capacityRate, discountRate);
    candidateRows(end + 1, :) = {assetTypes(t), assetLabels(t), numel(typeIdx), numel(candidateIdx), ...
        numel(candidateIdx) / numel(typeIdx), sum(pof.replacement_cost_2026_kkrw(typeIdx), "omitnan"), ...
        pof.w_type_alpha_0_5(typeIdx(1)), pof.w_type_expert(typeIdx(1))}; %#ok<AGROW>
    for y = 1:numel(years)
        budgetRows(end + 1, :) = {assetTypes(t), assetLabels(t), years(y), ...
            constraints.budgets(y), constraints.capacities(y)}; %#ok<AGROW>
    end
end
allIdx = (1:height(pof))';
allConstraints = buildConstraints(pof, allIdx, years, budgetRate, capacityRate, discountRate);
for y = 1:numel(years)
    budgetRows(end + 1, :) = {"all", "전체설비", years(y), allConstraints.budgets(y), allConstraints.capacities(y)}; %#ok<AGROW>
end
candidateSummary = cell2table(candidateRows, 'VariableNames', {'asset_type', 'asset_type_label', ...
    'asset_count', 'candidate_count', 'candidate_ratio', 'asset_value_2026_kkrw', ...
    'type_weight_alpha_0_5', 'type_weight_expert'});
budgetSummary = cell2table(budgetRows, 'VariableNames', {'asset_type', 'asset_type_label', ...
    'year', 'budget_kkrw', 'capacity_assets'});
end

function constraints = buildConstraints(pof, assetIdx, years, budgetRate, capacityRate, discountRate)
assetValue = sum(pof.replacement_cost_2026_kkrw(assetIdx), "omitnan");
baseBudget = assetValue * budgetRate;
budgets = zeros(1, numel(years));
for y = 1:numel(years)
    % replacement_cost_YEAR_kkrw는 기준년도 현재가치로 할인된 비용이므로,
    % 예산도 같은 할인율을 적용한 현재가치 기준으로 맞춘다.
    budgets(y) = baseBudget / ((1 + discountRate) ^ (y - 1));
end
constraints.budgets = budgets;
constraints.capacities = repmat(max(1, ceil(numel(assetIdx) * capacityRate)), 1, numel(years));
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

function [choices, typeAnnual, typeTotal, selectedAssets, solverStatus, gaProgress] = runIndividualPhase( ...
    pof, assetTypes, assetLabels, candidateMask, years, budgetRate, capacityRate, discountRate, ...
    methods, phaseName, gaGenerations, gaPopulation, gaMutationRate, runDir)

nAssets = height(pof);
choices = struct();
annualParts = {};
totalParts = {};
selectedParts = {};
solverRows = {};
progressParts = {};

for t = 1:numel(assetTypes)
    typeIdxAll = find(string(pof.asset_type) == assetTypes(t));
    typeIdxCandidate = typeIdxAll(candidateMask(typeIdxAll));
    constraints = buildConstraints(pof, typeIdxAll, years, budgetRate, capacityRate, discountRate);
    mats = buildMatrices(pof, typeIdxCandidate, years);
    fprintf("[%s] %s 후보 %d / 전체 %d\n", phaseName, assetLabels(t), numel(typeIdxCandidate), numel(typeIdxAll));

    for m = 1:numel(methods)
        method = methods(m);
        [objectiveName, scoreMat] = getScoreMatrix(method, mats);
        fprintf("[%s] %s / %s 시작\n", phaseName, assetLabels(t), method);
        writeStatus(runDir, sprintf("%s | %s | %s 시작", phaseName, assetLabels(t), method));
        tic;
        if endsWith(method, "greedy")
            localChoice = runGreedy(scoreMat, mats, constraints);
            solverInfo = struct("solver", "greedy", "exitflag", NaN, "message", "greedy");
            progress = table();
        elseif endsWith(method, "ilp")
            [localChoice, solverInfo] = runIlp(scoreMat, mats, constraints);
            progress = table();
        elseif endsWith(method, "ga")
            [localChoice, progress] = runGa(scoreMat, mats, constraints, gaGenerations, gaPopulation, gaMutationRate);
            solverInfo = struct("solver", "custom_ga", "exitflag", NaN, "message", "GA 200 generations");
        else
            error("알 수 없는 방법입니다: %s", method);
        end
        elapsed = toc;

        globalChoice = zeros(nAssets, 1, "int16");
        globalChoice(typeIdxCandidate) = localChoice;
        key = matlab.lang.makeValidName(sprintf("%s__%s__%s", phaseName, method, assetTypes(t)));
        choices.(key) = globalChoice;

        [annual, total, selected] = summarizeChoice(pof, globalChoice, method, phaseName, objectiveName, assetTypes(t), assetLabels(t), constraints, years);
        annualParts{end + 1} = annual; %#ok<AGROW>
        totalParts{end + 1} = total; %#ok<AGROW>
        selectedParts{end + 1} = selected; %#ok<AGROW>
        solverRows(end + 1, :) = {phaseName, method, objectiveName, assetTypes(t), assetLabels(t), ...
            string(solverInfo.solver), solverInfo.exitflag, string(solverInfo.message), numel(typeIdxCandidate), sum(globalChoice > 0), elapsed}; %#ok<AGROW>
        writeMethodCheckpoint(runDir, phaseName, method, assetTypes(t), assetLabels(t), annual, total, selected, solverInfo, progress);

        if ~isempty(progress)
            progress.phase = repmat(string(phaseName), height(progress), 1);
            progress.method = repmat(method, height(progress), 1);
            progress.asset_type = repmat(assetTypes(t), height(progress), 1);
            progress.asset_type_label = repmat(assetLabels(t), height(progress), 1);
            progress = movevars(progress, ["phase", "method", "asset_type", "asset_type_label"], "Before", 1);
            progressParts{end + 1} = progress; %#ok<AGROW>
        end
        fprintf("[%s] %s / %s 완료: 선택 %d대, %.1f초\n", phaseName, assetLabels(t), method, sum(globalChoice > 0), elapsed);
        writeStatus(runDir, sprintf("%s | %s | %s 완료 | 선택 %d대 | %.1f초", ...
            phaseName, assetLabels(t), method, sum(globalChoice > 0), elapsed));
    end
end

typeAnnual = vertcat(annualParts{:});
typeTotal = vertcat(totalParts{:});
selectedAssets = vertcat(selectedParts{:});
solverStatus = cell2table(solverRows, 'VariableNames', {'phase', 'method', 'objective', 'asset_type', ...
    'asset_type_label', 'solver', 'exitflag', 'message', 'candidate_count', 'selected_count', 'elapsed_seconds'});
if isempty(progressParts)
    gaProgress = table();
else
    gaProgress = vertcat(progressParts{:});
end
end

function [objectiveName, scoreMat] = getScoreMatrix(method, mats)
if method == "risk_greedy"
    objectiveName = "risk";
    scoreMat = mats.risk;
elseif startsWith(method, "investment_value")
    objectiveName = "investment_value";
    scoreMat = mats.investmentValue;
elseif startsWith(method, "pi")
    objectiveName = "local_pi";
    scoreMat = mats.localPi;
elseif startsWith(method, "integrated")
    objectiveName = "integrated_pi";
    scoreMat = mats.integratedPi;
else
    error("점수 행렬을 찾을 수 없습니다: %s", method);
end
end

function choice = runGreedy(scoreMat, mats, constraints)
[n, nYears] = size(scoreMat);
choice = zeros(n, 1, "int16");
for y = 1:nYears
    budgetLeft = constraints.budgets(y);
    capacityLeft = constraints.capacities(y);
    remaining = find(choice == 0);
    [~, orderLocal] = sort(scoreMat(remaining, y), "descend");
    order = remaining(orderLocal);
    for k = 1:numel(order)
        if capacityLeft <= 0
            break;
        end
        idx = order(k);
        itemCost = mats.cost(idx, y);
        if itemCost <= budgetLeft && scoreMat(idx, y) > 0
            choice(idx) = y;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
end
end

function [choice, solverInfo] = runIlp(scoreMat, mats, constraints)
[n, nYears] = size(scoreMat);
nVars = n * nYears;
score = double(scoreMat(:));
cost = double(mats.cost(:));
assetVec = repmat((1:n)', nYears, 1);
yearVec = repelem((1:nYears)', n);

% 선택될 수 없는 변수는 intlinprog에 넘기기 전에 제거한다.
% 점수가 0 이하이거나 해당 연도 예산보다 비용이 큰 변수는 최적해에
% 포함될 수 없으므로, 분기한정 탐색을 불필요하게 키우지 않도록 한다.
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
lb = zeros(nKeep, 1);
ub = ones(nKeep, 1);
intcon = 1:nKeep;
options = buildIlpOptions();
fprintf("    [ILP] 유효 변수 %d / 전체 변수 %d, 제약식 %d개\n", nKeep, nVars, size(A, 1));

try
    [x, fval, exitflag, output] = intlinprog(f, intcon, A, b, [], [], lb, ub, options);
    if isempty(x)
        choice = zeros(n, 1, "int16");
    else
        xFull = zeros(nVars, 1);
        xFull(validIdx) = x;
        xMat = reshape(xFull, n, nYears);
        [maxVal, yearIdx] = max(xMat, [], 2);
        choice = int16(yearIdx .* (maxVal >= 0.5));
        choice = repairChoice(choice, scoreMat, mats, constraints, false);
    end
    if isfield(output, "message")
        outMessage = string(output.message);
    else
        outMessage = "";
    end
    solverInfo = struct("solver", "intlinprog", "exitflag", exitflag, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, outMessage), "objective", -fval);
catch ME
    warning('simulation:ilpFallback', 'ILP 실패, 그리디 대체: %s', ME.message);
    choice = runGreedy(scoreMat, mats, constraints);
    solverInfo = struct("solver", "intlinprog_failed_greedy_fallback", "exitflag", -999, ...
        "message", sprintf("유효 변수 %d/%d | %s", nKeep, nVars, string(ME.message)), "objective", choiceScore(choice, scoreMat));
end
end

function options = buildIlpOptions()
displayMode = strtrim(string(getenv("SIM_ILP_DISPLAY")));
if strlength(displayMode) == 0
    displayMode = "iter";
end
options = optimoptions("intlinprog", "Display", char(displayMode));

% Matlab 버전에 따라 지원 옵션이 다를 수 있으므로 가능한 경우에만 적용한다.
try
    options.Heuristics = "advanced";
catch
end
try
    options.CutGeneration = "advanced";
catch
end
try
    options.IntegerPreprocess = "advanced";
catch
end

% 상대갭 허용오차: 미설정 시 기본 0.1%(1e-3)로 둔다.
% intlinprog 기본값 1e-4(0.01%)는 교체비용이 4종뿐이라 조합 축퇴가 심한
% 유형(예: 지상변압기)에서 최적성 증명이 끝나지 않아 무한 정체를 유발한다.
relativeGap = str2double(string(getenv("SIM_ILP_REL_GAP")));
if ~(isfinite(relativeGap) && relativeGap >= 0)
    relativeGap = 1e-3;
end
try
    options.RelativeGapTolerance = relativeGap;
catch
end

% 시간 상한(기본 600초): 갭을 못 닫더라도 그때까지의 최선해(exitflag=2)를
% 반환하게 하여 무한 정체를 방지한다. 좋은 해는 통상 초반에 확보되므로
% 여유 있게 두어도 해 품질 손실은 거의 없다. SIM_ILP_MAX_TIME으로 조정 가능.
maxTime = readEnvNumber("SIM_ILP_MAX_TIME", 600);
if isfinite(maxTime) && maxTime > 0
    try
        options.MaxTime = maxTime;
    catch
    end
end
end

function [bestChoice, progress] = runGa(scoreMat, mats, constraints, generations, populationSize, mutationRate)
[n, nYears] = size(scoreMat);
population = zeros(populationSize, n, "int16");
population(1, :) = runGreedy(scoreMat, mats, constraints)';
for p = 2:populationSize
    noise = 0.75 + 0.50 * rand(n, nYears);
    population(p, :) = runGreedy(scoreMat .* noise, mats, constraints)';
end
fitness = evaluatePopulationFitness(population, scoreMat);
[bestScore, bestIdx] = max(fitness);
bestChoice = population(bestIdx, :)';
progressRows = {};

for g = 1:generations
    newPopulation = zeros(size(population), "int16");
    eliteCount = max(2, round(populationSize * 0.10));
    [~, eliteOrder] = sort(fitness, "descend");
    newPopulation(1:eliteCount, :) = population(eliteOrder(1:eliteCount), :);
    for p = (eliteCount + 1):populationSize
        parentA = population(tournamentSelect(fitness), :);
        parentB = population(tournamentSelect(fitness), :);
        mask = rand(1, n) < 0.5;
        child = parentA;
        child(mask) = parentB(mask);
        mutateMask = rand(1, n) < mutationRate;
        if any(mutateMask)
            child(mutateMask) = int16(randi([0, nYears], 1, sum(mutateMask)));
        end
        child = repairChoice(child', scoreMat, mats, constraints, true)';
        newPopulation(p, :) = child;
    end
    population = newPopulation;
    fitness = evaluatePopulationFitness(population, scoreMat);
    [currentBest, bestIdx] = max(fitness);
    if currentBest > bestScore
        bestScore = currentBest;
        bestChoice = population(bestIdx, :)';
    end
    if g == 1 || mod(g, 10) == 0 || g == generations
        progressRows(end + 1, :) = {g, bestScore, currentBest, mean(fitness), sum(bestChoice > 0)}; %#ok<AGROW>
        fprintf("    GA generation %d/%d, best=%.6f, mean=%.6f, selected=%d\n", ...
            g, generations, bestScore, mean(fitness), sum(bestChoice > 0));
    end
end
progress = cell2table(progressRows, 'VariableNames', {'generation', 'best_score', ...
    'population_best', 'population_mean', 'selected_assets'});
end

function idx = tournamentSelect(fitness)
n = numel(fitness);
candidates = randi(n, 3, 1);
[~, localBest] = max(fitness(candidates));
idx = candidates(localBest);
end

function fitness = evaluatePopulationFitness(population, scoreMat)
nPop = size(population, 1);
fitness = zeros(nPop, 1);
for p = 1:nPop
    fitness(p) = choiceScore(population(p, :)', scoreMat);
end
end

function value = choiceScore(choice, scoreMat)
selected = find(choice > 0);
if isempty(selected)
    value = 0;
    return;
end
n = size(scoreMat, 1);
cols = double(choice(selected));
linIdx = selected + (cols - 1) * n;
value = sum(scoreMat(linIdx), "omitnan");
end

function repaired = repairChoice(choice, scoreMat, mats, constraints, fillFlag)
repaired = int16(choice(:));
[~, nYears] = size(scoreMat);
for y = 1:nYears
    selected = find(repaired == y);
    while numel(selected) > constraints.capacities(y) || sum(mats.cost(selected, y), "omitnan") > constraints.budgets(y)
        if isempty(selected)
            break;
        end
        efficiency = scoreMat(selected, y) ./ max(mats.cost(selected, y), 1);
        [~, worst] = min(efficiency);
        repaired(selected(worst)) = 0;
        selected = find(repaired == y);
    end
    if ~fillFlag
        continue;
    end
    selected = find(repaired == y);
    budgetLeft = constraints.budgets(y) - sum(mats.cost(selected, y), "omitnan");
    capacityLeft = constraints.capacities(y) - numel(selected);
    if budgetLeft <= 0 || capacityLeft <= 0
        continue;
    end
    remaining = find(repaired == 0);
    if isempty(remaining)
        continue;
    end
    fillScore = scoreMat(remaining, y) ./ max(mats.cost(remaining, y), 1);
    [~, orderLocal] = sort(fillScore, "descend");
    order = remaining(orderLocal);
    for k = 1:numel(order)
        if capacityLeft <= 0
            break;
        end
        idx = order(k);
        itemCost = mats.cost(idx, y);
        if itemCost <= budgetLeft && scoreMat(idx, y) > 0
            repaired(idx) = y;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
end
end

function [annual, total, selectedAssets] = summarizeChoice(pof, choice, method, phaseName, objectiveName, assetTypeScope, assetLabelScope, constraints, years)
annualRows = {};
selectedRows = {};
if assetTypeScope == "all"
    scopeIdx = (1:height(pof))';
else
    scopeIdx = find(string(pof.asset_type) == assetTypeScope);
end
for y = 1:numel(years)
    year = years(y);
    selected = find(choice == y);
    cumulative = find(choice > 0 & choice <= y);
    cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
    riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
    investmentValue = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
    saidi = sum(pof.(sprintf("saidi_%d_min", year))(selected), "omitnan");
    pofSum = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
    localPiSum = sum(pof.(sprintf("local_pi_%d", year))(selected), "omitnan");
    integratedPiSum = sum(pof.(sprintf("integrated_pi_%d", year))(selected), "omitnan");
    baselineRisk = sum(pof.(sprintf("risk_%d_kkrw", year))(scopeIdx), "omitnan");
    baselineSaidi = sum(pof.(sprintf("saidi_%d_min", year))(scopeIdx), "omitnan");
    removedRisk = sum(pof.(sprintf("risk_%d_kkrw", year))(cumulative), "omitnan");
    removedSaidi = sum(pof.(sprintf("saidi_%d_min", year))(cumulative), "omitnan");
    if isempty(constraints)
        budgetLimit = NaN;
        capacityLimit = NaN;
    else
        budgetLimit = constraints.budgets(y);
        capacityLimit = constraints.capacities(y);
    end
    budgetUsageRatio = safeDivide(cost, budgetLimit);
    budgetExceeded = cost > budgetLimit + 1e-6;
    capacityUsageRatio = safeDivide(numel(selected), capacityLimit);
    capacityExceeded = numel(selected) > capacityLimit;
    annualRows(end + 1, :) = {phaseName, method, objectiveName, assetTypeScope, assetLabelScope, year, ...
        numel(selected), cost, riskReduction, investmentValue, safeDivide(riskReduction, cost), ...
        saidi, pofSum, localPiSum, integratedPiSum, baselineRisk, baselineRisk - removedRisk, ...
        baselineSaidi, baselineSaidi - removedSaidi, budgetLimit, capacityLimit, ...
        budgetUsageRatio, budgetExceeded, capacityUsageRatio, capacityExceeded}; %#ok<AGROW>
    for r = 1:numel(selected)
        idx = selected(r);
        selectedRows(end + 1, :) = {phaseName, method, objectiveName, assetTypeScope, r, ...
            string(pof.asset_id(idx)), string(pof.asset_type(idx)), string(pof.asset_type_label(idx)), year, ...
            pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
            pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
            pof.(sprintf("investment_value_%d_kkrw", year))(idx), ...
            pof.(sprintf("investment_efficiency_%d", year))(idx), ...
            pof.(sprintf("saidi_%d_min", year))(idx), ...
            pof.(sprintf("pof_%d", year))(idx), ...
            pof.(sprintf("local_pi_%d", year))(idx), ...
            pof.(sprintf("integrated_pi_%d", year))(idx), ...
            pof.w_type_alpha_0_5(idx)}; %#ok<AGROW>
    end
end
annual = cell2table(annualRows, 'VariableNames', {'phase', 'method', 'objective', ...
    'asset_type_scope', 'asset_type_label', 'year', 'selected_count', ...
    'investment_cost_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
    'investment_efficiency', 'saidi_reduction_min', 'expected_failures', ...
    'local_pi', 'integrated_pi', 'baseline_risk_kkrw', 'risk_after_cumulative_kkrw', ...
    'baseline_saidi_min', 'saidi_after_cumulative_min', 'budget_limit_kkrw', 'capacity_limit', ...
    'budget_usage_ratio', 'budget_exceeded', 'capacity_usage_ratio', 'capacity_exceeded'});
total = groupsummary(annual, {'phase', 'method', 'objective', 'asset_type_scope', 'asset_type_label'}, "sum", ...
    {'selected_count', 'investment_cost_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
    'saidi_reduction_min', 'expected_failures', 'local_pi', 'integrated_pi'});
total.Properties.VariableNames = erase(total.Properties.VariableNames, "sum_");
% groupsummary가 자동으로 추가하는 GroupCount 열은 최종 비교표에 불필요하므로 제거한다.
if ismember("GroupCount", total.Properties.VariableNames)
    total = removevars(total, "GroupCount");
end
totalLimits = groupsummary(annual, {'phase', 'method', 'objective', 'asset_type_scope', 'asset_type_label'}, "sum", ...
    {'budget_limit_kkrw', 'capacity_limit'});
totalLimits.Properties.VariableNames = erase(totalLimits.Properties.VariableNames, "sum_");
if ismember("GroupCount", totalLimits.Properties.VariableNames)
    totalLimits = removevars(totalLimits, "GroupCount");
end
total = join(total, totalLimits, "Keys", {'phase', 'method', 'objective', 'asset_type_scope', 'asset_type_label'});
total.investment_efficiency = total.risk_reduction_kkrw ./ max(total.investment_cost_kkrw, 1);
total.budget_usage_ratio = total.investment_cost_kkrw ./ max(total.budget_limit_kkrw, 1);
total.budget_exceeded = total.investment_cost_kkrw > total.budget_limit_kkrw + 1e-6;
total.capacity_usage_ratio = total.selected_count ./ max(total.capacity_limit, 1);
total.capacity_exceeded = total.selected_count > total.capacity_limit;
if isempty(selectedRows)
    selectedAssets = table();
else
    selectedAssets = cell2table(selectedRows, 'VariableNames', {'phase', 'method', 'objective', ...
        'asset_type_scope', 'selection_rank_in_year', 'asset_id', 'asset_type', 'asset_type_label', ...
        'replacement_year', 'replacement_cost_kkrw', 'risk_reduction_kkrw', ...
        'investment_value_kkrw', 'investment_efficiency', 'saidi_min', 'pof', ...
        'local_pi', 'integrated_pi', 'w_type_alpha_0_5'});
end
end

function [combinedAnnual, combinedTotal, combinedSelected] = combineIndividualChoices(pof, choices, assetTypes, years, methods, phaseName, budgetRate, capacityRate, discountRate)
annualParts = {};
totalParts = {};
selectedParts = {};
% 합산 결과를 전체설비 기준 예산·용량 제약과 비교할 수 있도록 전체 제약을 계산한다.
% 유형별 예산의 합은 전체 예산과 같으므로(자산가치 비례 배분) 합산 투자액이
% 전체 예산을 초과하지 않음을 표에서 확인할 수 있다.
totalConstraints = buildConstraints(pof, (1:height(pof))', years, budgetRate, capacityRate, discountRate);
for m = 1:numel(methods)
    method = methods(m);
    combinedChoice = zeros(height(pof), 1, "int16");
    for t = 1:numel(assetTypes)
        key = matlab.lang.makeValidName(sprintf("%s__%s__%s", phaseName, method, assetTypes(t)));
        combinedChoice = max(combinedChoice, choices.(key));
    end
    matsAll = buildMatrices(pof, (1:height(pof))', years);
    [objectiveName, ~] = getScoreMatrix(method, matsAll);
    [annual, total, selected] = summarizeChoice(pof, combinedChoice, method, phaseName + "_combined", objectiveName, ...
        "all", "전체설비", totalConstraints, years);
    annualParts{end + 1} = annual; %#ok<AGROW>
    totalParts{end + 1} = total; %#ok<AGROW>
    selectedParts{end + 1} = selected; %#ok<AGROW>
end
combinedAnnual = vertcat(annualParts{:});
combinedTotal = vertcat(totalParts{:});
combinedSelected = vertcat(selectedParts{:});
end

function [integratedAnnual, integratedTotal, integratedSelected, integratedSolver, integratedProgress] = runIntegratedPhase( ...
    pof, assetTypes, candidateMask, piChoices, years, budgetRate, capacityRate, discountRate, ...
    gaGenerations, gaPopulation, gaMutationRate, runDir)

nAssets = height(pof);
totalConstraints = buildConstraints(pof, (1:nAssets)', years, budgetRate, capacityRate, discountRate);
postMask = false(nAssets, 1);
postSourceMethods = ["pi_greedy", "pi_ilp", "pi_ga"];
for t = 1:numel(assetTypes)
    for m = 1:numel(postSourceMethods)
        key = matlab.lang.makeValidName(sprintf("%s__%s__%s", "pi_phase", postSourceMethods(m), assetTypes(t)));
        if isfield(piChoices, key)
            postMask = postMask | (piChoices.(key) > 0);
        end
    end
end
preIdx = find(candidateMask);
postIdx = find(postMask);

% A안(post): 개별설비 PI 최적화에서 한 번이라도 선택된 후보군에 설비유형 가중치가 반영된 integrated_pi를 적용한다.
% B안(pre): 원 후보군 전체에 integrated_pi를 사전 계산한 뒤 전체설비 기준으로 직접 최적화한다.
configs = {
    "integrated_post_type_weight_ilp", postIdx;
    "integrated_post_type_weight_ga", postIdx;
    "integrated_pre_type_weight_ilp", preIdx;
    "integrated_pre_type_weight_ga", preIdx
    };

annualParts = {};
totalParts = {};
selectedParts = {};
solverRows = {};
progressParts = {};
for c = 1:size(configs, 1)
    method = configs{c, 1};
    candidateIdx = configs{c, 2};
    mats = buildMatrices(pof, candidateIdx, years);
    [objectiveName, scoreMat] = getScoreMatrix(method, mats);
    fprintf("[integrated] %s 후보 %d 시작\n", method, numel(candidateIdx));
    writeStatus(runDir, sprintf("integrated_phase | %s 시작 | 후보 %d", method, numel(candidateIdx)));
    tic;
    if endsWith(method, "ilp")
        [localChoice, solverInfo] = runIlp(scoreMat, mats, totalConstraints);
        progress = table();
    else
        [localChoice, progress] = runGa(scoreMat, mats, totalConstraints, gaGenerations, gaPopulation, gaMutationRate);
        solverInfo = struct("solver", "custom_ga", "exitflag", NaN, "message", "GA 200 generations");
    end
    elapsed = toc;
    globalChoice = zeros(nAssets, 1, "int16");
    globalChoice(candidateIdx) = localChoice;
    [annual, total, selected] = summarizeChoice(pof, globalChoice, method, "integrated_phase", objectiveName, ...
        "all", "전체설비", totalConstraints, years);
    annualParts{end + 1} = annual; %#ok<AGROW>
    totalParts{end + 1} = total; %#ok<AGROW>
    selectedParts{end + 1} = selected; %#ok<AGROW>
    solverRows(end + 1, :) = {"integrated_phase", method, objectiveName, "all", "전체설비", ...
        string(solverInfo.solver), solverInfo.exitflag, string(solverInfo.message), numel(candidateIdx), sum(globalChoice > 0), elapsed}; %#ok<AGROW>
    if ~isempty(progress)
        progress.phase = repmat("integrated_phase", height(progress), 1);
        progress.method = repmat(method, height(progress), 1);
        progress.asset_type = repmat("all", height(progress), 1);
        progress.asset_type_label = repmat("전체설비", height(progress), 1);
        progress = movevars(progress, ["phase", "method", "asset_type", "asset_type_label"], "Before", 1);
        progressParts{end + 1} = progress; %#ok<AGROW>
    end
    fprintf("[integrated] %s 완료: 선택 %d대, %.1f초\n", method, sum(globalChoice > 0), elapsed);
    writeStatus(runDir, sprintf("integrated_phase | %s 완료 | 선택 %d대 | %.1f초", method, sum(globalChoice > 0), elapsed));
end
integratedAnnual = vertcat(annualParts{:});
integratedTotal = vertcat(totalParts{:});
integratedSelected = vertcat(selectedParts{:});
integratedSolver = cell2table(solverRows, 'VariableNames', {'phase', 'method', 'objective', 'asset_type', ...
    'asset_type_label', 'solver', 'exitflag', 'message', 'candidate_count', 'selected_count', 'elapsed_seconds'});
if isempty(progressParts)
    integratedProgress = table();
else
    integratedProgress = vertcat(progressParts{:});
end
end

function finalComparison = buildFinalComparison(valueCombinedTotal, piCombinedTotal, integratedTotal)
valueRows = valueCombinedTotal(ismember(valueCombinedTotal.method, ["investment_value_ilp", "investment_value_ga"]), :);
piRows = piCombinedTotal(ismember(piCombinedTotal.method, ["pi_ilp", "pi_ga"]), :);
finalComparison = [valueRows; piRows; integratedTotal];
baselineIdx = find(finalComparison.method == "investment_value_ilp", 1);
if isempty(baselineIdx)
    baselineIdx = 1;
end
metrics = ["selected_count", "investment_cost_kkrw", "risk_reduction_kkrw", "investment_value_kkrw", ...
    "saidi_reduction_min", "local_pi", "integrated_pi", "investment_efficiency"];
for m = 1:numel(metrics)
    metric = metrics(m);
    baseValue = finalComparison.(metric)(baselineIdx);
    if baseValue == 0
        finalComparison.([char(metric) '_vs_value_ilp_pct']) = NaN(height(finalComparison), 1);
    else
        finalComparison.([char(metric) '_vs_value_ilp_pct']) = ...
            (finalComparison.(metric) - baseValue) ./ abs(baseValue) * 100;
    end
end
end

function figureManifest = saveSimulationFigures(figureDir, valueCombinedTotal, piCombinedTotal, integratedTotal, valueTypeTotal, piTypeTotal)
rows = {};
saveBar(valueCombinedTotal.method, valueCombinedTotal.investment_value_kkrw, ...
    "투자가치 최적화 합산 비교", fullfile(figureDir, "value_combined_investment_value.png"));
rows(end + 1, :) = {"value_combined_investment_value.png", "투자가치 최적화 합산 비교"}; %#ok<AGROW>
saveBar(valueCombinedTotal.method, valueCombinedTotal.risk_reduction_kkrw, ...
    "투자가치 최적화 Risk 저감량 비교", fullfile(figureDir, "value_combined_risk_reduction.png"));
rows(end + 1, :) = {"value_combined_risk_reduction.png", "투자가치 최적화 Risk 저감량 비교"}; %#ok<AGROW>
saveBar(piCombinedTotal.method, piCombinedTotal.local_pi, ...
    "PI 기반 개별설비 합산 비교", fullfile(figureDir, "pi_combined_local_pi.png"));
rows(end + 1, :) = {"pi_combined_local_pi.png", "PI 기반 개별설비 합산 비교"}; %#ok<AGROW>
saveBar(integratedTotal.method, integratedTotal.integrated_pi, ...
    "통합설비 Integrated PI 비교", fullfile(figureDir, "integrated_total_pi.png"));
rows(end + 1, :) = {"integrated_total_pi.png", "통합설비 Integrated PI 비교"}; %#ok<AGROW>
saveStackedTypeBar(valueTypeTotal, fullfile(figureDir, "value_asset_type_selected_count.png"), "투자가치 단계 설비군별 선택대수");
rows(end + 1, :) = {"value_asset_type_selected_count.png", "투자가치 단계 설비군별 선택대수"}; %#ok<AGROW>
saveStackedTypeBar(piTypeTotal, fullfile(figureDir, "pi_asset_type_selected_count.png"), "PI 단계 설비군별 선택대수");
rows(end + 1, :) = {"pi_asset_type_selected_count.png", "PI 단계 설비군별 선택대수"}; %#ok<AGROW>
figureManifest = cell2table(rows, 'VariableNames', {'figure_file', 'title'});
end

function saveBar(labels, values, titleText, path)
fig = figure("Visible", "off", "Position", [100 100 1100 500]);
bar(categorical(string(labels)), values);
title(titleText);
ylabel("값");
xtickangle(25);
grid on;
saveas(fig, path);
close(fig);
end

function saveStackedTypeBar(typeTotal, path, titleText)
methods = unique(typeTotal.method, "stable");
types = unique(typeTotal.asset_type_label, "stable");
data = zeros(numel(methods), numel(types));
for i = 1:numel(methods)
    for j = 1:numel(types)
        idx = typeTotal.method == methods(i) & typeTotal.asset_type_label == types(j);
        data(i, j) = sum(typeTotal.selected_count(idx), "omitnan");
    end
end
fig = figure("Visible", "off", "Position", [100 100 1200 600]);
bar(categorical(string(methods)), data, "stacked");
title(titleText);
ylabel("선택대수");
legend(string(types), "Location", "bestoutside");
xtickangle(25);
grid on;
saveas(fig, path);
close(fig);
end

function writeMethodCheckpoint(runDir, phaseName, method, assetType, assetLabel, annual, total, selected, solverInfo, progress)
checkpointDir = char(fullfile(runDir, "checkpoints", "method_level"));
if ~exist(checkpointDir, "dir")
    mkdir(checkpointDir);
end
checkpointName = char(matlab.lang.makeValidName(sprintf("%s__%s__%s", phaseName, method, assetType)));
checkpointFile = fullfile(checkpointDir, [checkpointName '.xlsx']);
if isempty(checkpointFile)
    error("체크포인트 파일 경로가 비어 있습니다. runDir 값을 확인해야 합니다.");
end

if ~isempty(annual); writetable(annual, checkpointFile, "Sheet", "annual"); end
if ~isempty(total); writetable(total, checkpointFile, "Sheet", "total"); end
if ~isempty(selected); writetable(selected, checkpointFile, "Sheet", "selected_assets"); end
solverTable = struct2table(solverInfo, 'AsArray', true);
solverTable.phase = string(phaseName);
solverTable.method = string(method);
solverTable.asset_type = string(assetType);
solverTable.asset_type_label = string(assetLabel);
solverTable = movevars(solverTable, ["phase", "method", "asset_type", "asset_type_label"], "Before", 1);
writetable(solverTable, checkpointFile, "Sheet", "solver");
if ~isempty(progress); writetable(progress, checkpointFile, "Sheet", "progress"); end

writeStatus(runDir, sprintf("체크포인트 저장 | %s | %s | %s | %s", phaseName, assetLabel, method, checkpointFile));
end

function writePhaseCheckpoint(runDir, checkpointDir, stageName, typeAnnual, typeTotal, combinedAnnual, combinedTotal, solverStatus, gaProgress)
stageName = char(stageName);
checkpointFile = fullfile(checkpointDir, [stageName '.xlsx']);
if ~isempty(typeAnnual); writetable(typeAnnual, checkpointFile, "Sheet", "type_annual"); end
if ~isempty(typeTotal); writetable(typeTotal, checkpointFile, "Sheet", "type_total"); end
if ~isempty(combinedAnnual); writetable(combinedAnnual, checkpointFile, "Sheet", "combined_annual"); end
if ~isempty(combinedTotal); writetable(combinedTotal, checkpointFile, "Sheet", "combined_total"); end
if ~isempty(solverStatus); writetable(solverStatus, checkpointFile, "Sheet", "solver_status"); end
if ~isempty(gaProgress); writetable(gaProgress, checkpointFile, "Sheet", "ga_progress"); end
fprintf("[checkpoint] %s 저장: %s\n", stageName, checkpointFile);
statusFile = fullfile(runDir, "simulation_status.txt");
fid = fopen(statusFile, "a", "n", "UTF-8");
fprintf(fid, "%s | %s 완료 | %s\n", char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")), stageName, checkpointFile);
fclose(fid);
end

function writeStatus(runDir, message)
statusFile = fullfile(runDir, "simulation_status.txt");
fid = fopen(statusFile, "a", "n", "UTF-8");
if fid > 0
    fprintf(fid, "%s | %s\n", char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")), string(message));
    fclose(fid);
else
    warning('simulation:statusWriteFailed', '상태 파일을 열 수 없습니다: %s', statusFile);
end
end

function out = safeDivide(a, b)
if b == 0
    out = 0;
else
    out = a / b;
end
end
