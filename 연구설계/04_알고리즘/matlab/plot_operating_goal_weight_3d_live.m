%% 운영목표 가중치 민감도 3D 산점도 작성
% 목적:
%   경제성, 신뢰도, 안전·환경 가중치 조합에 따라 투자가치와 SAIDI가
%   어떻게 변화하는지 3D 산점도로 표현한다.
%
% 실행:
%   run("연구설계/04_알고리즘/matlab/plot_operating_goal_weight_3d_live.m")
%
% 출력:
%   연구설계/07_그림자료/generated/chapter4/
%     fig4_10_operating_goal_weight_sensitivity_bubble.png
%     fig4_10_operating_goal_weight_sensitivity_bubble.fig

clear; clc;

%% 1. 사용자 설정
% 대표 방법론: 통합 PI 포트폴리오 범위의 통합형 ILP
targetScope = "integrated_pi_portfolio";
targetMethod = "integrated_pi_ilp";

% SAIDI 표현 방식:
%   "removed" : SAIDI 저감량
%   "after"   : 투자 후 SAIDI
saidiMetric = "removed";

% 그림 표시 설정
fontName = "Batang";
minBubbleSize = 55;
maxBubbleSize = 220;
baselineMarkerSize = 260;
viewAngle = [42 24];
outputBaseName = "fig4_10_operating_goal_weight_sensitivity_bubble";

%% 2. 경로 및 파일 탐색
scriptDir = fileparts(mfilename("fullpath"));
if strlength(scriptDir) == 0
    scriptDir = pwd;
end
researchDir = detectResearchDir(scriptDir);

sensitivityRoot = fullfile(researchDir, "06_시뮬레이션결과", "민감도_강건성");
resultFile = findLatestSensitivityResult(sensitivityRoot);

figureDir = fullfile(researchDir, "07_그림자료", "generated", "chapter4");
if ~isfolder(figureDir)
    mkdir(figureDir);
end

fprintf("민감도 결과 파일: %s\n", resultFile);
fprintf("대상 범위/방법론: %s / %s\n", targetScope, targetMethod);

%% 3. 데이터 로드 및 필터링
totalSummary = readtable(resultFile, "Sheet", "04_total_summary", "VariableNamingRule", "preserve");
annualSummary = readtable(resultFile, "Sheet", "03_annual_summary", "VariableNamingRule", "preserve");

totalSummary.scenario_group = string(totalSummary.scenario_group);
totalSummary.simulation_scope = string(totalSummary.simulation_scope);
totalSummary.method = string(totalSummary.method);
annualSummary.scenario_group = string(annualSummary.scenario_group);
annualSummary.simulation_scope = string(annualSummary.simulation_scope);
annualSummary.method = string(annualSummary.method);

idxTotal = totalSummary.scenario_group == "operating_goal_weight_sweep" & ...
    totalSummary.simulation_scope == targetScope & ...
    totalSummary.method == targetMethod;

plotData = totalSummary(idxTotal, :);
if isempty(plotData)
    error("운영목표 가중치 시나리오 데이터를 찾지 못했습니다.");
end

lastYear = max(annualSummary.year);
idxAnnual = annualSummary.scenario_group == "operating_goal_weight_sweep" & ...
    annualSummary.simulation_scope == targetScope & ...
    annualSummary.method == targetMethod & ...
    annualSummary.year == lastYear;
saidiData = annualSummary(idxAnnual, :);

% scenario_id 기준으로 SAIDI 데이터를 결합한다.
if saidiMetric == "removed"
    saidiCol = "saidi_removed_cumulative_min";
    saidiLabel = "SAIDI 저감량 [분/고객·년]";
    saidiTitle = "Scenarios - SAIDI Improvement";
else
    saidiCol = "saidi_after_cumulative_min";
    saidiLabel = "투자 후 SAIDI [분/고객·년]";
    saidiTitle = "Scenarios - Post-Investment SAIDI";
end

