# Claude Code 작업 지시서: 제4장 최적화 시뮬레이션 및 결과 분석 작성

## 0. 작업 목적

본 문서는 박사학위논문 제4장 `최적화 시뮬레이션 및 결과 분석`을 작성하기 위한 작업 지시서이다.  
제4장은 본 논문의 핵심 주장인 `투자가치`, `설비 단위 PI`, `통합 PI` 기반 포트폴리오 최적화의 효과를 시뮬레이션 결과로 증명하는 장이다.

제4장은 단순히 결과표를 나열하는 장이 아니라 다음 논리를 단계적으로 검증해야 한다.

1. 기존 Risk 우선순위 방식은 위험수준을 설명하는 데 유용하지만, 투자비용 대비 효과를 직접 최적화하지 못한다.
2. 투자가치 기반 최적화는 동일한 예산·물량 조건에서 Risk 우선순위 방식보다 경제성 측면에서 우수한 포트폴리오를 도출한다.
3. 설비 단위 PI 기반 최적화는 투자가치 단일지표가 충분히 반영하지 못하는 신뢰도, 안전·환경 성과를 반영한다.
4. 통합 PI 기반 최적화는 이종 설비를 전력회사 전체 관점에서 하나의 포트폴리오로 비교할 수 있게 한다.
5. 민감도 및 강건성 분석을 통해 제안 방법론의 결론이 특정 기준값에만 의존하지 않음을 확인한다.

---

## 1. 기본 작업 규칙

### 1.1 언어와 문체

- 모든 본문은 한국어로 작성한다.
- 문체는 박사학위논문 수준의 학술 문체로 작성한다.
- 문장은 지나치게 짧은 보고서식 나열을 피하고, `결과 → 해석 → 연구적 의미`가 연결되도록 작성한다.
- AI가 작성한 듯한 반복 문구를 피한다.
- `본 연구는 ...`이라는 표현을 과도하게 반복하지 않는다.
- `결과적으로`, `따라서`, `이는`, `한편` 등 연결어를 자연스럽게 사용하되 기계적으로 반복하지 않는다.

### 1.2 용어 기준

다음 용어를 일관되게 사용한다.

| 사용 용어 | 피할 표현 |
|---|---|
| 설비 단위 PI | Local PI |
| 통합 PI | Integrated PI |
| 투자가치 | NPV, 투자순가치 혼용 |
| Risk 저감량 | Risk 감소량, 위험도 감소량 혼용 |
| 고장예측대수 | 고장 대수, 연간 고장 대수 혼용 |
| 2단계 통합 PI 최적화 방식 | 통합 사후 가중 방식 |
| 비교 시나리오 | 절제실험 |

### 1.3 시뮬레이션 해석 원칙

- 메인 비교는 `Greedy`, `ILP`, `GA` 결과를 중심으로 해석한다.
- `NSGA-II`는 대표 결과가 아니라 확장 다목적 탐색 결과로만 설명한다.
- 투자가치 최적화에서는 `투자비용 최소화`를 별도 목적함수로 병렬 적용하지 않는다.
- 대표 통합 방식은 `2단계 통합 PI 최적화 방식`이다.
- `사전 통합 PI 방식`은 대표 방식이 아니라 비교 시나리오로 설명한다.
- BWM 결과는 독립 BWM 설문이 아니라 AHP 응답 기반 재구성 비교군으로 설명한다.

---

## 2. 우선 참고해야 할 폴더와 파일

제4장 작성 시에는 우선 다음 폴더를 기준으로 자료를 확인한다.

```text
C:\Users\shfmq\codexwork\AHP_AIP\연구설계
```

### 2.1 연구설계 기준 파일

```text
연구설계/00_연구설계/연구설계_최종.md
연구설계/00_연구설계/파일_인덱스.md
연구설계/README.md
```

### 2.2 본문 원고

```text
연구설계/01_논문_장별/05_제4장_제안_방법론.md
연구설계/01_논문_장별/06_제5장_시범적용_및_결과_분석.md
```

현재 논문 목차에서는 결과 장이 `제4장 최적화 시뮬레이션 및 결과 분석`으로 조정되었으므로, 기존 장별 파일의 번호와 실제 목차 번호가 다를 수 있다. 본 작업에서는 사용자가 제시한 최신 목차를 따른다.

