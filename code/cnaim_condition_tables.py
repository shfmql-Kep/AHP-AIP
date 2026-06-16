"""
CNAIM v2.1 Appendix B 컨디션 입력 보정표 (Observed / Measured Condition Inputs)
===========================================================================
출처: CNAIM.pdf (Ofgem, April 2021)
  - B.5  관측 컨디션 입력 (Observed Condition Inputs)   p.115~
  - B.6  측정 컨디션 입력 (Measured Condition Inputs)    p.148~
  - B.7  오일 시험 보정 (Oil Test Modifier)              p.163, EQ.22
  - B.8  유중가스(DGA) 시험 보정                          p.164, EQ.23~25
  - B.9  FFA 시험 보정                                    p.165, EQ.26
  - Section 6.7.2 MMI(Maximum/Multiple Increment) 결합 알고리즘
  - Table 9(일반 2입력), Table 10(변압기 5입력, Max=4), Table 13/15(자산군별 결합 파라미터)

이 모듈은 aip_01_generate_input.py(입력 데이터 생성)과
aip_02_run_analysis.py(위험도 분석) 양쪽에서 공통으로 import하는
"단일 진실 공급원(single source of truth)" 캘리브레이션 테이블이다.

각 상태(state) 튜플 구조: (state_key, Factor, Cap, Collar, severity_rank)
  - Factor/Cap/Collar : CNAIM 원문 그대로의 값
  - severity_rank     : 0(정상)~1(최악) 사이의 보조값. CNAIM 공식 수치가 아니라,
                         입력 데이터 생성 시 자산별 잠재 중증도(z)와 상태를 매칭하기
                         위해 이 프로젝트에서 정의한 보조 스케일이다.
"""

import numpy as np

# ==================================================================
# 0. 자산유형(한국어) → 컨디션 테이블 키 매핑
# ==================================================================
ASSET_KEY_MAP = {
    "주상변압기": "HV_TR", "지상변압기": "HV_TR", "지중변압기": "HV_TR",
    "가공개폐기": "SW_DIST", "지중개폐기_RMU": "SW_DIST",
    "특고압차단기": "SW_PRIM",
    "지중케이블": "CABLE",
    "목주": "POLE", "콘크리트주": "POLE", "철주": "POLE",
    "LV배전반_UGB": "LV_UGB",
    "가공배전선로": "OHL_COND",
}

