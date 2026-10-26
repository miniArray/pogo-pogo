# Course format v1

A course is a JSON document: local data, not code and not a save file.
`schema/course.schema.json` is the structural contract (JSON Schema
2020-12). `src/course/course_definition.gd` applies it, then checks the
cross-references the schema cannot express. Unknown fields are errors at
every level. Files are at most 2 MB and 16 levels deep.

## Fields

| Field | Meaning |
|---|---|
| `format_version` | Exactly 1. |
| `level.id` | 1–64 lowercase letters, digits, `.`, `_` or `-`. |
| `terrain.rows`, `terrain.columns` | Exactly 7 sections of 8 screens. |
| `terrain.grid` | 56 screen IDs, row by row. 255 marks an absent screen. |
| `terrain.screens` | 1–56 records: a unique `id` (0–254) and 256 `cells`, row by row: 16 x 16 metatile IDs of 16 pixels. |
| `terrain.metatiles` | Exactly 256 records: `tile` (a key the asset pack resolves, or empty) and `collision` (0 empty, 1 solid, 2 climbable, 3 hazard). |
| `sections` | Exactly 7 records with the `tileset` key the asset pack uses for that section. |
| `placements` | 1–255 actors: unique `index` (0–254), `section`, `x` (0–2047), `y` (0–255) and `type`: `walker`, `gem` or `goal`. At least one goal. |
| `entry`, `retry` | Where play starts and where a retry returns: `section`, `x`, `y` (0–239) and `camera_x` (0–1792). The point must be in a present screen inside its 256-pixel camera view. |
| `checkpoint` | `section` and `page` (screen column) that latch the checkpoint, and the `destination` used by later retries. |
| `hud` | Starting `health` (3–5) and spare `lives` (0–9). |
| `music` | Optional music cue key for the asset pack. |

## Rules

- **Coordinates.** A section is 2048 x 256 pixels. Rows 0–47 sit behind the
  status band; rows 48–239 are the playfield. Rows 240–255 are drawn but
  never collide.
- **Hazards.** Class-3 metatiles act by their ID: `0x90`–`0x9F` are spikes
  (solid, and they hurt unless the player lands on them in a pogo bounce),
  `0xA0`–`0xAF` are water. A player who touches water below row 208 falls
  out and retries. Other class-3 IDs in present screens are rejected.
- **Pits.** Put water in the bottom rows of every pit. A fall from the bottom
  band with no water and no section below also counts as a pit.
- **Climbing.** Grab a climbable cell by jumping with Up held. Climbing above
  row 57 or falling below row 224 moves to the section above or below, but
  only when the camera rests on an odd screen column and the target screen
  is present. The camera rests on a column when the next screen is absent,
  so put vertical connections in an odd column at the edge of the present
  screens.
- **Actors.** A walker's `y` is its centre; stand it 12 pixels above the
  floor (y 196 on a floor at row 13). Walkers wake when their spot scrolls
  into view and sleep when they leave it.

## Selecting and saving

Native: `-- --course=PATH` or `POGO_COURSE` plays a file. `-- --export-course=PATH`
writes the selected course as canonical JSON (sorted keys, two-space indent)
and quits. **R** restarts and **N** plays the next bundled course.

Browser: **Settings → Course** plays a bundled course, loads a JSON file or
saves the current course. An invalid file changes nothing and shows the
reason with its field path.

## Bundled courses

`tools/build-courses.py` draws the three bundled courses as character maps
and writes `courses/*.json`. Each has a replay route in `tests/routes/` that
clears it; `tests/route_test.gd` compares the game state every 30 updates
with `tests/fixtures/*.digest`.
