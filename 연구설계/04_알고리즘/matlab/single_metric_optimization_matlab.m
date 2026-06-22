%% 단일지표 투자 최적화 - MATLAB 버전
% 입력/PoF 산출은 Python 파이프라인 결과를 사용하고, 최적화만 MATLAB에서 수행한다.
% 공통 후보군은 현재년도 Risk 또는 투자가치 상위 30% 설비(candidate_top30_current = 1)이다.

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputDir = fullfile(baseDir, "outputs");
if ~isfolder(outputDir)
    mkdir(outputDir);
end

inputFile = fullfile(dataDir, "pof_5yr_output.xlsx");
outputFile = fullfile(outputDir, "single_metric_optimization_matlab.xlsx");
runLogFile = fullfile(outputDir, "single_metric_optimization_matlab.log");

years = [2026 2027 2028 2029 2030];
nYears = numel(years);
discountRate = 0.05;
budgetRate = 0.04;
capacityRate = 0.05;
candidateFlag = "candidate_top30_current";

nsgaSeed = 20260619;
nsgaPopulation = 120;
nsgaGenerations = 300;
nsgaMutationRate = 0.020;
nsgaTournamentSize = 3;

diary(runLogFile);
diary on;
cleanupObj = onCleanup(@() diary("off"));

fprintf("single metric optimization - MATLAB\n");
fprintf("input: %s\n", inputFile);

pof = readtable(inputFile, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
nAssets = height(pof);
candidateMask = pof.(candidateFlag) == 1;
candidateIdx = find(candidateMask);
nCandidates = numel(candidateIdx);

totalAssetValueKkrw = sum(pof.("replacement_cost_2026_kkrw"), "omitnan");
annualBudgetBaseKkrw = totalAssetValueKkrw * budgetRate;
budgets = annualBudgetBaseKkrw ./ ((1 + discountRate) .^ (0:nYears-1));
annualCapacity = round(nAssets * capacityRate);
capacities = repmat(annualCapacity, 1, nYears);

fprintf("assets: %d\n", nAssets);
fprintf("candidate assets: %d\n", nCandidates);
fprintf("annual budget base: %.3f kkrw\n", annualBudgetBaseKkrw);
fprintf("annual capacity: %d assets\n", annualCapacity);

costMat = zeros(nCandidates, nYears);
riskMat = zeros(nCandidates, nYears);
riskReductionMat = zeros(nCandidates, nYears);
valueMat = zeros(nCandidates, nYears);
saidiMat = zeros(nCandidates, nYears);
pofMat = zeros(nCandidates, nYears);
bcrMat = zeros(nCandidates, nYears);
for y = 1:nYears
    year = years(y);
    costMat(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year))(candidateIdx);
    riskMat(:, y) = pof.(sprintf("risk_%d_kkrw", year))(candidateIdx);
    riskReductionMat(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year))(candidateIdx);
    valueMat(:, y) = pof.(sprintf("investment_value_%d_kkrw", year))(candidateIdx);
    saidiMat(:, y) = pof.(sprintf("saidi_%d_min", year))(candidateIdx);
    pofMat(:, y) = pof.(sprintf("pof_%d", year))(candidateIdx);
    bcrMat(:, y) = pof.(sprintf("bcr_%d", year))(candidateIdx);
end

fprintf("running risk greedy...\n");
riskChoice = runGreedy(nAssets, candidateIdx, costMat, riskMat, budgets, capacities);

fprintf("running investment value greedy...\n");
valueChoice = runGreedy(nAssets, candidateIdx, costMat, valueMat, budgets, capacities);

fprintf("running investment value ILP with intlinprog...\n");
[ilpChoice, ilpStatus] = runInvestmentValueIlp( ...
    nAssets, candidateIdx, costMat, valueMat, budgets, capacities);

fprintf("running NSGA-II optimization...\n");
[nsgaChoice, nsgaObjective, nsgaProgress, nsgaPareto] = runNsga2( ...
    nAssets, candidateIdx, costMat, riskReductionMat, valueMat, budgets, capacities, ...
    nsgaSeed, nsgaPopulation, nsgaGenerations, nsgaMutationRate, nsgaTournamentSize);

methodNames = ["risk_greedy"; "investment_value_greedy"; "investment_value_ilp"; "investment_value_nsga2"];
choices = {riskChoice; valueChoice; ilpChoice; nsgaChoice};

candidateSummary = buildCandidateSummary(pof, candidateMask, nsgaPopulation, nsgaGenerations, nsgaMutationRate);
constraints = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, annualBudgetBaseKkrw, ...
    annualCapacity, budgets, capacities, years);
