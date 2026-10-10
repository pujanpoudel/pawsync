import SpriteKit

/// Shared anatomical anchors, also consumed by the Windows/Linux renderer.
/// Only the pictured limbs move; authored OpenPets locomotion is left intact.
struct PetGait:Decodable {
    struct Limb:Decodable {
        let pivot:[Double],tip:[Double],phase:Double,role:String,stride:Double,lift:Double
    }
    let kind:String,row:Int,column:Int,facing:Double,cycle:Double,bob:Double,limbs:[Limb]
    static let catalog:[String:PetGait] = {
        guard let url=Bundle.main.resourceURL?.appendingPathComponent("Locomotion/gaits.json"),let data=try? Data(contentsOf:url) else { return [:] }
        return (try? JSONDecoder().decode([String:PetGait].self,from:data)) ?? [:]
    }()
    var procedural:Bool { kind != "authored" && kind != "knight" }
    static let columns=24,rows=26
    static let rest=SKWarpGeometryGrid(columns:columns,rows:rows)
    func displacement(x:Double,y:Double,phase:Double)->SIMD2<Float> {
        var dx=0.0,dy=0.0
        for limb in limbs {
            let px=limb.pivot[0],py=limb.pivot[1],tx=limb.tip[0],ty=limb.tip[1]
            let length=max(14,hypot(tx-px,ty-py)),rx=limb.role == "arm" ? 12.0:10.0
            // Confine influence to the actual limb, with a fixed shoulder/hip.
            let progress=max(0,min(1,(y-py)/max(10,ty-py)))
            let centerX=px+(tx-px)*progress
            let weight=exp(-pow((x-centerX)/rx,2)*0.5)*progress*max(0,min(1,(ty+16-y)/16))
            let t=(phase+limb.phase).truncatingRemainder(dividingBy:1)
            // 60% planted stance, 40% forward recovery with toe clearance.
            let swing=t >= 0.6
            let q=swing ? (t-0.6)/0.4:t/0.6
            let stride=swing ? -cos(q * .pi):1-2*q
            var forward=stride*limb.stride*facing
            var lift=swing ? sin(q * .pi)*limb.lift:0
            if limb.role == "arm" { forward=sin((phase+limb.phase)*2 * .pi)*limb.stride;lift=0 }
            if kind == "hop" { forward=sin((phase+limb.phase)*2 * .pi)*limb.stride;lift=max(0,sin((phase+limb.phase)*2 * .pi))*limb.lift }
            if kind == "swim" || kind == "fly" {
                forward=sin((phase+limb.phase)*2 * .pi)*limb.stride
                lift=sin((phase+limb.phase)*2 * .pi)*(kind == "fly" ? 9:3)
            }
            // Rotation at the joint plus toe clearance avoids a rubbery body sway.
            let angle=forward/length
            let vx=x-px,vy=y-py
            dx+=(vx*(cos(angle)-1)+vy*sin(angle))*weight
            dy+=(-vx*sin(angle)+vy*(cos(angle)-1)-lift)*weight
        }
        return SIMD2(Float(dx/192),Float(-dy/208))
    }
    func geometry(phase:Double)->SKWarpGeometryGrid {
        var source:[SIMD2<Float>]=[],target:[SIMD2<Float>]=[]
        for row in 0...Self.rows { for column in 0...Self.columns {
            let p=SIMD2<Float>(Float(column)/Float(Self.columns),Float(row)/Float(Self.rows))
            source.append(p);target.append(p+displacement(x:Double(p.x)*192,y:(1-Double(p.y))*208,phase:phase))
        } }
        return SKWarpGeometryGrid(columns:Self.columns,rows:Self.rows,sourcePositions:source,destinationPositions:target)
    }
    func action(duration:TimeInterval)->SKAction {
        let steps=24
        return SKAction.animate(withWarps:(0...steps).map { geometry(phase:Double($0)/Double(steps)) },times:(0...steps).map { NSNumber(value:Double($0)/Double(steps)*duration) }) ?? .wait(forDuration:duration)
    }
}
