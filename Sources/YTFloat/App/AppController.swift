import AppKit
import OSLog
#if SWIFT_PACKAGE
import YTFloatCore
#endif

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let preferences = Preferences()
    private var window: FloatingWindow!
    private var player: PlayerController!
    private var playerView: PlayerView!
    private var server: HTTPServer?
    private var ipc: IPCServer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var openingLink = false
    private var saveTask: DispatchWorkItem?
    private let logger = Logger(subsystem: "app.ytfloat.YTFloat", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let paths = try IPCPaths()
            do {
                ipc = try IPCServer(paths: paths) { [weak self] command, reply in
                    DispatchQueue.main.async { reply(self?.handle(command) ?? CommandReply(ok: false, message: "Player is closing.")) }
                }
            } catch IPCError.alreadyRunning {
                _ = try? IPCClient.send(Command(.show), paths: paths)
                NSApp.terminate(nil)
                return
            }
            setupWindow()
            setupMenus()
            try startServer()
            showPlayer()
        } catch { fatalAlert(error) }
    }

    private func setupWindow() {
        window = FloatingWindow()
        window.delegate = self
        player = PlayerController(preferences: preferences)
        player.onOpen = { [weak self] in self?.openLink() }
        player.onExternal = { [weak self] in self?.openOnYouTube() }
        player.onTitle = { [weak self] title in self?.window.title = title; self?.playerView.setTitle(title) }
        playerView = PlayerView(webView: player.webView, preferences: preferences,
            close: { NSApp.terminate(nil) }, minimize: { [weak self] in self?.window.miniaturize(nil) },
            zoom: { [weak self] in self?.window.toggleZoom() },
            settings: { [weak self] in self?.showSettings() },
            togglePin: { [weak self] in
                guard let self else { return }
                self.preferences.alwaysOnTop.toggle(); self.applyPreferences()
            })
        window.contentView = playerView
        window.onActivity = { [weak self] in self?.playerView.activity() }
        window.onOpen = { [weak self] in self?.openLink() }
        window.onPaste = { [weak self] in self?.pasteLink() }
        window.onSettings = { [weak self] in self?.showSettings() }
        window.onTogglePlayback = { [weak self] in self?.player.togglePlayback() }
        window.onSeek = { [weak self] delta in self?.player.seek(delta) }
        restoreWindow()
        applyPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func startServer() throws {
        let resources = Bundle.main.resourceURL!.appendingPathComponent("Resources")
        var assets: [String: HTTPServer.Asset] = [:]
        for (name, type) in [("index.html", "text/html; charset=utf-8"), ("player.js", "text/javascript; charset=utf-8"), ("player.css", "text/css; charset=utf-8")] {
            assets[name] = HTTPServer.Asset(data: try Data(contentsOf: resources.appendingPathComponent(name)), contentType: type)
        }
        server = try HTTPServer(assets: assets)
        server?.start { [weak self] result in
            switch result {
            case .success(let url): self?.player.start(at: url)
            case .failure(let error): self?.fatalAlert(error)
            }
        }
    }

    private func handle(_ command: Command) -> CommandReply {
        guard window != nil else { return CommandReply(ok: false, message: "YTFloat is starting. Try again shortly.") }
        switch command.action {
        case .video:
            guard let video = command.video else { return CommandReply(ok: false, message: "Missing video.") }
            showPlayer()
            player.open(video)
            playerView.setTitle("Loading video…")
        case .show: showPlayer()
        case .hide: popover?.close(); window.orderOut(nil)
        case .quit:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
        case .status:
            let payload: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                "video": player.currentVideo?.id ?? "", "start": player.currentVideo?.start ?? 0,
                "state": player.state, "pageURL": player.pageURL?.absoluteString ?? "",
                "embedReferer": player.embedReferer, "visible": window.isVisible,
                "minimized": window.isMiniaturized, "floating": window.level == .floating,
                "opacity": window.alphaValue, "width": window.frame.width, "height": window.frame.height]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
                return CommandReply(message: json)
            }
            return CommandReply(ok: false, message: "Status is unavailable.")
        }
        return CommandReply()
    }

    @objc private func showPlayer() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        ensureVisible()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPreferences() {
        guard window != nil else { return }
        window.level = preferences.alwaysOnTop ? .floating : .normal
        window.alphaValue = preferences.opacity
        window.lockAspect = preferences.lockAspect
        window.contentAspectRatio = preferences.lockAspect ? NSSize(width: 16, height: 9) : .zero
        window.collectionBehavior = preferences.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        if preferences.lockAspect, abs(window.frame.width / window.frame.height - 16 / 9) > 0.01 {
            var frame = window.frame
            let height = max(180, frame.width * 9 / 16)
            frame.origin.y += frame.height - height
            frame.size = NSSize(width: height * 16 / 9, height: height)
            window.setFrame(frame, display: true)
            ensureVisible()
        }
        player?.applyPreferences()
        playerView?.updatePin()
    }

    @objc private func showSettings() {
        if let popover, popover.isShown { popover.close(); return }
        playerView.keepControlsVisible = true
        playerView.activity()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = SettingsController(preferences: preferences) { [weak self] in self?.applyPreferences() }
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.delegate = self
        self.popover = popover
        popover.show(relativeTo: playerView.settingsButton.bounds, of: playerView.settingsButton, preferredEdge: .minY)
    }
    func popoverDidClose(_ notification: Notification) {
        playerView.keepControlsVisible = false
        playerView.activity()
        popover = nil
    }

    @objc private func openLink() {
        guard !openingLink else { return }
        showPlayer()
        popover?.close()
        openingLink = true
        let alert = NSAlert()
        alert.messageText = "Open a YouTube link"
        alert.informativeText = "Watch, Shorts, live, and shortened links all work."
        alert.addButton(withTitle: "Open Video")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        field.placeholderString = "https://youtu.be/…"
        if let copied = NSPasteboard.general.string(forType: .string), (try? VideoRequest(url: copied)) != nil { field.stringValue = copied }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            self.openingLink = false
            guard result == .alertFirstButtonReturn else { return }
            self.openURL(field.stringValue)
        }
    }

    @objc private func pasteLink() {
        guard let text = NSPasteboard.general.string(forType: .string) else { openLink(); return }
        openURL(text)
    }
    private func openURL(_ text: String) {
        do { _ = handle(Command(.video, video: try VideoRequest(url: text))) }
        catch {
            let alert = NSAlert(); alert.messageText = "That link couldn’t be opened"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }
    @objc private func openOnYouTube() { if let url = player.currentVideo?.url { NSWorkspace.shared.open(url) } }
    @objc private func togglePlayback() { player.togglePlayback() }
    @objc private func hidePlayer() { window.orderOut(nil) }
    @objc private func zoomPlayer() { window.toggleZoom() }
    @objc private func minimizePlayer() { window.miniaturize(nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func setupMenus() {
        let main = NSMenu()
        let app = NSMenu()
        add("About YTFloat", to: app, selector: #selector(about))
        app.addItem(.separator())
        add("Settings…", to: app, selector: #selector(showSettings), key: ",")
        app.addItem(.separator())
        add("Quit YTFloat", to: app, selector: #selector(quit), key: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let file = NSMenu(title: "File")
        add("Open YouTube Link…", to: file, selector: #selector(openLink), key: "o")
        add("Paste YouTube Link", to: file, selector: #selector(pasteLink), key: "v")
        add("Open on YouTube", to: file, selector: #selector(openOnYouTube))
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)
        let controls = NSMenu(title: "Window")
        add("Show Player", to: controls, selector: #selector(showPlayer))
        add("Hide Player", to: controls, selector: #selector(hidePlayer), key: "h")
        add("Minimize", to: controls, selector: #selector(minimizePlayer), key: "m")
        add("Zoom", to: controls, selector: #selector(zoomPlayer))
        let controlsItem = NSMenuItem(); controlsItem.submenu = controls; main.addItem(controlsItem)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: "YTFloat")
        let status = NSMenu()
        add("Show Player", to: status, selector: #selector(showPlayer))
        add("Open YouTube Link…", to: status, selector: #selector(openLink))
        add("Play / Pause", to: status, selector: #selector(togglePlayback))
        status.addItem(.separator())
        add("Settings…", to: status, selector: #selector(showSettings))
        status.addItem(.separator())
        add("Quit YTFloat", to: status, selector: #selector(quit))
        statusItem?.menu = status
    }
    private func add(_ title: String, to menu: NSMenu, selector: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self; menu.addItem(item)
    }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "YTFloat", .applicationVersion: "1.0", .credits: NSAttributedString(string: "A little window for YouTube.\nNative Swift · AppKit · WebKit")]) }

    private func restoreWindow() {
        if let stored = preferences.defaults.string(forKey: "windowFrame") {
            let frame = NSRectFromString(stored)
            if [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }), frame.width >= 320, frame.height >= 180 { window.setFrame(frame, display: false) }
            else { window.center() }
        } else { window.center() }
        ensureVisible()
    }
    private func ensureVisible() {
        guard let window, let screen = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(window.frame).area < $1.visibleFrame.intersection(window.frame).area
        }) else { return }
        let usable = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var frame = window.frame
        let scale = min(1, usable.width / frame.width, usable.height / frame.height)
        frame.size.width *= scale; frame.size.height *= scale
        frame.origin.x = min(max(frame.minX, usable.minX), usable.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, usable.minY), usable.maxY - frame.height)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }
    @objc private func screensChanged() { ensureVisible() }
    func windowDidMove(_ notification: Notification) { scheduleSave() }
    func windowDidResize(_ notification: Notification) { scheduleSave() }
    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveFrame() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }
    private func saveFrame() { if let window { preferences.defaults.set(NSStringFromRect(window.frame), forKey: "windowFrame") } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPlayer(); return false }
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first { openURL(url.absoluteString) } }
    func applicationWillTerminate(_ notification: Notification) {
        saveTask?.cancel(); saveFrame()
        playerView?.stop(); player?.stop()
        ipc?.stop(); ipc = nil
        server?.stop(); server = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        NotificationCenter.default.removeObserver(self)
    }
    private func fatalAlert(_ error: Error) {
        logger.error("Startup failed: \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert(); alert.messageText = "YTFloat couldn’t start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
