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
        window.title = "Örtü Ayarları"
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
                    Text("Örtü")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Hafif, yerel ve Mac’in için.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Görünüm") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Örtü", selection: $model.selectedPackID) {
                            ForEach(model.packs) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                        LabeledContent("Opaklık") {
                            Slider(value: $model.opacity, in: 0.35 ... 1.0)
                                .frame(width: 220)
                        }
                        LabeledContent("Düşme") {
                            Slider(value: $model.drop, in: 0.20 ... 0.85)
                                .frame(width: 220)
                        }
                        LabeledContent("Genişlik") {
                            Slider(value: $model.width, in: 0.20 ... 1.0)
                                .frame(width: 220)
                        }
                        LabeledContent("Arka plan") {
                            HStack(spacing: 8) {
                                Slider(value: $model.dimAmount, in: 0 ... 1)
                                    .frame(width: 170)
                                Text(model.dimAmount >= 0.995 ? "Tam" : "\(Int((model.dimAmount * 100).rounded()))%")
                                    .monospacedDigit()
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        Toggle("İplik rengini özelleştir", isOn: $model.tintEnabled)
                        ColorPicker(
                            "İplik rengi",
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

                GroupBox("Örtü Paketleri") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(model.installedPackCount) kullanıcı paketi yüklü")
                                Text(".ortupack dosyasını buraya bırakabilirsin.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Paket Ekle…") {
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
                                            Text("Yerleşik")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Menu {
                                                Button("Güncelle…") { model.updateCoverPack(pack) }
                                                Button("Finder’da Göster") { model.revealCoverPack(pack) }
                                                Divider()
                                                Button("Kaldır", role: .destructive) { model.removeCoverPack(pack) }
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

                GroupBox("Uygulama") {
                    VStack(alignment: .leading, spacing: 7) {
                        Picker("Birden fazla ekran", selection: $model.displayScope) {
                            ForEach(DisplayScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        Text(model.displayScope.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(
                            "Girişte otomatik aç",
                            isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            )
                        )
                        Text("Örtüyü her yerden serip kaldırmak için ⌃⌥O kısayolunu kullanabilirsin.")
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
                    Button("Varsayılanlara Dön") {
                        model.resetAppearance()
                    }
                    Spacer()
                    Button(model.isDraped ? "Örtüyü Kaldır" : "Örtüyü Ser") {
                        model.toggleDrape()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Örtüler veri-only .ortupack paketleri olarak yüklenir; paketler kod çalıştıramaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 520)
    }
}
