from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[3]
CHAPTER_DIR = ROOT / "연구설계" / "01_논문_장별"
REFERENCE_FILE = CHAPTER_DIR / "07_참고문헌.md"


def main():
    used = set()
    for path in CHAPTER_DIR.glob("*.md"):
        if path.name == "07_참고문헌.md":
            continue
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"\[([0-9]+)\]", text):
            used.add(int(match.group(1)))

    ref_text = REFERENCE_FILE.read_text(encoding="utf-8")
    refs = {
        int(match.group(1))
        for match in re.finditer(r"^\[([0-9]+)\]", ref_text, re.MULTILINE)
    }

    print("used:", sorted(used))
    print("refs:", sorted(refs))
    print("missing_refs_for_used:", sorted(used - refs))
    print("unused_refs:", sorted(refs - used))


if __name__ == "__main__":
    main()
