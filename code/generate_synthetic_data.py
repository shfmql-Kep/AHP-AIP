"""
CNAIM v2.1 기반 합성 데이터셋 생성기
배전설비 자산투자계획(AIP) 박사논문 연구용

5개 자산군 × 500기 합성 데이터
- CNAIM Table 20: Normal Expected Life
- CNAIM Table 21: PoF Curve Parameters (K, C-Value)
- CNAIM EQ.3~12: Health Score → PoF 계산
- CNAIM Section 7: CoF 4항목 구조

[자산군 → CNAIM 매핑]
  주상변압기  : HV Transformer (GM)                   K=0.0078%, NEL=60yr
  지상변압기  : HV Transformer (GM) / 더 큰 용량       K=0.0078%, NEL=60yr
  가공개폐기  : HV Switchgear (GM) - Distribution      K=0.0067%, NEL=55yr
  지중개폐기  : HV Switchgear (GM) - Primary           K=0.0052%, NEL=55yr
  배전선로    : Poles / OHL Conductor                  K=0.0285%, NEL=55yr
"""

import numpy as np
import pandas as pd
import os

np.random.seed(42)

# ═══════════════════════════════════════════════════════════════════
# 1. CNAIM 캘리브레이션 파라미터
# ═══════════════════════════════════════════════════════════════════

# Table 21: PoF Curve Parameters
# C-Value = 1.087 (전 자산군 공통), Health Score Limit = 4
ASSET_POF_PARAMS = {
    '주상변압기': {'K': 0.0078 / 100, 'C': 1.087, 'HSL': 4, 'NEL': 60},
    '지상변압기': {'K': 0.0078 / 100, 'C': 1.087, 'HSL': 4, 'NEL': 60},
    '가공개폐기': {'K': 0.0067 / 100, 'C': 1.087, 'HSL': 4, 'NEL': 55},
    '지중개폐기': {'K': 0.0052 / 100, 'C': 1.087, 'HSL': 4, 'NEL': 55},
    '배전선로':   {'K': 0.0285 / 100, 'C': 1.087, 'HSL': 4, 'NEL': 55},
}

# CoF 기준값 (천원 단위) - CNAIM Table 16 기반 국내 환경 적용
# Financial(F), Safety(S), Environmental(E), Network Performance(NP)
# 참조: 6.6/11kV Transformer Total=£22,271 → ~35,600천원
#       6.6/11kV Primary CB Total=£73,165  → ~117,000천원
#       6.6/11kV Secondary CB Total=£24,848 → ~39,700천원
ASSET_COF_REF = {
    '주상변압기': {'F': 14_000, 'S':  7_000, 'E':  5_500, 'NP':  9_000},  # 합계 ~35,500
    '지상변압기': {'F': 22_000, 'S':  7_000, 'E':  6_000, 'NP': 14_000},  # 합계 ~49,000
    '가공개폐기': {'F': 11_000, 'S': 16_000, 'E':  2_000, 'NP': 22_000},  # 합계 ~51,000
    '지중개폐기': {'F': 13_000, 'S': 38_000, 'E':  2_500, 'NP': 64_000},  # 합계 ~117,500
    '배전선로':   {'F':  7_000, 'S':  2_000, 'E':  1_500, 'NP':  4_500},  # 합계 ~15,000
}

# ILP 입력 파라미터
REPLACEMENT_COST_10K_KRW = {  # 단위: 만원 (10,000 KRW)
    '주상변압기': 250,   # 250만원 (50kVA 기준)
    '지상변압기': 800,   # 800만원 (300kVA 기준)
    '가공개폐기': 350,   # 350만원
    '지중개폐기': 600,   # 600만원 (RMU 기준)
    '배전선로':   450,   # 450만원 (구간당 약 500m)
}

MAINTENANCE_HOURS = {  # 단위: 시간
    '주상변압기': 8,
    '지상변압기': 20,
    '가공개폐기': 6,
    '지중개폐기': 14,
    '배전선로':   12,
}

LABOR_DAYS = {  # 단위: 인일
    '주상변압기': 2,
    '지상변압기': 5,
    '가공개폐기': 2,
    '지중개폐기': 4,
    '배전선로':   3,
}

ASSET_COUNTS = {
    '주상변압기': 150,
    '지상변압기':  50,
    '가공개폐기': 100,
    '지중개폐기': 100,
    '배전선로':   100,
}


