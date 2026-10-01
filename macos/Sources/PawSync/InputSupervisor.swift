import AppKit
import CoreGraphics
import Combine

@MainActor final class InputSupervisor: ObservableObject {
    @Published private(set) var authorized = CGPreflightListenEventAccess()
    @Published private(set) var running = false
    @Published private(set) var status = "Clicks work. Allow Input Monitoring for typing in other apps."
    // Aggregate counts only; no event contents or key identities are retained.
    @Published private(set) var typingPulses = 0
    @Published private(set) var clicks = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var globalKeyboardFallback: Any?
    private var permissionTimer: Timer?
    private var pendingTyping=0,pendingClicks=0
    private var counterUpdate:DispatchWorkItem?
    var onTyping: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var onPointer: (() -> Void)?

    func requestPermission() {
        _ = CGRequestListenEventAccess()
        start()
        if !running { openPrivacySettings() }
    }
    func start() {
        stop()
        // Global mouse observation excludes this app. The local monitor handles
        // our Settings and pet window, without consuming any control's input.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.receiveMouse(event.type) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown || event.type == .flagsChanged {
                    if self?.running != true { self?.typingTrigger() }
                } else { self?.receiveMouse(event.type) }
            }
            return event
        }
        attachKeyboardTap()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let allowed = CGPreflightListenEventAccess()
                if allowed != self.authorized || (allowed && !self.running) { self.attachKeyboardTap() }
            }
        }
        permissionTimer?.tolerance = 0.5
    }
    private func attachKeyboardTap() {
        detachKeyboardTap()
        authorized = CGPreflightListenEventAccess()
        guard authorized else {
            attachKeyboardFallback()
            status = "Clicks work. Allow Input Monitoring for typing in other apps."
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let supervisor = Unmanaged<InputSupervisor>.fromOpaque(context).takeUnretainedValue()
            // Return immediately. Only the event TYPE is forwarded, never keys/text.
            DispatchQueue.main.async { [weak supervisor] in supervisor?.receiveKeyboard(type) }
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            attachKeyboardFallback()
            running=globalKeyboardFallback != nil
            status = "Input Monitoring is enabled. Using the alternate global keyboard listener."
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = CGEvent.tapIsEnabled(tap: tap)
        if running,let globalKeyboardFallback { NSEvent.removeMonitor(globalKeyboardFallback); self.globalKeyboardFallback=nil }
        if !running { attachKeyboardFallback(); running=globalKeyboardFallback != nil }
        status = running ? "Typing and clicks are live in every app." : "Using the alternate global keyboard listener."
    }
    private func attachKeyboardFallback() {
        guard globalKeyboardFallback == nil else { return }
        globalKeyboardFallback=NSEvent.addGlobalMonitorForEvents(matching:[.keyDown,.flagsChanged]) { [weak self] _ in
            // NSEvent is deliberately discarded: only the occurrence matters.
            MainActor.assumeIsolated { self?.typingTrigger() }
        }
    }
    private func receiveKeyboard(_ type: CGEventType) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown, .flagsChanged: typingTrigger()
        default: break
        }
    }
    private func publishCountersSoon() {
        guard counterUpdate == nil else { return }
        let work=DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingTyping > 0 { self.typingPulses+=self.pendingTyping; self.pendingTyping=0 }
            if self.pendingClicks > 0 { self.clicks+=self.pendingClicks; self.pendingClicks=0 }
            self.counterUpdate=nil
        }
        counterUpdate=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    private func typingTrigger() { pendingTyping+=1; publishCountersSoon(); onTyping?() }
    private func receiveMouse(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            pendingClicks+=1; publishCountersSoon(); onClick?(NSEvent.mouseLocation)
        case .mouseMoved, .leftMouseDragged: onPointer?()
        default: break
        }
    }
    private func detachKeyboardTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; running = false
    }
    func stop() {
        counterUpdate?.cancel(); counterUpdate=nil
        if pendingTyping > 0 { typingPulses+=pendingTyping; pendingTyping=0 }
        if pendingClicks > 0 { clicks+=pendingClicks; pendingClicks=0 }
        permissionTimer?.invalidate(); permissionTimer = nil
        detachKeyboardTap()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let globalKeyboardFallback { NSEvent.removeMonitor(globalKeyboardFallback) }
        localMonitor = nil; mouseMonitor = nil
        globalKeyboardFallback=nil
    }
    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
