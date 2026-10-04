import AppKit
import SpriteKit
import QuartzCore

@MainActor final class DesktopOverlayWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = false; hidesOnDeactivate = false; isReleasedWhenClosed = false
        // The pet can receive a mouse-down without taking keyboard focus from
        // the app underneath it. A panel that can never become key can drop
        // clicks before the SKView's hit test is reached.
        becomesKeyOnlyIfNeeded = true; worksWhenModal = true
        title = "PawSync Companion"
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PetInteractionView: SKView {
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    weak var controller: OverlayController?
    private var previous: CGPoint?
    private var moving = false
    private var petTracking:NSTrackingArea?
    override func draggingEntered(_ sender:any NSDraggingInfo) -> NSDragOperation {
        if let id=sender.draggingPasteboard.string(forType:.string),id.hasPrefix("free."),id.count<=80 { return .copy }
        guard let controller,controller.canAcceptFiles(fileURLs(sender.draggingPasteboard)) else { return [] }
        controller.setDropHighlight(true)
        controller.showDropTarget?()
        return .copy
    }
    override func draggingUpdated(_ sender:any NSDraggingInfo)->NSDragOperation {
        if let id=sender.draggingPasteboard.string(forType:.string),id.hasPrefix("free."),id.count<=80 { return .copy }
        guard let controller,controller.canAcceptFiles(fileURLs(sender.draggingPasteboard)) else { controller?.setDropHighlight(false);return [] }
        controller.setDropHighlight(true);return .copy
    }
    override func draggingEnded(_ sender:any NSDraggingInfo) { controller?.setDropHighlight(false);controller?.hideDropTarget?() }
    override func performDragOperation(_ sender:any NSDraggingInfo) -> Bool {
        if let id=sender.draggingPasteboard.string(forType:.string),id.count<=80,let scene {
            defer { controller?.endHatDrag() }
            let local=convert(sender.draggingLocation,from:nil)
            return controller?.onHatDrop?(id,scene.convertPoint(fromView:local)) ?? false
        }
        guard let controller else { return false }
        defer { controller.setDropHighlight(false);controller.hideDropTarget?() }
        return controller.onFileDrop?(fileURLs(sender.draggingPasteboard)) ?? false
    }
    override func draggingExited(_ sender:(any NSDraggingInfo)?) { controller?.setDropHighlight(false);controller?.hideDropTarget?() }
    private func fileURLs(_ pasteboard:NSPasteboard)->[URL] {
        let objects=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [NSURL] ?? []
        return objects.map{$0 as URL}
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let petTracking { removeTrackingArea(petTracking) }
        petTracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        if let petTracking { addTrackingArea(petTracking) }
    }
    override func mouseEntered(with event:NSEvent) { revealPocketIfPet(event.locationInWindow) }
    override func mouseMoved(with event:NSEvent) { revealPocketIfPet(event.locationInWindow) }
    private func revealPocketIfPet(_ point:NSPoint) {
        guard let controller,controller.hitPet(fromView:point) else { return }
        if controller.hitHeldFiles(fromView:point) { controller.showFileShelf?() }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), let scene, let pet = controller?.pet,
              (pet.containsOpaquePoint(scene.convertPoint(fromView: local)) || pet.containsHeldFilesPoint(scene.convertPoint(fromView:local))) else { return nil }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount>=2 {
            previous=nil;controller?.isInteracting=false
            if event.clickCount == 2 { controller?.showQuickActions?() }
            return
        }
        previous = NSEvent.mouseLocation
        moving = event.modifierFlags.contains(.option)
        controller?.isInteracting = true
        controller?.reactToPetClick()
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard let previous else { return }
        if moving {
            controller?.movePet(by: CGSize(width: point.x - previous.x, height: point.y - previous.y))
        } else { controller?.reactToPetting(direction: point.x - previous.x) }
        self.previous = point
    }
    override func mouseUp(with event: NSEvent) {
        previous = nil; controller?.isInteracting = false; controller?.updatePassThrough()
    }
    override func rightMouseDown(with event: NSEvent) {
        controller?.reactToPetClick()
    }
}