annualSummary = buildAnnualSummary(methodNames, choices, pof, years, budgets, capacities);
totalSummary = buildTotalSummary(methodNames, annualSummary);
selectedAssets = buildSelectedAssets(methodNames, choices, pof, years);
assetTypeSummary = buildAssetTypeSummary(selectedAssets);
feasibility = buildFeasibility(methodNames, choices, pof, years, budgets, capacities, candidateMask);
solverStatus = buildSolverStatus(ilpStatus, nsgaObjective, nsgaPopulation, nsgaGenerations, nsgaMutationRate, candidateFlag);
nsgaProgressTable = table((1:height(nsgaProgress))', nsgaProgress.best_investment_value_kkrw, ...
    nsgaProgress.best_risk_reduction_kkrw, nsgaProgress.min_cost_kkrw, nsgaProgress.pareto_count, ...
    'VariableNames', {'generation', 'best_investment_value_kkrw', 'best_risk_reduction_kkrw', 'min_cost_kkrw', 'pareto_count'});

if isfile(outputFile)
    delete(outputFile);
end
writetable(candidateSummary, outputFile, "Sheet", "candidate_summary");
writetable(constraints, outputFile, "Sheet", "constraints");
writetable(totalSummary, outputFile, "Sheet", "total_summary");
writetable(annualSummary, outputFile, "Sheet", "annual_summary");
writetable(assetTypeSummary, outputFile, "Sheet", "asset_type_summary");
writetable(selectedAssets, outputFile, "Sheet", "selected_assets");
writetable(feasibility, outputFile, "Sheet", "feasibility");
writetable(solverStatus, outputFile, "Sheet", "solver_status");
writetable(nsgaProgressTable, outputFile, "Sheet", "nsga_progress");
writetable(nsgaPareto, outputFile, "Sheet", "nsga_pareto");

fprintf("saved: %s\n", outputFile);

%% 지역 함수

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

function [choice, status] = runInvestmentValueIlp(nAssets, candidateIdx, costMat, valueMat, budgets, capacities)
% 투자가치 총합을 최대화하는 0-1 정수계획법을 구성한다.
nCandidates = numel(candidateIdx);
nYears = numel(budgets);
nVars = nCandidates * nYears;

f = -valueMat(:);
intcon = 1:nVars;
lb = zeros(nVars, 1);
ub = ones(nVars, 1);

% 자산별 최대 1회 교체 제약: [I I I I I] x <= 1
AAsset = kron(ones(1, nYears), speye(nCandidates));
bAsset = ones(nCandidates, 1);

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
    "Display", "iter");

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
status.objective_kkrw = -fval;
status.message = string(output.message);
status.relative_gap = getOptionalField(output, "relativegap");
status.absolute_gap = getOptionalField(output, "absolutegap");
status.nodes = getOptionalField(output, "numnodes");
status.iterations = getOptionalField(output, "iterations");
end

function value = getOptionalField(s, fieldName)
% MATLAB 버전에 따라 output 필드명이 다를 수 있어 안전하게 읽는다.
if isfield(s, fieldName)
    value = s.(fieldName);
else
    value = NaN;
end
end

function [choice, bestScore, progress] = runCustomGa(nAssets, candidateIdx, costMat, riskMat, valueMat, ...
    budgets, capacities, seed, populationSize, generations, mutationRate, tournamentSize)
% Global Optimization Toolbox 없이 실행 가능한 custom GA.
% 그리디 결과를 강제로 포함하지 않고, 후보군 내부에서 비용 대비 효율 기반 무작위 초기해를 생성한다.
rng(seed);
nCandidates = numel(candidateIdx);
nYears = numel(budgets);
population = zeros(populationSize, nCandidates);

for p = 1:populationSize
    if mod(p, 3) == 1
        scoreMat = valueMat ./ max(costMat, 1);
    elseif mod(p, 3) == 2
        scoreMat = valueMat;
    else
        scoreMat = riskMat .* (valueMat ./ max(costMat, 1));
    end
    noise = 0.80 + 0.40 * rand(nCandidates, nYears);
    population(p, :) = makeSeedChromosome(costMat, valueMat, scoreMat .* noise, budgets, capacities);
end

scores = zeros(populationSize, 1);
for p = 1:populationSize
    population(p, :) = repairChromosome(population(p, :), costMat, valueMat, budgets, capacities);
    scores(p) = chromosomeObjective(population(p, :), valueMat);
end

