"""
논문_통합본.md → HWP 변환 스크립트
=====================================
pyhwpx(한글 COM) 기반으로 Markdown을 HWP로 변환한다.

변환 규칙:
  # 제목      → 개요 1 (16pt 굵게, 가운데)
  ## 절       → 개요 2 (14pt 굵게)
  ### 소절    → 개요 3 (13pt 굵게)
  #### 소소절 → 개요 4 (12pt 굵게)
  | 표 |      → HWP 표
  ```코드```  → 코드 블록 (고정폭)
  > 인용      → 들여쓰기 본문
  ---         → 단락 구분
  본문        → 함초롬바탕 10pt, 줄간격 180%

수식($...$): LaTeX 기호를 유니코드 텍스트로 변환
수동 보완 권장: 복잡한 수식, 그림
"""

import re, sys
from pathlib import Path
from pyhwpx import Hwp

BASE = Path(__file__).resolve().parent.parent
MD   = BASE / "논문_통합본.md"
OUT  = BASE / "논문_AHP_AIP.hwp"

FACE   = "함초롬바탕"
FACE_C = "함초롬돋움"     # 코드용 고정폭

# ── LaTeX → 유니코드 ──────────────────────────────────────────────────
LATEX_MAP = {
    r'\lambda':'λ', r'\Lambda':'Λ', r'\alpha':'α', r'\beta':'β',
    r'\gamma':'γ',  r'\delta':'δ',  r'\sigma':'σ', r'\Sigma':'Σ',
    r'\mu':'μ',     r'\pi':'π',     r'\theta':'θ', r'\Theta':'Θ',
    r'\omega':'ω',  r'\Omega':'Ω',  r'\phi':'φ',   r'\psi':'ψ',
    r'\rho':'ρ',    r'\tau':'τ',    r'\xi':'ξ',    r'\eta':'η',
    r'\epsilon':'ε',r'\zeta':'ζ',   r'\infty':'∞', r'\partial':'∂',
    r'\cdot':'·',   r'\times':'×',  r'\div':'÷',   r'\pm':'±',
    r'\leq':'≤',    r'\geq':'≥',    r'\neq':'≠',   r'\approx':'≈',
    r'\equiv':'≡',  r'\sim':'∼',    r'\in':'∈',    r'\notin':'∉',
    r'\subset':'⊂', r'\supset':'⊃', r'\cup':'∪',   r'\cap':'∩',
    r'\forall':'∀', r'\exists':'∃',
    r'\rightarrow':'→', r'\leftarrow':'←',
    r'\Rightarrow':'⇒', r'\Leftarrow':'⇐',
    r'\leftrightarrow':'↔',
    r'\sum':'Σ',   r'\prod':'Π',  r'\int':'∫',  r'\sqrt':'√',
    r'\frac':'/',  r'\binom':'C', r'\cdots':'···', r'\ldots':'…',
    r'\quad':'  ', r'\qquad':'   ',
    r'\text':'',   r'\mathrm':'', r'\mathbf':'', r'\mathit':'',
    r'\left':'',   r'\right':'',  r'\hat':'',    r'\bar':'',
    r'\tilde':'',  r'\vec':'',    r'\overline':'',
}

def clean_latex(txt: str) -> str:
    for k, v in LATEX_MAP.items():
        txt = txt.replace(k, v)
    txt = re.sub(r'\{([^{}]*)\}', r'\1', txt)
    txt = re.sub(r'\{([^{}]*)\}', r'\1', txt)
    txt = re.sub(r'\^(\{[^}]+\}|\S)', lambda m: '^'+m.group(1).strip('{}'), txt)
    txt = re.sub(r'_(\{[^}]+\}|\S)',  lambda m: '_'+m.group(1).strip('{}'), txt)
    return txt.strip()


def strip_md(txt: str) -> str:
    """Markdown 인라인 기호 제거"""
    txt = re.sub(r'\$\$([^$]+)\$\$', lambda m: clean_latex(m.group(1)), txt)
    txt = re.sub(r'\$([^$\n]+)\$',   lambda m: clean_latex(m.group(1)), txt)
    txt = re.sub(r'\*\*(.+?)\*\*', r'\1', txt)
    txt = re.sub(r'__(.+?)__',     r'\1', txt)
    txt = re.sub(r'\*(.+?)\*',     r'\1', txt)
    txt = re.sub(r'`([^`]+)`',     r'[\1]', txt)
    txt = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', txt)
    txt = re.sub(r'!\[(.+?)\]\(.+?\)', r'[그림: \1]', txt)
    txt = re.sub(r'<!--.*?-->', '', txt, flags=re.DOTALL)
    return txt.strip()


def parse_table(buf: list) -> list:
    rows = []
    for line in buf:
        if re.match(r'^\s*\|[-:| ]+\|\s*$', line):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if any(cells):
            rows.append([strip_md(c) for c in cells])
    return rows


