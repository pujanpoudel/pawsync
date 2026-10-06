import AppKit
import SpriteKit

enum PetEmotion:String,CaseIterable,Identifiable {
    case happy,curious,surprised,affectionate,shy,sad,sleepy,excited,proud,focused,playful,delighted,cozy,grumpy
    var id:String { rawValue }
    var title:String { rawValue.capitalized }
}

struct PetExpressionProfile:Decodable {
    struct Eye:Decodable { let point:[Double];let radius:Double;let fur:[Double] }
    let eyes:[Eye]
    let crown:[Double]
    let accessoryScale:Double
    let pawCenters:[[Double]]
    let fullBody:Bool?
    let footCenters:[[Double]]?
    enum CodingKeys:String,CodingKey { case eyes,crown;case accessoryScale="accessory_scale",pawCenters="paw_centers",fullBody="full_body",footCenters="foot_centers" }
    static func load(_ directory:URL)->Self? {
        let url=directory.appendingPathComponent("interaction.json")
        guard let data=try? Data(contentsOf:url),data.count<16_384,let value=try? JSONDecoder().decode(Self.self,from:data),
              value.eyes.count == 2,value.crown.count == 2,value.pawCenters.count == 2,
              (0.3...2).contains(value.accessoryScale),
              (value.pawCenters+[value.crown]+value.eyes.map(\.point)).allSatisfy({$0.count == 2 && $0.allSatisfy{$0.isFinite && (0...1).contains($0)}}),
              value.footCenters.map({$0.count == 2 && $0.allSatisfy{$0.count == 2 && $0.allSatisfy{$0.isFinite && (0...1).contains($0)}}}) ?? true,
              value.eyes.allSatisfy({(1...16).contains($0.radius) && $0.fur.count == 3 && $0.fur.allSatisfy{$0.isFinite && (0...1).contains($0)}}) else { return nil }
        return value
    }
}