@MainActor final class CompanionScene: SKScene {
    var step: (() -> Void)?
    override func update(_ currentTime: TimeInterval) { step?() }
}

@MainActor final class OverlayController: NSObject {
    let window = DesktopOverlayWindow()
    let view = PetInteractionView(frame: CGRect(x: 0, y: 0, width: 280, height: 260))
    let scene = CompanionScene(size: CGSize(width: 280, height: 260))
    private(set) var pet: (SKNode & CompanionAnimating)?
    let preferences: Preferences
    var showSettings: (() -> Void)?
    var isSettingsPoint: ((CGPoint) -> Bool)?
    var makeContextMenu: (() -> NSMenu)?
    var showFileShelf:(()->Void)?
    var storedFileCount:(()->Int)?
    var companionUIActive:(()->Bool)?
    var showDropTarget:(()->Void)?
    var hideDropTarget:(()->Void)?
    var showQuickActions:(()->Void)?
    var canAcceptFiles:(([URL])->Bool)?
    var onFileDrop:(([URL])->Bool)?
    var onHatDrop: ((String,CGPoint)->Bool)?
    var shouldTemporarilyHide: (() -> Bool)?
    var reactionSettings: ReactionSettings?
    var movementSettings:PetPresentationStore?
    var restorePresentation:(()->Void)?
    private(set) var temporarilyHidden = false
    var isHidden: Bool { preferences.hidden || temporarilyHidden }
    private var currentReaction: PetReaction = .idle
    private var resumeReaction = false
    private let statusLabel = SKLabelNode(fontNamed: NSFont.systemFont(ofSize:11,weight:.semibold).fontName)
    var onPetting: (() -> Void)?
    var onPetWake: (() -> Void)?
    var onWake: (() -> Void)?
    var onVisibilityChanged: (() -> Void)?
    var onReminderDismiss: (() -> Bool)?
    var windowEdge: (() -> CGRect?)?
    private let travelDriver = SKNode()
    private var musicAudible = false
    private var musicBeat = 0.5
    private var dancing = false
    private var nearbySince: Date?
    private var nextCursorReaction = Date.distantPast
    var isInteracting = false
    var focusSleeping = false { didSet { updateSleep() } }
    var careSleeping = false { didSet { if careSleeping != oldValue { updateSleep() } } }
    private var screenSleeping = false
    private var idleSleeping = false
    private var menuSleeping = false
    var isMenuSleeping:Bool { menuSleeping }
    private var lastInput = Date()
    private var animationDeadline = Date()
    private var renderPauseWork:DispatchWorkItem?
    private var nextBreath = Date()
    private var lastPettingSound = Date.distantPast
    private(set) var receivingFiles=false
    private var tick: Timer?
    private var pointerFallback: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var screen: NSScreen?
    private var freeOrigin: CGPoint?
    private var settingsVisible = false
    private var wardrobeDragging = false
    private var hatDragGeneration = 0
    func beginHatDrag() {
        hatDragGeneration+=1; let generation=hatDragGeneration; wardrobeDragging=true; window.level = .floating
        updatePassThrough()
        DispatchQueue.main.asyncAfter(deadline:.now()+12) { [weak self] in if self?.hatDragGeneration == generation { self?.endHatDrag() } }
    }
    func endHatDrag() { wardrobeDragging=false; setSettingsVisible(settingsVisible) }
    private var walking = false
    private var nextWander = Date().addingTimeInterval(15)
    private var patrolRight=false
    private var movementGeneration = 0
    var isScreenSleeping: Bool { screenSleeping }
    var canRoam = true

    static func clampedOrigin(_ point: CGPoint, in visible: CGRect, size: CGSize = CGSize(width: 280, height: 260)) -> CGPoint {
        CGPoint(x: max(visible.minX, min(visible.maxX - size.width, point.x)), y: max(visible.minY, min(visible.maxY - size.height, point.y)))
    }

