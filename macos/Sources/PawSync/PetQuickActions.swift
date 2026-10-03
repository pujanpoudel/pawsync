import AppKit

@MainActor final class PetQuickActionsController {
    private var panel:PawPopupPanel?
    private weak var anchor:NSWindow?
    private let action:(String)->Void
    var attachment:(()->PetChromeAnchor)?
    private var pointerTimer:Timer?
    private var globalClickMonitor:Any?
    private var localClickMonitor:Any?
    private var activeView:PetQuickActionsNativeView?
    var isVisible:Bool { panel?.isVisible == true }
    init(action:@escaping (String)->Void) { self.action=action }
    func show(near window:NSWindow) {
        anchor=window
        let context=attachment?() ?? .fallback(window)
        if panel == nil {
            let p=PawPopupPanel(contentRect:CGRect(x:0,y:0,width:344,height:266),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="PawSync Pet Actions";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.becomesKeyOnlyIfNeeded=true;p.ignoresMouseEvents=false;p.worksWhenModal=true
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            let view=PetQuickActionsNativeView(palette:context.palette) { [weak self] id in self?.dismiss();self?.action(id) }
            p.contentView=view;activeView=view;panel=p
        }
        activeView?.palette=context.palette
        // The empty middle surrounds the companion's ears and shoulders.
        let frame=context.clamp(CGRect(x:context.pet.midX-172,y:context.pet.maxY-130,width:344,height:266))
        panel?.setFrame(frame,display:true);panel?.orderFrontRegardless()
        updatePointer()
        if pointerTimer == nil {
            let timer=Timer(timeInterval:0.08,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.updatePointer() } }
            timer.tolerance=0.02;RunLoop.main.add(timer,forMode:.common);pointerTimer=timer
        }
        if globalClickMonitor == nil {
            globalClickMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissIfOutside() }
            }
            localClickMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.dismissIfOutside() };return event
            }
        }
    }
    func dismiss() {
        panel?.orderOut(nil);pointerTimer?.invalidate();pointerTimer=nil
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor=nil;localClickMonitor=nil
    }
    private func dismissIfOutside() {
        guard let panel,panel.isVisible else { return }
        let cursor=NSEvent.mouseLocation
        let pet=attachment?().pet ?? anchor?.frame ?? .zero
        if !panel.frame.contains(cursor) && !pet.insetBy(dx:-20,dy:-20).contains(cursor) { dismiss() }
    }
    private func updatePointer() {
        guard let panel,panel.isVisible else { return }
        let cursor=NSEvent.mouseLocation
        let point=panel.convertPoint(fromScreen:cursor)
        let parentPoint=activeView?.superview?.convert(point,from:nil) ?? point
        // A transparent hole in an NSView does not itself pass through an NSWindow.
        // Keep the entire panel mouse-transparent until a real button is under it.
        panel.ignoresMouseEvents=activeView?.hitTest(parentPoint) == nil
    }
}

@MainActor final class PetQuickActionsNativeView:NSView {
    var palette:PetChromePalette { didSet { for button in buttons { button.palette=palette } } }
    private(set) var buttons:[PetPawActionButton]=[]
    init(palette:PetChromePalette,action:@escaping (String)->Void) {
        self.palette=palette;super.init(frame:CGRect(x:0,y:0,width:344,height:266))
        let items=[("hello","Say hi","heart.fill"),("water","Water","drop.fill"),("reminder","Reminders","bell.fill"),("focus","Focus","timer"),("walk","Walk","figure.walk"),("files","Pocket","doc.fill")]
        let centers:[CGPoint]=[CGPoint(x:43,y:217),CGPoint(x:61,y:125),CGPoint(x:130,y:43),CGPoint(x:214,y:43),CGPoint(x:283,y:125),CGPoint(x:301,y:217)]
        for (index,item) in items.enumerated() {
            let button=PetPawActionButton(title:item.1,symbol:item.2) { action(item.0) };button.palette=palette
            button.identifier=NSUserInterfaceItemIdentifier(item.0);button.frame=CGRect(x:centers[index].x-40,y:centers[index].y-31,width:80,height:79)
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
    private(set) var caption:NSTextField!
    override init(title:String,symbol:String?=nil,action:@escaping ()->Void) {
        super.init(title:title,symbol:symbol,action:action)
        let label=PetActionCaption(labelWithString:title)
        label.font = .systemFont(ofSize:11,weight:.semibold)
        label.alignment = .center;label.lineBreakMode = .byClipping;label.isSelectable=false
        label.frame=CGRect(x:4,y:58,width:72,height:17)
        caption=label;addSubview(label)
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override func draw(_ dirtyRect:NSRect) {
        let inset:CGFloat=isHighlighted ? 3 : hovered ? 0 : 1
        PetChromeDrawing.paw(in:CGRect(x:15+inset,y:1+inset,width:50-inset*2,height:50-inset*2),palette:palette,pressed:hovered || isHighlighted)
        if let image,let icon=image.withSymbolConfiguration(.init(pointSize:15,weight:.medium)) {
            let tinted=NSImage(size:icon.size,flipped:false) { rect in icon.draw(in:rect);self.palette.ink.setFill();rect.fill(using:.sourceAtop);return true }
            tinted.draw(in:CGRect(x:32,y:28,width:16,height:16))
        }
        // Opaque fur-colored tags keep text readable over any desktop wallpaper.
        let tag=NSBezierPath(roundedRect:CGRect(x:2,y:54,width:76,height:23),xRadius:11,yRadius:11)
        PetChromeDrawing.paint(tag,fill:palette.fur,ink:palette.ink,width:1)
        caption.textColor=palette.ink
    }
}

@MainActor private final class PetActionCaption:NSTextField {
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}