# ==================================================================
# 1. 자산유형별 관측(Observed)/측정(Measured) 컨디션 입력 테이블
# ==================================================================
CATEGORICAL_INPUTS = {
    # -- HV Transformer (GM): 주상/지상/지중변압기 -------------------
    "HV_TR": {
        "observed": {
            "ext_condition": [   # Table 81: 외관상태
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("slight",           1.1, 10.0, 0.5, 0.35),
                ("some",             1.25, 10.0, 3.0, 0.60),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "cable_box": [        # Table 82: 케이블박스 상태
                ("no_deterioration", 1.0, 10.0, 0.5, 0.00),
                ("some",             1.1, 10.0, 0.5, 0.50),
                ("substantial",      1.3, 10.0, 0.5, 0.90),
            ],
        },
        "measured": {
            "partial_discharge": [   # Table 171
                ("low",               1.0, 10.0, 0.5, 0.00),
                ("medium",            1.1, 10.0, 0.5, 0.35),
                ("high_unconfirmed",  1.3, 10.0, 5.5, 0.65),
                ("high_confirmed",    1.5, 10.0, 8.0, 0.90),
            ],
            "temp_reading": [         # Table 172
                ("normal",            1.0, 10.0, 0.5, 0.00),
                ("moderately_high",   1.2, 10.0, 0.5, 0.50),
                ("very_high",         1.4, 10.0, 5.5, 0.90),
            ],
        },
    },

    # -- HV Switchgear (GM) Distribution: 가공개폐기/지중개폐기_RMU --
    "SW_DIST": {
        "observed": {
            "ext_condition": [        # Table 54
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.2, 10.0, 3.0, 0.55),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "oil_gas_leak": [          # Table 55
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.1, 10.0, 3.0, 0.50),
                ("substantial",      1.3, 10.0, 8.0, 0.90),
            ],
            "thermographic": [         # Table 56
                ("ambient_or_below",        0.9, 10.0, 0.5, 0.00),
                ("above_ambient",           1.0, 10.0, 0.5, 0.30),
                ("substantially_above",     1.1, 10.0, 0.5, 0.80),
            ],
            "internal_condition": [    # Table 57
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.2, 10.0, 3.0, 0.55),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "indoor_env": [             # Table 58
                ("better_than_expected", 0.9, 10.0, 0.5, 0.00),
                ("as_expected",          1.0, 10.0, 0.5, 0.25),
                ("deteriorated",         1.3, 10.0, 0.5, 0.60),
                ("severely_deteriorated",1.5, 10.0, 0.5, 0.90),
            ],
            "cable_box": [              # Table 59
                ("no_deterioration", 1.0, 10.0, 0.5, 0.00),
                ("some",             1.1, 10.0, 0.5, 0.50),
                ("substantial",      1.3, 10.0, 0.5, 0.90),
            ],
        },
        "measured": {
            "partial_discharge": [      # Table 148
                ("low",               1.0, 10.0, 0.5, 0.00),
                ("medium",            1.1, 10.0, 0.5, 0.35),
                ("high_unconfirmed",  1.3, 10.0, 5.5, 0.65),
                ("high_confirmed",    1.5, 10.0, 8.0, 0.90),
            ],
            "ductor_test": [             # Table 149
                ("as_new",        1.0, 10.0, 0.5, 0.00),
                ("up_to_10pct",   1.1, 10.0, 0.5, 0.50),
                ("over_10pct",    1.3, 10.0, 0.5, 0.90),
            ],
            "oil_tests": [               # Table 150
                ("as_new",        1.0, 10.0, 0.5, 0.00),
                ("up_to_10pct",   1.1, 10.0, 0.5, 0.50),
                ("over_10pct",    1.3, 10.0, 0.5, 0.90),
            ],
            "temp_reading": [             # Table 151
                ("ambient_or_below",     0.9, 10.0, 0.5, 0.00),
                ("above_ambient",        1.0, 10.0, 0.5, 0.30),
                ("substantially_above",  1.1, 10.0, 0.5, 0.80),
            ],
            "trip_test": [                # Table 152
                ("pass", 1.0, 10.0, 0.5, 0.00),
                ("fail", 1.4, 10.0, 0.5, 0.90),
            ],
        },
    },

    # -- HV Switchgear (GM) Primary: 특고압차단기 --------------------
    "SW_PRIM": {
        "observed": {
            "ext_condition": [
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.2, 10.0, 3.0, 0.55),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "oil_gas_leak": [
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.1, 10.0, 3.0, 0.50),
                ("substantial",      1.3, 10.0, 8.0, 0.90),
            ],
            "thermographic": [
                ("ambient_or_below",        0.9, 10.0, 0.5, 0.00),
                ("above_ambient",           1.0, 10.0, 0.5, 0.30),
                ("substantially_above",     1.1, 10.0, 0.5, 0.80),
            ],
            "internal_condition": [
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.15),
                ("some",             1.2, 10.0, 3.0, 0.55),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "indoor_env": [
                ("better_than_expected", 0.9, 10.0, 0.5, 0.00),
                ("as_expected",          1.0, 10.0, 0.5, 0.25),
                ("deteriorated",         1.3, 10.0, 0.5, 0.60),
                ("severely_deteriorated",1.5, 10.0, 0.5, 0.90),
            ],
            "cable_box": [
                ("no_deterioration", 1.0, 10.0, 0.5, 0.00),
                ("some",             1.1, 10.0, 0.5, 0.50),
                ("substantial",      1.3, 10.0, 0.5, 0.90),
            ],
        },
        "measured": {
            "partial_discharge": [
                ("low",               1.0, 10.0, 0.5, 0.00),
                ("medium",            1.1, 10.0, 0.5, 0.35),
                ("high_unconfirmed",  1.3, 10.0, 5.5, 0.65),
                ("high_confirmed",    1.5, 10.0, 8.0, 0.90),
            ],
            "ductor_test": [
                ("as_new",        1.0, 10.0, 0.5, 0.00),
                ("up_to_10pct",   1.1, 10.0, 0.5, 0.50),
                ("over_10pct",    1.3, 10.0, 0.5, 0.90),
            ],
            "ir_test": [               # Table 155 (Primary 전용 추가 입력)
                ("as_new",        1.0, 10.0, 0.5, 0.00),
                ("up_to_10pct",   1.1, 10.0, 0.5, 0.50),
                ("over_10pct",    1.3, 10.0, 0.5, 0.90),
            ],
            "oil_tests": [
                ("as_new",        1.0, 10.0, 0.5, 0.00),
                ("up_to_10pct",   1.1, 10.0, 0.5, 0.50),
                ("over_10pct",    1.3, 10.0, 0.5, 0.90),
            ],
            "temp_reading": [
                ("ambient_or_below",     0.9, 10.0, 0.5, 0.00),
                ("above_ambient",        1.0, 10.0, 0.5, 0.30),
                ("substantially_above",  1.1, 10.0, 0.5, 0.80),
            ],
            "trip_test": [
                ("pass", 1.0, 10.0, 0.5, 0.00),
                ("fail", 1.4, 10.0, 0.5, 0.90),
            ],
        },
    },

    # -- Non-Pressurised Cable: 지중케이블 (관측 입력 없음) ----------
    "CABLE": {
        "observed": {},
        "measured": {
            "sheath_test": [          # Table 179
                ("pass",         1.0, 10.0, 0.5, 0.00),
                ("failed_minor", 1.3, 10.0, 0.5, 0.55),
                ("failed_major", 1.6, 10.0, 5.5, 0.90),
            ],
            "partial_discharge": [    # Table 180
                ("low",    1.0, 10.0, 0.5, 0.00),
                ("medium", 1.15, 10.0, 0.5, 0.45),
                ("high",   1.5, 10.0, 5.5, 0.90),
            ],
            "fault_history": [        # Table 181 (faults/km/year)
                ("none",               1.0, 5.4, 0.5, 0.00),
                ("lt_0_01_per_km",     1.3, 10.0, 0.5, 0.40),
                ("between_0_01_0_1",   1.6, 10.0, 5.5, 0.70),
                ("ge_0_1_per_km",      1.8, 10.0, 8.0, 0.90),
            ],
        },
    },

    # -- Poles (목주/콘크리트주/철주 동일 보정값) --------------------
    "POLE": {
        "observed": {
            "visual_condition": [      # Table 108/112/116
                ("acceptable",                1.0, 10.0, 0.5, 0.00),
                ("some_deterioration",        1.3, 10.0, 4.0, 0.50),
                ("substantial_deterioration", 1.8, 10.0, 8.0, 0.90),
            ],
            "pole_top_rot": [
                ("no",  1.0, 10.0, 0.5, 0.00),
                ("yes", 1.3, 10.0, 0.5, 0.70),
            ],
            "pole_leaning": [
                ("no",  1.0, 10.0, 0.5, 0.00),
                ("yes", 1.2, 10.0, 0.5, 0.60),
            ],
            "bird_animal_damage": [
                ("no",  1.0, 10.0, 0.5, 0.00),
                ("yes", 1.3, 10.0, 0.5, 0.60),
            ],
        },
        "measured": {
            "pole_decay": [             # Table 192/193/194
                ("none",                  0.8, 5.4, 0.5, 0.00),
                ("no_significant_decay",  1.0, 6.4, 0.5, 0.20),
                ("high",                  1.4, 10.0, 5.5, 0.60),
                ("very_high",             1.8, 10.0, 8.0, 0.90),
            ],
        },
    },

    # -- LV Underground General Bond: LV배전반_UGB --------------------
    "LV_UGB": {
        "observed": {
            "steel_cover_pit": [        # Table 35
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.0, 10.0, 0.5, 0.20),
                ("some",             1.2, 10.0, 0.5, 0.55),
                ("substantial",      1.4, 10.0, 0.5, 0.90),
            ],
            "water_moisture": [          # Table 36
                ("none",             1.0, 10.0, 0.5, 0.00),
                ("present_in_pit",   1.1, 10.0, 0.5, 0.50),
                ("present_in_bell",  1.3, 10.0, 0.5, 0.90),
            ],
            "bell_condition": [          # Table 37
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("some",             1.2, 10.0, 0.5, 0.50),
                ("substantial",      1.4, 10.0, 0.5, 0.90),
            ],
            "insulation_condition": [    # Table 38
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("some",             1.0, 10.0, 0.5, 0.40),
                ("substantial",      1.3, 10.0, 8.0, 0.90),
            ],
            "signs_of_heating": [        # Table 39
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("some",             1.0, 10.0, 0.5, 0.40),
                ("substantial",      1.5, 10.0, 5.5, 0.90),
            ],
            "phase_barriers": [           # Table 40
                ("present", 1.0, 10.0, 0.5, 0.00),
                ("missing", 1.3, 10.0, 0.5, 0.80),
            ],
        },
        "measured": {
            "operational_adequacy": [     # Table 144
                ("operable",   1.0, 10.0, 0.5, 0.00),
                ("inoperable", 1.5, 10.0, 8.0, 0.90),
            ],
        },
    },

    # -- Tower Line Conductor (EHV 표 재사용): 가공배전선로 ----------
    "OHL_COND": {
        "observed": {
            "visual_condition": [        # Table 140
                ("no_deterioration", 0.9, 10.0, 0.5, 0.00),
                ("superficial",      1.1, 10.0, 0.5, 0.30),
                ("some",             1.3, 10.0, 4.0, 0.60),
                ("substantial",      1.4, 10.0, 8.0, 0.90),
            ],
            "midspan_joints": [           # Table 141
                ("count_0",   1.0, 10.0, 0.5, 0.00),
                ("count_1",   1.05, 10.0, 0.5, 0.30),
                ("count_2",   1.1, 10.0, 0.5, 0.60),
                ("count_gt2", 1.2, 10.0, 5.5, 0.90),
            ],
        },
        "measured": {
            "conductor_sampling": [       # Table 199
                ("low",            1.0, 5.4, 0.5, 0.00),
                ("medium_normal",  1.1, 10.0, 3.0, 0.45),
                ("high",           1.4, 10.0, 8.0, 0.90),
            ],
            "corrosion_monitoring": [     # Table 200
                ("low",            1.0, 5.4, 0.5, 0.00),
                ("medium_normal",  1.1, 10.0, 3.0, 0.45),
                ("high",           1.4, 10.0, 8.0, 0.90),
            ],
        },
    },
}

