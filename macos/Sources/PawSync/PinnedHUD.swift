import AppKit
import SwiftUI

struct HUDMetric:Identifiable,Equatable { var id:String; var label:String; var value:String; var icon:String }
struct HUDEntry:Equatable { var source:String; var title:String; var priority:Int; var metrics:[HUDMetric] }
@MainActor final class PinnedHUD:ObservableObject {
    @Published private(set) var current:HUDEntry?
    private var entries:[String:HUDEntry]=[:]
    private var panel:NSPanel?
    private weak var petWindow:NSWindow?
    private var observer:NSObjectProtocol?
    private var suspended=false
    private var scale:CGFloat=1
    func attach(to window:NSWindow) {
        petWindow=window
        observer=NotificationCenter.default.addObserver(forName:NSWindow.didMoveNotification,object:window,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
    }
    func submit(_ entry:HUDEntry?,source:String) {
        guard source.count <= 100 else { return }
        if let entry {
            guard entries.count < 32 || entries[source] != nil,entry.metrics.count <= 4,entry.title.count <= 100,entry.metrics.allSatisfy({$0.id.count <= 80 && $0.label.count <= 40 && $0.value.count <= 60 && $0.icon.count <= 60}) else { return }
            entries[source]=entry
        } else { entries.removeValue(forKey:source) }
        refresh()
    }
    func setSuspended(_ value:Bool) { suspended=value; refresh() }
    func setScale(_ value:Double) { let value=CGFloat(max(0.7,min(1.5,value))); guard scale != value else { return }; scale=value; panel?.contentView=nil; refresh() }
    private func refresh() {
        let candidate=entries.values.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.source < $1.source }.first
        let changed=current != candidate
        if changed { current=candidate }
        guard !suspended,current != nil,let petWindow,petWindow.isVisible else { panel?.orderOut(nil); return }
        if panel == nil {
            let panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=false; panel.hidesOnDeactivate=false; panel.ignoresMouseEvents=true
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]; panel.level = .floating; self.panel=panel
        }
        if !changed,panel?.contentView != nil { reposition(); if panel?.isVisible != true { panel?.orderFrontRegardless() }; return }
        let height:CGFloat = (current?.metrics.count ?? 0) > 2 ? 110 : 76
        panel?.setContentSize(CGSize(width:250*scale,height:height*scale))
        panel?.contentView=NSHostingView(rootView:PinnedHUDView(hud:self).frame(width:250,height:height).scaleEffect(scale,anchor:.topLeading).frame(width:250*scale,height:height*scale,alignment:.topLeading))
        reposition(); panel?.orderFrontRegardless()
    }
    private func reposition() {
        guard let panel,let petWindow else { return }
        let visible=petWindow.screen?.visibleFrame ?? petWindow.frame
        panel.setFrameOrigin(CGPoint(x:max(visible.minX,min(visible.maxX-panel.frame.width,petWindow.frame.midX-panel.frame.width/2)),y:max(visible.minY,min(visible.maxY-panel.frame.height,petWindow.frame.maxY-20))))
    }
    func shutdown() { panel?.orderOut(nil); panel?.contentView=nil; panel=nil; if let observer { NotificationCenter.default.removeObserver(observer) } }
}
private struct PinnedHUDView:View {
    @ObservedObject var hud:PinnedHUD
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let entry=hud.current {
                Text(entry.title).font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:8) {
                    ForEach(entry.metrics) { metric in Label { VStack(alignment:.leading,spacing:1) { Text(metric.value).font(.system(size:12,weight:.semibold,design:.rounded)); Text(metric.label).font(.system(size:9)) } } icon: { Image(systemName:metric.icon).foregroundStyle(.purple) } }
                }
            }
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:.windowBackgroundColor).opacity(0.96),in:RoundedRectangle(cornerRadius:18))
    }
}
