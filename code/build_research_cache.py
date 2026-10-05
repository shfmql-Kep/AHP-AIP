from __future__ import annotations

import re
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

import pdfplumber
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "research_cache"
TEXT_DIR = CACHE / "text"
TABLE_DIR = CACHE / "tables"
FIGURE_DIR = CACHE / "figures"
META_DIR = CACHE / "metadata"

SOURCE_DIRS = [
    ROOT / "박사논문 예시",
    ROOT / "참고자료",
]
EXTRA_PDFS = [
    ROOT / "CNAIM.pdf",
]

TOPIC_RULES = {
    "자산관리/ISO55000": ["asset management", "iso 55000", "iam", "samp", "자산관리"],
    "AIP/투자계획": ["asset investment planning", "aip", "investment planning", "투자계획", "investment"],
    "CNAIM/PoF": ["cnaim", "probability of failure", "pof", "health index", "health score", "고장확률"],
    "CoF/Risk": ["consequence of failure", "cof", "risk", "long term risk", "위험"],
    "SAIDI/KPI": ["saidi", "reliability", "kpi", "customer minutes", "신뢰도"],
    "AHP/Fuzzy/MCDM": ["ahp", "fuzzy", "mcdm", "pairwise", "analytic hierarchy"],
    "포트폴리오/최적화": ["portfolio", "optimization", "optimisation", "ilp", "genetic algorithm", "ga"],
    "민감도/강건성": ["sensitivity", "robust", "scenario", "constraint", "시나리오"],
    "소프트웨어/시장동향": ["software", "market guide", "buyer", "gartner", "verdantix"],
}

FIGURE_KEYWORDS = [
    "figure", "fig.", "그림", "diagram", "framework", "process", "model",
    "architecture", "flow", "matrix", "curve", "chart",
]
TABLE_KEYWORDS = ["table", "표", "appendix", "부록"]


@dataclass
class PdfDoc:
    doc_id: str
    source_group: str
    path: Path
    title: str
    pages: int = 0
    text_chars: int = 0
    figure_pages: list[int] | None = None
    table_pages: list[int] | None = None
    topics: list[str] | None = None
    text_file: Path | None = None
    table_file: Path | None = None


def safe_stem(path: Path, index: int) -> str:
    name = re.sub(r"[^\w가-힣.-]+", "_", path.stem, flags=re.UNICODE).strip("_")
    if len(name) > 60:
        name = name[:60].rstrip("_")
    return f"D{index:02d}_{name}"


def iter_pdfs() -> list[tuple[str, Path]]:
    items: list[tuple[str, Path]] = []
    for source_dir in SOURCE_DIRS:
        if not source_dir.exists():
            continue
        for path in sorted(source_dir.rglob("*.pdf")):
            items.append((source_dir.name, path))
    for path in EXTRA_PDFS:
        if path.exists():
            items.append(("루트", path))
    return items


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def contains_any(text: str, words: Iterable[str]) -> bool:
    lower = text.lower()
    return any(w.lower() in lower for w in words)


def detect_topics(text: str, path: Path) -> list[str]:
    haystack = f"{path.name}\n{text[:30000]}".lower()
    topics = [topic for topic, words in TOPIC_RULES.items() if any(w.lower() in haystack for w in words)]
    return topics or ["추후분류"]


def count_page_images(reader_page) -> int:
    try:
        resources = reader_page.get("/Resources") or {}
        xobjects = resources.get("/XObject") or {}
        count = 0
        for obj in xobjects.values():
            try:
                subtype = obj.get_object().get("/Subtype")
                if subtype == "/Image":
                    count += 1
            except Exception:
                continue
        return count
    except Exception:
        return 0