# ==================================================================
# 2. 한국어 컬럼명 매핑: (asset_key, category, input_name) -> 컬럼명
# ==================================================================
COLUMN_NAMES = {
    ("HV_TR", "observed", "ext_condition"):      "관측_외관상태",
    ("HV_TR", "observed", "cable_box"):          "관측_케이블박스상태",
    ("HV_TR", "measured", "partial_discharge"):  "측정_부분방전",
    ("HV_TR", "measured", "temp_reading"):       "측정_온도판정",

    ("SW_DIST", "observed", "ext_condition"):        "관측_외관상태",
    ("SW_DIST", "observed", "oil_gas_leak"):         "관측_오일누유가스압",
    ("SW_DIST", "observed", "thermographic"):        "관측_열화상진단",
    ("SW_DIST", "observed", "internal_condition"):   "관측_내부상태운전",
    ("SW_DIST", "observed", "indoor_env"):           "관측_실내환경",
    ("SW_DIST", "observed", "cable_box"):            "관측_케이블박스상태",
    ("SW_DIST", "measured", "partial_discharge"):    "측정_부분방전",
    ("SW_DIST", "measured", "ductor_test"):          "측정_덕터테스트",
    ("SW_DIST", "measured", "oil_tests"):            "측정_오일테스트결과",
    ("SW_DIST", "measured", "temp_reading"):         "측정_온도판정",
    ("SW_DIST", "measured", "trip_test"):            "측정_트립테스트",

    ("SW_PRIM", "observed", "ext_condition"):        "관측_외관상태",
    ("SW_PRIM", "observed", "oil_gas_leak"):         "관측_오일누유가스압",
    ("SW_PRIM", "observed", "thermographic"):        "관측_열화상진단",
    ("SW_PRIM", "observed", "internal_condition"):   "관측_내부상태운전",
    ("SW_PRIM", "observed", "indoor_env"):           "관측_실내환경",
    ("SW_PRIM", "observed", "cable_box"):            "관측_케이블박스상태",
    ("SW_PRIM", "measured", "partial_discharge"):    "측정_부분방전",
    ("SW_PRIM", "measured", "ductor_test"):          "측정_덕터테스트",
    ("SW_PRIM", "measured", "ir_test"):              "측정_IR테스트",
    ("SW_PRIM", "measured", "oil_tests"):            "측정_오일테스트결과",
    ("SW_PRIM", "measured", "temp_reading"):         "측정_온도판정",
    ("SW_PRIM", "measured", "trip_test"):            "측정_트립테스트",

    ("CABLE", "measured", "sheath_test"):        "측정_시스시험",
    ("CABLE", "measured", "partial_discharge"):  "측정_부분방전",
    ("CABLE", "measured", "fault_history"):      "측정_고장이력",

    ("POLE", "observed", "visual_condition"):    "관측_지지물외관상태",
    ("POLE", "observed", "pole_top_rot"):        "관측_상부부후",
    ("POLE", "observed", "pole_leaning"):        "관측_기울임",
    ("POLE", "observed", "bird_animal_damage"):  "관측_조류동물피해",
    ("POLE", "measured", "pole_decay"):          "측정_부후도",

    ("LV_UGB", "observed", "steel_cover_pit"):       "관측_철재커버피트상태",
    ("LV_UGB", "observed", "water_moisture"):        "관측_수분침투",
    ("LV_UGB", "observed", "bell_condition"):        "관측_벨상태",
    ("LV_UGB", "observed", "insulation_condition"):  "관측_절연상태",
    ("LV_UGB", "observed", "signs_of_heating"):      "관측_발열징후",
    ("LV_UGB", "observed", "phase_barriers"):        "관측_상간격벽",
    ("LV_UGB", "measured", "operational_adequacy"):  "측정_운영가능여부",

    ("OHL_COND", "observed", "visual_condition"):     "관측_도체외관상태",
    ("OHL_COND", "observed", "midspan_joints"):       "관측_중간접속점수",
    ("OHL_COND", "measured", "conductor_sampling"):   "측정_도체샘플링",
    ("OHL_COND", "measured", "corrosion_monitoring"): "측정_부식모니터링",
}

