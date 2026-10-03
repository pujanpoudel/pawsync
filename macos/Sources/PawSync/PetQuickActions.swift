import AppKit

@MainActor final class PetQuickActionsController {
    private var panel:PawPopupPanel?
    private weak var anchor:NSWindow?
    private let action:(String)->Void
    var attachment:(()->PetChromeAnchor)?
    private var pointerTimer:Timer?
    private var lastInBounds=Date()
    private var activeView:PetQuickActionsNativeView?
    var isVisible:Bool { panel?.isVisible == true }
    init(action:@escaping (String)->Void) { self.action=action }
    func show(near window:NSWindow) {
        anchor=window
        let context=attachment?() ?? .fallback(window)
        if panel == nil {
            let p=PawPopupPanel(contentRect:CGRect(x:0,y:0,width:300,height:238),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="PawSync Pet Actions";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.becomesKeyOnlyIfNeeded=true;p.ignoresMouseEvents=false;p.worksWhenModal=true
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            let view=PetQuickActionsNativeView(palette:context.palette) { [weak self] id in self?.dismiss();self?.action(id) }
            p.contentView=view;activeView=view;panel=p
        }
        activeView?.palette=context.palette
        // The empty middle surrounds the companion's ears and shoulders.
        let frame=context.clamp(CGRect(x:context.pet.midX-150,y:context.pet.maxY-115,width:300,height:238))
        panel?.setFrame(frame,display:true);panel?.orderFrontRegardless();lastInBounds=Date()
        updatePointer()
        if pointerTimer == nil {
            let timer=Timer(timeInterval:0.08,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.updatePointer() } }
            timer.tolerance=0.02;RunLoop.main.add(timer,forMode:.common);pointerTimer=timer
        }
    }
    func scheduleDismiss() { lastInBounds=Date().addingTimeInterval(-0.1) }
    func dismiss() { panel?.orderOut(nil);pointerTimer?.invalidate();pointerTimer=nil }
    private func updatePointer() {
        guard let panel,panel.isVisible else { return }
        let cursor=NSEvent.mouseLocation
        let point=panel.convertPoint(fromScreen:cursor)
        let parentPoint=activeView?.superview?.convert(point,from:nil) ?? point
        // A transparent hole in an NSView does not itself pass through an NSWindow.
        // Keep the entire panel mouse-transparent until a real button is under it.
        panel.ignoresMouseEvents=activeView?.hitTest(parentPoint) == nil
        let pet=attachment?().pet ?? anchor?.frame ?? .zero
        if panel.frame.contains(cursor) || pet.insetBy(dx:-20,dy:-20).contains(cursor) { lastInBounds=Date() }
        else if Date().timeIntervalSince(lastInBounds)>0.45 { dismiss() }
    }
}

@MainActor final class PetQuickActionsNativeView:NSView {
    var palette:PetChromePalette { didSet { for button in buttons { button.palette=palette } } }
    private(set) var buttons:[PetPawActionButton]=[]
    init(palette:PetChromePalette,action:@escaping (String)->Void) {
        self.palette=palette;super.init(frame:CGRect(x:0,y:0,width:300,height:238))
        let items=[("hello","Say hi","heart.fill"),("water","Water","drop.fill"),("reminder","Remind me","bell.fill"),("focus","Focus","timer"),("walk","Walk","figure.walk"),("files","Pocket","doc.fill")]
        let centers:[CGPoint]=[CGPoint(x:35,y:163),CGPoint(x:51,y:91),CGPoint(x:111,y:43),CGPoint(x:189,y:43),CGPoint(x:249,y:91),CGPoint(x:265,y:163)]
        for (index,item) in items.enumerated() {
            let button=PetPawActionButton(title:item.1,symbol:item.2) { action(item.0) };button.palette=palette
            button.identifier=NSUserInterfaceItemIdentifier(item.0);button.frame=CGRect(x:centers[index].x-29,y:centers[index].y-31,width:58,height:67)
            addSubview(button);buttons.append(button)
        }
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint)->NSView? {
        let local=convert(point,from:superview)
        guard bounds.contains(local) else { return nil }
        for button in buttons where button.frame.contains(local) { return button }
        return nil
    }
}

@MainActor final class PetPawActionButton:PetSoftButton {
    override func draw(_ dirtyRect:NSRect) {
        let inset:CGFloat=isHighlighted ? 3 : hovered ? 0 : 1
        PetChromeDrawing.paw(in:CGRect(x:4+inset,y:1+inset,width:50-inset*2,height:50-inset*2),palette:palette,pressed:hovered || isHighlighted)
        if let image,let icon=image.withSymbolConfiguration(.init(pointSize:15,weight:.medium)) {
            let tinted=NSImage(size:icon.size,flipped:false) { rect in icon.draw(in:rect);self.palette.ink.setFill();rect.fill(using:.sourceAtop);return true }
            tinted.draw(in:CGRect(x:21,y:28,width:16,height:16))
        }
        PetChromeDrawing.label(title,in:CGRect(x:0,y:54,width:58,height:13),size:9,color:palette.ink,weight:hovered ? .bold:.medium)
    }
}
