# Working on Pogo! Pogo!

Godot 4.6.3, GDScript. Read `README.md`, `docs/course-format.md`,
`docs/asset-packs.md` and `docs/decisions.md` before changing behaviour.

## Rules

- **Deterministic core.** `CourseGame.update(buttons)` advances one game
  update with integer math. Frame time never scales motion. Rendering and
  sound read game state and never change it.
- **Motion is fixed.** `src/game/player_motion.gd`, `src/game/camera.gd`,
  `src/game/vertical_transition.gd` and the timing table in
  `src/game/player_animation.gd` define how the game plays. Change them only
  on purpose, then re-record the route fixtures and say why in
  `docs/decisions.md`.
- **Assets are input, never output.** Never commit or bundle an asset pack,
  a picture, a font or a sound. The engine draws placeholder shapes. Tests
  generate their pack in a scratch folder.
- **Original content only.** Courses, names, text and any future art must be
  original to this project or carry a licence that allows it. Do not copy
  layouts, characters, names, music or art from other games.
- **Schemas are contracts.** Change `schema/*.json` and the matching loader
  together, keep unknown fields as errors, and record the reason in
  `docs/decisions.md`.

## Checks

Run inside `nix develop`:

- `python3 tools/check.py`: every Godot test, standard schema validation,
  headless launches with and without the generated pack, a broken-pack
  fallback and course export.
- `tools/export.sh web && python3 tools/browser-check.py`: plays the web
  export in Chromium and saves screenshots to `build/browser-check/`.
- After an intended mechanics change: `POGO_RECORD=1 tools/godot.sh
  --headless --script tests/route_test.gd`, then review the fixture diff.