# ==================================================================
# 3. MMI 결합 파라미터 (Factor Divider 1/2, Max No. of Combined Factors)
#    observed/measured: 자산군 1차 결합 (Table 13/15 계열)
#    top              : 관측CF·측정CF(·오일·DGA·FFA) 2차 결합 (Table 9/10)
# ==================================================================
MMI_PARAMS = {
    "HV_TR":   {"observed": (2, 1.5, 1.5), "measured": (2, 1.5, 1.5), "top": (4, 1.5, 1.5)},
    "SW_DIST": {"observed": (3, 1.5, 1.5), "measured": (3, 1.5, 1.5), "top": (2, 1.5, 1.5)},
    "SW_PRIM": {"observed": (3, 1.5, 1.5), "measured": (3, 1.5, 1.5), "top": (2, 1.5, 1.5)},
    "CABLE":   {"observed": (1, 1.5, 1.5), "measured": (3, 1.5, 1.5), "top": (2, 1.5, 1.5)},
    "POLE":    {"observed": (2, 1.5, 1.5), "measured": (1, 1.5, 1.5), "top": (2, 1.5, 1.5)},
    "LV_UGB":  {"observed": (3, 1.5, 1.5), "measured": (1, 1.5, 1.5), "top": (2, 1.5, 1.5)},
    "OHL_COND":{"observed": (2, 1.5, 1.5), "measured": (2, 1.5, 1.5), "top": (2, 1.5, 1.5)},
}

