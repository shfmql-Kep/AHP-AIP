from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REF = ROOT / "연구설계" / "01_논문_장별" / "07_참고문헌.md"
INTEGRATED = ROOT / "연구설계" / "논문_통합본_최신.md"


def main():
    ref_text = REF.read_text(encoding="utf-8").strip()
    integrated_text = INTEGRATED.read_text(encoding="utf-8")
    start = integrated_text.index("# 참고문헌")
    end = integrated_text.index("# Abstract", start)
    updated = integrated_text[:start] + ref_text + "\n\n" + integrated_text[end:]
    INTEGRATED.write_text(updated, encoding="utf-8")
    print(INTEGRATED)


if __name__ == "__main__":
    main()
