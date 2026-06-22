%% NSGA-II 기반 다목적 포트폴리오 최적화 - MATLAB 버전
% 목적:
% 1) 투자가치 버전 NSGA-II:
%    - 투자가치 최대화
%    - 투자비용 최소화
% 2) PI 버전 NSGA-II:
%    - AHP 기반 Local PI 최대화
%    - 투자비용 최소화
%
% 주의:
% - SAIDI와 Risk 총량은 목적함수가 아니라 KPI 총량제 제약으로 적용한다.
% - KPI 상한은 2026년 투자 전 기준 총량의 98%로 고정한다.
% - 예산은 상한 제약으로만 적용한다.
% - 논문 본문/검토보고서는 수정하지 않고, 코드와 결과 엑셀만 생성한다.

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputDir = fullfile(baseDir, "outputs");
if ~isfolder(outputDir)
    mkdir(outputDir);
end

pofFile = fullfile(dataDir, "pof_5yr_output.xlsx");
piFile = fullfile(outputDir, "local_pi_matlab.xlsx");
integratedPiFile = fullfile(outputDir, "integrated_pi_matlab.xlsx");
runStamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
outputFile = fullfile(outputDir, "nsga_portfolio_optimization_matlab_" + runStamp + ".xlsx");
runLogFile = fullfile(outputDir, "nsga_portfolio_optimization_matlab_" + runStamp + ".log");
checkpointDir = fullfile(outputDir, "nsga_checkpoints_" + runStamp);
if ~isfolder(checkpointDir)
    mkdir(checkpointDir);
end

years = [2026 2027 2028 2029 2030];
nYears = numel(years);
discountRate = 0.05;
budgetRate = 0.04;
capacityRate = 0.05;
budgetFloorRate = 0.00;
candidateFlag = "candidate_top30_current";
saidiCapRate = 0.98;
riskCapRates = [1.05 1.075 1.10 1.15 1.20];

nsgaSeed = 20260620;
nsgaPopulation = 160;
nsgaGenerations = 200;
nsgaMutationRate = 0.015;
nsgaTournamentSize = 3;

% 빠른 검증 실행이 필요할 때만 환경변수로 NSGA 설정을 임시 조정한다.
populationOverride = str2double(getenv("NSGA_POPULATION"));
if ~isnan(populationOverride) && populationOverride >= 20
    nsgaPopulation = round(populationOverride);
end
generationsOverride = str2double(getenv("NSGA_GENERATIONS"));
if ~isnan(generationsOverride) && generationsOverride >= 1
    nsgaGenerations = round(generationsOverride);
end
saidiCapRateOverride = str2double(getenv("NSGA_SAIDI_CAP_RATE"));
if ~isnan(saidiCapRateOverride) && saidiCapRateOverride > 0
    saidiCapRate = saidiCapRateOverride;
end
riskCapRatesOverride = strtrim(string(getenv("NSGA_RISK_CAP_RATES")));
if strlength(riskCapRatesOverride) > 0
    parsedRiskCapRates = str2double(split(riskCapRatesOverride, ","));
    parsedRiskCapRates = parsedRiskCapRates(~isnan(parsedRiskCapRates) & parsedRiskCapRates > 0);
    if ~isempty(parsedRiskCapRates)
        riskCapRates = parsedRiskCapRates(:)';
    end
end
seedCheckpointDirOverride = strtrim(string(getenv("NSGA_SEED_CHECKPOINT_DIR")));

diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off")); %#ok<NASGU>

fprintf("NSGA-II portfolio optimization - MATLAB\n");
fprintf("PoF input: %s\n", pofFile);
fprintf("Local PI input: %s\n", piFile);
fprintf("Integrated PI input: %s\n", integratedPiFile);

if ~isfile(pofFile)
    error("PoF 출력 파일을 찾을 수 없습니다: %s", pofFile);
end
if ~isfile(piFile)
    error("Local PI 산출 파일을 찾을 수 없습니다: %s", piFile);
end

%% 1. 입력 로드
pof = readtable(pofFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
piWide = readtable(piFile, "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
if isfile(integratedPiFile)
    integratedPiWide = readtable(integratedPiFile, "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");
else
    integratedPiWide = table();
end

if height(pof) ~= height(piWide)
    error("PoF 출력과 Local PI 출력의 행 수가 다릅니다. PoF=%d, PI=%d", height(pof), height(piWide));
end
if ~all(string(pof.asset_id) == string(piWide.asset_id))
    error("PoF 출력과 Local PI 출력의 asset_id 순서가 일치하지 않습니다.");
end
if ~isempty(integratedPiWide)
    if height(integratedPiWide) ~= height(pof)
        error("PoF 출력과 Integrated PI 출력의 행 수가 다릅니다. PoF=%d, Integrated PI=%d", height(pof), height(integratedPiWide));
    end
    if ~all(string(pof.asset_id) == string(integratedPiWide.asset_id))
        error("PoF 출력과 Integrated PI 출력의 asset_id 순서가 일치하지 않습니다.");
    end
end

nAssets = height(pof);
candidateMask = logical(pof.(candidateFlag));
candidateIdx = find(candidateMask);
nCandidates = numel(candidateIdx);
seedPopulation = loadSeedPopulationFromCheckpoints(seedCheckpointDirOverride, nCandidates);

totalAssetValueKkrw = sum(pof.("replacement_cost_2026_kkrw"), "omitnan");
annualBudgetBaseKkrw = totalAssetValueKkrw * budgetRate;
budgetUpper = annualBudgetBaseKkrw ./ ((1 + discountRate) .^ (0:nYears-1));
budgetLower = zeros(size(budgetUpper));
annualCapacity = round(nAssets * capacityRate);
capacities = repmat(annualCapacity, 1, nYears);

baselineSaidi = zeros(1, nYears);
baselineRisk = zeros(1, nYears);
for y = 1:nYears
    year = years(y);
    baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year)), "omitnan");
    baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan");
end
saidiCap = baselineSaidi(1) * saidiCapRate;
riskCapValues = baselineRisk(1) .* riskCapRates;
riskCap = riskCapValues(1);

fprintf("assets: %d\n", nAssets);
fprintf("candidate assets: %d\n", nCandidates);
fprintf("annual budget base: %.3f kKRW\n", annualBudgetBaseKkrw);
fprintf("budget floor rate: %.2f (no lower-bound budget constraint)\n", budgetFloorRate);
fprintf("annual capacity: %d assets\n", annualCapacity);
fprintf("SAIDI cap: %.10f (2026 baseline %.10f x %.3f)\n", saidiCap, baselineSaidi(1), saidiCapRate);
fprintf("Risk cap first scenario: %.3f kKRW (2026 baseline %.3f x %.3f)\n", riskCap, baselineRisk(1), riskCapRates(1));
fprintf("NSGA population=%d, generations=%d, mutation=%.4f\n", ...
    nsgaPopulation, nsgaGenerations, nsgaMutationRate);