# ==================================================================
# 4. HV Transformer 전용: 오일/유중가스(DGA)/FFA 연속형 입력
# ==================================================================
HV_TR_CONTINUOUS_COLUMNS = {
    "moisture":  "측정_오일수분_ppm",
    "acidity":   "측정_오일산도_mgKOHg",
    "breakdown": "측정_오일절연강도_kV",
    "h2":        "측정_유중가스H2_ppm",
    "ch4":       "측정_유중가스CH4_ppm",
    "c2h4":      "측정_유중가스C2H4_ppm",
    "c2h6":      "측정_유중가스C2H6_ppm",
    "c2h2":      "측정_유중가스C2H2_ppm",
    "ffa":       "측정_FFA_ppm",
}
# (good, bad) 생성 기준값. breakdown은 역상관(클수록 좋음 -> z가 클수록 값이 작아짐)
HV_TR_CONTINUOUS_RANGES = {
    "moisture":  (5.0, 65.0),
    "acidity":   (0.05, 0.60),
    "breakdown": (65.0, 22.0),
    "h2":        (5.0, 220.0),
    "ch4":       (3.0, 160.0),
    "c2h4":      (3.0, 160.0),
    "c2h6":      (3.0, 160.0),
    "c2h2":      (0.2, 110.0),
    # FFA 범위: EQ.26(Collar=2.39×S^0.66)을 역산하여 HI1~HI5 전 구간을 커버하도록 설정
    #   z=0.00 → 0.30ppm → Collar≈1.1 (HI1)
    #   z=0.15 → 1.38ppm → Collar≈3.0 (HI1/HI2 경계)
    #   z=0.59 → 4.55ppm → Collar≈6.5 (HI3/HI4 경계)
    #   z=0.91 → 6.85ppm → Collar≈8.5 (HI4/HI5 경계)
    #   z=1.00 → 7.50ppm → Collar≈9.3 (HI5 최악)
    "ffa":       (0.3, 7.5),
}

