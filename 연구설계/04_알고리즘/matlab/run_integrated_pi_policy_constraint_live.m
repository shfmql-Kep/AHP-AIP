%% 통합 PI 정책 제약 시뮬레이션 실행 스크립트
% MATLAB Live Script(.mlx)에서 이 내용을 그대로 복사해 실행해도 된다.
%
% 목적:
%   1. 기존 시나리오의 투자가치 기반 ILP와 통합 PI ILP를 기준안으로 산정한다.
%   2. 설비유형별 연간 최소 물량 교체 비율 하한을 추가한 정책 제약형 결과를 산정한다.
%   3. 설비유형별 자산가액 대비 연간 최소 투자예산 하한을 추가한 정책 제약형 결과를 산정한다.
%   4. 기준안과 정책 제약안의 통합 PI, 투자가치, 리스크 저감량, SAIDI, 설비유형별 배분 변화를 비교한다.

%% 1. 작업 경로 설정
clear; clc;

rootDir = "C:\Users\shfmq\codexwork\AHP_AIP";
scriptPath = fullfile(rootDir, "연구설계", "04_알고리즘", "matlab", ...
    "integrated_pi_policy_constraint_matlab.m");

if ~isfile(scriptPath)
    error("정책 제약 시뮬레이션 스크립트를 찾을 수 없습니다: %s", scriptPath);
end

cd(rootDir);
fprintf("작업 폴더: %s\n", pwd);
fprintf("실행 스크립트: %s\n", scriptPath);

% MATLAB 세션이 이전 버전의 로컬 함수를 캐시하고 있을 수 있으므로,
% 실행 전 함수 캐시와 경로 캐시를 강제로 갱신한다.
clear functions;
rehash;

% 실행 대상 코드가 연간 정책 제약 버전인지 사전에 검증한다.
scriptText = fileread(scriptPath);
if ~contains(scriptText, "scenarioListToTable(scenarioList, assetTypes, assetLabels, years)") || ...
        ~contains(scriptText, "'scenario_group', 'year', 'asset_type'")
    error("현재 실행 대상 스크립트가 연간 정책 제약 버전이 아닙니다. 파일 저장 상태를 확인하십시오: %s", scriptPath);
end

%% 2. 비교 방법 및 정책 제약 시나리오 설정
% 설비유형 순서:
% 1) 주상변압기
% 2) 지상변압기
% 3) 가공개폐기
% 4) 지중개폐기
% 5) 가공배전선로
% 6) 지중케이블

% 2.1 기준안 및 비교 방법
% 기준안은 기존 본문 시나리오의 투자가치 기반 ILP와, 설비유형별 최소 제약이 없는 통합 PI ILP이다.
% 정책 제약 시나리오도 동일한 두 목적함수로 함께 실행하여, 정책 제약이 목적함수별 결과에 미치는 영향을 비교한다.
setenv("POLICY_METHODS", "investment_value_ilp,integrated_pi_ilp");

% 2.2 설비유형별 최소 물량 교체 비율
% 값은 각 설비유형의 전체 보유대수 대비 매년 최소 교체해야 하는 비율이다.
% 기준 물량상한 5%와 숫자상 혼동되지 않도록 1.0~4.5%를 0.5%p 간격으로 검토한다.
setenv("POLICY_MIN_TYPE_COUNT_RATES", "0.01,0.015,0.02,0.025,0.03,0.035,0.04,0.045");

% 2.3 설비유형별 최소 투자예산 하한
% 값은 각 설비유형의 2026년 기준 자산가액 대비 매년 최소 투자해야 하는 비율이다.
% 기준 예산상한 4%와 숫자상 혼동되지 않도록 1.0~3.5%를 0.5%p 간격으로 검토한다.
setenv("POLICY_MIN_TYPE_BUDGET_RATES", "0.01,0.015,0.02,0.025,0.03,0.035");