# ═══════════════════════════════════════════════════════════════════
# 2. CNAIM 수식 구현
# ═══════════════════════════════════════════════════════════════════

def compute_beta1(NEL: float, duty_factor: float = 1.0, location_factor: float = 1.0) -> tuple:
    """
    β1 (Initial Ageing Rate) - CNAIM EQ.5
    β1 = ln(H_expected_life / H_new) / Expected Life
    """
    H_new = 0.5
    H_expected_life = 5.5
    expected_life = NEL / (duty_factor * location_factor)
    expected_life = max(expected_life, 1.0)
    beta1 = np.log(H_expected_life / H_new) / expected_life
    return beta1, expected_life


def compute_initial_health_score(age: float, beta1: float) -> float:
    """
    Initial Health Score - CNAIM EQ.6
    IHS = H_new × exp(β1 × age), cap at 5.5
    """
    H_new = 0.5
    hs = H_new * np.exp(beta1 * age)
    return min(hs, 5.5)


def mmi_combine(factors: list, divider1: float = 1.5, divider2: float = 1.5,
                max_combined: int = 2) -> float:
    """
    MMI (Maximum and Multiple Increment) 기법 - CNAIM Section 6.7.2
    여러 Condition Factor를 하나의 Combined Factor로 결합
    """
    if any(f > 1 for f in factors):
        var1 = max(factors)
        above_one = sorted([f - 1 for f in factors if f > 1 and f != var1], reverse=True)
        var2 = sum(above_one[:max_combined - 1])
        return var1 + (var2 / divider1)
    else:
        var1 = min(factors)
        others = [f for f in factors if f != var1]
        var2 = min(others) if others else 1.0
        return var1 + ((var2 - 1) / divider2)


def compute_current_health_score(initial_hs: float, hs_factor: float,
                                  hs_cap: float = 10.0, hs_collar: float = 0.5) -> float:
    """
    Current Health Score - CNAIM EQ.7-9
    CHS = IHS × HS_Factor, 적용 Cap/Collar
    """
    chs = initial_hs * hs_factor
    chs = min(chs, hs_cap)
    chs = max(chs, hs_collar)
    return min(chs, 10.0)


def compute_pof(H: float, K: float, C: float, HSL: int = 4) -> float:
    """
    PoF per annum - CNAIM EQ.3 (Taylor 급수 3차)
    PoF = K × [1 + CH + (CH)²/2! + (CH)³/3!]
    H = max(Health Score, HSL)
    """
    h = max(H, HSL)
    pof = K * (1.0 + (C * h) + (C * h) ** 2 / 2.0 + (C * h) ** 3 / 6.0)
    return pof


def compute_cof_total(asset_type: str, customer_factor: float = 1.0,
                      loc_env_factor: float = 1.0, size_env_factor: float = 1.0) -> dict:
    """
    CoF 4항목 계산 (천원) - CNAIM Section 7
    Financial, Safety, Environmental, Network Performance
    """
    ref = ASSET_COF_REF[asset_type]
    F  = ref['F']                                      # EQ.28: 교체/수리비
    S  = ref['S']                                      # EQ.31: 안전사고 비용
    E  = ref['E'] * loc_env_factor * size_env_factor   # EQ.33: 환경 비용
    NP = ref['NP'] * customer_factor                   # EQ.37: 계통성능 비용
    return {'F': F, 'S': S, 'E': E, 'NP': NP, 'total': F + S + E + NP}


# ═══════════════════════════════════════════════════════════════════
# 3. 합성 데이터 생성
# ═══════════════════════════════════════════════════════════════════

# Observed Condition 상태 매핑 (CNAIM Table 35~, Section 6.9)
OBS_CONDITIONS = {
    'no_deterioration':  {'factor': 0.9, 'label': '이상 없음'},
    'superficial':       {'factor': 1.0, 'label': '경미한 열화'},
    'some':              {'factor': 1.2, 'label': '일부 열화'},
    'substantial':       {'factor': 1.4, 'label': '심각한 열화'},
}

# Measured Condition 상태 매핑 (CNAIM Table 66~, Section 6.10)
MEAS_CONDITIONS = {
    'good':     {'factor': 0.9, 'label': '양호'},
    'normal':   {'factor': 1.0, 'label': '보통'},
    'moderate': {'factor': 1.2, 'label': '주의'},
    'poor':     {'factor': 1.5, 'label': '불량'},
}