/// Facial expressions cover only the measured eye pixels with sampled fur,
/// then draw expressive lids/pupils. Effects never substitute an emoji for a face.
@MainActor final class PetExpressionNode:SKNode {
    private(set) var emotion:PetEmotion?
    private var profile:PetExpressionProfile?
    private let palette:PetChromePalette
    init(profile:PetExpressionProfile?,id:String) {
        self.profile=profile;palette = .companion(id);super.init();zPosition=16
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    func useProfile(_ value:PetExpressionProfile?,preserveEmotion:Bool=false) {
        let previous=preserveEmotion ? emotion:nil;clear();profile=value
        if let previous { show(previous) }
    }
    func clear() { removeAllActions();removeAllChildren();emotion=nil;alpha=1 }
    func show(_ value:PetEmotion) {
        guard emotion != value else { return };clear();emotion=value
        if let profile {
            for (index,eye) in profile.eyes.enumerated() {
                let group=SKNode();group.position=CGPoint(x:(eye.point[0]-0.5)*192,y:(1-eye.point[1])*208);addChild(group)
                let r=CGFloat(eye.radius)
                let fur=NSColor(calibratedRed:eye.fur[0],green:eye.fur[1],blue:eye.fur[2],alpha:1)
                if value != .focused && value != .surprised {
                    let cover=SKShapeNode(ellipseOf:CGSize(width:r*2.75,height:r*2.8));cover.fillColor=fur;cover.strokeColor = .clear;group.addChild(cover)
                }
                func line(_ from:CGPoint,_ to:CGPoint,_ control:CGPoint,width:CGFloat=1.7) {
                    let p=CGMutablePath();p.move(to:from);p.addQuadCurve(to:to,control:control)
                    let node=SKShapeNode(path:p);node.strokeColor=palette.ink;node.lineWidth=width;node.lineCap = .round;group.addChild(node)
                }
                switch value {
                case .happy,.proud,.excited,.affectionate,.delighted:
                    line(CGPoint(x:-r,y:-1),CGPoint(x:r,y:-1),CGPoint(x:0,y:r*1.3))
                case .sleepy,.shy,.cozy:
                    line(CGPoint(x:-r,y:0),CGPoint(x:r,y:0),CGPoint(x:0,y:-r*0.75))
                case .surprised:
                    // Preserve the illustrated eyes exactly. A light brow lift
                    // reads as surprise without replacing irises or adding sclera.
                    line(CGPoint(x:-r*0.7,y:r*1.9),CGPoint(x:r*0.7,y:r*1.9),CGPoint(x:0,y:r*2.3),width:1.1)
                case .curious:
                    let pupil=SKShapeNode(ellipseOf:CGSize(width:r*1.8,height:r*2));pupil.fillColor=palette.ink;pupil.strokeColor = .clear;group.addChild(pupil)
                    line(CGPoint(x:-r,y:r*1.8),CGPoint(x:r,y:r*1.8),CGPoint(x:0,y:r*2.5),width:1.2)
                case .playful:
                    line(CGPoint(x:-r,y:-1),CGPoint(x:r,y:-1),CGPoint(x:0,y:r*1.3))
                case .grumpy:
                    line(CGPoint(x:-r,y:index == 0 ? r*0.35:-r*0.35),CGPoint(x:r,y:index == 0 ? -r*0.35:r*0.35),CGPoint(x:0,y:0))
                case .sad:
                    line(CGPoint(x:-r,y:0),CGPoint(x:r,y:0),CGPoint(x:0,y:r*0.7))
                    let tear=SKShapeNode(ellipseOf:CGSize(width:3,height:5));tear.position=CGPoint(x:index == 0 ? -r:r,y:-r*1.4);tear.fillColor=NSColor(calibratedRed:0.49,green:0.75,blue:0.85,alpha:1);tear.strokeColor = .clear;group.addChild(tear)
                case .focused:
                    line(CGPoint(x:-r,y:r*1.5),CGPoint(x:r,y:r*1.2),CGPoint(x:0,y:r*1.5),width:1.2)
                }
                if [.happy,.affectionate,.shy,.proud,.playful,.delighted,.cozy].contains(value) {
                    let blush=SKShapeNode(ellipseOf:CGSize(width:r*2,height:r*0.8));blush.position=CGPoint(x:index == 0 ? -r*0.4:r*0.4,y:-r*2.2);blush.fillColor=palette.blush.withAlphaComponent(0.7);blush.strokeColor = .clear;group.addChild(blush)
                }
            }
        }
        // Imported pets without measured faces keep their own authored facial art.
        // A few tiny, hand-drawn accents still make affection/celebration legible.
        if [.affectionate,.excited,.proud,.delighted].contains(value) {
            for (index,x) in [CGFloat(-62),CGFloat(62)].enumerated() {
                let p=CGMutablePath()
                if value == .affectionate {
                    p.move(to:.zero);p.addCurve(to:CGPoint(x:-7,y:7),control1:CGPoint(x:-3,y:4),control2:CGPoint(x:-11,y:6));p.addCurve(to:CGPoint(x:0,y:9),control1:CGPoint(x:-7,y:15),control2:CGPoint(x:-1,y:15));p.addCurve(to:CGPoint(x:7,y:7),control1:CGPoint(x:1,y:15),control2:CGPoint(x:11,y:15));p.addLine(to:.zero)
                } else {
                    p.move(to:CGPoint(x:0,y:12));p.addLine(to:CGPoint(x:3,y:7));p.addLine(to:CGPoint(x:8,y:5));p.addLine(to:CGPoint(x:3,y:3));p.addLine(to:.zero);p.addLine(to:CGPoint(x:-3,y:3));p.addLine(to:CGPoint(x:-8,y:5));p.addLine(to:CGPoint(x:-3,y:7));p.closeSubpath()
                }
                let accent=SKShapeNode(path:p);accent.fillColor=value == .affectionate ? palette.blush:.systemYellow;accent.strokeColor=palette.ink;accent.lineWidth=1
                accent.position=CGPoint(x:x,y:144+CGFloat(index)*8);addChild(accent)
            }
        }
    }
}
