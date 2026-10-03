import AppKit
import SwiftUI

struct SpeechAction:Identifiable { let id:String; let title:String; let icon:String; let action:()->Void }

@MainActor final class CompanionSpeech: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var text = ""
    @Published private(set) var isReminder = false
    @Published private(set) var actions:[SpeechAction]=[]
    var isVisible:Bool { panel?.isVisible == true }
    var onVisibility:((Bool)->Void)?
    var onDone: (() -> Void)?
    var onAutoDismiss: (() -> Void)?
    var onSnooze: (() -> Void)?
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private weak var petWindow: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var scale:CGFloat=1
    @Published private(set) var bubbleHeight:CGFloat=152
    func setScale(_ value:Double) {
        scale=CGFloat(max(0.7,min(1.5,value)))
        refreshPanelContent()
        reposition()
    }
    private func refreshPanelContent() {
        panel?.setContentSize(CGSize(width:290*scale,height:bubbleHeight*scale))
        panel?.contentView=NSHostingView(rootView:CompanionSpeechView(speech:self).scaleEffect(scale,anchor:.topLeading).frame(width:290*scale,height:bubbleHeight*scale,alignment:.topLeading))
    }
    func attach(to window: NSWindow) {
        petWindow = window
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }
    @discardableResult func show(title: String, text: String, reminder: Bool = false, actions:[SpeechAction]=[]) -> Bool {
        // Actionable reminders keep presentation priority over greetings/rewards.
        guard reminder || !isReminder || panel?.isVisible != true else { return false }
        dismissTimer?.invalidate(); dismissTimer = nil
        self.title = String(title.prefix(120)); self.text = String(text.prefix(1000)); isReminder = reminder; self.actions=Array(actions.prefix(3))
        bubbleHeight = reminder || !self.actions.isEmpty ? 190 : 152
        if panel == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 290, height: bubbleHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "PawSync Message"; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            self.panel = panel
        }
        refreshPanelContent()
        panel?.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        reposition(); panel?.orderFrontRegardless(); onVisibility?(true)
        dismissTimer = Timer.scheduledTimer(withTimeInterval: reminder ? 12 : 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isReminder { self.onAutoDismiss?() }
                self.dismiss()
            }
        }
        return true
    }
    func reposition() {
        guard let panel, let petWindow else { return }
        let visible = petWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? petWindow.frame
        let x = max(visible.minX, min(visible.maxX - panel.frame.width, petWindow.frame.midX - panel.frame.width/2))
        let y = max(visible.minY, min(visible.maxY - panel.frame.height, petWindow.frame.maxY - 28))
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }
    func dismiss() { dismissTimer?.invalidate(); dismissTimer = nil; panel?.orderOut(nil); isReminder=false; onVisibility?(false) }
    func stop() {
        dismiss()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil; panel?.contentView = nil; panel = nil
    }
}

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius:CGFloat=25, tailHeight:CGFloat=17, bottom=rect.maxY-tailHeight
        var path=Path()
        path.move(to:CGPoint(x:rect.minX+radius,y:rect.minY))
        path.addLine(to:CGPoint(x:rect.maxX-radius,y:rect.minY))
        path.addQuadCurve(to:CGPoint(x:rect.maxX,y:rect.minY+radius),control:CGPoint(x:rect.maxX,y:rect.minY))
        path.addLine(to:CGPoint(x:rect.maxX,y:bottom-radius))
        path.addQuadCurve(to:CGPoint(x:rect.maxX-radius,y:bottom),control:CGPoint(x:rect.maxX,y:bottom))
        path.addLine(to:CGPoint(x:rect.midX+17,y:bottom))
        path.addQuadCurve(to:CGPoint(x:rect.midX,y:rect.maxY),control:CGPoint(x:rect.midX+9,y:bottom+12))
        path.addQuadCurve(to:CGPoint(x:rect.midX-17,y:bottom),control:CGPoint(x:rect.midX-9,y:bottom+12))
        path.addLine(to:CGPoint(x:rect.minX+radius,y:bottom))
        path.addQuadCurve(to:CGPoint(x:rect.minX,y:bottom-radius),control:CGPoint(x:rect.minX,y:bottom))
        path.addLine(to:CGPoint(x:rect.minX,y:rect.minY+radius))
        path.addQuadCurve(to:CGPoint(x:rect.minX+radius,y:rect.minY),control:CGPoint(x:rect.minX,y:rect.minY))
        path.closeSubpath();return path
    }
}
private struct CompanionSpeechView: View {
    @ObservedObject var speech: CompanionSpeech
    private let ink = Color(red: 0.34, green: 0.25, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: speech.isReminder && speech.title.localizedCaseInsensitiveContains("water") ? "drop.fill" : speech.isReminder ? "sparkles" : "heart.fill").foregroundStyle(speech.isReminder && speech.title.localizedCaseInsensitiveContains("water") ? Color(red:0.32,green:0.65,blue:0.78) : Color.pink.opacity(0.82))
                    .frame(width:25,height:25).background(Color.white.opacity(0.76),in:Circle())
                Text(speech.title).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 2)
                Button { if speech.isReminder { speech.onDone?() } else { speech.dismiss() } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width:23,height:23).background(Color(red:1,green:0.89,blue:0.93),in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Dismiss bubble")
            }
            Text(speech.text).font(.system(size: 12, weight: .medium, design: .rounded)).lineSpacing(2).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(.leading,3)
                .onTapGesture { if speech.isReminder { speech.onDone?() } else { speech.dismiss() } }
            if !speech.actions.isEmpty || speech.isReminder {
                HStack(spacing:8) {
                    if !speech.actions.isEmpty { ForEach(speech.actions) { action in pill(action.title,icon:action.icon,action:action.action) } }
                    else {
                        pill("Got it!",icon:"heart") { speech.onDone?() }
                        pill("10 min",icon:"moon") { speech.onSnooze?() }
                    }
                }
            }
        }.foregroundStyle(ink).padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 26)
            .frame(width: 290, height: speech.bubbleHeight, alignment: .topLeading)
            .background { ZStack { BubbleShape().fill(.ultraThinMaterial);BubbleShape().fill(LinearGradient(colors:[Color(red:1,green:0.93,blue:0.90).opacity(0.60),Color(red:0.95,green:0.89,blue:0.98).opacity(0.44)],startPoint:.topLeading,endPoint:.bottomTrailing));BubbleShape().stroke(Color.white.opacity(0.92),lineWidth:1.35) } }
            .shadow(color: Color(red:0.44,green:0.31,blue:0.39).opacity(0.15), radius: 13, y: 5)
            .contextMenu { if speech.isReminder { Button("Snooze 10 min") { speech.onSnooze?() }; Button("Dismiss") { speech.onDone?() } } }
    }
    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 6).background(.white.opacity(0.75), in: Capsule()) }.buttonStyle(.plain)
    }
}