# Table 203~205 (HV Transformer 컬럼): 오일 시험 원시값 -> 점수
OIL_BREAKPOINTS = {
    "moisture":  [(15.0, 0), (30.0, 2), (40.0, 4), (50.0, 8), (float("inf"), 10)],
    "acidity":   [(0.15, 2), (0.30, 4), (0.50, 8), (float("inf"), 10)],
    "breakdown": [(30.0, 10), (40.0, 4), (50.0, 2), (float("inf"), 0)],  # 역방향
}
# Table 206/207 (HV 컬럼): 오일 컨디션 점수(EQ.22) -> Factor/Collar
OIL_FACTOR_BREAKPOINTS = [(250.0, 1.00), (500.0, 1.10), (1000.0, 1.20), (float("inf"), 1.40)]
OIL_COLLAR_BREAKPOINTS = [(1000.0, 0.5), (float("inf"), 5.5)]

# Table 208~212: 유중가스(ppm) -> 점수
DGA_GAS_BREAKPOINTS = {
    "h2":   [(20.0, 0), (40.0, 2), (100.0, 4), (200.0, 10), (float("inf"), 16)],
    "ch4":  [(10.0, 0), (20.0, 2), (50.0, 4), (150.0, 10), (float("inf"), 16)],
    "c2h4": [(10.0, 0), (20.0, 2), (50.0, 4), (150.0, 10), (float("inf"), 16)],
    "c2h6": [(10.0, 0), (20.0, 2), (50.0, 4), (150.0, 10), (float("inf"), 16)],
    "c2h2": [(1.0, 0), (5.0, 2), (20.0, 4), (100.0, 8), (float("inf"), 10)],
}
DGA_WEIGHTS = {"h2": 50, "ch4": 30, "c2h4": 30, "c2h6": 30, "c2h2": 100}  # EQ.23
DGA_DIVIDER = 220.0  # EQ.24