[bestScore, bestIdx] = max(scores);
bestChromosome = population(bestIdx, :);
progress = zeros(generations + 1, 1);
progress(1) = bestScore;

for g = 1:generations
    newPopulation = zeros(size(population));
    newPopulation(1, :) = bestChromosome;
    for p = 2:populationSize
        parentA = population(tournamentSelect(scores, tournamentSize), :);
        parentB = population(tournamentSelect(scores, tournamentSize), :);
        child = parentA;
        mask = rand(1, nCandidates) < 0.5;
        child(mask) = parentB(mask);
        child = mutateChromosome(child, nYears, mutationRate);
        child = repairChromosome(child, costMat, valueMat, budgets, capacities);
        newPopulation(p, :) = child;
    end
    population = newPopulation;
    for p = 1:populationSize
        scores(p) = chromosomeObjective(population(p, :), valueMat);
    end
    [genBest, genBestIdx] = max(scores);
    if genBest > bestScore
        bestScore = genBest;
        bestChromosome = population(genBestIdx, :);
    end
    progress(g + 1) = bestScore;
    if mod(g, 10) == 0 || g == generations
        fprintf("GA generation %d/%d, best objective %.3f\n", g, generations, bestScore);
    end
end

choice = zeros(nAssets, 1);
for y = 1:nYears
    localSelected = find(bestChromosome == y);
    choice(candidateIdx(localSelected)) = y;
end
end

function [choice, representativeValue, progressTable, paretoTable] = runNsga2(nAssets, candidateIdx, ...
    costMat, riskMat, valueMat, budgets, capacities, seed, populationSize, generations, mutationRate, tournamentSize)
% NSGA-II 직접 구현.
% 목적함수는 ① 투자가치 최대화, ② Risk 선택량 최대화, ③ 투자비용 최소화이다.
% SAIDI는 단일지표 최적화 목적함수에서 제외하고, 결과표의 보고 지표로만 사용한다.
% 단일지표 비교 대표해는 Pareto 해집합 중 투자가치가 가장 큰 해로 선정한다.
rng(seed);
nCandidates = numel(candidateIdx);
nYears = numel(budgets);
population = zeros(populationSize, nCandidates);
scoreBank = buildNsgaScoreBank(costMat, riskMat, valueMat);
orderBank = buildOrderBank(scoreBank);

for p = 1:populationSize
    scoreIdx = mod(p - 1, numel(scoreBank)) + 1;
    scoreMat = scoreBank{scoreIdx};
    if p <= numel(scoreBank)
        noise = ones(nCandidates, nYears);
    else
        noise = 0.70 + 0.60 * rand(nCandidates, nYears);
    end
    population(p, :) = makeSeedChromosome(costMat, valueMat, scoreMat .* noise, budgets, capacities);
    population(p, :) = repairRefillChromosome(population(p, :), costMat, valueMat, ...
        scoreMat, orderBank{scoreIdx}, budgets, capacities);
end

[objectives, metrics] = evaluatePopulation(population, costMat, riskMat, valueMat);
[rank, crowding, fronts] = rankAndCrowding(objectives);
progressRows = cell(generations, 5);

for g = 1:generations
    offspring = zeros(populationSize, nCandidates);
    for p = 1:populationSize
        parentA = population(nsgaTournamentSelect(rank, crowding, tournamentSize), :);
        parentB = population(nsgaTournamentSelect(rank, crowding, tournamentSize), :);
        child = parentA;
        mask = rand(1, nCandidates) < 0.5;
        child(mask) = parentB(mask);
        child = mutatePortfolioChromosome(child, nYears, mutationRate);
        scoreIdx = randi(numel(scoreBank));
        child = repairRefillChromosome(child, costMat, valueMat, ...
            scoreBank{scoreIdx}, orderBank{scoreIdx}, budgets, capacities);
        offspring(p, :) = child;
    end

    combined = [population; offspring];
    [combinedObjectives, combinedMetrics] = evaluatePopulation(combined, costMat, riskMat, valueMat);
    [combinedRank, combinedCrowding, combinedFronts] = rankAndCrowding(combinedObjectives);
    selectedIdx = environmentalSelection(combinedFronts, combinedCrowding, populationSize);
    [~, scalarBestIdx] = max(combinedMetrics(:, 1));
    if ~ismember(scalarBestIdx, selectedIdx)
        selectedIdx(end) = scalarBestIdx;
    end
    population = combined(selectedIdx, :);
    objectives = combinedObjectives(selectedIdx, :);
    metrics = combinedMetrics(selectedIdx, :);
    [rank, crowding, fronts] = rankAndCrowding(objectives);

    progressRows(g, :) = {g, max(metrics(:, 1)), max(metrics(:, 2)), min(metrics(:, 3)), numel(fronts{1})};
    if mod(g, 10) == 0 || g == generations
        fprintf("NSGA-II generation %d/%d, best IV %.3f, pareto %d\n", ...
            g, generations, max(metrics(:, 1)), numel(fronts{1}));
    end
