import AppKit
import ApplicationServices
import Combine

@MainActor
final class DockClick: ObservableObject {
    static let shared = DockClick()
    @Published var enabled = UserDefaults.standard.bool(forKey: "dockClickEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "dockClickEnabled"); update() }
    }
    @Published var trusted = AXIsProcessTrusted()
    private var monitor: Any?
    private var candidate: (pid_t, CGPoint)?
    private var activationObserver: NSObjectProtocol?
    private var lastActivationTime = ProcessInfo.processInfo.systemUptime
    private var clickGeneration = 0

    private init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastActivationTime = ProcessInfo.processInfo.systemUptime
            }
        }
    }
    func refresh() { trusted = AXIsProcessTrusted(); update() }
    func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        update()
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func dockTarget(at point: CGPoint) -> URL? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock",
              attribute(hit, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { return nil }
        return attribute(hit, kAXURLAttribute) as? URL
    }
    private func update() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        candidate = nil
        clickGeneration += 1
        guard enabled && trusted else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }
    private func handle(_ event: NSEvent) {
        guard let point = event.cgEvent?.location else { return }
        if event.type == .leftMouseDown {
            candidate = nil
            clickGeneration += 1
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  event.clickCount == 1,
                  event.timestamp - lastActivationTime > 0.5,
                  let url = dockTarget(at: point),
                  let app = NSWorkspace.shared.frontmostApplication,
                  !app.isHidden,
                  app.bundleURL?.standardizedFileURL == url.standardizedFileURL else { return }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            let windows = attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []
            guard !windows.contains(where: { attribute($0, kAXMinimizedAttribute) as? Bool == true }),
                  windows.contains(where: {
                attribute($0, kAXMinimizedAttribute) as? Bool == false &&
                attribute($0, "AXFullScreen") as? Bool != true
            }) else { return }
            candidate = (app.processIdentifier, point)
        } else {
            guard let (pid, start) = candidate else { return }
            candidate = nil
            guard hypot(point.x - start.x, point.y - start.y) < 5,
                  let url = dockTarget(at: point),
                  NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL == url.standardizedFileURL else { return }
            let generation = clickGeneration
            let activationAtClick = lastActivationTime
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.enabled, AXIsProcessTrusted(),
                      self.clickGeneration == generation,
                      self.lastActivationTime == activationAtClick,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let windows = self.attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
                guard !windows.contains(where: { self.attribute($0, kAXMinimizedAttribute) as? Bool == true }) else { return }
                for window in windows where self.attribute(window, "AXFullScreen") as? Bool != true {
                    var settable: DarwinBoolean = false
                    if AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue {
                        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                    }
                }
            }
        }
    }
}
