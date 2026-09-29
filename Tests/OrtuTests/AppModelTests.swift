import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Ortu

@Suite("App model settings")
@MainActor
struct AppModelTests {
    @Test("Appearance changes are normalized, persisted, and rendered")
    func appearanceSettings() {
        let dependencies = TestDependencies()
        let model = dependencies.makeModel()

        model.opacity = 2
        model.drop = -1
        model.width = 0.82
        model.dimAmount = 0.37
        model.tintEnabled = true
        model.setTintColor(.systemBlue)

        #expect(model.opacity == 1)
        #expect(model.drop == 0.20)
        #expect(model.width == 0.82)
        #expect(model.dimAmount == 0.37)
        #expect(dependencies.preferences.value(for: "coverOpacity") as? Double == 1)
        #expect(dependencies.preferences.value(for: "coverDrop") as? Double == 0.20)
        #expect(dependencies.overlay.appearances.last?.opacity == 1)
        #expect(dependencies.overlay.appearances.last?.dimAmount == 0.37)
    }

    @Test("Persisted settings are loaded and invalid values are clamped")
    func persistedSettings() {
        let dependencies = TestDependencies(values: [
            "coverOpacity": 0.67,
            "coverDrop": 4.0,
            "coverWidth": 0.73,
            "dimAmount": -1.0,
            "displayScope": DisplayScope.primary.rawValue,
            "tintEnabled": true,
            "tintHex": "#112233",
        ])

        let model = dependencies.makeModel()

        #expect(model.opacity == 0.67)
        #expect(model.drop == AppearanceSettings.dropRange.upperBound)
        #expect(model.width == 0.73)
        #expect(model.dimAmount == 0)
        #expect(model.displayScope == .primary)
        #expect(model.tintEnabled)
        #expect(model.tintColor.hexRGB == "#112233")
        #expect(dependencies.overlay.scopes == [.primary])
    }

    @Test("Drape transitions call only the overlay boundary")
    func drapeLifecycle() {
        let dependencies = TestDependencies()
        let model = dependencies.makeModel()
        var observedStates: [Bool] = []
        model.onDrapeStateChange = { observedStates.append($0) }

        model.drapeCover()
        model.removeCover()

        #expect(!model.isDraped)
        #expect(dependencies.overlay.showCount == 1)
        #expect(dependencies.overlay.hideAnimations == [true])
        #expect(observedStates == [true, false])
    }

    @Test("Launch at login reports approval and failures")
    func launchAtLogin() {
        let dependencies = TestDependencies()
        let model = dependencies.makeModel()
        dependencies.launchAtLogin.nextStatus = .requiresApproval

        model.setLaunchAtLogin(true)

        #expect(model.launchAtLogin)
        #expect(model.launchAtLoginMessage == L10n.text("launch_at_login.approval"))
        dependencies.launchAtLogin.error = TestError.expected
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLoginMessage == L10n.text("launch_at_login.failed", "expected"))
    }

    @Test("Pack import runs through the actor and refreshes published state")
    func importsPack() async {
        let summary = sampleSummary()
        let dependencies = TestDependencies(pack: summary)
        let model = dependencies.makeModel()

        let imported = await model.importCoverPack(from: URL(fileURLWithPath: "/tmp/Sample.ortupack"))

        #expect(imported)
        #expect(model.selectedPackID == summary.id)
        #expect(model.packs == [summary])
        #expect(model.installedPackCount == 1)
        #expect(model.packMessage == L10n.text("pack.installed", summary.name))
        #expect(!model.isPackOperationInProgress)
    }

    @Test("Workspace reveal is isolated behind a boundary")
    func revealPack() {
        let summary = sampleSummary()
        let dependencies = TestDependencies(pack: summary)
        let model = dependencies.makeModel()

        model.revealCoverPack(summary)

        #expect(dependencies.workspace.urls == [summary.packageURL])
    }

    @Test("Settings and overlay AppKit surfaces can be constructed")
    func appKitSmoke() {
        let dependencies = TestDependencies()
        let model = dependencies.makeModel()
        let settings = SettingsWindowController(model: model)
        let appearance = OverlayAppearance(
            opacity: 0.9,
            drop: 0.5,
            width: 0.9,
            dimAmount: 0.2,
            textureURL: nil,
            tintColor: nil
        )
        let overlay = OverlayView(
            frame: CGRect(x: 0, y: 0, width: 1_280, height: 720),
            appearance: appearance,
            onRequestFold: {}
        )

        overlay.update(appearance: appearance)
        overlay.resetInteraction()
        overlay.dismiss(animated: false) {}

        #expect(settings.window?.title == L10n.text("settings.window.title"))
        #expect(settings.window?.frame.width ?? 0 >= 440)
        #expect(overlay.acceptsFirstResponder)
        #expect(overlay.accessibilityLabel() == L10n.text("accessibility.overlay"))
    }

    @Test("English and Turkish localizations preserve the Örtü brand")
    func localizations() {
        #expect(L10n.text("app.name", localeIdentifier: "en") == "Örtü")
        #expect(L10n.text("app.name", localeIdentifier: "tr") == "Örtü")
        #expect(L10n.text("menu.drape", localeIdentifier: "en") == "Drape Örtü")
        #expect(L10n.text("menu.drape", localeIdentifier: "tr") == "Örtüyü Ser")
        #expect(L10n.text("settings.shortcut_hint", localeIdentifier: "en").contains("⇧⌘O"))
    }

    @Test("The global toggle uses Command-Shift-O")
    func globalShortcut() {
        #expect(GlobalShortcutController.keyCode == UInt32(kVK_ANSI_O))
        #expect(GlobalShortcutController.modifiers == UInt32(cmdKey | shiftKey))
    }
}

