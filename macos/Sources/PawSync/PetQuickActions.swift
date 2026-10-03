import AppKit

@MainActor final class PetQuickActionsController {
    private var panel:NSPanel?
    private weak var anchor:NSWindow?
    private let action:(String)->Void
    private var pointerTimer:Timer?
    private var lastInBounds=Date()

    init(action:@escaping (String)->Void) { self.action=action }

    func show(near window:NSWindow) {
        anchor=window
        if panel == nil {
            let size=CGSize(width:360,height:184)
            let p=PawPopupPanel(contentRect:CGRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.becomesKeyOnlyIfNeeded=true;p.ignoresMouseEvents=false;p.worksWhenModal=true
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            p.contentView=PetQuickActionsNativeView(action:action)
            panel=p
        }
        let screen=window.screen ?? NSScreen.main,visible=screen?.visibleFrame ?? .zero
        let size=CGSize(width:360,height:184),pet=window.frame
        let x=max(visible.minX,min(visible.maxX-size.width,pet.midX-size.width/2))
        let y=max(visible.minY,min(visible.maxY-size.height,pet.maxY-76))
        panel?.setFrame(CGRect(origin:CGPoint(x:x,y:y),size:size),display:true)
        panel?.orderFrontRegardless()
        lastInBounds=Date()
        if pointerTimer == nil {
            pointerTimer=Timer.scheduledTimer(withTimeInterval:0.12,repeats:true){[weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,let panel=self.panel,panel.isVisible else { return }
                    let cursor=NSEvent.mouseLocation
                    if panel.frame.contains(cursor) || (self.anchor?.frame.insetBy(dx:-14,dy:-14).contains(cursor) ?? false) { self.lastInBounds=Date() }
                    else if Date().timeIntervalSince(self.lastInBounds)>0.38 { self.dismiss() }
                }
            }
        }
    }

    func scheduleDismiss() { lastInBounds=Date().addingTimeInterval(-0.12) }
    private func dismiss() { panel?.orderOut(nil);pointerTimer?.invalidate();pointerTimer=nil }
}

@MainActor private final class PetQuickActionsNativeView:NSView {
    private let action:(String)->Void
    private var buttons:[NSButton]=[]
    private let items:[(String,String,String,NSColor)]=[
        ("water","Water","drop.fill",NSColor(calibratedRed:0.35,green:0.67,blue:0.78,alpha:1)),
        ("reminder","Reminder","bell.badge.fill",NSColor(calibratedRed:0.83,green:0.43,blue:0.56,alpha:1)),
        ("focus","Focus","timer",NSColor(calibratedRed:0.57,green:0.45,blue:0.72,alpha:1)),
        ("walk","Walk","figure.walk",NSColor(calibratedRed:0.39,green:0.62,blue:0.48,alpha:1)),
        ("files","Pocket","tray.full.fill",NSColor(calibratedRed:0.77,green:0.52,blue:0.34,alpha:1)),
        ("hello","Say hi","face.smiling",NSColor(calibratedRed:0.82,green:0.48,blue:0.57,alpha:1))
    ]

    init(action:@escaping (String)->Void) {
        self.action=action
        super.init(frame:CGRect(x:0,y:0,width:360,height:184))
        for (index,item) in items.enumerated() {
            let button=NSButton(title:item.1,target:self,action:#selector(activate(_:)))
            button.identifier=NSUserInterfaceItemIdentifier(item.0)
            button.isBordered=false
            button.image=NSImage(systemSymbolName:item.2,accessibilityDescription:item.1)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:17,weight:.semibold))
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor=item.3
            button.attributedTitle=NSAttributedString(string:item.1,attributes:[.font:NSFont.systemFont(ofSize:10,weight:.semibold),.foregroundColor:NSColor(calibratedRed:0.33,green:0.27,blue:0.29,alpha:1)])
            button.wantsLayer=true
            button.layer?.cornerRadius=18
            button.layer?.backgroundColor=NSColor(calibratedRed:1,green:0.97,blue:0.92,alpha:1).cgColor
            button.layer?.borderColor=NSColor(calibratedRed:0.91,green:0.84,blue:0.78,alpha:1).cgColor
            button.layer?.borderWidth=1
            button.layer?.shadowColor=NSColor(calibratedRed:0.33,green:0.25,blue:0.23,alpha:1).withAlphaComponent(0.12).cgColor
            button.layer?.shadowOpacity=1;button.layer?.shadowRadius=5;button.layer?.shadowOffset=CGSize(width:0,height:-2)
            button.setButtonType(.momentaryChange)
            button.frame=Self.buttonFrame(index)
            button.setAccessibilityLabel(item.1)
            addSubview(button);buttons.append(button)
        }
    }

    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { false }

    override func hitTest(_ point:NSPoint)->NSView? {
        guard buttons.contains(where:{$0.frame.insetBy(dx:-3,dy:-3).contains(point)}) else { return nil }
        return super.hitTest(point)
    }

    @objc private func activate(_ sender:NSButton) {
        guard let id=sender.identifier?.rawValue else { return }
        action(id)
    }

    private static func buttonFrame(_ index:Int)->CGRect {
        let frames=[
            CGRect(x:7,y:117,width:92,height:58),CGRect(x:134,y:132,width:92,height:58),CGRect(x:261,y:117,width:92,height:58),
            CGRect(x:34,y:8,width:92,height:58),CGRect(x:134,y:0,width:92,height:58),CGRect(x:234,y:8,width:92,height:58)
        ]
        return frames[index]
    }
}
