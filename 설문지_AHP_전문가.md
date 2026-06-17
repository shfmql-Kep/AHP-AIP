# 부록 A. 전문가 설문지
# Appendix A. Expert Questionnaire

---

**연구 제목**: 다기준 의사결정과 수리 최적화를 결합한 배전설비 자산투자계획(AIP) 방법론  
**Title**: A Multi-Criteria Decision-Making and Mathematical Optimization Approach for Distribution Asset Investment Planning (AIP)

**기관**: 한국교통대학교 전기공학과 박사과정  
**지도교수**: 강형구 교수  
**연락처**: shfmql12@mokpo.ac.kr

---

## A.1 연구 개요 / Research Overview

본 연구는 배전설비(변압기·개폐기·배전선로·지지물)의 교체 투자 우선순위를 결정하기 위해 **계층분석법(AHP)**, **퍼지 계층분석법(Fuzzy AHP)**, **최선-최악법(BWM)**을 적용하여 전문가 판단을 정량화합니다. 수집된 가중치는 정수선형계획법(ILP) 및 유전 알고리즘(GA)과 결합하여 예산 제약 하 최적 투자 포트폴리오를 도출하는 데 활용됩니다.

This study applies the Analytic Hierarchy Process (AHP), Fuzzy AHP, and the Best-Worst Method (BWM) to quantify expert judgment for prioritizing replacement investment in power distribution assets. The derived weights are combined with Integer Linear Programming (ILP) and Genetic Algorithm (GA) to determine the optimal investment portfolio under budget constraints.

---

## A.2 응답자 정보 / Respondent Profile

| 항목 / Item | 내용 / Response |
|------------|----------------|
| 성명 / Name | |
| 소속 / Affiliation | |
| 직위 / Position | |
| 배전·자산관리 경력 (년) / Years of Experience | |

**전문성 자기평가 / Self-Assessment of Expertise** (해당란에 ✓ 표시)

| 분야 / Domain | 매우 낮음 1 | 2 | 3 | 4 | 매우 높음 5 |
|--------------|:-----------:|:-:|:-:|:-:|:-----------:|
| 배전설비 기술 / Distribution Asset Technology | □ | □ | □ | □ | □ |
| 자산관리·투자계획 / Asset Management & AIP | □ | □ | □ | □ | □ |
| 전력계통 신뢰도 / Power System Reliability | □ | □ | □ | □ | □ |
| 전력경제성 / Power Economics | □ | □ | □ | □ | □ |

---

## A.3 평가 계층 구조 / Evaluation Hierarchy

본 연구의 투자 우선순위 평가 기준은 아래의 3계층 구조로 구성됩니다.

```
[목표 / Goal]
배전설비 투자 우선순위 결정
Optimal Distribution Asset Investment Portfolio

        |                   |                   |
[대기준 / Main Criteria]
  C1: 경제효율성        C2: 고객 서비스      C3: Risk 저감
  Economic Efficiency   Customer Service     Risk Reduction

   |         |          |         |        |       |       |
[하위기준 / Sub-Criteria]
 C1-1     C1-2       C2-1      C2-2    C3-1    C3-2   C3-3
 NPV      BCR       SAIDI     ENF     재무    안전   환경
                    저감       저감    Risk    Risk   Risk
```

**기준 정의 / Criterion Definitions**

| 기호 | 명칭 | 정의 |
|------|------|------|
| **C1** | 경제효율성 (Economic Efficiency) | 교체 투자로 인한 재무적 편익의 규모 및 효율성 |
| **C2** | 고객 서비스 (Customer Service) | 교체 투자로 인한 전력 공급 신뢰도 향상 정도 |
| **C3** | Risk 저감 (Risk Reduction) | 교체 투자로 인한 자산 위험도(PoF×CoF) 감소 정도 |
| **C1-1** | NPV | 미래 위험 비용 절감액의 현재가치 합산 (규모) |
| **C1-2** | BCR (편익비용비율) | 교체비용 단위당 회수되는 위험 비용 저감액 (효율) |
| **C2-1** | SAIDI 저감 | 교체 후 연간 고객 평균 정전시간 저감 기대량 |
| **C2-2** | ENF 저감 | 교체 후 연간 예상 고장 건수 저감 기대량 |
| **C3-1** | 재무 Risk 저감 | 정전으로 인한 재무 피해 위험도 저감량 |
| **C3-2** | 안전 Risk 저감 | 인명 안전 피해 위험도 저감량 |
| **C3-3** | 환경 Risk 저감 | 환경 오염 피해 위험도 저감량 |

---

---

# Part 1. 계층분석법 (Classical AHP)

## 응답 방법 / Instructions

두 기준을 비교하여 **어느 기준이 더 중요한지**, 그리고 **얼마나 더 중요한지**를 아래 척도에 따라 판단하여 해당 칸에 ✓ 표시하십시오.

