import AppKit
import WebKit
#if SWIFT_PACKAGE
import YTFloatCore
#endif

final class PlayerView: NSView {
    let settingsButton: NSButton
    let pinButton: NSButton
    private let chrome: NSView
    private let titleLabel = NSTextField(labelWithString: "YTFloat")
    private let webView: WKWebView
    private let preferences: Preferences
    private var tracking: NSTrackingArea?
    private var hideTask: DispatchWorkItem?
    private var inside = false
    private var edges: [ResizeEdge] = []
    var keepControlsVisible = false

    init(webView: WKWebView, preferences: Preferences, close: @escaping () -> Void,
         minimize: @escaping () -> Void, zoom: @escaping () -> Void,
         settings: @escaping () -> Void, togglePin: @escaping () -> Void) {
        self.webView = webView
        self.preferences = preferences
        settingsButton = Self.symbolButton("gearshape", label: "Settings", action: settings)
        pinButton = Self.symbolButton("pin.fill", label: "Always on Top", action: togglePin)
        let strip = DragStrip()
        let group = NSStackView()
        group.orientation = .horizontal
        group.spacing = 8
        for (type, name, action) in [
            (NSWindow.ButtonType.closeButton, "Close YTFloat", close),
            (.miniaturizeButton, "Minimize", minimize), (.zoomButton, "Zoom / Restore", zoom)
        ] {
            let button = NSWindow.standardWindowButton(type, for: [.titled]) ?? NSButton()
            button.isEnabled = true
            button.toolTip = name
            button.setAccessibilityLabel(name)
            button.target = ButtonAction.retain(on: button, action: action)
            button.action = #selector(ButtonAction.invoke)
            group.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 14).isActive = true
            button.heightAnchor.constraint(equalToConstant: 14).isActive = true
        }
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let trailing = NSStackView(views: [pinButton, settingsButton])
        trailing.spacing = 2
        strip.addSubview(group); strip.addSubview(titleLabel); strip.addSubview(trailing)
        for view in [group, titleLabel, trailing] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            group.widthAnchor.constraint(equalToConstant: 58),
            trailing.widthAnchor.constraint(equalToConstant: 58),
            group.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 12),
            group.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -5),
            trailing.centerYAnchor.constraint(equalTo: strip.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: group.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: strip.centerYAnchor)
        ])
        chrome = glassSurface(content: strip, radius: 16)
        chrome.appearance = NSAppearance(named: .darkAqua)
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        addSubview(webView)
        addSubview(chrome)
        chrome.alphaValue = 0
        chrome.isHidden = true
        for sides: ResizeEdge.Sides in [.left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]] {
            let edge = ResizeEdge(sides)
            edges.append(edge); addSubview(edge)
        }
        updatePin()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        webView.frame = bounds
        chrome.frame = NSRect(x: 8, y: bounds.height - 40, width: bounds.width - 16, height: 32)
        for edge in edges {
            let s = edge.sides
            let horizontal = s.contains(.left) || s.contains(.right)
            let vertical = s.contains(.top) || s.contains(.bottom)
            if horizontal && vertical {
                edge.frame = NSRect(x: s.contains(.left) ? 0 : bounds.width - 12,
                                    y: s.contains(.top) ? bounds.height - 12 : 0, width: 12, height: 12)
            } else if horizontal {
                edge.frame = NSRect(x: s.contains(.left) ? 0 : bounds.width - 5, y: 12, width: 5, height: bounds.height - 24)
            } else {
                edge.frame = NSRect(x: 12, y: s.contains(.top) ? bounds.height - 5 : 0, width: bounds.width - 24, height: 5)
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { inside = true; activity() }
    override func mouseMoved(with event: NSEvent) { activity() }
    override func mouseExited(with event: NSEvent) {
        guard !bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        inside = false
        if !keepControlsVisible { fadeOut() }
    }

    func activity() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        guard inside || keepControlsVisible else { return }
        hideTask?.cancel()
        chrome.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            chrome.animator().alphaValue = 1
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.keepControlsVisible else { return }
            if let window = self.window,
               self.chrome.frame.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)), self.inside { return }
            self.fadeOut()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.overlayTimeout, execute: task)
    }

    private func fadeOut() {
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            chrome.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.chrome.alphaValue == 0 { self?.chrome.isHidden = true }
        })
    }
    func setTitle(_ title: String) { titleLabel.stringValue = title }
    func updatePin() {
        pinButton.contentTintColor = preferences.alwaysOnTop ? .controlAccentColor : .labelColor
        pinButton.setAccessibilityValue(preferences.alwaysOnTop ? "On" : "Off")
        pinButton.toolTip = preferences.alwaysOnTop ? "Always on Top · On" : "Always on Top · Off"
    }
    func stop() { hideTask?.cancel() }

    private static func symbolButton(_ name: String, label: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: name, accessibilityDescription: label)!, target: nil, action: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = ButtonAction.retain(on: button, action: action)
        button.action = #selector(ButtonAction.invoke)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }
}

private var actionKey: UInt8 = 0
final class ButtonAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
    static func retain(on object: NSObject, action: @escaping () -> Void) -> ButtonAction {
        let target = ButtonAction(action)
        objc_setAssociatedObject(object, &actionKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return target
    }
}
