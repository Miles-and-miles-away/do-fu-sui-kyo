# do-fu-sui-kyo — agent working notes

Godot 4.7 / GDScript VR project. The logic brain (`GameState.gd`) is unit-tested
headless; the VR layer is exercised in-headset, not by tests.

## Before committing (enforced by CI — don't let it bounce)

Run from the repo root and make all three clean:

```sh
gdformat .                                           # auto-format (CI checks this)
gdlint .                                             # lint
godot --headless --path . --script res://tests/test_game_state.gd   # logic tests, exit 0
godot --headless --audio-driver Dummy --path . --script res://tests/test_music.gd  # music tests, exit 0
```

(`--audio-driver Dummy` on the music suite so it doesn't grab a real audio device. Close the
Godot editor first — an open editor holds the project and headless `--script` runs will hang.)

- A `pre-commit` hook runs `gdformat` + `gdlint` automatically — install it once with
  `pip install pre-commit && pre-commit install`. The compile-check + test suite run in
  CI only (they need the engine).
- gdtoolkit is pinned to the exact `4.5.0` in both `.pre-commit-config.yaml` (`rev`) and `ci.yml`
  (`pip install`); bump both together so local and CI format identically.
- Don't reformat or lint `addons/` — third-party code, excluded everywhere.