def extract_pdf(doc: PdfDoc) -> PdfDoc:
    text_blocks: list[str] = []
    table_lines: list[str] = []
    figure_pages: list[int] = []
    table_pages: list[int] = []

    reader = PdfReader(str(doc.path))
    doc.pages = len(reader.pages)

    with pdfplumber.open(str(doc.path)) as pdf:
        for idx, page in enumerate(pdf.pages, start=1):
            text = normalize_text(page.extract_text() or "")
            image_count = 0
            if idx - 1 < len(reader.pages):
                image_count = count_page_images(reader.pages[idx - 1])

            text_blocks.append(f"## p.{idx}\n\n{text if text else '[텍스트 추출 없음]'}\n")

            lower = text.lower()
            if image_count > 0 or contains_any(lower, FIGURE_KEYWORDS):
                figure_pages.append(idx)
            if contains_any(lower, TABLE_KEYWORDS):
                table_pages.append(idx)

            try:
                tables = page.extract_tables() or []
            except Exception:
                tables = []

            if tables:
                if idx not in table_pages:
                    table_pages.append(idx)
                table_lines.append(f"## p.{idx}\n")
                for t_no, table in enumerate(tables, start=1):
                    table_lines.append(f"### 표 후보 {t_no}\n")
                    table_lines.extend(markdown_table(table))
                    table_lines.append("")

    full_text = "\n".join(text_blocks)
    doc.text_chars = len(full_text)
    doc.figure_pages = sorted(set(figure_pages))
    doc.table_pages = sorted(set(table_pages))
    doc.topics = detect_topics(full_text, doc.path)

    doc.text_file = TEXT_DIR / f"{doc.doc_id}.md"
    doc.text_file.write_text(
        f"# {doc.title}\n\n"
        f"- 원본: `{doc.path.relative_to(ROOT) if doc.path.is_relative_to(ROOT) else doc.path}`\n"
        f"- 페이지 수: {doc.pages}\n"
        f"- 주요 주제: {', '.join(doc.topics)}\n"
        f"- 그림 후보 페이지: {format_ranges(doc.figure_pages)}\n"
        f"- 표 후보 페이지: {format_ranges(doc.table_pages)}\n\n"
        "---\n\n"
        f"{full_text}\n",
        encoding="utf-8",
    )

    doc.table_file = TABLE_DIR / f"{doc.doc_id}_tables.md"
    doc.table_file.write_text(
        f"# {doc.title} - 표 추출 후보\n\n"
        + ("\n".join(table_lines) if table_lines else "자동 추출 가능한 표가 없거나, 표가 이미지 형태입니다.\n"),
        encoding="utf-8",
    )
    return doc


def read_cached_doc(doc: PdfDoc) -> PdfDoc | None:
    text_file = TEXT_DIR / f"{doc.doc_id}.md"
    table_file = TABLE_DIR / f"{doc.doc_id}_tables.md"
    if not text_file.exists() or not table_file.exists():
        return None

    head = text_file.read_text(encoding="utf-8", errors="replace")[:3000]
    pages_match = re.search(r"- 페이지 수:\s*(\d+)", head)
    topics_match = re.search(r"- 주요 주제:\s*(.*)", head)
    figure_match = re.search(r"- 그림 후보 페이지:\s*(.*)", head)
    table_match = re.search(r"- 표 후보 페이지:\s*(.*)", head)

    doc.pages = int(pages_match.group(1)) if pages_match else 0
    doc.text_chars = text_file.stat().st_size
    doc.topics = [x.strip() for x in topics_match.group(1).split(",")] if topics_match else ["추후분류"]
    doc.figure_pages = parse_ranges(figure_match.group(1)) if figure_match else []
    doc.table_pages = parse_ranges(table_match.group(1)) if table_match else []
    doc.text_file = text_file
    doc.table_file = table_file
    return doc


def markdown_table(table: list[list[str | None]]) -> list[str]:
    cleaned = [[normalize_cell(cell) for cell in row] for row in table if row]
    if not cleaned:
        return ["표 추출 실패"]
    max_cols = max(len(row) for row in cleaned)
    cleaned = [row + [""] * (max_cols - len(row)) for row in cleaned]
    header = cleaned[0]
    body = cleaned[1:] or [[""] * max_cols]
    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(["---"] * max_cols) + " |",
    ]
    for row in body:
        lines.append("| " + " | ".join(row) + " |")
    return lines


def normalize_cell(cell: str | None) -> str:
    if cell is None:
        return ""
    cell = normalize_text(str(cell)).replace("\n", "<br>")
    cell = cell.replace("|", "\\|")
    return cell


