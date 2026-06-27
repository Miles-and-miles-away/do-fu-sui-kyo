# 土風水競 — Card face sprite spec

The 18 card faces (R5, R8, NFR7, T20 — extended from the FSD's 4 frames to **6** by adding a
`determined` pair shown while a card is held). Companion to `docs/FSD.md` (requirements) and
`docs/ASSETS.md §5` (asset manifest). Tooling: `tools/sprites.py` (placeholders / slice / check / normalize).

Placeholders already exist in `art/` so faces aren't blank — replace them with real art at the
**same names, same size**, run `python tools/sprites.py check art`, re-import. Nothing else changes.

---

## 1. Inventory — exactly 18 files

3 critters × 6 expressions. Filenames (the convention lives in `tools/sprites.py`):

```
fish_{neutral,blink,determined,determined_blink,smile,cry}.png   # WATER (0)
bird_{neutral,blink,determined,determined_blink,smile,cry}.png   # SKY   (1)
dino_{neutral,blink,determined,determined_blink,smile,cry}.png   # EARTH (2)
```

`fish→WATER, bird→SKY, dino→EARTH` matches `GameState.Type` / `GameRoot.frames_*`.

## 2. Format

- **PNG, RGBA.**
- **2:3 portrait** to match the card mesh (`Card.tscn` quad is 0.1 × 0.15 m). Use **512 × 768**
  (or any 2:3, e.g. 1024 × 1536). A square image gets vertically stretched on the card.
  *(Prefer square art? Say so and the quad changes to square instead.)*
- **All 18 identical dimensions** — non-negotiable (NFR7). `tools/sprites.py check` enforces it.
- Mipmaps will be off, so power-of-two isn't needed.

## 3. The #1 rule — framing consistency (NFR7)

Across all 18, the head sits at the **same position, scale, and baseline**. Between a critter's
6 frames, **only the face features change** (eyes, brows, mouth, tears) — the head outline is
identical. If the head shifts/resizes between frames, the expressions will visibly *jump*.

How to guarantee it: draw **neutral as the master**, then make the other 5 by editing only the
eyes/brows/mouth on a copy, onion-skinned over neutral. Don't redraw the head.

## 4. Per-expression intent

| Frame | Eyes | Mouth | When shown |
|---|---|---|---|
| **neutral** | open | calm/small | resting (R6) |
| **blink** | **closed** (only the eyes differ from neutral) | same as neutral | ~150 ms every 3–4.5 s (R6) |
| **determined** | open, focused (slightly angled brows) | firm/set | **while held/selected** (on grab) |
| **determined_blink** | **closed** (determined eyes-closed) | firm/set | blink while held (~150 ms) |
| **smile** | open, bright | big upturn | round winner (R7) |
| **cry** | open + tears | downturn | round loser (R7) |

The two `determined` frames are the held state: grab a card and it psyches up (and blinks the
determined face) until you release it; resolution then locks it to smile/cry.

## 5. Background — pick one, use for all 18

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

Per file (or set once and apply to all 18 via a preset):

- Compress Mode = **Lossless** (not VRAM)
- **Detect 3D → Compress To = Disabled**
- Mipmaps = **off**
- Filter = **Linear** (or Nearest for pixel art) — the *same* on all 18
- Identical settings across all 18 (NFR7).

## 8. Assigning in Godot

After import, select **GameRoot** in `main.tscn` and fill the three arrays **in canonical order
`[neutral, blink, determined, determined_blink, smile, cry]`** (same order as the slicer and
`tools/sprites.py`):

- `frames_water` ← the 6 `fish_*` frames in that order
- `frames_sky`   ← the 6 `bird_*` frames
- `frames_earth` ← the 6 `dino_*` frames

GameRoot is the single source of frames — the robot pulls from the same place, so nothing is
assigned twice. A short array is tolerated (a missing `determined` pair just falls back to
neutral while held), so you can wire 4 frames first and add the determined pair later.

## 9. Process

1. Lock style + the 3 critter designs.
2. Draw each **neutral master** at final canvas size.
3. Derive the other 5 (blink, determined, determined_blink, smile, cry) by editing only the face,
   onion-skinned over neutral.
4. Export all 18 at identical 2:3 size, exact names from §1.
5. **Validate:** `python tools/sprites.py check <dir>` → must print "OK". If sizes drift,
   `python tools/sprites.py normalize <dir> --out art_fixed` letterboxes them all to one size.
6. Drop into `art/`, import with §7 settings, assign per §8.

## 10. Tooling reference (`tools/sprites.py`, needs Pillow)

```
python tools/sprites.py placeholders [--out art] [--size 512x768]   # regen placeholders
python tools/sprites.py slice <sheet.png> <fish|bird|dino> [--out art] [--inset N]
python tools/sprites.py check <dir>                                  # validate; exit 1 on problems
python tools/sprites.py normalize <dir> [--out art_normalized] [--size 512x768]
python tools/sprites.py selftest                                     # self-check the tool
```

