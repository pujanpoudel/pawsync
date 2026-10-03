import AppKit
import SwiftUI

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
            let p=NSPanel(contentRect:CGRect(x:0,y:0,width:340,height:150),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.becomesKeyOnlyIfNeeded=true
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            let host=PetQuickActionsHostingView(rootView:PetQuickActionsView { [weak self] id in self?.action(id);self?.dismiss() })
            p.contentView=host
            panel=p
        }
        let screen=window.screen ?? NSScreen.main,visible=screen?.visibleFrame ?? .zero
        let size=CGSize(width:340,height:150),pet=window.frame
        let x=max(visible.minX,min(visible.maxX-size.width,pet.midX-size.width/2))
        // Float over the pet's head so the actions feel attached to its body.
        let y=max(visible.minY,min(visible.maxY-size.height,pet.maxY-100))
        panel?.setFrame(CGRect(origin:CGPoint(x:x,y:y),size:size),display:true);panel?.orderFrontRegardless()
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

@MainActor private final class PetQuickActionsHostingView:NSHostingView<PetQuickActionsView> {
    private let centers:[CGPoint]=[CGPoint(x:37,y:41),CGPoint(x:91,y:87),CGPoint(x:146,y:111),CGPoint(x:201,y:111),CGPoint(x:256,y:87),CGPoint(x:310,y:41)]
    required init(rootView:PetQuickActionsView) { super.init(rootView:rootView) }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override func hitTest(_ point:NSPoint)->NSView? {
        let swiftPoint=CGPoint(x:point.x,y:bounds.height-point.y)
        guard centers.contains(where:{abs($0.x-swiftPoint.x)<=34 && abs($0.y-swiftPoint.y)<=36}) else { return nil }
        return super.hitTest(point)
    }
}

private struct PetQuickActionsView:View {
    var perform:(String)->Void
    private let actions:[(String,String,String,Color)]=[
        ("water","Water break","drop.fill",Color(red:0.35,green:0.68,blue:0.79)),
        ("reminder","Reminder","bell.badge.fill",Color(red:0.88,green:0.49,blue:0.59)),
        ("focus","Focus","timer",Color(red:0.60,green:0.48,blue:0.75)),
        ("walk","Take a walk","figure.walk",Color(red:0.42,green:0.66,blue:0.53)),
        ("files","Pocket","tray.full.fill",Color(red:0.83,green:0.59,blue:0.39)),
        ("hello","Say hi","face.smiling",Color(red:0.85,green:0.53,blue:0.62))
    ]
    var body:some View {
        ZStack {
            ForEach(Array(actions.enumerated()),id:\.element.0) { index,item in
                let locations:[CGPoint]=[CGPoint(x:37,y:41),CGPoint(x:91,y:87),CGPoint(x:146,y:111),CGPoint(x:201,y:111),CGPoint(x:256,y:87),CGPoint(x:310,y:41)]
                OrbitActionButton(title:item.1,icon:item.2,color:item.3) { perform(item.0) }
                    .position(locations[index])
            }
        }.frame(width:340,height:150)
    }
}

private struct OrbitActionButton:View {
    let title:String;let icon:String;let color:Color;let action:()->Void
    var body:some View {
        Button(action:action) {
            Image(systemName:icon).font(.system(size:17,weight:.semibold)).foregroundStyle(color)
                .frame(width:46,height:46).background(color.opacity(0.12),in:Circle())
                .overlay(Circle().fill(LinearGradient(colors:[.white.opacity(0.30),color.opacity(0.10)],startPoint:.topLeading,endPoint:.bottomTrailing)))
                .overlay(Circle().stroke(.white.opacity(0.92),lineWidth:1.35))
                .shadow(color:color.opacity(0.22),radius:7,y:4)
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}