end

paretoLocalIdx = fronts{1};
paretoMetrics = metrics(paretoLocalIdx, :);
paretoPopulation = population(paretoLocalIdx, :);

% 단일지표 비교 대표해: 투자가치 최대, 동률이면 비용 최소
[~, valueOrder] = sortrows([-paretoMetrics(:, 1), paretoMetrics(:, 3)]);
representativeLocal = valueOrder(1);
bestChromosome = paretoPopulation(representativeLocal, :);
representativeValue = paretoMetrics(representativeLocal, 1);

choice = zeros(nAssets, 1);
for y = 1:nYears
    localSelected = find(bestChromosome == y);
    choice(candidateIdx(localSelected)) = y;
end

progressTable = cell2table(progressRows, 'VariableNames', {'generation', ...
    'best_investment_value_kkrw', 'best_risk_reduction_kkrw', 'min_cost_kkrw', 'pareto_count'});
paretoTable = table((1:size(paretoMetrics, 1))', paretoMetrics(:, 1), paretoMetrics(:, 2), ...
    paretoMetrics(:, 3), paretoMetrics(:, 4), ...
    'VariableNames', {'pareto_rank', 'investment_value_kkrw', 'risk_reduction_kkrw', ...
    'investment_cost_kkrw', 'selected_count'});
end

function [objectives, metrics] = evaluatePopulation(population, costMat, riskMat, valueMat)
% NSGA-II 목적함수와 보고용 지표를 계산한다.
nPop = size(population, 1);
objectives = zeros(nPop, 3);
metrics = zeros(nPop, 4);
for p = 1:nPop
    [value, risk, cost, selectedCount] = chromosomeMetrics( ...
        population(p, :), costMat, riskMat, valueMat);
    objectives(p, :) = [-value, -risk, cost];
    metrics(p, :) = [value, risk, cost, selectedCount];
end
end

function [value, risk, cost, selectedCount] = chromosomeMetrics(chromosome, costMat, riskMat, valueMat)
% 염색체의 투자가치, Risk, 비용, 선택 대수를 계산한다.
value = 0;
risk = 0;
cost = 0;
selectedCount = 0;
for y = 1:size(valueMat, 2)
    selected = chromosome == y;
    if any(selected)
        value = value + sum(valueMat(selected, y), "omitnan");
        risk = risk + sum(riskMat(selected, y), "omitnan");
        cost = cost + sum(costMat(selected, y), "omitnan");
        selectedCount = selectedCount + nnz(selected);
    end
end
end

function [rank, crowding, fronts] = rankAndCrowding(objectives)
% 비지배 정렬과 crowding distance 계산.
fronts = fastNonDominatedSort(objectives);
n = size(objectives, 1);
rank = inf(n, 1);
crowding = zeros(n, 1);
for f = 1:numel(fronts)
    front = fronts{f};
    rank(front) = f;
    crowding(front) = crowdingDistance(objectives, front);
end
end

function fronts = fastNonDominatedSort(objectives)
% NSGA-II의 fast non-dominated sorting.
n = size(objectives, 1);
S = cell(n, 1);
dominatedCount = zeros(n, 1);
fronts = {};
front1 = [];
for p = 1:n
    S{p} = [];
    for q = 1:n
        if p == q
            continue;
        end
        if dominates(objectives(p, :), objectives(q, :))
            S{p}(end + 1) = q; %#ok<AGROW>
        elseif dominates(objectives(q, :), objectives(p, :))
            dominatedCount(p) = dominatedCount(p) + 1;
        end
    end
    if dominatedCount(p) == 0
        front1(end + 1) = p; %#ok<AGROW>
    end
end
fronts{1} = front1;
i = 1;
while i <= numel(fronts) && ~isempty(fronts{i})
    nextFront = [];
    for p = fronts{i}
        for q = S{p}
            dominatedCount(q) = dominatedCount(q) - 1;
            if dominatedCount(q) == 0
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

function tf = dominates(a, b)
% minimization 기준 지배관계.
tf = all(a <= b) && any(a < b);
end

function distance = crowdingDistance(objectives, front)
% front 내부 crowding distance.
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

