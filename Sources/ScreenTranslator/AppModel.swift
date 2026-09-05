import AppKit
import SwiftUI
import ScreenCaptureKit
import Translation
import Vision
import ServiceManagement

struct LanguageOption: Identifiable {
    let id: String
    let name: String

    var language: Locale.Language { Locale.Language(identifier: id) }
    var baseCode: String { language.languageCode?.identifier ?? id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published var status = "准备就绪，按 F8 开始"
    @Published var hasPermission = CGPreflightScreenCaptureAccess()
    @Published var languageStatus = "正在检查语言包…"
    @Published var languageReady = false
    @Published var languageOptions: [LanguageOption] = [.init(id: "en", name: "英语")]
    @Published var targetLanguageOptions: [LanguageOption] = [.init(id: "zh-Hans", name: "简体中文")]
    @Published var downloadConfiguration: TranslationSession.Configuration?
    @Published var preparingLanguage = false
    @Published var shortcutError: String?
    @Published var loginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginRequested") && SMAppService.mainApp.status == .enabled
    @Published private(set) var shortcut: Shortcut
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var shortcutHint = "点击后，按下想使用的单键或组合键"
    @Published var translationMode: TranslationMode {
        didSet {
            guard translationMode != oldValue else { return }
            UserDefaults.standard.set(translationMode.rawValue, forKey: "translationMode")
            stop(message: "已切换为\(translationMode.label)，按 \(shortcut.label) 开始")
            discardTranslationSessions()
        }
    }
    @Published var sourceLanguage: String {
        didSet {
            UserDefaults.standard.set(sourceLanguage, forKey: "sourceLanguage")
            stop()
            discardTranslationSessions()
            Task { await refreshLanguageStatus() }
        }
    }
    @Published var targetLanguage: String {
        didSet {
            UserDefaults.standard.set(targetLanguage, forKey: "targetLanguage")
            stop()
            discardTranslationSessions()
            Task { await refreshLanguageStatus() }
        }
    }
    @Published var fontScale: Double {
        didSet { UserDefaults.standard.set(fontScale, forKey: "fontScale"); if isActive { stop() } }
    }
    var openSettings: (() -> Void)?
    private let hotkey = HotKeyManager()
    private let shortcutRecorder = ShortcutRecorder()
    private let overlay = OverlayController()
    private let recognizer = RecognitionService()
    private var captureTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var currentSession: TranslationSession?
    private var currentSessionKey: String?
    private var translationSessions: [String: TranslationSession] = [:]
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var latestImage: CGImage?
    private var latestFingerprint: Data?
    private var processedStamp: FrameStamp?
    private var cache = TranslationCache()
    private var screenObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        shortcut = Shortcut.load(from: defaults)
        translationMode = TranslationMode(rawValue: defaults.string(forKey: "translationMode") ?? "") ?? .live
        sourceLanguage = defaults.string(forKey: "sourceLanguage") ?? "auto"
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "zh-Hans"
        fontScale = defaults.object(forKey: "fontScale") == nil ? 1 : defaults.double(forKey: "fontScale")
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.toggle() } }
        shortcutRecorder.onCommit = { [weak self] in self?.commitShortcut($0) }
        shortcutRecorder.onCancel = { [weak self] in self?.cancelShortcutRecording() }
        shortcutRecorder.onHint = { [weak self] in self?.shortcutHint = $0 }
        registerShortcut()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isActive else { return }
                    self.stop(message: "显示器配置已改变，请重新按快捷键开启")
                }
            }
        Task { await loadLanguages(); await refreshLanguageStatus() }
    }

    private func registerShortcut() {
        shortcutError = hotkey.register(shortcut) ? nil : "快捷键注册失败，可能已被其他软件占用。请换一个快捷键。"
        if !isActive { status = shortcutError ?? "准备就绪，按 \(shortcut.label) 开始" }
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        stop(message: "请按下新的快捷键")
        hotkey.unregister()
        shortcutError = nil
        isRecordingShortcut = true
        shortcutHint = "请按键；Esc 也可设置，放弃请点「取消」"
        shortcutRecorder.begin()
    }

    func cancelShortcutRecording() {
        guard isRecordingShortcut else { return }
        shortcutRecorder.end()
        isRecordingShortcut = false
        shortcutHint = "已取消，保留原快捷键"
        registerShortcut()
    }

    private func commitShortcut(_ candidate: Shortcut) {
        shortcutRecorder.end()
        isRecordingShortcut = false
        if hotkey.register(candidate) {
            shortcut = candidate
            candidate.save(to: .standard)
            shortcutError = nil
            shortcutHint = "已设置为 \(candidate.label)，点击可再次修改"
            status = "快捷键设置成功，按 \(candidate.label) 开始"
        } else {
            let restored = hotkey.register(shortcut)
            shortcutError = restored ? "该按键被系统或其他软件占用，已保留 \(shortcut.label)。请重试其他按键。" : "快捷键注册失败，请重新录入其他按键。"
            shortcutHint = "设置未成功，点击重新录入"
            status = shortcutError!
        }
    }

    func refreshPermission() { hasPermission = CGPreflightScreenCaptureAccess() }

    func requestPermission() {
        if CGRequestScreenCaptureAccess() { hasPermission = true }
        else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            status = "请在系统设置中允许「屏幕译」录制屏幕，必要时退出后重新打开"
        }
    }

    func loadLanguages() async {
        let languages = await LanguageAvailability().supportedLanguages
        let ocr = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        let ocrBases = Set(ocr.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 })
        let allOptions = makeLanguageOptions(languages)
        languageOptions = allOptions.filter { ocrBases.contains($0.baseCode) }
        targetLanguageOptions = allOptions

        if sourceLanguage != "auto", !languageOptions.contains(where: { $0.id == sourceLanguage }) {
            sourceLanguage = "auto"
        }
        if !targetLanguageOptions.contains(where: { $0.id == targetLanguage }) {
            targetLanguage = targetLanguageOptions.first(where: { $0.id == "zh-Hans" })?.id
                ?? targetLanguageOptions.first(where: { $0.baseCode == "zh" })?.id
                ?? targetLanguageOptions.first?.id
                ?? "zh-Hans"
        }
    }

    private func makeLanguageOptions(_ languages: [Locale.Language]) -> [LanguageOption] {
        var seen = Set<String>()
        return languages.compactMap { language in
            let id = language.minimalIdentifier
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = Locale(identifier: "zh_CN").localizedString(forIdentifier: id)
                ?? Locale(identifier: "zh_CN").localizedString(forLanguageCode: language.languageCode?.identifier ?? id)
                ?? id
            return LanguageOption(id: id, name: name)
        }.sorted {
            let leftPriority = languagePriority($0.id)
            let rightPriority = languagePriority($1.id)
            return leftPriority == rightPriority ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : leftPriority < rightPriority
        }
    }

    private func languagePriority(_ id: String) -> Int {
        if id == "en" { return 0 }
        if id == "zh-Hans" { return 1 }
        if id == "zh-Hant" { return 2 }
        return 3
    }

    var sourceLanguageName: String {
        if sourceLanguage == "auto" { return "自动识别" }
        return languageOptions.first(where: { $0.id == sourceLanguage })?.name ?? displayName(sourceLanguage)
    }

    var targetLanguageName: String {
        targetLanguageOptions.first(where: { $0.id == targetLanguage })?.name ?? displayName(targetLanguage)
    }

    var languagePairValid: Bool {
        sourceLanguage == "auto" || !TextAnalysis.sameLanguage(sourceLanguage, targetLanguage)
    }

    private func displayName(_ id: String) -> String {
        Locale(identifier: "zh_CN").localizedString(forIdentifier: id)
            ?? Locale(identifier: "zh_CN").localizedString(forLanguageCode: Locale.Language(identifier: id).languageCode?.identifier ?? id)
            ?? id
    }

    private var packageSourceLanguage: String {
        if sourceLanguage != "auto" { return sourceLanguage }
        return Locale.Language(identifier: targetLanguage).languageCode?.identifier == "en" ? "zh-Hans" : "en"
    }

    func refreshLanguageStatus() async {
        let selectedSource = sourceLanguage
        let selectedTarget = targetLanguage
        guard languagePairValid else {
            languageReady = false
            languageStatus = "原文语言和翻译后语言不能相同"
            return
        }
        let source = packageSourceLanguage
        let target = Locale.Language(identifier: selectedTarget)
        let availability = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: target)
        guard selectedSource == sourceLanguage, selectedTarget == targetLanguage else { return }
        let sourceName = displayName(source)
        let targetName = displayName(selectedTarget)
        let autoNote = selectedSource == "auto" ? "（自动识别以\(sourceName)检查）" : ""
        languageReady = availability == .installed
        switch availability {
        case .installed: languageStatus = "\(sourceName) → \(targetName)：已安装，可离线使用\(autoNote)"
        case .supported: languageStatus = "\(sourceName) → \(targetName)：需要先下载语言包\(autoNote)"
        case .unsupported: languageStatus = "系统暂不支持这组语言，请选择其他源语言"
        @unknown default: languageStatus = "暂时无法确认语言包状态"
        }
    }

    func prepareLanguage() {
        guard !preparingLanguage, languagePairValid else { return }
        preparingLanguage = true
        languageStatus = "正在准备语言包，请留意系统下载提示…"
        let source = Locale.Language(identifier: packageSourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        if downloadConfiguration?.source == source, downloadConfiguration?.target == target { downloadConfiguration?.invalidate() }
        else { downloadConfiguration = .init(source: source, target: target) }
    }

    func finishPreparation(error: Error?) async {
        preparingLanguage = false
        await refreshLanguageStatus()
        if let error { languageStatus = "语言包准备失败：\(error.localizedDescription)。可再次点击重试。" }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(enabled, forKey: "launchAtLoginRequested")
            loginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginRequested") && SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { status = "请在系统设置 → 登录项中确认允许开机启动" }
        } catch {
            loginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginRequested") && SMAppService.mainApp.status == .enabled
            status = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func toggle() {
        guard !isRecordingShortcut else { return }
        if isActive { stop(); return }
        guard languagePairValid else {
            status = "请在设置中选择不同的原文语言和翻译后语言"
            openSettings?()
            return
        }
        refreshPermission()
        guard hasPermission else {
            status = "首次使用需要授权屏幕录制"
            openSettings?()
            return
        }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            status = "没有可用的显示器"; return
        }
        generation &+= 1
        revision = 0
        latestImage = nil
        latestFingerprint = nil
        processedStamp = nil
        isActive = true
        status = "正在读取屏幕…"
        overlay.prepare(screen: screen, fontScale: fontScale)
        let token = generation
        let displayID = CGDirectDisplayID(number.uint32Value)
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let mode = translationMode
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.isActive, self.generation == token else { return }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    self.stop(message: "目标显示器已断开"); return
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !ownApps.isEmpty else {
                    self.stop(message: "无法排除翻译覆盖层，请重新开启翻译")
                    return
                }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                let nativeWidth = size.width * scale
                let nativeHeight = size.height * scale
                let liveLimit: CGFloat = 2200
                let reduction = mode == .live ? min(1, liveLimit / max(nativeWidth, nativeHeight)) : 1
                config.width = Int((nativeWidth * reduction).rounded())
                config.height = Int((nativeHeight * reduction).rounded())
                config.showsCursor = false
                config.captureResolution = .best
                config.scalesToFit = reduction < 1
                try await CaptureLoop.run(mode: mode) {
                    guard self.isActive, self.generation == token else { throw CancellationError() }
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard !Task.isCancelled, self.isActive, self.generation == token else { throw CancellationError() }
                    let fingerprint = await Task.detached(priority: .utility) { RecognitionService.fingerprint(image) }.value
                    guard self.isActive, self.generation == token else { throw CancellationError() }
                    if RecognitionService.isMeaningfullyDifferent(self.latestFingerprint, from: fingerprint) {
                        self.latestFingerprint = fingerprint
                        self.latestImage = image
                        self.revision &+= 1
                    }
                    self.scheduleProcessing()
                }
            } catch {
                guard self.isActive, self.generation == token, !Task.isCancelled else { return }
                self.stop(message: "无法读取屏幕：\(error.localizedDescription)。请检查屏幕录制权限。")
            }
        }
    }

    private var stamp: FrameStamp { .init(generation: generation, revision: revision) }

    private func scheduleProcessing() {
        guard isActive, processingTask == nil, let image = latestImage, processedStamp != stamp else { return }
        let requestedStamp = stamp
        let preferred = sourceLanguage
        let selectedTarget = targetLanguage
        let automaticSources = Set(languageOptions.map(\.id))
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.currentSession = nil
                self.processingTask = nil
                self.scheduleProcessing()
            }
            do {
                let profile: RecognitionProfile = self.translationMode == .live ? .lowLatency : .highAccuracy
                let rawRegions = try await self.recognizer.recognize(
                    image,
                    preferred: preferred,
                    target: selectedTarget,
                    supportedSources: automaticSources,
                    profile: profile
                )
                let regions = TextAnalysis.mergeLines(rawRegions)
                guard !Task.isCancelled, self.isActive, self.stamp == requestedStamp else { return }
                var warnings: [String] = []
                for (language, group) in Dictionary(grouping: regions, by: \.language).sorted(by: { $0.key < $1.key }) {
                    try Task.checkCancellation()
                    guard self.isActive, self.stamp == requestedStamp else { return }
                    let missing = Dictionary(grouping: group.filter { self.cache[$0.cacheKey] == nil }, by: \.cacheKey).compactMap { $0.value.first }
                    guard !missing.isEmpty else { continue }
                    let source = Locale.Language(identifier: language)
                    let target = Locale.Language(identifier: selectedTarget)
                    let available = await LanguageAvailability().status(from: source, to: target)
                    guard !Task.isCancelled, self.isActive, self.stamp == requestedStamp else { return }
                    guard available == .installed else {
                        let name = self.displayName(language)
                        warnings.append(available == .supported ? "\(name)需下载语言包，请打开设置" : "系统不支持\(name)翻译")
                        continue
                    }
                    let sessionKey = "\(language)|\(selectedTarget)|\(self.translationMode.rawValue)"
                    let session = self.translationSession(for: source, target: target, key: sessionKey)
                    self.currentSession = session
                    self.currentSessionKey = sessionKey
                    let requests = missing.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.cacheKey) }
                    let responses = try await session.translations(from: requests)
                    guard !Task.isCancelled, self.isActive, self.generation == requestedStamp.generation else { return }
                    for response in responses {
                        if let key = response.clientIdentifier { self.cache.set(response.targetText, for: key) }
                    }
                    self.currentSession = nil
                    self.currentSessionKey = nil
                }
                guard !Task.isCancelled, self.isActive, self.stamp == requestedStamp else { return }
                let translated = regions.compactMap { region -> TranslatedRegion? in
                    guard let text = self.cache[region.cacheKey], text != region.text else { return nil }
                    return .init(region: region, translation: text)
                }
                self.overlay.show(translated)
                self.processedStamp = requestedStamp
                if self.translationMode == .single { self.latestImage = nil }
                self.status = warnings.first ?? (translated.isEmpty ? "未发现需要翻译的外语文字" : "\(self.translationMode.label) · \(translated.count) 处文字 · \(self.shortcut.label) 关闭")
            } catch {
                guard !Task.isCancelled, self.isActive, self.stamp == requestedStamp else { return }
                self.currentSession?.cancel()
                if let key = self.currentSessionKey { self.translationSessions.removeValue(forKey: key) }
                self.processedStamp = requestedStamp
                if self.translationMode == .single { self.latestImage = nil }
                self.status = "翻译失败：\(error.localizedDescription)。按快捷键关闭后可重试。"
            }
        }
    }

    private func translationSession(for source: Locale.Language, target: Locale.Language, key: String) -> TranslationSession {
        if let session = translationSessions[key] { return session }
        let session: TranslationSession
        if #available(macOS 26.4, *) {
            let strategy: TranslationSession.Strategy = translationMode == .live ? .lowLatency : .highFidelity
            session = TranslationSession(installedSource: source, target: target, preferredStrategy: strategy)
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
        translationSessions[key] = session
        return session
    }

    private func discardTranslationSessions() {
        translationSessions.values.forEach { $0.cancel() }
        translationSessions.removeAll()
        currentSession = nil
        currentSessionKey = nil
    }

    func stop(message: String? = nil) {
        isActive = false
        generation &+= 1
        captureTask?.cancel()
        captureTask = nil
        processingTask?.cancel()
        currentSession?.cancel()
        if let currentSessionKey { translationSessions.removeValue(forKey: currentSessionKey) }
        currentSession = nil
        currentSessionKey = nil
        recognizer.cancel()
        overlay.close()
        latestImage = nil
        latestFingerprint = nil
        processedStamp = nil
        cache.clear()
        status = message ?? "已关闭，按 \(shortcut.label) 开始"
    }
}
