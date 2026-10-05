#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MD → HWP 수식 전용 변환 스크립트
```latex ... ``` 블록을 찾아 LaTeX → MathML → 한글 수식으로 자동 삽입.
각 수식 앞에 레이블(파일명 + 번호) 삽입.
"""

import re
import sys
import tempfile
from pathlib import Path
from time import sleep

import latex2mathml.converter

try:
    from pyhwpx import Hwp
except ImportError:
    print("오류: pyhwpx가 설치되지 않았습니다.")
    sys.exit(1)

# ── 경로 ─────────────────────────────────────────────────────────────────────
BASE_DIR    = Path(r"C:\Users\shfmq\codexwork\AHP_AIP")
CHAPTER_DIR = BASE_DIR / "연구설계" / "01_논문_장별"
OUTPUT_PATH = BASE_DIR / "수식_모음.hwp"

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


def extract_latex_blocks(md_path: Path) -> list[str]:
    """MD 파일에서 ```latex ... ``` 블록의 LaTeX 수식 추출."""
    text = md_path.read_text(encoding="utf-8")
    pattern = re.compile(r'```latex\s*\n(.*?)```', re.DOTALL)
    return [m.group(1).strip() for m in pattern.finditer(text)]


def latex_to_mml_file(latex: str, tmp_dir: Path, idx: int) -> Path:
    """LaTeX 수식 → MathML 임시 파일 저장 후 경로 반환."""
    try:
        mml = latex2mathml.converter.convert(latex)
    except Exception as e:
        raise ValueError(f"LaTeX 변환 실패: {e}\n수식: {latex}")

    mml_path = tmp_dir / f"eq_{idx:04d}.mml"
    mml_path.write_text(mml, encoding="utf-8")
    return mml_path


def insert_label(hwp: Hwp, text: str):
    hwp.set_font(FaceName="바탕", Size=10, Bold=True)
    hwp.set_linespacing(200, "Percent")
    hwp.set_para(AlignType="Left")
    hwp.insert_text(text)
    hwp.BreakPara()
    hwp.set_font(Bold=False)


def main():
    print("한글 실행 중...")
    hwp = Hwp(new=True, visible=True)

    tmp_dir = Path(tempfile.mkdtemp(prefix="hwp_eq_"))
    total = 0
    fail = 0

    for md_name in MD_FILES:
        md_path = CHAPTER_DIR / md_name
        if not md_path.exists():
            print(f"  [없음] {md_name}")
            continue

        blocks = extract_latex_blocks(md_path)
        if not blocks:
            print(f"  [수식 없음] {md_name}")
            continue

        print(f"  {md_name}: {len(blocks)}개 수식")

        for eq_idx, latex in enumerate(blocks, start=1):
            label = f"[{md_name}] 수식 {eq_idx}"
            insert_label(hwp, label)

            # LaTeX 원문도 회색 참고용으로 삽입
            hwp.set_font(FaceName="Courier New", Size=9, Bold=False)
            hwp.insert_text(latex.replace("\n", " "))
            hwp.BreakPara()

            try:
                mml_path = latex_to_mml_file(latex, tmp_dir, total + 1)
                hwp.import_mathml(str(mml_path))
                sleep(0.3)
            except Exception as e:
                print(f"    [오류] {label}: {e}")
                hwp.set_font(FaceName="바탕", Size=10)
                hwp.insert_text(f"[수식 변환 실패: {e}]")
                fail += 1

            hwp.BreakPara()
            hwp.BreakPara()
            total += 1

    print(f"\n총 {total}개 수식 처리 (실패 {fail}개)")
    print(f"저장 중: {OUTPUT_PATH}")
    hwp.save_as(str(OUTPUT_PATH), format="HWP")
    print("완료!")

    # 임시 파일 정리
    for f in tmp_dir.glob("*.mml"):
        f.unlink()
    tmp_dir.rmdir()


if __name__ == "__main__":
    main()