% 2.4 사용자 지정 최소 교체대수 벡터
% 특정 설비유형에 서로 다른 연간 최소 교체대수를 부여하고 싶을 때 사용한다.
% 사용하지 않을 경우 빈 값으로 둔다.
% 예: 주상 5대, 지상 3대, 가공개폐기 3대, 지중개폐기 2대, 가공선로 4대, 지중케이블 2대
setenv("POLICY_MIN_TYPE_COUNT_VECTOR", "");
% setenv("POLICY_MIN_TYPE_COUNT_VECTOR", "5,3,3,2,4,2");

% 2.5 사용자 지정 최소 투자예산 벡터
% 단위는 kKRW이다. 사용하지 않을 경우 빈 값으로 둔다.
% 예: 각 설비유형별 연간 최소 투자예산을 직접 지정
setenv("POLICY_MIN_TYPE_BUDGET_VECTOR", "");
% setenv("POLICY_MIN_TYPE_BUDGET_VECTOR", "100000,80000,50000,50000,70000,70000");

%% 3. ILP 솔버 설정
% 시간이 부족하면 MaxTime을 줄일 수 있으나, 정책 제약형은 기준안보다 탐색이 어려울 수 있다.
% 논문용 결과는 300초 이상을 권장한다.
setenv("POLICY_ILP_MAX_TIME", "300");

% 상대 갭 허용값이다. 0.001은 0.1% 갭을 의미한다.
setenv("POLICY_ILP_REL_GAP", "0.001");

% 진행 상황을 보고 싶으면 "iter", 조용히 실행하려면 "off"로 둔다.
setenv("POLICY_ILP_DISPLAY", "iter");

%% 4. 실행 전 설정 확인
fprintf("\n=== 정책 제약 시뮬레이션 설정 ===\n");
fprintf("비교 방법: %s\n", getenv("POLICY_METHODS"));
fprintf("최소 물량 교체 비율 시나리오: %s\n", getenv("POLICY_MIN_TYPE_COUNT_RATES"));
fprintf("최소 투자예산 비율 시나리오: %s\n", getenv("POLICY_MIN_TYPE_BUDGET_RATES"));
fprintf("사용자 지정 최소 교체대수: %s\n", getenv("POLICY_MIN_TYPE_COUNT_VECTOR"));
fprintf("사용자 지정 최소 투자예산: %s\n", getenv("POLICY_MIN_TYPE_BUDGET_VECTOR"));
fprintf("ILP 시간 제한: %s초\n", getenv("POLICY_ILP_MAX_TIME"));
fprintf("ILP 상대 갭: %s\n", getenv("POLICY_ILP_REL_GAP"));

%% 5. 통합 PI 정책 제약 시뮬레이션 실행
run(scriptPath);

%% 6. 결과 확인 안내
% 결과는 다음 폴더 아래에 실행 시각별 폴더로 저장된다.
% 주의: 본 실행 스크립트 내부에서 clear가 수행되므로, 실행 후 경로 변수를 다시 정의한다.
rootDir = "C:\Users\shfmq\codexwork\AHP_AIP";
resultRoot = fullfile(rootDir, "연구설계", "06_시뮬레이션결과", "정책제약_통합PI");
latestRun = getLatestRunFolder(resultRoot);

fprintf("\n=== 실행 완료 ===\n");
fprintf("결과 루트 폴더: %s\n", resultRoot);
if strlength(latestRun) > 0
    fprintf("최신 실행 폴더: %s\n", latestRun);
    fprintf("결과 엑셀 파일: %s\n", fullfile(latestRun, "integrated_pi_policy_constraint_results.xlsx"));
end

%% 7. 결과 파일 바로 열기
% 필요하면 아래 주석을 해제한다.
% winopen(fullfile(latestRun, "integrated_pi_policy_constraint_results.xlsx"));

%% 로컬 함수
function latestRun = getLatestRunFolder(resultRoot)
latestRun = "";
if ~isfolder(resultRoot)
    return;
end
items = dir(fullfile(resultRoot, "integrated_pi_policy_constraint_*"));
items = items([items.isdir]);
if isempty(items)
    return;
end
[~, idx] = max([items.datenum]);
latestRun = string(fullfile(items(idx).folder, items(idx).name));
end
