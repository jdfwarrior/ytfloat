import AppKit
#if SWIFT_PACKAGE
import YTFloatCore
#endif

final class SettingsController: NSViewController {
    private let preferences: Preferences
    private let changed: () -> Void
    private let opacityValue = NSTextField(labelWithString: "100%")

    init(preferences: Preferences, changed: @escaping () -> Void) {
        self.preferences = preferences; self.changed = changed
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 380))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        let title = NSTextField(labelWithString: "Make yourself comfortable")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(title)
        addToggle("Always on Top", symbol: "pin", key: "alwaysOnTop", value: preferences.alwaysOnTop, to: stack)
        addToggle("Show on All Spaces", symbol: "rectangle.on.rectangle", key: "allSpaces", value: preferences.allSpaces, to: stack)
        let line = NSBox(); line.boxType = .separator; stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let opacityHeader = NSStackView(views: [NSTextField(labelWithString: "Window Opacity"), NSView(), opacityValue])
        opacityHeader.widthAnchor.constraint(equalToConstant: 260).isActive = true
        opacityValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityValue.textColor = .secondaryLabelColor
        opacityValue.stringValue = "\(Int(preferences.opacity * 100))%"
        let slider = NSSlider(value: preferences.opacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel("Window Opacity")
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let opacityStack = NSStackView(views: [opacityHeader, slider]); opacityStack.orientation = .vertical; opacityStack.spacing = 5
        stack.addArrangedSubview(opacityStack)
        addToggle("Autoplay Videos", symbol: "play", key: "autoplay", value: preferences.autoplay, to: stack)
        addToggle("Lock Aspect Ratio", symbol: "aspectratio", key: "lockAspect", value: preferences.lockAspect, to: stack)
        addToggle("Playback Controls on Hover", symbol: "slider.horizontal.3", key: "showControls", value: preferences.showControls, to: stack)
        let timeout = NSPopUpButton()
        timeout.addItems(withTitles: ["2 seconds", "3 seconds", "5 seconds"])
        timeout.selectItem(at: [2.0, 3.0, 5.0].firstIndex(of: preferences.overlayTimeout) ?? 1)
        timeout.target = self; timeout.action = #selector(timeoutChanged(_:))
        timeout.controlSize = .small
        timeout.setAccessibilityLabel("Window Control Timeout")
        let timeoutRow = NSStackView(views: [NSTextField(labelWithString: "Hide Window Controls"), NSView(), timeout])
        timeoutRow.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(timeoutRow)
        let note = NSTextField(wrappingLabelWithString: "Minimizing keeps audio playing. Closing quits YTFloat.")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 260
        stack.addArrangedSubview(note)
    }

    private func addToggle(_ text: String, symbol: String, key: String, value: Bool, to stack: NSStackView) {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        let toggle = NSSwitch()
        toggle.state = value ? .on : .off
        toggle.controlSize = .small
        toggle.setAccessibilityLabel(text)
        toggle.target = ButtonAction.retain(on: toggle) { [weak self, weak toggle] in
            guard let self, let toggle else { return }
            self.preferences.defaults.set(toggle.state == .on, forKey: key)
            self.changed()
        }
        toggle.action = #selector(ButtonAction.invoke)
        let row = NSStackView(views: [image, label, NSView(), toggle])
        row.spacing = 9
        row.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(row)
    }
    @objc private func opacityChanged(_ slider: NSSlider) {
        preferences.opacity = slider.doubleValue
        opacityValue.stringValue = "\(Int(preferences.opacity * 100))%"
        changed()
    }
    @objc private func timeoutChanged(_ popup: NSPopUpButton) {
        preferences.overlayTimeout = [2.0, 3.0, 5.0][popup.indexOfSelectedItem]
        changed()
    }
}