fprintf("Active Risk cap scenario rates: %s\n", strjoin(compose("%.1f%%", riskCapRates .* 100), ", "));
fprintf("Active Risk cap scenario values: %s kKRW\n", strjoin(compose("%.3f", riskCapValues), ", "));

%% 2. 후보군 행렬 구성
mats = buildCandidateMatrices(pof, piWide, integratedPiWide, candidateIdx, years);

%% 3. NSGA-II 시나리오 실행
configs = struct([]);
configs(1).method = "investment_value_nsga_kpi";
configs(1).objective = "investment_value";
configs(1).primaryLabel = "investment_value";
configs(1).primaryMat = mats.investmentValue;

configs(2).method = "local_pi_ahp_nsga_kpi";
configs(2).objective = "local_pi_ahp";
configs(2).primaryLabel = "local_pi_ahp";
configs(2).primaryMat = mats.localPiAhp;

configs(3).method = "integrated_pi_ahp_nsga_kpi";
configs(3).objective = "integrated_pi_ahp_alpha05";
configs(3).primaryLabel = "integrated_pi_ahp_alpha05";
configs(3).primaryMat = mats.integratedPiAhpAlpha05;

methodFilter = strtrim(string(getenv("NSGA_METHODS")));
if strlength(methodFilter) > 0
    requestedMethods = strtrim(split(methodFilter, ","));
    keepConfig = false(1, numel(configs));
    for c = 1:numel(configs)
        keepConfig(c) = any(requestedMethods == configs(c).method) || any(requestedMethods == configs(c).objective);
    end
    configs = configs(keepConfig);
    if isempty(configs)
        error("NSGA_METHODS에 지정된 실행 대상이 configs에 없습니다: %s", methodFilter);
    end
end

allRunSummary = {};
allProgress = {};
allPareto = {};
allRepresentatives = {};
allAnnual = {};
allSelected = {};

for s = 1:numel(riskCapRates)
    riskCapRate = riskCapRates(s);
    riskCap = baselineRisk(1) * riskCapRate;
    scenarioId = "risk_cap_" + string(round(riskCapRate * 1000));
    fprintf("\nScenario %s: Risk cap %.3f kKRW (2026 baseline x %.3f)\n", scenarioId, riskCap, riskCapRate);

    for c = 1:numel(configs)
        cfg = configs(c);
        cfg.scenario_id = scenarioId;
        cfg.saidi_cap_rate = saidiCapRate;
        cfg.risk_cap_rate = riskCapRate;
        fprintf("\nRunning %s / %s...\n", cfg.scenario_id, cfg.method);
        rng(nsgaSeed + (s - 1) * numel(configs) + c - 1);

        [population, objectives, violations, metrics, progress] = runNsga2Portfolio( ...
            cfg.primaryMat, mats, budgetLower, budgetUpper, capacities, ...
            baselineSaidi, baselineRisk, saidiCap, riskCap, ...
            nsgaPopulation, nsgaGenerations, nsgaMutationRate, nsgaTournamentSize, seedPopulation);

        [paretoTable, paretoChromosomes] = buildParetoTable(cfg, population, objectives, violations, metrics, saidiCap, riskCap);
        representatives = chooseRepresentatives(cfg, paretoTable);
        annualSummary = buildAnnualSummary(cfg, representatives, paretoChromosomes, pof, piWide, integratedPiWide, candidateIdx, years, ...
            baselineSaidi, baselineRisk, saidiCap, riskCap);
        selectedAssets = buildSelectedAssets(cfg, representatives, paretoChromosomes, pof, piWide, integratedPiWide, candidateIdx, years);
        runSummary = buildRunSummary(cfg, paretoTable, representatives, progress);

        progress.scenario_id = repmat(cfg.scenario_id, height(progress), 1);
        progress.method = repmat(cfg.method, height(progress), 1);
        progress.objective = repmat(cfg.objective, height(progress), 1);
        progress.saidi_cap_rate = repmat(cfg.saidi_cap_rate, height(progress), 1);
        progress.risk_cap_rate = repmat(cfg.risk_cap_rate, height(progress), 1);
        progress = movevars(progress, ["scenario_id", "method", "objective", "saidi_cap_rate", "risk_cap_rate"], "Before", 1);

        allRunSummary{end + 1} = runSummary; %#ok<SAGROW>
        allProgress{end + 1} = progress; %#ok<SAGROW>
        allPareto{end + 1} = paretoTable; %#ok<SAGROW>
        allRepresentatives{end + 1} = representatives; %#ok<SAGROW>
        allAnnual{end + 1} = annualSummary; %#ok<SAGROW>
        allSelected{end + 1} = selectedAssets; %#ok<SAGROW>

        checkpointFile = fullfile(checkpointDir, cfg.scenario_id + "_" + cfg.method + ".mat");
        save(checkpointFile, "cfg", "population", "objectives", "violations", "metrics", ...
            "progress", "paretoTable", "representatives", "annualSummary", "selectedAssets", "-v7.3");
        fprintf("checkpoint saved: %s\n", checkpointFile);
    end
end

candidateSummary = buildCandidateSummary(pof, candidateMask, nsgaPopulation, nsgaGenerations, ...
    nsgaMutationRate, budgetRate, capacityRate, budgetFloorRate, saidiCapRate, riskCapRates);
constraints = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, budgetFloorRate, ...
    annualBudgetBaseKkrw, annualCapacity, budgetLower, budgetUpper, capacities, years, ...
    baselineSaidi, baselineRisk, saidiCap, saidiCapRate, riskCapRates);

runSummary = vertcat(allRunSummary{:});
progressTable = vertcat(allProgress{:});
paretoSolutions = vertcat(allPareto{:});
representativeSummary = vertcat(allRepresentatives{:});
annualSummary = vertcat(allAnnual{:});
selectedAssets = vertcat(allSelected{:});

%% 4. 저장
writetable(candidateSummary, outputFile, "Sheet", "candidate_summary");
writetable(constraints, outputFile, "Sheet", "constraints");
writetable(runSummary, outputFile, "Sheet", "run_summary");
writetable(representativeSummary, outputFile, "Sheet", "representative_summary");
writetable(annualSummary, outputFile, "Sheet", "annual_summary");
writetable(paretoSolutions, outputFile, "Sheet", "pareto_solutions");
writetable(selectedAssets, outputFile, "Sheet", "selected_assets");
writetable(progressTable, outputFile, "Sheet", "nsga_progress");

fprintf("saved: %s\n", outputFile);

%% =========================================================================
% 지역 함수
% =========================================================================

function mats = buildCandidateMatrices(pof, piWide, integratedPiWide, candidateIdx, years)
% 후보군별 연도 행렬을 구성한다.
nCandidates = numel(candidateIdx);
nYears = numel(years);

