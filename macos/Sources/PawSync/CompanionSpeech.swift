import AppKit
import Combine

struct SpeechAction:Identifiable { let id:String;let title:String;let icon:String;let action:()->Void }

@MainActor final class CompanionSpeech:ObservableObject {
    @Published private(set) var title=""
    @Published private(set) var text=""
    @Published private(set) var isReminder=false
    @Published private(set) var actions:[SpeechAction]=[]
    @Published private(set) var bubbleHeight:CGFloat=170
    var isVisible:Bool { panel?.isVisible == true }
    var onVisibility:((Bool)->Void)?
    var onDone:(()->Void)?
    var onAutoDismiss:(()->Void)?
    var onSnooze:(()->Void)?
    var attachment:(()->PetChromeAnchor)?
    private var panel:PawPopupPanel?
    private var dismissTimer:Timer?
    private weak var petWindow:NSWindow?
    private var moveObserver:NSObjectProtocol?
    private var scale:CGFloat=1
    func setScale(_ value:Double) { scale=CGFloat(max(0.7,min(1.5,value)));refreshPanelContent();reposition() }
    private func refreshPanelContent() {
        guard let panel else { return }
        panel.setContentSize(CGSize(width:310*scale,height:bubbleHeight*scale))
        let context=petWindow.map{attachment?() ?? .fallback($0)}
        let view=PetSpeechNativeView(title:title,text:text,reminder:isReminder,actions:actions,palette:context?.palette ?? .companion("bunny"),height:bubbleHeight,onDismiss:{[weak self] in self?.complete()},onSnooze:{[weak self] in self?.onSnooze?()})
        view.frame=CGRect(x:0,y:0,width:310*scale,height:bubbleHeight*scale);view.setBoundsSize(CGSize(width:310,height:bubbleHeight));panel.contentView=view
    }
    func attach(to window:NSWindow) {
        petWindow=window
        moveObserver=NotificationCenter.default.addObserver(forName:NSWindow.didMoveNotification,object:window,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
    }
    @discardableResult func show(title:String,text:String,reminder:Bool=false,actions:[SpeechAction]=[])->Bool {
        guard reminder || !isReminder || panel?.isVisible != true else { return false }
        dismissTimer?.invalidate();dismissTimer=nil
        self.title=String(title.prefix(120));self.text=String(text.prefix(1000));isReminder=reminder;self.actions=Array(actions.prefix(3))
        bubbleHeight=reminder || !self.actions.isEmpty ? 208:170
        if panel == nil {
            let p=PawPopupPanel(contentRect:CGRect(x:0,y:0,width:310,height:bubbleHeight),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="PawSync Thought Bubble";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.becomesKeyOnlyIfNeeded=true;p.ignoresMouseEvents=false;p.worksWhenModal=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            p.level=NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1);panel=p
        }
        refreshPanelContent();reposition();panel?.orderFrontRegardless();onVisibility?(true)
        let timer=Timer(timeInterval:reminder ? 12:8,repeats:false) { [weak self] _ in MainActor.assumeIsolated { guard let self else { return };if self.isReminder { self.onAutoDismiss?() };self.dismiss() } }
        RunLoop.main.add(timer,forMode:.common);dismissTimer=timer;return true
    }
    private func complete() { if isReminder { onDone?() } else { dismiss() } }
    func reposition() {
        guard let panel,let petWindow else { return }
        let context=attachment?() ?? .fallback(petWindow)
        // Three thought dots descend toward the companion's head, rather than
        // centering a floating card above the whole transparent window.
        panel.setFrame(context.clamp(CGRect(x:context.pet.midX-284*scale,y:context.pet.maxY-10,width:panel.frame.width,height:panel.frame.height)),display:true)
    }
    func dismiss() { dismissTimer?.invalidate();dismissTimer=nil;panel?.orderOut(nil);isReminder=false;onVisibility?(false) }
    func stop() { dismiss();if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) };moveObserver=nil;panel?.contentView=nil;panel=nil }
}

@MainActor final class PetSpeechNativeView:NSView {
    let palette:PetChromePalette
    let onDismiss:()->Void
    private var bubblePath:NSBezierPath { PetChromeDrawing.cloud(in:bounds) }
    init(title:String,text:String,reminder:Bool,actions:[SpeechAction],palette:PetChromePalette,height:CGFloat,onDismiss:@escaping ()->Void,onSnooze:@escaping ()->Void) {
        self.palette=palette;self.onDismiss=onDismiss;super.init(frame:CGRect(x:0,y:0,width:310,height:height))
        let heading=PetSpeechLabel(labelWithString:title);heading.font = .systemFont(ofSize:13,weight:.semibold);heading.textColor=palette.ink;heading.lineBreakMode = .byTruncatingTail;heading.frame=CGRect(x:39,y:35,width:220,height:19);addSubview(heading)
        let message=PetSpeechLabel(wrappingLabelWithString:text);message.font = .systemFont(ofSize:12,weight:.medium);message.textColor=palette.ink;message.maximumNumberOfLines=3;message.lineBreakMode = .byWordWrapping;message.frame=CGRect(x:39,y:62,width:230,height:53);message.isSelectable=false;addSubview(message)
        let close=PetSoftButton(title:"",symbol:"xmark",action:onDismiss);close.palette=palette;close.setAccessibilityLabel("Dismiss thought bubble");close.frame=CGRect(x:265,y:32,width:23,height:23);addSubview(close)
        let buttons: [(String,()->Void)] = !actions.isEmpty ? actions.map{($0.title,$0.action)} : reminder ? [(title.localizedCaseInsensitiveContains("water") ? "I had a sip!":"All done",onDismiss),("Snooze 10 min",onSnooze)]:[]
        var x:CGFloat=39
        for (title,action) in buttons {
            let width=min(110,max(65,CGFloat(title.count)*5.8+20))
            let button=PetSoftButton(title:title,action:action);button.palette=palette;button.frame=CGRect(x:x,y:height-89,width:width,height:27);addSubview(button);x+=width+7
        }
        if reminder {
            let menu=NSMenu();let snooze=NSMenuItem(title:"Snooze 10 min",action:#selector(snoozeMenu),keyEquivalent:"");snooze.target=self;menu.addItem(snooze);self.menu=menu;self.snoozeAction=onSnooze
        }
        setAccessibilityLabel(reminder ? "Pet reminder":"Pet thought bubble")
    }
    private var snoozeAction:(()->Void)?
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        PetChromeDrawing.paint(bubblePath,fill:palette.fur,ink:palette.ink,width:1.6)
        for (x,y,r) in [(CGFloat(254),bounds.height-27,CGFloat(7)),(CGFloat(273),bounds.height-13,CGFloat(4.5)),(CGFloat(286),bounds.height-4,CGFloat(2.5))] {
            PetChromeDrawing.paint(NSBezierPath(ovalIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),fill:palette.fur,ink:palette.ink,width:1.2)
        }
        // A little blush sits in a lobe of the cloud, keeping the text itself clean.
        palette.blush.withAlphaComponent(0.32).setFill();NSBezierPath(ovalIn:CGRect(x:22,y:58,width:9,height:4)).fill()
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        let local=convert(point,from:superview)
        guard bubblePath.contains(local) else { return nil }
        return super.hitTest(point)
    }
    override func mouseUp(with event:NSEvent) { onDismiss() }
    @objc private func snoozeMenu() { snoozeAction?() }
}

@MainActor private final class PetSpeechLabel:NSTextField {
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}
