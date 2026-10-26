#!/usr/bin/env python3
"""Run every public check. Run inside the Nix shell from the repository root:

    nix develop -c python3 tools/check.py

It needs no asset pack: the pack checks generate one in a scratch folder.
"""
import json
import pathlib
import subprocess
import sys
import tempfile

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = [str(ROOT / 'tools/godot.sh'), '--headless']
SCRIPTS = ['course', 'display', 'world', 'route', 'pack']
COURSES = ['first-steps', 'stilt-gardens', 'shaft-and-spires']
failures = []


def run(args, expect, forbid=('SCRIPT ERROR',), label=None, timeout=600):
    label = label or ' '.join(args)
    result = subprocess.run(GODOT + args, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    problems = [f'missing "{text}"' for text in expect if text not in output]
    problems += [f'found "{text}"' for text in forbid if text in output]
    if result.returncode != 0:
        problems.append(f'exit code {result.returncode}')
    if problems:
        failures.append(label)
        print(f'FAIL {label}: {", ".join(problems)}\n{output[-3000:]}')
    else:
        print(f'PASS {label}')
    return output


def schemas():
    schema = json.loads((ROOT / 'schema/course.schema.json').read_text())
    validator = jsonschema.Draft202012Validator(schema)
    for course in COURSES:
        errors = list(validator.iter_errors(json.loads((ROOT / f'courses/{course}.json').read_text())))
        if errors:
            failures.append(f'schema {course}')
            print(f'FAIL standard schema validation of {course}: {errors[0].message}')
        else:
            print(f'PASS standard schema validation of {course}')
    for name in ['asset-pack', 'sprite-sheet', 'course']:
        jsonschema.Draft202012Validator.check_schema(json.loads((ROOT / f'schema/{name}.schema.json').read_text()))
    print('PASS schema files are valid JSON Schema 2020-12')


def main():
    subprocess.run(['godot', '--headless', '--import'], cwd=ROOT, capture_output=True)
    schemas()
    for script in SCRIPTS:
        forbid = ('SCRIPT ERROR', '_FAIL') if script != 'pack' else ('SCRIPT ERROR', 'PACK_CHECK_FAIL')
        run(['--script', f'tests/{script}_test.gd'], [f'{script.upper()}_CHECK_PASS'], forbid, f'{script} test')
    with tempfile.TemporaryDirectory() as scratch:
        pack = pathlib.Path(scratch) / 'pack'
        broken = pathlib.Path(scratch) / 'broken'
        run(['--script', 'tools/make-test-pack.gd', '--', str(pack)], ['TEST_PACK_WRITTEN'], label='generate test pack')
        broken.mkdir()
        (broken / 'pack.json').write_text('{"format_version": 9, "name": "broken"}')
        for course in COURSES:
            run(['--quit-after', '240', '--', f'--course=res://courses/{course}.json'],
                [f'POGO_READY course={course} pack=placeholder'], label=f'launch {course}')
            run(['--quit-after', '240', '--', f'--course=res://courses/{course}.json', f'--pack={pack}'],
                ['POGO_PACK_READY Solid colours', f'POGO_READY course={course} pack=Solid colours'],
                label=f'launch {course} with the test pack')
        run(['--quit-after', '120', '--', f'--pack={broken}'],
            ['POGO_PACK_REJECTED $.format_version', 'POGO_READY course=first-steps pack=placeholder'],
            label='a broken pack falls back to placeholders')
        run(['--quit-after', '120', '--', f'--pack={pack}', '--placeholder'],
            ['POGO_READY course=first-steps pack=placeholder'], label='--placeholder ignores the pack')
        exported = pathlib.Path(scratch) / 'exported.json'
        run(['--', '--course=res://courses/stilt-gardens.json', f'--export-course={exported}'],
            ['COURSE_EXPORTED stilt-gardens'], label='export a course')
        if json.loads(exported.read_text()) != json.loads((ROOT / 'courses/stilt-gardens.json').read_text()):
            failures.append('export round trip')
            print('FAIL exported course differs from the bundled file')
        else:
            print('PASS exported course matches the bundled file')
    print(f'\n{"CHECKS_FAILED" if failures else "CHECKS_PASSED"}: {len(failures)} failing')
    for failure in failures:
        print(f'  {failure}')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