Compare each pair of criteria and indicate **which criterion is more important** and **how much more important** using the scale below.

### Saaty(1980) 중요도 척도 / Importance Scale

| 척도 / Scale | 정의 / Definition | 설명 / Explanation |
|:---:|---|---|
| **1** | 동등하게 중요 (Equal importance) | 두 기준이 동등하게 기여함 |
| **3** | 약간 더 중요 (Moderate importance) | 경험·판단에 의해 한쪽이 약간 선호됨 |
| **5** | 중요 (Strong importance) | 경험·판단에 의해 한쪽이 강하게 선호됨 |
| **7** | 매우 중요 (Very strong importance) | 실제로 지배적으로 중요함이 입증됨 |
| **9** | 절대적으로 중요 (Absolute importance) | 가장 높은 수준의 중요도 |
| **2, 4, 6, 8** | 중간값 (Intermediate values) | 인접 척도 사이의 판단이 필요할 때 |

> **응답 방법**: 왼쪽 기준이 더 중요하면 왼쪽 숫자에, 오른쪽 기준이 더 중요하면 오른쪽 숫자에 ✓ 표시  
> **예시**: C1이 C2보다 "중요"하다면 → C1 쪽 **5**에 ✓

---

## P1-1. 대기준 쌍대비교 / Main Criteria Pairwise Comparison

**[Q1]** C1 경제효율성 vs. C2 고객서비스

|  | ←C1이 더 중요 | | | | | | | | | C2가 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C1 경제효율성** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C2 고객서비스** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

**[Q2]** C1 경제효율성 vs. C3 Risk 저감

|  | ←C1이 더 중요 | | | | | | | | | C3가 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C1 경제효율성** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C3 Risk저감** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

**[Q3]** C2 고객서비스 vs. C3 Risk 저감

|  | ←C2가 더 중요 | | | | | | | | | C3가 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C2 고객서비스** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C3 Risk저감** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

---

## P1-2. C1 하위기준 쌍대비교 / Sub-Criteria of C1

> C1(경제효율성) 내에서 NPV와 BCR 중 배전설비 투자 결정에 더 중요한 기준은 무엇입니까?  
> **NPV**: 절대적 위험 비용 절감 규모 | **BCR**: 교체비용 대비 투자 효율성

**[Q4]** C1-1 NPV vs. C1-2 BCR

|  | ←NPV가 더 중요 | | | | | | | | | BCR이 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C1-1 NPV** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C1-2 BCR** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

---

## P1-3. C2 하위기준 쌍대비교 / Sub-Criteria of C2

> C2(고객서비스) 내에서 SAIDI 저감과 고장건수(ENF) 저감 중 더 중요한 기준은 무엇입니까?  
> **SAIDI 저감**: 고객 체감 정전시간 감소 | **ENF 저감**: 고장 발생 빈도 감소

**[Q5]** C2-1 SAIDI 저감 vs. C2-2 ENF 저감

|  | ←SAIDI가 더 중요 | | | | | | | | | ENF가 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C2-1 SAIDI 저감** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C2-2 ENF 저감** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

---

## P1-4. C3 하위기준 쌍대비교 / Sub-Criteria of C3

> C3(Risk 저감) 내에서 아래 세 하위기준을 비교합니다.  
> **C3-1 재무 Risk 저감**: 정전 재무 피해 감소  
> **C3-2 안전 Risk 저감**: 인명 안전 피해 감소  
> **C3-3 환경 Risk 저감**: 환경 오염 피해 감소

**[Q6]** C3-1 재무 Risk 저감 vs. C3-2 안전 Risk 저감

|  | ←재무가 더 중요 | | | | | | | | | 안전이 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C3-1 재무 Risk** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C3-2 안전 Risk** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

**[Q7]** C3-1 재무 Risk 저감 vs. C3-3 환경 Risk 저감

|  | ←재무가 더 중요 | | | | | | | | | 환경이 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C3-1 재무 Risk** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C3-3 환경 Risk** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

**[Q8]** C3-2 안전 Risk 저감 vs. C3-3 환경 Risk 저감

|  | ←안전이 더 중요 | | | | | | | | | 환경이 더 중요→ |  |
|--|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|--|
| **C3-2 안전 Risk** | **9** | **7** | **5** | **3** | **1** | **3** | **5** | **7** | **9** | **C3-3 환경 Risk** |
| | □ | □ | □ | □ | □ | □ | □ | □ | □ | |

---

> **일관성 참고**: 응답의 일관성 비율(CR)이 0.1 이하일 때 결과가 유효합니다.  
> CR이 초과될 경우 재응답을 요청드릴 수 있습니다.

---

---

# Part 2. 퍼지 계층분석법 (Fuzzy AHP)

## 응답 방법 / Instructions

