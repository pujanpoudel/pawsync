import AppKit

/// Companion controls use the same fur, outline and blush as their owner.
struct PetChromePalette {
    let fur:NSColor
    let ink:NSColor
    let blush:NSColor
    let cloth:NSColor
    static func companion(_ id:String)->Self {
        let warm=NSColor(calibratedRed:0.39,green:0.27,blue:0.22,alpha:1)
        let rose=NSColor(calibratedRed:0.90,green:0.60,blue:0.59,alpha:1)
        let cream=NSColor(calibratedRed:1,green:0.96,blue:0.87,alpha:1)
        switch id {
        case "fox","shibe": return Self(fur:NSColor(calibratedRed:0.95,green:0.67,blue:0.38,alpha:1),ink:warm,blush:rose,cloth:cream)
        case "bear","otter","capybara": return Self(fur:NSColor(calibratedRed:0.75,green:0.56,blue:0.40,alpha:1),ink:warm,blush:rose,cloth:cream)
        case "panda","openpets-tux","openpets-snoopy": return Self(fur:NSColor(calibratedRed:0.94,green:0.94,blue:0.90,alpha:1),ink:NSColor(calibratedRed:0.29,green:0.30,blue:0.31,alpha:1),blush:rose,cloth:cream)
        case "openpets-wall-e": return Self(fur:NSColor(calibratedRed:0.93,green:0.77,blue:0.39,alpha:1),ink:warm,blush:rose,cloth:cream)
        default: return Self(fur:cream,ink:warm,blush:rose,cloth:NSColor(calibratedRed:0.97,green:0.80,blue:0.70,alpha:1))
        }
    }
}

struct PetChromeAnchor {
    var pet:CGRect
    var visible:CGRect
    var palette:PetChromePalette
    var name:String
    static var unattached:Self { Self(pet:.zero,visible:.zero,palette:.companion("bunny"),name:"Buddy") }
    static func fallback(_ window:NSWindow)->Self {
        let f=window.frame
        return Self(pet:CGRect(x:f.midX-f.width*0.27,y:f.minY+f.height*0.12,width:f.width*0.54,height:f.height*0.74),visible:window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? f,palette:.companion("bunny"),name:"Buddy")
    }
    func clamp(_ frame:CGRect)->CGRect {
        CGRect(x:max(visible.minX+5,min(visible.maxX-frame.width-5,frame.minX)),y:max(visible.minY+5,min(visible.maxY-frame.height-5,frame.minY)),width:frame.width,height:frame.height)
    }
}

