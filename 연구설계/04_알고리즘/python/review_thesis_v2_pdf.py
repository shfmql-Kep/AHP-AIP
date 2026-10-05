from pathlib import Path
import re
from collections import Counter, defaultdict

import pdfplumber
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[3]
PDF = ROOT / "논문초안_v2.pdf"
WORK = ROOT / "tmp" / "review_v2"
PAGES_DIR = WORK / "pages"
OUT_DIR = ROOT / "연구설계" / "08_검토보고서" / "논문초안_v2"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def normalize_text(text: str) -> str:
    return (text or "").replace("\u00a0", " ").replace("\uf000", "")


def extract_pdf_text():
    pages = []
    with pdfplumber.open(str(PDF)) as pdf:
        for idx, page in enumerate(pdf.pages, start=1):
            text = normalize_text(page.extract_text(x_tolerance=1, y_tolerance=3) or "")
            pages.append((idx, text))
    return pages


def find_lines(pages, patterns):
    hits = []
    for page_no, text in pages:
        for line in text.splitlines():
            line2 = line.strip()
            if not line2:
                continue
            for pattern in patterns:
                if re.search(pattern, line2, flags=re.IGNORECASE):
                    hits.append((page_no, line2))
                    break
    return hits


def create_contact_sheets():
    image_paths = sorted(PAGES_DIR.glob("page-*.png"))
    if not image_paths:
        return []

    # 한 장에 12쪽씩 배치한다.
    sheets = []
    thumb_w = 310
    thumb_h = 438
    cols = 4
    rows = 3
    margin = 40
    gap = 26

    try:
        font = ImageFont.truetype("arial.ttf", 18)
        font_big = ImageFont.truetype("arial.ttf", 26)
    except Exception:
        font = None
        font_big = None

    for sheet_idx, start in enumerate(range(0, len(image_paths), cols * rows), start=1):
        chunk = image_paths[start : start + cols * rows]
        canvas_w = margin * 2 + cols * thumb_w + (cols - 1) * gap
        canvas_h = margin * 2 + 35 + rows * thumb_h + (rows - 1) * gap
        canvas = Image.new("RGB", (canvas_w, canvas_h), "white")
        draw = ImageDraw.Draw(canvas)
        draw.text((margin, 8), f"논문초안_v2 페이지 검토 시트 {sheet_idx}", fill=(0, 0, 0), font=font_big)
        for i, img_path in enumerate(chunk):
            row = i // cols
            col = i % cols
            x = margin + col * (thumb_w + gap)
            y = margin + 35 + row * (thumb_h + gap)
            img = Image.open(img_path).convert("RGB")
            img.thumbnail((thumb_w, thumb_h))
            canvas.paste(img, (x, y))
            page_no = int(re.search(r"-(\d+)\.png$", img_path.name).group(1))
            draw.rectangle([x, y, x + img.width, y + img.height], outline=(160, 160, 160), width=1)
            draw.text((x + 4, y + 4), f"p.{page_no}", fill=(180, 0, 0), font=font)
        out = OUT_DIR / f"contact_sheet_{sheet_idx:02d}.png"
        canvas.save(out)
        sheets.append(out)
    return sheets


def write_review_inputs():
    pages = extract_pdf_text()
    all_text = "\n\n".join(f"--- PAGE {p} ---\n{text}" for p, text in pages)
    (OUT_DIR / "논문초안_v2_전체텍스트추출.txt").write_text(all_text, encoding="utf-8")

    caption_patterns = [
        r"^(그림|표)\s*[0-9IVXGHA-Z가-힣.\-]+",
        r"^(Figure|Fig\.|Table)\s*[0-9IVXGHA-Z.\-]+",
    ]
    captions = find_lines(pages, caption_patterns)
    (OUT_DIR / "그림표_캡션_목록.txt").write_text(
        "\n".join(f"p.{p}: {line}" for p, line in captions), encoding="utf-8"
    )

    issue_patterns = {
        "방어적 문구": [
            r"본 연구는 .*개발하지",
            r"목적이 있지 않",
            r"사용하지 않",
            r"대체하기 위한 것이 아니",
            r"해석하기보다",
            r"한계가 있으나",
        ],
        "내부 개발 흔적": [
            r"Python",
            r"MATLAB",
            r"intlinprog",
            r"ga 함수",
            r"스크립트",
            r"시트",
            r"solver",
            r"random seed",
        ],
        "AI 문체 후보": [
            r"이를 통해",
            r"이에 따라",
            r"이러한",
            r"결국",
            r"다만",
            r"즉,",
            r"중요하다",
            r"필요하다",
        ],
        "용어 점검": [
            r"위험도",
            r"성능지표",
            r"PI_",
            r"Local PI",
            r"시범적용",
            r"직접 통합형",
            r"사전 통합",
            r"사후 통합",
        ],
    }

    issue_lines = []
    for group, patterns in issue_patterns.items():
        hits = find_lines(pages, patterns)
        issue_lines.append(f"\n## {group} ({len(hits)}건)\n")
        for page_no, line in hits[:250]:
            issue_lines.append(f"- p.{page_no}: {line}")
    (OUT_DIR / "자동점검_후보문장.txt").write_text("\n".join(issue_lines), encoding="utf-8")

    headings = []
    for page_no, text in pages:
        for line in text.splitlines():
            line = line.strip()
            if re.match(r"^(제\s*[0-9]+장|제\s*[0-9]+절|[0-9]+\.\s|[가-하]\.\s)", line):
                headings.append((page_no, line))
    (OUT_DIR / "목차성_제목_추출.txt").write_text(
        "\n".join(f"p.{p}: {line}" for p, line in headings), encoding="utf-8"
    )

    # 단어 빈도: 반복 표현 확인용
    tokens = ["본 연구", "이를 통해", "이러한", "다만", "따라서", "중요하다", "필요하다", "리스크", "위험도", "성능지표", "투자우선순위 지수"]
    counts = Counter()
    for _, text in pages:
        for token in tokens:
            counts[token] += text.count(token)
    (OUT_DIR / "반복표현_빈도.txt").write_text(
        "\n".join(f"{k}: {v}" for k, v in counts.most_common()), encoding="utf-8"
    )

    sheets = create_contact_sheets()
    return pages, captions, sheets


if __name__ == "__main__":
    pages, captions, sheets = write_review_inputs()
    print(f"pages={len(pages)}")
    print(f"captions={len(captions)}")
    print(f"contact_sheets={len(sheets)}")
    print(OUT_DIR)
