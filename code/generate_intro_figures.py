from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "figures" / "generated"
OUT.mkdir(parents=True, exist_ok=True)

FONT_REG = Path("C:/Windows/Fonts/NotoSansKR-VF.ttf")
FONT_BOLD = Path("C:/Windows/Fonts/malgunbd.ttf")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_BOLD if bold and FONT_BOLD.exists() else FONT_REG
    return ImageFont.truetype(str(path), size=size)


def rounded_box(draw: ImageDraw.ImageDraw, xy, fill, outline="#1f3b57", width=2, radius=24):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def centered_text(draw: ImageDraw.ImageDraw, box, text, fnt, fill="#111827", spacing=6):
    lines = text.split("\n")
    widths = [draw.textbbox((0, 0), line, font=fnt)[2] for line in lines]
    heights = [draw.textbbox((0, 0), line, font=fnt)[3] - draw.textbbox((0, 0), line, font=fnt)[1] for line in lines]
    total_h = sum(heights) + spacing * (len(lines) - 1)
    x1, y1, x2, y2 = box
    y = y1 + (y2 - y1 - total_h) / 2
    for line, w, h in zip(lines, widths, heights):
        draw.text((x1 + (x2 - x1 - w) / 2, y), line, font=fnt, fill=fill)
        y += h + spacing


def draw_arrow(draw: ImageDraw.ImageDraw, start, end, fill="#2f5f8f", width=5):
    draw.line([start, end], fill=fill, width=width)
    ex, ey = end
    sx, sy = start
    if ex >= sx:
        pts = [(ex, ey), (ex - 18, ey - 10), (ex - 18, ey + 10)]
    else:
        pts = [(ex, ey), (ex + 18, ey - 10), (ex + 18, ey + 10)]
    draw.polygon(pts, fill=fill)


def generate_am_evolution():
    img = Image.new("RGB", (1800, 620), "#ffffff")
    draw = ImageDraw.Draw(img)
    title_f = font(34, True)
    box_title_f = font(25, True)
    body_f = font(20)
    small_f = font(17)

    draw.text((70, 42), "전력설비 자산관리 방법론의 발전 단계", font=title_f, fill="#0f2742")
    draw.text((72, 90), "정비 중심 관리에서 투자 포트폴리오 의사결정으로 확장", font=body_f, fill="#44546a")

    boxes = [
        (80, 190, 390, 390, "TBM\n시간기반 정비", "일정 주기 중심\n점검·교체"),
        (460, 190, 770, 390, "CBM\n상태기반 정비", "상태정보 반영\n개별 설비 판단"),
        (840, 190, 1150, 390, "RBAM\n리스크 기반 관리", "PoF × CoF\n위험도 정량화"),
        (1220, 190, 1530, 390, "AIP\n자산투자계획", "비용·리스크·성과\n포트폴리오 최적화"),
    ]
    fills = ["#eaf2fb", "#e7f4ee", "#fff2d7", "#f0e8ff"]
    outlines = ["#2f5f8f", "#2f7d55", "#b87900", "#6e4bb8"]

    for i, (x1, y1, x2, y2, title, body) in enumerate(boxes):
        rounded_box(draw, (x1, y1, x2, y2), fills[i], outlines[i], 3, 28)
        centered_text(draw, (x1, y1 + 18, x2, y1 + 92), title, box_title_f, outlines[i])
        centered_text(draw, (x1 + 20, y1 + 105, x2 - 20, y2 - 18), body, body_f, "#1f2937")
        if i < len(boxes) - 1:
            draw_arrow(draw, (x2 + 22, (y1 + y2) // 2), (boxes[i + 1][0] - 22, (y1 + y2) // 2))

    rounded_box(draw, (80, 455, 1530, 545), "#f8fafc", "#b7c3d0", 2, 18)
    note = "본 연구의 위치: CNAIM 기반 PoF·Risk 산정 → 다기준 PI 산정 → 5개년 포트폴리오 최적화"
    centered_text(draw, (100, 455, 1510, 545), note, small_f, "#263747")
    img.save(OUT / "fig_am_evolution.png", quality=95)


def generate_paper_structure():
    img = Image.new("RGB", (1800, 760), "#ffffff")
    draw = ImageDraw.Draw(img)
    title_f = font(34, True)
    chapter_f = font(23, True)
    body_f = font(18)
    small_f = font(16)

    draw.text((70, 42), "논문의 구성", font=title_f, fill="#0f2742")
    draw.text((72, 90), "문제 정의에서 프레임워크 설계와 시뮬레이션 검증으로 이어지는 연구 흐름", font=body_f, fill="#44546a")

    chapters = [
        ("제1장\n서론", "연구 배경\n목적·범위"),
        ("제2장\n기술적 배경\n및 선행연구", "자산관리·AIP\n투자가치·MCDM"),
        ("제3장\n제안\n프레임워크", "PI 모델\n최적화 수리모형"),
        ("제4장\n시뮬레이션\n및 결과 분석", "투자가치·PI·통합 PI\n민감도 검증"),
        ("제5장\n결론", "연구 결과\n기여·한계"),
    ]
    x0, y0 = 70, 190
    w, h, gap = 285, 250, 55
    fills = ["#eaf2fb", "#e7f4ee", "#fff2d7", "#f0e8ff", "#fdecec"]
    outlines = ["#2f5f8f", "#2f7d55", "#b87900", "#6e4bb8", "#b84a4a"]

    centers = []
    for i, (title, body) in enumerate(chapters):
        x1 = x0 + i * (w + gap)
        y1 = y0
        x2, y2 = x1 + w, y1 + h
        rounded_box(draw, (x1, y1, x2, y2), fills[i], outlines[i], 3, 26)
        centered_text(draw, (x1 + 10, y1 + 24, x2 - 10, y1 + 120), title, chapter_f, outlines[i])
        draw.line((x1 + 34, y1 + 136, x2 - 34, y1 + 136), fill=outlines[i], width=2)
        centered_text(draw, (x1 + 18, y1 + 150, x2 - 18, y2 - 20), body, body_f, "#1f2937")
        centers.append((x2, (y1 + y2) // 2, x1, (y1 + y2) // 2))
        if i < len(chapters) - 1:
            draw_arrow(draw, (x2 + 12, (y1 + y2) // 2), (x2 + gap - 12, (y1 + y2) // 2))

    rounded_box(draw, (120, 515, 1680, 650), "#f8fafc", "#b7c3d0", 2, 20)
    bottom = "핵심 논리: 전력설비 투자 의사결정의 한계 → 다기준 성능지표(PI) → 포트폴리오 최적화 → 투자효과·강건성 검증"
    centered_text(draw, (150, 520, 1650, 605), bottom, small_f, "#263747")
    draw.text((150, 616), "※ 목차 그림은 원고 구성 이해를 돕기 위한 저자 작성 도식임.", font=small_f, fill="#6b7280")
    img.save(OUT / "fig_paper_structure.png", quality=95)


if __name__ == "__main__":
    generate_am_evolution()
    generate_paper_structure()
    print("서론 그림 2종 생성 완료")
