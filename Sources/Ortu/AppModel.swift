import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    var onDrapeStateChange: ((Bool) -> Void)?
    var onLaunchAtLoginChange: ((Bool) -> Void)?

    private enum DefaultsKey {
        static let opacity = "coverOpacity"
        static let drop = "coverDrop"
        static let width = "coverWidth"
        static let dimAmount = "dimAmount"
        static let legacyDimBackground = "dimBackground"
        static let displayScope = "displayScope"
        static let selectedPackID = "selectedPackID"
        static let tintEnabled = "tintEnabled"
        static let tintHex = "tintHex"
    }

    @Published private(set) var isDraped = false
    @Published private(set) var installedPackCount = 0
    @Published private(set) var packMessage: String?
    @Published private(set) var packs: [CoverPackSummary] = []
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var tintColor: RGBAColor
    @Published private(set) var isPackOperationInProgress = false

    @Published var selectedPackID: String {
        didSet {
            preferences.set(selectedPackID, forKey: DefaultsKey.selectedPackID)
            applyAppearance()
        }
    }

    @Published var opacity: Double {
        didSet {
            let normalized = AppearanceSettings.normalizeOpacity(opacity)
            guard normalized == opacity else {
                opacity = normalized
                return
            }
            preferences.set(opacity, forKey: DefaultsKey.opacity)
            applyAppearance()
        }
    }

    @Published var drop: Double {
        didSet {
            let normalized = AppearanceSettings.normalizeDrop(drop)
            guard normalized == drop else {
                drop = normalized
                return
            }
            preferences.set(drop, forKey: DefaultsKey.drop)
            applyAppearance()
        }
    }

    @Published var width: Double {
        didSet {
            let normalized = AppearanceSettings.normalizeWidth(width)
            guard normalized == width else {
                width = normalized
                return
            }
            preferences.set(width, forKey: DefaultsKey.width)
            applyAppearance()
        }
    }

    @Published var dimAmount: Double {
        didSet {
            let normalized = AppearanceSettings.normalizeDimAmount(dimAmount)
            guard normalized == dimAmount else {
                dimAmount = normalized
                return
            }
            preferences.set(dimAmount, forKey: DefaultsKey.dimAmount)
            applyAppearance()
        }
    }

    @Published var displayScope: DisplayScope {
        didSet {
            preferences.set(displayScope.rawValue, forKey: DefaultsKey.displayScope)
            overlayCoordinator.update(displayScope: displayScope)
        }
    }

    @Published var tintEnabled: Bool {
        didSet {
            preferences.set(tintEnabled, forKey: DefaultsKey.tintEnabled)
            applyAppearance()
        }
    }

    private let preferences: any PreferencesStoring
    private let overlayCoordinator: any OverlayCoordinating
    private let packStore: any CoverPackStoring
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let workspaceRevealer: any WorkspaceRevealing
    private var settingsWindowController: SettingsWindowController?
    private var packLoadingTask: Task<Void, Never>?

    init(
        preferences: any PreferencesStoring = UserDefaults.standard,
        overlayCoordinator: any OverlayCoordinating = OverlayCoordinator(),
        packStore: any CoverPackStoring = CoverPackStore(),
        launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        workspaceRevealer: any WorkspaceRevealing = SystemWorkspaceRevealer()
    ) {
        self.preferences = preferences
        self.overlayCoordinator = overlayCoordinator
        self.packStore = packStore
        self.launchAtLoginManager = launchAtLoginManager
        self.workspaceRevealer = workspaceRevealer

        let legacyDimEnabled = preferences.object(forKey: DefaultsKey.legacyDimBackground) as? Bool ?? true
        let appearance = AppearanceSettings(
            opacity: preferences.object(forKey: DefaultsKey.opacity) as? Double
                ?? AppearanceSettings.defaultOpacity,
            drop: preferences.object(forKey: DefaultsKey.drop) as? Double
                ?? AppearanceSettings.defaultDrop,
            width: preferences.object(forKey: DefaultsKey.width) as? Double
                ?? AppearanceSettings.defaultWidth,
            dimAmount: preferences.object(forKey: DefaultsKey.dimAmount) as? Double
                ?? (legacyDimEnabled ? AppearanceSettings.defaultDimAmount : 0)
        )
        opacity = appearance.opacity
        drop = appearance.drop
        width = appearance.width
        dimAmount = appearance.dimAmount
        displayScope =
            preferences.string(forKey: DefaultsKey.displayScope).flatMap(DisplayScope.init(rawValue:))
            ?? .all
        tintEnabled = preferences.object(forKey: DefaultsKey.tintEnabled) as? Bool ?? false
        tintColor =
            preferences.string(forKey: DefaultsKey.tintHex).flatMap(RGBAColor.init(hexRGB:))
            ?? RGBAColor(red: 0.82, green: 0.40, blue: 0.34)
        selectedPackID = preferences.string(forKey: DefaultsKey.selectedPackID) ?? "dev.ortu.inci"

        refreshLaunchAtLogin()
        overlayCoordinator.onRequestFold = { [weak self] in self?.removeCover() }
        overlayCoordinator.update(displayScope: displayScope)
        applyAppearance()
        packLoadingTask = Task { [weak self] in await self?.refreshPacks() }
    }

    deinit {
        packLoadingTask?.cancel()
    }

    func toggleDrape() {
        isDraped ? removeCover() : drapeCover()
    }

    func drapeCover() {
        isDraped = true
        onDrapeStateChange?(true)
        applyAppearance()
        overlayCoordinator.show()
    }

    func removeCover() {
        isDraped = false
        onDrapeStateChange?(false)
        overlayCoordinator.hide(animated: true)
    }

    func openSettings() {
        refreshLaunchAtLogin()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: self)
        }
        settingsWindowController?.show()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            refreshLaunchAtLogin()
            launchAtLoginMessage =
                launchAtLoginManager.status == .requiresApproval
                ? L10n.text("launch_at_login.approval")
                : (enabled ? L10n.text("launch_at_login.enabled") : nil)
        } catch {
            refreshLaunchAtLogin()
            launchAtLoginMessage = L10n.text("launch_at_login.failed", error.localizedDescription)
        }
    }

    func resetAppearance() {
        opacity = AppearanceSettings.defaultOpacity
        let selectedPack = packs.first { $0.id == selectedPackID }
        drop = selectedPack?.defaultDrop ?? AppearanceSettings.defaultDrop
        width = selectedPack?.defaultWidth ?? AppearanceSettings.defaultWidth
        dimAmount = AppearanceSettings.defaultDimAmount
        tintEnabled = false
    }

    func setTintColor(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        tintColor = RGBAColor(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
        preferences.set(tintColor.hexRGB, forKey: DefaultsKey.tintHex)
        applyAppearance()
    }

    func importCoverPack() {
        chooseCoverPack(prompt: L10n.text("pack.panel.add_prompt")) { [weak self] sourceURL in
            Task { await self?.importCoverPack(from: sourceURL) }
        }
    }

    func updateCoverPack(_ pack: CoverPackSummary) {
        guard !pack.isBuiltIn else { return }
        chooseCoverPack(prompt: L10n.text("pack.panel.update_prompt")) { [weak self] sourceURL in
            Task { await self?.importCoverPack(from: sourceURL, replacingID: pack.id) }
        }
    }

    func revealCoverPack(_ pack: CoverPackSummary) {
        guard !pack.isBuiltIn else { return }
        workspaceRevealer.reveal(pack.packageURL)
    }

    func removeCoverPack(_ pack: CoverPackSummary) {
        guard !pack.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("pack.remove.confirmation", pack.name)
        alert.informativeText = L10n.text("pack.remove.warning")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("settings.remove"))
        alert.addButton(withTitle: L10n.text("pack.remove.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { [weak self] in await self?.removeConfirmedCoverPack(pack) }
    }

    private func chooseCoverPack(prompt: String, completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("pack.panel.title")
        panel.prompt = prompt
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ortupack") ?? .package]

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        completion(sourceURL)
    }

    @discardableResult
    func importCoverPack(from sourceURL: URL, replacingID: String? = nil) async -> Bool {
        isPackOperationInProgress = true
        defer { isPackOperationInProgress = false }
        do {
            let result = try await packStore.importPack(from: sourceURL, replacingID: replacingID)
            await refreshPacks(selecting: result.pack.manifest.id)
            let manifest = result.pack.manifest
            let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
            let name = manifest.name[languageCode] ?? manifest.name["en"] ?? manifest.name["tr"] ?? manifest.id
            packMessage =
                result.action == .updated
                ? L10n.text("pack.updated", name, manifest.version)
                : L10n.text("pack.installed", name)
            return true
        } catch {
            packMessage = error.localizedDescription
            return false
        }
    }

    func quit() {
        overlayCoordinator.hide(animated: false)
        NSApp.terminate(nil)
    }

    private func removeConfirmedCoverPack(_ pack: CoverPackSummary) async {
        isPackOperationInProgress = true
        defer { isPackOperationInProgress = false }
        do {
            try await packStore.removePack(id: pack.id)
            await refreshPacks()
            if selectedPackID == pack.id, let fallback = packs.first {
                selectedPackID = fallback.id
            }
            packMessage = L10n.text("pack.removed", pack.name)
        } catch {
            packMessage = error.localizedDescription
        }
    }

    func refreshPacks(selecting packID: String? = nil) async {
        async let count = packStore.installedPackCount()
        async let summaries = packStore.availablePacks()
        installedPackCount = await count
        packs = await summaries
        guard !Task.isCancelled else { return }

        if let packID {
            selectedPackID = packID
        } else if !packs.contains(where: { $0.id == selectedPackID }), let firstPack = packs.first {
            selectedPackID = firstPack.id
        } else {
            applyAppearance()
        }
    }

    private func applyAppearance() {
        let selectedPack = packs.first { $0.id == selectedPackID }
        let activeTint = tintEnabled && selectedPack?.supportsTint == true ? tintColor : nil
        overlayCoordinator.update(
            appearance: OverlayAppearance(
                opacity: opacity,
                drop: drop,
                width: width,
                dimAmount: dimAmount,
                textureURL: selectedPack?.textureURL,
                tintColor: activeTint
            )
        )
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = launchAtLoginManager.status != .disabled
        onLaunchAtLoginChange?(launchAtLogin)
    }
}