    func setSettingsVisible(_ visible: Bool) {
        settingsVisible = visible
        // Keep the pet visible, but always let our own controls receive clicks.
        window.level = visible ? .normal : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        updatePassThrough()
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        view.controller = self
        view.registerForDraggedTypes([.string,.fileURL])
        view.allowsTransparency = true; view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true; view.shouldCullNonVisibleNodes = true
        scene.backgroundColor = .clear; scene.scaleMode = .resizeFill
        scene.step = { [weak self] in
            guard let self, self.walking else { return }
            self.window.setFrameOrigin(self.travelDriver.position)
        }
        view.presentScene(scene)
        window.contentView = view
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reposition()
                // Reassert all-Spaces membership after the transition so a
                // nonactivating panel cannot remain on its original desktop.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.18) { [weak self] in
                    guard let self else { return }
                    self.window.collectionBehavior=[.canJoinAllSpaces,.ignoresCycle,.fullScreenAuxiliary]
                    self.reposition()
                    if !self.isHidden && !self.settingsVisible { self.window.orderFrontRegardless() }
                }
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenSleeping = true; self?.stopWalking(); self?.stopDance(); self?.pet?.setRenderingSuspended(true); self?.renderPauseWork?.cancel(); self?.view.isPaused = true; self?.onVisibilityChanged?() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenSleeping = false; self?.reposition(); self?.animate(for: 0.8); self?.onVisibilityChanged?(); self?.onWake?() }
        })
        appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
        tick?.tolerance = 0.2
        reposition()
    }
    func setInputMonitoring(_ enabled: Bool) {
        pointerFallback?.invalidate(); pointerFallback = nil
        // Cursor-only fallback remains active even if a keyboard tap is live.
        // A paused render loop or a missed mouse-move event must not strand hit testing.
        pointerFallback = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePassThrough() }
        }
        pointerFallback?.tolerance = 0.01
    }
    func loadPet(_ id: String) throws {
        stopWalking(); stopDance()
        pet?.setRenderingSuspended(true); pet?.onNeedsRender=nil
        let node: SKNode & CompanionAnimating
        if let spec = PetStore.frameOriginal(id) ?? PetStore.imports.first(where: { $0.id == id }) { node = try FramePetNode(spec: spec) }
        else { node = try PetSpriteNode(manifest: PetStore.load(id), directory: PetStore.directory(for: id)) }
        scene.removeAllChildren(); scene.addChild(travelDriver);
        animationDeadline=Date()
        statusLabel.fontSize = 11; statusLabel.fontColor = .systemPurple; statusLabel.zPosition = 80; scene.addChild(statusLabel); currentReaction = .idle; statusLabel.text = nil; pet = node; node.position = CGPoint(x: 140, y: 32); scene.addChild(node)
        view.preferredFramesPerSecond=node is FramePetNode ? 30 : 60
        node.onNeedsRender = { [weak self,weak node] in self?.animate(for:node?.requiresContinuousRendering == true ? 0.35:0.08) }
        node.setRenderingSuspended(screenSleeping || isHidden || preferences.reactionsPaused)
        setScale(preferences.petScale)
        node.setAccessory(preferences.accessory)
        node.setHeldFileCount(storedFileCount?() ?? 0)
        updateSleep(); animate(for: 3); node.idle()
        updatePassThrough()
    }
    private func frontWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        guard let info = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        // Quartz is top-left based on the main display; AppKit is bottom-left based.
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: mainTop - rect.maxY, width: rect.width, height: rect.height)
    }
    func reposition(focusedPoint: CGPoint? = nil) {
        temporarilyHidden = shouldTemporarilyHide?() ?? false
        let front = frontWindowFrame()
        let point = focusedPoint ?? front.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        guard let focused = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        stopWalking()
        if screen !== focused { freeOrigin = nil }
        screen = focused
        let visible = focused.visibleFrame
        let local = CGRect(origin: .zero, size: visible.size)
        let width = scene.size.width, height = scene.size.height
        var origin: CGPoint
        switch preferences.anchor {
        case .dock: origin = CGPoint(x: local.maxX - width - 20, y: 0)
        case .notch: origin = CGPoint(x: local.midX - width/2, y: local.maxY - height)
        case .activeWindow:
            let rect = front ?? visible
            origin = CGPoint(x: rect.maxX - visible.minX - width + 50, y: rect.minY - visible.minY - 12)
        case .free: origin = freeOrigin ?? CGPoint(x: local.midX - width/2, y: 30)
        }
        origin.x = max(0, min(local.width - width, origin.x)); origin.y = max(0, min(local.height - height, origin.y))
        // The transparent panel is only pet-sized, never a display-sized input shield.
        window.setFrame(CGRect(x: visible.minX + origin.x, y: visible.minY + origin.y, width: width, height: height), display: false)
        pet?.setRenderingSuspended(isHidden || screenSleeping || preferences.reactionsPaused)
        if isHidden { window.orderOut(nil); view.isPaused = true }
        else if !settingsVisible { window.orderFrontRegardless() }
        else if !window.isVisible { window.orderFront(nil) }
        onVisibilityChanged?()
        updatePassThrough()
    }
    func movePet(by delta: CGSize) {
        stopWalking(); preferences.movement = .stay
        preferences.anchor = .free
        guard let visible = screen?.visibleFrame else { return }
        freeOrigin = CGPoint(x: max(0, min(visible.width - scene.size.width, window.frame.minX - visible.minX + delta.width)), y: max(0, min(visible.height - scene.size.height, window.frame.minY - visible.minY + delta.height)))
        window.setFrameOrigin(CGPoint(x: visible.minX + freeOrigin!.x, y: visible.minY + freeOrigin!.y))
    }
    func updatePassThrough() {
        guard !isInteracting else { return }
        guard !screenSleeping, !isHidden else { window.ignoresMouseEvents = true; return }
        if settingsVisible, !wardrobeDragging, isSettingsPoint?(NSEvent.mouseLocation) == true {
            window.ignoresMouseEvents = true
            return
        }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = view.convert(local, from: window.contentView)
        let hit = view.bounds.contains(viewPoint) && ((pet?.containsOpaquePoint(scene.convertPoint(fromView: viewPoint)) ?? false) || (pet?.containsHeldFilesPoint(scene.convertPoint(fromView:viewPoint)) ?? false))
        if window.ignoresMouseEvents == hit { window.ignoresMouseEvents = !hit }
        let scenePoint = scene.convertPoint(fromView: viewPoint)
        let near = hypot(local.x-scene.size.width/2, local.y-scene.size.height*0.45) < 130
        if currentReaction == .idle, near, !focusSleeping, !careSleeping, !idleSleeping, !preferences.reactionsPaused, canRoam {
            if nearbySince == nil { nearbySince = Date() }
            if Date().timeIntervalSince(nearbySince!) > 0.6, Date() > nextCursorReaction {
                nextCursorReaction = Date().addingTimeInterval(3)
                if !(pet is FramePetNode) { animate(for:1.2) }; pet?.look(toward: scenePoint)
            }
        } else { nearbySince = nil }
    }
    func typing() {
        guard !preferences.reactionsPaused else { return }
        stopWalking(); stopDance()
        interruptReaction()
        didReceiveInput()
        guard !focusSleeping, !careSleeping else { return }
        animate(for: 0.7); pet?.typing()
    }
    func previewTyping() {
        for index in 0..<8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.14) { [weak self] in self?.typing() }
        }
    }
    func previewClick() { click(at: CGPoint(x: window.frame.minX - 150, y: window.frame.midY)) }
    func click(at screenPoint: CGPoint) {
        guard !preferences.reactionsPaused else { return }
        let wasWalking=walking
        stopWalking(); stopDance()
        interruptReaction()
        didReceiveInput()
        // A click on another display moves the companion; ordinary clicks don't
        // reorder a window over Settings or move the target during a mouse-down.
        if screen?.frame.contains(screenPoint) != true { reposition(focusedPoint: screenPoint) }
        guard !focusSleeping, !careSleeping else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = view.convert(windowPoint, from: window.contentView)
        let point = scene.convertPoint(fromView: viewPoint)
        // Direct pet interactions are handled by the view's separate petting gesture.
        guard wasWalking || pet?.containsOpaquePoint(point) != true else { return }
        animate(for: 0.6); pet?.click(toward: point)
    }
    private func didReceiveInput() {
        lastInput = Date()
        if idleSleeping { idleSleeping = false; updateSleep() }
    }
    func reactToPetClick() {
        stopWalking(); stopDance(); interruptReaction(); didReceiveInput()
        if onReminderDismiss?() == true { return }
        if careSleeping { onPetWake?() }
        guard !focusSleeping, !careSleeping else { return }
        animate(for: 1.6); pet?.cuddle()
    }
    func reactToPetting(direction: CGFloat) {
        guard !focusSleeping, !careSleeping else { return }
        stopWalking(); stopDance()
        interruptReaction()
        didReceiveInput(); animate(for: 1.5); pet?.pet(direction: direction)
        if Date().timeIntervalSince(lastPettingSound) > 1.5 { lastPettingSound = Date(); onPetting?() }
    }
    private func interruptReaction() {
        if currentReaction.loops { resumeReaction = true }
        pet?.removeAction(forKey: "mapped-reaction")
    }
    func react(_ reaction: PetReaction) {
        guard !focusSleeping, !isHidden, !screenSleeping else { return }
        stopWalking(); stopDance(); currentReaction = reaction; resumeReaction = false
        statusLabel.text = reaction == .idle ? nil : reaction.rawValue.capitalized
        playCurrentReaction()
        if !reaction.loops, reaction != .idle {
            DispatchQueue.main.asyncAfter(deadline: .now()+3) { [weak self] in
                guard let self, self.currentReaction == reaction else { return }
                self.currentReaction = .idle; self.statusLabel.text = nil
            }
        }
    }
    private func playCurrentReaction() {
        animate(for: currentReaction.loops ? 1.2 : 3)
        pet?.play(reactionSettings?.animation(for:currentReaction) ?? currentReaction.defaultAnimation,looping:currentReaction.loops,relaxed:reactionSettings?.relaxedWaiting ?? false)
    }
    func integration(_ status: String) { react(status == "build_success" ? .success : .error) }
    func celebrate() { stopWalking(); stopDance(); animate(for: 1.5); pet?.celebrate() }
    func setScale(_ scale: Double) {
        stopWalking()
        let scale = max(0.4,min(1.8,scale))
        let size = CGSize(width: 280*scale, height: 260*scale)
        scene.size = size; view.frame = CGRect(origin: .zero, size: size)
        let visible = screen?.visibleFrame ?? window.frame
        let origin = Self.clampedOrigin(window.frame.origin, in: visible, size: size)
        window.setFrame(CGRect(origin: origin, size: size), display: false)
        statusLabel.position = CGPoint(x:size.width/2,y:size.height-30*scale)
        pet?.setScale(scale); pet?.position = CGPoint(x: size.width/2, y: 32*scale)
        animate(for: 0.3); updatePassThrough()
    }
    var chromeAnchor:PetChromeAnchor {
        let bounds=pet?.companionBoundsInScene ?? CGRect(x:65,y:32,width:150,height:200)
        let a=view.convert(scene.convertPoint(toView:bounds.origin),to:nil)
        let b=view.convert(scene.convertPoint(toView:CGPoint(x:bounds.maxX,y:bounds.maxY)),to:nil)
        let frame=window.convertToScreen(CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y)))
        let name=(PetStore.builtInNames[preferences.companion] ?? "Buddy").components(separatedBy:" the ").first ?? "Buddy"
        return PetChromeAnchor(pet:frame,visible:window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame,palette:.companion(preferences.companion),name:name)
    }
    func hitHeldFiles(fromView point:CGPoint)->Bool { pet?.containsHeldFilesPoint(scene.convertPoint(fromView:point)) ?? false }
    func hitPet(fromView point:CGPoint)->Bool {
        guard view.bounds.contains(point),let pet else { return false }
        return pet.containsOpaquePoint(scene.convertPoint(fromView:point)) || pet.containsHeldFilesPoint(scene.convertPoint(fromView:point))
    }
    func canAcceptFiles(_ urls:[URL])->Bool { canAcceptFiles?(urls) ?? false }
    func catchFiles(count:Int) {
        guard count>0 else { return }
        stopWalking();stopDance();interruptReaction();didReceiveInput();statusLabel.text="Caught it!"
        receivingFiles=false;pet?.setHeldFileCount(storedFileCount?() ?? count);pet?.catchFiles();animate(for:1.5)
        DispatchQueue.main.asyncAfter(deadline:.now()+2.5){[weak self] in if self?.statusLabel.text=="Caught it!" { self?.statusLabel.text=nil } }
    }
    func setHeldFileCount(_ count:Int) { pet?.setHeldFileCount(count) }
    func setDropHighlight(_ active:Bool) {
        guard active != receivingFiles else { return };receivingFiles=active
        statusLabel.text=active ? "Drop to catch!" : nil
        if active {
            stopWalking();stopDance();interruptReaction();didReceiveInput()
            if careSleeping { onPetWake?() }
            pet?.setReceivingFiles(true)
        } else { pet?.setReceivingFiles(false);updateSleep() }
        animate(for:0.5)
    }
    func showEmotion(_ emotion:PetEmotion) {
        guard !isHidden,!screenSleeping,!focusSleeping,!careSleeping else { return }
        stopWalking();stopDance();interruptReaction();didReceiveInput();pet?.express(emotion);animate(for:2)
    }
    func wave() { stopWalking(); stopDance(); animate(for: 1.5); pet?.wave() }
    func jumpNow() {
        guard !isHidden, !screenSleeping, !focusSleeping, !careSleeping, let visible = screen?.visibleFrame else { return }
        let target = Self.clampedOrigin(CGPoint(x: window.frame.minX + (window.frame.midX > visible.midX ? -140 : 140), y: window.frame.minY), in: visible, size: scene.size)
        travel(to: target, jump: true)
    }
    func wanderNow() {
        guard !focusSleeping,!careSleeping,!isHidden,!screenSleeping else { return }
        currentReaction = .idle; resumeReaction=false; statusLabel.text=nil
        pet?.removeAction(forKey:"mapped-reaction")
        nextWander = .distantPast; wanderIfNeeded(force: true)
    }
    func stopWalking() {
        movementGeneration += 1; travelDriver.removeAllActions()
        guard walking else { return }
        walking = false; pet?.setWalking(false); restorePresentation?(); updatePassThrough()
        view.preferredFramesPerSecond=pet is FramePetNode ? 30 : 60
    }
    private func travel(to target: CGPoint, jump: Bool, completion: (() -> Void)? = nil) {
        stopWalking(); stopDance(); walking = true
        view.preferredFramesPerSecond=60
        let generation = movementGeneration
        let start = window.frame.origin
        travelDriver.position = start
        let path = CGMutablePath(); path.move(to: start)
        if jump {
            let top = screen?.visibleFrame.maxY ?? max(start.y,target.y)+scene.size.height+100
            path.addQuadCurve(to: target, control: CGPoint(x: (start.x+target.x)/2, y: min(top-scene.size.height, max(start.y,target.y)+100)))
        } else { path.addLine(to: target) }
        let speed=max(20,min(200,movementSettings?.state.walkSpeed ?? 95))
        let duration = jump ? (pet is FramePetNode ? 1.68 : 1.1) : max(1.2,min(30,hypot(target.x-start.x,target.y-start.y)/speed))
        pet?.face(target.x-start.x)
        if jump { pet?.play(.jumping,looping:false,relaxed:false) } else { pet?.setWalking(true) }
        animate(for: duration+0.5); window.ignoresMouseEvents = true
        let motion = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
        motion.timingMode = .easeInEaseOut
        travelDriver.run(.sequence([motion, .run { [weak self] in
            guard let self, self.movementGeneration == generation else { return }
            self.window.setFrameOrigin(target); self.walking = false; self.view.preferredFramesPerSecond=self.pet is FramePetNode ? 30 : 60; self.pet?.setWalking(false); self.restorePresentation?(); self.updatePassThrough(); completion?()
        }]), withKey: "travel")
    }
    private func wanderIfNeeded(force: Bool = false) {
        guard currentReaction == .idle, canRoam, !walking, !dancing, !screenSleeping, (force || companionUIActive?() != true), (force || !settingsVisible), !isHidden, !focusSleeping, !careSleeping, !idleSleeping, !isInteracting, !preferences.reactionsPaused,
              force || (preferences.movement != .stay && Date().timeIntervalSince(lastInput) > 3), Date() >= nextWander,
              let visible = screen?.visibleFrame else { return }
        var y = window.frame.minY
        var x = window.frame.minX + CGFloat.random(in: -260...260)
        var jump = false
        if force {
            // The dock anchor starts near the right edge. Random positive
            // steps used to clamp to almost zero, making Walk look broken.
            let left=window.frame.minX-visible.minX
            let right=visible.maxX-scene.size.width-window.frame.minX
            x=window.frame.minX+(right > left ? min(260,right) : -min(260,left))
        }
        if preferences.movement == .patrol { patrolRight.toggle(); x=patrolRight ? visible.maxX-scene.size.width-10 : visible.minX+10 }
        if preferences.movement == .follow, !force {
            let pointer = NSEvent.mouseLocation; guard visible.contains(pointer) else { return }; x = pointer.x-scene.size.width/2
        }
        if preferences.anchor != .notch { y = visible.minY }
        if preferences.edgeTraversal, [.free, .activeWindow].contains(preferences.anchor), let frame = windowEdge?() {
            // Query only window geometry after Accessibility is granted. Alternate surfaces with deliberate arcs.
            if abs(window.frame.minY-visible.minY) < 20 { y = frame.maxY-32; x = min(frame.maxX-180,max(frame.minX,x)); jump = true }
            else { y = visible.minY; jump = true }
        }
        let target = Self.clampedOrigin(CGPoint(x: x, y: y), in: visible, size: scene.size)
        guard hypot(target.x-window.frame.minX,target.y-window.frame.minY) > 60 else { nextWander = Date().addingTimeInterval(4); return }
        let returnHome = preferences.anchor == .dock && preferences.movement == .roam
        travel(to: target, jump: jump) { [weak self] in
            guard let self, returnHome else { return }
            let completedGeneration = self.movementGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let self, self.movementGeneration == completedGeneration,
                      self.currentReaction == .idle, !self.walking, !self.isInteracting,
                      !self.isHidden, !self.screenSleeping, !self.focusSleeping,
                      !self.careSleeping, self.preferences.anchor == .dock,
                      self.preferences.movement == .roam, let screen = self.screen else { return }
                let frame = screen.visibleFrame
                let home = Self.clampedOrigin(CGPoint(x: frame.maxX - self.scene.size.width - 20,
                                                       y: frame.minY), in: frame, size: self.scene.size)
                if abs(self.window.frame.minX - home.x) > 40 { self.travel(to: home, jump: false) }
            }
        }
        let interval=max(3,min(120,movementSettings?.state.wanderInterval ?? 25))
        nextWander = Date().addingTimeInterval(preferences.movement == .follow ? 4 : interval)
    }
    func deliverReminder(_ item: PetReminder, completion: @escaping () -> Void) {
        stopDance(); stopWalking()
        guard !isHidden, !screenSleeping, let visible = screen?.visibleFrame else { completion(); return }
        idleSleeping = false
        // Priority reminders temporarily wake the focus pet without ending the focus timer.
        pet?.setSleeping(false)
        let target = Self.clampedOrigin(CGPoint(x: visible.midX-scene.size.width/2, y: visible.minY), in: visible, size: scene.size)
        let gesture = { [weak self] in self?.animate(for: 3); self?.pet?.reminderGesture(item.kind); completion() }
        if hypot(target.x-window.frame.minX,target.y-window.frame.minY) > 60 { travel(to: target, jump: window.frame.minY-visible.minY > 40, completion: gesture) }
        else { gesture() }
    }
    func finishReminder() { canRoam = true; updateSleep() }
    func musicSignal(_ audible: Bool, beat: TimeInterval) {
        musicAudible = audible; musicBeat = beat
        if !audible { stopDance() }
    }
    private func stopDance() {
        guard dancing else { return }
        dancing = false; pet?.setDancing(false, beat: musicBeat); animate(for: 0.2)
    }
    func refreshAppearance() {
        pet?.setRenderingSuspended(preferences.reactionsPaused || screenSleeping || isHidden)
        if preferences.reactionsPaused { stopWalking(); stopDance(); view.isPaused = true }
        else { didReceiveInput(); animate(for: 0.4) }
    }
    func setMenuSleeping(_ value:Bool) { menuSleeping=value;updateSleep() }
    private func updateSleep() {
        let asleep=focusSleeping || careSleeping || idleSleeping || menuSleeping
        if asleep { stopWalking(); stopDance() }
        animate(for: 1); pet?.setSleeping(asleep); restorePresentation?()
    }
    func animate(for seconds: TimeInterval) {
        guard !screenSleeping, !isHidden else { return }
        let duration=pet is FramePetNode && pet?.requiresContinuousRendering != true && !walking && !dancing ? min(0.08,seconds):seconds
        animationDeadline = max(animationDeadline, Date().addingTimeInterval(duration))
        view.isPaused = false
        renderPauseWork?.cancel()
        let work=DispatchWorkItem { [weak self] in
            guard let self,Date() >= self.animationDeadline else { return }; self.view.isPaused=true
        }
        renderPauseWork=work
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0.01,animationDeadline.timeIntervalSinceNow)+0.005,execute:work)
    }
    private func heartbeat() {
        guard !screenSleeping, !isHidden, !preferences.reactionsPaused else { stopWalking(); stopDance(); view.isPaused = true; return }
        if Date().timeIntervalSince(lastInput) >= 15, !idleSleeping,!receivingFiles { idleSleeping = true; updateSleep() }
        if currentReaction == .idle, musicAudible, canRoam, !focusSleeping, !careSleeping, !idleSleeping, !isInteracting, Date().timeIntervalSince(lastInput) > 1.5 {
            stopWalking()
            if !dancing { dancing = true; pet?.setDancing(true, beat: musicBeat) }
            animate(for: 1.2)
        }
        if currentReaction.loops, !focusSleeping, !careSleeping, !idleSleeping, canRoam, !walking, !isInteracting {
            if resumeReaction, Date().timeIntervalSince(lastInput) > 1.5 { resumeReaction = false; playCurrentReaction() }
            if !(pet is FramePetNode) { animate(for:1.2) }
        }
        if Date() > animationDeadline { view.isPaused = true }
        if !(pet is FramePetNode),currentReaction == .idle, !focusSleeping, !careSleeping, !idleSleeping, !dancing, !walking, canRoam, Date() > nextBreath {
            nextBreath = Date().addingTimeInterval(15); animate(for: 2.4); pet?.idle()
        }
        if preferences.anchor == .activeWindow, preferences.movement == .stay { reposition() }
        wanderIfNeeded()
    }
    @objc func petFromMenu() { reactToPetting(direction: 5) }
    @objc func settingsFromMenu() { showSettings?() }
    @objc func hideFromMenu() { preferences.hidden = true; reposition() }
    func stop() {
        renderPauseWork?.cancel(); pet?.setRenderingSuspended(true)
        stopWalking()
        tick?.invalidate(); pointerFallback?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        window.orderOut(nil)
    }
}