OBS_KEYS   = list(OBS_CONDITIONS.keys())
OBS_PROBS  = [0.20, 0.40, 0.28, 0.12]   # 현장 조사 분포 가정
MEAS_KEYS  = list(MEAS_CONDITIONS.keys())
MEAS_PROBS = [0.20, 0.45, 0.25, 0.10]   # 측정 조사 분포 가정


def generate_assets() -> pd.DataFrame:
    records = []
    asset_id = 1

    for asset_type, count in ASSET_COUNTS.items():
        p = ASSET_POF_PARAMS[asset_type]
        K, C, HSL, NEL = p['K'], p['C'], p['HSL'], p['NEL']

        for _ in range(count):
            # ── 나이 (정규분포, NEL 기준)
            age = int(np.clip(
                np.random.normal(loc=NEL * 0.48, scale=NEL * 0.22),
                1, NEL + 15
            ))

            # ── Location Factor (Table 22-24: 해안거리/고도/부식 통합)
            location_factor = float(np.random.choice(
                [0.90, 1.00, 1.05, 1.10, 1.35],
                p=[0.08, 0.52, 0.20, 0.15, 0.05]
            ))

            # ── Duty Factor (Table 33: 변압기, Table 32: 개폐기)
            if asset_type in ['주상변압기', '지상변압기']:
                util = np.random.choice([40, 60, 85, 115], p=[0.20, 0.40, 0.30, 0.10])
                if util <= 50:    df_val = 0.90
                elif util <= 70:  df_val = 0.95
                elif util <= 100: df_val = 1.00
                else:             df_val = 1.40
            elif asset_type == '가공개폐기':
                op = np.random.choice(['normal', 'high'], p=[0.82, 0.18])
                df_val = 1.20 if op == 'high' else 1.00
            else:
                df_val = 1.00

            # ── β1 / Expected Life (EQ.4-5)
            beta1, exp_life = compute_beta1(NEL, df_val, location_factor)

            # ── Initial Health Score (EQ.6)
            init_hs = compute_initial_health_score(age, beta1)

            # ── Condition Modifier (EQ.7-9, MMI)
            obs_key  = np.random.choice(OBS_KEYS,  p=OBS_PROBS)
            meas_key = np.random.choice(MEAS_KEYS, p=MEAS_PROBS)
            obs_f    = OBS_CONDITIONS[obs_key]['factor']
            meas_f   = MEAS_CONDITIONS[meas_key]['factor']

            hs_factor = mmi_combine([obs_f, meas_f])
            curr_hs   = compute_current_health_score(init_hs, hs_factor)

            # ── PoF (EQ.3)
            pof = compute_pof(curr_hs, K, C, HSL)

            # ── CoF 파라미터
            num_customers = int(np.clip(np.random.lognormal(np.log(45), 0.65), 1, 500))
            ref_customers = {'주상변압기': 40, '지상변압기': 80,
                             '가공개폐기': 60, '지중개폐기': 120, '배전선로': 30}
            customer_factor = min(num_customers / ref_customers[asset_type], 5.0)

            near_water      = np.random.choice([True, False], p=[0.12, 0.88])
            loc_env_factor  = 1.30 if near_water else 1.00
            size_cat        = np.random.choice(['소', '중', '대'], p=[0.30, 0.50, 0.20])
            size_env_factor = {'소': 0.80, '중': 1.00, '대': 1.30}[size_cat]

            cof = compute_cof_total(asset_type, customer_factor, loc_env_factor, size_env_factor)

            # ── Risk = PoF × CoF
            risk = pof * cof['total']

            # ── 의무교체 여부 (나이 30년+ & 심각한 관측 상태)
            mandatory = 1 if (age >= 30 and obs_key == 'substantial') else 0

            # ── AHP 4개 평가기준 (C1~C4), 0~1 정규화
            # C1: 기술적 위험도 (PoF 기반)
            c1 = min(pof / (K * 50), 1.0)  # 기준: K의 50배 → max

            # C2: 공급 신뢰도 (고객 수 영향)
            c2 = min(customer_factor / 4.0, 1.0)

            # C3: 설비 중요도 (NP 비용 기반)
            max_np = ASSET_COF_REF['지중개폐기']['NP'] * 5.0
            c3 = min(cof['NP'] / max_np, 1.0)

            # C4: 경제성 (위험도/투자비용 비율)
            cost_k = REPLACEMENT_COST_10K_KRW[asset_type]
            c4 = min(risk / (cost_k * 200), 1.0)

            # ── HI 밴드 (CNAIM Table 5-6)
            if curr_hs < 3.0:
                hi_band = 'HI1'
            elif curr_hs < 5.0:
                hi_band = 'HI2'
            elif curr_hs < 6.5:
                hi_band = 'HI3'
            elif curr_hs < 8.5:
                hi_band = 'HI4'
            else:
                hi_band = 'HI5'

            records.append({
                'asset_id':                f'A{asset_id:04d}',
                'asset_type':              asset_type,
                'age_years':               age,
                'normal_expected_life':    NEL,
                'expected_life':           round(exp_life, 1),
                'location_factor':         location_factor,
                'duty_factor':             df_val,
                'obs_condition':           obs_key,
                'meas_condition':          meas_key,
                'hs_factor':               round(hs_factor, 4),
                'initial_health_score':    round(init_hs, 4),
                'current_health_score':    round(curr_hs, 4),
                'hi_band':                 hi_band,
                'pof_per_annum':           round(pof, 6),
                'cof_financial_k_krw':     round(cof['F'], 0),
                'cof_safety_k_krw':        round(cof['S'], 0),
                'cof_environmental_k_krw': round(cof['E'], 0),
                'cof_network_k_krw':       round(cof['NP'], 0),
                'cof_total_k_krw':         round(cof['total'], 0),
                'risk_score':              round(risk, 2),
                'num_customers':           num_customers,
                'near_water':              int(near_water),
                'asset_size':              size_cat,
                'mandatory_replace':       mandatory,
                'replace_cost_10k_krw':    REPLACEMENT_COST_10K_KRW[asset_type],
                'maintenance_hours':       MAINTENANCE_HOURS[asset_type],
                'labor_days':              LABOR_DAYS[asset_type],
                'C1_tech_risk':            round(c1, 4),
                'C2_supply_reliability':   round(c2, 4),
                'C3_importance':           round(c3, 4),
                'C4_economics':            round(c4, 4),
            })
            asset_id += 1

    return pd.DataFrame(records)


