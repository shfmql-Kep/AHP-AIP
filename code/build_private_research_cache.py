from __future__ import annotations

import html
import re
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET

import pdfplumber
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = next(p for p in ROOT.iterdir() if p.is_dir() and p.name == "참고자료")
CACHE = ROOT / "private_research_cache"
TEXT_DIR = CACHE / "text"
TABLE_DIR = CACHE / "tables"
FIGURE_DIR = CACHE / "figures"
META_DIR = CACHE / "metadata"

PRIVATE_TARGETS = [
    "발간용_최종보고서_0421_v3.hwpx",
    "유출금지_AIP 사전과제 최종보고서.pdf",
]

TOPIC_RULES = {
    "AIP/투자가치 평가": ["투자가치", "investment value", "asset investment planning", "aip", "투자 가치"],
    "전력설비 투자방법론": ["전력설비", "투자방법론", "investment methodology", "교체투자", "투자 우선순위"],
    "자산관리 시스템/투자 최적화": ["자산관리", "asset management", "투자 최적화", "optimization", "최적화 솔루션"],
    "비용-리스크-성능 균형": ["risk", "리스크", "위험", "cost", "비용", "performance", "성능"],
    "KPI/SAIDI/Risk 제약": ["kpi", "saidi", "risk", "위험도", "신뢰도", "품질"],
    "포트폴리오 최적화 및 민감도 분석": ["portfolio", "포트폴리오", "민감도", "sensitivity", "시나리오"],
}

FIGURE_KEYWORDS = ["그림", "figure", "fig.", "프로세스", "절차", "모형", "프레임워크", "matrix", "chart", "그래프"]
TABLE_KEYWORDS = ["표", "table", "부록", "목록"]


@dataclass
class PrivateDoc:
    doc_id: str
    path: Path
    title: str
    kind: str
    pages_or_sections: int = 0
    text_chars: int = 0
    topics: list[str] | None = None
    figure_candidates: list[str] | None = None
    table_candidates: list[str] | None = None
    text_file: Path | None = None
    table_file: Path | None = None
    metadata_file: Path | None = None


def ensure_dirs() -> None:
    for d in [CACHE, TEXT_DIR, TABLE_DIR, FIGURE_DIR, META_DIR]:
        d.mkdir(parents=True, exist_ok=True)


def safe_stem(path: Path, index: int) -> str:
    name = re.sub(r"[^\w가-힣.-]+", "_", path.stem, flags=re.UNICODE).strip("_")
    return f"P{index:02d}_{name[:70].rstrip('_')}"


def find_targets() -> list[Path]:
    files = {p.name: p for p in SOURCE_DIR.iterdir() if p.is_file()}
    missing = [name for name in PRIVATE_TARGETS if name not in files]
    if missing:
        raise FileNotFoundError("비공개 대상 자료를 찾지 못했습니다: " + ", ".join(missing))
    return [files[name] for name in PRIVATE_TARGETS]


def normalize_text(text: str) -> str:
    text = html.unescape(text or "")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def contains_any(text: str, words: Iterable[str]) -> bool:
    lower = text.lower()
    return any(w.lower() in lower for w in words)


def detect_topics(text: str, title: str) -> list[str]:
    haystack = f"{title}\n{text[:80000]}".lower()
    topics = [topic for topic, words in TOPIC_RULES.items() if any(w.lower() in haystack for w in words)]
    return topics or ["추후분류"]


def format_candidates(values: list[str] | None) -> str:
    if not values:
        return "-"
    return ", ".join(values[:80]) + (" ..." if len(values) > 80 else "")


