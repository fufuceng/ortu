import AppKit
import Foundation
import ServiceManagement

protocol PreferencesStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferencesStoring {}

@MainActor
protocol OverlayCoordinating: AnyObject {
    var onRequestFold: (() -> Void)? { get set }

    func update(appearance: OverlayAppearance)
    func update(displayScope: DisplayScope)
    func show()
    func hide(animated: Bool)
}

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        default:
            .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
protocol WorkspaceRevealing: AnyObject {
    func reveal(_ url: URL)
}

@MainActor
final class SystemWorkspaceRevealer: WorkspaceRevealing {
    func reveal(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}
