# 土風水競 — Card face sprite spec

The 12 card faces (R5, R8, NFR7, T20). Companion to `docs/FSD.md` (requirements) and
`docs/ASSETS.md §5` (asset manifest). Tooling: `tools/sprites.py` (generate / check / normalize).

Placeholders already exist in `art/` so faces aren't blank — replace them with real art at the
**same names, same size**, run `python tools/sprites.py check art`, re-import. Nothing else changes.

---

## 1. Inventory — exactly 12 files

3 critters × 4 expressions. Filenames (the convention lives in `tools/sprites.py`):

```
fish_neutral.png  fish_blink.png  fish_smile.png  fish_cry.png      # WATER (0)
bird_neutral.png  bird_blink.png  bird_smile.png  bird_cry.png      # SKY   (1)
dino_neutral.png  dino_blink.png  dino_smile.png  dino_cry.png      # EARTH (2)
```

`fish→WATER, bird→SKY, dino→EARTH` matches `GameState.Type` / `GameRoot.frames_*`.

## 2. Format

- **PNG, RGBA.**
- **2:3 portrait** to match the card mesh (`Card.tscn` quad is 0.1 × 0.15 m). Use **512 × 768**
  (or any 2:3, e.g. 1024 × 1536). A square image gets vertically stretched on the card.
  *(Prefer square art? Say so and the quad changes to square instead.)*
- **All 12 identical dimensions** — non-negotiable (NFR7). `tools/sprites.py check` enforces it.
- Mipmaps will be off, so power-of-two isn't needed.

## 3. The #1 rule — framing consistency (NFR7)

Across all 12, the head sits at the **same position, scale, and baseline**. Between a critter's
4 frames, **only the face features change** (eyes, mouth, tears) — the head outline is identical.
If the head shifts/resizes between frames, blink/smile/cry will visibly *jump*.

How to guarantee it: draw **neutral as the master**, then make blink/smile/cry by editing only
the eyes/mouth on a copy, onion-skinned over neutral. Don't redraw the head.

## 4. Per-expression intent

| Frame | Eyes | Mouth | When shown |
|---|---|---|---|
| **neutral** | open | calm/small | resting (R6) |
| **blink** | **closed** (only the eyes differ from neutral) | same as neutral | ~150 ms every 3–4.5 s (R6) |
| **smile** | open, bright | big upturn | round winner (R7) |
| **cry** | open + tears | downturn | round loser (R7) |

## 5. Background — pick one, use for all 12

- **(A, recommended) Opaque solid background** filling the 2:3 frame (looks like a printed card).
  No alpha artifacts, cheapest on Quest. The placeholders use this. Works as-is, **but** for real
  opaque art also switch the card material to `TRANSPARENCY_DISABLED` (currently `ALPHA_SCISSOR`
  in `Card.tscn` → sub-resource `transparency = 0`) — opaque art renders fine either way, this is
  just a tidy/perf tweak.
- **(B) Transparent background** (critter floats on the card mesh). Keep edges **crisp/hard** —
  soft anti-aliased edges halo under `ALPHA_SCISSOR`. Leave the material as-is (`transparency = 2`).

## 6. Style

Cute, front-facing, **bold flat shapes** (SVG/block-ish, matching the room aesthetic). High
contrast, readable at arm's length in VR — not fine detail. Consistency over polish.

## 7. Godot import settings (F4 — or faces blur/halo on device)

Per file (or set once and apply to all 12 via a preset):

- Compress Mode = **Lossless** (not VRAM)
- **Detect 3D → Compress To = Disabled**
- Mipmaps = **off**
- Filter = **Linear** (or Nearest for pixel art) — the *same* on all 12
- Identical settings across all 12 (NFR7).

## 8. Assigning in Godot

After import, select **GameRoot** in `main.tscn` and fill the three arrays **in order
`[neutral, blink, smile, cry]`**:

- `frames_water` ← fish_neutral, fish_blink, fish_smile, fish_cry
- `frames_sky`   ← bird_neutral, bird_blink, bird_smile, bird_cry
- `frames_earth` ← dino_neutral, dino_blink, dino_smile, dino_cry

GameRoot is the single source of frames — the robot pulls from the same place, so nothing is
assigned twice.

## 9. Process

1. Lock style + the 3 critter designs.
2. Draw each **neutral master** at final canvas size.
3. Derive blink/smile/cry by editing only the face, onion-skinned over neutral.
4. Export all 12 at identical 2:3 size, exact names from §1.
5. **Validate:** `python tools/sprites.py check <dir>` → must print "OK". If sizes drift,
   `python tools/sprites.py normalize <dir> --out art_fixed` letterboxes them all to one size.
6. Drop into `art/`, import with §7 settings, assign per §8.

## 10. Tooling reference (`tools/sprites.py`, needs Pillow)

```
python tools/sprites.py placeholders [--out art] [--size 512x768]   # regen placeholders
python tools/sprites.py check <dir>                                  # validate; exit 1 on problems
python tools/sprites.py normalize <dir> [--out art_normalized] [--size 512x768]
python tools/sprites.py selftest                                     # self-check the tool
```