def format_ranges(values: list[int] | None) -> str:
    if not values:
        return "-"
    values = sorted(set(values))
    ranges = []
    start = prev = values[0]
    for v in values[1:]:
        if v == prev + 1:
            prev = v
        else:
            ranges.append(f"{start}" if start == prev else f"{start}-{prev}")
            start = prev = v
    ranges.append(f"{start}" if start == prev else f"{start}-{prev}")
    return ", ".join(ranges)


def parse_ranges(text: str) -> list[int]:
    text = (text or "").strip()
    if not text or text == "-":
        return []
    values: list[int] = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            if a.strip().isdigit() and b.strip().isdigit():
                values.extend(range(int(a), int(b) + 1))
        elif part.isdigit():
            values.append(int(part))
    return sorted(set(values))


def infer_use_positions(topics: list[str]) -> str:
    positions: list[str] = []
    topic_set = set(topics)
    if {"자산관리/ISO55000", "AIP/투자계획", "소프트웨어/시장동향"} & topic_set:
        positions.extend(["제2장 이론적 배경", "제3장 선행연구 분석"])
    if {"CNAIM/PoF", "CoF/Risk", "SAIDI/KPI"} & topic_set:
        positions.extend(["제2장 이론적 배경", "제4장 방법론"])
    if {"AHP/Fuzzy/MCDM", "포트폴리오/최적화", "민감도/강건성"} & topic_set:
        positions.extend(["제3장 선행연구 분석", "제4장 방법론", "제5장 결과 분석"])
    return ", ".join(dict.fromkeys(positions)) or "추후 판단"


def infer_core_note(doc: PdfDoc) -> str:
    title = doc.title.lower()
    topics = set(doc.topics or [])
    if "박사논문 예시" in doc.source_group:
        if "예시 1" in doc.title:
            return "AHP와 Fuzzy 결합 논리, 부록 설문 구성, 장·절 전개 방식 참고. 문장·구성 복제는 금지하고 방법론 정당화 논리만 활용."
        return "국내 박사논문 형식, 장 구성, 결과 해석 문체, 표·그림 배치 방식 참고. 본문 표현은 본 연구에 맞게 재작성."
    if "cnaim" in title or "network asset indices" in title:
        return "CNAIM 기반 HI, PoF, CoF, Risk 산정체계의 1차 근거. 대상 설비 매핑, PoF 산식, 그림 4 프로세스 확인에 우선 활용."
    if "iam" in title:
        return "IAM 자산관리 개념, 조직·전략·리스크·의사결정 체계 설명 근거. 제2장 자산관리 개념 그림과 용어 정리에 활용."
    if "samp" in title:
        return "전력회사 자산관리계획과 규제·전송자산 투자계획의 실무 근거. KPI, 리스크 허용수준, 장기계획 논리에 활용."
    if "amcl" in title or "asset investment planning" in title or "market guide" in title:
        return "AIP 프로세스, 비용-리스크-성능 균형, 소프트웨어 기반 투자계획 실무 동향 근거. 연구 필요성과 실무적 의의에 활용."
    if "verdantix" in title or "buyer" in title or "software" in title or "gartner" in title:
        return "APM/AIP/EAM 소프트웨어 시장과 데이터 기반 자산관리 전환 동향 근거. 선행연구·산업동향 배경에 활용."
    if "national grid" in title or "circuit optimisation" in title:
        return "회로·계통 최적화 및 전력회사 운영목표 기반 투자계획 사례 근거. 민감도 분석과 KPI 제약 설명에 활용."
    if "AHP/Fuzzy/MCDM" in topics:
        return "전문가 판단, 다기준 가중치, 정성적 판단의 모호성 보정 논리 근거로 활용."
    return "본문 수정 시 관련 장에서 보조 근거로 활용하되, 직접 인용 전 원문 페이지 재확인 필요."