def xml_local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def extract_hwpx(doc: PrivateDoc) -> PrivateDoc:
    section_blocks: list[str] = []
    table_blocks: list[str] = []
    figure_candidates: list[str] = []
    table_candidates: list[str] = []
    metadata_lines: list[str] = []

    with zipfile.ZipFile(doc.path) as zf:
        names = zf.namelist()
        section_names = [n for n in names if n.startswith("Contents/section") and n.endswith(".xml")]
        image_names = [n for n in names if n.startswith("BinData/")]
        doc.pages_or_sections = len(section_names)

        metadata_lines.append(f"# {doc.title} - HWPX 메타데이터")
        metadata_lines.append("")
        metadata_lines.append(f"- 섹션 XML 수: {len(section_names)}")
        metadata_lines.append(f"- BinData 항목 수: {len(image_names)}")
        metadata_lines.append("")
        metadata_lines.append("## BinData 목록")
        for name in image_names:
            metadata_lines.append(f"- {name}")

        for section_idx, name in enumerate(section_names, start=1):
            xml = zf.read(name).decode("utf-8", errors="replace")
            root = ET.fromstring(xml)
            texts: list[str] = []
            rows: list[list[str]] = []
            current_row: list[str] = []

            for elem in root.iter():
                local = xml_local_name(elem.tag)
                if local == "t" and elem.text:
                    texts.append(elem.text)
                elif local == "tbl":
                    table_candidates.append(f"section{section_idx}")
                elif local == "tr":
                    if current_row:
                        rows.append(current_row)
                        current_row = []
                elif local == "tc":
                    cell_texts = []
                    for child in elem.iter():
                        if xml_local_name(child.tag) == "t" and child.text:
                            cell_texts.append(child.text)
                    if cell_texts:
                        current_row.append(normalize_text(" ".join(cell_texts)))

            if current_row:
                rows.append(current_row)

            section_text = normalize_text(" ".join(texts))
            section_blocks.append(f"## section {section_idx}\n\n{section_text if section_text else '[텍스트 추출 없음]'}\n")

            if contains_any(section_text, FIGURE_KEYWORDS):
                figure_candidates.append(f"section{section_idx}")
            if contains_any(section_text, TABLE_KEYWORDS) or rows:
                table_candidates.append(f"section{section_idx}")

            if rows:
                table_blocks.append(f"## section {section_idx}\n")
                table_blocks.extend(markdown_table(rows[:200]))
                table_blocks.append("")

    full_text = "\n".join(section_blocks)
    doc.text_chars = len(full_text)
    doc.topics = detect_topics(full_text, doc.title)
    doc.figure_candidates = sorted(set(figure_candidates + [f"BinData:{len(figure_candidates)+1}" for _ in []]))
    doc.table_candidates = sorted(set(table_candidates))

    doc.text_file = TEXT_DIR / f"{doc.doc_id}.md"
    doc.text_file.write_text(private_text_header(doc) + full_text + "\n", encoding="utf-8")

    doc.table_file = TABLE_DIR / f"{doc.doc_id}_tables.md"
    doc.table_file.write_text(
        f"# {doc.title} - 표 추출 후보\n\n"
        + ("\n".join(table_blocks) if table_blocks else "자동 추출 가능한 표 구조가 없거나 이미지 형태입니다.\n"),
        encoding="utf-8",
    )

    doc.metadata_file = META_DIR / f"{doc.doc_id}_metadata.md"
    doc.metadata_file.write_text("\n".join(metadata_lines) + "\n", encoding="utf-8")
    return doc


def count_page_images(reader_page) -> int:
    try:
        resources = reader_page.get("/Resources") or {}
        xobjects = resources.get("/XObject") or {}
        count = 0
        for obj in xobjects.values():
            try:
                if obj.get_object().get("/Subtype") == "/Image":
                    count += 1
            except Exception:
                continue
        return count
    except Exception:
        return 0


def extract_pdf(doc: PrivateDoc) -> PrivateDoc:
    text_blocks: list[str] = []
    table_blocks: list[str] = []
    figure_pages: list[str] = []
    table_pages: list[str] = []

    reader = PdfReader(str(doc.path))
    doc.pages_or_sections = len(reader.pages)

    with pdfplumber.open(str(doc.path)) as pdf:
        for idx, page in enumerate(pdf.pages, start=1):
            text = normalize_text(page.extract_text() or "")
            image_count = count_page_images(reader.pages[idx - 1]) if idx - 1 < len(reader.pages) else 0
            text_blocks.append(f"## p.{idx}\n\n{text if text else '[텍스트 추출 없음]'}\n")

            if image_count > 0 or contains_any(text, FIGURE_KEYWORDS):
                figure_pages.append(f"p.{idx}")
            if contains_any(text, TABLE_KEYWORDS):
                table_pages.append(f"p.{idx}")

            try:
                tables = page.extract_tables() or []
            except Exception:
                tables = []
            if tables:
                if f"p.{idx}" not in table_pages:
                    table_pages.append(f"p.{idx}")
                table_blocks.append(f"## p.{idx}\n")
                for t_no, table in enumerate(tables, start=1):
                    table_blocks.append(f"### 표 후보 {t_no}\n")
                    table_blocks.extend(markdown_table(table))
                    table_blocks.append("")

    full_text = "\n".join(text_blocks)
    doc.text_chars = len(full_text)
    doc.topics = detect_topics(full_text, doc.title)
    doc.figure_candidates = figure_pages
    doc.table_candidates = table_pages

    doc.text_file = TEXT_DIR / f"{doc.doc_id}.md"
    doc.text_file.write_text(private_text_header(doc) + full_text + "\n", encoding="utf-8")

    doc.table_file = TABLE_DIR / f"{doc.doc_id}_tables.md"
    doc.table_file.write_text(
        f"# {doc.title} - 표 추출 후보\n\n"
        + ("\n".join(table_blocks) if table_blocks else "자동 추출 가능한 표가 없거나 표가 이미지 형태입니다.\n"),
        encoding="utf-8",
    )
    return doc