# ── 한글 문서 작성 클래스 ─────────────────────────────────────────────
class HwpWriter:
    def __init__(self, hwp: Hwp):
        self.h = hwp
        self._last_style = None

    def _font(self, face: str, size_pt: int, bold: bool = False):
        self.h.set_font(FaceName=face, Size=size_pt * 100,
                        Bold=bold, Italic=False)

    def _para(self, align: str = 'justify', linespace: int = 180,
              indent: int = 0):
        self.h.set_linespacing(linespace, method='Percent')
        if align == 'center':
            self.h.ParagraphShapeAlignCenter()
        elif align == 'left':
            self.h.ParagraphShapeAlignLeft()
        else:
            self.h.ParagraphShapeAlignJustify()

    # ── 스타일 별 삽입 ──────────────────────────────────────────────
    def heading(self, text: str, level: int):
        cfg = {
            1: (16, 'center', 160, '개요 1'),
            2: (14, 'left',   160, '개요 2'),
            3: (13, 'left',   160, '개요 3'),
            4: (12, 'left',   160, '개요 4'),
        }.get(level, (11, 'left', 160, '개요 5'))

        size, align, ls, style = cfg
        self.h.set_style(style)
        self._font(FACE, size, bold=True)
        self._para(align, ls)
        self.h.insert_text(strip_md(text))
        self.h.BreakPara()

    def body(self, text: str):
        self.h.set_style('본문')
        self._font(FACE, 10)
        self._para('justify', 180)
        self.h.insert_text(text)
        self.h.BreakPara()

    def code_block(self, lines: list):
        for ln in lines:
            self.h.set_style('본문')
            self._font(FACE_C, 9)
            self._para('left', 150)
            self.h.insert_text(ln if ln else ' ')
            self.h.BreakPara()
        # 본문으로 복귀
        self.h.set_style('본문')
        self._font(FACE, 10)
        self._para('justify', 180)

    def quote(self, text: str):
        self.h.set_style('본문')
        self._font(FACE, 10)
        self._para('left', 160)
        self.h.ParagraphShapeIncreaseLeftMargin()
        self.h.insert_text(text)
        self.h.BreakPara()
        self.h.ParagraphShapeDecreaseLeftMargin()

    def table(self, rows: list):
        if not rows:
            return
        ncols = max(len(r) for r in rows)
        nrows = len(rows)
        if ncols < 1 or nrows < 1:
            return

        try:
            self.h.create_table(nrows, ncols)
        except Exception as e:
            print(f"    [표 생성 실패, 텍스트 대체]: {e}")
            for row in rows:
                self.body(' | '.join(row))
            return

        for r_idx, row in enumerate(rows):
            for c_idx in range(ncols):
                if c_idx > 0:
                    self.h.TableRightCell()
                cell = row[c_idx] if c_idx < len(row) else ''
                bold = (r_idx == 0)
                self._font(FACE, 9, bold=bold)
                self.h.set_linespacing(160, method='Percent')
                self.h.TableCellAlignCenterCenter()
                if cell:
                    self.h.insert_text(cell)
            if r_idx < nrows - 1:
                self.h.TableLowerCell()
                self.h.TableColBegin()

        # 표 바깥으로 이동 (다음 단락)
        self.h.MoveNextParaBegin()
        self.h.set_style('본문')
        self._font(FACE, 10)
        self._para('justify', 180)

    def blank(self):
        self.h.set_style('본문')
        self._font(FACE, 10)
        self.h.BreakPara()

    def hrule(self):
        self.blank()
        self.blank()


# ── 변환 메인 ─────────────────────────────────────────────────────────
def convert(md_path: Path, out_path: Path):
    lines = md_path.read_text(encoding='utf-8').splitlines()
    total = len(lines)

    print("=== 논문 HWP 변환 시작 ===")
    hwp = Hwp(new=True, visible=False)
    wr  = HwpWriter(hwp)

    # 페이지 기본 설정: A4, 여백
    # set_pagedef는 pset(HParameterSet) 방식 → 대안으로 기본 설정 유지
    # (한글 기본 A4 설정이 이미 적용되어 있음)

    i        = 0
    in_code  = False
    code_buf = []
    in_table = False
    tbl_buf  = []

    while i < total:
        raw  = lines[i]
        line = raw.rstrip()
        i   += 1

        if i % 300 == 0:
            pct = 100 * i // total
            print(f"  {i}/{total}줄 ({pct}%) 처리 중...")

        # HTML 주석 블록 통째로 스킵
        stripped = line.strip()
        if stripped.startswith('<!--'):
            if '-->' not in stripped:
                while i < total and '-->' not in lines[i]:
                    i += 1
                i += 1
            continue

        # ── 코드 블록 ─────────────────────────────────────────────
        if stripped.startswith('```'):
            if not in_code:
                in_code  = True
                code_buf = []
            else:
                wr.code_block(code_buf)
                in_code  = False
                code_buf = []
            continue
        if in_code:
            code_buf.append(line)
            continue

        # ── 표 ────────────────────────────────────────────────────
        if stripped.startswith('|') and stripped.endswith('|'):
            if not in_table:
                in_table = True
                tbl_buf  = []
            tbl_buf.append(line)
            continue
        if in_table:
            wr.table(parse_table(tbl_buf))
            in_table = False
            tbl_buf  = []
            i -= 1   # 현재 줄 재처리
            continue

        # ── 제목 ──────────────────────────────────────────────────
        m = re.match(r'^(#{1,4})\s+(.+)', line)
        if m:
            wr.heading(m.group(2), len(m.group(1)))
            continue

        # ── 수평선 ────────────────────────────────────────────────
        if re.match(r'^-{3,}\s*$', line) or re.match(r'^={3,}\s*$', line):
            wr.hrule()
            continue

        # ── 인용 ──────────────────────────────────────────────────
        if stripped.startswith('>'):
            wr.quote(strip_md(stripped.lstrip('> ').strip()))
            continue

        # ── 빈 줄 ─────────────────────────────────────────────────
        if not stripped:
            wr.blank()
            continue

        # ── 본문 ──────────────────────────────────────────────────
        wr.body(strip_md(line))

    # 잔여 버퍼 처리
    if in_table and tbl_buf:
        wr.table(parse_table(tbl_buf))
    if in_code and code_buf:
        wr.code_block(code_buf)

    print("  저장 중...")
    hwp.save_as(str(out_path))
    hwp.quit()
    print(f"\n완료: {out_path}")


if __name__ == '__main__':
    convert(MD, OUT)
