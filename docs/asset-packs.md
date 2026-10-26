# Asset packs

An asset pack gives Pogo! Pogo! its pictures and sounds. The game ships with
no art, fonts or audio. Without a pack, it draws placeholder shapes and plays
no sound. A pack changes pictures and sound only. It cannot change motion,
collision, timing, the course or any other game rule.

A pack is player input, like a course file. The game never bundles,
commits or downloads one.

## Choosing a pack

| Where | How |
|---|---|
| Native | `-- --pack=/path/to/pack` (a folder or a `.zip`), or the `POGO_PACK` environment variable. `--pack` wins. `-- --placeholder` ignores every pack. |
| Browser | **Settings → Choose pack (.zip)…**. The zip is cached as `user://pack.zip` in browser storage and used again after a reload. **Remove pack** deletes the cached copy. |

An invalid pack is not used. The game shows the reason at the bottom of the
screen, logs `POGO_PACK_REJECTED <field path> <reason>`, and keeps drawing
placeholder shapes. A valid pack logs `POGO_PACK_READY` with a summary.

## Layout

A pack is a folder, or a zip of that folder's contents, with `pack.json` at
its root. Every other file is named by a path relative to the root. Paths
use letters, digits, `_`, `.`, `/` and `-`, and may not contain `.` or `..`
segments. Pictures are PNG. Sounds are WAV (PCM) or Ogg Vorbis. Each file is
at most 16 MB; each picture is at most 4096 pixels on a side.

`schema/asset-pack.schema.json` is the structural contract (JSON Schema
2020-12). The loader also checks keys and files as described below.

```json
{
  "format_version": 1,
  "name": "My pack",
  "tilesets": {
    "meadow": {
      "backdrop": "#1d2b53",
      "tiles": { "ground": "tiles/ground.png", "vine": "tiles/vine.png" }
    }
  },
  "sprites": {
    "player": { "sheet": "sprites/player.json" },
    "walker": { "sheet": "sprites/walker.json", "texels_per_pixel": 2 }
  },
  "hud": { "band": "hud/band.png", "health": "hud/heart.png", "health_empty": "hud/heart-empty.png", "life": "hud/life.png" },
  "sounds": { "pogo": "sounds/boing.wav", "gem": "sounds/chime.ogg" },
  "music": { "meadow": "music/meadow.ogg" }
}
```

Only `format_version` and `name` are required. Everything else is optional,
and anything missing falls back to a placeholder shape or silence.

### Tilesets and tiles

Each course section names a tileset, and each course metatile names a tile
key (see [course format](course-format.md)). A cell is drawn with
`tilesets[<section tileset>].tiles[<metatile tile>]`, scaled into its 16 x
16 pixel cell. A metatile with an empty tile key, or a key the tileset does
not have, is drawn as a placeholder for its collision class. `backdrop` is
the colour behind the section. Tileset and tile keys are 1–64 lowercase
letters, digits, `.`, `_` or `-`.

The bundled courses use the tilesets `meadow`, `garden`, `cavern` and
`spires`, and the tile keys `ground-top`, `ground`, `block`, `vine`, `ledge`,
`grass`, `spikes` and `water`.

### Sprites

`player`, `walker`, `gem` and `goal` each take an Aseprite sheet export:
the JSON file (array or hash `frames`) and the PNG its `meta.image` names,
relative to the JSON file. `schema/sprite-sheet.schema.json` is the subset
the game reads.

| Field | Use |
|---|---|
| `meta.frameTags[]` | Name the animations. `direction` may be `forward`, `reverse`, `pingpong` or `pingpong_reverse`. Tags the game does not draw are listed as notices and ignored. |
| `frames[].frame` | Where the picture is in the PNG. |
| `frames[].sourceSize`, `spriteSourceSize` | The picture's canvas and trim offset, so trimmed export is safe. |
| `frames[].duration` | Milliseconds, used as a weight for walker, gem and goal loops. |
| slice `origin` with a `pivot` | The actor point inside the canvas. Without it, the canvas centre is used. |
| `texels_per_pixel` (manifest) | Draw a sheet at 1–8 texels per world pixel. Default 1. |

Art faces right; the game mirrors it when the actor faces left.

| Sprite | Tags | Actor point |
|---|---|---|
| `player` | `idle`, `walk`, `air`, `crouch`, `climb`, `hurt`, `pogo`, `push`, `land`, `swing`, `swing_miss` | Body centre. Feet are 12 pixels below it; the body is about 20 pixels wide. |
| `walker` | `walk`, `knocked_out` | Body centre; feet 12 pixels below. |
| `gem` | `idle` | Centre. |
| `goal` | `idle` | Centre of a 48-pixel-tall marker. |

Player pictures follow the game's own animation counters. A tag with exactly
one picture per animation step shows the picture for the current step
(steps: idle 1, walk 4, air 1, crouch 5, climb 2, hurt 1, pogo 3, push 2,
land 2, swing 7, swing_miss 2). Any other count is spread evenly over the
loop. A missing player tag uses `idle`.

### Status band

`hud.band` fills the 48-pixel band at the top. `health` and `health_empty`
are 10 x 10 health pips; `life` is the 12 x 12 lives icon. The score and
digits use the engine's built-in font.

### Sounds and music

`sounds` maps game events to files: `land`, `pogo`, `climb`, `swing`,
`swing_miss`, `hurt`, `knockout`, `gem`, `checkpoint`, `defeat`, `retry`,
`game_over` and `clear`. `music` maps cue keys to files that loop. A course
names its cue in its `music` field; the bundled courses use `meadow`,
`garden` and `spires`.

## Checks

`tests/test_pack.gd` builds a pack of solid colours and short tones in a
scratch folder. `tests/pack_test.gd` loads it from a folder and a zip, checks
every lookup, draws a frame and plays sounds, then rejects 13 kinds of broken
pack. `tools/browser-check.py` loads the same pack through the browser file
picker.