fields = ["cost", "risk", "riskReduction", "investmentValue", "saidi", "pof", "localPiAhp", "localPiFuzzy", "integratedPiAhpAlpha05"];
for f = 1:numel(fields)
    mats.(fields(f)) = zeros(nCandidates, nYears);
end

for y = 1:nYears
    year = years(y);
    mats.cost(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year))(candidateIdx);
    mats.risk(:, y) = pof.(sprintf("risk_%d_kkrw", year))(candidateIdx);
    mats.riskReduction(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year))(candidateIdx);
    mats.investmentValue(:, y) = pof.(sprintf("investment_value_%d_kkrw", year))(candidateIdx);
    mats.saidi(:, y) = pof.(sprintf("saidi_%d_min", year))(candidateIdx);
    mats.pof(:, y) = pof.(sprintf("pof_%d", year))(candidateIdx);
    mats.localPiAhp(:, y) = piWide.(sprintf("local_pi_ahp_%d", year))(candidateIdx);
    mats.localPiFuzzy(:, y) = piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(candidateIdx);
    if isempty(integratedPiWide)
        mats.integratedPiAhpAlpha05(:, y) = mats.localPiAhp(:, y);
    else
        mats.integratedPiAhpAlpha05(:, y) = integratedPiWide.(sprintf("integrated_pi_ahp_alpha_0_5_%d", year))(candidateIdx);
    end
end
end

function [population, objectives, violations, metrics, progress] = runNsga2Portfolio( ...
    primaryMat, mats, budgetLower, budgetUpper, capacities, ...
    baselineSaidi, baselineRisk, saidiCap, riskCap, ...
    populationSize, generations, mutationRate, tournamentSize, seedPopulation)
% 제약지배 NSGA-II를 실행한다.
if nargin < 14
    seedPopulation = [];
end
nCandidates = size(mats.cost, 1);
nYears = size(mats.cost, 2);

scoreBank = buildScoreBank(primaryMat, mats.saidi, mats.cost);
orderBank = buildOrderBank(scoreBank);

population = initializePopulation(populationSize, nCandidates, nYears, mats.cost, primaryMat, ...
    budgetLower, budgetUpper, capacities, scoreBank, orderBank);
if ~isempty(seedPopulation)
    [~, seedViolations, seedMetrics] = evaluatePopulation(seedPopulation, primaryMat, mats, budgetLower, budgetUpper, capacities, ...
        baselineSaidi, baselineRisk, saidiCap, riskCap);
    seedRankKey = [seedViolations, -seedMetrics(:, 1), seedMetrics(:, 2)];
    [~, seedOrder] = sortrows(seedRankKey);
    seedCount = min(populationSize, size(seedPopulation, 1));
    population(1:seedCount, :) = seedPopulation(seedOrder(1:seedCount), :);
    bestSeedMask = seedViolations <= min(seedViolations) + 1e-9;
    fprintf("seed population injected: %d portfolios (best seed primary=%.6f, min seed violation=%.6g)\n", ...
        seedCount, max(seedMetrics(bestSeedMask, 1)), min(seedViolations));
end
[objectives, violations, metrics] = evaluatePopulation(population, primaryMat, mats, budgetLower, budgetUpper, capacities, ...
    baselineSaidi, baselineRisk, saidiCap, riskCap);
[fronts, rank] = constrainedNonDominatedSort(objectives, violations);
crowding = zeros(populationSize, 1);
for f = 1:numel(fronts)
    d = crowdingDistance(objectives, fronts{f});
    crowding(fronts{f}) = d;
end

progressRows = {};
progressRows(end + 1, :) = progressRow(0, objectives, violations, metrics, fronts); %#ok<AGROW>

for g = 1:generations
    offspring = zeros(size(population));
    for p = 1:populationSize
        parentA = population(nsgaTournamentSelect(rank, crowding, tournamentSize), :);
        parentB = population(nsgaTournamentSelect(rank, crowding, tournamentSize), :);
        child = crossoverChromosome(parentA, parentB);
        child = mutateChromosome(child, nYears, mutationRate);
        bankIdx = randi(numel(scoreBank));
        child = repairRefillChromosome(child, mats.cost, primaryMat, scoreBank{bankIdx}, orderBank{bankIdx}, ...
            budgetLower, budgetUpper, capacities);
        offspring(p, :) = child;
    end

    combined = [population; offspring];
    [combinedObjectives, combinedViolations, combinedMetrics] = evaluatePopulation(combined, primaryMat, mats, ...
        budgetLower, budgetUpper, capacities, baselineSaidi, baselineRisk, saidiCap, riskCap);
    [combinedFronts, combinedRank] = constrainedNonDominatedSort(combinedObjectives, combinedViolations); %#ok<ASGLU>
    combinedCrowding = zeros(size(combined, 1), 1);
    for f = 1:numel(combinedFronts)
        d = crowdingDistance(combinedObjectives, combinedFronts{f});
        combinedCrowding(combinedFronts{f}) = d;
    end

    selectedIdx = environmentalSelection(combinedFronts, combinedCrowding, populationSize);
    population = combined(selectedIdx, :);
    objectives = combinedObjectives(selectedIdx, :);
    violations = combinedViolations(selectedIdx, :);
    metrics = combinedMetrics(selectedIdx, :);

    [fronts, rank] = constrainedNonDominatedSort(objectives, violations);
    crowding = zeros(populationSize, 1);
    for f = 1:numel(fronts)
        d = crowdingDistance(objectives, fronts{f});
        crowding(fronts{f}) = d;
    end

    if mod(g, 10) == 0 || g == generations
        r = progressRow(g, objectives, violations, metrics, fronts);
        progressRows(end + 1, :) = r; %#ok<AGROW>
        fprintf("generation %d/%d, feasible=%d, pareto=%d, best_primary=%.6f, min_cost=%.3f, best_saidi=%.6f\n", ...
            g, generations, r{3}, r{4}, r{5}, r{6}, r{7});
    end
end

progress = cell2table(progressRows, 'VariableNames', { ...
    'generation', 'population_size', 'feasible_count', 'pareto_count', ...
    'best_primary', 'min_cost_kkrw', 'best_saidi', ...
    'best_investment_value_kkrw', 'best_risk_reduction_kkrw', ...
    'best_ahp_pi', 'best_fuzzy_pi', 'best_integrated_pi', 'min_violation'});
end

function row = progressRow(generation, objectives, violations, metrics, fronts)
% 세대별 진행상황 요약 행을 만든다.
feasible = violations <= 1e-9;
if any(feasible)
    target = feasible;
else
    target = true(size(feasible));
end
front1 = fronts{1};
paretoFeasible = front1(violations(front1) <= 1e-9);
if isempty(paretoFeasible)
    paretoCount = numel(front1);
else
    paretoCount = numel(paretoFeasible);
end
row = {generation, size(objectives, 1), sum(feasible), paretoCount, ...
    max(metrics(target, 1)), min(metrics(target, 2)), max(metrics(target, 3)), ...
    max(metrics(target, 4)), max(metrics(target, 5)), ...
    max(metrics(target, 7)), max(metrics(target, 8)), max(metrics(target, 9)), min(violations)};