saidiJoin = saidiData(:, ["scenario_id", saidiCol]);
plotData = outerjoin(plotData, saidiJoin, ...
    "Keys", "scenario_id", ...
    "MergeKeys", true, ...
    "Type", "left");

validIdx = isfinite(plotData.w_economy) & ...
    isfinite(plotData.w_reliability) & ...
    isfinite(plotData.w_safety_environment) & ...
    isfinite(plotData.investment_value_kkrw) & ...
    isfinite(plotData.(saidiCol));
plotData = plotData(validIdx, :);

if isempty(plotData)
    error("그림 작성에 사용할 유효 데이터가 없습니다.");
end

%% 4. 축 및 색상값 구성
xEconomy = plotData.w_economy;
yReliability = plotData.w_reliability;
zSafetyEnv = plotData.w_safety_environment;

% 투자가치는 억 원 단위로 표시한다.
investmentValueEok = plotData.investment_value_kkrw ./ 100000;
saidiValue = plotData.(saidiCol);

baselineIdx = false(height(plotData), 1);
if ismember("weight_scenario_id", string(plotData.Properties.VariableNames))
    baselineIdx = string(plotData.weight_scenario_id) == "expert_mean";
end
if ~any(baselineIdx)
    % 기준 시나리오가 명시적으로 없을 경우 전문가 평균 가중치에 가장 가까운 점을 사용한다.
    expertWeight = [0.3541253119705049, 0.26165035247332163, 0.3842243355561736];
    dist = (xEconomy - expertWeight(1)).^2 + ...
        (yReliability - expertWeight(2)).^2 + ...
        (zSafetyEnv - expertWeight(3)).^2;
    [~, nearestIdx] = min(dist);
    baselineIdx(nearestIdx) = true;
end

%% 5. 그림 작성
fig = figure("Color", "w", "Position", [100 100 1700 720]);
tiledlayout(fig, 1, 2, "Padding", "compact", "TileSpacing", "compact");

ax1 = nexttile;
drawWeightScatter(ax1, xEconomy, yReliability, zSafetyEnv, investmentValueEok, ...
    baselineIdx, "(a) 투자가치", "투자가치 [억 원]", ...
    minBubbleSize, maxBubbleSize, baselineMarkerSize, viewAngle, fontName);

ax2 = nexttile;
drawWeightScatter(ax2, xEconomy, yReliability, zSafetyEnv, saidiValue, ...
    baselineIdx, "(b) SAIDI 저감", saidiLabel, ...
    minBubbleSize, maxBubbleSize, baselineMarkerSize, viewAngle, fontName);

sgtitle("운영목표 가중치 민감도 분석", ...
    "FontName", fontName, "FontSize", 20, "FontWeight", "bold");

%% 6. 저장
pngPath = fullfile(figureDir, outputBaseName + ".png");
figPath = fullfile(figureDir, outputBaseName + ".fig");

exportgraphics(fig, pngPath, "Resolution", 300);
savefig(fig, figPath);

fprintf("저장 완료: %s\n", pngPath);
fprintf("저장 완료: %s\n", figPath);

%% 로컬 함수
function drawWeightScatter(ax, x, y, z, c, baselineIdx, plotTitle, colorbarLabel, ...
    minBubbleSize, maxBubbleSize, baselineMarkerSize, viewAngle, fontName)

bubbleSize = scaleBubbleSize(c, minBubbleSize, maxBubbleSize);

% 작은 점을 먼저 그리고 큰 점이 위로 오도록 값 기준으로 정렬한다.
[~, order] = sort(c, "ascend");
xPlot = x(order);
yPlot = y(order);
zPlot = z(order);
cPlot = c(order);
sizePlot = bubbleSize(order);

scatter3(ax, xPlot, yPlot, zPlot, sizePlot, cPlot, "filled", ...
    "MarkerEdgeColor", [1 1 1], ...
    "LineWidth", 0.7, ...
    "MarkerFaceAlpha", 0.92);
hold(ax, "on");

