from pathlib import Path
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[3]


def find_pdf(name_contains):
    for path in ROOT.rglob("*.pdf"):
        if name_contains in path.name:
            return path
    raise FileNotFoundError(name_contains)


def extract_tail(path, tail_pages=20):
    reader = PdfReader(str(path))
    pages = []
    for index in range(max(0, len(reader.pages) - tail_pages), len(reader.pages)):
        text = reader.pages[index].extract_text() or ""
        pages.append((index + 1, text))
    return len(reader.pages), pages


def main():
    out_dir = ROOT / "tmp" / "reference_extract"
    out_dir.mkdir(parents=True, exist_ok=True)
    targets = [
        ("논문초안", find_pdf("논문 초안")),
        ("박사논문예시2", find_pdf("박사논문 예시 2")),
    ]
    for label, path in targets:
        page_count, pages = extract_tail(path, 25)
        out = out_dir / f"{label}_tail_reference_text.txt"
        with out.open("w", encoding="utf-8") as f:
            f.write(f"FILE: {path}\n")
            f.write(f"PAGES: {page_count}\n\n")
            for page_no, text in pages:
                f.write(f"\n\n--- PAGE {page_no} ---\n")
                f.write(text)
        print(out)

    draft = find_pdf("논문 초안")
    reader = PdfReader(str(draft))
    hits = []
    for index, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        if "참고문헌" in text or "References" in text:
            hits.append((index + 1, text[:1000]))
    hit_out = out_dir / "논문초안_reference_hits.txt"
    with hit_out.open("w", encoding="utf-8") as f:
        for page_no, text in hits:
            f.write(f"\n--- PAGE {page_no} ---\n{text}\n")
    print(hit_out)


if __name__ == "__main__":
    main()
