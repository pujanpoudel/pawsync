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
        var cloud=Path()
        cloud.move(to:CGPoint(x:45,y:18))
        cloud.addCurve(to:CGPoint(x:18,y:33),control1:CGPoint(x:30,y:4),control2:CGPoint(x:15,y:14))
        cloud.addCurve(to:CGPoint(x:13,y:66),control1:CGPoint(x:2,y:40),control2:CGPoint(x:2,y:58))
        cloud.addCurve(to:CGPoint(x:33,y:101),control1:CGPoint(x:4,y:82),control2:CGPoint(x:15,y:101))
        cloud.addCurve(to:CGPoint(x:75,y:108),control1:CGPoint(x:39,y:117),control2:CGPoint(x:62,y:120))
        cloud.addCurve(to:CGPoint(x:122,y:107),control1:CGPoint(x:93,y:122),control2:CGPoint(x:113,y:117))
        cloud.addCurve(to:CGPoint(x:173,y:109),control1:CGPoint(x:141,y:120),control2:CGPoint(x:160,y:120))
        cloud.addCurve(to:CGPoint(x:221,y:106),control1:CGPoint(x:190,y:119),control2:CGPoint(x:213,y:117))
        cloud.addCurve(to:CGPoint(x:261,y:88),control1:CGPoint(x:240,y:115),control2:CGPoint(x:264,y:103))
        cloud.addCurve(to:CGPoint(x:274,y:53),control1:CGPoint(x:282,y:82),control2:CGPoint(x:287,y:62))
        cloud.addCurve(to:CGPoint(x:250,y:23),control1:CGPoint(x:282,y:35),control2:CGPoint(x:269,y:20))
        cloud.addCurve(to:CGPoint(x:203,y:18),control1:CGPoint(x:239,y:7),control2:CGPoint(x:216,y:5))
        cloud.addCurve(to:CGPoint(x:151,y:16),control1:CGPoint(x:184,y:3),control2:CGPoint(x:164,y:2))
        cloud.addCurve(to:CGPoint(x:102,y:17),control1:CGPoint(x:130,y:1),control2:CGPoint(x:111,y:5))
        cloud.addCurve(to:CGPoint(x:45,y:18),control1:CGPoint(x:83,y:4),control2:CGPoint(x:56,y:4))
        cloud.closeSubpath()
        var path=cloud.applying(CGAffineTransform(scaleX:rect.width/300,y:(rect.height-29)/120))
        path.addEllipse(in:CGRect(x:rect.midX+9,y:rect.height-25,width:13,height:13))
        path.addEllipse(in:CGRect(x:rect.midX+30,y:rect.height-10,width:6,height:6))
        return path
    }
}
private struct CompanionSpeechView: View {
    @ObservedObject var speech: CompanionSpeech
    private let ink = Color(red: 0.34, green: 0.25, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: speech.isReminder ? "sparkles" : "heart.fill").foregroundStyle(Color.pink.opacity(0.8))
                Text(speech.title).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 2)
                Button { if speech.isReminder { speech.onDone?() } else { speech.dismiss() } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width:23,height:23).background(Color(red:1,green:0.89,blue:0.93),in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Dismiss bubble")
            }
            Text(speech.text).font(.system(size: 13, weight: .medium, design: .rounded)).lineSpacing(2).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
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
        }.foregroundStyle(ink).padding(.horizontal, 36).padding(.top, 27).padding(.bottom, 34)
            .frame(width: 290, height: speech.bubbleHeight, alignment: .topLeading)
            .background(BubbleShape().fill(Color(red: 1, green: 0.985, blue: 0.97)))
            .overlay(BubbleShape().stroke(Color(red: 0.87, green: 0.70, blue: 0.74), lineWidth: 1.6))
            .shadow(color: ink.opacity(0.13), radius: 10, y: 4)
            .contextMenu { if speech.isReminder { Button("Snooze 10 min") { speech.onSnooze?() }; Button("Dismiss") { speech.onDone?() } } }
    }
    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 6).background(.white.opacity(0.75), in: Capsule()) }.buttonStyle(.plain)
    }
}
