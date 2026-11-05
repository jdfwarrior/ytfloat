# YTFloat

A small, native macOS YouTube player. One floating window, one system `WKWebView`, no bundled browser engine or third-party runtime.

[![Build and Release](https://github.com/jdfwarrior/ytfloat/actions/workflows/build-release.yml/badge.svg)](https://github.com/jdfwarrior/ytfloat/actions/workflows/build-release.yml)

[Download the latest release](https://github.com/jdfwarrior/ytfloat/releases/latest). Choose `arm64` for Apple Silicon or `x86_64` for Intel, extract the ZIP, and move `YTFloat.app` into Applications. Downloaded builds are ad-hoc signed, not Developer ID signed or notarized; macOS may require approval in Privacy & Security before opening them.

- Borderless 480 × 270 player with rounded corners; minimum 320 × 180.
- Native Liquid Glass controls on macOS 26 and later; native visual material on macOS 14–15. Interactive glass on macOS 27 when compiled with its SDK.
- Native traffic lights, draggable header, all-edge resizing, 16:9 aspect lock, and zoom/restore without entering fullscreen.
- Persistent always-on-top, opacity, autoplay, playback controls, overlay timeout, and Spaces preferences.
- Menu bar access without a Dock icon. Closing quits; minimizing and hiding keep audio playing.
- A private Unix socket lets every `ytfloat` command reuse the same app and window.

## Build and launch

Requires a Mac and the macOS 26 SDK or later (Xcode 26+ or matching Command Line Tools). Runs on macOS 14 or later. The build targets your Mac’s architecture; the checked local build is Apple Silicon.

```sh
./script/build_and_run.sh
```

The Codex **Run** button invokes the same script. It quits the old app, builds an optimized Release version, stages `dist/YTFloat.app`, signs it locally, and launches the bundle. No paid developer account is needed.

Build without launching:

```sh
./script/build.sh
```

Other development modes:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
CONFIGURATION=debug ./script/build_and_run.sh
```

The scripts select SwiftPM’s native build backend for compatibility with Command Line Tools. The Xcode project is an independent build path and does not require SwiftPM packages or network dependency resolution.

### Xcode

Open `YTFloat.xcodeproj`, select the shared **YTFloat** scheme, and run. The project builds the app and embeds the CLI in `Contents/Helpers/ytfloat`.

```sh
xcodebuild -project YTFloat.xcodeproj -scheme YTFloat \
  -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build
```

The Xcode project is checked in. If you add or remove Swift source files, regenerate it with `python3 script/generate_xcode_project.py`. Core logic is compiled directly into each Xcode target; SwiftPM builds it as the shared `YTFloatCore` module. Both paths use the same source files.

## Install

```sh
./script/install.sh
```

Defaults to `~/Applications/YTFloat.app` and a CLI symlink at `~/.local/bin/ytfloat`. Add `~/.local/bin` to your shell’s `PATH` if needed. Custom destinations:

```sh
./script/install.sh /Applications/YTFloat.app /usr/local/bin
```

The destination directories must be writable. The app and CLI work together without launching the app manually. Keep the CLI inside the app and link to it: moving the app requires rerunning the installer to update the link.

The app executable and CLI have different directories because `YTFloat` and `ytfloat` would collide on standard case-insensitive Mac volumes. The SwiftPM CLI build product is named `ytfloat-cli`; the packaged command is `ytfloat`.

## Usage

```sh
ytfloat 'https://www.youtube.com/watch?v=M7lc1UVf-VE'
ytfloat 'https://youtu.be/M7lc1UVf-VE?t=1m30s'
ytfloat 'https://youtube.com/shorts/VIDEO_ID'
ytfloat 'https://youtube.com/live/VIDEO_ID'
ytfloat 'https://youtube.com/embed/VIDEO_ID?start=90'
ytfloat --show
ytfloat --hide
ytfloat --quit
ytfloat --status
ytfloat --help
```

Quote URLs containing `&` or `?`. IDs must have 11 URL-safe characters. Start times support integer seconds and `1h2m30s` durations, limited to seven days. Credentials, custom ports, unrelated hosts, and ambiguous duplicate parameters are rejected.

`--show` launches if necessary. `--hide` and `--quit` are harmless when the app is stopped. `--status` prints JSON containing the process ID, requested video/start time, player state, window settings, local page URL, and iframe Referer observed by WebKit. `YTFLOAT_APP=/path/to/YTFloat.app` overrides app discovery.

Without installation, substitute `dist/YTFloat.app/Contents/Helpers/ytfloat` for `ytfloat`.

## Window and playback

Move the pointer into the window to reveal its compact native control bar. Drag its title area to move the window, or double-click it to zoom/restore. Drag any edge or corner to resize. The green traffic light fits the player within the usable display, preserving aspect ratio when locked. It never switches to fullscreen.

The pin toggles always-on-top. The gear opens native preferences. Opacity applies live from 35% to 100%. Controls fade after 2, 3, or 5 seconds of inactivity, remain available while hovered, and disappear when the pointer leaves. Window controls remain available even when playback controls are turned off.

YouTube’s official player supplies play/pause, seek, elapsed time, volume/mute, captions, and playback speed. There is no duplicate transport toolbar. Toggling playback controls rebuilds only the iframe and preserves playback position, volume, mute state, and whether playback was active; ordinary video replacement reuses the existing iframe.

| Shortcut | Action |
| --- | --- |
| ⌘O | Open a YouTube link |
| ⌘V | Open a link from the clipboard |
| ⌘, | Settings |
| ⌘M | Minimize |
| ⌘W / ⌘Q | Quit |
| Space / Left / Right | Playback / seek when focus is on the native window; YouTube also supplies its own keyboard controls |

Minimizing or hiding does not pause an already-playing video. Restoring never forces playback to resume if you paused it. Autoplay affects newly opened videos. WebKit can still require a user click; a fallback play button appears when autoplay is blocked. Closing quits and releases server, socket, and WebKit resources. The previous window frame is restored and clamped to connected displays.

## Architecture and security

- **AppKit:** An accessory application and a single `NSWindow`. Native controls and `NSPopover` settings. `NSGlassEffectView` is availability-gated; the video itself has no glass layer.
- **Network.framework:** A dynamic TCP port bound explicitly to `127.0.0.1`. Only three fixed assets are served beneath a random per-launch path. No directory traversal, filesystem browsing, proxy, CORS access, or HTTP command endpoints. Host headers, methods, header sizes, connection counts, and request timeouts are bounded.
- **WebKit:** The player page is loaded with `WKWebView.load(URLRequest)` from real HTTP, never `file://`, `loadHTMLString`, or a data URL. The page, server, and iframe set `strict-origin-when-cross-origin`. The IFrame API receives the actual loopback origin; WebKit supplies that origin as the embed request’s HTTP Referer. No request interception or certificate bypass is used.
- **IPC:** `/tmp/ytfloat-UID` must be an owned, private directory (0700), not a symlink. The socket is 0600. A lifetime `flock` guards app creation and stale socket removal. A separate launch lock serializes CLI cold starts. Direct duplicate app launches are protected too. Lock files intentionally remain; kernel locks disappear when a process exits.
- **Preferences:** `UserDefaults` under `app.ytfloat.YTFloat`. Video URLs are validated again when decoded from IPC. JavaScript receives structured arguments through WebKit instead of interpolated strings. Only the local main frame can invoke the native bridge.

The app has no analytics, API keys, account requirement, or bundled runtime. YouTube receives normal embedded-player network requests and can use its own cookies. The system WebKit data store is isolated to this app.

### Playback limitations

Some videos disable embedding, require sign-in or age verification, or have regional restrictions. YTFloat presents the player error with retry and “Open on YouTube” actions. Error 153 indicates rejected client identity/referrer; it is diagnosed explicitly. Internet access and YouTube availability are required. A valid referrer cannot make every video embeddable.

The compact minimum size follows the requested 320 × 180 design; 480 × 270 or larger is preferable for YouTube controls. Universal binaries, distribution signing, and notarization are not configured for this initial local build. Builds are ad-hoc signed for local use.

References: [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference), [embedded-player client identity](https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity), [AppKit Liquid Glass](https://developer.apple.com/documentation/appkit/nsglasseffectview).

## Tests and verification

```sh
./script/test.sh
python3 script/smoke_test.py
```

The ten Swift Testing tests cover supported and unsafe URLs, time parsing, decoder validation, preference persistence/clamping, concurrent IPC, duplicate-instance locking, delayed command bytes, stale sockets, private-directory validation, real HTTP responses, fixed routes, and method restrictions.

The integration script needs a logged-in graphical Mac. It changes the current video and restarts the app, including one deliberate forced termination. It checks simultaneous cold launches, repeated commands, video replacement, hide/show, Host validation, loopback binding, invalid inputs, direct duplicate launch protection, stale-socket recovery, shutdown, and a relocated app bundle. It reopens the original app afterward.

See `VALIDATION.md` for measured size, memory, and the checks actually completed on this Mac. macOS 14–15 fallback appearance and the full Xcode build must be checked separately on those installations.

## Source layout

- `Sources/YTFloat/App`: lifecycle, menu bar, commands, window persistence.
- `Sources/YTFloat/Window`: borderless window, glass chrome, tracking, dragging, resizing.
- `Sources/YTFloat/Player`: WebKit bridge and navigation.
- `Sources/YTFloat/Settings`: native preferences popover.
- `Sources/YTFloat/Resources`: plain HTML/CSS/JavaScript player.
- `Sources/YTFloatCore`: URL parsing, preferences, HTTP, and IPC.
- `Sources/CLI`: terminal launcher.
- `Tests/YTFloatCoreTests`: automated tests.
- `script`: build, run, installation, tests, and Xcode generation.

The icon is deterministic vector artwork generated with AppKit by `script/make_icon.swift`; the packaged `.icns` is checked in under `Config`.

## Automated builds and releases

GitHub Actions runs the core tests and builds both the Swift package and Xcode project on macOS 26, separately for Apple Silicon and Intel. Every push to `main`, pull request, and manual workflow run produces downloadable ZIP artifacts with SHA-256 checksums.

Pushing a version tag publishes a GitHub release after both builds pass:

```sh
# First update CFBundleShortVersionString and CFBundleVersion in Config/Info.plist.
git add Config/Info.plist
git commit -m "Bump version to 1.0.1"
git tag v1.0.1
git push origin main v1.0.1
```

The tag must match `CFBundleShortVersionString` exactly, prefixed with `v`. The CLI reads its version from the app bundle, so it stays consistent with the release. The workflow verifies archive checksums before publication and supports rerunning an existing tag to replace its assets. No personal access token or Apple signing secrets are needed; only the release job receives permission to write release contents.

To produce the same architecture-specific archive locally:

```sh
./script/package_release.sh
```

ZIPs and checksum files are written under `dist/releases`. The macOS 27-only interactive-glass API is compiled only when the build SDK supports it; macOS 26 CI builds retain native Liquid Glass using its macOS 26 APIs.