# Table 215: FFA(ppm) -> Factor
FFA_FACTOR_BREAKPOINTS = [(4.0, 1.00), (5.0, 1.10), (6.0, 1.25), (7.0, 1.40), (float("inf"), 1.60)]


def get_condition_columns(asset_type: str) -> list:
    """자산유형(한국어)에 해당하는 관측/측정 컨디션 입력 컬럼명을 순서대로 반환"""
    asset_key = ASSET_KEY_MAP[asset_type]
    cols = []
    for category in ("observed", "measured"):
        for input_name in CATEGORICAL_INPUTS.get(asset_key, {}).get(category, {}):
            cols.append(COLUMN_NAMES[(asset_key, category, input_name)])
    if asset_key == "HV_TR":
        cols.extend(HV_TR_CONTINUOUS_COLUMNS.values())
    return cols


# ==================================================================
# 5. MMI(Maximum/Multiple Increment) 일반 결합 알고리즘 (Section 6.7.2)
# ==================================================================

def mmi_general(factors, divider1: float = 1.5, divider2: float = 1.5,
                 max_combined: int = 2) -> float:
    """N개의 Condition Factor를 CNAIM MMI 알고리즘으로 결합한다.

    factors > 1 인 값이 있으면: Var1=최댓값, Var2=다음 상위
    (max_combined-1)개의 (Factor-1) 합, Var3=Var2/divider1, 결과=Var1+Var3.
    모두 <=1 이면: Var1=최솟값, Var2=두번째로 작은 값,
    Var3=(Var2-1)/divider2, 결과=Var1+Var3.
    """
    factors = [f for f in factors if f is not None]
    if not factors:
        return 1.0
    if len(factors) == 1:
        return factors[0]

    gt1 = sorted([f for f in factors if f > 1.0], reverse=True)
    if gt1:
        var1 = gt1[0]
        rest = gt1[1:max_combined]
        var2 = sum(f - 1.0 for f in rest)
        var3 = var2 / divider1
        return var1 + var3

    asc = sorted(factors)
    var1 = asc[0]
    var2 = asc[1] if len(asc) > 1 else 1.0
    var3 = (var2 - 1.0) / divider2
    return var1 + var3


def combine_category(asset_key: str, category: str, state_dict: dict) -> tuple:
    """자산유형의 한 카테고리(observed/measured) 내 모든 입력을 MMI로 결합.

    state_dict: {input_name: state_key, ...}
    반환: (Combined Factor, Combined Cap, Combined Collar)
    카테고리에 정의된 입력이 없으면 중립값(1.0, 10.0, 0.5)을 반환한다.
    """
    defs = CATEGORICAL_INPUTS.get(asset_key, {}).get(category, {})
    if not defs:
        return 1.0, 10.0, 0.5

    factors, caps, collars = [], [], []
    for input_name, states in defs.items():
        skey = state_dict.get(input_name)
        match = next((s for s in states if s[0] == skey), None)
        if match is None:
            match = states[0]
        factors.append(match[1]); caps.append(match[2]); collars.append(match[3])

    max_n, d1, d2 = MMI_PARAMS[asset_key][category]
    cf = mmi_general(factors, d1, d2, max_n)
    return cf, min(caps), max(collars)


def lookup_breakpoint(value: float, table: list):
    """breakpoint 테이블([(상한값, 결과), ...] 오름차순)에서 value에 해당하는 결과 조회"""
    for upper, result in table:
        if value <= upper:
            return result
    return table[-1][1]