# ═══════════════════════════════════════════════════════════════════
# 4. 실행 및 저장
# ═══════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    print("=" * 60)
    print("CNAIM 기반 합성 데이터셋 생성")
    print("=" * 60)

    df = generate_assets()

    out_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'synthetic_assets_500.csv')
    out_path = os.path.normpath(out_path)
    df.to_csv(out_path, index=False, encoding='utf-8-sig')
    print(f"\n저장 완료 → {out_path}")
    print(f"총 자산 수: {len(df)}기\n")

    print("─── 자산군별 요약 ───")
    summary = df.groupby('asset_type').agg(
        수량=('asset_id', 'count'),
        평균나이=('age_years', 'mean'),
        평균HS=('current_health_score', 'mean'),
        평균PoF=('pof_per_annum', 'mean'),
        평균CoF=('cof_total_k_krw', 'mean'),
        평균Risk=('risk_score', 'mean'),
        의무교체=('mandatory_replace', 'sum'),
    ).round(4)
    print(summary.to_string())

    print("\n─── HI 밴드 분포 ───")
    print(df['hi_band'].value_counts().sort_index().to_string())

    print("\n─── 전체 기초통계 ───")
    key_cols = ['age_years', 'current_health_score', 'pof_per_annum',
                'cof_total_k_krw', 'risk_score']
    print(df[key_cols].describe().round(4).to_string())

    total_budget = 300_000   # 30억원 = 300,000만원
    total_cost   = df['replace_cost_10k_krw'].sum()
    mand_df      = df[df['mandatory_replace'] == 1]
    print(f"\n─── ILP 제약 요약 ───")
    print(f"  예산 상한 (B):          {total_budget:,} 만원 (30억원)")
    print(f"  전체 교체 시 비용:       {total_cost:,} 만원")
    print(f"  의무교체 수량 |M|:       {len(mand_df)}기")
    print(f"  의무교체 비용:           {mand_df['replace_cost_10k_krw'].sum():,} 만원")
    print(f"  총 공사시간 (전체):      {df['maintenance_hours'].sum():,} 시간")
    print(f"  총 투입인력 (전체):      {df['labor_days'].sum():,} 인일")
    print("=" * 60)