end

function scoreBank = buildScoreBank(primaryMat, saidiMat, costMat)
% 초기해와 repair/refill에 사용할 탐색 점수 묶음.
primaryEff = primaryMat ./ max(costMat, 1);
saidiEff = saidiMat ./ max(costMat, 1);
balanced = normalizeByColumn(primaryMat) + normalizeByColumn(saidiMat) + normalizeByColumn(primaryEff);
costAware = normalizeByColumn(primaryMat) + normalizeByColumn(saidiMat) - 0.25 * normalizeByColumn(costMat);
scoreBank = {primaryMat, primaryEff, saidiMat, saidiEff, balanced, costAware};
end

function orderBank = buildOrderBank(scoreBank)
% 각 점수 행렬별 연도 내림차순 순서를 미리 계산한다.
orderBank = cell(numel(scoreBank), 1);
for s = 1:numel(scoreBank)
    scoreMat = scoreBank{s};
    [nCandidates, nYears] = size(scoreMat);
    orderMat = zeros(nCandidates, nYears);
    for y = 1:nYears
        [~, orderMat(:, y)] = sort(scoreMat(:, y), "descend");
    end
    orderBank{s} = orderMat;
end
end

function out = normalizeByColumn(x)
% 열별 min-max 정규화.
out = zeros(size(x));
for y = 1:size(x, 2)
    col = x(:, y);
    mn = min(col, [], "omitnan");
    mx = max(col, [], "omitnan");
    if mx > mn
        out(:, y) = (col - mn) ./ (mx - mn);
    else
        out(:, y) = 0;
    end
end
end

function population = initializePopulation(populationSize, nCandidates, nYears, costMat, primaryMat, ...
    budgetLower, budgetUpper, capacities, scoreBank, orderBank)
% 실행 가능한 초기 포트폴리오를 다양하게 생성한다.
population = zeros(populationSize, nCandidates);
for p = 1:populationSize
    bankIdx = mod(p - 1, numel(scoreBank)) + 1;
    noise = 0.85 + 0.30 * rand(nCandidates, nYears);
    scoreMat = scoreBank{bankIdx} .* noise;
    orderMat = orderBank{bankIdx};
    if mod(p, 5) == 0
        randomScore = rand(nCandidates, nYears);
        [~, orderMat] = sort(randomScore, "descend");
        scoreMat = randomScore;
    end
    population(p, :) = makeSeedChromosome(costMat, primaryMat, scoreMat, orderMat, budgetLower, budgetUpper, capacities);
end
end

function chromosome = makeSeedChromosome(costMat, primaryMat, scoreMat, orderMat, budgetLower, budgetUpper, capacities)
% 점수 기반으로 예산 하한~상한을 최대한 만족하는 초기해를 만든다.
[nCandidates, nYears] = size(costMat);
chromosome = zeros(1, nCandidates);
selectedAny = false(nCandidates, 1);
for y = 1:nYears
    budgetLeft = budgetUpper(y);
    capacityLeft = capacities(y);
    order = orderMat(:, y);
    for ii = 1:numel(order)
        if capacityLeft <= 0
            break;
        end
        k = order(ii);
        if selectedAny(k) || primaryMat(k, y) <= 0 || scoreMat(k, y) <= 0
            continue;
        end
        itemCost = costMat(k, y);
        if itemCost <= budgetLeft
            chromosome(k) = y;
            selectedAny(k) = true;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
        if budgetUpper(y) - budgetLeft >= budgetLower(y) && budgetLeft < min(costMat(:, y), [], "omitnan")
            break;
        end
    end
end
end

function [objectives, violations, metrics] = evaluatePopulation(population, primaryMat, mats, budgetLower, budgetUpper, capacities, ...
    baselineSaidi, baselineRisk, saidiCap, riskCap)
% 인구집단의 목적함수, 제약위반, 주요 성과지표를 평가한다.
nPop = size(population, 1);
objectives = zeros(nPop, 2);
violations = zeros(nPop, 1);
metrics = zeros(nPop, 14);
for p = 1:nPop
    [obj, viol, metric] = evaluateChromosome(population(p, :), primaryMat, mats, budgetLower, budgetUpper, capacities, ...
        baselineSaidi, baselineRisk, saidiCap, riskCap);
    objectives(p, :) = obj;
    violations(p) = viol;
    metrics(p, :) = metric;
end
end

function [objective, violation, metric] = evaluateChromosome(chromosome, primaryMat, mats, budgetLower, budgetUpper, capacities, ...
    baselineSaidi, baselineRisk, saidiCap, riskCap)
% 단일 염색체를 평가한다.
nYears = numel(budgetUpper);
primaryTotal = 0;
costTotal = 0;
saidiTotal = 0;
investmentValueTotal = 0;
riskReductionTotal = 0;
failureTotal = 0;
selectedCount = 0;
ahpPiTotal = 0;
fuzzyPiTotal = 0;
integratedPiTotal = 0;
violation = 0;
saidiAfter = zeros(1, nYears);
riskAfter = zeros(1, nYears);

for y = 1:nYears
    selected = find(chromosome == y);
    countY = numel(selected);
    costY = sum(mats.cost(selected, y), "omitnan");
    primaryTotal = primaryTotal + sum(primaryMat(selected, y), "omitnan");
    costTotal = costTotal + costY;
    saidiTotal = saidiTotal + sum(mats.saidi(selected, y), "omitnan");
    investmentValueTotal = investmentValueTotal + sum(mats.investmentValue(selected, y), "omitnan");
    riskReductionTotal = riskReductionTotal + sum(mats.riskReduction(selected, y), "omitnan");
    failureTotal = failureTotal + sum(mats.pof(selected, y), "omitnan");
    ahpPiTotal = ahpPiTotal + sum(mats.localPiAhp(selected, y), "omitnan");
    fuzzyPiTotal = fuzzyPiTotal + sum(mats.localPiFuzzy(selected, y), "omitnan");
    integratedPiTotal = integratedPiTotal + sum(mats.integratedPiAhpAlpha05(selected, y), "omitnan");
    selectedCount = selectedCount + countY;

    violation = violation + max(0, costY - budgetUpper(y)) / max(budgetUpper(y), 1);
    violation = violation + max(0, budgetLower(y) - costY) / max(budgetUpper(y), 1);
    violation = violation + max(0, countY - capacities(y)) / max(capacities(y), 1);
end

for y = 1:nYears
    cumulativeSelected = find(chromosome > 0 & chromosome <= y);
    saidiReduction = sum(mats.saidi(cumulativeSelected, y), "omitnan");
    riskReductionCurrentYear = sum(mats.risk(cumulativeSelected, y), "omitnan");
    saidiAfter(y) = baselineSaidi(y) - saidiReduction;
    riskAfter(y) = baselineRisk(y) - riskReductionCurrentYear;
    violation = violation + max(0, saidiAfter(y) - saidiCap) / max(saidiCap, 1e-12);
    violation = violation + max(0, riskAfter(y) - riskCap) / max(riskCap, 1);
