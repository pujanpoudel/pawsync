import SpriteKit

/// Interpolate actual illustrated limbs rather than swapping between poses
/// whose face/armor silhouettes differ. The face and upper ears stay fixed.
enum KnightCatMotion {
    enum Gesture { case breathe,walk,tapLeft,tapRight,wave,stretch,affection,dance }
    static let columns=16,rows=24
    static let rest=SKWarpGeometryGrid(columns:columns,rows:rows)
    static func geometry(_ gesture:Gesture,phase:Double,profile:PetExpressionProfile)->SKWarpGeometryGrid {
        var source:[SIMD2<Float>]=[],target:[SIMD2<Float>]=[]
        let t=Float(phase),s=sin(t*2 * .pi),pulse=sin(t * .pi)
        let paws=profile.pawCenters,feet=profile.footCenters ?? [[0.41,0.1],[0.60,0.1]]
        func weight(_ x:Float,_ y:Float,_ point:[Double],_ rx:Float,_ ry:Float)->Float {
            let dx=(x-Float(point[0]))/rx,dy=(y-Float(point[1]))/ry
            return exp(-(dx*dx+dy*dy)*0.5) * max(0,min(1,(0.53-y)*12))
        }
        for row in 0...rows { for column in 0...columns {
            let x=Float(column)/Float(columns),y=Float(row)/Float(rows)
            let p=SIMD2<Float>(x,y);source.append(p);var delta=SIMD2<Float>.zero
            let left=weight(x,y,paws[0],0.085,0.10),right=weight(x,y,paws[1],0.085,0.10)
            let bootL=weight(x,y,feet[0],0.07,0.07),bootR=weight(x,y,feet[1],0.07,0.07)
            let cape=weight(x,y,[0.82,0.27],0.14,0.17)
            switch gesture {
            case .walk:
                delta.x += (bootL-bootR)*s*0.032 + (right-left)*s*0.018
                delta.y += (bootL*max(0,s)+bootR*max(0,-s))*0.032
                delta.x += cape*s*0.017
            case .tapLeft,.tapRight:
                let hand=gesture == .tapLeft ? left:right
                delta.y += hand*pulse*0.032;delta.x += hand*pulse*(gesture == .tapLeft ? -0.010:0.010)
                delta.x += cape*pulse*0.004
            case .wave:
                delta.y += right*pulse*0.065;delta.x += right*pulse*0.020 + right*s*0.012
            case .stretch,.affection:
                delta.y += (left+right)*pulse*0.058
                delta.x += (right-left)*pulse*0.026 + cape*s*0.012
            case .dance:
                delta.y += (left+right)*abs(s)*0.037 + (bootL*max(0,s)+bootR*max(0,-s))*0.015
                delta.x += (right-left)*s*0.020 + cape*s*0.018
            case .breathe:
                delta.x += cape*pulse*0.008;delta.y += (left+right)*pulse*0.004
            }
            target.append(p+delta)
        } }
        return SKWarpGeometryGrid(columns:columns,rows:rows,sourcePositions:source,destinationPositions:target)
    }
    static func action(_ gesture:Gesture,duration:TimeInterval,profile:PetExpressionProfile)->SKAction {
        let steps=16
        let warps=(0...steps).map { geometry(gesture,phase:Double($0)/Double(steps),profile:profile) as SKWarpGeometry }
        let times=(0...steps).map { NSNumber(value:Double($0)/Double(steps)*duration) }
        return SKAction.animate(withWarps:warps,times:times) ?? .wait(forDuration:duration)
    }
    /// Inverse map the animated mesh so a lifted paw remains clickable and
    /// the transparent pixels beside it still pass through to other apps.
    static func sourcePoint(_ point:SIMD2<Float>,in grid:SKWarpGeometryGrid)->SIMD2<Float>? {
        func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float { a.x*b.y-a.y*b.x }
        func triangle(_ ia:Int,_ ib:Int,_ ic:Int)->SIMD2<Float>? {
            let a=grid.destPosition(at:ia),b=grid.destPosition(at:ib),c=grid.destPosition(at:ic)
            let denominator=cross(b-a,c-a)
            guard abs(denominator)>0.000001 else { return nil }
            let u=cross(point-a,c-a)/denominator,v=cross(b-a,point-a)/denominator
            guard u >= -0.0001,v >= -0.0001,u+v <= 1.0001 else { return nil }
            let sa=grid.sourcePosition(at:ia)
            return sa+(grid.sourcePosition(at:ib)-sa)*u+(grid.sourcePosition(at:ic)-sa)*v
        }
        let cx=max(0,min(columns-1,Int(point.x*Float(columns)))),cy=max(0,min(rows-1,Int(point.y*Float(rows))))
        for row in max(0,cy-3)...min(rows-1,cy+3) { for column in max(0,cx-3)...min(columns-1,cx+3) {
            let a=row*(columns+1)+column,b=a+1,c=a+columns+1,d=c+1
            if let p=triangle(a,b,d) ?? triangle(a,d,c) { return p }
        } }
        return nil
    }
}