## 11. Generation prompts (Gemini "nano banana")

One prompt **per character**, each producing a single **2×3 grid** (6 expressions, 2 wide × 3
tall). The slicer reads cells row-major into the six frames and **fits each onto the 2:3 card**,
so the grid cells don't have to be 2:3 themselves (square cells are fine — they're padded, not
stretched). Layout (fixed — `tools/sprites.py slice` assumes exactly this):

```
row 1:  neutral | blink
row 2:  determined | determined_blink
row 3:  smile | cry
```

Ask for **one uniform background colour across all six cells** — nano banana sometimes alternates
cell shades; the slicer pads each card with that cell's own colour, so a uniform sheet keeps all
six card backgrounds matching.

**Workflow:** generate a character → save the sheet (e.g. `art/_sheets/fish.png`) →
`python tools/sprites.py slice art/_sheets/fish.png fish` → repeat for bird/dino →
`python tools/sprites.py check art`. Add `--inset 4` if a faint seam shows at the cut lines.

**Shared style DNA (keeps all 3 matching):** flat modern vector mascot · thick clean outlines ·
soft cel shading, one highlight · big expressive eyes · bold simple shapes, readable across a
room · dead-front, centered, symmetrical · solid flat pastel background, no scenery · 2:3 portrait.

**Cross-character consistency:** generate Fish first, then attach it as a reference image for
Bird and Dino with *"match this image's exact art style, line weight, shading, eye style and
proportions — same world, different animal."*

**Fish** — A cute kawaii mascot **fish** card face. Flat modern vector illustration:
thick clean dark outlines, smooth cel shading with one soft top highlight, no gradients or
texture. A round friendly aqua-teal fish, big round sparkly eyes, small rounded fins, tiny
mouth — chibi, front-facing, centered, symmetrical. Solid flat **soft aqua** background, no
scenery. Compose **six portraits of this exact same fish in a clean 2×3 grid** (2 wide, 3 tall),
equal cells, drawn at the **identical size, position, pose, lighting and framing in every cell**
— only the expression changes. 
Row 1: 
(1) **neutral** — calm, eyes open; (2) **blink** —
identical but eyes gently closed; 
Row 2: 
(3) **determined** — focused and eager, slightly angled brows, a firm set mouth, psyched up, not angry but determined. (4) **determined-blink** — the determined face with eyes
gently closed; 
Row 3: (5) **smile** — big joyful open smile, bright eyes (a winner); (6) **cry** —
teary downturned eyes with tear drops, wobbly frown (a loser, still cute).
High-res, **one uniform background colour across all six cells**. **No text, labels, borders,
watermark, extra characters, or background objects.**

**Bird** — A cute kawaii mascot **baby bird** card face. Flat modern vector illustration:
thick clean dark outlines, smooth cel shading with one soft top highlight, no gradients or
texture. A round fluffy warm-yellow/coral chick, big round sparkly eyes, tiny stubby wings, a
small orange beak — chibi, front-facing, centered, symmetrical. Solid flat **pale sky-blue**
background, no scenery. Compose **six portraits of this exact same bird in a clean 2×3 grid**
(2 wide, 3 tall), equal cells, drawn at the **identical size, position, pose, lighting and
framing in every cell** — only the expression changes.
Row 1: (1) **neutral** — calm, eyes open; (2) **blink** — identical but eyes gently closed;
Row 2: (3) **determined** — focused and eager, slightly angled brows, a firm set beak, psyched
up, not angry but determined; (4) **determined-blink** — the determined face with eyes gently closed;
Row 3: (5) **smile** — big joyful open smile/chirp, bright eyes (a winner); (6) **cry** — teary
downturned eyes with tear drops, wobbly frown (a loser, still cute).
High-res, **one uniform background colour across all six cells**. **No text, labels, borders,
watermark, extra characters, or background objects.**

**Dino** — A cute kawaii mascot **baby dinosaur** card face. Flat modern vector illustration:
thick clean dark outlines, smooth cel shading with one soft top highlight, no gradients or
texture. A round chunky leaf-green baby dino with a rounded belly, small soft back spikes, stubby
arms and big round sparkly eyes — chibi, front-facing, centered, symmetrical. Solid flat **soft
sage-green** background, no scenery. Compose **six portraits of this exact same dino in a clean
2×3 grid** (2 wide, 3 tall), equal cells, drawn at the **identical size, position, pose, lighting
and framing in every cell** — only the expression changes.
Row 1: (1) **neutral** — calm, eyes open; (2) **blink** — identical but eyes gently closed;
Row 2: (3) **determined** — focused and eager, slightly angled brows, a firm set mouth, psyched
up, not angry but determined; (4) **determined-blink** — the determined face with eyes gently closed;
Row 3: (5) **smile** — big joyful open smile, bright eyes (a winner); (6) **cry** — teary
downturned eyes with tear drops, wobbly frown (a loser, still cute).
High-res, **one uniform background colour across all six cells**. **No text, labels, borders,
watermark, extra characters, or background objects.**