def make_indexes(docs: list[PdfDoc]) -> None:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    list_lines = [
        "# 연구자료 캐시 목록",
        "",
        f"- 생성일: {now}",
        "- 목적: 박사논문 예시·참고자료·CNAIM 자료를 반복 활용하기 위한 텍스트/표/그림 후보 인덱스",
        "- 주의: 본 캐시는 원문 검토를 대체하지 않으며, 핵심 인용·그림 사용 전에는 원문 페이지를 재확인해야 한다.",
        "",
        "| ID | 구분 | 자료명 | 페이지 | 텍스트 파일 | 표 파일 | 주요 주제 | 논문 반영 후보 |",
        "|---|---|---|---:|---|---|---|---|",
    ]
    for doc in docs:
        list_lines.append(
            f"| {doc.doc_id} | {doc.source_group} | {doc.title} | {doc.pages} | "
            f"`{doc.text_file.relative_to(ROOT)}` | `{doc.table_file.relative_to(ROOT)}` | "
            f"{', '.join(doc.topics or [])} | {infer_use_positions(doc.topics or [])} |"
        )
    (CACHE / "00_자료목록.md").write_text("\n".join(list_lines) + "\n", encoding="utf-8")

    summary_lines = [
        "# 문헌별 핵심요약",
        "",
        "이 파일은 논문 본문 수정 시 먼저 확인하는 빠른 참조용 요약이다. 자동 주제분류와 연구 진행 중의 활용 맥락을 함께 반영하였다.",
        "",
    ]
    for doc in docs:
        summary_lines.extend([
            f"## {doc.doc_id}. {doc.title}",
            "",
            f"- 구분: {doc.source_group}",
            f"- 페이지 수: {doc.pages}",
            f"- 주요 주제: {', '.join(doc.topics or [])}",
            f"- 핵심 활용 방향: {infer_core_note(doc)}",
            f"- 논문 반영 위치: {infer_use_positions(doc.topics or [])}",
            f"- 그림 후보 페이지: {format_ranges(doc.figure_pages)}",
            f"- 표 후보 페이지: {format_ranges(doc.table_pages)}",
            f"- 텍스트 캐시: `{doc.text_file.relative_to(ROOT)}`",
            f"- 표 캐시: `{doc.table_file.relative_to(ROOT)}`",
            "- 주의: 직접 인용, 그림 재작성, 수치 확인 전에는 원문 PDF의 해당 페이지를 재확인한다.",
            "",
        ])
    (CACHE / "01_문헌별_핵심요약.md").write_text("\n".join(summary_lines), encoding="utf-8")

    topic_lines = [
        "# 주제별 근거 인덱스",
        "",
        "논문 본문 수정 시 우선 이 파일에서 주제별 관련 자료를 찾고, 필요한 경우 `text/`의 해당 페이지를 확인한다.",
        "",
    ]
    for topic in TOPIC_RULES:
        topic_lines.append(f"## {topic}\n")
        matched = [d for d in docs if d.topics and topic in d.topics]
        if not matched:
            topic_lines.append("- 관련 자료 미분류\n")
            continue
        for doc in matched:
            topic_lines.append(
                f"- {doc.doc_id} `{doc.title}`: p.{format_ranges(doc.figure_pages)} 그림 후보, "
                f"p.{format_ranges(doc.table_pages)} 표 후보, 반영 후보: {infer_use_positions(doc.topics or [])}"
            )
        topic_lines.append("")
    (CACHE / "02_주제별_근거인덱스.md").write_text("\n".join(topic_lines), encoding="utf-8")

    fig_lines = [
        "# 그림·표 후보 인덱스",
        "",
        "자동 추출 텍스트, 이미지 객체, figure/table 키워드를 기준으로 만든 후보 목록이다. 실제 논문 반영 전 원문 페이지를 다시 확인한다.",
        "",
        "| ID | 자료명 | 그림 후보 페이지 | 표 후보 페이지 | 비고 |",
        "|---|---|---|---|---|",
    ]
    for doc in docs:
        note = "이미지형 표/그림 가능" if doc.figure_pages else "텍스트 중심"
        fig_lines.append(
            f"| {doc.doc_id} | {doc.title} | {format_ranges(doc.figure_pages)} | {format_ranges(doc.table_pages)} | {note} |"
        )
    (CACHE / "03_그림표_인덱스.md").write_text("\n".join(fig_lines) + "\n", encoding="utf-8")

    evidence_lines = [
        "# 논문 반영 위치표",
        "",
        "각 자료가 논문의 어느 장에서 근거로 활용될 수 있는지 정리한 1차 인덱스이다.",
        "",
        "| ID | 자료명 | 핵심 활용 방향 | 반영 위치 | 주의사항 |",
        "|---|---|---|---|---|",
    ]
    for doc in docs:
        evidence_lines.append(
            f"| {doc.doc_id} | {doc.title} | {', '.join(doc.topics or [])} 관련 근거 | "
            f"{infer_use_positions(doc.topics or [])} | 직접 인용·그림 사용 전 원문 재확인 |"
        )
    (CACHE / "04_논문반영_위치표.md").write_text("\n".join(evidence_lines) + "\n", encoding="utf-8")

    guide = """# research_cache 사용법

이 폴더는 박사논문 본문 수정 중 반복 참조할 자료를 토큰 효율적으로 사용하기 위한 캐시이다.

## 권장 사용 순서

1. `00_자료목록.md`에서 자료 ID와 성격을 확인한다.
2. `02_주제별_근거인덱스.md`에서 주제별 관련 자료를 찾는다.
3. `03_그림표_인덱스.md`에서 그림·표 후보 페이지를 확인한다.
4. 필요한 경우 `text/Dxx_자료명.md`의 해당 페이지 텍스트를 확인한다.
5. 표가 필요하면 `tables/Dxx_자료명_tables.md`를 확인한다.
6. 논문에 직접 인용하거나 그림을 재작성할 때는 원본 PDF 페이지를 다시 확인한다.

## 주의

- 이 캐시는 자동 추출 결과이므로 OCR 누락, 표 구조 깨짐, 이미지형 글자 누락이 있을 수 있다.
- 원문 그림을 그대로 사용하는 경우 저작권·출처·사용조건을 별도로 확인해야 한다.
- 논문 본문에는 원문 그림을 복제하기보다, 구조를 참고하여 본 연구 맥락에 맞게 재작성하는 것을 원칙으로 한다.
"""
    (CACHE / "README.md").write_text(guide, encoding="utf-8")

    (FIGURE_DIR / "README.md").write_text(
        "# 그림 캐시 안내\n\n"
        "현재 환경에는 PDF 페이지 렌더링 도구(Poppler)가 없어 원문 페이지 이미지를 자동 생성하지 않았다.\n"
        "대신 `03_그림표_인덱스.md`에 그림 후보 페이지를 정리했다.\n"
        "논문에 그림을 넣을 때는 후보 페이지를 원문 PDF에서 확인한 뒤, 저작권 문제가 없거나 재작성 가능한 경우 "
        "`figures/generated/` 또는 `figures/source/`에 새 그림으로 저장한다.\n",
        encoding="utf-8",
    )