end

objective = [-primaryTotal, costTotal];
metric = [primaryTotal, costTotal, saidiTotal, investmentValueTotal, riskReductionTotal, ...
    failureTotal, ahpPiTotal, fuzzyPiTotal, integratedPiTotal, selectedCount, ...
    max(saidiAfter), max(riskAfter), saidiAfter(end), riskAfter(end)];
end

function [fronts, rank] = constrainedNonDominatedSort(objectives, violations)
% 제약지배 원칙을 적용한 비지배 정렬.
n = size(objectives, 1);
S = cell(n, 1);
dominatedCount = zeros(n, 1);
rank = inf(n, 1);
front1 = [];
for p = 1:n
    S{p} = [];
    for q = 1:n
        if p == q
            continue;
        end
        if constrainedDominates(objectives(p, :), violations(p), objectives(q, :), violations(q))
            S{p}(end + 1) = q; %#ok<AGROW>
        elseif constrainedDominates(objectives(q, :), violations(q), objectives(p, :), violations(p))
            dominatedCount(p) = dominatedCount(p) + 1;
        end
    end
    if dominatedCount(p) == 0
        rank(p) = 1;
        front1(end + 1) = p; %#ok<AGROW>
    end
end
fronts = {};
fronts{1} = front1;
i = 1;
while i <= numel(fronts) && ~isempty(fronts{i})
    nextFront = [];
    for p = fronts{i}
        for q = S{p}
            dominatedCount(q) = dominatedCount(q) - 1;
            if dominatedCount(q) == 0
                rank(q) = i + 1;
                nextFront(end + 1) = q; %#ok<AGROW>
            end
        end
    end
    if ~isempty(nextFront)
        fronts{end + 1} = nextFront; %#ok<AGROW>
    end
    i = i + 1;
end
end

function tf = constrainedDominates(objA, violA, objB, violB)
% 제약을 만족하는 해가 위반 해보다 우선하고, 둘 다 가능하면 목적함수 지배관계를 적용한다.
tol = 1e-9;
feasibleA = violA <= tol;
feasibleB = violB <= tol;
if feasibleA && ~feasibleB
    tf = true;
elseif ~feasibleA && feasibleB
    tf = false;
elseif ~feasibleA && ~feasibleB
    tf = violA < violB;
else
    tf = all(objA <= objB) && any(objA < objB);
end
end

function distance = crowdingDistance(objectives, front)
% front 내부 crowding distance를 계산한다.
nFront = numel(front);
distance = zeros(nFront, 1);
if nFront == 0
    return;
end
if nFront <= 2
    distance(:) = inf;
    return;
end
frontObj = objectives(front, :);
nObj = size(frontObj, 2);
for m = 1:nObj
    [sortedValues, order] = sort(frontObj(:, m));
    distance(order(1)) = inf;
    distance(order(end)) = inf;
    denom = sortedValues(end) - sortedValues(1);
    if denom == 0
        continue;
    end
    for i = 2:(nFront - 1)
        distance(order(i)) = distance(order(i)) + ...
            (sortedValues(i + 1) - sortedValues(i - 1)) / denom;
    end
end
end

function idx = nsgaTournamentSelect(rank, crowding, tournamentSize)
% rank가 낮고 crowding이 큰 개체를 선호하는 토너먼트 선택.
n = numel(rank);
candidates = randi(n, tournamentSize, 1);
best = candidates(1);
for i = 2:numel(candidates)
    challenger = candidates(i);
    if rank(challenger) < rank(best) || ...
            (rank(challenger) == rank(best) && crowding(challenger) > crowding(best))
        best = challenger;
    end
end
idx = best;
end

function selectedIdx = environmentalSelection(fronts, crowding, populationSize)
% NSGA-II 환경 선택.
selectedIdx = [];
for f = 1:numel(fronts)
    front = fronts{f};
    if numel(selectedIdx) + numel(front) <= populationSize
        selectedIdx = [selectedIdx, front]; %#ok<AGROW>
    else
        remaining = populationSize - numel(selectedIdx);
        [~, order] = sort(crowding(front), "descend");
        selectedIdx = [selectedIdx, front(order(1:remaining))]; %#ok<AGROW>
        break;
    end
end
selectedIdx = selectedIdx(:);
end

function child = crossoverChromosome(parentA, parentB)
% 균등교차.
mask = rand(size(parentA)) < 0.5;
child = parentA;
child(mask) = parentB(mask);
end

function chromosome = mutateChromosome(chromosome, nYears, mutationRate)
% 제거, 연도 이동, 무작위 추가를 섞은 변이.
mask = rand(size(chromosome)) < mutationRate;
if any(mask)
    r = rand(1, nnz(mask));
    newGenes = zeros(1, nnz(mask));
    yearMask = r >= 0.55;
    newGenes(yearMask) = ceil(((r(yearMask) - 0.55) / 0.45) * nYears);
    newGenes(newGenes > nYears) = nYears;
    chromosome(mask) = newGenes;
end

selected = find(chromosome > 0);
if ~isempty(selected)
    shiftCount = max(1, round(numel(selected) * mutationRate * 0.20));
    shiftCount = min(shiftCount, numel(selected));
    shiftIdx = selected(randperm(numel(selected), shiftCount));
    chromosome(shiftIdx) = randi(nYears, 1, shiftCount);
end
end

function chromosome = repairRefillChromosome(chromosome, costMat, primaryMat, fillScoreMat, fillOrderMat, ...
    budgetLower, budgetUpper, capacities)
% 예산·물량 초과를 제거하고, 예산 하한 미달분을 다시 채운다.
nYears = numel(budgetUpper);

% 1단계: 연도별 예산 상한·물량 초과 제거
for y = 1:nYears
    selected = find(chromosome == y);
    if isempty(selected)
        continue;
    end
    totalCost = sum(costMat(selected, y), "omitnan");
    count = numel(selected);
    if count <= capacities(y) && totalCost <= budgetUpper(y)
        continue;
    end

    removalEfficiency = fillScoreMat(selected, y) ./ max(costMat(selected, y), 1);
    [~, removalOrder] = sort(removalEfficiency, "ascend");
    ptr = 1;
    while (count > capacities(y) || totalCost > budgetUpper(y)) && ptr <= numel(removalOrder)
        removeIdx = selected(removalOrder(ptr));
        chromosome(removeIdx) = 0;
        totalCost = totalCost - costMat(removeIdx, y);
        count = count - 1;
        ptr = ptr + 1;
    end
end

