#!/usr/bin/env python3
"""Sprite tooling for the 18 card faces (docs/SPRITES.md).

One file, four jobs:
  placeholders  generate 18 consistent placeholder faces (so nothing is blank pre-art)
  slice         cut a 2x3 expression sheet (nano banana output) into the 6 named files
  check         validate a folder: all 18 present, identical size, 2:3 aspect, RGBA
  normalize     force all to one identical 2:3 size (letterboxed, no distortion)

2x3 sheet layout (matches docs/SPRITES.md prompts), row-major:
  row1 = neutral, blink ; row2 = determined, determined_blink ; row3 = smile, cry.
Cells need NOT be 2:3 — slice fits each onto the 2:3 card, padding with the cell's own
background colour, so square-ish grid cells aren't stretched.

The naming convention lives HERE and is the single source docs/SPRITES.md points at:
  <critter>_<expression>.png  →  fish/bird/dino × 6 expressions  = 18 files.

Run the self-check (ponytail: the one runnable check this leaves behind):
  python tools/sprites.py selftest
Needs Pillow (environment.yml ships it; or `pip install pillow`).
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# fish=WATER, bird=SKY, dino=EARTH — order matches GameState.Type / GameRoot.frames_*.
CRITTERS = ["fish", "bird", "dino"]
# Canonical order — same in the GRID (row-major), GameRoot.frames_*, and docs/SPRITES.md §8.
# blink = neutral eyes-closed; determined_blink = determined eyes-closed (shown while held).
EXPRESSIONS = ["neutral", "blink", "determined", "determined_blink", "smile", "cry"]
GRID_COLS, GRID_ROWS = 2, 3  # `slice` sheet layout; COLS*ROWS must equal len(EXPRESSIONS)
# Solid card background painted behind each (ideally transparent) character, per critter.
# Override per run with --bg "#rrggbb". One uniform colour per card = no padding mismatch.
CARD_BG = {
    "fish": (176, 223, 227, 255),  # soft aqua
    "bird": (188, 214, 240, 255),  # pale sky-blue
    "dino": (191, 216, 182, 255),  # soft sage-green
}
DEFAULT_SIZE = (512, 768)  # 2:3 portrait, matching the Card.tscn quad (0.1 × 0.15 m)
ASPECT = 2 / 3

# Per-critter palette: (background, head, ink). Placeholders only — real art replaces these.
PALETTE = {
    "fish": ((150, 200, 225), (95, 160, 205), (20, 45, 65)),
    "bird": ((238, 225, 150), (240, 180, 70), (80, 50, 10)),
    "dino": ((175, 210, 165), (90, 160, 95), (25, 55, 30)),
}


def expected_names() -> list[str]:
    return [f"{c}_{e}.png" for c in CRITTERS for e in EXPRESSIONS]


# ── placeholders ─────────────────────────────────────────────────────────────
def _draw_face(critter: str, expr: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    bg, head, ink = PALETTE[critter]
    img = Image.new("RGBA", size, bg + (255,))  # fully opaque → renders even under alpha-scissor
    d = ImageDraw.Draw(img)

    # Head + eyes + mouth share IDENTICAL geometry across all 4 frames — only the eye/mouth
    # shapes change. That's what keeps blink/smile from "jumping" (NFR7), by construction.
    cx, cy, r = w // 2, int(h * 0.43), int(w * 0.40)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=head + (255,), outline=ink + (255,), width=6)

    closed = expr in ("blink", "determined_blink")  # eyes-closed frames
    eye_dx, eye_y, eye_r = int(w * 0.16), int(h * 0.38), int(w * 0.055)
    for ex in (cx - eye_dx, cx + eye_dx):
        if closed:  # closed eyes = horizontal bars
            d.line((ex - eye_r, eye_y, ex + eye_r, eye_y), fill=ink + (255,), width=10)
        else:
            d.ellipse((ex - eye_r, eye_y - eye_r, ex + eye_r, eye_y + eye_r), fill=ink + (255,))
        if expr == "cry":  # a tear under each eye
            tx, ty = ex, eye_y + int(h * 0.05)
            d.ellipse((tx - 9, ty - 14, tx + 9, ty + 14), fill=(120, 190, 240, 255))

    if expr in ("determined", "determined_blink"):  # angled focused brows (inner end lower)
        by, drop = eye_y - int(h * 0.06), 18
        d.line((cx - eye_dx - eye_r, by, cx - eye_dx + eye_r, by + drop), fill=ink + (255,), width=11)
        d.line((cx + eye_dx - eye_r, by + drop, cx + eye_dx + eye_r, by), fill=ink + (255,), width=11)

    mx, my, mw = cx, int(h * 0.55), int(w * 0.22)
    mbox = (mx - mw, my - mw, mx + mw, my + mw)
    if expr == "smile":
        d.arc(mbox, 0, 180, fill=ink + (255,), width=12)  # U = happy
    elif expr == "cry":
        d.arc((mbox[0], mbox[1] + mw, mbox[2], mbox[3] + mw), 180, 360, fill=ink + (255,), width=12)
    elif expr in ("determined", "determined_blink"):  # firm set mouth
        d.line((mx - mw, my, mx + mw, my), fill=ink + (255,), width=14)
    else:  # neutral / blink — small straight mouth
        d.line((mx - mw // 2, my, mx + mw // 2, my), fill=ink + (255,), width=10)

    # Label so placeholders are obviously placeholders and tell-apart-able in-headset.
    try:
        font = ImageFont.load_default(size=46)
    except TypeError:  # Pillow < 10.1 has no size arg
        font = ImageFont.load_default()
    label = f"{critter.upper()} · {expr}"
    tb = d.textbbox((0, 0), label, font=font)
    d.text(((w - (tb[2] - tb[0])) // 2, int(h * 0.88)), label, fill=ink + (255,), font=font)
    return img


def generate_placeholders(out_dir: Path, size: tuple[int, int] = DEFAULT_SIZE) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for c in CRITTERS:
        for e in EXPRESSIONS:
            p = out_dir / f"{c}_{e}.png"
            _draw_face(c, e, size).save(p)
            written.append(p)
    return written


# ── slice (GRID_COLS×GRID_ROWS sheet → named files) ──────────────────────────
def _fit(tile: Image.Image, size: tuple[int, int], bg: tuple) -> Image.Image:
    # Scale `tile` to fit INSIDE `size` preserving aspect, then composite onto a solid `bg`
    # card colour. Made for transparent character art (bg shows around the critter) — every
    # card gets the exact same background, so there's no padding-colour mismatch. Opaque art
    # still works (it just covers the bg), but its own baked background carries through.
    tw, th = tile.size
    scale = min(size[0] / tw, size[1] / th)
    scaled = tile.resize((max(1, round(tw * scale)), max(1, round(th * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", size, bg)
    canvas.paste(scaled, ((size[0] - scaled.width) // 2, (size[1] - scaled.height) // 2), scaled)
    return canvas


# Cells are read row-major into EXPRESSIONS, matching the generation prompt in docs/SPRITES.md.
def slice_sheet(
    sheet: Path,
    critter: str,
    out_dir: Path,
    size: tuple[int, int] = DEFAULT_SIZE,
    inset: int = 0,
    bg: tuple = None,
) -> list[Path]:
    if critter not in CRITTERS:
        raise SystemExit(f"unknown critter {critter!r}; expected one of {CRITTERS}")
    card_bg = bg if bg else CARD_BG.get(critter, (210, 210, 215, 255))
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    with Image.open(sheet) as im:
        im = im.convert("RGBA")
        w, h = im.size
        cw, ch = w // GRID_COLS, h // GRID_ROWS
        for idx, expr in enumerate(EXPRESSIONS):
            r, c = divmod(idx, GRID_COLS)
            # inset trims px off each INTERIOR cut edge — a guard for sheets with a faint
            # seam between cells (AI grids sometimes have one). 0 = exact grid-line cut.
            box = (
                c * cw + (inset if c > 0 else 0),
                r * ch + (inset if r > 0 else 0),
                (c + 1) * cw - (inset if c < GRID_COLS - 1 else 0),
                (r + 1) * ch - (inset if r < GRID_ROWS - 1 else 0),
            )
            tile = _fit(im.crop(box), size, card_bg)
            dst = out_dir / f"{critter}_{expr}.png"
            tile.save(dst)
            written.append(dst)
    return written


# ── check ────────────────────────────────────────────────────────────────────
def check(folder: Path) -> tuple[bool, list[str]]:
    problems: list[str] = []
    present = {p.name for p in folder.glob("*.png")}
    expected = set(expected_names())

    missing = sorted(expected - present)
    if missing:
        problems.append(f"missing {len(missing)}: {', '.join(missing)}")
    extra = sorted(present - expected)
    if extra:
        problems.append(f"unexpected (not auto-validated): {', '.join(extra)}")

    sizes: set[tuple[int, int]] = set()
    for name in sorted(expected & present):
        with Image.open(folder / name) as im:
            sizes.add(im.size)
            if im.mode != "RGBA":
                problems.append(f"{name}: mode {im.mode}, want RGBA")
            if abs((im.size[0] / im.size[1]) - ASPECT) > 0.01:
                problems.append(f"{name}: aspect {im.size[0]}x{im.size[1]} is not 2:3")
    if len(sizes) > 1:
        problems.append(f"sizes differ across frames: {sorted(sizes)} (must be identical, NFR7)")

    ok = not missing and len(sizes) <= 1 and not any("mode" in p or "aspect" in p for p in problems)
    return ok, problems


# ── normalize ────────────────────────────────────────────────────────────────
def normalize(in_dir: Path, out_dir: Path, size: tuple[int, int] = DEFAULT_SIZE) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for name in expected_names():
        src = in_dir / name
        if not src.exists():
            continue
        with Image.open(src) as im:
            im = im.convert("RGBA")
            im.thumbnail(size, Image.LANCZOS)  # fit inside target, keep aspect (no distortion)
            canvas = Image.new("RGBA", size, (0, 0, 0, 0))  # transparent letterbox
            canvas.paste(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2), im)
            dst = out_dir / name
            canvas.save(dst)
            written.append(dst)
    return written


# ── cli ──────────────────────────────────────────────────────────────────────
def _parse_size(s: str) -> tuple[int, int]:
    w, h = (int(x) for x in s.lower().split("x"))
    return w, h


def _parse_color(s: str) -> tuple:
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Card-face sprite tooling (docs/SPRITES.md).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("placeholders", help="generate the 18 placeholder faces")
    p.add_argument("--out", type=Path, default=Path("art"))
    p.add_argument("--size", type=_parse_size, default=DEFAULT_SIZE)

    p = sub.add_parser("slice", help="cut a 3x2 expression sheet into the 6 named files")
    p.add_argument("sheet", type=Path)
    p.add_argument("critter", choices=CRITTERS)
    p.add_argument("--out", type=Path, default=Path("art"))
    p.add_argument("--size", type=_parse_size, default=DEFAULT_SIZE)
    p.add_argument("--inset", type=int, default=0, help="trim N px off each interior cut (seam guard)")
    p.add_argument("--bg", type=_parse_color, default=None, help='card background "#rrggbb" (else per-critter default)')

    p = sub.add_parser("check", help="validate a folder of 18 faces; exit 1 on any problem")
    p.add_argument("dir", type=Path)

    p = sub.add_parser("normalize", help="force all to one identical 2:3 size")
    p.add_argument("dir", type=Path)
    p.add_argument("--out", type=Path, default=Path("art_normalized"))
    p.add_argument("--size", type=_parse_size, default=DEFAULT_SIZE)

    sub.add_parser("selftest", help="generate placeholders to a temp dir and check them")

    args = ap.parse_args(argv)

    if args.cmd == "placeholders":
        written = generate_placeholders(args.out, args.size)
        print(f"wrote {len(written)} placeholders to {args.out}/")
        ok, problems = check(args.out)
        print("check: OK" if ok else "check FAILED:\n  " + "\n  ".join(problems))
        return 0 if ok else 1

    if args.cmd == "slice":
        written = slice_sheet(args.sheet, args.critter, args.out, args.size, args.inset, args.bg)
        print(f"sliced {args.sheet} → {args.out}/: " + ", ".join(p.name for p in written))
        return 0

    if args.cmd == "check":
        ok, problems = check(args.dir)
        n = len(expected_names())
        print(f"{args.dir}: " + (f"OK — {n} consistent 2:3 RGBA frames" if ok else "PROBLEMS:"))
        for pr in problems:
            print("  -", pr)
        return 0 if ok else 1

    if args.cmd == "normalize":
        written = normalize(args.dir, args.out, args.size)
        print(f"normalized {len(written)} → {args.out}/ at {args.size[0]}x{args.size[1]}")
        return 0

    if args.cmd == "selftest":
        with tempfile.TemporaryDirectory() as td:
            generate_placeholders(Path(td))
            ok, problems = check(Path(td))
            assert ok, f"selftest failed: {problems}"
            assert len(list(Path(td).glob("*.png"))) == len(expected_names())
        print(f"selftest OK: {len(expected_names())} placeholders generated and validated")
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
