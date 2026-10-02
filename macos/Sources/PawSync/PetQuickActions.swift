import AppKit
import SwiftUI

@MainActor final class PetQuickActionsController {
    private var panel:NSPanel?
    private weak var anchor:NSWindow?
    private let action:(String)->Void
    init(action:@escaping (String)->Void) { self.action=action }
    func show(near window:NSWindow) {
        anchor=window
        if panel == nil {
            let p=NSPanel(contentRect:CGRect(x:0,y:0,width:300,height:198),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.becomesKeyOnlyIfNeeded=true
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle];p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1)
            p.contentView=NSHostingView(rootView:PetQuickActionsView { [weak self] id in self?.action(id);self?.panel?.orderOut(nil) })
            panel=p
        }
        let screen=window.screen ?? NSScreen.main,visible=screen?.visibleFrame ?? .zero
        let size=CGSize(width:300,height:198),pet=window.frame
        let x=max(visible.minX,min(visible.maxX-size.width,pet.midX-size.width/2))
        let y=max(visible.minY,min(visible.maxY-size.height,pet.maxY+8))
        panel?.setFrame(CGRect(origin:CGPoint(x:x,y:y),size:size),display:true);panel?.orderFrontRegardless()
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
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) { Image(systemName:"sparkles").foregroundStyle(Color(red:0.82,green:0.45,blue:0.59));Text("A little menu").font(.system(size:15,weight:.bold,design:.rounded));Spacer();Button { perform("close") } label:{Image(systemName:"xmark").font(.system(size:10,weight:.bold)).foregroundStyle(.secondary).frame(width:23,height:23).background(.white.opacity(0.72),in:Circle())}.buttonStyle(.plain) }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(actions,id:\.0) { item in
                    Button { perform(item.0) } label:{VStack(spacing:6){Image(systemName:item.2).font(.system(size:16,weight:.semibold)).foregroundStyle(item.3);Text(item.1).font(.system(size:10,weight:.semibold,design:.rounded)).foregroundStyle(Color.primary.opacity(0.82)).lineLimit(1)}}.buttonStyle(.plain).frame(maxWidth:.infinity,minHeight:56).background(.white.opacity(0.66),in:RoundedRectangle(cornerRadius:14,style:.continuous)).overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.8),lineWidth:1))
                }
            }
        }.padding(13).frame(width:300,height:198).background(.ultraThinMaterial,in:PetBubbleShape()).overlay(PetBubbleShape().fill(LinearGradient(colors:[Color(red:1,green:0.94,blue:0.93).opacity(0.48),Color(red:0.92,green:0.87,blue:0.98).opacity(0.26)],startPoint:.topLeading,endPoint:.bottomTrailing))).overlay(PetBubbleShape().stroke(.white.opacity(0.86),lineWidth:1.2)).shadow(color:Color(red:0.56,green:0.36,blue:0.45).opacity(0.18),radius:17,y:7)
    }
}
