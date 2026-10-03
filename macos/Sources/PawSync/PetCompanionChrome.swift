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
        let animal=id.replacingOccurrences(of:"pawpaw-season2-",with:"").replacingOccurrences(of:"pawpaw-",with:"")
        func soft(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->Self {
            let fur=NSColor(calibratedRed:r,green:g,blue:b,alpha:1)
            return Self(fur:fur,ink:warm,blush:rose,cloth:fur.blended(withFraction:0.76,of:cream) ?? cream)
        }
        switch animal {
        case "fox","shibe","shiba","corgi","squirrel","pixel-cat": return soft(0.95,0.67,0.38)
        case "hamster": return soft(0.99,0.78,0.48)
        case "frog","chameleon": return soft(0.68,0.78,0.53)
        case "dolphin","beluga","manatee","seal": return soft(0.64,0.75,0.77)
        case "pig","axolotl": return soft(0.99,0.75,0.70)
        case "koala","wolf","raccoon","opossum","skunk","penguin","openpets-clippit": return soft(0.72,0.72,0.72)
        case "bat","shetland-sheepdog": return soft(0.66,0.56,0.49)
        case "bear","otter","capybara","tanuki","sloth","hedgehog","armadillo","platypus": return soft(0.75,0.56,0.40)
        case "panda","giant-panda","sheep","openpets-tux","openpets-snoopy": return Self(fur:NSColor(calibratedRed:0.94,green:0.94,blue:0.90,alpha:1),ink:NSColor(calibratedRed:0.29,green:0.30,blue:0.31,alpha:1),blush:rose,cloth:cream)
        case "openpets-default": return soft(0.78,0.69,0.91)
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
    static func heldNote(size:CGSize,palette:PetChromePalette,count:Int)->NSImage {
        let image=NSImage(size:size,flipped:true) { rect in
            let paper=NSBezierPath();paper.move(to:CGPoint(x:8,y:5));paper.line(to:CGPoint(x:19,y:5));paper.line(to:CGPoint(x:25,y:11));paper.line(to:CGPoint(x:25,y:28));paper.line(to:CGPoint(x:8,y:28));paper.close()
            paint(paper,fill:palette.cloth,ink:palette.ink.withAlphaComponent(0.8),width:0.85)
            let fold=NSBezierPath();fold.move(to:CGPoint(x:19,y:5));fold.line(to:CGPoint(x:19,y:11));fold.line(to:CGPoint(x:25,y:11));paint(fold,fill:palette.fur,ink:palette.ink.withAlphaComponent(0.6),width:0.7)
            let seal=NSBezierPath();seal.move(to:CGPoint(x:16,y:23));seal.curve(to:CGPoint(x:12,y:17),controlPoint1:CGPoint(x:10,y:20),controlPoint2:CGPoint(x:10,y:16));seal.curve(to:CGPoint(x:16,y:18),controlPoint1:CGPoint(x:13,y:15),controlPoint2:CGPoint(x:15,y:16));seal.curve(to:CGPoint(x:20,y:17),controlPoint1:CGPoint(x:17,y:16),controlPoint2:CGPoint(x:19,y:15));seal.curve(to:CGPoint(x:16,y:23),controlPoint1:CGPoint(x:22,y:18),controlPoint2:CGPoint(x:19,y:21));seal.close();palette.blush.setFill();seal.fill()
            if count>1 {
                let badge=NSBezierPath(roundedRect:CGRect(x:20,y:0,width:13,height:12),xRadius:5,yRadius:5)
                paint(badge,fill:palette.ink,ink:palette.cloth,width:0.7)
                label(count>99 ? "+":"\(count)",in:CGRect(x:20,y:1,width:13,height:10),size:7,color:palette.cloth,weight:.semibold)
            }
            return true
        }
        return image
    }
    static func cloud(in rect:CGRect)->NSBezierPath {
        let w=rect.width,h=rect.height-36
        let p=NSBezierPath();p.move(to:CGPoint(x:46,y:25))
        p.curve(to:CGPoint(x:113,y:16),controlPoint1:CGPoint(x:57,y:8),controlPoint2:CGPoint(x:96,y:6))
        p.curve(to:CGPoint(x:193,y:16),controlPoint1:CGPoint(x:132,y:2),controlPoint2:CGPoint(x:174,y:2))
        p.curve(to:CGPoint(x:w-43,y:27),controlPoint1:CGPoint(x:w-92,y:4),controlPoint2:CGPoint(x:w-51,y:10))
        p.curve(to:CGPoint(x:w-17,y:79),controlPoint1:CGPoint(x:w-10,y:30),controlPoint2:CGPoint(x:w-6,y:58))
        p.curve(to:CGPoint(x:w-39,y:h-16),controlPoint1:CGPoint(x:w+2,y:h-42),controlPoint2:CGPoint(x:w-11,y:h-12))
        p.curve(to:CGPoint(x:w-102,y:h-4),controlPoint1:CGPoint(x:w-52,y:h+2),controlPoint2:CGPoint(x:w-86,y:h+6))
        p.curve(to:CGPoint(x:105,y:h-4),controlPoint1:CGPoint(x:w-129,y:h+9),controlPoint2:CGPoint(x:129,y:h+9))
        p.curve(to:CGPoint(x:39,y:h-18),controlPoint1:CGPoint(x:85,y:h+6),controlPoint2:CGPoint(x:51,y:h+1))
        p.curve(to:CGPoint(x:18,y:78),controlPoint1:CGPoint(x:10,y:h-12),controlPoint2:CGPoint(x:5,y:h-45))
        p.curve(to:CGPoint(x:46,y:25),controlPoint1:CGPoint(x:3,y:55),controlPoint2:CGPoint(x:14,y:30));p.close();return p
    }
}

@MainActor class PetSoftButton:NSButton {
    enum Emphasis { case standard,primary,secondary }
    var emphasis:Emphasis = .standard { didSet { needsDisplay=true } }
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
        let active=isHighlighted || hovered
        let fill:NSColor=emphasis == .primary ? palette.ink : emphasis == .secondary ? palette.cloth : palette.fur
        let foreground=emphasis == .primary ? palette.cloth:palette.ink
        let background=active ? fill.blended(withFraction:emphasis == .primary ? 0.12:0.30,of:palette.blush) ?? fill:fill
        PetChromeDrawing.paint(path,fill:background,ink:emphasis == .standard ? palette.ink.withAlphaComponent(0.55):palette.ink,width:emphasis == .standard ? 1:1.2)
        if title.isEmpty,let image {
            image.withSymbolConfiguration(.init(pointSize:11,weight:.semibold))?.withSymbolConfiguration(.init(paletteColors:[foreground]))?.draw(in:bounds.insetBy(dx:7,dy:7))
        } else { PetChromeDrawing.label(title,in:CGRect(x:5,y:(bounds.height-14)/2,width:bounds.width-10,height:16),size:10,color:foreground,weight:.semibold) }
    }
    @objc private func pressed() { didActivate?() }
}
