import SpriteKit

/// The reference kitten crouches, springs up with its forepaws raised, and
/// softly lands. This finite response never adds motion to a previous click.
enum PetClickMotion {
    static let duration:TimeInterval = 1.4
    static func hops(rest:CGPoint)->SKAction {
        func pose(x:CGFloat,y:CGFloat,scale:CGFloat,angle:CGFloat,time:TimeInterval,mode:SKActionTimingMode)->SKAction {
            let action=SKAction.group([
                .move(to:CGPoint(x:rest.x+x,y:rest.y+y),duration:time),
                .scaleY(to:scale,duration:time),
                .rotate(toAngle:angle,duration:time)
            ])
            action.timingMode=mode;return action
        }
        var actions:[SKAction]=[]
        for side in [CGFloat(-1),CGFloat(1)] {
            actions += [
                pose(x:0,y:0,scale:0.91,angle:0,time:0.14,mode:.easeInEaseOut),
                pose(x:side*2,y:22,scale:1.05,angle:side*0.035,time:0.18,mode:.easeOut),
                pose(x:side,y:0,scale:0.96,angle:0,time:0.20,mode:.easeIn),
                pose(x:0,y:0,scale:1,angle:0,time:0.09,mode:.easeOut)
            ]
        }
        actions.append(pose(x:0,y:0,scale:1,angle:0,time:0.18,mode:.easeInEaseOut))
        return .sequence(actions)
    }
}
