import AppKit
import ApplicationServices
import Combine

// Mission Control's accessibility hierarchy is not a documented public API. Window matching
// deliberately refuses ambiguous matches rather than risking closing the wrong document.
@MainActor
final class MissionSwipe: ObservableObject {
    static let shared = MissionSwipe()
    @Published var enabled = UserDefaults.standard.bool(forKey: "missionSwipeEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "missionSwipeEnabled"); configure() }
    }
    private struct Thumbnail {
        let element: AXUIElement
        let rect: CGRect
        let label: String
        let identifier: String
        let panel: NSPanel
        var buttonRect: CGRect { CGRect(x: rect.minX, y: rect.minY, width: 32, height: 32) }
    }
    private var thumbnails: [Thumbnail] = []
    private var timer: Timer?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var stableTicks = 0
    private var swallowUp = false
    private var scrolling = false
    private var swipeAmount = 0.0
    private var swipeTarget: Thumbnail?
    private var didSwipe = false
    private init() {}

    func configure() {
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        clear()
        guard enabled, AXIsProcessTrusted() else { return }
        if tap == nil {
            let mask = [CGEventType.leftMouseDown, .leftMouseUp, .scrollWheel].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<MissionSwipe>.fromOpaque(info).takeUnretainedValue()
                return MainActor.assumeIsolated { owner.handle(type, event) ? nil : Unmanaged.passUnretained(event) }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap { tapSource = CFMachPortCreateRunLoopSource(nil, tap, 0); if let tapSource { CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes) } }
        }
        guard tap != nil else { return }
        let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    private func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, key as CFString, &result) == .success ? result : nil
    }
    private func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func rect(_ e: AXUIElement) -> CGRect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
    private func roots() -> [AXUIElement] {
        ["com.apple.dock", "com.apple.WindowManager"].flatMap { id -> [AXUIElement] in
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier else { return [] }
            let root = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(root, 0.15)
            return children(root).filter { e in
                guard let id = value(e, kAXIdentifierAttribute) as? String else { return false }
                return ["mc", "mc.display"].contains(id) && !children(e).isEmpty
            }
        }
    }
    private func refresh() {
        guard enabled, AXIsProcessTrusted() else { clear(); return }
        let roots = roots()
        guard !roots.isEmpty else { clear(); if let tap { CGEvent.tapEnable(tap: tap, enable: false) }; return }
        var found: [(AXUIElement, CGRect, String, String)] = []
        func visit(_ e: AXUIElement, _ depth: Int) {
            guard depth < 8 else { return }
            let identifier = value(e, kAXIdentifierAttribute) as? String ?? ""
            if identifier.hasPrefix("mc.spaces") { return }
            if (value(e, kAXRoleAttribute) as? String) == kAXButtonRole as String,
               let frame = rect(e), frame.width > 40, frame.height > 40,
               let title = value(e, kAXTitleAttribute) as? String, !title.isEmpty {
                found.append((e, frame, title, identifier)); return
            }
            for child in children(e) { visit(child, depth + 1) }
        }
        roots.forEach { visit($0, 0) }
        // The overview animates as it fills a gap. Reuse panels through layout changes;
        // creating and ordering new overlay windows every tick can disturb that animation.
        let same = found.count == thumbnails.count && found.allSatisfy { item in
            thumbnails.contains { CFEqual($0.element, item.0) && $0.rect.equalTo(item.1) }
        }
        stableTicks = same ? min(stableTicks + 1, 3) : 0
        if !same {
            let previous = thumbnails
            thumbnails = found.map { e, frame, label, id in
                let panel = previous.first(where: { CFEqual($0.element, e) })?.panel ?? makePanel(frame)
                if panel.isVisible { panel.orderOut(nil) }
                place(panel, on: frame)
                return Thumbnail(element: e, rect: frame, label: label, identifier: id, panel: panel)
            }
            for old in previous where !thumbnails.contains(where: { $0.panel === old.panel }) {
                old.panel.orderOut(nil)
            }
        }
        let ready = stableTicks >= 2
        for thumb in thumbnails {
            if ready && !thumb.panel.isVisible { thumb.panel.orderFrontRegardless() }
            else if !ready && thumb.panel.isVisible { thumb.panel.orderOut(nil) }
        }
        if let tap, CGEvent.tapIsEnabled(tap: tap) != ready { CGEvent.tapEnable(tap: tap, enable: ready) }
    }
    private func place(_ panel: NSPanel, on rect: CGRect) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: rect.minX, y: height - rect.minY - 32))
    }
    private func makePanel(_ rect: CGRect) -> NSPanel {
        let height = NSScreen.screens.first?.frame.height ?? 0
        let panel = NSPanel(contentRect: NSRect(x: rect.minX, y: height - rect.minY - 32, width: 32, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep a 32-point click target while drawing a quieter, 24-point native-style control.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let glass = NSVisualEffectView(frame: NSRect(x: 4, y: 4, width: 24, height: 24))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        let symbol = NSImageView(frame: NSRect(x: 6, y: 6, width: 12, height: 12))
        symbol.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭窗口")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        symbol.contentTintColor = .labelColor
        symbol.imageScaling = .scaleProportionallyUpOrDown
        glass.addSubview(symbol)
        container.addSubview(glass)
        panel.contentView = container
        return panel
    }
    private func clear() { thumbnails.forEach { $0.panel.orderOut(nil) }; thumbnails.removeAll(); stableTicks = 0; scrolling = false; swipeTarget = nil }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap, stableTicks >= 2 { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        if type == .leftMouseUp { defer { swallowUp = false }; return swallowUp }
        guard stableTicks >= 2 else { return false }
        if type == .leftMouseDown, let thumb = thumbnails.first(where: { $0.buttonRect.contains(event.location) }) {
            swallowUp = true; DispatchQueue.main.async { [weak self] in self?.close(thumb) }; return true
        }
        if type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0, let ns = NSEvent(cgEvent: event) {
            if ns.phase.contains(.began) {
                swipeTarget = thumbnails.first { $0.rect.contains(event.location) }
                scrolling = swipeTarget != nil
                didSwipe = false; swipeAmount = 0
            }
            guard scrolling, ns.momentumPhase.isEmpty else { return false }
            swipeAmount += ns.scrollingDeltaY
            if !didSwipe, abs(swipeAmount) > 75, let target = swipeTarget, target.rect.contains(event.location) {
                didSwipe = true; DispatchQueue.main.async { [weak self] in self?.close(target) }
            }
            if ns.phase.contains(.ended) || ns.phase.contains(.cancelled) { scrolling = false; swipeTarget = nil }
            // Do not let Mission Control also process the same swipe as a system gesture.
            return true
        }
        return false
    }
    private func close(_ thumb: Thumbnail) {
        guard enabled, roots().count > 0, thumbnails.contains(where: { CFEqual($0.element, thumb.element) && $0.rect == thumb.rect }) else { return }
        var windows: [AXUIElement] = []
        var candidates: [MissionWindowCandidate] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let ax = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(ax, 0.15)
            for window in (value(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
                guard (value(window, kAXMinimizedAttribute) as? Bool) != true,
                      (value(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole as String else { continue }
                windows.append(window)
                candidates.append(MissionWindowCandidate(title: value(window, kAXTitleAttribute) as? String ?? "",
                                                         appName: app.localizedName ?? "",
                                                         bundleIdentifier: app.bundleIdentifier))
            }
        }
        guard let index = MissionWindowMatch.uniqueIndex(label: thumb.label, thumbnailIdentifier: thumb.identifier, candidates: candidates),
              let button = value(windows[index], kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else { NSSound.beep(); return }
        if AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) != .success { NSSound.beep() }
    }
}