### 2.3 본문 시뮬레이션 결과

```text
연구설계/06_시뮬레이션결과/본문_시뮬레이션/simulation_chapter_v2_results.xlsx
```

주요 시트:

| 시트 | 용도 |
|---|---|
| `00_run_config` | 실행 조건 |
| `01_candidate_summary` | 설비유형별 후보군 요약 |
| `01_budget_summary` | 예산 요약 |
| `02_value_type_annual` | Risk/투자가치 기반 설비유형별 연도별 결과 |
| `02_value_type_total` | Risk/투자가치 기반 설비유형별 합산 결과 |
| `03_value_combined_annual` | Risk/투자가치 기반 전체설비 연도별 결과 |
| `03_value_combined_total` | Risk/투자가치 기반 전체설비 합산 결과 |
| `04_pi_type_annual` | PI 기반 설비유형별 연도별 결과 |
| `04_pi_type_total` | PI 기반 설비유형별 합산 결과 |
| `05_pi_combined_annual` | PI 기반 전체설비 연도별 결과 |
| `05_pi_combined_total` | PI 기반 전체설비 합산 결과 |
| `06_integrated_annual` | 통합 PI 기반 연도별 결과 |
| `06_integrated_total` | 통합 PI 기반 합산 결과 |
| `07_final_comparison` | 최종 비교표 |
| `08_solver_status` | Solver 상태 |
| `09_ga_progress` | GA 수렴 과정 |
| `10_figure_manifest` | 생성 그림 목록 |

### 2.4 PI 산출 결과

```text
연구설계/05_PI_산출결과/local_pi_matlab.xlsx
연구설계/05_PI_산출결과/integrated_pi_matlab.xlsx
연구설계/05_PI_산출결과/bwm_pi_matlab.xlsx
```

`local_pi_matlab.xlsx` 주요 시트:

| 시트 | 용도 |
|---|---|
| `criteria_weights` | 대기준 가중치 |
| `ahp_sub_weights` | AHP 하위지표 가중치 |
| `fuzzy_adjusted_weights` | Fuzzy 보정가중치 |
| `normalization_summary` | 정규화 기준 |
| `pi_summary_year` | 연도별 PI 요약 |
| `pi_summary_type_year` | 설비유형별 PI 요약 |
| `local_pi_asset_wide` | 설비 단위 PI 상세 |
| `local_pi_asset_year` | 설비-연도별 PI 상세 |

`integrated_pi_matlab.xlsx` 주요 시트:

| 시트 | 용도 |
|---|---|
| `type_weights` | 설비유형 가중치 및 비용 보정계수 |
| `integrated_pi_asset_wide` | 통합 PI 상세 |
| `integrated_pi_summary_type_year` | 통합 PI 설비유형별 요약 |

### 2.5 민감도 및 강건성 결과

```text
연구설계/06_시뮬레이션결과/민감도_강건성/sensitivity_analysis_results_final.xlsx
```

주요 시트:

| 시트 | 용도 |
|---|---|
| `00_run_config` | 민감도 분석 실행 조건 |
| `01_baseline_kpi` | 기준 KPI |
| `02_scope_definition` | 분석 범위 |
| `02_weight_scenarios` | 운영목표 가중치 시나리오 |
| `02b_scenarios` | 전체 민감도 시나리오 |
| `03_annual_summary` | 연도별 결과 |
| `04_total_summary` | 합산 결과 |
| `05_type_summary` | 설비유형별 결과 |
| `06_constraint_check` | 제약조건 충족 여부 |
| `07_solver_status` | Solver 상태 |
| `08_figure_manifest` | 그림 목록 |
| `09_rank_by_scenario` | 시나리오별 순위 |
| `10_robustness_summary` | 강건성 요약 |
| `11_baseline_improvement` | 기준 대비 개선율 |
| `12_feasibility_summary` | 실현가능성 요약 |
| `13_conclusion_check` | 핵심 결론 검증 |

---

## 3. 제4장 전체 구성

사용자가 확정한 제4장 목차는 다음과 같다.