% 기준 시나리오는 기존 그림과 동일하게 붉은 별표로 표시한다.
hBaseline = gobjects(0);
if any(baselineIdx)
    hBaseline = scatter3(ax, x(baselineIdx), y(baselineIdx), z(baselineIdx), ...
        baselineMarkerSize, [0.90 0.00 0.18], "p", ...
        "MarkerFaceColor", [0.90 0.00 0.18], ...
        "MarkerEdgeColor", [0.45 0.00 0.08], ...
        "LineWidth", 1.2, ...
        "DisplayName", "기준 시나리오");
end

grid(ax, "on");
box(ax, "on");
view(ax, viewAngle);
colormap(ax, "turbo");

xlim(ax, [0 1]);
ylim(ax, [0 1]);
zlim(ax, [0 1]);
xticks(ax, 0:0.2:1);
yticks(ax, 0:0.2:1);
zticks(ax, 0:0.2:1);

xlabel(ax, "경제성 가중치", "FontName", fontName, "FontSize", 15, "FontWeight", "bold");
ylabel(ax, "신뢰도 가중치", "FontName", fontName, "FontSize", 15, "FontWeight", "bold");
zlabel(ax, "안전·환경 가중치", "FontName", fontName, "FontSize", 15, "FontWeight", "bold");
title(ax, plotTitle, "FontName", fontName, "FontSize", 17, "FontWeight", "bold");

cb = colorbar(ax);
cb.Label.String = colorbarLabel;
cb.Label.FontName = fontName;
cb.Label.FontSize = 13;
cb.Label.FontWeight = "bold";

set(ax, "FontName", fontName, "FontSize", 12, ...
    "LineWidth", 1.0, ...
    "GridAlpha", 0.26, ...
    "Projection", "perspective");

if any(baselineIdx)
    legend(ax, hBaseline, "기준 시나리오", ...
        "Location", "northwest", ...
        "FontName", fontName, ...
        "FontSize", 12, ...
        "Box", "on");
end

text(ax, 0.03, 0.96, 0.08, "점 크기 = 성과값", ...
    "FontName", fontName, ...
    "FontSize", 11, ...
    "Color", [0.25 0.25 0.25], ...
    "BackgroundColor", [1 1 1], ...
    "EdgeColor", [0.75 0.75 0.75], ...
    "Margin", 3);
hold(ax, "off");
end

function bubbleSize = scaleBubbleSize(values, minBubbleSize, maxBubbleSize)
vMin = min(values, [], "omitnan");
vMax = max(values, [], "omitnan");
if ~isfinite(vMin) || ~isfinite(vMax) || abs(vMax - vMin) < eps
    bubbleSize = repmat((minBubbleSize + maxBubbleSize) / 2, size(values));
else
    normalized = (values - vMin) ./ (vMax - vMin);
    bubbleSize = minBubbleSize + normalized .* (maxBubbleSize - minBubbleSize);
end
end

function researchDir = detectResearchDir(startDir)
currentDir = string(startDir);
while strlength(currentDir) > 0
    candidate = fullfile(currentDir, "연구설계");
    if isfolder(candidate)
        researchDir = candidate;
        return;
    end
    parentDir = string(fileparts(currentDir));
    if parentDir == currentDir
        break;
    end
    currentDir = parentDir;
end
error("연구설계 폴더를 찾지 못했습니다. 현재 경로: %s", startDir);
end

function resultFile = findLatestSensitivityResult(sensitivityRoot)
if ~isfolder(sensitivityRoot)
    error("민감도 분석 결과 폴더를 찾지 못했습니다: %s", sensitivityRoot);
end

files = dir(fullfile(sensitivityRoot, "**", "sensitivity_analysis_results_final.xlsx"));
if isempty(files)
    files = dir(fullfile(sensitivityRoot, "**", "sensitivity_analysis_results.xlsx"));
end
if isempty(files)
    error("민감도 분석 결과 xlsx 파일을 찾지 못했습니다: %s", sensitivityRoot);
end

[~, idx] = max([files.datenum]);
resultFile = fullfile(files(idx).folder, files(idx).name);
end