function scoreBank = buildNsgaScoreBank(costMat, riskMat, valueMat)
% NSGA-II 초기해와 refill에 사용할 다양한 탐색 점수.
investmentEfficiency = riskMat ./ max(costMat, 1);
riskEfficiency = investmentEfficiency;
balanced = normalizeMetric(valueMat) + normalizeMetric(riskMat) + normalizeMetric(investmentEfficiency);
costAware = normalizeMetric(valueMat) + normalizeMetric(riskMat) - 0.30 * normalizeMetric(costMat);
scoreBank = {valueMat, investmentEfficiency, riskMat, riskEfficiency, riskMat .* investmentEfficiency, balanced, costAware};
end

function orderBank = buildOrderBank(scoreBank)
% scoreBank별 연도 내림차순 정렬 인덱스를 미리 계산한다.
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

function out = normalizeMetric(x)
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

function chromosome = repairRefillChromosome(chromosome, costMat, valueMat, fillScoreMat, fillOrderMat, budgets, capacities)
% 제약 초과분을 제거한 뒤 남은 예산·물량으로 다시 채우는 repair/refill 연산자.
nYears = numel(budgets);

% 1단계: 연도별 예산·물량 초과 제거
for y = 1:nYears
    selected = find(chromosome == y);
    if isempty(selected)
        continue;
    end
    totalCost = sum(costMat(selected, y), "omitnan");
    count = numel(selected);
    if count <= capacities(y) && totalCost <= budgets(y)
        continue;
    end

    removalEfficiency = fillScoreMat(selected, y) ./ max(costMat(selected, y), 1);
    [~, removalOrder] = sort(removalEfficiency, "ascend");
    ptr = 1;
    while (count > capacities(y) || totalCost > budgets(y)) && ptr <= numel(removalOrder)
        removeIdx = selected(removalOrder(ptr));
        chromosome(removeIdx) = 0;
        totalCost = totalCost - costMat(removeIdx, y);
        count = count - 1;
        ptr = ptr + 1;
    end
end

% 2단계: 남은 예산·물량 재충전
selectedAny = chromosome > 0;
for y = 1:nYears
    selected = find(chromosome == y);
    budgetLeft = budgets(y) - sum(costMat(selected, y), "omitnan");
    capacityLeft = capacities(y) - numel(selected);
    if budgetLeft <= 0 || capacityLeft <= 0
        continue;
    end

    order = fillOrderMat(:, y);
    minCost = min(costMat(:, y), [], "omitnan");
    for ii = 1:numel(order)
        if capacityLeft <= 0 || budgetLeft < minCost
            break;
        end
        k = order(ii);
        if selectedAny(k) || valueMat(k, y) <= 0 || fillScoreMat(k, y) <= 0
            continue;
        end
        itemCost = costMat(k, y);
        if itemCost <= budgetLeft
            chromosome(k) = y;
            selectedAny(k) = true;
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
end
end

function chromosome = mutatePortfolioChromosome(chromosome, nYears, mutationRate)
% 포트폴리오 탐색용 변이: 제거, 연도 이동, 무작위 추가를 섞는다.
mutated = rand(size(chromosome)) < mutationRate;
if any(mutated)
    r = rand(1, nnz(mutated));
    newGenes = zeros(1, nnz(mutated));
    yearMask = r >= 0.60;
    newGenes(yearMask) = ceil(((r(yearMask) - 0.60) / 0.40) * nYears);
    newGenes(newGenes > nYears) = nYears;
    chromosome(mutated) = newGenes;
end

selected = find(chromosome > 0);
if ~isempty(selected)
    shiftCount = max(1, round(numel(selected) * mutationRate * 0.25));
    shiftCount = min(shiftCount, numel(selected));
    shiftIdx = selected(randperm(numel(selected), shiftCount));
    chromosome(shiftIdx) = randi(nYears, 1, shiftCount);
end
end

function chromosome = makeSeedChromosome(costMat, valueMat, scoreMat, budgets, capacities)
% 점수 기반으로 실행 가능한 초기 염색체를 생성한다.
[nCandidates, nYears] = size(costMat);
chromosome = zeros(1, nCandidates);
remaining = true(nCandidates, 1);
for y = 1:nYears
    budgetLeft = budgets(y);
    capacityLeft = capacities(y);
    [~, order] = sort(scoreMat(:, y), "descend");
    for ii = 1:numel(order)
        k = order(ii);
        if ~remaining(k) || valueMat(k, y) <= 0
            continue;
        end
        itemCost = costMat(k, y);
        if itemCost <= budgetLeft && capacityLeft > 0
            chromosome(k) = y;
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