```text
제4장 최적화 시뮬레이션 및 결과 분석
  제1절 시뮬레이션 개요
  제2절 Risk 및 투자가치 기반 포트폴리오 최적화 시뮬레이션
  제3절 PI 기반 설비 단위 포트폴리오 최적화 시뮬레이션
    1. 설비 단위 PI 산출
    2. PI 기반 설비 단위 최적화 시뮬레이션 효과 분석
  제4절 통합 PI 기반 시스템 단위 포트폴리오 최적화 시뮬레이션
    1. 통합 PI 산출 및 적용 프로세스
    2. 통합 PI 기반 시스템 단위 최적화 시뮬레이션 효과 분석
  제5절 민감도 및 강건성 비교
    1. 제약조건 민감도 분석
    2. 다기준 성능지표 민감도 분석
    3. 시뮬레이션 강건성 검증
  제6절 최적화 시뮬레이션 결과 고찰
```

---

## 4. 제1절 시뮬레이션 개요 작성 계획

### 4.1 목적

제1절은 제4장에서 수행하는 모든 시뮬레이션의 공통 전제를 설명한다.  
결과를 깊게 해석하기보다, 이후 절에서 제시되는 표와 그림을 이해하기 위한 실험 설계를 정리한다.

### 4.2 작성할 핵심 내용

- 분석 대상 설비 6종
- 계획기간 2026~2030년
- 의사결정 단위: 설비-연도 조합
- 후보군 구성: 기준연도 Risk 상위 30%와 투자가치 상위 30%의 합집합
- 연도별 예산 제약
- 연도별 물량 제약
- 설비별 최대 1회 교체 제약
- 기본 시나리오에서는 의무교체와 설비유형별 최소·최대 배분제약 제외
- 비교 기법: Risk Greedy, 투자가치 Greedy, 투자가치 ILP, 투자가치 GA, PI Greedy, PI ILP, PI GA, 통합 PI ILP, 통합 PI GA, NSGA-II 확장 분석

### 4.3 표와 그림

#### 표 4.1 Simulation Input Data and Planning Conditions

| 구분 | 기준값 또는 적용 방식 |
|---|---|
| 계획기간 | 2026~2030년 |
| 분석 단위 | 설비-연도 조합 |
| 대상 설비 | 6개 설비유형 |
| 후보군 | Risk 상위 30% ∪ 투자가치 상위 30% |
| 예산 제약 | 연도별 예산 |
| 물량 제약 | 연도별 교체 가능 대수 |
| 할인율 | 5% |
| 최적화 기법 | Greedy, ILP, GA, NSGA-II 확장 분석 |

#### 표 4.2 Candidate Asset Summary by Asset Type

출처:

```text
simulation_chapter_v2_results.xlsx
01_candidate_summary
```

포함 항목:

- 설비유형
- 전체 설비 수
- 후보 설비 수
- 후보 비율
- 자산가액
- 설비유형 가중치

#### 그림 4.1 Overall Simulation Procedure

내용:

```text
PoF·Risk·투자효과 입력
↓
후보군 구성
↓
Risk/투자가치 기반 시뮬레이션
↓
설비 단위 PI 기반 시뮬레이션
↓
통합 PI 기반 시뮬레이션
↓
민감도 및 강건성 분석
↓
최종 비교 및 고찰
```

#### 그림 4.2 Candidate Asset Distribution by Asset Type

- x축: 설비유형
- y축: 후보 설비 수 또는 후보 비율
- 전체 설비 수와 후보 설비 수를 함께 표시

---

## 5. 제2절 Risk 및 투자가치 기반 포트폴리오 최적화 시뮬레이션

### 5.1 검증 질문

기존 Risk 우선순위 방식보다 투자가치 기반 최적화가 경제성 측면에서 더 우수한가?

### 5.2 절 구성

```text
1. 투자가치 분포 분석
2. Risk 우선순위와 투자가치 우선순위의 차이
3. 개별설비별 시뮬레이션 결과
4. 전체 설비 합산 결과 비교
5. 소결
```

### 5.3 투자가치 분포 분석

#### 그림 4.3 Investment Value Distribution of Candidate Assets

형태:

- x축: 투자 순번
- y축: 투자가치
- 투자가치 내림차순 정렬
- 0 기준선 표시
- 양의 투자가치와 음의 투자가치 영역 구분

본문 해석:

- 투자가치가 양수인 설비는 Risk 저감량이 투자비용보다 큰 설비이다.
- 투자가치가 음수인 설비는 교체효과보다 비용 부담이 큰 설비이다.
- Risk가 높다고 항상 투자가치가 높은 것은 아니다.
- Risk 우선순위만으로 투자대상을 정하면 경제성이 낮은 설비가 포함될 수 있다.

