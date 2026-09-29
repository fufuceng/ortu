import AppKit
import CoreGraphics

@MainActor
final class OverlayCoordinator: NSObject, OverlayCoordinating {
    var onRequestFold: (() -> Void)?

    private var appearance = OverlayAppearance(
        opacity: 0.92,
        drop: 0.56,
        width: 0.96,
        dimAmount: 0.16,
        textureURL: nil,
        tintColor: nil
    )
    private var displayScope = DisplayScope.all
    private var windows: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var isVisible = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func update(appearance: OverlayAppearance) {
        self.appearance = appearance
        windows.values.forEach { $0.update(appearance: appearance) }
    }

    func update(displayScope: DisplayScope) {
        guard self.displayScope != displayScope else { return }
        self.displayScope = displayScope
        if isVisible { rebuildWindows() }
    }

    func show() {
        isVisible = true
        rebuildWindows()
        windows.values.forEach { $0.show() }
    }

    func hide(animated: Bool = true) {
        isVisible = false
        windows.values.forEach { $0.hide(animated: animated) }
        windows.removeAll()
    }

    @objc private func screenConfigurationDidChange() {
        guard isVisible else { return }
        rebuildWindows()
    }

    @objc private func sessionDidResignActive() {
        guard isVisible else { return }
        hide(animated: false)
        onRequestFold?()
    }

    private func rebuildWindows() {
        let targetScreens: [NSScreen]
        switch displayScope {
        case .all:
            targetScreens = NSScreen.screens
        case .primary:
            targetScreens = NSScreen.screens.first.map { [$0] } ?? []
        case .pointer:
            let pointerScreen =
                NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.screens.first
            targetScreens = pointerScreen.map { [$0] } ?? []
        }

        let screensByID = Dictionary(
            uniqueKeysWithValues: targetScreens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )

        let removedIDs = Set(windows.keys).subtracting(screensByID.keys)
        removedIDs.forEach {
            windows[$0]?.hide(animated: false)
            windows[$0] = nil
        }

        for (displayID, screen) in screensByID {
            if let existing = windows[displayID] {
                existing.move(to: screen)
                existing.update(appearance: appearance)
            } else {
                let controller = OverlayWindowController(
                    screen: screen,
                    appearance: appearance,
                    onRequestFold: { [weak self] in self?.onRequestFold?() }
                )
                windows[displayID] = controller
            }
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}

@MainActor
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
private final class OverlayWindowController {
    private let window: OverlayPanel
    private let overlayView: OverlayView

    init(screen: NSScreen, appearance: OverlayAppearance, onRequestFold: @escaping () -> Void) {
        overlayView = OverlayView(frame: .zero, appearance: appearance, onRequestFold: onRequestFold)
        window = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.contentView = overlayView
        overlayView.autoresizingMask = [.width, .height]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.ignoresMouseEvents = false
        window.animationBehavior = .none
        window.setFrame(screen.frame, display: false)
    }

    func move(to screen: NSScreen) {
        window.setFrame(screen.frame, display: false)
    }

    func update(appearance: OverlayAppearance) {
        overlayView.update(appearance: appearance)
    }

    func show() {
        overlayView.resetInteraction()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
    }

    func hide(animated: Bool) {
        let retainedWindow = window
        overlayView.dismiss(animated: animated) {
            retainedWindow.orderOut(nil)
        }
    }
}