% 2단계: 예산 하한 미달 연도 refill
selectedAny = chromosome > 0;
for y = 1:nYears
    selected = find(chromosome == y);
    budgetUsed = sum(costMat(selected, y), "omitnan");
    capacityLeft = capacities(y) - numel(selected);
    if budgetUsed >= budgetLower(y) || capacityLeft <= 0
        continue;
    end

    order = fillOrderMat(:, y);
    for ii = 1:numel(order)
        if budgetUsed >= budgetLower(y) || capacityLeft <= 0
            break;
        end
        k = order(ii);
        if selectedAny(k) || primaryMat(k, y) <= 0 || fillScoreMat(k, y) <= 0
            continue;
        end
        itemCost = costMat(k, y);
        if budgetUsed + itemCost <= budgetUpper(y)
            chromosome(k) = y;
            selectedAny(k) = true;
            budgetUsed = budgetUsed + itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
end
end

function [paretoTable, paretoChromosomes] = buildParetoTable(cfg, population, objectives, violations, metrics, saidiCap, riskCap)
% 최종 인구의 feasible Pareto 해를 표로 정리한다.
[fronts, ~] = constrainedNonDominatedSort(objectives, violations);
front1 = fronts{1};
paretoIdx = front1(violations(front1) <= 1e-9);
if isempty(paretoIdx)
    [~, order] = sort(violations, "ascend");
    paretoIdx = order(1:min(20, numel(order)));
end

paretoChromosomes = population(paretoIdx, :);
M = metrics(paretoIdx, :);
O = objectives(paretoIdx, :);
V = violations(paretoIdx);
n = numel(paretoIdx);

method = repmat(cfg.method, n, 1);
objective = repmat(cfg.objective, n, 1);
scenario_id = repmat(cfg.scenario_id, n, 1);
saidi_cap_rate = repmat(cfg.saidi_cap_rate, n, 1);
risk_cap_rate = repmat(cfg.risk_cap_rate, n, 1);
solution_id = strings(n, 1);
for i = 1:n
    solution_id(i) = cfg.scenario_id + "_" + cfg.method + "_P" + string(i);
end

paretoTable = table(scenario_id, method, objective, saidi_cap_rate, risk_cap_rate, solution_id, (1:n)', ...
    M(:, 10), M(:, 2), M(:, 5), M(:, 4), safeDivideVector(M(:, 5), M(:, 2)), ...
    M(:, 3), M(:, 6), M(:, 7), M(:, 8), M(:, 9), M(:, 1), ...
    -O(:, 1), O(:, 2), M(:, 11), M(:, 12), M(:, 13), M(:, 14), ...
    repmat(saidiCap, n, 1), repmat(riskCap, n, 1), V, ...
    'VariableNames', {'scenario_id', 'method', 'objective', 'saidi_cap_rate', 'risk_cap_rate', ...
    'solution_id', 'solution_index', ...
    'selected_count', 'investment_cost_kkrw', 'risk_reduction_kkrw', ...
    'investment_value_kkrw', 'investment_efficiency', 'saidi_at_selection_min', ...
    'expected_failures_at_selection', 'local_pi_ahp', 'local_pi_fuzzy_adjusted', ...
    'integrated_pi_ahp_alpha05', 'primary_objective_value', 'objective_primary_max', 'objective_cost_min', ...
    'max_saidi_after_cumulative_min', 'max_risk_after_cumulative_kkrw', ...
    'final_2030_saidi_after_cumulative_min', 'final_2030_risk_after_cumulative_kkrw', ...
    'saidi_cap_min', 'risk_cap_kkrw', 'constraint_violation'});
end

function representatives = chooseRepresentatives(cfg, paretoTable)
% Pareto 해 중 대표해를 선택한다.
if height(paretoTable) == 0
    representatives = paretoTable;
    representatives.representative_type = strings(0, 1);
    return;
end

types = strings(0, 1);
indices = [];

[~, idx] = max(paretoTable.primary_objective_value);
types(end + 1, 1) = "max_primary";
indices(end + 1, 1) = idx;

[~, idx] = min(paretoTable.investment_cost_kkrw);
types(end + 1, 1) = "min_cost";
indices(end + 1, 1) = idx;

[~, idx] = max(paretoTable.local_pi_ahp);
types(end + 1, 1) = "max_ahp_pi";
indices(end + 1, 1) = idx;

[~, idx] = max(paretoTable.local_pi_fuzzy_adjusted);
types(end + 1, 1) = "max_fuzzy_pi";
indices(end + 1, 1) = idx;

% 같은 해가 여러 대표 유형에 해당할 수 있으므로 representative_type만 누적 표시한다.
uniqueIdx = unique(indices, "stable");
rows = [];
repType = strings(numel(uniqueIdx), 1);
for i = 1:numel(uniqueIdx)
    idx = uniqueIdx(i);
    rows(end + 1, 1) = idx; %#ok<AGROW>
    repType(i) = strjoin(types(indices == idx), "|");
end
representatives = paretoTable(rows, :);
representatives.representative_type = repType;
representatives = movevars(representatives, "representative_type", "After", "solution_id");
representatives.method = repmat(cfg.method, height(representatives), 1);
representatives.objective = repmat(cfg.objective, height(representatives), 1);
representatives.scenario_id = repmat(cfg.scenario_id, height(representatives), 1);
representatives.saidi_cap_rate = repmat(cfg.saidi_cap_rate, height(representatives), 1);
representatives.risk_cap_rate = repmat(cfg.risk_cap_rate, height(representatives), 1);
end

function idx = findKneePoint(paretoTable)
% 정규화된 유토피아점과의 거리 최소 해를 knee point로 사용한다.
primary = normalizeBenefit(paretoTable.primary_objective_value, true);
cost = normalizeBenefit(paretoTable.investment_cost_kkrw, false);
saidi = normalizeBenefit(paretoTable.saidi_at_selection_min, true);
dist = sqrt((1 - primary).^2 + (1 - cost).^2 + (1 - saidi).^2);
[~, idx] = min(dist);
end

function out = normalizeBenefit(x, largerIsBetter)
x = double(x);
mn = min(x);
mx = max(x);
if mx <= mn
    out = ones(size(x));
    return;
end
if largerIsBetter
    out = (x - mn) ./ (mx - mn);
else
    out = (mx - x) ./ (mx - mn);
end
end

function annualSummary = buildAnnualSummary(cfg, representatives, paretoChromosomes, pof, piWide, integratedPiWide, candidateIdx, years, ...
    baselineSaidi, baselineRisk, saidiCap, riskCap)