전문가 판단에는 본질적인 **모호성과 불확실성**이 존재합니다. 아래의 **언어적 척도**를 사용하여 두 기준의 상대적 중요도를 표현하십시오.

Expert judgments inherently contain **ambiguity and uncertainty**. Please express the relative importance of each pair of criteria using the **linguistic scale** below.

### 언어적 척도 및 삼각퍼지수 / Linguistic Scale and Triangular Fuzzy Numbers (TFN)

Chang(1996) 방법 기준 / Based on Chang(1996) Extent Analysis Method

| 언어 표현 / Linguistic Term | 기호 | TFN (l, m, u) | 역수 TFN / Reciprocal |
|-----------------------------|:----:|:-------------:|:---------------------:|
| 절대적으로 중요 (Absolutely Important) | AI | (7, 9, 9) | (1/9, 1/9, 1/7) |
| 매우 중요 (Very Strongly Important) | VI | (5, 7, 9) | (1/9, 1/7, 1/5) |
| 중요 (Strongly Important) | SI | (3, 5, 7) | (1/7, 1/5, 1/3) |
| 약간 중요 (Weakly Important) | WI | (1, 3, 5) | (1/5, 1/3, 1/1) |
| 동등 (Equally Important) | EI | (1, 1, 1) | (1, 1, 1) |

> **응답 방법**: 왼쪽 기준이 더 중요하면 왼쪽 언어 표현에, 오른쪽 기준이 더 중요하면 오른쪽 언어 표현에 ✓ 표시  
> **예시**: C1이 C2보다 "중요(SI)"하다면 → C1 쪽 SI에 ✓

---

## P2-1. 대기준 쌍대비교 (Fuzzy) / Main Criteria

**[Q9]** C1 경제효율성 vs. C2 고객서비스

| **C1 경제효율성** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C2 고객서비스** |
|:----------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:----------------:|
| ←C1 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | C2 중요→ |

**[Q10]** C1 경제효율성 vs. C3 Risk 저감

| **C1 경제효율성** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C3 Risk저감** |
|:----------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:---------------:|
| ←C1 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | C3 중요→ |

**[Q11]** C2 고객서비스 vs. C3 Risk 저감

| **C2 고객서비스** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C3 Risk저감** |
|:----------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:---------------:|
| ←C2 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | C3 중요→ |

---

## P2-2. C1 하위기준 쌍대비교 (Fuzzy)

**[Q12]** C1-1 NPV vs. C1-2 BCR

| **C1-1 NPV** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C1-2 BCR** |
|:-----------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:-----------:|
| ←NPV 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | BCR 중요→ |

---

## P2-3. C2 하위기준 쌍대비교 (Fuzzy)

**[Q13]** C2-1 SAIDI 저감 vs. C2-2 ENF 저감

| **C2-1 SAIDI** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C2-2 ENF** |
|:--------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:-----------:|
| ←SAIDI 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | ENF 중요→ |

---

## P2-4. C3 하위기준 쌍대비교 (Fuzzy)

**[Q14]** C3-1 재무 Risk vs. C3-2 안전 Risk

| **C3-1 재무** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C3-2 안전** |
|:------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:------------:|
| ←재무 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | 안전 중요→ |

**[Q15]** C3-1 재무 Risk vs. C3-3 환경 Risk

| **C3-1 재무** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C3-3 환경** |
|:------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:------------:|
| ←재무 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | 환경 중요→ |

**[Q16]** C3-2 안전 Risk vs. C3-3 환경 Risk

| **C3-2 안전** | AI | VI | SI | WI | EI | WI | SI | VI | AI | **C3-3 환경** |
|:------------:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:------------:|
| ←안전 중요 | □ | □ | □ | □ | □ | □ | □ | □ | □ | 환경 중요→ |

---

---

# Part 3. 최선-최악법 (Best-Worst Method, BWM)

## 응답 방법 / Instructions (Rezaei, 2015)

BWM은 AHP 대비 **쌍대비교 수를 대폭 축소**하면서 높은 일관성을 보장하는 방법입니다 (Rezaei, 2015, Omega).

각 계층별로 아래 **3단계**로 응답합니다.

- **Step 1**: 기준 목록 중 **가장 중요한 기준(Best)**과 **가장 덜 중요한 기준(Worst)**을 선택
- **Step 2**: Best 기준과 나머지 기준들을 1~9 척도로 비교 **(Best-to-Others 벡터, A_B)**
- **Step 3**: 나머지 기준들과 Worst 기준을 1~9 척도로 비교 **(Others-to-Worst 벡터, A_W)**

> **척도**: 1 = 동등하게 중요, 9 = 절대적으로 중요 (Best 또는 해당 기준이 더 중요할수록 숫자 큼)  
> **주의**: Best 기준 자신의 A_B 값 = 1, Worst 기준 자신의 A_W 값 = 1

