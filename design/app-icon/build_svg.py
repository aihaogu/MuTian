#!/usr/bin/env python3
"""Build the 木天 app icon masters (C · 四部) as self-contained SVGs."""
from pathlib import Path

OUT = Path(__file__).resolve().parent

INK = "#33261D"
WOOD = "#5E4230"
PAPER = "#F6F0E3"
TILE_TOP = "#F4EEE2"
TILE_BOTTOM = "#E9E0CF"
BOOKS = [  # 四库全书书衣：经绿、史红、子蓝、集灰
    ("#4D7A5B", "#3E6449"),
    ("#A8412F", "#8A3426"),
    ("#34598A", "#294771"),
    ("#7A756C", "#625E57"),
]

# macOS Big Sur+ grid: 824 px tile, 100 px inset, ~185 px corner radius.
TILE = '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#tile)"/>'

DEFS = f"""<defs>
  <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOTTOM}"/>
  </linearGradient>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="140%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/>
    <feOffset dy="12"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.28"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>"""

# 书阁屋顶：正脊 + 弧形屋面 + 起翘的檐角
RIDGE = f'<path d="M298 276 H726 L738 250 H286 Z" fill="{INK}"/>'
ROOF = f"""<path d="M150 356
         C 196 352 236 340 262 322
         C 300 296 324 282 340 270 H684
         C 700 282 724 296 762 322
         C 788 340 828 352 874 356
         C 862 374 840 384 812 384 H212
         C 184 384 162 374 150 356 Z" fill="{INK}"/>"""

BEAM = f'<rect x="232" y="384" width="560" height="22" fill="{WOOD}"/>'
BASE = (f'<rect x="206" y="790" width="612" height="26" rx="4" fill="{INK}"/>'
        f'<rect x="236" y="816" width="552" height="14" rx="3" fill="{WOOD}"/>')
BASE_SMALL = f'<rect x="206" y="790" width="612" height="34" rx="4" fill="{INK}"/>'

# 四册线装书铺满书阁，不写字：书衣四色即经史子集，空白题签点出线装书。
BOOK_W, BOOK_GAP = 124, 12
BOOK_X = [512 - 2 * BOOK_W - 1.5 * BOOK_GAP + i * (BOOK_W + BOOK_GAP) for i in range(4)]
BOOK_TOP, BOOK_BOTTOM = 424, 790
SPINE_W = 18
SLIP_X, SLIP_Y, SLIP_W, SLIP_H = 16, 26, 44, 136


def book(x: float, cover: str, dark: str) -> str:
    """线装书正面：装订在右，题签在左上。"""
    h = BOOK_BOTTOM - BOOK_TOP
    return (f'<rect x="{x}" y="{BOOK_TOP}" width="{BOOK_W}" height="{h}" rx="4" fill="{cover}"/>'
            f'<rect x="{x + BOOK_W - SPINE_W}" y="{BOOK_TOP}" width="{SPINE_W}" height="{h}" fill="{dark}"/>'
            f'<rect x="{x + SLIP_X}" y="{BOOK_TOP + SLIP_Y}" width="{SLIP_W}" height="{SLIP_H}" rx="3" fill="{PAPER}"/>')


def svg(body: str, title: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" '
            f'role="img" aria-label="{title}">\n<title>{title}</title>\n{DEFS}\n'
            f'<g filter="url(#drop)">{TILE}</g>\n<g transform="translate(0 -24)">\n{body}\n</g>\n</svg>\n')


books = [book(x, c, d) for x, (c, d) in zip(BOOK_X, BOOKS)]
full = "\n".join([RIDGE, ROOF, BEAM, *books, BASE])
small = "\n".join([ROOF, BEAM, *books, BASE_SMALL])  # 64 px 及以下：去掉正脊，台基合成一条

(OUT / "mutian-icon.svg").write_text(svg(full, "木天"), encoding="utf-8")
(OUT / "mutian-icon-small.svg").write_text(svg(small, "木天"), encoding="utf-8")
print("ok")
