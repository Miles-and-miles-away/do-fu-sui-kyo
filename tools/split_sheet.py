#!/usr/bin/env python3
"""Cut a 2x3 expression sheet into the 6 named cells, ready for hand bg-removal.

For the robot opponent sheets (sub / plane / tank) whose flat backgrounds get removed by
hand (Instant Alpha) before the existing `sprites.py bake` + `frame` steps. The animals
already have transparent files, so they don't need this.

Each cell is fitted (aspect-preserved, centred) onto a 512x768 TRANSPARENT canvas — the same
2:3 card size as the animal art/_transparent/*.png — so once you knock out the painted
background the files match that format exactly and feed straight into bake/frame.

    python tools/split_sheet.py art/_sheets/sub_sprite.png   sub   --out art/_transparent
    python tools/split_sheet.py art/_sheets/plane_sprite.png plane --out art/_transparent
    python tools/split_sheet.py art/_sheets/tank_sprite.png  tank  --out art/_transparent

Self-check: python tools/split_sheet.py selftest   (needs Pillow)
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from PIL import Image

# Row-major, matching the sheet layout in docs/SPRITES.md (and sprites.py EXPRESSIONS).
EXPRESSIONS = ["neutral", "blink", "determined", "determined_blink", "smile", "cry"]
COLS, ROWS = 2, 3
SIZE = (512, 768)  # 2:3 card, same as sprites.py DEFAULT_SIZE


def split(sheet: Path, prefix: str, out_dir: Path, size: tuple[int, int] = SIZE) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    with Image.open(sheet) as im:
        im = im.convert("RGBA")
        w, h = im.size
        cw, ch = w // COLS, h // ROWS
        for idx, expr in enumerate(EXPRESSIONS):
            r, c = divmod(idx, COLS)
            cell = im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            # fit inside the 2:3 card, centred, transparent letterbox (painted bg untouched
            # in the cell — that's what you remove by hand next).
            scale = min(size[0] / cell.width, size[1] / cell.height)
            scaled = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.LANCZOS)
            canvas = Image.new("RGBA", size, (0, 0, 0, 0))
            canvas.alpha_composite(scaled, ((size[0] - scaled.width) // 2, (size[1] - scaled.height) // 2))
            dst = out_dir / f"{prefix}_{expr}.png"
            canvas.save(dst)
            written.append(dst)
    return written


def _selftest() -> None:
    # 6 cells, each painted a unique grey; assert each named file picks up its own cell.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sheet = Image.new("RGBA", (COLS * 100, ROWS * 100))
        for idx in range(len(EXPRESSIONS)):
            r, c = divmod(idx, COLS)
            for x in range(c * 100, c * 100 + 100):
                for y in range(r * 100, r * 100 + 100):
                    sheet.putpixel((x, y), (idx * 40, idx * 40, idx * 40, 255))
        sp = td / "s.png"
        sheet.save(sp)
        out = split(sp, "x", td)
        assert len(out) == len(EXPRESSIONS)
        for idx, p in enumerate(out):
            im = Image.open(p)
            assert im.size == SIZE, im.size
            assert im.getpixel((SIZE[0] // 2, SIZE[1] // 2)) == (idx * 40, idx * 40, idx * 40, 255), p.name
    print(f"selftest OK: {len(EXPRESSIONS)} cells split to the right names")


if __name__ == "__main__":
    if sys.argv[1:] == ["selftest"]:
        _selftest()
        raise SystemExit(0)
    ap = argparse.ArgumentParser(description="Split a 2x3 expression sheet into 6 named cells.")
    ap.add_argument("sheet", type=Path)
    ap.add_argument("prefix", help="file prefix, e.g. sub / plane / tank")
    ap.add_argument("--out", type=Path, default=Path("art/_transparent"))
    a = ap.parse_args()
    written = split(a.sheet, a.prefix, a.out)
    print(f"wrote {len(written)} → {a.out}/: " + ", ".join(p.name for p in written))