@MainActor enum PetChromeDrawing {
    static func paint(_ path:NSBezierPath,fill:NSColor,ink:NSColor,width:CGFloat=1.5) {
        fill.setFill();path.fill();ink.setStroke();path.lineWidth=width;path.lineJoinStyle = .round;path.stroke()
    }
    static func label(_ text:String,in rect:CGRect,size:CGFloat=11,color:NSColor,weight:NSFont.Weight = .medium,alignment:NSTextAlignment = .center) {
        let p=NSMutableParagraphStyle();p.alignment=alignment;p.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:p])
    }
    static func paw(in rect:CGRect,palette:PetChromePalette,pressed:Bool=false) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x:rect.minX,y:rect.minY)
        NSGraphicsContext.current?.cgContext.scaleBy(x:rect.width/50,y:rect.height/50)
        let toes:[CGRect]=[CGRect(x:1,y:13,width:10,height:15),CGRect(x:11,y:3,width:12,height:17),CGRect(x:26,y:1,width:12,height:17),CGRect(x:39,y:11,width:10,height:16)]
        for toe in toes { paint(NSBezierPath(ovalIn:toe),fill:palette.fur,ink:palette.ink,width:1.4) }
        let pad=NSBezierPath()
        pad.move(to:CGPoint(x:25,y:17));pad.curve(to:CGPoint(x:45,y:36),controlPoint1:CGPoint(x:35,y:16),controlPoint2:CGPoint(x:47,y:28))
        pad.curve(to:CGPoint(x:27,y:47),controlPoint1:CGPoint(x:44,y:49),controlPoint2:CGPoint(x:35,y:49))
        pad.curve(to:CGPoint(x:7,y:43),controlPoint1:CGPoint(x:18,y:51),controlPoint2:CGPoint(x:7,y:50))
        pad.curve(to:CGPoint(x:25,y:17),controlPoint1:CGPoint(x:-1,y:33),controlPoint2:CGPoint(x:15,y:16));pad.close()
        paint(pad,fill:pressed ? palette.blush : palette.fur,ink:palette.ink,width:1.5)
        let bean=NSBezierPath(ovalIn:CGRect(x:15,y:27,width:20,height:14));palette.blush.withAlphaComponent(pressed ? 0.45 : 0.28).setFill();bean.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    static func mitten(in rect:CGRect,palette:PetChromePalette) {
        let path=NSBezierPath(roundedRect:rect,xRadius:rect.width*0.44,yRadius:rect.height*0.44)
        paint(path,fill:palette.fur,ink:palette.ink,width:1.4)
        let crease=NSBezierPath()
        for x in [rect.midX-3,rect.midX+3] { crease.move(to:CGPoint(x:x,y:rect.maxY-5));crease.line(to:CGPoint(x:x,y:rect.maxY-1)) }
        palette.ink.withAlphaComponent(0.5).setStroke();crease.lineWidth=1;crease.stroke()
    }
    static func pocket(in rect:CGRect,palette:PetChromePalette,count:Int=0) {
        // Local coordinates are flipped: open rim at the top, soft rounded base.
        let p=NSBezierPath()
        p.move(to:CGPoint(x:rect.minX+7,y:rect.minY+8))
        p.curve(to:CGPoint(x:rect.maxX-7,y:rect.minY+8),controlPoint1:CGPoint(x:rect.midX-12,y:rect.minY-2),controlPoint2:CGPoint(x:rect.midX+12,y:rect.minY-2))
        p.curve(to:CGPoint(x:rect.maxX-4,y:rect.maxY-14),controlPoint1:CGPoint(x:rect.maxX+1,y:rect.minY+30),controlPoint2:CGPoint(x:rect.maxX+3,y:rect.maxY-29))
        p.curve(to:CGPoint(x:rect.minX+4,y:rect.maxY-14),controlPoint1:CGPoint(x:rect.maxX-11,y:rect.maxY+10),controlPoint2:CGPoint(x:rect.minX+11,y:rect.maxY+10))
        p.curve(to:CGPoint(x:rect.minX+7,y:rect.minY+8),controlPoint1:CGPoint(x:rect.minX-3,y:rect.maxY-30),controlPoint2:CGPoint(x:rect.minX-1,y:rect.minY+30));p.close()
        paint(p,fill:palette.cloth,ink:palette.ink,width:1.8)
        let seam=NSBezierPath(roundedRect:rect.insetBy(dx:12,dy:14),xRadius:24,yRadius:24)
        seam.setLineDash([2,4],count:2,phase:0);seam.lineWidth=1;palette.ink.withAlphaComponent(0.27).setStroke();seam.stroke()
        let rim=NSBezierPath();rim.move(to:CGPoint(x:rect.minX+11,y:rect.minY+15));rim.curve(to:CGPoint(x:rect.maxX-11,y:rect.minY+15),controlPoint1:CGPoint(x:rect.midX-20,y:rect.minY+5),controlPoint2:CGPoint(x:rect.midX+20,y:rect.minY+5));rim.lineWidth=3;palette.ink.withAlphaComponent(0.24).setStroke();rim.stroke()
        if count > 0 { label("\(count)",in:CGRect(x:rect.midX-11,y:rect.maxY-20,width:22,height:12),size:8,color:palette.ink,weight:.semibold) }
    }
    static func heldPocket(size:CGSize,palette:PetChromePalette,count:Int)->NSImage {
        let image=NSImage(size:size,flipped:true) { rect in
            let paper=NSBezierPath(roundedRect:CGRect(x:11,y:2,width:20,height:25),xRadius:2,yRadius:2)
            paint(paper,fill:.white,ink:palette.ink,width:1.1)
            palette.blush.setStroke();let lines=NSBezierPath();for y in [7,11,15] { lines.move(to:CGPoint(x:15,y:y));lines.line(to:CGPoint(x:26,y:y)) };lines.lineWidth=1;lines.stroke()
            pocket(in:CGRect(x:4,y:13,width:36,height:27),palette:palette,count:count)
            mitten(in:CGRect(x:0,y:12,width:12,height:12),palette:palette)
            mitten(in:CGRect(x:32,y:12,width:12,height:12),palette:palette)
            return true
        }
        return image
    }
    static func cloud(in rect:CGRect)->NSBezierPath {
        let w=rect.width,h=rect.height-36
        let p=NSBezierPath();p.move(to:CGPoint(x:37,y:33))
        p.curve(to:CGPoint(x:91,y:18),controlPoint1:CGPoint(x:38,y:8),controlPoint2:CGPoint(x:76,y:6))
        p.curve(to:CGPoint(x:156,y:15),controlPoint1:CGPoint(x:108,y:0),controlPoint2:CGPoint(x:141,y:3))
        p.curve(to:CGPoint(x:w-42,y:27),controlPoint1:CGPoint(x:w-100,y:0),controlPoint2:CGPoint(x:w-45,y:5))
        p.curve(to:CGPoint(x:w-20,y:76),controlPoint1:CGPoint(x:w-4,y:28),controlPoint2:CGPoint(x:w+2,y:61))
        p.curve(to:CGPoint(x:w-36,y:h-18),controlPoint1:CGPoint(x:w+1,y:h-7),controlPoint2:CGPoint(x:w-11,y:h+2))
        p.curve(to:CGPoint(x:w-100,y:h-5),controlPoint1:CGPoint(x:w-47,y:h+11),controlPoint2:CGPoint(x:w-78,y:h+11))
        p.curve(to:CGPoint(x:98,y:h-3),controlPoint1:CGPoint(x:w-119,y:h+10),controlPoint2:CGPoint(x:117,y:h+10))
        p.curve(to:CGPoint(x:38,y:h-23),controlPoint1:CGPoint(x:64,y:h+10),controlPoint2:CGPoint(x:35,y:h+1))
        p.curve(to:CGPoint(x:23,y:79),controlPoint1:CGPoint(x:2,y:h-16),controlPoint2:CGPoint(x:1,y:97))
        p.curve(to:CGPoint(x:37,y:33),controlPoint1:CGPoint(x:0,y:55),controlPoint2:CGPoint(x:9,y:29));p.close();return p
    }
}

