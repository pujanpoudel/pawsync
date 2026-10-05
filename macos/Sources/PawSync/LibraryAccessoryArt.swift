import AppKit
import SpriteKit

/// PawSync's original vector wearables. A common contact baseline lets the
/// fitting system seat each object on the pet, rather than float it above ears.
@MainActor enum LibraryAccessoryArt {
    static func make(_ item:FreeHat)->SKNode {
        let root=SKNode();root.name="cosmetic"
        let ink=NSColor(calibratedRed:0.31,green:0.24,blue:0.22,alpha:1)
        let hex=UInt32(item.color ?? "F6A9B8",radix:16) ?? 0xF6A9B8
        let tint=NSColor(calibratedRed:Double((hex >> 16)&255)/255,green:Double((hex >> 8)&255)/255,blue:Double(hex&255)/255,alpha:1)
        let cream=NSColor(calibratedRed:1,green:0.96,blue:0.86,alpha:1)
        let green=NSColor(calibratedRed:0.55,green:0.70,blue:0.43,alpha:1)
        func shape(_ path:CGPath,_ color:NSColor,width:CGFloat=1.6) {
            let n=SKShapeNode(path:path);n.fillColor=color;n.strokeColor=ink;n.lineWidth=width;n.isAntialiased=true;root.addChild(n)
        }
        func oval(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ c:NSColor) { shape(CGPath(ellipseIn:CGRect(x:x-w/2,y:y-h/2,width:w,height:h),transform:nil),c) }
        func rect(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ c:NSColor,_ r:CGFloat=5) { shape(CGPath(roundedRect:CGRect(x:x-w/2,y:y-h/2,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil),c) }
        func line(_ p:[CGPoint],_ c:NSColor=ink,_ w:CGFloat=1.7) {
            let path=CGMutablePath();path.move(to:p[0]);p.dropFirst().forEach{path.addLine(to:$0)}
            let n=SKShapeNode(path:path);n.strokeColor=c;n.lineWidth=w;n.lineCap = .round;root.addChild(n)
        }
        func face(_ y:CGFloat=18) {
            oval(-6,y,2.6,3.6,ink);oval(6,y,2.6,3.6,ink)
            let path=CGMutablePath();path.move(to:CGPoint(x:-3,y:y-4));path.addQuadCurve(to:CGPoint(x:3,y:y-4),control:CGPoint(x:0,y:y-7))
            let n=SKShapeNode(path:path);n.strokeColor=ink;n.lineWidth=1.2;root.addChild(n)
            oval(-10,y-3,4,2,NSColor.systemPink.withAlphaComponent(0.35));oval(10,y-3,4,2,NSColor.systemPink.withAlphaComponent(0.35))
        }
        switch item.kind ?? "star" {
        case "leaf":
            let p=CGMutablePath();p.move(to:CGPoint(x:-22,y:3));p.addQuadCurve(to:CGPoint(x:21,y:24),control:CGPoint(x:-25,y:34));p.addQuadCurve(to:CGPoint(x:-22,y:3),control:CGPoint(x:23,y:0));shape(p,tint);line([CGPoint(x:-19,y:5),CGPoint(x:17,y:22)])
        case "flower":
            oval(0,3,24,6,green)
            for i in 0..<6 { let a=CGFloat(i) * .pi/3;oval(cos(a)*12,18+sin(a)*12,17,17,tint) };oval(0,18,16,16,cream);face(18)
        case "mushroom":
            rect(0,11,17,22,cream)
            let p=CGMutablePath();p.move(to:CGPoint(x:-25,y:17));p.addCurve(to:CGPoint(x:25,y:17),control1:CGPoint(x:-23,y:49),control2:CGPoint(x:23,y:49));p.closeSubpath();shape(p,tint)
            oval(-12,24,8,6,cream);oval(5,31,9,7,cream);face(11)
        case "fruit","berry":
            oval(-7,18,28,33,tint);oval(7,18,28,33,tint)
            line([CGPoint(x:0,y:31),CGPoint(x:2,y:40)],ink,2.5);oval(9,36,17,7,green)
            if item.kind == "berry" { for x:CGFloat in [-10,0,10] { oval(x,25,2,3,cream) } };face(17)
        case "donut":
            oval(0,22,46,40,NSColor(calibratedRed:0.81,green:0.58,blue:0.36,alpha:1));oval(0,25,44,28,tint);oval(0,26,14,11,cream)
            for x:CGFloat in [-14,-7,8,15] { line([CGPoint(x:x,y:31),CGPoint(x:x+3,y:34)],cream,2) };face(15)
        case "cupcake":
            let p=CGMutablePath();p.move(to:CGPoint(x:-19,y:22));p.addLine(to:CGPoint(x:19,y:22));p.addLine(to:CGPoint(x:14,y:1));p.addLine(to:CGPoint(x:-14,y:1));p.closeSubpath();shape(p,tint)
            oval(0,24,44,18,cream);oval(0,33,28,16,cream);oval(0,40,13,12,tint);face(14)
        case "dumpling": oval(0,17,45,32,tint);for x:CGFloat in [-10,0,10] { line([CGPoint(x:x,y:28),CGPoint(x:x+2,y:33)],cream) };face(17)
        case "toast": rect(0,20,39,39,NSColor(calibratedRed:0.83,green:0.61,blue:0.40,alpha:1),10);rect(0,22,30,27,cream,8);oval(0,25,16,10,tint);face(13)
        case "cup": rect(0,18,34,32,tint,7);oval(20,20,17,19,tint);oval(20,20,9,11,cream);oval(-1,32,34,7,cream);face(18);line([CGPoint(x:-7,y:38),CGPoint(x:-9,y:44),CGPoint(x:-6,y:50)],cream)
        case "bow":
            for sign:CGFloat in [-1,1] { let p=CGMutablePath();p.move(to:CGPoint(x:0,y:14));p.addLine(to:CGPoint(x:sign*24,y:29));p.addQuadCurve(to:CGPoint(x:sign*24,y:1),control:CGPoint(x:sign*32,y:14));p.closeSubpath();shape(p,tint) };oval(0,14,12,18,cream)
        case "beanie": oval(0,19,53,38,tint);rect(0,5,56,12,cream);oval(0,40,12,12,tint);for x:CGFloat in [-14,0,14] { line([CGPoint(x:x,y:15),CGPoint(x:x,y:28)],cream,1) }
        case "beret": oval(-3,17,59,27,tint);rect(0,4,42,8,cream);line([CGPoint(x:-1,y:29),CGPoint(x:3,y:35)],ink,3)
        case "crown":
            let p=CGMutablePath();p.move(to:CGPoint(x:-25,y:2));for q in [CGPoint(x:-28,y:28),CGPoint(x:-12,y:17),CGPoint(x:0,y:34),CGPoint(x:12,y:17),CGPoint(x:28,y:28),CGPoint(x:25,y:2)] { p.addLine(to:q) };p.closeSubpath();shape(p,tint);rect(0,5,52,7,cream);oval(0,16,7,8,cream)
        case "moon": oval(0,22,40,40,tint);oval(9,29,31,31,cream);face(16)
        case "cloud": oval(0,13,48,24,tint);oval(-12,20,23,25,tint);oval(6,25,30,31,tint);face(14)
        case "rainbow":
            for (i,c) in [tint,NSColor(calibratedRed:0.96,green:0.77,blue:0.49,alpha:1),green].enumerated() {
                let p=CGMutablePath();p.addArc(center:CGPoint(x:0,y:8),radius:CGFloat(25-i*6),startAngle:0,endAngle:.pi,clockwise:false)
                let n=SKShapeNode(path:p);n.strokeColor=c;n.lineWidth=6;n.lineCap = .round;root.addChild(n)
            };oval(-24,6,21,13,cream);oval(24,6,21,13,cream)
        case "bird": oval(0,18,34,33,tint);oval(-15,15,13,18,tint);oval(15,15,13,18,tint);oval(0,16,7,5,NSColor.systemOrange);oval(-7,22,3,4,ink);oval(7,22,3,4,ink)
        case "butterfly":for x:CGFloat in [-12,12] { oval(x,23,26,27,tint);oval(x,8,21,19,cream) };rect(0,16,6,30,ink,3);line([CGPoint(x:0,y:30),CGPoint(x:-6,y:37)]);line([CGPoint(x:0,y:30),CGPoint(x:6,y:37)])
        default:
            let p=CGMutablePath();for i in 0..<10 { let a=CGFloat(i) * .pi/5 + .pi/2,r:CGFloat=i.isMultiple(of:2) ? 23:11;let q=CGPoint(x:cos(a)*r,y:sin(a)*r+23);if i==0 {p.move(to:q)} else {p.addLine(to:q)} };p.closeSubpath();shape(p,tint);face(23)
        }
        PetWearableFit.recordBounds(root)
        return root
    }
}

@MainActor enum PetWearableFit {
    static func recordBounds(_ node:SKNode) {
        let b=node.calculateAccumulatedFrame()
        node.userData=["artWidth":Double(b.width),"artBottom":Double(b.minY),"artTop":Double(b.maxY)]
    }
    static func apply(_ node:SKNode,id:String,petID:String,headScale:CGFloat,eyePoint:CGPoint?,eyeDistance:CGFloat?,slot:CGPoint,transform:HatTransform) {
        let kind=FreeHat.all.first{$0.id==id}?.kind ?? (id == "free.bow" ? "bow":id == "free.beanie" ? "beanie":id == "free.crown" ? "crown":id == "accessory.hat" ? "hat":"perch")
        let width=node.userData?["artWidth"] as? Double ?? 65,bottom=node.userData?["artBottom"] as? Double ?? 0
        let headWidth=max(24,70*headScale)
        let cap=["beanie","beret","hat"].contains(kind)
        let ratio:CGFloat=kind == "bow" ? 0.48:cap ? 0.93:kind == "crown" ? 0.72:0.55
        var scale=headWidth*ratio/max(1,CGFloat(width)),offset=CGPoint.zero
        if id == "accessory.glasses",let eyePoint,let eyeDistance {
            scale=max(0.25,eyeDistance/44)
            offset=CGPoint(x:eyePoint.x-slot.x,y:eyePoint.y-slot.y+33*scale*transform.scale)
        } else {
            offset.y = -CGFloat(bottom)*scale*transform.scale-1.5*headScale
            if kind == "bow" { offset.x=headWidth*0.32;offset.y -= headWidth*0.17 }
            if cap { offset.y -= 2*headScale }
            if petID == "bunny",kind == "bow" {offset.y += headWidth*0.45}
        }
        node.position=CGPoint(x:offset.x+transform.x,y:offset.y+transform.y)
        node.setScale(scale*transform.scale);node.zRotation=transform.rotation * .pi/180
    }
}

@MainActor enum WearablePreview {
    private static let images=NSCache<NSString,NSImage>()
    static func image(_ id:String)->NSImage {
        if let image=images.object(forKey:id as NSString) { return image }
        let node=PetAccessories.make(id)
        let shapes=node?.children.compactMap{$0 as? SKShapeNode} ?? []
        let frame=node?.calculateAccumulatedFrame() ?? CGRect(x:-35,y:0,width:70,height:50)
        let scale=min(80/max(1,frame.width),58/max(1,frame.height))
        let image=NSImage(size:CGSize(width:96,height:72),flipped:false) { _ in
            guard let c=NSGraphicsContext.current?.cgContext else { return false }
            c.saveGState();c.translateBy(x:48-frame.midX*scale,y:36-frame.midY*scale);c.scaleBy(x:scale,y:scale)
            for s in shapes { guard let p=s.path else {continue};c.saveGState();c.translateBy(x:s.position.x,y:s.position.y);c.rotate(by:s.zRotation);c.addPath(p);c.setFillColor(s.fillColor.cgColor);c.setStrokeColor(s.strokeColor.cgColor);c.setLineWidth(s.lineWidth);c.drawPath(using:s.lineWidth>0 ? .fillStroke:.fill);c.restoreGState() };c.restoreGState();return true
        }
        images.countLimit=64;images.setObject(image,forKey:id as NSString);return image
    }
}