function chromosome = repairChromosome(chromosome, costMat, valueMat, budgets, capacities)
% 연도별 예산·물량 제약을 만족하도록 염색체를 복구한다.
nYears = numel(budgets);
for y = 1:nYears
    selected = find(chromosome == y);
    if isempty(selected)
        continue;
    end
    totalCost = sum(costMat(selected, y), "omitnan");
    if numel(selected) <= capacities(y) && totalCost <= budgets(y)
        continue;
    end
    efficiency = valueMat(selected, y) ./ max(costMat(selected, y), 1);
    [~, order] = sort(efficiency, "descend");
    keep = [];
    budgetLeft = budgets(y);
    capacityLeft = capacities(y);
    for ii = 1:numel(order)
        k = selected(order(ii));
        itemCost = costMat(k, y);
        if itemCost <= budgetLeft && capacityLeft > 0
            keep(end + 1) = k; %#ok<AGROW>
            budgetLeft = budgetLeft - itemCost;
            capacityLeft = capacityLeft - 1;
        end
    end
    chromosome(selected) = 0;
    chromosome(keep) = y;
end
end

function score = chromosomeObjective(chromosome, valueMat)
% 염색체의 투자가치 목적함수값.
score = 0;
for y = 1:size(valueMat, 2)
    selected = chromosome == y;
    if any(selected)
        score = score + sum(valueMat(selected, y), "omitnan");
    end
end
end

function idx = tournamentSelect(scores, tournamentSize)
% 토너먼트 선택.
n = numel(scores);
candidates = randi(n, tournamentSize, 1);
[~, bestLocal] = max(scores(candidates));
idx = candidates(bestLocal);
end

function chromosome = mutateChromosome(chromosome, nYears, mutationRate)
% 돌연변이. 0은 미교체, 1~nYears는 교체연도 인덱스이다.
mask = rand(size(chromosome)) < mutationRate;
if any(mask)
    r = rand(1, nnz(mask));
    newGenes = zeros(1, nnz(mask));
    yearMask = r >= 0.55;
    newGenes(yearMask) = ceil(((r(yearMask) - 0.55) / 0.45) * nYears);
    newGenes(newGenes > nYears) = nYears;
    chromosome(mask) = newGenes;
end
end

function T = buildCandidateSummary(pof, candidateMask, nsgaPopulation, nsgaGenerations, nsgaMutationRate)
% 후보군 및 알고리즘 설정 요약.
nAssets = height(pof);
candidateCount = sum(candidateMask);
T = table( ...
    ["total_assets"; "risk_top30_current_assets"; "investment_value_top30_current_assets"; ...
     "optimization_candidate_assets"; "optimization_candidate_ratio"; ...
     "nsga_population"; "nsga_generations"; "nsga_mutation_rate"; "ilp_time_limit"], ...
    [nAssets; sum(pof.("risk_top30_current")); sum(pof.("investment_value_top30_current")); ...
     candidateCount; candidateCount / nAssets; nsgaPopulation; nsgaGenerations; nsgaMutationRate; NaN], ...
    ["all assets in pof_5yr_output"; "top 30% by risk_2026_kkrw"; ...
     "top 30% by investment_value_2026_kkrw"; "candidate_top30_current = 1"; ...
     "candidate assets / total assets"; "custom NSGA-II population"; "custom NSGA-II generations"; ...
     "custom NSGA-II mutation probability"; "none"], ...
    'VariableNames', {'item', 'value', 'note'});
end

function T = buildConstraintsSummary(totalAssetValueKkrw, budgetRate, capacityRate, annualBudgetBaseKkrw, ...
    annualCapacity, budgets, capacities, years)
% 제약조건 요약.
items = ["total_asset_value_proxy_kkrw"; "budget_rate"; "capacity_rate"; ...
    "annual_budget_base_2026_kkrw"; "annual_capacity_assets"];
values = [totalAssetValueKkrw; budgetRate; capacityRate; annualBudgetBaseKkrw; annualCapacity];
notes = ["sum of replacement_cost_2026_kkrw"; "annual budget ratio"; ...
    "annual capacity ratio"; "base annual budget before discounting"; ...
    "round(total assets * 5%)"];
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

function T = buildAnnualSummary(methodNames, choices, pof, years, budgets, capacities)
% 방법별·연도별 투자 결과 요약.
rows = {};
baselineRisk = zeros(1, numel(years));
baselineSaidi = zeros(1, numel(years));
baselineFailures = zeros(1, numel(years));
for y = 1:numel(years)
    year = years(y);
    baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan");
    baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year)), "omitnan");
    baselineFailures(y) = sum(pof.(sprintf("pof_%d", year)), "omitnan");