def oil_test_modifier(moisture_ppm: float, acidity: float, breakdown_kv: float) -> tuple:
    """EQ.22 오일 컨디션 점수 + Table 206/207 -> (Factor, Cap=10, Collar)"""
    m_score = lookup_breakpoint(moisture_ppm, OIL_BREAKPOINTS["moisture"])
    a_score = lookup_breakpoint(acidity, OIL_BREAKPOINTS["acidity"])
    b_score = lookup_breakpoint(breakdown_kv, OIL_BREAKPOINTS["breakdown"])
    score = 80 * m_score + 100 * a_score + 80 * b_score
    factor = lookup_breakpoint(score, OIL_FACTOR_BREAKPOINTS)
    collar = lookup_breakpoint(score, OIL_COLLAR_BREAKPOINTS)
    return float(factor), 10.0, float(collar)


def dga_test_modifier(h2: float, ch4: float, c2h4: float, c2h6: float, c2h2: float) -> tuple:
    """EQ.23/24 유중가스 점수 -> (Factor=1 고정[HV Transformer], Cap=10, Collar)

    CNAIM 원문: HV Transformer는 DGA 시험이 정기적으로 시행되지 않아
    이전 결과와의 비교가 불가능하므로 DGA Test Factor는 항상 1로 고정한다.
    """
    score = (
        DGA_WEIGHTS["h2"] * lookup_breakpoint(h2, DGA_GAS_BREAKPOINTS["h2"]) +
        DGA_WEIGHTS["ch4"] * lookup_breakpoint(ch4, DGA_GAS_BREAKPOINTS["ch4"]) +
        DGA_WEIGHTS["c2h4"] * lookup_breakpoint(c2h4, DGA_GAS_BREAKPOINTS["c2h4"]) +
        DGA_WEIGHTS["c2h6"] * lookup_breakpoint(c2h6, DGA_GAS_BREAKPOINTS["c2h6"]) +
        DGA_WEIGHTS["c2h2"] * lookup_breakpoint(c2h2, DGA_GAS_BREAKPOINTS["c2h2"])
    )
    collar = float(np.clip(score / DGA_DIVIDER, 0.5, 10.0))
    return 1.0, 10.0, collar


def ffa_test_modifier(ffa_ppm: float) -> tuple:
    """Table 215 + EQ.26 -> (Factor, Cap=10, Collar)"""
    factor = lookup_breakpoint(ffa_ppm, FFA_FACTOR_BREAKPOINTS)
    collar = float(np.clip(2.39 * (max(ffa_ppm, 0.0) ** 0.66), 0.5, 10.0))
    return float(factor), 10.0, collar


# ==================================================================
# 6. 잠재 중증도(z) 기반 상관 랜덤 생성 헬퍼 (aip_01에서 사용)
# ==================================================================

def sample_states(states: list, z: np.ndarray, rng: np.random.Generator,
                   noise_std: float = 0.12) -> np.ndarray:
    """잠재 중증도 z(0~1)에 입력별 소(小)노이즈를 더해 severity_rank가
    가장 가까운 상태를 선택한다. 동일 자산의 여러 입력이 z를 공유하므로
    서로 연관된 컨디션 입력들이 같은 방향으로 움직인다(상관성 보장)."""
    sevs = np.array([s[4] for s in states])
    target = np.clip(z + rng.normal(0, noise_std, size=z.shape), 0.0, 1.0)
    idx = np.argmin(np.abs(target[:, None] - sevs[None, :]), axis=1)
    keys = np.array([s[0] for s in states], dtype=object)
    return keys[idx]


def sample_continuous(z: np.ndarray, rng: np.random.Generator,
                       good: float, bad: float, noise_rel: float = 0.22) -> np.ndarray:
    """잠재 중증도 z(0~1)를 good~bad 구간에 선형 보간 + 노이즈로 매핑한다.
    (good>bad이면 값이 작을수록 나쁜 상태인 역상관 입력, 예: 절연강도kV)"""
    span = bad - good
    base = good + z * span
    noise = rng.normal(0, noise_rel, size=z.shape) * abs(span)
    val = base + noise
    lo, hi = (min(good, bad), max(good, bad))
    margin = 0.3 * (hi - lo)
    val = np.clip(val, max(lo - margin, 0.0), hi + margin)
    return np.round(val, 3)
