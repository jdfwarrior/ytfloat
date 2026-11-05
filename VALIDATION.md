# YTFloat validation

Validated on November 4, 2026, on Apple Silicon, macOS 27.3 (26C5035r), using Apple Swift 6.4 and the macOS 27 SDK from Command Line Tools. No full Xcode installation was available.

## Delivered artifacts

- Installed app: `~/Applications/YTFloat.app`
- Release build: `dist/YTFloat.app`
- Terminal command: `/opt/homebrew/bin/ytfloat`, linked to the installed app’s `Contents/Helpers/ytfloat`.
- An additional installer-default symlink exists at `~/.local/bin/ytfloat`.
- Source, Xcode project, Swift package, build/run/install scripts, tests, and Codex Run action are included.
- The installed app was launched and its welcome screen visually inspected. It is left open at 480 × 270 with default preferences.

## Results

| Check | Result |
| --- | --- |
| Optimized Release build and bundle staging | Passed |
| Ad-hoc app and helper signatures (`codesign --verify --deep --strict`) | Passed |
| Ten Swift Testing tests | Passed |
| Six simultaneous cold-start URL commands | One process and one player |
| Forty consecutive status commands | Passed |
| Replacement video and start time | Same PID, window dimensions, and WebView page URL |
| Direct duplicate app launch (`open -n`) | Existing instance retained |
| Hide and restore | Passed |
| Minimize and CLI restore | Same PID and active playback; 480 × 270 restored |
| Green control zoom and restore | 480 × 270 → 1686 × 949 → 480 × 270; no fullscreen |
| Edge and corner resize | Visually verified; 320 × 180 minimum and return to 480 × 270 |
| Aspect ratio unlocked | Free resizing with normal video letterboxing; lock restored correctly |
| Floating level and opacity | UI changes confirmed in app status; 75% opacity and normal level persisted across restart |
| Autoplay preference | Enabled playback observed; disabled preference yielded a cued video on next launch |
| Playback controls preference | Iframe rebuilt with `controls=0`, then `controls=1`; playback continued |
| Native settings and Liquid Glass | Visually verified on macOS 27 |
| Hover chrome | Visible over video/settings and hidden when idle/outside |
| Keyboard close | App terminated and command socket removed; installed CLI relaunched it |
| Forced termination / stale socket | Next invocation recovered with a new PID |
| Relocated bundle | Local page loaded from a copy in `/tmp`; no build-folder resource dependency |
| HTTP Host validation | Unexpected Host rejected with 400 |
| HTTP server binding | `lsof` confirmed `127.0.0.1` only, on a dynamic port |
| Unexpected files and mutating methods | 404 and 405 in real HTTP tests |
| Private IPC directory and symlink validation | Passed |
| Delayed IPC client bytes | Passed; accepted sockets explicitly clear inherited nonblocking mode |
| Invalid and lookalike YouTube hosts | Rejected |

The integration script completed all eight reported phases. The full test/build/integration sequence was rerun after the substantive socket and window changes. The final keyboard-close adjustment was subsequently rebuilt, installed, signed, and directly verified through the UI and socket removal.

Window title dragging is delegated to AppKit’s `NSWindow.performDrag(with:)`, including first-click support and a title hit region. Automated coordinate dragging through this runner was not a reliable way to measure its displacement; exact title-drag tracking should receive a human usability check. Custom edge and corner resizing was verified independently and does not use a nested mouse-event loop or the competing native border resize handler.

## Playback and referrer evidence

The installed app played the official YouTube IFrame API sample, `M7lc1UVf-VE`, with native status reporting `playing`. The UI showed changing frames, elapsed time, captions, and official playback controls.

Observed installed-app page:

```text
http://127.0.0.1:62126/<per-launch-random-path>/index.html
```

Observed iframe navigation Referer:

```text
http://127.0.0.1:62126/
```

Both the port and asset path change at each launch. The IFrame API’s `origin` parameter matched that actual HTTP origin. Playback succeeded without suppressing WebKit networking protections or substituting file/data HTML. This sample does not imply that restricted or non-embeddable videos will work.

## Size

Final locally signed Release build, optimized with `-Osize` and stripped of local symbols:

| Artifact | Measured size |
| --- | ---: |
| GUI executable | 289,200 bytes |
| CLI executable | 188,912 bytes |
| Complete app, including icon and player assets | 916 KiB allocated on disk (`du -sk`) |

The icon accounts for approximately 419 KiB of file data. No browser engine, JavaScript runtime, third-party package, or Swift runtime is bundled.

## Memory

Single resident-memory snapshots of the **native YTFloat host process**, taken from `ps -o rss=` for the installed executable at 480 × 270 and 100% opacity:

| State | Host RSS |
| --- | ---: |
| Welcome screen, `state=idle` | 91,600 KiB / 89.45 MiB |
| Sample video, `state=playing` | 100,128 KiB / 97.78 MiB |

These measurements **exclude separate WebKit WebContent, networking, and GPU helper processes**. They are not total playback memory, private-memory measurements, averages, or benchmarks. Shared framework pages, graphics backing, caches, process warmup, video quality, and window size affect RSS. Total WebKit playback memory was not reliably attributed and is not claimed here.

The measured process path was `~/Applications/YTFloat.app/Contents/MacOS/YTFloat`. No continuous player-state polling is used by the app. Timers are limited to hover hiding, startup/network timeouts, and debounced preference saves.

## Remaining platform checks

- Full Xcode build was not executed because only Command Line Tools are installed. The checked-in project and Info.plist passed `plutil` validation; its shared scheme is included.
- macOS 14–15 fallback materials and macOS 26 glass were not separately run. Availability guards retain the macOS 14 deployment target; macOS 27 glass was tested.
- Multi-monitor hardware rearrangement, extended playback/memory soak testing, and external distribution signing/notarization were not exercised.
- This initial build is native Apple Silicon, not Universal.
