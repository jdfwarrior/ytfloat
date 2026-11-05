import AppKit

final class FloatingWindow: NSWindow {
    var onActivity: (() -> Void)?
    var onOpen: (() -> Void)?
    var onPaste: (() -> Void)?
    var onSettings: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onSeek: ((Int) -> Void)?
    var lockAspect = true
    private var frameBeforeZoom: NSRect?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                   styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        title = "YTFloat"
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 320, height: 180)
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown: onActivity?()
        default: break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "o": onOpen?()
            case "v": onPaste?()
            case ",": onSettings?()
            case "w", "q": NSApp.terminate(nil)
            case "m": miniaturize(nil)
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        // WebKit retains its own keyboard interaction when the iframe is focused.
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: onTogglePlayback?()
        case 123: onSeek?(-5)
        case 124: onSeek?(5)
        default: super.keyDown(with: event)
        }
    }

    func toggleZoom() {
        if let frameBeforeZoom {
            setFrame(frameBeforeZoom, display: true, animate: true)
            self.frameBeforeZoom = nil
        } else if let screen = screen ?? NSScreen.main {
            frameBeforeZoom = frame
            var target = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            if lockAspect {
                let size = NSSize(width: min(target.width, target.height * 16 / 9), height: min(target.height, target.width * 9 / 16))
                target = NSRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height)
            }
            setFrame(target, display: true, animate: true)
        }
    }

    func cancelZoomRestore() { frameBeforeZoom = nil }
}

/// Narrow hit regions leave video interaction intact and make every border resizable.
final class ResizeEdge: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    struct Sides: OptionSet {
        let rawValue: Int
        static let left = Sides(rawValue: 1), right = Sides(rawValue: 2)
        static let bottom = Sides(rawValue: 4), top = Sides(rawValue: 8)
    }
    let sides: Sides
    init(_ sides: Sides) { self.sides = sides; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func resetCursorRects() {
        let horizontal = sides.contains(.left) || sides.contains(.right)
        let vertical = sides.contains(.top) || sides.contains(.bottom)
        let cursor: NSCursor
        if #available(macOS 15.0, *), horizontal && vertical {
            cursor = NSCursor.frameResize(position: sides.contains(.left)
                ? (sides.contains(.top) ? .topLeft : .bottomLeft)
                : (sides.contains(.top) ? .topRight : .bottomRight), directions: .all)
        } else { cursor = horizontal ? .resizeLeftRight : .resizeUpDown }
        addCursorRect(bounds, cursor: cursor)
    }

    private var initialFrame: NSRect?
    private var initialPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        guard let window = window as? FloatingWindow else { return }
        window.cancelZoomRestore()
        initialFrame = window.frame
        initialPoint = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) { resize(with: event) }

    override func mouseUp(with event: NSEvent) {
        resize(with: event)
        initialFrame = nil
        initialPoint = nil
    }

    private func resize(with event: NSEvent) {
        guard let window = window as? FloatingWindow,
              let initial = initialFrame, let start = initialPoint else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        var width = initial.width, height = initial.height
        if sides.contains(.left) { width -= dx }
        if sides.contains(.right) { width += dx }
        if sides.contains(.top) { height += dy }
        if sides.contains(.bottom) { height -= dy }
        if window.lockAspect {
            let horizontal = sides.contains(.left) || sides.contains(.right)
            let vertical = sides.contains(.top) || sides.contains(.bottom)
            if horizontal && (!vertical || abs(dx) > abs(dy) * 16 / 9) {
                width = max(320, width); height = width * 9 / 16
            } else { height = max(180, height); width = height * 16 / 9 }
        } else { width = max(320, width); height = max(180, height) }
        let x = sides.contains(.left) ? initial.maxX - width : initial.minX
        let y = sides.contains(.bottom) ? initial.maxY - height : initial.minY
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
