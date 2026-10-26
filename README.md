# Pogo! Pogo!

A side-scrolling pogo platformer in Godot 4.6.3. Walk, jump, climb vines,
swing at walls, and bounce on a pogo stick over spikes, water and walkers.
Three courses are included. The game uses an integer simulation at 60
updates per second, so the same input always gives the same result.

The game ships without pictures, fonts or sounds of its own. It draws simple
placeholder shapes until you give it an [asset pack](docs/asset-packs.md)
with your own art and audio.

**AI disclosure:** agents wrote this game under human direction. Checks
replay recorded routes through every course and compare the game state.

## Play

```
nix run .            # or: nix develop -c tools/godot.sh --path .
```

| Action | Keyboard | Gamepad |
|---|---|---|
| Move, climb | Arrows | D-pad or left stick |
| Jump (A) | Z or Space | A |
| Pogo, swing (B) | X or Shift | B or X |

- **Pogo:** jump, then hold Down+B in the air. Keep holding B to keep
  bouncing. A bounce knocks out walkers and is safe on spikes.
- **Climb:** jump with Up held next to a vine. Up/Down climbs; A lets go.
- **Swing:** walk into a wall until you push against it, then press B.
- Collect gems, reach the checkpoint, and touch the goal flag to clear the
  course. Falling into water or losing all health costs a life.

Other keys: **R** restarts, **N** next course, **M** mute, **F8** cycles
the display shape, **F9** toggles whole-number zoom.

Command line, after `--`: `--pack=PATH`, `--placeholder`, `--course=PATH`,
`--export-course=PATH`, `--display=MODE` (`original`, `fill` or a ratio such as
`4:3`, for this run only). See [asset packs](docs/asset-packs.md) and the
[course format](docs/course-format.md).

## Browser

`tools/export.sh web` writes `export/web/`. Serve that folder over HTTP.
The page has touch controls, a course selector, course JSON load and save,
an asset-pack picker, display shapes and mute under **Settings**.

## Display

**Original** keeps the 256 x 240 view. **Fill** and the fixed ratios show
more scenery around the same game; the game itself always simulates the same
256-pixel window. **Sharp pixels** zooms by whole numbers when the window is
large enough.

## Check and build

```
nix develop -c python3 tools/check.py          # all checks, no pack needed
nix develop -c tools/export.sh web             # web export
nix develop -c python3 tools/browser-check.py  # plays the web export in Chromium
nix build                                      # Linux package for this system
nix build .#packages.aarch64-linux.linux-game  # ARM64 device build, no ARM builder needed
```

`tools/build-courses.py` rebuilds the bundled courses.
`tools/probe-route.gd` and `tools/search-route.gd` help write replay routes.

## Layout

```
src/course/   course document, validation and collision lookups
src/game/     player motion, camera, retries, walker, the course game
src/pack/     asset-pack and sprite-sheet loaders
src/render/   course view and display layout
src/audio/    sound board
courses/      bundled courses
schema/       JSON Schemas for courses, packs and sprite sheets
tests/        checks, replay routes and fixtures, the generated test pack
tools/        export, checks, course builder, route tools
web/          browser shell
```