#### 그림 4.4 Risk and Investment Value Relationship

형태:

- x축: 기준연도 Risk
- y축: 투자가치
- 색상: 설비유형
- 0선 표시

목적:

- Risk와 투자가치가 동일한 지표가 아님을 시각적으로 보여준다.

### 5.4 개별설비별 결과

출처:

```text
simulation_chapter_v2_results.xlsx
02_value_type_annual
02_value_type_total
```

#### 표 4.3~4.8 Asset-Level Results of Risk and Investment Value Optimization

설비유형별 표 구조:

| 구분 | 투자대수 | 투자비용 | Risk 저감량 | 투자가치 | 투자효율 | SAIDI 저감 |
|---|---:|---:|---:|---:|---:|---:|
| Risk Greedy |  |  |  |  |  |  |
| IV Greedy |  |  |  |  |  |  |
| IV ILP |  |  |  |  |  |  |
| IV GA |  |  |  |  |  |  |

#### 그림 4.5 Annual Investment Cost by Risk and Investment Value Methods

- x축: 연도
- y축: 투자비용
- 막대: Risk Greedy, IV Greedy, IV ILP, IV GA

#### 그림 4.6 Annual Replacement Quantity by Risk and Investment Value Methods

- x축: 연도
- y축: 투자대수
- 막대: Risk Greedy, IV Greedy, IV ILP, IV GA

### 5.5 전체 설비 합산 결과 비교

출처:

```text
simulation_chapter_v2_results.xlsx
03_value_combined_total
07_final_comparison
```

#### 그림 4.7 Total Performance Comparison of Risk and Investment Value Methods

형태:

- x축: Risk Greedy, IV Greedy, IV ILP, IV GA
- 막대: Risk 저감량, 투자비용, 투자가치
- 보조축: 투자효율

#### 표 4.9 Aggregate Results of Risk and Investment Value Optimization

| 결과 분석 | 단위 | Risk Greedy | IV Greedy | IV ILP | IV GA |
|---|---|---:|---:|---:|---:|
| 투자대수 | 대 |  |  |  |  |
| 투자비용 | 백만원 |  |  |  |  |
| Risk 저감량 | 백만원 |  |  |  |  |
| 투자가치 | 백만원 |  |  |  |  |
| 투자효율 | - |  |  |  |  |
| SAIDI 저감 | 분 |  |  |  |  |

Risk Greedy 대비 증가율 표를 별도로 제시한다.

| 지표 | IV Greedy | IV ILP | IV GA |
|---|---:|---:|---:|
| 투자비용 증감률 |  |  |  |
| Risk 저감량 증가율 |  |  |  |
| 투자가치 증가율 |  |  |  |
| 투자효율 증가폭 |  |  |  |
| SAIDI 증감률 |  |  |  |

### 5.6 제2절 핵심 해석

투자가치 기반 최적화는 기존 Risk 우선순위 방식보다 동일한 예산·물량 조건에서 경제적 투자효과를 더 명확하게 개선한다.  
특히 ILP는 후보군 내에서 비용과 Risk 저감효과의 조합을 동시에 고려하므로, Risk가 높지만 비용효율이 낮은 설비를 배제하고 순편익이 큰 설비를 선택할 수 있다.

---

## 6. 제3절 PI 기반 설비 단위 포트폴리오 최적화 시뮬레이션

### 6.1 검증 질문

투자가치 단일지표에 신뢰도, 안전·환경 기준을 추가하면 포트폴리오가 어떻게 달라지는가?

### 6.2 절 구성

```text
1. 설비 단위 PI 산출 결과
2. PI 분포 분석
3. 투자가치 기반 최적화와 PI 기반 최적화 비교
4. 개별설비별 PI 최적화 결과
5. 전체 설비 합산 결과 비교
6. 소결
```

### 6.3 설비 단위 PI 산출 결과

출처:

```text
local_pi_matlab.xlsx
criteria_weights
ahp_sub_weights
fuzzy_adjusted_weights
normalization_summary
pi_summary_type_year
local_pi_asset_wide
```

#### 표 4.10 Criteria and Sub-Criteria Weights for Asset-Level PI

포함 항목:

