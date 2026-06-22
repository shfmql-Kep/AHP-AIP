%% NSGA 후보 포트폴리오 기반 통합설비 최적화
% 목적:
% 1) 기존 NSGA-II 실행에서 생성된 후보 포트폴리오 집합을 불러온다.
% 2) 각 후보 포트폴리오에 설비유형 가중치가 반영된 Integrated PI를 사후 적용한다.
% 3) 정책 KPI 제약(SAIDI, Risk 총량)을 만족하는 후보 중 Integrated PI가 최대인 포트폴리오를 선택한다.
%
% 주의:
% - 이 스크립트는 설비유형 가중치를 개별 자산 점수에 미리 곱해 NSGA를 다시 수행하지 않는다.
% - 기존 NSGA가 산출한 후보군을 유지한 상태에서 통합설비 관점의 의사결정 가중치를 적용한다.

clear; clc;

baseDir = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(baseDir, "data");
outputDir = fullfile(baseDir, "outputs");

years = 2026:2030;
nYears = numel(years);
discountRate = 0.05;
budgetRate = 0.04;
capacityRate = 0.05;
budgetFloorRate = 0.00;
saidiCapRate = 0.98;
riskCapRate = 1.15;
alphaTag = "alpha_0_5";

runStamp = char(string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
outputWorkbook = fullfile(outputDir, "integrated_portfolio_from_nsga_candidates_" + string(runStamp) + ".xlsx");

pofPath = fullfile(dataDir, "pof_5yr_output.xlsx");
localPiPath = fullfile(outputDir, "local_pi_matlab.xlsx");
integratedPiPath = fullfile(outputDir, "integrated_pi_matlab.xlsx");
nsgaWorkbook = resolveNsgaWorkbook(outputDir);
checkpointDir = resolveCheckpointDir(outputDir);

fprintf("통합설비 최적화 시작: NSGA 후보군 사후 재평가 방식\n");
fprintf("입력 NSGA 결과: %s\n", nsgaWorkbook);
fprintf("입력 체크포인트: %s\n", checkpointDir);

pof = readtable(pofPath, "Sheet", "pof_5yr", "VariableNamingRule", "preserve");
localPi = readtable(localPiPath, "Sheet", "local_pi_asset_wide", "VariableNamingRule", "preserve");
integratedPi = readtable(integratedPiPath, "Sheet", "integrated_pi_asset_wide", "VariableNamingRule", "preserve");
typeWeights = readtable(integratedPiPath, "Sheet", "type_weights", "VariableNamingRule", "preserve");

assetIds = string(pof.asset_id);
if height(localPi) ~= height(pof) || height(integratedPi) ~= height(pof)
    error("PoF, Local PI, Integrated PI 자산 수가 서로 다릅니다.");
end
if any(string(localPi.asset_id) ~= assetIds) || any(string(integratedPi.asset_id) ~= assetIds)
    error("PoF, Local PI, Integrated PI의 asset_id 순서가 일치하지 않습니다.");
end

candidateIdx = find(logical(pof.candidate_top30_current));
nCandidates = numel(candidateIdx);
fprintf("후보 자산 수(candidate_top30_current): %d\n", nCandidates);

popRecords = loadCandidatePopulations(checkpointDir);
population = popRecords.population;
sourceMethod = popRecords.source_method;

if size(population, 2) ~= nCandidates
    error("체크포인트 population 열 수(%d)가 후보 자산 수(%d)와 다릅니다.", size(population, 2), nCandidates);
end

[population, uniqueIdx] = unique(population, "rows", "stable");
sourceMethod = sourceMethod(uniqueIdx);
nPortfolios = size(population, 1);
fprintf("중복 제거 후 후보 포트폴리오 수: %d\n", nPortfolios);

mats = buildAssetMatrices(pof, localPi, integratedPi, candidateIdx, years, alphaTag);
constraints = buildConstraints(pof, years, discountRate, budgetRate, capacityRate, budgetFloorRate, saidiCapRate, riskCapRate);

portfolioMetrics = evaluatePortfolioSet(population, sourceMethod, mats, constraints, years);

feasibleMask = portfolioMetrics.violation <= 1e-9;
if any(feasibleMask)
    feasibleMetrics = portfolioMetrics(feasibleMask, :);
    [~, order] = sortrows([ ...
        -feasibleMetrics.integrated_pi_total, ...
        feasibleMetrics.investment_cost_total, ...
        -feasibleMetrics.investment_value_total ...
    ]);
    selectedPortfolioRow = feasibleMetrics.population_row(order(1));
    feasibilityNote = "feasible";
else
    warning("정책 KPI 제약을 모두 만족하는 후보 포트폴리오가 없습니다. 위반량이 가장 작은 후보를 선택합니다.");
    [~, order] = sortrows([portfolioMetrics.violation, -portfolioMetrics.integrated_pi_total]);
    selectedPortfolioRow = portfolioMetrics.population_row(order(1));
    feasibilityNote = "minimum_violation";
end

selectedChromosome = population(selectedPortfolioRow, :);
integratedAnnual = buildAnnualSummaryFromChromosome( ...
    "integrated_pi_candidate_rescore", ...
    "통합 PI 후보군 재평가", ...
    selectedChromosome, ...
    mats, ...
    constraints, ...
    years ...
);
integratedSelected = buildSelectedAssetsFromChromosome( ...
    "integrated_pi_candidate_rescore", ...
    "통합 PI 후보군 재평가", ...
    selectedChromosome, ...
    pof, ...
    localPi, ...
    integratedPi, ...
    candidateIdx, ...
    years, ...
    alphaTag ...
);

integratedSummary = portfolioMetrics(portfolioMetrics.population_row == selectedPortfolioRow, :);
integratedSummary.method = "integrated_pi_candidate_rescore";
integratedSummary.method_label = "통합 PI 후보군 재평가";
integratedSummary.selection_note = feasibilityNote;

existingSelected = readExistingRepresentativeSelectedAssets(nsgaWorkbook, pof, integratedPi, alphaTag);
existingAnnual = buildAnnualSummaryFromSelectedAssets(existingSelected, pof, constraints, years);

comparisonAnnualRaw = [existingAnnual; integratedAnnual];
comparisonTotalRaw = buildTotalComparison(comparisonAnnualRaw);
comparisonAnnualDisplay = buildAnnualDisplay(comparisonAnnualRaw);
comparisonTotalDisplay = buildTotalDisplay(comparisonTotalRaw, "investment_value_nsga_kpi");
constraintCheckDisplay = buildConstraintCheckDisplay(comparisonAnnualRaw);

writeTableSafe(portfolioMetrics, outputWorkbook, "candidate_population_summary");
writeTableSafe(integratedSummary, outputWorkbook, "integrated_representative_summary");
writeTableSafe(integratedAnnual, outputWorkbook, "integrated_annual_summary");
writeTableSafe(integratedSelected, outputWorkbook, "integrated_selected_assets");
writeTableSafe(comparisonAnnualRaw, outputWorkbook, "comparison_annual_raw");
writeTableSafe(comparisonAnnualDisplay, outputWorkbook, "comparison_annual_display");
writeTableSafe(comparisonTotalRaw, outputWorkbook, "comparison_total_raw");
writeTableSafe(comparisonTotalDisplay, outputWorkbook, "comparison_total_display");
writeTableSafe(constraintCheckDisplay, outputWorkbook, "constraint_check_display");
writeTableSafe(typeWeights, outputWorkbook, "type_weights");

fprintf("통합설비 최적화 완료: %s\n", outputWorkbook);
fprintf("선택 방식: %s\n", feasibilityNote);
fprintf("통합 PI 후보군 재평가 - 투자대수 %d, 투자비용 %.0f kKRW, Risk 저감량 %.0f kKRW, 투자가치 %.0f kKRW, SAIDI %.6f, Local PI %.6f, Integrated PI %.6f\n", ...
    integratedSummary.selected_count_total, ...
    integratedSummary.investment_cost_total, ...
    integratedSummary.risk_reduction_total, ...
    integratedSummary.investment_value_total, ...
    integratedSummary.saidi_reduction_total, ...
    integratedSummary.local_pi_total, ...
    integratedSummary.integrated_pi_total ...
);

%% 로컬 함수

function nsgaWorkbook = resolveNsgaWorkbook(outputDir)
    preferred = fullfile(outputDir, "nsga_portfolio_optimization_matlab_20260620_144251.xlsx");
    envPath = getenv("INTEGRATED_NSGA_WORKBOOK");
    if strlength(string(envPath)) > 0 && isfile(envPath)
        nsgaWorkbook = envPath;
    elseif isfile(preferred)
        nsgaWorkbook = preferred;
    else
        files = dir(fullfile(outputDir, "nsga_portfolio_optimization_matlab_*.xlsx"));
        if isempty(files)
            error("NSGA 결과 엑셀 파일을 찾을 수 없습니다.");
        end
        [~, idx] = max([files.datenum]);
        nsgaWorkbook = fullfile(files(idx).folder, files(idx).name);
    end
end

function checkpointDir = resolveCheckpointDir(outputDir)
    preferred = fullfile(outputDir, "nsga_checkpoints_20260620_144251");
    envPath = getenv("INTEGRATED_CHECKPOINT_DIR");
    if strlength(string(envPath)) > 0 && isfolder(envPath)
        checkpointDir = envPath;
    elseif isfolder(preferred)
        checkpointDir = preferred;
    else
        dirs = dir(fullfile(outputDir, "nsga_checkpoints_*"));
        dirs = dirs([dirs.isdir]);
        if isempty(dirs)
            error("NSGA 체크포인트 폴더를 찾을 수 없습니다.");
        end
        [~, idx] = max([dirs.datenum]);
        checkpointDir = fullfile(dirs(idx).folder, dirs(idx).name);
    end
end

function popRecords = loadCandidatePopulations(checkpointDir)
    files = [
        struct("name", fullfile(checkpointDir, "risk_cap_1150_investment_value_nsga_kpi.mat"), "method", "investment_value_nsga_kpi")
        struct("name", fullfile(checkpointDir, "risk_cap_1150_local_pi_ahp_nsga_kpi.mat"), "method", "local_pi_ahp_nsga_kpi")
    ];

    population = [];
    sourceMethod = strings(0, 1);
    for i = 1:numel(files)
        if ~isfile(files(i).name)
            error("필수 체크포인트 파일이 없습니다: %s", files(i).name);
        end
        loaded = load(files(i).name, "population");
        thisPopulation = loaded.population;
        population = [population; thisPopulation]; %#ok<AGROW>
        sourceMethod = [sourceMethod; repmat(string(files(i).method), size(thisPopulation, 1), 1)]; %#ok<AGROW>
        fprintf("체크포인트 로드: %s / 후보 포트폴리오 %d개\n", files(i).method, size(thisPopulation, 1));
    end

    popRecords = table();
    popRecords.population = population;
    popRecords.source_method = sourceMethod;
end

function mats = buildAssetMatrices(pof, localPi, integratedPi, candidateIdx, years, alphaTag)
    nCandidates = numel(candidateIdx);
    nYears = numel(years);

    mats.asset_id = string(pof.asset_id(candidateIdx));
    mats.asset_type = string(pof.asset_type(candidateIdx));
    mats.asset_type_label = string(integratedPi.asset_type_label(candidateIdx));
    mats.cost = zeros(nCandidates, nYears);
    mats.risk = zeros(nCandidates, nYears);
    mats.risk_reduction = zeros(nCandidates, nYears);
    mats.investment_value = zeros(nCandidates, nYears);
    mats.saidi = zeros(nCandidates, nYears);
    mats.pof = zeros(nCandidates, nYears);
    mats.local_pi = zeros(nCandidates, nYears);
    mats.integrated_pi = zeros(nCandidates, nYears);

    for y = 1:nYears
        year = years(y);
        mats.cost(:, y) = pof.(sprintf("replacement_cost_%d_kkrw", year))(candidateIdx);
        mats.risk(:, y) = pof.(sprintf("risk_%d_kkrw", year))(candidateIdx);
        mats.risk_reduction(:, y) = pof.(sprintf("risk_reduction_%d_kkrw", year))(candidateIdx);
        mats.investment_value(:, y) = pof.(sprintf("investment_value_%d_kkrw", year))(candidateIdx);
        mats.saidi(:, y) = pof.(sprintf("saidi_%d_min", year))(candidateIdx);
        mats.pof(:, y) = pof.(sprintf("pof_%d", year))(candidateIdx);
        mats.local_pi(:, y) = localPi.(sprintf("local_pi_ahp_%d", year))(candidateIdx);
        mats.integrated_pi(:, y) = integratedPi.(sprintf("integrated_pi_ahp_%s_%d", alphaTag, year))(candidateIdx);
    end
end

function constraints = buildConstraints(pof, years, discountRate, budgetRate, capacityRate, budgetFloorRate, saidiCapRate, riskCapRate)
    nAssets = height(pof);
    nYears = numel(years);

    firstCost = pof.(sprintf("replacement_cost_%d_kkrw", years(1)));
    totalAssetValue = sum(firstCost, "omitnan");
    annualBudgetBase = totalAssetValue * budgetRate;
    annualCapacityBase = ceil(nAssets * capacityRate);

    baselineRisk = zeros(1, nYears);
    baselineSaidi = zeros(1, nYears);
    budgetUpper = zeros(1, nYears);
    budgetLower = zeros(1, nYears);
    capacityUpper = zeros(1, nYears);

    for y = 1:nYears
        year = years(y);
        baselineRisk(y) = sum(pof.(sprintf("risk_%d_kkrw", year)), "omitnan");
        baselineSaidi(y) = sum(pof.(sprintf("saidi_%d_min", year)), "omitnan");
        discountFactor = (1 + discountRate) ^ (y - 1);
        budgetUpper(y) = annualBudgetBase / discountFactor;
        budgetLower(y) = annualBudgetBase * budgetFloorRate / discountFactor;
        capacityUpper(y) = annualCapacityBase;
    end

    constraints = struct();
    constraints.totalAssetValue = totalAssetValue;
    constraints.budgetUpper = budgetUpper;
    constraints.budgetLower = budgetLower;
    constraints.capacityUpper = capacityUpper;
    constraints.baselineRisk = baselineRisk;
    constraints.baselineSaidi = baselineSaidi;
    constraints.riskCap = baselineRisk(1) * riskCapRate;
    constraints.saidiCap = baselineSaidi(1) * saidiCapRate;
end

function portfolioMetrics = evaluatePortfolioSet(population, sourceMethod, mats, constraints, years)
    nPortfolios = size(population, 1);
    populationRow = (1:nPortfolios)';
    selectedCount = zeros(nPortfolios, 1);
    investmentCost = zeros(nPortfolios, 1);
    riskReduction = zeros(nPortfolios, 1);
    investmentValue = zeros(nPortfolios, 1);
    saidiReduction = zeros(nPortfolios, 1);
    pofReduction = zeros(nPortfolios, 1);
    localPi = zeros(nPortfolios, 1);
    integratedPi = zeros(nPortfolios, 1);
    efficiency = zeros(nPortfolios, 1);
    violation = zeros(nPortfolios, 1);
    maxSaidiAfter = zeros(nPortfolios, 1);
    maxRiskAfter = zeros(nPortfolios, 1);

    for i = 1:nPortfolios
        chromosome = population(i, :);
        totals = evaluateChromosome(chromosome, mats, constraints, years);
        selectedCount(i) = totals.selected_count_total;
        investmentCost(i) = totals.investment_cost_total;
        riskReduction(i) = totals.risk_reduction_total;
        investmentValue(i) = totals.investment_value_total;
        saidiReduction(i) = totals.saidi_reduction_total;
        pofReduction(i) = totals.pof_reduction_total;
        localPi(i) = totals.local_pi_total;
        integratedPi(i) = totals.integrated_pi_total;
        efficiency(i) = totals.investment_efficiency;
        violation(i) = totals.violation;
        maxSaidiAfter(i) = totals.max_saidi_after;
        maxRiskAfter(i) = totals.max_risk_after;
    end

    portfolioMetrics = table( ...
        populationRow, sourceMethod, selectedCount, investmentCost, riskReduction, investmentValue, ...
        saidiReduction, pofReduction, localPi, integratedPi, efficiency, violation, maxSaidiAfter, maxRiskAfter, ...
        'VariableNames', cellstr([ ...
            "population_row", "source_method", "selected_count_total", "investment_cost_total", ...
            "risk_reduction_total", "investment_value_total", "saidi_reduction_total", "pof_reduction_total", ...
            "local_pi_total", "integrated_pi_total", "investment_efficiency", "violation", ...
            "max_saidi_after", "max_risk_after" ...
        ]) ...
    );
end

function totals = evaluateChromosome(chromosome, mats, constraints, years)
    nYears = numel(years);
    violation = 0;
    selectedCountTotal = 0;
    investmentCostTotal = 0;
    riskReductionTotal = 0;
    investmentValueTotal = 0;
    saidiReductionTotal = 0;
    pofReductionTotal = 0;
    localPiTotal = 0;
    integratedPiTotal = 0;
    saidiAfter = zeros(1, nYears);
    riskAfter = zeros(1, nYears);

    for y = 1:nYears
        idxYear = chromosome == y;
        yearCount = sum(idxYear);
        yearCost = sum(mats.cost(idxYear, y), "omitnan");

        selectedCountTotal = selectedCountTotal + yearCount;
        investmentCostTotal = investmentCostTotal + yearCost;
        riskReductionTotal = riskReductionTotal + sum(mats.risk_reduction(idxYear, y), "omitnan");
        investmentValueTotal = investmentValueTotal + sum(mats.investment_value(idxYear, y), "omitnan");
        saidiReductionTotal = saidiReductionTotal + sum(mats.saidi(idxYear, y), "omitnan");
        pofReductionTotal = pofReductionTotal + sum(mats.pof(idxYear, y), "omitnan");
        localPiTotal = localPiTotal + sum(mats.local_pi(idxYear, y), "omitnan");
        integratedPiTotal = integratedPiTotal + sum(mats.integrated_pi(idxYear, y), "omitnan");

        violation = violation + max(0, yearCost - constraints.budgetUpper(y)) / max(1, constraints.budgetUpper(y));
        violation = violation + max(0, constraints.budgetLower(y) - yearCost) / max(1, constraints.budgetUpper(y));
        violation = violation + max(0, yearCount - constraints.capacityUpper(y)) / max(1, constraints.capacityUpper(y));

        cumulativeSelected = chromosome > 0 & chromosome <= y;
        saidiRemoved = sum(mats.saidi(cumulativeSelected, y), "omitnan");
        riskRemoved = sum(mats.risk(cumulativeSelected, y), "omitnan");
        saidiAfter(y) = constraints.baselineSaidi(y) - saidiRemoved;
        riskAfter(y) = constraints.baselineRisk(y) - riskRemoved;

        violation = violation + max(0, saidiAfter(y) - constraints.saidiCap) / max(1e-12, constraints.saidiCap);
        violation = violation + max(0, riskAfter(y) - constraints.riskCap) / max(1, constraints.riskCap);
    end

    totals = struct();
    totals.selected_count_total = selectedCountTotal;
    totals.investment_cost_total = investmentCostTotal;
    totals.risk_reduction_total = riskReductionTotal;
    totals.investment_value_total = investmentValueTotal;
    totals.saidi_reduction_total = saidiReductionTotal;
    totals.pof_reduction_total = pofReductionTotal;
    totals.local_pi_total = localPiTotal;
    totals.integrated_pi_total = integratedPiTotal;
    totals.investment_efficiency = riskReductionTotal / max(1, investmentCostTotal);
    totals.violation = violation;
    totals.max_saidi_after = max(saidiAfter);
    totals.max_risk_after = max(riskAfter);
end

function annualSummary = buildAnnualSummaryFromChromosome(method, methodLabel, chromosome, mats, constraints, years)
    nYears = numel(years);
    rows = cell(nYears, 17);

    for y = 1:nYears
        idxYear = chromosome == y;
        cumulativeSelected = chromosome > 0 & chromosome <= y;

        yearCost = sum(mats.cost(idxYear, y), "omitnan");
        yearRiskReduction = sum(mats.risk_reduction(idxYear, y), "omitnan");
        yearInvestmentValue = sum(mats.investment_value(idxYear, y), "omitnan");
        yearSaidi = sum(mats.saidi(idxYear, y), "omitnan");
        yearPof = sum(mats.pof(idxYear, y), "omitnan");
        yearLocalPi = sum(mats.local_pi(idxYear, y), "omitnan");
        yearIntegratedPi = sum(mats.integrated_pi(idxYear, y), "omitnan");
        saidiAfter = constraints.baselineSaidi(y) - sum(mats.saidi(cumulativeSelected, y), "omitnan");
        riskAfter = constraints.baselineRisk(y) - sum(mats.risk(cumulativeSelected, y), "omitnan");

        rows(y, :) = { ...
            string(method), string(methodLabel), years(y), string(years(y)), sum(idxYear), yearCost, ...
            yearRiskReduction, yearInvestmentValue, yearSaidi, yearPof, yearLocalPi, yearIntegratedPi, ...
            yearRiskReduction / max(1, yearCost), saidiAfter, riskAfter, constraints.saidiCap, constraints.riskCap ...
        };
    end

    annualSummary = cell2table(rows, 'VariableNames', cellstr([ ...
        "method", "method_label", "year", "year_label", "selected_count", "investment_cost_kkrw", ...
        "risk_reduction_kkrw", "investment_value_kkrw", "saidi_reduction_min", "pof_sum", ...
        "local_pi_ahp", "integrated_pi_ahp_alpha05", "investment_efficiency", ...
        "saidi_after_min", "risk_after_kkrw", "saidi_cap_min", "risk_cap_kkrw" ...
    ]));
end

function selectedAssets = buildSelectedAssetsFromChromosome(method, methodLabel, chromosome, pof, localPi, integratedPi, candidateIdx, years, alphaTag)
    selectedRows = find(chromosome > 0);
    nRows = numel(selectedRows);
    rows = cell(nRows, 15);

    for r = 1:nRows
        candidateRow = selectedRows(r);
        assetRow = candidateIdx(candidateRow);
        yearIdx = chromosome(candidateRow);
        year = years(yearIdx);

        rows(r, :) = { ...
            string(method), string(methodLabel), string(pof.asset_id(assetRow)), string(pof.asset_type(assetRow)), ...
            string(integratedPi.asset_type_label(assetRow)), year, ...
            pof.(sprintf("replacement_cost_%d_kkrw", year))(assetRow), ...
            pof.(sprintf("risk_reduction_%d_kkrw", year))(assetRow), ...
            pof.(sprintf("investment_value_%d_kkrw", year))(assetRow), ...
            pof.(sprintf("saidi_%d_min", year))(assetRow), ...
            pof.(sprintf("pof_%d", year))(assetRow), ...
            localPi.(sprintf("local_pi_ahp_%d", year))(assetRow), ...
            integratedPi.(sprintf("integrated_pi_ahp_%s_%d", alphaTag, year))(assetRow), ...
            integratedPi.w_type_alpha_0_5(assetRow), ...
            integratedPi.w_type_expert(assetRow) ...
        };
    end

    selectedAssets = cell2table(rows, 'VariableNames', cellstr([ ...
        "method", "method_label", "asset_id", "asset_type", "asset_type_label", "replacement_year", ...
        "replacement_cost_kkrw", "risk_reduction_kkrw", "investment_value_kkrw", "saidi_min", "pof", ...
        "local_pi_ahp", "integrated_pi_ahp_alpha05", "integrated_type_weight_alpha05", "expert_type_weight" ...
    ]));
end

function selectedAssets = readExistingRepresentativeSelectedAssets(nsgaWorkbook, pof, integratedPi, alphaTag)
    raw = readtable(nsgaWorkbook, "Sheet", "selected_assets", "VariableNamingRule", "preserve");
    if ~ismember("representative_type", string(raw.Properties.VariableNames))
        error("selected_assets 시트에 representative_type 열이 없습니다.");
    end

    mask = contains(string(raw.representative_type), "max_primary");
    raw = raw(mask, :);
    if isempty(raw)
        error("기존 NSGA 결과에서 max_primary 대표해를 찾을 수 없습니다.");
    end

    raw.method = string(raw.method);
    raw.method_label = mapMethodLabel(raw.method);
    raw.asset_id = string(raw.asset_id);
    raw.asset_type = string(raw.asset_type);
    assetIds = string(pof.asset_id);
    integratedValues = zeros(height(raw), 1);
    integratedWeights = zeros(height(raw), 1);
    expertWeights = zeros(height(raw), 1);
    assetTypeLabels = strings(height(raw), 1);
    for r = 1:height(raw)
        assetRow = find(assetIds == string(raw.asset_id(r)), 1);
        year = raw.replacement_year(r);
        if isempty(assetRow)
            error("기존 대표해의 asset_id를 PoF 출력에서 찾을 수 없습니다: %s", string(raw.asset_id(r)));
        end
        integratedValues(r) = integratedPi.(sprintf("integrated_pi_ahp_%s_%d", alphaTag, year))(assetRow);
        integratedWeights(r) = integratedPi.w_type_alpha_0_5(assetRow);
        expertWeights(r) = integratedPi.w_type_expert(assetRow);
        assetTypeLabels(r) = string(integratedPi.asset_type_label(assetRow));
    end

    selectedAssets = table( ...
        raw.method, raw.method_label, raw.asset_id, raw.asset_type, assetTypeLabels, raw.replacement_year, ...
        raw.replacement_cost_kkrw, raw.risk_reduction_kkrw, raw.investment_value_kkrw, ...
        raw.saidi_at_replacement_min, raw.pof_at_replacement, raw.local_pi_ahp, integratedValues, integratedWeights, expertWeights, ...
        'VariableNames', cellstr([ ...
            "method", "method_label", "asset_id", "asset_type", "asset_type_label", "replacement_year", ...
            "replacement_cost_kkrw", "risk_reduction_kkrw", "investment_value_kkrw", "saidi_min", "pof", ...
            "local_pi_ahp", "integrated_pi_ahp_alpha05", "integrated_type_weight_alpha05", "expert_type_weight" ...
        ]) ...
    );
end

function labels = mapMethodLabel(methods)
    labels = strings(numel(methods), 1);
    for i = 1:numel(methods)
        switch string(methods(i))
            case "investment_value_nsga_kpi"
                labels(i) = "투자가치 NSGA";
            case "local_pi_ahp_nsga_kpi"
                labels(i) = "Local PI NSGA";
            otherwise
                labels(i) = string(methods(i));
        end
    end
end

function annualSummary = buildAnnualSummaryFromSelectedAssets(selectedAssets, pof, constraints, years)
    methods = unique(selectedAssets.method, "stable");
    rows = {};
    assetIds = string(pof.asset_id);

    for m = 1:numel(methods)
        method = methods(m);
        methodMask = selectedAssets.method == method;
        methodLabel = selectedAssets.method_label(find(methodMask, 1));

        for y = 1:numel(years)
            year = years(y);
            idxYear = methodMask & selectedAssets.replacement_year == year;
            idxCumulative = methodMask & selectedAssets.replacement_year <= year;

            cumulativeAssetIds = string(selectedAssets.asset_id(idxCumulative));
            cumulativeRows = find(ismember(assetIds, cumulativeAssetIds));
            saidiRemoved = sum(pof.(sprintf("saidi_%d_min", year))(cumulativeRows), "omitnan");
            riskRemoved = sum(pof.(sprintf("risk_%d_kkrw", year))(cumulativeRows), "omitnan");
            saidiAfter = constraints.baselineSaidi(y) - saidiRemoved;
            riskAfter = constraints.baselineRisk(y) - riskRemoved;

            yearRiskReduction = sum(selectedAssets.risk_reduction_kkrw(idxYear), "omitnan");
            yearCost = sum(selectedAssets.replacement_cost_kkrw(idxYear), "omitnan");

            rows(end + 1, :) = { ...
                method, methodLabel, year, string(year), sum(idxYear), yearCost, ...
                yearRiskReduction, ...
                sum(selectedAssets.investment_value_kkrw(idxYear), "omitnan"), ...
                sum(selectedAssets.saidi_min(idxYear), "omitnan"), ...
                sum(selectedAssets.pof(idxYear), "omitnan"), ...
                sum(selectedAssets.local_pi_ahp(idxYear), "omitnan"), ...
                sum(selectedAssets.integrated_pi_ahp_alpha05(idxYear), "omitnan"), ...
                yearRiskReduction / max(1, yearCost), ...
                saidiAfter, riskAfter, constraints.saidiCap, constraints.riskCap ...
            }; %#ok<AGROW>
        end
    end

    annualSummary = cell2table(rows, 'VariableNames', cellstr([ ...
        "method", "method_label", "year", "year_label", "selected_count", "investment_cost_kkrw", ...
        "risk_reduction_kkrw", "investment_value_kkrw", "saidi_reduction_min", "pof_sum", ...
        "local_pi_ahp", "integrated_pi_ahp_alpha05", "investment_efficiency", ...
        "saidi_after_min", "risk_after_kkrw", "saidi_cap_min", "risk_cap_kkrw" ...
    ]));
end

function totalComparison = buildTotalComparison(annualRaw)
    methods = unique(annualRaw.method, "stable");
    rows = cell(numel(methods), 14);
    for m = 1:numel(methods)
        method = methods(m);
        mask = annualRaw.method == method;
        methodLabel = annualRaw.method_label(find(mask, 1));
        riskReduction = sum(annualRaw.risk_reduction_kkrw(mask), "omitnan");
        cost = sum(annualRaw.investment_cost_kkrw(mask), "omitnan");
        rows(m, :) = { ...
            method, methodLabel, sum(annualRaw.selected_count(mask), "omitnan"), cost, ...
            riskReduction, sum(annualRaw.investment_value_kkrw(mask), "omitnan"), ...
            sum(annualRaw.saidi_reduction_min(mask), "omitnan"), ...
            sum(annualRaw.pof_sum(mask), "omitnan"), ...
            sum(annualRaw.local_pi_ahp(mask), "omitnan"), ...
            sum(annualRaw.integrated_pi_ahp_alpha05(mask), "omitnan"), ...
            riskReduction / max(1, cost), ...
            annualRaw.saidi_after_min(find(mask, 1, "last")), ...
            annualRaw.risk_after_kkrw(find(mask, 1, "last")), ...
            "합산" ...
        };
    end

    totalComparison = cell2table(rows, 'VariableNames', cellstr([ ...
        "method", "method_label", "selected_count", "investment_cost_kkrw", "risk_reduction_kkrw", ...
        "investment_value_kkrw", "saidi_reduction_min", "pof_sum", "local_pi_ahp", ...
        "integrated_pi_ahp_alpha05", "investment_efficiency", "saidi_after_2030_min", ...
        "risk_after_2030_kkrw", "period_label" ...
    ]));
end

function displayTable = buildAnnualDisplay(annualRaw)
    displayTable = annualRaw;
    displayTable.method_label = string(displayTable.method_label);
    displayTable.year_label = string(displayTable.year_label);
end

function displayTable = buildTotalDisplay(totalRaw, baselineMethod)
    metrics = [
        "selected_count"
        "investment_cost_kkrw"
        "risk_reduction_kkrw"
        "investment_value_kkrw"
        "saidi_reduction_min"
        "local_pi_ahp"
        "integrated_pi_ahp_alpha05"
        "investment_efficiency"
    ];
    labels = [
        "투자대수"
        "투자비용"
        "Risk 저감량"
        "투자가치"
        "SAIDI"
        "Local PI"
        "Integrated PI"
        "투자효율"
    ];

    methods = string(totalRaw.method);
    baselineIdx = find(methods == string(baselineMethod), 1);
    if isempty(baselineIdx)
        baselineIdx = 1;
    end

    rows = cell(numel(metrics), 1 + height(totalRaw));
    varNames = ["metric"; matlab.lang.makeValidName(string(totalRaw.method_label))];
    for i = 1:numel(metrics)
        metric = metrics(i);
        baselineValue = totalRaw.(metric)(baselineIdx);
        rows{i, 1} = labels(i);
        for m = 1:height(totalRaw)
            value = totalRaw.(metric)(m);
            if m == baselineIdx || baselineValue == 0
                rows{i, m + 1} = sprintf("%.6g", value);
            else
                changeRate = (value - baselineValue) / abs(baselineValue) * 100;
                rows{i, m + 1} = sprintf("%.6g (%+.2f%%)", value, changeRate);
            end
        end
    end

    displayTable = cell2table(rows, 'VariableNames', cellstr(varNames));
end

function displayTable = buildConstraintCheckDisplay(annualRaw)
    displayTable = annualRaw(:, cellstr([ ...
        "method", "method_label", "year", "saidi_after_min", "saidi_cap_min", ...
        "risk_after_kkrw", "risk_cap_kkrw" ...
    ]));
    displayTable.saidi_ok = displayTable.saidi_after_min <= displayTable.saidi_cap_min + 1e-9;
    displayTable.risk_ok = displayTable.risk_after_kkrw <= displayTable.risk_cap_kkrw + 1e-6;
end

function writeTableSafe(tbl, outputWorkbook, sheetName)
    safeSheetName = char(string(sheetName));
    safeSheetName = regexprep(safeSheetName, '[:\\/\?\*\[\]]', '_');
    if strlength(string(safeSheetName)) > 31
        safeSheetName = extractBefore(string(safeSheetName), 32);
        safeSheetName = char(safeSheetName);
    end
    writetable(tbl, outputWorkbook, "Sheet", safeSheetName, "UseExcel", false);
end
