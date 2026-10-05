%% 운영목표 가중치 민감도 3D Scatter 그래프
% x=경제성, y=신뢰도, z=안전·환경 가중치 / 색상=투자가치 or SAIDI
% 출력: fig4_10_operating_goal_weight_sensitivity.png

clear; clc;

%% ── 경로 설정 ─────────────────────────────────────────────────────────
BASE    = 'C:\Users\shfmq\codexwork\AHP_AIP';
XLSX    = fullfile(BASE, '연구설계', '06_시뮬레이션결과', '민감도_강건성', ...
          'sensitivity_analysis_fast_20260624_100129', ...
          'sensitivity_analysis_results_final.xlsx');
OUT_DIR = fullfile(BASE, '연구설계', '07_그림자료', 'generated', 'chapter4');
if ~exist(OUT_DIR, 'dir'), mkdir(OUT_DIR); end

%% ── 데이터 로드 ───────────────────────────────────────────────────────
T4 = readtable(XLSX, 'Sheet', '04_total_summary');
T3 = readtable(XLSX, 'Sheet', '03_annual_summary');

METHOD = 'integrated_pi_ilp';
SCOPE  = 'integrated_pi_portfolio';
GROUP  = 'operating_goal_weight_sweep';

%% ── 투자가치 데이터 ───────────────────────────────────────────────────
mask4 = strcmp(T4.scenario_group, GROUP) & ...
        strcmp(T4.method,         METHOD) & ...
        strcmp(T4.simulation_scope, SCOPE);
D4 = T4(mask4, {'w_economy','w_reliability','w_safety_environment','investment_value_kkrw'});
D4 = D4(~any(ismissing(D4), 2), :);
D4.iv_billion = D4.investment_value_kkrw / 100000;   % 억원

%% ── SAIDI 저감 데이터 (최종 연도 누적값) ─────────────────────────────
mask3 = strcmp(T3.scenario_group, GROUP) & ...
        strcmp(T3.method,         METHOD) & ...
        strcmp(T3.simulation_scope, SCOPE);
D3 = T3(mask3, {'w_economy','w_reliability','w_safety_environment','year','saidi_removed_cumulative_min'});
D3 = D3(~any(ismissing(D3), 2), :);

% 시나리오별 최종 연도만 추출
[~, idx] = sortrows(D3, {'w_economy','w_reliability','w_safety_environment','year'});
D3 = D3(idx, :);
[~, last_idx] = unique(D3(:, {'w_economy','w_reliability','w_safety_environment'}), 'rows', 'last');
DS = D3(last_idx, :);

%% ── 기준 시나리오 가중치 (AHP 결과) ─────────────────────────────────
W_eco  = 0.3541;
W_rel  = 0.2616;
W_saf  = 0.3842;

tol = 0.005;
base_iv = D4.iv_billion( abs(D4.w_economy - W_eco) < tol & ...
                          abs(D4.w_reliability - W_rel) < tol & ...
                          abs(D4.w_safety_environment - W_saf) < tol );
base_saidi = DS.saidi_removed_cumulative_min( ...
                          abs(DS.w_economy - W_eco) < tol & ...
                          abs(DS.w_reliability - W_rel) < tol & ...
                          abs(DS.w_safety_environment - W_saf) < tol );

%% ── 그림 설정 ─────────────────────────────────────────────────────────
FONT     = 'KoPub돋움체 Bold';
PT_AXIS  = 20;
PT_TICK  = 15;
PT_TITLE = 16;

fig = figure('Units','centimeters','Position',[2 2 44 20], ...
             'Color','w');

panels = { ...
    D4.w_economy, D4.w_reliability, D4.w_safety_environment, D4.iv_billion, ...
      '(a) 투자가치', '투자가치 (억원)', 'plasma', base_iv; ...
    DS.w_economy, DS.w_reliability, DS.w_safety_environment, DS.saidi_removed_cumulative_min, ...
      '(b) SAIDI 저감', 'SAIDI 저감 (분)', 'viridis', base_saidi ...
};

for k = 1:2
    x   = panels{k, 1};
    y   = panels{k, 2};
    z   = panels{k, 3};
    c   = panels{k, 4};
    ttl = panels{k, 5};
    clb = panels{k, 6};
    cmp = panels{k, 7};
    bv  = panels{k, 8};

    ax = subplot(1, 2, k);

    % 3D scatter
    sc = scatter3(ax, x, y, z, 120, c, 'filled', ...
                  'MarkerEdgeColor','w','LineWidth',0.4);
    colormap(ax, cmp);
    cb = colorbar(ax);
    cb.Label.String      = clb;
    cb.Label.FontName    = FONT;
    cb.Label.FontSize    = PT_TICK;
    cb.FontName          = FONT;
    cb.FontSize          = PT_TICK;

    hold(ax, 'on');

    % 기준 시나리오 마커
    if ~isempty(bv)
        plot3(ax, W_eco, W_rel, W_saf, ...
              'p', 'MarkerSize', 22, ...
              'MarkerFaceColor', [0.8 0.0 0.1], ...
              'MarkerEdgeColor', [0.5 0 0], ...
              'LineWidth', 1.0, ...
              'DisplayName', '기준 시나리오');
        legend(ax, 'Location','northwest','FontName',FONT,'FontSize',PT_TICK);
    end
    hold(ax, 'off');

    % 축 범위·눈금
    xlim(ax, [0 1]); ylim(ax, [0 1]); zlim(ax, [0 1]);
    xticks(ax, 0:0.2:1);
    yticks(ax, 0:0.2:1);
    zticks(ax, 0:0.2:1);

    % 축 레이블
    xlabel(ax, '경제성 가중치', 'FontName',FONT,'FontSize',PT_AXIS,'FontWeight','bold');
    ylabel(ax, '신뢰도 가중치', 'FontName',FONT,'FontSize',PT_AXIS,'FontWeight','bold');
    zlabel(ax, '안전·환경 가중치','FontName',FONT,'FontSize',PT_AXIS,'FontWeight','bold');
    title(ax,  ttl, 'FontName',FONT,'FontSize',PT_TITLE,'FontWeight','bold');

    % 눈금 폰트
    ax.FontName   = FONT;
    ax.FontSize   = PT_TICK;
    ax.FontWeight = 'bold';

    % 시점
    view(ax, -50, 20);
    grid(ax, 'on');
    box(ax, 'on');
end

%% ── 저장 ──────────────────────────────────────────────────────────────
out = fullfile(OUT_DIR, 'fig4_10_operating_goal_weight_sensitivity.png');
exportgraphics(fig, out, 'Resolution', 300);
fprintf('저장 완료: %s\n', out);