- 경제성
- 신뢰도
- 안전·환경
- 하위지표별 가중치
- AHP 가중치
- Fuzzy 보정가중치

#### 그림 4.8 Weight Structure of Asset-Level PI

내용:

- 경제성, 신뢰도, 안전·환경
- 6개 하위지표
- 하위지표별 가중치

### 6.4 PI 분포 분석

#### 그림 4.9 Distribution of Asset-Level PI

- x축: PI 순번
- y축: 설비 단위 PI
- 내림차순 정렬
- 설비유형별 색상 구분

본문 해석:

- PI는 투자가치뿐 아니라 SAIDI, 고장예측대수, 안전·환경 기대영향을 함께 반영한다.
- 투자가치 상위 설비와 PI 상위 설비가 반드시 일치하지 않는다.
- PI 기반 방식은 경제성 중심 방식보다 공공적 KPI 반영성이 크다.

#### 그림 4.10 Investment Value and Asset-Level PI Relationship

- x축: 투자가치
- y축: 설비 단위 PI
- 색상: 설비유형

목적:

- 투자가치와 PI가 같은 방향으로만 움직이지 않는다는 점을 시각화한다.

### 6.5 개별설비별 PI 최적화 결과

출처:

```text
simulation_chapter_v2_results.xlsx
04_pi_type_annual
04_pi_type_total
```

#### 표 4.11~4.16 Asset-Level PI Optimization Results by Asset Type

| 구분 | 투자대수 | 투자비용 | Risk 저감량 | 투자가치 | SAIDI 저감 | 고장예측대수 저감 | 설비 단위 PI |
|---|---:|---:|---:|---:|---:|---:|---:|
| IV ILP |  |  |  |  |  |  |  |
| PI Greedy |  |  |  |  |  |  |  |
| PI ILP |  |  |  |  |  |  |  |
| PI GA |  |  |  |  |  |  |  |

#### 그림 4.11 Annual Cost and Quantity of Asset-Level PI Optimization

- 연도별 투자비용
- 연도별 투자대수

### 6.6 전체 설비 합산 결과 비교

출처:

```text
simulation_chapter_v2_results.xlsx
05_pi_combined_total
07_final_comparison
```

#### 그림 4.12 Aggregate Comparison of Investment Value and Asset-Level PI Methods

- x축: IV ILP, IV GA, PI Greedy, PI ILP, PI GA
- 막대: 투자가치, Risk 저감량, 설비 단위 PI
- 보조축: SAIDI 저감

#### 표 4.17 Aggregate Results of Asset-Level PI Optimization

| 결과 분석 | 단위 | IV ILP | PI Greedy | PI ILP | PI GA |
|---|---|---:|---:|---:|---:|
| 투자대수 | 대 |  |  |  |  |
| 투자비용 | 백만원 |  |  |  |  |
| Risk 저감량 | 백만원 |  |  |  |  |
| 투자가치 | 백만원 |  |  |  |  |
| SAIDI 저감 | 분 |  |  |  |  |
| 고장예측대수 저감 | 대 |  |  |  |  |
| 설비 단위 PI | - |  |  |  |  |

### 6.7 제3절 핵심 해석

PI 기반 최적화는 투자가치 기반 최적화보다 경제성 지표가 일부 낮아질 수 있으나, 공급신뢰도와 다기준 성과를 개선한다.  
이는 전력회사 투자계획이 단순한 경제성 최대화 문제가 아니라, 운영 KPI와 공공성을 함께 고려해야 하는 다기준 의사결정 문제임을 보여준다.

---

## 7. 제4절 통합 PI 기반 시스템 단위 포트폴리오 최적화 시뮬레이션

### 7.1 검증 질문

설비유형별로 따로 최적화하는 것이 아니라, 이종 설비를 하나의 시스템 관점 포트폴리오로 통합할 수 있는가?

### 7.2 절 구성

```text
1. 통합 PI 산출 및 적용 프로세스
2. 설비유형 가중치와 비용 규모 보정
3. 통합 PI 분포 분석
4. 통합 PI 기반 최적화 결과
5. 사후 통합 방식과 사전 통합 방식 비교
6. 설비유형별 선택 분포 분석
7. 소결
```

### 7.3 통합 PI 산출 및 적용 프로세스

출처:

```text
integrated_pi_matlab.xlsx
type_weights
integrated_pi_asset_wide
integrated_pi_summary_type_year
```

