#!/usr/bin/env python3
"""Write the bundled courses in courses/ from the layouts drawn below.

Each layout is a list of strings, one character per 16-pixel metatile, 16 rows
per section and 16 characters per screen column. Run from the repository root:

    nix develop -c python3 tools/build-courses.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Character -> (metatile ID, tile key, collision class).
LEGEND = {
    '.': (0x00, '', 0),
    '=': (0x01, 'ground-top', 1),
    '#': (0x02, 'ground', 1),
    'B': (0x03, 'block', 1),
    'H': (0x04, 'vine', 2),
    '-': (0x05, 'ledge', 1),
    ',': (0x06, 'grass', 0),
    '^': (0x90, 'spikes', 3),
    '~': (0xA0, 'water', 3),
}
EMPTY_SCREEN = 255


def metatiles():
    table = [{'tile': '', 'collision': 0} for _ in range(256)]
    for _, (index, tile, collision) in LEGEND.items():
        table[index] = {'tile': tile, 'collision': collision}
    return table


def build(course_id, sections, tilesets, placements, entry, retry, checkpoint, health=4, lives=2, music=None):
    """`sections` maps section index -> layout rows (16 strings of 128 columns,
    with ' ' marking an absent screen column block)."""
    grid = [EMPTY_SCREEN] * 56
    screens = []
    seen = {}
    for section, rows in sections.items():
        assert len(rows) == 16, (course_id, section, len(rows))
        width = max(len(row) for row in rows)
        rows = [row.ljust(width) for row in rows]
        for column in range(width // 16):
            block = [row[column * 16:(column + 1) * 16] for row in rows]
            if all(set(line) == {' '} for line in block):
                continue
            cells = []
            for line in block:
                assert ' ' not in line, (course_id, section, column, line)
                cells.extend(LEGEND[ch][0] for ch in line)
            key = tuple(cells)
            if key not in seen:
                seen[key] = len(screens)
                screens.append({'id': len(screens), 'cells': cells})
            grid[section * 8 + column] = seen[key]
    document = {
        'format_version': 1,
        'level': {'id': course_id},
        'terrain': {'rows': 7, 'columns': 8, 'grid': grid, 'screens': screens, 'metatiles': metatiles()},
        'sections': [{'tileset': tilesets.get(i, 'meadow')} for i in range(7)],
        'placements': [
            {'index': i, 'section': p[0], 'x': p[1], 'y': p[2], 'type': p[3]} for i, p in enumerate(placements)
        ],
        'entry': entry,
        'retry': retry,
        'checkpoint': checkpoint,
        'hud': {'health': health, 'lives': lives},
    }
    if music:
        document['music'] = music
    path = ROOT / 'courses' / f'{course_id}.json'
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
    print(f'wrote {path.relative_to(ROOT)}: {len(screens)} screens, {len(placements)} placements')


def dest(section, x, y, camera_x):
    return {'section': section, 'x': x, 'y': y, 'camera_x': camera_x}


# Ground rows: the floor surface is row 13 (y 208); a standing player's centre is y 196.
STAND = 196


class Canvas:
    """A section drawn with rectangles: columns are 16-pixel cells, 16 rows."""

    def __init__(self, screens, absent=()):
        self.rows = [['.'] * (screens * 16) for _ in range(16)]
        for screen in absent:
            for row in self.rows:
                row[screen * 16:(screen + 1) * 16] = [' '] * 16

    def paint(self, ch, left, top, width=1, height=1):
        for y in range(top, top + height):
            for x in range(left, left + width):
                assert self.rows[y][x] != ' ', ('absent screen', x, y)
                self.rows[y][x] = ch
        return self

    def ground(self, left, width, top=13):
        self.paint('=', left, top, width, 1)
        return self.paint('#', left, top + 1, width, 15 - top)

    def pit(self, left, width, ch='~'):
        self.paint('.', left, 12, width, 1)
        if ch == '~':
            return self.paint('~', left, 13, width, 3)
        return self.paint('^', left, 13, width, 1)

    def lines(self):
        return [''.join(row) for row in self.rows]


def first_steps():
    c = Canvas(6)
    c.paint(',', 0, 12, 96).ground(0, 96)
    c.pit(21, 4)                       # first water gap: a plain jump
    c.paint('B', 19, 11, 2, 2)         # a low step
    c.pit(36, 7, '^')                  # spike strip: pogo across it
    c.paint('H', 58, 3, 2, 10)         # tall vine: climb, let go, drift onto the ledge
    c.paint('-', 60, 8, 4)             # ledge beside the vine
    c.pit(68, 3)                       # second water gap
    c.paint('B', 75, 9, 8, 4)          # wall to climb with a pogo bounce
    c.paint('B', 77, 7, 4, 2)
    placements = [
        (3, 120, 184, 'gem'), (3, 136, 184, 'gem'),
        (3, 375, 120, 'gem'),
        (3, 480, STAND, 'walker'),
        (3, 600, 90, 'gem'), (3, 984, 112, 'gem'), (3, 1000, 112, 'gem'),
        (3, 1150, STAND, 'walker'),
        (3, 1250, 140, 'gem'),
        (3, 1350, STAND, 'walker'),
        (3, 1490, STAND - 12, 'goal'),
    ]
    build(
        'first-steps', {3: c.lines()}, {3: 'meadow'}, placements,
        entry=dest(3, 40, 160, 0), retry=dest(3, 40, 160, 0),
        checkpoint={'section': 3, 'page': 3, 'destination': dest(3, 792, 160, 768)},
        music='meadow',
    )


def stilt_gardens():
    c = Canvas(8)
    c.paint(',', 0, 12, 128).ground(0, 128)
    c.pit(15, 4)                       # water
    c.paint('-', 20, 8, 3)             # gem ledge
    c.pit(30, 10, '^')                 # long spike bed: keep bouncing
    c.paint('B', 44, 10, 2, 3)         # block
    c.pit(52, 4)
    c.paint('B', 58, 9, 1, 4)          # stilts between pools
    c.pit(59, 4)
    c.paint('B', 63, 9, 1, 4)
    c.pit(76, 8, '^')
    c.pit(92, 4)
    c.paint('-', 100, 8, 4)            # gem ledge
    c.pit(108, 3)
    placements = [
        (2, 330, 112, 'gem'), (2, 346, 112, 'gem'), (2, 400, STAND, 'walker'),
        (2, 560, 120, 'gem'), (2, 720, STAND, 'walker'), (2, 935, 120, 'gem'),
        (2, 1100, STAND, 'walker'), (2, 1280, 120, 'gem'), (2, 1400, STAND, 'walker'),
        (2, 1610, 112, 'gem'), (2, 1626, 112, 'gem'), (2, 1650, STAND, 'walker'),
        (2, 1880, STAND, 'walker'),
        (2, 2000, STAND - 12, 'goal'),
    ]
    build(
        'stilt-gardens', {2: c.lines()}, {2: 'garden'}, placements,
        entry=dest(2, 40, 160, 0), retry=dest(2, 40, 160, 0),
        checkpoint={'section': 2, 'page': 4, 'destination': dest(2, 1056, 160, 1024)},
        music='garden',
    )


def shaft_and_spires():
    lower = Canvas(4)
    lower.paint(',', 0, 12, 64).ground(0, 64)
    lower.pit(18, 5)
    lower.pit(36, 4, '^')
    lower.paint('-', 30, 8, 4)
    lower.paint('H', 60, 0, 2, 13)     # shaft vine up to the section above
    upper = Canvas(4, absent=[0])
    upper.paint(',', 16, 12, 48).ground(16, 48)
    upper.paint('H', 60, 9, 2, 7)      # the vine arrives through the floor
    upper.pit(44, 6, '^')
    upper.pit(28, 8)
    upper.paint('-', 30, 9, 4)
    placements = [
        (4, 200, 120, 'gem'), (4, 340, 100, 'gem'), (4, 520, 116, 'gem'),
        (4, 560, STAND, 'walker'), (4, 800, STAND, 'walker'),
        (4, 975, 80, 'gem'),
        (3, 880, 116, 'gem'), (3, 660, STAND, 'walker'), (3, 600, 150, 'gem'),
        (3, 400, STAND, 'walker'), (3, 520, 116, 'gem'),
        (3, 300, STAND - 12, 'goal'),
    ]
    build(
        'shaft-and-spires', {4: lower.lines(), 3: upper.lines()}, {4: 'cavern', 3: 'spires'},
        placements,
        entry=dest(4, 40, 160, 0), retry=dest(4, 40, 160, 0),
        checkpoint={'section': 3, 'page': 3, 'destination': dest(3, 880, 160, 768)},
        health=5, lives=3, music='spires',
    )


if __name__ == '__main__':
    (ROOT / 'courses').mkdir(exist_ok=True)
    first_steps()
    stilt_gardens()
    shaft_and_spires()
