#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MD → HTML 변환 스크립트
논문 장별 MD 파일을 각각 HTML로 변환한다.
수식: Pandoc MathML 렌더링 / 표: Pandoc markdown table / 코드블록: 그대로 출력
"""

import re
import subprocess
from pathlib import Path

BASE_DIR    = Path(r"C:\Users\shfmq\codexwork\AHP_AIP")
CHAPTER_DIR = BASE_DIR / "연구설계" / "01_논문_장별"
OUTPUT_DIR = BASE_DIR / "연구설계" / "html_장별"
PANDOC = BASE_DIR / "tools" / "pandoc-3.10" / "pandoc.exe"

MD_FILES = [
    "01_국문초록.md",
    "02_제1장_서론.md",
    "03_제2장_이론적_배경.md",
    "04_제3장_제안_방법론.md",
    "05_제4장_최적화시뮬레이션_결과분석.md",
    "06_제5장_결론.md",
    "07_참고문헌.md",
    "08_Abstract.md",
    "09_부록.md",
    "10_부록_설문지.md",
]

CSS = """
body {
    font-family: '바탕', 'Batang', serif;
    font-size: 11pt;
    line-height: 200%;
    margin: 35mm 30mm 25mm 35mm;
    color: #000;
}
h1 {
    font-family: 'HY견명조', 'HYGothic', serif;
    font-size: 16pt;
    text-align: center;
    font-weight: bold;
    margin-top: 2em;
    page-break-before: always;
}
h1:first-of-type { page-break-before: avoid; }
h2 { font-size: 13pt; font-weight: bold; margin-top: 1.5em; }
h3 { font-size: 12pt; font-weight: bold; margin-top: 1.2em; }
h4 { font-size: 11pt; font-weight: bold; margin-top: 1em; }
p  { text-align: justify; margin: 0.4em 0; }
table {
    border-collapse: collapse;
    width: 100%;
    margin: 1em 0;
    font-size: 10pt;
}
th, td {
    border: 1px solid #000;
    padding: 4px 8px;
    text-align: left;
    line-height: 160%;
}
th { background: #f0f0f0; font-weight: bold; }
img { max-width: 100%; display: block; margin: 0.5em auto; }
figcaption, p strong:first-child { text-align: center; font-size: 10pt; }
pre { font-family: 'Courier New', monospace; font-size: 9pt;
      background: #f8f8f8; padding: 8px; border: 1px solid #ddd; }
code { font-family: 'Courier New', monospace; font-size: 9pt; }
hr { border: none; border-top: 1px solid #ccc; margin: 1.5em 0; }
"""

def preprocess(text: str) -> str:
    """```latex ... ``` 블록을 MathJax $$ ... $$ 로 변환."""
    def to_display_math(m):
        latex = m.group(1).strip()
        return f"\n$$\n{latex}\n$$\n"

    text = re.sub(r'```latex\s*\n(.*?)```', to_display_math,
                  text, flags=re.DOTALL)
    return text


def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    if not PANDOC.exists():
        raise FileNotFoundError(f"Pandoc 실행 파일을 찾을 수 없습니다: {PANDOC}")

    for md_name in MD_FILES:
        md_path = CHAPTER_DIR / md_name
        if not md_path.exists():
            print(f"  [없음] {md_name}")
            continue

        raw = md_path.read_text(encoding="utf-8")
        raw = preprocess(raw)

        out_path = OUTPUT_DIR / md_name.replace(".md", ".html")
        tmp_md = OUTPUT_DIR / ("__tmp_" + md_name)
        tmp_css = OUTPUT_DIR / "__thesis_style.css"
        tmp_md.write_text(raw, encoding="utf-8")
        tmp_css.write_text(CSS, encoding="utf-8")

        subprocess.run(
            [
                str(PANDOC),
                str(tmp_md),
                "-f", "markdown-yaml_metadata_block+tex_math_dollars+raw_html",
                "-t", "html5",
                "--standalone",
                "--mathml",
                "--metadata", f"title={md_name.replace('.md', '')}",
                "--css", str(tmp_css),
                "-o", str(out_path),
            ],
            check=True,
            cwd=str(BASE_DIR),
        )
        tmp_md.unlink(missing_ok=True)
        print(f"  완료: {out_path.name}")

    (OUTPUT_DIR / "__thesis_style.css").unlink(missing_ok=True)
    print(f"\n저장 위치: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