@MainActor
private final class TestDependencies {
    let preferences: PreferencesStub
    let overlay = OverlayCoordinatorSpy()
    let launchAtLogin = LaunchAtLoginStub()
    let workspace = WorkspaceRevealerSpy()
    let packStore: PackStoreStub

    init(values: [String: Any] = [:], pack: CoverPackSummary? = nil) {
        preferences = PreferencesStub(values: values)
        packStore = PackStoreStub(pack: pack)
    }

    func makeModel() -> AppModel {
        AppModel(
            preferences: preferences,
            overlayCoordinator: overlay,
            packStore: packStore,
            launchAtLoginManager: launchAtLogin,
            workspaceRevealer: workspace
        )
    }
}

private final class PreferencesStub: PreferencesStoring {
    private var values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
    }

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    func value(for key: String) -> Any? {
        values[key]
    }
}

@MainActor
private final class OverlayCoordinatorSpy: OverlayCoordinating {
    var onRequestFold: (() -> Void)?
    private(set) var appearances: [OverlayAppearance] = []
    private(set) var scopes: [DisplayScope] = []
    private(set) var showCount = 0
    private(set) var hideAnimations: [Bool] = []

    func update(appearance: OverlayAppearance) {
        appearances.append(appearance)
    }

    func update(displayScope: DisplayScope) {
        scopes.append(displayScope)
    }

    func show() {
        showCount += 1
    }

    func hide(animated: Bool) {
        hideAnimations.append(animated)
    }
}

@MainActor
private final class LaunchAtLoginStub: LaunchAtLoginManaging {
    var nextStatus = LaunchAtLoginStatus.disabled
    var error: Error?
    var status: LaunchAtLoginStatus { nextStatus }

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
    }
}

@MainActor
private final class WorkspaceRevealerSpy: WorkspaceRevealing {
    private(set) var urls: [URL] = []

    func reveal(_ url: URL) {
        urls.append(url)
    }
}

private actor PackStoreStub: CoverPackStoring {
    private let pack: CoverPackSummary?

    init(pack: CoverPackSummary?) {
        self.pack = pack
    }

    func installedPackCount() -> Int {
        pack == nil ? 0 : 1
    }

    func availablePacks() -> [CoverPackSummary] {
        pack.map { [$0] } ?? []
    }

    func importPack(from sourceURL: URL, replacingID expectedID: String?) throws -> CoverPackImportResult {
        guard let pack else { throw CoverPackError.notPackage }
        return CoverPackImportResult(
            pack: ValidatedCoverPack(
                url: pack.packageURL,
                manifest: sampleManifestForModel(id: pack.id, name: pack.name),
                totalBytes: 1
            ),
            action: .installed
        )
    }

    func removePack(id: String) throws {}
}

private enum TestError: LocalizedError {
    case expected

    var errorDescription: String? { "expected" }
}

private func sampleSummary() -> CoverPackSummary {
    CoverPackSummary(
        id: "dev.ortu.sample",
        name: "Örnek",
        author: "Örtü",
        version: "1.0.0",
        isBuiltIn: false,
        packageURL: URL(fileURLWithPath: "/tmp/dev.ortu.sample.ortupack", isDirectory: true),
        defaultDrop: 0.56,
        defaultWidth: 0.9,
        supportsTint: true,
        textureURL: URL(fileURLWithPath: "/tmp/texture.png"),
        previewURL: nil
    )
}

private func sampleManifestForModel(id: String, name: String) -> CoverPackManifest {
    CoverPackManifest(
        schemaVersion: 1,
        id: id,
        version: "1.0.0",
        name: ["tr": name],
        author: "Örtü",
        license: "MIT",
        canvas: .init(width: 1, height: 1),
        anchor: "topCenter",
        defaultDrop: 0.56,
        defaultWidth: 0.9,
        tintMode: "multiply",
        assets: .init(
            texture1x: "texture@1x.png",
            texture2x: "texture@2x.png",
            mask: "mask.png",
            preview: nil
        ),
        sha256: nil
    )
}