% 대표해의 연도별 성과를 계산한다.
rows = {};
for r = 1:height(representatives)
    chromosome = paretoChromosomes(representatives.solution_index(r), :);
    for y = 1:numel(years)
        year = years(y);
        localSelected = find(chromosome == y);
        selected = candidateIdx(localSelected);
        cumulativeLocalSelected = find(chromosome > 0 & chromosome <= y);
        cumulativeSelected = candidateIdx(cumulativeLocalSelected);
        cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
        riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
        investmentValue = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
        saidi = sum(pof.(sprintf("saidi_%d_min", year))(selected), "omitnan");
        failures = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
        ahpPi = sum(piWide.(sprintf("local_pi_ahp_%d", year))(selected), "omitnan");
        fuzzyPi = sum(piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(selected), "omitnan");
        integratedPi = sum(getIntegratedPiByYear(integratedPiWide, selected, year), "omitnan");
        primary = getPrimaryValue(cfg.objective, investmentValue, ahpPi, fuzzyPi, integratedPi);
        saidiReductionCumulative = sum(pof.(sprintf("saidi_%d_min", year))(cumulativeSelected), "omitnan");
        riskReductionCumulative = sum(pof.(sprintf("risk_%d_kkrw", year))(cumulativeSelected), "omitnan");
        saidiAfter = baselineSaidi(y) - saidiReductionCumulative;
        riskAfter = baselineRisk(y) - riskReductionCumulative;
        rows(end + 1, :) = {cfg.scenario_id, cfg.method, cfg.objective, cfg.saidi_cap_rate, cfg.risk_cap_rate, ...
            representatives.solution_id(r), representatives.representative_type(r), year, numel(selected), cost, ...
            riskReduction, investmentValue, safeDivide(riskReduction, cost), ...
            saidi, failures, ahpPi, fuzzyPi, integratedPi, primary, ...
            baselineSaidi(y), saidiReductionCumulative, saidiAfter, saidiCap, saidiAfter <= saidiCap + 1e-9, ...
            baselineRisk(y), riskReductionCumulative, riskAfter, riskCap, riskAfter <= riskCap + 1e-6}; %#ok<AGROW>
    end
end
annualSummary = cell2table(rows, 'VariableNames', {'scenario_id', 'method', 'objective', ...
    'saidi_cap_rate', 'risk_cap_rate', 'solution_id', ...
    'representative_type', 'year', 'selected_count', 'investment_cost_kkrw', ...
    'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
    'saidi_at_selection_min', 'expected_failures_at_selection', ...
    'local_pi_ahp', 'local_pi_fuzzy_adjusted', 'integrated_pi_ahp_alpha05', 'primary_objective_value', ...
    'baseline_saidi_min', 'saidi_reduction_cumulative_min', 'saidi_after_cumulative_min', ...
    'saidi_cap_min', 'saidi_cap_ok', 'baseline_risk_kkrw', ...
    'risk_reduction_cumulative_kkrw', 'risk_after_cumulative_kkrw', ...
    'risk_cap_kkrw', 'risk_cap_ok'});
end

function selectedAssets = buildSelectedAssets(cfg, representatives, paretoChromosomes, pof, piWide, integratedPiWide, candidateIdx, years)
% 대표해의 선택 자산 상세표.
rows = {};
for r = 1:height(representatives)
    chromosome = paretoChromosomes(representatives.solution_index(r), :);
    for y = 1:numel(years)
        year = years(y);
        localSelected = find(chromosome == y);
        selected = candidateIdx(localSelected);
        for ii = 1:numel(selected)
            idx = selected(ii);
            investmentValue = pof.(sprintf("investment_value_%d_kkrw", year))(idx);
            ahpPi = piWide.(sprintf("local_pi_ahp_%d", year))(idx);
            fuzzyPi = piWide.(sprintf("local_pi_fuzzy_adjusted_%d", year))(idx);
            integratedPi = getIntegratedPiByYear(integratedPiWide, idx, year);
            primary = getPrimaryValue(cfg.objective, investmentValue, ahpPi, fuzzyPi, integratedPi);
            rows(end + 1, :) = {cfg.scenario_id, cfg.method, cfg.objective, cfg.saidi_cap_rate, cfg.risk_cap_rate, ...
                representatives.solution_id(r), representatives.representative_type(r), string(pof.asset_id(idx)), ...
                string(pof.asset_type(idx)), string(piWide.asset_label(idx)), ...
                string(piWide.asset_group(idx)), year, ...
                pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
                pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
                investmentValue, pof.(sprintf("bcr_%d", year))(idx), ...
                pof.(sprintf("saidi_%d_min", year))(idx), ...
                pof.(sprintf("pof_%d", year))(idx), ahpPi, fuzzyPi, integratedPi, primary}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    selectedAssets = table();
else
    selectedAssets = cell2table(rows, 'VariableNames', {'scenario_id', 'method', 'objective', ...
        'saidi_cap_rate', 'risk_cap_rate', 'solution_id', ...
        'representative_type', 'asset_id', 'asset_type', 'asset_label', 'asset_group', ...
        'replacement_year', 'replacement_cost_kkrw', 'risk_reduction_kkrw', ...
        'investment_value_kkrw', 'investment_efficiency', 'saidi_at_replacement_min', ...
        'pof_at_replacement', 'local_pi_ahp', 'local_pi_fuzzy_adjusted', ...
        'integrated_pi_ahp_alpha05', 'primary_objective_value'});
    selectedAssets = sortrows(selectedAssets, {'method', 'solution_id', 'replacement_year', 'primary_objective_value'}, ...
        {'ascend', 'ascend', 'ascend', 'descend'});
end
end

function values = getIntegratedPiByYear(integratedPiWide, selected, year)
% Integrated PI 파일이 없을 때도 기존 Local PI 실행이 깨지지 않도록 0을 반환한다.
if isempty(selected)
    values = zeros(0, 1);
    return;
end
if isempty(integratedPiWide)
    values = zeros(numel(selected), 1);
    return;
end
values = integratedPiWide.(sprintf("integrated_pi_ahp_alpha_0_5_%d", year))(selected);
end

function value = getPrimaryValue(objective, investmentValue, ahpPi, fuzzyPi, integratedPi)
% NSGA 시나리오별 1번 목적함수 값을 반환한다.
if objective == "investment_value"
    value = investmentValue;
elseif objective == "local_pi_ahp"
    value = ahpPi;
elseif objective == "local_pi_fuzzy_adjusted"
    value = fuzzyPi;
elseif objective == "integrated_pi_ahp_alpha05"
    value = integratedPi;
else
    error("알 수 없는 objective입니다: %s", objective);
end
end