end

for m = 1:numel(methodNames)
    choice = choices{m};
    for y = 1:numel(years)
        year = years(y);
        selected = find(choice == y);
        cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selected), "omitnan");
        risk = sum(pof.(sprintf("risk_%d_kkrw", year))(selected), "omitnan");
        riskReduction = sum(pof.(sprintf("risk_reduction_%d_kkrw", year))(selected), "omitnan");
        value = sum(pof.(sprintf("investment_value_%d_kkrw", year))(selected), "omitnan");
        saidi = sum(pof.(sprintf("saidi_%d_min", year))(selected), "omitnan");
        pofSum = sum(pof.(sprintf("pof_%d", year))(selected), "omitnan");
        rows(end + 1, :) = {methodNames(m), year, numel(selected), capacities(y), ...
            safeDivide(numel(selected), capacities(y)), cost, budgets(y), safeDivide(cost, budgets(y)), ...
            risk, riskReduction, value, safeDivide(riskReduction, cost), saidi, pofSum, ...
            baselineRisk(y), baselineSaidi(y), baselineFailures(y)}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'method', 'year', 'selected_count', ...
    'capacity_limit', 'capacity_used_pct', 'investment_cost_kkrw', ...
    'budget_limit_kkrw', 'budget_used_pct', 'risk_at_selection_kkrw', ...
    'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', 'saidi_at_selection_min', ...
    'expected_failures_at_selection', 'baseline_risk_kkrw', ...
    'baseline_saidi_min', 'baseline_expected_failures'});
end

function T = buildTotalSummary(methodNames, annualSummary)
% 방법별 합계 요약.
rows = {};
for m = 1:numel(methodNames)
    method = methodNames(m);
    sub = annualSummary(annualSummary.method == method, :);
    totalCount = sum(sub.selected_count);
    totalCost = sum(sub.investment_cost_kkrw, "omitnan");
    totalValue = sum(sub.investment_value_kkrw, "omitnan");
    totalRisk = sum(sub.risk_at_selection_kkrw, "omitnan");
    totalRiskReduction = sum(sub.risk_reduction_kkrw, "omitnan");
    totalSaidi = sum(sub.saidi_at_selection_min, "omitnan");
    totalFailures = sum(sub.expected_failures_at_selection, "omitnan");
    rows(end + 1, :) = {method, totalCount, totalCost, totalRiskReduction, totalValue, ...
        safeDivide(totalRiskReduction, totalCost), totalRisk, totalSaidi, totalFailures, mean(sub.budget_used_pct, "omitnan"), ...
        mean(sub.capacity_used_pct, "omitnan")}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'method', 'total_selected_count', ...
    'total_investment_cost_kkrw', 'total_risk_reduction_kkrw', ...
    'total_investment_value_kkrw', 'total_investment_efficiency', ...
    'total_risk_at_selection_kkrw', 'total_saidi_at_selection_min', ...
    'total_expected_failures_at_selection', 'avg_budget_used_pct', 'avg_capacity_used_pct'});
T = sortrows(T, 'total_investment_value_kkrw', 'descend');
end

function T = buildSelectedAssets(methodNames, choices, pof, years)
% 선택 자산 상세표.
rows = {};
for m = 1:numel(methodNames)
    choice = choices{m};
    for y = 1:numel(years)
        year = years(y);
        selected = find(choice == y);
        for ii = 1:numel(selected)
            idx = selected(ii);
            rows(end + 1, :) = {methodNames(m), string(pof.("asset_id")(idx)), ...
                string(pof.("asset_type")(idx)), pof.("risk_top30_current")(idx), ...
                pof.("investment_value_top30_current")(idx), pof.("candidate_top30_current")(idx), ...
                year, pof.(sprintf("replacement_cost_%d_kkrw", year))(idx), ...
                pof.(sprintf("risk_%d_kkrw", year))(idx), ...
                pof.(sprintf("risk_reduction_%d_kkrw", year))(idx), ...
                pof.(sprintf("investment_value_%d_kkrw", year))(idx), ...
                pof.(sprintf("bcr_%d", year))(idx), ...
                pof.(sprintf("saidi_%d_min", year))(idx), ...
                pof.(sprintf("pof_%d", year))(idx)}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    T = table();