#### 표 4.18 Asset Type Weights and Cost Scale Factors

| 설비유형 | 전문가 가중치 | 비용 보정계수 | 통합 가중치 |
|---|---:|---:|---:|
| 주상변압기 |  |  |  |
| 지상변압기 |  |  |  |
| 가공개폐기 |  |  |  |
| 지중개폐기 |  |  |  |
| 가공배전선로 |  |  |  |
| 지중케이블 |  |  |  |

#### 그림 4.13 Integrated PI Calculation Process

내용:

```text
Asset-Level PI
↓
Asset Type Weight
↓
Cost Scale Factor
↓
Integrated PI
↓
System-Level Portfolio Optimization
```

### 7.4 통합 PI 분포 분석

#### 그림 4.14 Distribution of Integrated PI

- x축: 통합 PI 순번
- y축: 통합 PI
- 설비유형별 색상

#### 그림 4.15 Asset-Level PI vs Integrated PI

- x축: 설비 단위 PI
- y축: 통합 PI
- 색상: 설비유형

목적:

- 설비유형 가중치가 적용되면서 투자 우선순위가 어떻게 달라지는지 보여준다.

### 7.5 통합 최적화 결과 비교

출처:

```text
simulation_chapter_v2_results.xlsx
06_integrated_total
07_final_comparison
```

#### 표 4.19 Integrated PI Optimization Results

| 결과 분석 | 단위 | IV ILP | PI ILP | Post-Weighted Integrated PI ILP | Pre-Integrated PI ILP |
|---|---|---:|---:|---:|---:|
| 투자대수 | 대 |  |  |  |  |
| 투자비용 | 백만원 |  |  |  |  |
| Risk 저감량 | 백만원 |  |  |  |  |
| 투자가치 | 백만원 |  |  |  |  |
| SAIDI 저감 | 분 |  |  |  |  |
| 설비 단위 PI | - |  |  |  |  |
| 통합 PI | - |  |  |  |  |

#### 그림 4.16 Aggregate Comparison of Integrated PI Optimization

- x축: IV ILP, PI ILP, Integrated PI ILP, Pre-Integrated PI ILP
- 막대: Risk 저감량, 투자가치, 설비 단위 PI, 통합 PI
- 보조축: SAIDI 저감

### 7.6 설비유형별 선택 분포

출처:

```text
sensitivity_analysis_results_final.xlsx
05_type_summary
```

또는 본문 결과의 통합 결과 시트를 활용한다.

#### 그림 4.17 Selected Portfolio Composition by Asset Type

- x축: 방법
- y축: 선택 설비 비율
- 색상: 설비유형

#### 그림 4.18 Annual Replacement Composition of Integrated PI Optimization

- x축: 연도
- y축: 투자대수
- 색상: 설비유형

### 7.7 제4절 핵심 해석

통합 PI 기반 최적화는 설비유형별 독립 최적화 결과를 단순 합산하는 방식이 아니라, 이종 설비를 하나의 시스템 투자 포트폴리오로 비교하는 방식이다.  
특히 2단계 통합 PI 방식은 설비 단위 투자효과를 유지하면서도 설비유형 간 상대적 중요도를 반영하므로, 전력회사 관점의 포트폴리오 의사결정에 적합하다.

사전 통합 PI 방식은 통합 PI 자체는 높게 나타날 수 있으나, Risk 저감량, 투자가치, SAIDI 등 실질 KPI가 상대적으로 약화될 수 있다. 따라서 대표 방식이 아니라 통합 가중치 적용 시점의 영향을 확인하기 위한 비교 시나리오로 해석한다.

---

## 8. 제5절 민감도 및 강건성 비교

### 8.1 검증 질문

제안 방법론의 결론이 특정 예산, 특정 물량, 특정 가중치에서만 성립하는가?  
아니면 조건 변화에도 유지되는가?

### 8.2 절 구성

```text
1. 제약조건 민감도 분석
2. 다기준 성능지표 민감도 분석
3. 시뮬레이션 강건성 검증
```

### 8.3 제약조건 민감도 분석

출처:

```text
sensitivity_analysis_results_final.xlsx
02b_scenarios
03_annual_summary
04_total_summary
06_constraint_check
12_feasibility_summary
```

#### 표 4.20 Sensitivity Scenario Definition