def copy_existing_markdown() -> None:
    md_dir = CACHE / "existing_markdown"
    md_dir.mkdir(parents=True, exist_ok=True)
    for source_dir in SOURCE_DIRS:
        if not source_dir.exists():
            continue
        for path in sorted(source_dir.rglob("*.md")):
            target = md_dir / path.name
            shutil.copy2(path, target)


def main() -> None:
    for d in [CACHE, TEXT_DIR, TABLE_DIR, FIGURE_DIR, META_DIR]:
        d.mkdir(parents=True, exist_ok=True)

    copy_existing_markdown()

    docs: list[PdfDoc] = []
    for index, (group, path) in enumerate(iter_pdfs(), start=1):
        doc = PdfDoc(
            doc_id=safe_stem(path, index),
            source_group=group,
            path=path,
            title=path.stem,
        )
        cached = read_cached_doc(doc)
        if cached is not None:
            print(f"[{index}] 기존 캐시 사용: {doc.title}")
            docs.append(cached)
            continue

        print(f"[{index}] 처리 중: {doc.title}")
        try:
            docs.append(extract_pdf(doc))
        except Exception as exc:
            error_file = META_DIR / f"{doc.doc_id}_error.txt"
            error_file.write_text(f"{path}\n{type(exc).__name__}: {exc}\n", encoding="utf-8")
            doc.pages = 0
            doc.text_chars = 0
            doc.figure_pages = []
            doc.table_pages = []
            doc.topics = ["추출오류"]
            doc.text_file = error_file
            doc.table_file = error_file
            docs.append(doc)

    make_indexes(docs)
    print(f"완료: {CACHE}")


if __name__ == "__main__":
    main()