def private_text_header(doc: PrivateDoc) -> str:
    rel = doc.path.relative_to(ROOT)
    return (
        f"# {doc.title}\n\n"
        "- 보안등급: 비공개 로컬 분석용\n"
        "- 주의: 대외 공유, 원문 복사, 직접 인용, 그림 복제는 사용자 승인 전 금지\n"
        f"- 원본: `{rel}`\n"
        f"- 형식: {doc.kind}\n"
        f"- 페이지/섹션 수: {doc.pages_or_sections}\n"
        f"- 주요 주제: {', '.join(doc.topics or [])}\n"
        f"- 그림 후보: {format_candidates(doc.figure_candidates)}\n"
        f"- 표 후보: {format_candidates(doc.table_candidates)}\n\n"
        "---\n\n"
    )


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
    return normalize_text(str(cell)).replace("\n", "<br>").replace("|", "\\|")


def infer_use_positions(topics: list[str]) -> str:
    positions: list[str] = []
    topic_set = set(topics)
    if {"AIP/투자가치 평가", "전력설비 투자방법론", "자산관리 시스템/투자 최적화"} & topic_set:
        positions.extend(["제2장 이론적 배경", "제3장 선행연구 분석", "제4장 방법론"])
    if {"비용-리스크-성능 균형", "KPI/SAIDI/Risk 제약"} & topic_set:
        positions.extend(["제4장 방법론", "제5장 결과 분석"])
    if {"포트폴리오 최적화 및 민감도 분석"} & topic_set:
        positions.extend(["제4장 방법론", "제5장 민감도 분석"])
    return ", ".join(dict.fromkeys(positions)) or "추후 판단"


def infer_core_note(doc: PrivateDoc) -> str:
    title = doc.title
    if "사전과제" in title:
        return "한국전력공사 전력연구원 내부 사전검토 성격의 AIP 투자 최적화 타당성 근거. 연구 배경, 국내 전력설비 AIP 필요성, 실무 적용 가능성 설명에 활용."
    if "0421" in title or "투자가치" in title or "최종보고서" in title:
        return "전력설비 투자가치 평가모델과 투자방법론 개발 근거. 투자가치 지표, 투자방법론, 포트폴리오 최적화 프레임워크 정합성 검토에 활용."
    return "비공개 내부 근거자료. 직접 인용 대신 논리 검토와 방법론 정합성 확인에 활용."