function runSummary = buildRunSummary(cfg, paretoTable, representatives, progress)
% 시나리오별 실행 요약.
last = progress(end, :);
runSummary = table(cfg.scenario_id, cfg.method, cfg.objective, cfg.saidi_cap_rate, cfg.risk_cap_rate, ...
    height(paretoTable), height(representatives), ...
    last.feasible_count, last.best_primary, last.min_cost_kkrw, last.best_saidi, ...
    max(paretoTable.investment_value_kkrw), min(paretoTable.investment_cost_kkrw), ...
    max(paretoTable.saidi_at_selection_min), max(paretoTable.local_pi_ahp), ...
    max(paretoTable.local_pi_fuzzy_adjusted), min(paretoTable.constraint_violation), ...
    max(paretoTable.max_saidi_after_cumulative_min), max(paretoTable.max_risk_after_cumulative_kkrw), ...
    max(paretoTable.saidi_cap_min), max(paretoTable.risk_cap_kkrw), ...
    'VariableNames', {'scenario_id', 'method', 'objective', 'saidi_cap_rate', 'risk_cap_rate', ...
    'pareto_solution_count', ...
    'representative_count', 'final_feasible_count', 'final_best_primary', ...
    'final_min_cost_kkrw', 'final_best_saidi', 'pareto_max_investment_value_kkrw', ...
    'pareto_min_cost_kkrw', 'pareto_max_saidi', 'pareto_max_ahp_pi', ...
    'pareto_max_fuzzy_pi', 'pareto_min_constraint_violation', ...
    'pareto_max_saidi_after_cumulative_min', 'pareto_max_risk_after_cumulative_kkrw', ...
    'saidi_cap_min', 'risk_cap_kkrw'});
end

function T = buildCandidateSummary(pof, candidateMask, nsgaPopulation, nsgaGenerations, nsgaMutationRate, ...
    budgetRate, capacityRate, budgetFloorRate, saidiCapRate, riskCapRates)
% 후보군 및 NSGA 설정 요약.
nAssets = height(pof);
candidateCount = sum(candidateMask);
items = [
    "total_assets"
    "risk_top30_current_assets"
    "investment_value_top30_current_assets"
    "optimization_candidate_assets"
    "optimization_candidate_ratio"
    "nsga_population"
    "nsga_generations"
    "nsga_mutation_rate"
    "budget_rate"
    "budget_floor_rate"
    "capacity_rate"
    "saidi_cap_rate"
    "risk_cap_rate_min"
    "risk_cap_rate_max"
    "risk_cap_scenario_count"
    ];
values = [
    nAssets
    sum(pof.("risk_top30_current"))
    sum(pof.("investment_value_top30_current"))
    candidateCount
    candidateCount / nAssets
    nsgaPopulation
    nsgaGenerations
    nsgaMutationRate
    budgetRate
    budgetFloorRate
    capacityRate
    saidiCapRate
    min(riskCapRates)
    max(riskCapRates)
    numel(riskCapRates)
    ];
notes = [
    "all assets in pof_5yr_output"
    "top 30% by risk_2026_kkrw"
    "top 30% by investment_value_2026_kkrw"
    "candidate_top30_current = 1"
    "candidate assets / total assets"
    "NSGA-II population"
    "NSGA-II generations"
    "NSGA-II mutation probability"
    "annual budget ratio"
    "0 means no lower-bound budget constraint"
    "annual construction capacity ratio"
    "SAIDI cap = 2026 baseline * this rate"
    "minimum Risk cap scenario rate"
    "maximum Risk cap scenario rate"
    "Risk cap scenarios = " + strjoin(compose("%.3f", riskCapRates), ", ")
    ];
T = table(items, values, notes, 'VariableNames', {'item', 'value', 'note'});
end

function T = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, budgetFloorRate, ...
    annualBudgetBaseKkrw, annualCapacity, budgetLower, budgetUpper, capacities, years, ...
    baselineSaidi, baselineRisk, saidiCap, saidiCapRate, riskCapRates)
% 제약조건 요약.
riskCapValues = baselineRisk(1) .* riskCapRates;
riskCap = max(riskCapValues);
items = ["total_asset_value_proxy_kkrw"; "budget_rate"; "budget_floor_rate"; ...
    "capacity_rate"; "annual_budget_base_2026_kkrw"; "annual_capacity_assets"; ...
    "saidi_2026_baseline_min"; "saidi_cap_min"; ...
    "risk_2026_baseline_kkrw"; "risk_cap_kkrw"];
values = [totalAssetValueKkrw; budgetRate; budgetFloorRate; capacityRate; ...
    annualBudgetBaseKkrw; annualCapacity; baselineSaidi(1); saidiCap; ...
    baselineRisk(1); riskCap];
notes = ["sum of replacement_cost_2026_kkrw"; "annual budget upper ratio"; ...
    "0 means no lower-bound budget constraint"; "annual capacity ratio"; ...
    "base annual budget before discounting"; "round(total assets * capacity rate)"; ...
    "sum of SAIDI_2026 before replacement"; "fixed upper cap = 2026 baseline * kpi_cap_rate"; ...
    "sum of Risk_2026 before replacement"; "fixed upper cap = 2026 baseline * kpi_cap_rate"];
items(end + 1, 1) = "saidi_cap_rate"; %#ok<AGROW>
values(end + 1, 1) = saidiCapRate; %#ok<AGROW>
notes(end + 1, 1) = "SAIDI fixed cap rate"; %#ok<AGROW>
for s = 1:numel(riskCapRates)
    scenarioId = "risk_cap_" + string(round(riskCapRates(s) * 1000));
    items(end + 1, 1) = scenarioId + "_risk_cap_rate"; %#ok<AGROW>
    values(end + 1, 1) = riskCapRates(s); %#ok<AGROW>
    notes(end + 1, 1) = "Risk cap scenario rate"; %#ok<AGROW>
    items(end + 1, 1) = scenarioId + "_risk_cap_kkrw"; %#ok<AGROW>
    values(end + 1, 1) = riskCapValues(s); %#ok<AGROW>
    notes(end + 1, 1) = "Risk cap = 2026 baseline Risk * scenario rate"; %#ok<AGROW>
end
for y = 1:numel(years)
    items(end + 1, 1) = "budget_upper_" + years(y) + "_kkrw"; %#ok<AGROW>
    values(end + 1, 1) = budgetUpper(y); %#ok<AGROW>
    notes(end + 1, 1) = "annual budget upper bound"; %#ok<AGROW>
    items(end + 1, 1) = "capacity_" + years(y) + "_assets"; %#ok<AGROW>
    values(end + 1, 1) = capacities(y); %#ok<AGROW>
    notes(end + 1, 1) = "annual construction capacity"; %#ok<AGROW>
    items(end + 1, 1) = "baseline_saidi_" + years(y) + "_min"; %#ok<AGROW>
    values(end + 1, 1) = baselineSaidi(y); %#ok<AGROW>
    notes(end + 1, 1) = "SAIDI before cumulative replacement in this year"; %#ok<AGROW>
    items(end + 1, 1) = "baseline_risk_" + years(y) + "_kkrw"; %#ok<AGROW>
    values(end + 1, 1) = baselineRisk(y); %#ok<AGROW>
    notes(end + 1, 1) = "Risk before cumulative replacement in this year"; %#ok<AGROW>
end
T = table(items, values, notes, 'VariableNames', {'item', 'value', 'note'});
end

function out = safeDivide(a, b)
% 0 나누기 방지.
if b == 0
    out = 0;
else
    out = a / b;
end
end

function out = safeDivideVector(a, b)
% 벡터 0 나누기 방지.
out = zeros(size(a));
idx = b ~= 0;
out(idx) = a(idx) ./ b(idx);
end