| 구분 | 변화 범위 | 목적 |
|---|---|---|
| 예산 | 0.5~1.5배 | 예산 변화 영향 |
| 물량 | 0.5~1.5배 | 시공능력 변화 영향 |
| SAIDI 상한 | 기준 대비 강화 | 신뢰도 제약 영향 |
| Risk 총량 상한 | 기준 대비 강화 | 리스크 관리 제약 영향 |
| 운영목표 가중치 | 경제성/신뢰도/안전환경 중심 | KPI 전략 변화 영향 |

#### 그림 4.19 Budget Sensitivity of Optimization Results

- x축: 예산 배율
- y축: 투자가치 또는 통합 PI
- 선: IV ILP, PI ILP, Integrated PI ILP

#### 그림 4.20 Quantity Constraint Sensitivity

- x축: 물량 배율
- y축: 투자효과

#### 그림 4.21 SAIDI and Risk Constraint Feasibility Map

- x축: SAIDI 제약 수준
- y축: Risk 총량 제약 수준
- 색상: 실현가능성 또는 목적함수 값

### 8.4 다기준 성능지표 민감도 분석

출처:

```text
sensitivity_analysis_results_final.xlsx
02_weight_scenarios
09_rank_by_scenario
10_robustness_summary
11_baseline_improvement
```

#### 그림 4.22 Operating Goal Weight Scenario Distribution

- x축: 경제성 가중치
- y축: 신뢰도 가중치
- z축: 안전·환경 가중치
- 색상: 투자가치 또는 SAIDI

#### 그림 4.23 Portfolio Performance under Operating Goal Scenarios

- x축: 운영목표 시나리오
- y축: 성과지표
- 선: 투자가치, SAIDI, 통합 PI

### 8.5 강건성 검증

출처:

```text
sensitivity_analysis_results_final.xlsx
13_conclusion_check
10_robustness_summary
11_baseline_improvement
```

#### 표 4.21 Robustness Check of Main Conclusions

| 검증 명제 | 기준 시나리오 결과 | 민감도 분석 결과 | 판단 |
|---|---|---|---|
| IV ILP는 Risk Greedy보다 경제성이 우수한가 |  |  | 유지/부분유지 |
| PI ILP는 SAIDI와 PI를 개선하는가 |  |  | 유지/부분유지 |
| 통합 PI 방식은 시스템 관점 성과를 개선하는가 |  |  | 유지/부분유지 |
| 운영목표 변화 시 포트폴리오가 설명 가능하게 변화하는가 |  |  | 유지/부분유지 |

### 8.6 제5절 핵심 해석

민감도 분석 결과, 제안 프레임워크는 특정 기준값에서만 작동하는 단일 시나리오 해가 아니라, 예산·물량·운영 KPI·가중치 변화에 따라 포트폴리오 구성이 합리적으로 변화하는 의사결정 체계임을 확인하였다.

---

## 9. 제6절 최적화 시뮬레이션 결과 고찰

### 9.1 절 구성

```text
1. Risk 우선순위 방식의 의미와 한계
2. 투자가치 기반 방식의 경제성 개선 효과
3. PI 기반 방식의 다기준 성과 개선 효과
4. 통합 PI 기반 방식의 시스템 관점 의사결정 효과
5. 민감도 분석을 통한 강건성 확인
6. 실무적 시사점
```

### 9.2 핵심 논리

#### Risk 우선순위 방식

Risk 우선순위는 위험수준이 높은 설비를 식별하는 데 유용하지만, 투자비용 대비 효과를 직접 반영하지 못한다.

#### 투자가치 기반 방식

투자가치 기반 ILP는 동일한 예산과 물량 제약 아래에서 Risk 저감량과 투자비용의 조합을 최적화하므로, 경제성 측면에서 Risk Greedy보다 우수한 포트폴리오를 도출한다.

#### PI 기반 방식

PI 기반 방식은 경제성 단일지표에서 벗어나 신뢰도, 안전·환경 기준을 반영하므로, 투자가치가 일부 낮아지더라도 전력회사 운영 KPI 관점에서 더 균형 잡힌 투자계획을 제시할 수 있다.

#### 통합 PI 기반 방식

통합 PI 기반 방식은 설비유형별 독립 최적화의 한계를 보완하고, 이종 설비를 하나의 시스템 투자 포트폴리오로 비교할 수 있게 한다.

