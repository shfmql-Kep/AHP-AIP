# 문헌 수집 코퍼스 (2026-10-05)

## 수집 방법
- OpenAlex API(23개 질의 중 일부 재질의), arXiv API(10개 질의), Crossref API(4개 질의). 인용수순 상위 + 최근순 상위를 질의당 수집.
- OpenAlex 무료 일일 한도 소진으로 4개 질의(변압기 fleet, 케이블 노후, 개폐장치, 전역 민감도 최근분)는 Crossref로 대체.
- 수집 스크립트: 스크래치 영역(`crawl.py`, `crawl2.py`) — 필요 시 재생성 가능.

## 파일
| 파일 | 내용 |
|---|---|
| `corpus_raw.jsonl`, `corpus_raw2.jsonl` | OpenAlex 원자료 |
| `corpus_supp.json` | arXiv·Crossref 보충분 |
| `corpus_all.csv` | 중복 제거 전체(약 7,400건) |
| `corpus_core.csv` | 전력 분야 + 자산/계통 키워드 필터 통과(약 2,900건) |
| `corpus_asset_power.csv` | 자산관리·교체·건전도·고장확률 + 전력설비 교집합(약 970건) |
| `trend_topics_by_year.csv` | 주제별 연도 건수 |

## 한계
- 초록·메타데이터 기준이며 본문은 읽지 않았다. 일부 논문은 초록이 없다.
- 키워드 정규식 필터라 잡음(비전력 분야)이 남아 있다. 체계적 문헌고찰이 아니다.
- 2026년 건수는 최근순 수집으로 과대 반영될 수 있다(연도별 비중은 보조 지표).
- 국내 학술지(KCI) 커버리지가 낮다. DBpia·RISS 직접 검색 필요.