---

## P3-1. 대기준 BWM / Main Criteria (C1, C2, C3)

**[Step 1]** Best 및 Worst 기준 선택:

| | C1 경제효율성 | C2 고객서비스 | C3 Risk저감 |
|---|:---:|:---:|:---:|
| **Best** (가장 중요한 기준) | □ | □ | □ |
| **Worst** (가장 덜 중요한 기준) | □ | □ | □ |

**[Step 2]** Best-to-Others 벡터 (A_B): Best 기준 대비 각 기준의 상대적 중요도

> 예시: Best = C1이면 → C1 자신은 **1**, C1보다 덜 중요한 C2는 **3~9** 입력

| Best 기준 대비 / Compared to Best | C1 경제효율성 | C2 고객서비스 | C3 Risk저감 |
|----------------------------------|:-----------:|:-----------:|:-----------:|
| **중요도 (1~9)** | | | |

**[Step 3]** Others-to-Worst 벡터 (A_W): 각 기준 대비 Worst 기준의 상대적 중요도

> 예시: Worst = C3이면 → C3 자신은 **1**, C3보다 더 중요한 C1은 **3~9** 입력

| 각 기준 대비 Worst / Compared to Worst | C1 경제효율성 | C2 고객서비스 | C3 Risk저감 |
|---------------------------------------|:-----------:|:-----------:|:-----------:|
| **중요도 (1~9)** | | | |

---

## P3-2. C1 하위기준 BWM / Sub-Criteria of C1 (NPV, BCR)

**[Step 1]** Best / Worst 선택:

| | C1-1 NPV | C1-2 BCR |
|---|:---:|:---:|
| **Best** | □ | □ |
| **Worst** | □ | □ |

**[Step 2]** Best-to-Others 벡터 (A_B):

| Best 기준 대비 | C1-1 NPV | C1-2 BCR |
|--------------|:--------:|:--------:|
| **중요도 (1~9)** | | |

**[Step 3]** Others-to-Worst 벡터 (A_W):

| 각 기준 대비 Worst | C1-1 NPV | C1-2 BCR |
|-----------------|:--------:|:--------:|
| **중요도 (1~9)** | | |

---

## P3-3. C2 하위기준 BWM / Sub-Criteria of C2 (SAIDI, ENF)

**[Step 1]** Best / Worst 선택:

| | C2-1 SAIDI 저감 | C2-2 ENF 저감 |
|---|:---:|:---:|
| **Best** | □ | □ |
| **Worst** | □ | □ |

**[Step 2]** Best-to-Others 벡터 (A_B):

| Best 기준 대비 | C2-1 SAIDI 저감 | C2-2 ENF 저감 |
|--------------|:---------------:|:-------------:|
| **중요도 (1~9)** | | |

**[Step 3]** Others-to-Worst 벡터 (A_W):

| 각 기준 대비 Worst | C2-1 SAIDI 저감 | C2-2 ENF 저감 |
|-----------------|:---------------:|:-------------:|
| **중요도 (1~9)** | | |

---

## P3-4. C3 하위기준 BWM / Sub-Criteria of C3 (재무, 안전, 환경 Risk)

**[Step 1]** Best / Worst 선택:

| | C3-1 재무 Risk 저감 | C3-2 안전 Risk 저감 | C3-3 환경 Risk 저감 |
|---|:---:|:---:|:---:|
| **Best** | □ | □ | □ |
| **Worst** | □ | □ | □ |

**[Step 2]** Best-to-Others 벡터 (A_B):

| Best 기준 대비 | C3-1 재무 | C3-2 안전 | C3-3 환경 |
|--------------|:--------:|:--------:|:--------:|
| **중요도 (1~9)** | | | |

**[Step 3]** Others-to-Worst 벡터 (A_W):

| 각 기준 대비 Worst | C3-1 재무 | C3-2 안전 | C3-3 환경 |
|-----------------|:--------:|:--------:|:--------:|
| **중요도 (1~9)** | | | |

---

---

## 추가 의견 / Additional Comments

배전설비 투자 우선순위 결정 시 본 설문에서 다루지 않은 중요 기준 또는 의견을 기술하여 주십시오.

Please describe any important criteria or opinions not covered in this questionnaire.

> (자유 기재 / Free response)

---

**소중한 응답에 감사드립니다. / Thank you for your valuable response.**

문의: shfmql12@mokpo.ac.kr

---

## 참고문헌 / References

- Saaty, T. L. (1980). *The Analytic Hierarchy Process*. McGraw-Hill.
- Chang, D. Y. (1996). Applications of the extent analysis method on fuzzy AHP. *European Journal of Operational Research*, 95(3), 649–655.
- Rezaei, J. (2015). Best-worst multi-criteria decision-making method. *Omega*, 53, 49–57.
