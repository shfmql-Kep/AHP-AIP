from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    font_path = Path(r"C:\Windows\Fonts\malgunbd.ttf" if bold else r"C:\Windows\Fonts\malgun.ttf")
    return ImageFont.truetype(str(font_path), size)


def center_text(draw: ImageDraw.ImageDraw, x: float, y: float, text: str, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text((x - (bbox[2] - bbox[0]) / 2, y), text, font=font, fill=fill)


def main():
    out = Path("figures/generated/fig_utility_asset_management_market.png")
    out.parent.mkdir(parents=True, exist_ok=True)

    # Research and Markets 공개값:
    # 2024년 4.97, 2025년 5.51, 2029년 8.01 billion USD.
    # 2026~2028년은 보고서의 2025~2029 CAGR 9.8%를 적용하여 보간.
    years = list(range(2024, 2030))
    cagr = 0.098
    values = {
        2024: 4.97,
        2025: 5.51,
        2026: 5.51 * (1 + cagr),
        2027: 5.51 * (1 + cagr) ** 2,
        2028: 5.51 * (1 + cagr) ** 3,
        2029: 8.01,
    }

    width, height = 1700, 980
    img = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(img)

    navy = (8, 33, 73)
    teal = (0, 103, 132)
    teal_dark = (0, 82, 108)
    gray = (86, 92, 102)
    grid = (226, 231, 238)

    title_font = load_font(50, True)
    subtitle_font = load_font(27)
    axis_font = load_font(25)
    label_font = load_font(25, True)
    note_font = load_font(21)

    center_text(draw, width / 2, 48, "전력 유틸리티 자산관리 시스템 시장 규모 전망", title_font, navy)
    center_text(draw, width / 2, 112, "Utility Asset Management Market Size, 2024~2029 (USD Billion)", subtitle_font, gray)

    chart_left, chart_top = 150, 215
    chart_right, chart_bottom = 1535, 760
    chart_w = chart_right - chart_left
    chart_h = chart_bottom - chart_top
    max_y = 9.0

    # y축 격자
    for tick in [0, 2, 4, 6, 8]:
        y = chart_bottom - (tick / max_y) * chart_h
        draw.line((chart_left, y, chart_right, y), fill=grid, width=2)
        draw.text((chart_left - 55, y - 16), f"{tick}", font=axis_font, fill=gray)

    draw.line((chart_left, chart_bottom, chart_right, chart_bottom), fill=(170, 178, 190), width=3)
    draw.line((chart_left, chart_top, chart_left, chart_bottom), fill=(170, 178, 190), width=3)

    bar_area_w = chart_w / len(years)
    bar_w = 92
    for i, year in enumerate(years):
        x_center = chart_left + bar_area_w * (i + 0.5)
        value = values[year]
        y_top = chart_bottom - (value / max_y) * chart_h

        # 막대 그림자
        draw.rounded_rectangle(
            (x_center - bar_w / 2 + 8, y_top + 8, x_center + bar_w / 2 + 8, chart_bottom),
            radius=10,
            fill=(220, 225, 232),
        )
        draw.rounded_rectangle(
            (x_center - bar_w / 2, y_top, x_center + bar_w / 2, chart_bottom),
            radius=10,
            fill=teal_dark if year == 2029 else teal,
        )

        value_label = f"{value:.2f}"
        center_text(draw, x_center, y_top - 42, value_label, label_font, teal_dark)
        center_text(draw, x_center, chart_bottom + 25, str(year), axis_font, gray)

    draw.text((chart_left, chart_bottom + 92), "주: 2026~2028년은 2025~2029년 전망 CAGR 9.8%를 적용하여 산정.", font=note_font, fill=gray)
    draw.text((chart_left, chart_bottom + 128), "자료: Research and Markets, Utility Asset Management Global Market Report 2025를 바탕으로 본 연구 작성.", font=note_font, fill=gray)

    img.save(out, quality=96)


if __name__ == "__main__":
    main()