#### 민감도 분석

예산, 물량, SAIDI, Risk 총량, 운영목표 가중치 변화에서도 핵심 결론이 유지되는지를 확인함으로써 제안 방법론의 실용적 안정성을 검토한다.

---

## 10. 전체 그림 목록

| 번호 | 그림명 |
|---|---|
| 그림 4.1 | Overall Simulation Procedure |
| 그림 4.2 | Candidate Asset Distribution by Asset Type |
| 그림 4.3 | Investment Value Distribution of Candidate Assets |
| 그림 4.4 | Risk and Investment Value Relationship |
| 그림 4.5 | Annual Investment Cost by Risk and Investment Value Methods |
| 그림 4.6 | Annual Replacement Quantity by Risk and Investment Value Methods |
| 그림 4.7 | Total Performance Comparison of Risk and Investment Value Methods |
| 그림 4.8 | Weight Structure of Asset-Level PI |
| 그림 4.9 | Distribution of Asset-Level PI |
| 그림 4.10 | Investment Value and Asset-Level PI Relationship |
| 그림 4.11 | Annual Cost and Quantity of Asset-Level PI Optimization |
| 그림 4.12 | Aggregate Comparison of Investment Value and Asset-Level PI Methods |
| 그림 4.13 | Integrated PI Calculation Process |
| 그림 4.14 | Distribution of Integrated PI |
| 그림 4.15 | Asset-Level PI vs Integrated PI |
| 그림 4.16 | Aggregate Comparison of Integrated PI Optimization |
| 그림 4.17 | Selected Portfolio Composition by Asset Type |
| 그림 4.18 | Annual Replacement Composition of Integrated PI Optimization |
| 그림 4.19 | Budget Sensitivity of Optimization Results |
| 그림 4.20 | Quantity Constraint Sensitivity |
| 그림 4.21 | SAIDI and Risk Constraint Feasibility Map |
| 그림 4.22 | Operating Goal Weight Scenario Distribution |
| 그림 4.23 | Portfolio Performance under Operating Goal Scenarios |

---

## 11. 전체 표 목록

| 번호 | 표명 |
|---|---|
| 표 4.1 | Simulation Input Data and Planning Conditions |
| 표 4.2 | Candidate Asset Summary by Asset Type |
| 표 4.3~4.8 | Asset-Level Results of Risk and Investment Value Optimization |
| 표 4.9 | Aggregate Results of Risk and Investment Value Optimization |
| 표 4.10 | Criteria and Sub-Criteria Weights for Asset-Level PI |
| 표 4.11~4.16 | Asset-Level PI Optimization Results by Asset Type |
| 표 4.17 | Aggregate Results of Asset-Level PI Optimization |
| 표 4.18 | Asset Type Weights and Cost Scale Factors |
| 표 4.19 | Integrated PI Optimization Results |
| 표 4.20 | Sensitivity Scenario Definition |
| 표 4.21 | Robustness Check of Main Conclusions |

---

## 12. 작성 순서

실제 작성은 다음 순서로 진행한다.

1. 제1절 시뮬레이션 개요 작성
2. 표 4.1~4.2 생성
3. 후보군 분포, 투자가치 분포 그림 생성
4. 제2절 Risk 및 투자가치 기반 시뮬레이션 작성
5. 설비유형별 결과표와 종합표 생성
6. 제3절 PI 기반 설비 단위 시뮬레이션 작성
7. PI 분포, 투자가치-PI 산점도 생성
8. 제4절 통합 PI 기반 시뮬레이션 작성
9. 통합 PI 분포, 설비유형 선택분포 생성
10. 제5절 민감도 및 강건성 작성
11. 민감도 그래프와 강건성 표 생성
12. 제6절 결과 고찰 작성

---

## 13. 제4장의 최종 메시지

제4장은 다음 문장을 증명하는 장이 되어야 한다.

> 본 연구에서 제안한 투자가치, 설비 단위 PI 및 통합 PI 기반 포트폴리오 최적화 방식은 기존 Risk 우선순위 방식보다 투자효과를 더 정교하게 설명하며, 경제성 중심 의사결정에서 신뢰도·안전·환경 및 시스템 관점 의사결정으로 확장 가능한 전력설비 투자계획 프레임워크를 제공한다.