@MainActor class PetSoftButton:NSButton {
    var palette:PetChromePalette = .companion("bunny") { didSet { needsDisplay=true } }
    var hovered=false
    var didActivate:(()->Void)?
    private var tracking:NSTrackingArea?
    init(title:String,symbol:String?=nil,action:@escaping ()->Void) {
        super.init(frame:.zero);self.title=title;didActivate=action;isBordered=false;setButtonType(.momentaryChange)
        if let symbol { image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil) }
        target=self;self.action=#selector(pressed);setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    override var isFlipped:Bool { true }
    override var needsPanelToBecomeKey:Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas();if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil);if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event:NSEvent) { hovered=true;needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false;needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:bounds.height*0.5,yRadius:bounds.height*0.5)
        PetChromeDrawing.paint(path,fill:isHighlighted || hovered ? palette.blush.withAlphaComponent(0.35) : palette.fur,ink:palette.ink.withAlphaComponent(0.55),width:1)
        if title.isEmpty,let image { image.withSymbolConfiguration(.init(pointSize:11,weight:.semibold))?.draw(in:bounds.insetBy(dx:7,dy:7)) }
        else { PetChromeDrawing.label(title,in:CGRect(x:5,y:(bounds.height-14)/2,width:bounds.width-10,height:16),size:10,color:palette.ink,weight:.semibold) }
    }
    @objc private func pressed() { didActivate?() }
}
