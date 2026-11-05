#!/usr/bin/env python3
"""Exercise the packaged app on a logged-in Mac. Replaces the current video and restarts YTFloat."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import http.client
import json
import os
import signal
import subprocess
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist/YTFloat.app'
CLI = APP / 'Contents/Helpers/ytfloat'
SOCKET = Path(f'/tmp/ytfloat-{os.getuid()}/player.sock')

def run(*args, executable=CLI):
    p = subprocess.run([str(executable), *args], capture_output=True, text=True, timeout=15)
    if p.returncode:
        raise AssertionError(f'{args}: {p.stderr}')
    return p.stdout

def status(executable=CLI):
    return json.loads(run('--status', executable=executable))

def until(check, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = check()
            if value: return value
        except (AssertionError, OSError, ValueError): pass
        time.sleep(.1)
    raise AssertionError('Timed out waiting for app state')

def quit_app(executable=CLI):
    run('--quit', executable=executable)
    until(lambda: not SOCKET.exists())
    time.sleep(.3)

def check_single_instance():
    pids = subprocess.check_output(['pgrep', '-x', 'YTFloat'], text=True).split()
    assert len(pids) == 1, pids

run('--show')
before = status()
quit_app()
with ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(lambda _: run('https://youtu.be/M7lc1UVf-VE?t=30'), range(6)))
# Verify status without a separate readiness branch: a queued command is acknowledged only after handling.
first = status()
assert first['video'] == 'M7lc1UVf-VE' and first['start'] == 30, first
assert first['opacity'] == before['opacity'] and first['floating'] == before['floating']
check_single_instance()
print('PASS concurrent cold launch; one player; persisted window preferences')

for _ in range(40): assert status()['pid'] == first['pid']
run('--hide'); assert not status()['visible']
run('--show'); assert status()['visible']
run('https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=12')
replacement = status()
assert replacement['pid'] == first['pid'] and replacement['video'] == 'dQw4w9WgXcQ'
assert replacement['start'] == 12 and replacement['width'] == first['width']
assert replacement['pageURL'] == first['pageURL']
print('PASS repeated IPC, hide/show, replacement without a new process, window, or WebView page')

page = until(lambda: status()['pageURL'])
with urllib.request.urlopen(page, timeout=3) as response:
    assert response.status == 200 and b'player.js' in response.read()
    assert response.headers['Referrer-Policy'] == 'strict-origin-when-cross-origin'
url = urllib.parse.urlsplit(page)
connection = http.client.HTTPConnection(url.hostname, url.port, timeout=3)
connection.request('GET', url.path, headers={'Host':'attacker.invalid'})
assert connection.getresponse().status == 400
connection.close()
listeners = subprocess.check_output(['lsof','-nP','-a','-p',str(first['pid']),'-iTCP','-sTCP:LISTEN'], text=True)
assert f'127.0.0.1:{url.port}' in listeners and '*:' not in listeners, listeners
print('PASS HTTP assets, real origin, Host validation, loopback-only listener')

invalid = subprocess.run([str(CLI), 'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ'], capture_output=True)
assert invalid.returncode != 0
subprocess.run(['/usr/bin/open','-n',str(APP)], check=True)
time.sleep(.6); check_single_instance()
print('PASS invalid URL rejection and direct duplicate launch protection')

old_pid = status()['pid']
os.kill(old_pid, signal.SIGKILL)
time.sleep(.4)
run('--show')
assert status()['pid'] != old_pid
check_single_instance()
print('PASS recovery after unexpected termination and stale socket')

quit_app()
assert not SOCKET.exists()
print('PASS clean shutdown removes socket')

relocated = Path('/tmp/YTFloat-relocation-check/YTFloat.app')
relocated.parent.mkdir(exist_ok=True)
subprocess.run(['ditto',str(APP),str(relocated)],check=True)
other_cli = relocated / 'Contents/Helpers/ytfloat'
run('--show', executable=other_cli)
relocated_status = until(lambda: status(other_cli) if status(other_cli)['pageURL'] else None)
with urllib.request.urlopen(relocated_status['pageURL'], timeout=3) as response:
    assert response.status == 200 and b'player.js' in response.read()
quit_app(other_cli)
print('PASS relocated app loads bundled resources')

run('--show')
run('https://youtu.be/M7lc1UVf-VE')
print('PASS all integration checks; original app reopened')
