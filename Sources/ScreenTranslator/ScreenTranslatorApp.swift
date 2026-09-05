import SwiftUI
import AppKit
import Translation

private enum AppArtwork {
    static var icon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

@main
struct ScreenTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppArtwork.icon
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "屏幕译")
        item.button?.toolTip = "屏幕译 · \(model.shortcut.label) 显示或隐藏中文"
        statusItem = item
        model.openSettings = { [weak self] in self?.showSettings() }
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        updateMenu()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || !model.hasPermission {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    private func updateMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "屏幕译", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let state = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        menu.addItem(state)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: model.isActive ? "关闭翻译（\(model.shortcut.label)）" : "开启翻译（\(model.shortcut.label)）", action: #selector(toggleTranslation), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let modeItem = NSMenuItem(title: "翻译模式：\(model.translationMode.label)", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for mode in TranslationMode.allCases {
            let option = NSMenuItem(title: mode.label, action: #selector(changeMode(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = mode.rawValue
            option.state = model.translationMode == mode ? .on : .off
            modes.addItem(option)
        }
        modeItem.submenu = modes
        menu.addItem(modeItem)
        let languageItem = NSMenuItem(title: "语言：\(model.sourceLanguageName) → \(model.targetLanguageName)", action: nil, keyEquivalent: "")
        menu.addItem(languageItem)
        let settings = NSMenuItem(title: "设置与语言包…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出屏幕译", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
        statusItem?.button?.image = NSImage(systemSymbolName: model.isActive ? "character.bubble.fill" : "character.bubble", accessibilityDescription: "屏幕译")
        statusItem?.button?.toolTip = model.status
    }

    @objc private func toggleTranslation() { model.toggle() }
    @objc private func changeMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = TranslationMode(rawValue: raw) else { return }
        model.translationMode = mode
    }
    @objc private func quitApp() { model.stop(); NSApp.terminate(nil) }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 730),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "屏幕译"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        model.refreshPermission()
        Task { await model.refreshLanguageStatus() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.cancelShortcutRecording(); model.stop() }
}

import Combine

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: AppArtwork.icon)
                    .resizable().scaledToFit().frame(width: 52, height: 52)
                    .accessibilityLabel("屏幕译图标")
                VStack(alignment: .leading, spacing: 4) {
                    Text("屏幕译").font(.system(size: 28, weight: .bold))
                    Text("按一下，全屏显示译文。再按一下，回到原文。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.shortcut.label).font(.system(.body, design: .monospaced).bold())
                    .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 150)
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("首次使用", systemImage: "checklist").font(.headline)
                    HStack {
                        Image(systemName: model.hasPermission ? "checkmark.circle.fill" : "1.circle")
                            .foregroundStyle(model.hasPermission ? .green : .secondary)
                        Text(model.hasPermission ? "屏幕录制已授权" : "允许读取屏幕上的文字")
                        Spacer()
                        Button(model.hasPermission ? "重新检查" : "去授权") {
                            if model.hasPermission { model.refreshPermission() } else { model.requestPermission() }
                        }
                    }
                    Divider()
                    HStack(alignment: .top) {
                        Image(systemName: model.languageReady ? "checkmark.circle.fill" : "2.circle")
                            .foregroundStyle(model.languageReady ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("准备翻译语言包")
                            Text(model.languageStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(model.preparingLanguage ? "准备中…" : (model.languageReady ? "检查" : "下载语言包")) {
                            if model.languageReady { Task { await model.refreshLanguageStatus() } }
                            else { model.stop(); model.prepareLanguage() }
                        }.disabled(model.preparingLanguage || !model.languagePairValid)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.isRecordingShortcut)
            GroupBox {
                VStack(spacing: 14) {
                    HStack {
                        Button("切换快捷键") { model.beginShortcutRecording() }
                            .buttonStyle(.plain).disabled(model.isRecordingShortcut)
                        Spacer()
                        Button(action: model.beginShortcutRecording) {
                            HStack {
                                Image(systemName: model.isRecordingShortcut ? "keyboard" : "pencil")
                                Text(model.isRecordingShortcut ? "请按下快捷键…" : model.shortcut.label)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }.frame(width: 170)
                        }
                        .disabled(model.isRecordingShortcut)
                        .accessibilityLabel("录入切换快捷键")
                        if model.isRecordingShortcut {
                            Button("取消", action: model.cancelShortcutRecording)
                        }
                    }
                    Text(model.shortcutHint).font(.caption)
                        .foregroundStyle(model.isRecordingShortcut ? .teal : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text("翻译模式")
                        Spacer()
                        Picker("翻译模式", selection: $model.translationMode) {
                            ForEach(TranslationMode.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                            .disabled(model.isRecordingShortcut)
                    }
                    Text(model.translationMode.explanation).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text("原文语言")
                        Spacer()
                        Picker("原文语言", selection: $model.sourceLanguage) {
                            Text("自动识别").tag("auto")
                            ForEach(model.languageOptions) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(width: 230).disabled(model.preparingLanguage || model.isRecordingShortcut)
                    }
                    HStack {
                        Text("翻译成")
                        Spacer()
                        Picker("翻译后语言", selection: $model.targetLanguage) {
                            ForEach(model.targetLanguageOptions) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(width: 230).disabled(model.preparingLanguage || model.isRecordingShortcut)
                    }
                    if !model.languagePairValid {
                        Label("原文语言和翻译后语言不能相同", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text("译文字号")
                        Spacer()
                        Slider(value: $model.fontScale, in: 0.8...1.4, step: 0.1).frame(width: 160).disabled(model.isRecordingShortcut)
                        Text("\(Int(model.fontScale * 100))%").monospacedDigit().frame(width: 45)
                    }
                    Toggle("开机后在后台启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        .frame(maxWidth: .infinity, alignment: .leading).disabled(model.isRecordingShortcut)
                }.padding(8)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("翻译鼠标所在的整块屏幕；切换模式后，请重新开启翻译。")
                Text("支持字母、数字、方向键、功能键和组合键。单键会占用原按键功能。")
                Text("修饰键需搭配其他键；系统保留键不可用，部分键盘需 Fn + F8。")
                Text("自动识别会判断每段原文语言；手动选择适合固定语言的页面。")
                Text("每组语言需单独下载语言包。小字、艺术字体及受保护画面可能无法识别。")
            }.font(.caption).foregroundStyle(.secondary)
            if let error = model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Spacer()
                Button(model.isActive ? "关闭翻译" : "开启翻译") { model.toggle() }
                    .buttonStyle(.borderedProminent).tint(.teal).disabled(model.isRecordingShortcut)
            }
        }
        .padding(26).frame(width: 600, height: 730)
        .translationTask(model.downloadConfiguration) { session in
            do {
                try await session.prepareTranslation()
                await model.finishPreparation(error: nil)
            } catch { await model.finishPreparation(error: error) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
            Task { await model.refreshLanguageStatus() }
        }
    }
}