else
    T = cell2table(rows, 'VariableNames', {'method', 'asset_id', 'asset_type', ...
        'risk_top30_current', 'investment_value_top30_current', 'candidate_top30_current', ...
        'replacement_year', 'replacement_cost_kkrw', 'risk_at_replacement_kkrw', ...
        'risk_reduction_kkrw', 'investment_value_kkrw', 'investment_efficiency', ...
        'saidi_at_replacement_min', 'pof_at_replacement'});
    T = sortrows(T, {'method', 'replacement_year', 'investment_value_kkrw'}, ...
        {'ascend', 'ascend', 'descend'});
    T.selection_rank = groupRank(T.method, T.replacement_year);
    T = movevars(T, 'selection_rank', 'Before', 1);
end
end

function ranks = groupRank(methods, years)
% method-year 그룹별 순위.
ranks = zeros(numel(methods), 1);
keys = methods + "_" + string(years);
uniqueKeys = unique(keys, "stable");
for i = 1:numel(uniqueKeys)
    idx = find(keys == uniqueKeys(i));
    ranks(idx) = (1:numel(idx))';
end
end

function T = buildAssetTypeSummary(selectedAssets)
% 설비군별 선택 결과.
if isempty(selectedAssets) || height(selectedAssets) == 0
    T = table();
    return;
end
[G, method, replacementYear, assetType] = findgroups(selectedAssets.method, ...
    selectedAssets.replacement_year, selectedAssets.asset_type);
selectedCount = splitapply(@numel, selectedAssets.asset_id, G);
cost = splitapply(@sum, selectedAssets.replacement_cost_kkrw, G);
value = splitapply(@sum, selectedAssets.investment_value_kkrw, G);
risk = splitapply(@sum, selectedAssets.risk_at_replacement_kkrw, G);
riskReduction = splitapply(@sum, selectedAssets.risk_reduction_kkrw, G);
efficiency = riskReduction ./ max(cost, 1);
T = table(method, replacementYear, assetType, selectedCount, cost, riskReduction, value, efficiency, risk, ...
    'VariableNames', {'method', 'replacement_year', 'asset_type', 'selected_count', ...
    'investment_cost_kkrw', 'risk_reduction_kkrw', 'investment_value_kkrw', ...
    'investment_efficiency', 'risk_at_selection_kkrw'});
end

function T = buildFeasibility(methodNames, choices, pof, years, budgets, capacities, candidateMask)
% 해의 제약조건 충족 여부.
rows = {};
for m = 1:numel(methodNames)
    choice = choices{m};
    selected = find(choice > 0);
    withinCandidate = all(candidateMask(selected));
    budgetOk = true;
    capacityOk = true;
    for y = 1:numel(years)
        year = years(y);
        selectedYear = find(choice == y);
        cost = sum(pof.(sprintf("replacement_cost_%d_kkrw", year))(selectedYear), "omitnan");
        budgetOk = budgetOk && cost <= budgets(y) + 1e-6;
        capacityOk = capacityOk && numel(selectedYear) <= capacities(y);
    end
    value = 0;
    for y = 1:numel(years)
        year = years(y);
        selectedYear = find(choice == y);
        value = value + sum(pof.(sprintf("investment_value_%d_kkrw", year))(selectedYear), "omitnan");
    end
    rows(end + 1, :) = {methodNames(m), budgetOk && capacityOk && withinCandidate, ...
        budgetOk, capacityOk, withinCandidate, numel(selected), value}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'method', 'is_feasible', 'budget_ok', ...
    'capacity_ok', 'candidate_pool_ok', 'selected_assets', 'objective_investment_value_kkrw'});
end

function T = buildSolverStatus(ilpStatus, nsgaObjective, nsgaPopulation, nsgaGenerations, nsgaMutationRate, candidateFlag)
% solver 상태 기록.
T = table( ...
    ["ILP_intlinprog"; "custom_NSGA_II"], ...
    [string(ilpStatus.exitflag); "completed"], ...
    [ilpStatus.objective_kkrw; nsgaObjective], ...
    ["none"; "generation_based"], ...
    ["none"; "not_applicable"], ...
    [candidateFlag; candidateFlag], ...
    [string(ilpStatus.message); "population=" + nsgaPopulation + ", generations=" + nsgaGenerations + ...
        ", mutation_rate=" + nsgaMutationRate + ...
        ", objectives=max net investment value, max risk reduction, min cost; SAIDI is report-only; representative=max net investment value in Pareto set"], ...
    'VariableNames', {'solver', 'status', 'objective_kkrw', 'time_limit', ...
    'gap_limit', 'candidate_pool', 'note'});
end

function out = safeDivide(a, b)
% 0 나누기 방지.
if b == 0
    out = 0;
else
    out = a / b;
end
end
