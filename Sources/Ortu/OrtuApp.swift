import AppKit

@main
@MainActor
enum OrtuApplication {
    static func main() {
        if runPackValidationCommandIfRequested() { return }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private static func runPackValidationCommandIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.count == 3, arguments[1] == "--validate-pack" else { return false }

        let sourceURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ortu-validate-\(UUID().uuidString).ortupack",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            let validated: ValidatedCoverPack
            if values.isDirectory == true {
                validated = try CoverPackValidator().validate(at: sourceURL)
            } else {
                try CoverPackArchive().extract(sourceURL, to: staging)
                validated = try CoverPackValidator().validate(at: staging)
            }
            print(L10n.text("cli.pack.valid", validated.manifest.id, validated.manifest.version))
        } catch {
            let message = L10n.text("cli.pack.invalid", error.localizedDescription)
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
        return true
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var shortcutController: GlobalShortcutController?
    private weak var toggleMenuItem: NSMenuItem?
    private weak var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        model.onDrapeStateChange = { [weak self] isDraped in
            self?.updateToggleTitle(isDraped: isDraped)
        }
        model.onLaunchAtLoginChange = { [weak self] enabled in
            self?.launchAtLoginMenuItem?.state = enabled ? .on : .off
        }
        shortcutController = GlobalShortcutController { [weak self] in
            self?.model.toggleDrape()
        }

        if ProcessInfo.processInfo.arguments.contains("--drape") {
            model.drapeCover()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let packageURLs =
            filenames
            .map(URL.init(fileURLWithPath:))
            .filter { $0.pathExtension.lowercased() == "ortupack" }
        guard !packageURLs.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        Task {
            var didImport = false
            for url in packageURLs {
                didImport = await model.importCoverPack(from: url) || didImport
            }
            model.openSettings()
            sender.reply(toOpenOrPrint: didImport ? .success : .failure)
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset",
            accessibilityDescription: L10n.text("app.name")
        )
        statusItem.button?.toolTip = L10n.text("app.tooltip")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: L10n.text("menu.drape"),
            action: #selector(toggleCover),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.keyEquivalent = "o"
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        let settingsItem = NSMenuItem(
            title: L10n.text("menu.settings"),
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchItem = NSMenuItem(
            title: L10n.text("menu.launch_at_login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = model.launchAtLogin ? .on : .off
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.text("menu.quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        self.statusItem = statusItem
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            guard let button = statusItem?.button, let statusMenu else { return }
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
        } else {
            model.toggleDrape()
        }
    }

    private func updateToggleTitle(isDraped: Bool) {
        toggleMenuItem?.title = L10n.text(isDraped ? "menu.remove" : "menu.drape")
        statusItem?.button?.image = NSImage(
            systemSymbolName: isDraped ? "rectangle.topthird.inset.filled" : "rectangle.topthird.inset",
            accessibilityDescription: L10n.text(
                isDraped ? "accessibility.cover.draped" : "accessibility.cover.removed"
            )
        )
    }

    @objc private func toggleCover() {
        model.toggleDrape()
    }

    @objc private func openSettings() {
        model.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLogin)
    }

    @objc private func quit() {
        model.quit()
    }
}
