# Decisions

Each entry names what was chosen, where it comes from, and what it costs.

## Course format (v1)

- **Kept from the engine's earlier level format:** the 7 x 8 screen grid,
  255 as the absent-screen marker, 256-cell screens, the 256-entry metatile
  table with collision classes 0–3, the ID rule for class-3 hazards,
  placements with stable indices, the entry, retry and checkpoint records,
  the size and depth limits, and canonical output. Removing any of these
  would change mechanics or break existing tooling.
- **Removed:** catalog identifiers, per-metatile picture and palette
  indices, per-section picture-set and palette selectors, and the fields for
  content this engine does not have. They only selected data from a fixed
  external catalog.
- **Replaced:** picture indices with a `tile` key per metatile, and the
  per-section picture-set selector with a `tileset` key per section. The
  asset pack resolves both. Numeric actor types became the keys `walker`,
  `gem` and `goal`, the three actors the engine has. The music track number
  became an optional `music` cue key.
- **Added:** nothing beyond those replacements. A course needs a goal, so
  `goal` joined the placement types instead of adding a new field.

## Asset pack (v1)

- **Sources:** the sheet reader for player art that the engine already had
  (Aseprite JSON export with tags, trim, durations and an `origin` slice),
  and the version 2 graphics pack of the sibling game Eggshell (`--pack`,
  an environment variable, `--placeholder`, a manifest at the pack root,
  placeholder shapes for anything missing, and packs never supplying the
  level).
- **Shape:** one `pack.json` with optional `tilesets`, `sprites`, `hud`,
  `sounds` and `music`. Fixed enums for sprite and sound keys, so a typo is
  an error instead of silent art loss. Free keys for tilesets, tiles and
  music cues, because courses choose those.
- **Density:** an integer `texels_per_pixel` per sprite replaces the old
  rule that measured density against a fixed canvas height. The old rule
  depended on one specific picture size.
- **Cost:** a whole pack is refused when any named file is broken. A partial
  pack would be friendlier, but a refused pack with one clear reason is
  easier to fix and to test.

## Engine

- **Player motion and camera** keep their integer arithmetic, constants and
  update order. Paths the game never reaches were removed, and the state
  and animation numbers are contiguous. The replay fixtures were unchanged
  by the removal; renumbering changed only those two digest fields. Animation step
  counts and step lengths are part of the game rules, because the swing
  and the climbing sound read them; they live in
  `src/game/player_animation.gd`.
- **Clock:** one game update per physics tick at 60 per second.
- **Walker:** a new, simple enemy. It walks at one pixel per update, turns at
  walls and ledges, falls when unsupported, hurts on contact and is knocked
  out by a pogo bounce for 200 points. Gems give 100 points.
- **Pit safety net:** a fall from the bottom band with no section below
  counts as a pit, so a course without water in a pit cannot trap the
  player below the screen.
- **No pack is bundled.** The release has no pictures, fonts or audio of its
  own. The built-in engine font draws the score.
