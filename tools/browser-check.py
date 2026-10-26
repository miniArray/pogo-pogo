#!/usr/bin/env python3
"""Play the web export in headless Chromium and check the browser shell.

Run inside the Nix shell after `tools/export.sh web`:

    python3 tools/browser-check.py

It serves export/web, plays each bundled course with the touch-control state,
loads a generated asset pack through the file picker, checks that pictures
and sounds come from it, removes it again, and saves screenshots under
build/browser-check/.
"""
import asyncio
import base64
import contextlib
import functools
import http.server
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time

import websockets

ROOT = pathlib.Path(__file__).resolve().parents[1]
WEB = ROOT / 'export/web'
OUT = ROOT / 'build/browser-check'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class Page:
    def __init__(self, socket_):
        self.ws = socket_
        self.next_id = 0

    async def send(self, method, **params):
        self.next_id += 1
        ident = self.next_id
        await self.ws.send(json.dumps({'id': ident, 'method': method, 'params': params}))
        while True:
            message = json.loads(await self.ws.recv())
            if message.get('id') == ident:
                if 'error' in message:
                    raise RuntimeError(f'{method}: {message["error"]}')
                return message.get('result', {})

    async def eval(self, expression):
        result = await self.send('Runtime.evaluate', expression=expression, returnByValue=True, awaitPromise=True)
        return result.get('result', {}).get('value')

    async def state(self):
        text = await self.eval('window.pogoStateJSON || ""')
        return json.loads(text) if text else None

    async def wait_state(self, predicate, timeout=60, label='state'):
        deadline = time.time() + timeout
        state = None
        while time.time() < deadline:
            state = await self.state()
            if state and predicate(state):
                return state
            await asyncio.sleep(0.25)
        raise AssertionError(f'timed out waiting for {label}; last state {state}')

    async def shot(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        data = await self.send('Page.captureScreenshot', format='png')
        (OUT / f'{name}.png').write_bytes(base64.b64decode(data['data']))


async def hold(page, buttons, seconds):
    await page.eval(f'window.pogoPad.buttons = {buttons}')
    await asyncio.sleep(seconds)
    await page.eval('window.pogoPad.buttons = 0')


async def check(port, debug_port, pack_zip):
    import urllib.request
    targets = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{debug_port}/json').read())
    page_target = next(t for t in targets if t['type'] == 'page')
    async with websockets.connect(page_target['webSocketDebuggerUrl'], max_size=64 * 1024 * 1024) as ws:
        page = Page(ws)
        await page.send('Page.enable')
        await page.send('DOM.enable')
        await page.send('Emulation.setDeviceMetricsOverride', width=1024, height=760, deviceScaleFactor=1, mobile=False)
        await page.send('Page.navigate', url=f'http://127.0.0.1:{port}/index.html')
        state = await page.wait_state(lambda s: s['updates'] > 30, 120, 'game start')
        assert state['course'] == 'first-steps' and state['pack'] == 'placeholder', state
        print('PASS game starts in the browser with placeholder shapes')
        await page.shot('01-placeholder')
        # Touch-control state drives the player: hold right, then jump.
        x0 = state['x']
        await hold(page, 1, 1.5)
        state = await page.state()
        assert state['x'] > x0 + 40 * 256, ('right did not move the player', x0, state)
        print('PASS touch-control state moves the player')
        for index, course in enumerate(['first-steps', 'stilt-gardens', 'shaft-and-spires']):
            await page.eval(f'document.getElementById("course-select").value = "{index}"')
            await page.eval('document.getElementById("course-play").click()')
            await page.wait_state(lambda s, c=course: s['course'] == c and s['updates'] > 5, 30, course)
            await hold(page, 1, 1.0)
            await page.shot(f'02-course-{course}')
            print(f'PASS course {course} plays')
        # Load the generated pack through the real file input.
        await page.eval('document.getElementById("settings-button").click()')
        await page.eval('document.getElementById("course-select").value = "0"; document.getElementById("course-play").click()')
        await page.wait_state(lambda s: s['course'] == 'first-steps', 30, 'first course again')
        document = await page.send('DOM.getDocument')
        node = await page.send('DOM.querySelector', nodeId=document['root']['nodeId'], selector='#pack-file')
        await page.send('DOM.setFileInputFiles', files=[str(pack_zip)], nodeId=node['nodeId'])
        await page.eval('document.getElementById("pack-file").dispatchEvent(new Event("change"))')
        state = await page.wait_state(lambda s: s['pack'] == 'Solid colours', 30, 'pack load')
        assert state['music'] == 'meadow', ('course music cue should play from the pack', state)
        print('PASS the pack picker loads a zip and its music cue plays')
        await page.eval('document.getElementById("settings-button").click()')
        await page.eval('document.getElementById("reset-button").click()')
        await asyncio.sleep(0.5)
        sounds_before = (await page.state())['sounds']
        await hold(page, 1, 1.4)
        state = await page.state()
        assert state['sounds'] > sounds_before, ('collecting gems should play pack sounds', state)
        print('PASS pack sounds play for game events')
        await page.shot('03-test-pack')
        # Wider shape: more scenery, same game.
        await page.eval('document.getElementById("display-mode").value = "21:9"; document.getElementById("display-mode").dispatchEvent(new Event("change"))')
        state = await page.wait_state(lambda s: s['raster'][0] > 256, 10, 'wide raster')
        print(f'PASS 21:9 shape widens the raster to {state["raster"]}')
        await page.shot('04-wide')
        await page.eval('document.getElementById("display-mode").value = "original"; document.getElementById("display-mode").dispatchEvent(new Event("change"))')
        # Reload keeps the cached pack; Remove clears it.
        await page.send('Page.reload')
        await page.wait_state(lambda s: s['updates'] > 30, 120, 'reload')
        state = await page.wait_state(lambda s: s['pack'] == 'Solid colours', 20, 'cached pack after reload')
        print('PASS the pack survives a reload from browser storage')
        await page.eval('document.getElementById("pack-clear").click()')
        await page.wait_state(lambda s: s['pack'] == 'placeholder', 20, 'pack removed')
        print('PASS Remove pack returns to placeholder shapes')
        # A broken pack is refused and the game keeps going.
        broken = OUT / 'broken.zip'
        import zipfile
        with zipfile.ZipFile(broken, 'w') as z:
            z.writestr('pack.json', '{"format_version": 7, "name": "broken"}')
        await page.send('DOM.setFileInputFiles', files=[str(broken)], nodeId=(await page.send('DOM.querySelector', nodeId=(await page.send('DOM.getDocument'))['root']['nodeId'], selector='#pack-file'))['nodeId'])
        await page.eval('document.getElementById("pack-file").dispatchEvent(new Event("change"))')
        state = await page.wait_state(lambda s: 'not used' in s['notice'], 20, 'broken pack notice')
        assert state['pack'] == 'placeholder', state
        print('PASS a broken pack is refused with a notice')


def main():
    if not (WEB / 'index.html').exists():
        print('export/web is missing; run tools/export.sh web first')
        return 1
    with tempfile.TemporaryDirectory() as scratch:
        pack_dir = pathlib.Path(scratch) / 'pack'
        pack_zip = pathlib.Path(scratch) / 'solid-colours.zip'
        subprocess.run([str(ROOT / 'tools/godot.sh'), '--headless', '--script', 'tools/make-test-pack.gd', '--', str(pack_dir), str(pack_zip)], cwd=ROOT, check=True, capture_output=True)
        port = free_port()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(Quiet, directory=str(WEB)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        debug_port = free_port()
        profile = pathlib.Path(scratch) / 'profile'
        browser = subprocess.Popen([
            'chromium', '--headless=new', f'--remote-debugging-port={debug_port}', f'--user-data-dir={profile}',
            '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required',
            '--no-first-run', '--no-default-browser-check', 'about:blank',
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                with contextlib.suppress(OSError):
                    socket.create_connection(('127.0.0.1', debug_port), 0.2).close()
                    break
                time.sleep(0.1)
            asyncio.run(check(port, debug_port, pack_zip))
        except AssertionError as error:
            print(f'FAIL {error}')
            return 1
        finally:
            browser.terminate()
            server.shutdown()
    print('BROWSER_CHECK_PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