def write_indexes(docs: list[PrivateDoc]) -> None:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = [
        "# 비공개 연구자료 캐시 목록",
        "",
        f"- 생성일: {now}",
        "- 보안등급: 비공개 로컬 분석용",
        "- 외부 공유, 원문 복사, 직접 인용, 그림 복제는 사용자 승인 전 금지",
        "",
        "| ID | 자료명 | 형식 | 페이지/섹션 | 주요 주제 | 텍스트 캐시 | 표 캐시 | 논문 반영 후보 |",
        "|---|---|---|---:|---|---|---|---|",
    ]
    for doc in docs:
        lines.append(
            f"| {doc.doc_id} | {doc.title} | {doc.kind} | {doc.pages_or_sections} | "
            f"{', '.join(doc.topics or [])} | `{doc.text_file.relative_to(ROOT)}` | "
            f"`{doc.table_file.relative_to(ROOT)}` | {infer_use_positions(doc.topics or [])} |"
        )
    (CACHE / "00_비공개_자료목록.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    summary = [
        "# 비공개 문헌별 핵심요약",
        "",
        "이 파일은 내부 로컬 분석용이다. 논문 본문에 활용할 때는 원문 문장을 복제하지 않고 연구 맥락에 맞게 재서술한다.",
        "",
    ]
    for doc in docs:
        summary.extend([
            f"## {doc.doc_id}. {doc.title}",
            "",
            f"- 형식: {doc.kind}",
            f"- 페이지/섹션 수: {doc.pages_or_sections}",
            f"- 주요 주제: {', '.join(doc.topics or [])}",
            f"- 핵심 활용 방향: {infer_core_note(doc)}",
            f"- 논문 반영 위치: {infer_use_positions(doc.topics or [])}",
            f"- 그림 후보: {format_candidates(doc.figure_candidates)}",
            f"- 표 후보: {format_candidates(doc.table_candidates)}",
            f"- 텍스트 캐시: `{doc.text_file.relative_to(ROOT)}`",
            f"- 표 캐시: `{doc.table_file.relative_to(ROOT)}`",
            "- 주의: 대외 공유 제한 자료이므로 직접 인용·그림 사용 전 반드시 사용자 승인 필요",
            "",
        ])
    (CACHE / "01_문헌별_핵심요약.md").write_text("\n".join(summary), encoding="utf-8")

    topic_lines = [
        "# 비공개 주제별 근거 인덱스",
        "",
        "민감자료의 주제별 활용 위치를 정리한다. 본 파일은 로컬 분석용이며 외부 공유 금지.",
        "",
    ]
    for topic in TOPIC_RULES:
        topic_lines.append(f"## {topic}\n")
        matched = [doc for doc in docs if doc.topics and topic in doc.topics]
        if not matched:
            topic_lines.append("- 관련 자료 없음\n")
        else:
            for doc in matched:
                topic_lines.append(f"- {doc.doc_id} `{doc.title}`: {infer_core_note(doc)}")
            topic_lines.append("")
    (CACHE / "02_주제별_근거인덱스.md").write_text("\n".join(topic_lines), encoding="utf-8")

    fig_lines = [
        "# 비공개 그림·표 후보 인덱스",
        "",
        "그림·표 후보만 정리한다. 원문 그림 복제는 사용자 승인 전 금지.",
        "",
        "| ID | 자료명 | 그림 후보 | 표 후보 | 비고 |",
        "|---|---|---|---|---|",
    ]
    for doc in docs:
        fig_lines.append(
            f"| {doc.doc_id} | {doc.title} | {format_candidates(doc.figure_candidates)} | "
            f"{format_candidates(doc.table_candidates)} | 원문 확인 후 재작성 권장 |"
        )
    (CACHE / "03_그림표_인덱스.md").write_text("\n".join(fig_lines) + "\n", encoding="utf-8")

    apply_lines = [
        "# 비공개 논문 반영 위치표",
        "",
        "| ID | 자료명 | 핵심 활용 방향 | 반영 위치 | 주의사항 |",
        "|---|---|---|---|---|",
    ]
    for doc in docs:
        apply_lines.append(
            f"| {doc.doc_id} | {doc.title} | {infer_core_note(doc)} | "
            f"{infer_use_positions(doc.topics or [])} | 직접 인용·그림 복제 금지, 논리 근거로 재서술 |"
        )
    (CACHE / "04_논문반영_위치표.md").write_text("\n".join(apply_lines) + "\n", encoding="utf-8")

    (CACHE / "README.md").write_text(
        "# private_research_cache 사용법\n\n"
        "이 폴더는 대외 공유 제한 자료의 로컬 분석 캐시이다.\n\n"
        "## 원칙\n\n"
        "- 외부 공유 금지\n"
        "- 원문 문장 복제 금지\n"
        "- 직접 인용, 그림 복제, 외부 제출물 포함은 사용자 승인 후 판단\n"
        "- 논문 본문에는 근거를 확인한 뒤 연구 맥락에 맞게 재서술\n\n"
        "## 사용 순서\n\n"
        "1. `01_문헌별_핵심요약.md` 확인\n"
        "2. `02_주제별_근거인덱스.md`에서 관련 주제 확인\n"
        "3. 필요한 경우 `text/`의 해당 페이지/섹션 확인\n"
        "4. 그림·표는 `03_그림표_인덱스.md`로 후보 위치만 확인하고, 원문 확인 후 재작성\n",
        encoding="utf-8",
    )

    (FIGURE_DIR / "README.md").write_text(
        "# 비공개 그림 캐시 안내\n\n"
        "원문 그림 이미지는 자동 저장하지 않았다. 그림 후보 위치만 인덱싱했다.\n"
        "논문에 필요한 그림은 원문 확인 후 새 그림으로 재작성한다.\n",
        encoding="utf-8",
    )


def main() -> None:
    ensure_dirs()
    docs: list[PrivateDoc] = []
    for index, path in enumerate(find_targets(), start=1):
        doc = PrivateDoc(
            doc_id=safe_stem(path, index),
            path=path,
            title=path.stem,
            kind=path.suffix.lower().lstrip("."),
        )
        print(f"[{index}] 비공개 자료 분석 중: {doc.kind}")
        if path.suffix.lower() == ".pdf":
            docs.append(extract_pdf(doc))
        elif path.suffix.lower() == ".hwpx":
            docs.append(extract_hwpx(doc))
        else:
            raise ValueError(f"지원하지 않는 비공개 자료 형식입니다: {path.suffix}")
    write_indexes(docs)
    print(f"완료: {CACHE}")


if __name__ == "__main__":
    main()
