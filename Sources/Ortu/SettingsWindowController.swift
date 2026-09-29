import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(model: AppModel) {
        let rootView = SettingsView(model: model)
        let hostingView = NSHostingView(rootView: rootView)
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 760
        let windowHeight = min(720, max(560, visibleHeight - 80))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("settings.window.title")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("app.name"))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(L10n.text("app.tagline"))
                        .foregroundStyle(.secondary)
                }

                GroupBox(L10n.text("settings.section.appearance")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(L10n.text("settings.cover"), selection: $model.selectedPackID) {
                            ForEach(model.packs) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                        LabeledContent(L10n.text("settings.opacity")) {
                            Slider(value: $model.opacity, in: 0.35 ... 1.0)
                                .frame(width: 220)
                        }
                        LabeledContent(L10n.text("settings.drop")) {
                            Slider(value: $model.drop, in: 0.20 ... 0.85)
                                .frame(width: 220)
                        }
                        LabeledContent(L10n.text("settings.width")) {
                            Slider(value: $model.width, in: 0.20 ... 1.0)
                                .frame(width: 220)
                        }
                        LabeledContent(L10n.text("settings.background")) {
                            HStack(spacing: 8) {
                                Slider(value: $model.dimAmount, in: 0 ... 1)
                                    .frame(width: 170)
                                Text(
                                    model.dimAmount >= 0.995
                                        ? L10n.text("settings.full")
                                        : "\(Int((model.dimAmount * 100).rounded()))%"
                                )
                                .monospacedDigit()
                                .frame(width: 46, alignment: .trailing)
                            }
                        }
                        Toggle(L10n.text("settings.customize_thread"), isOn: $model.tintEnabled)
                        ColorPicker(
                            L10n.text("settings.thread_color"),
                            selection: Binding(
                                get: {
                                    Color(
                                        .sRGB,
                                        red: model.tintColor.red,
                                        green: model.tintColor.green,
                                        blue: model.tintColor.blue,
                                        opacity: 1
                                    )
                                },
                                set: { model.setTintColor(NSColor($0)) }
                            ),
                            supportsOpacity: false
                        )
                        .disabled(!model.tintEnabled)
                    }
                    .padding(8)
                }

                GroupBox(L10n.text("settings.section.packs")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.text("settings.user_pack_count", model.installedPackCount))
                                Text(L10n.text("settings.pack_drop_hint"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L10n.text("settings.add_pack")) {
                                model.importCoverPack()
                            }
                            .disabled(model.isPackOperationInProgress)
                        }

                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(model.packs) { pack in
                                    HStack(spacing: 9) {
                                        Image(systemName: pack.isBuiltIn ? "shippingbox.fill" : "shippingbox")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(pack.name)
                                            Text("v\(pack.version) · \(pack.author)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if pack.isBuiltIn {
                                            Text(L10n.text("settings.built_in"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Menu {
                                                Button(L10n.text("settings.update")) {
                                                    model.updateCoverPack(pack)
                                                }
                                                Button(L10n.text("settings.reveal")) {
                                                    model.revealCoverPack(pack)
                                                }
                                                Divider()
                                                Button(L10n.text("settings.remove"), role: .destructive) {
                                                    model.removeCoverPack(pack)
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis.circle")
                                            }
                                            .menuStyle(.borderlessButton)
                                            .fixedSize()
                                            .disabled(model.isPackOperationInProgress)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    if pack.id != model.packs.last?.id { Divider() }
                                }
                            }
                        }
                        .frame(height: 122)

                        if let message = model.packMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard
                        let packageURL = urls.first(where: {
                            $0.pathExtension.lowercased() == "ortupack"
                        })
                    else { return false }
                    Task { await model.importCoverPack(from: packageURL) }
                    return true
                }

                GroupBox(L10n.text("settings.section.application")) {
                    VStack(alignment: .leading, spacing: 7) {
                        Picker(L10n.text("settings.multiple_displays"), selection: $model.displayScope) {
                            ForEach(DisplayScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        Text(model.displayScope.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(
                            L10n.text("settings.launch_at_login"),
                            isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            )
                        )
                        Text(L10n.text("settings.shortcut_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let message = model.launchAtLoginMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                HStack {
                    Button(L10n.text("settings.reset")) {
                        model.resetAppearance()
                    }
                    Spacer()
                    Button(L10n.text(model.isDraped ? "menu.remove" : "menu.drape")) {
                        model.toggleDrape()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(L10n.text("settings.pack_safety"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 520)
    }
}
