import CoreGraphics

/// Head landmarks in a 192 × 208 frame. The original pets have deliberately
/// different silhouettes in their walk and jump poses, so headwear follows the
/// authored pose instead of remaining at one fixed point in the sprite cell.
struct PetAccessoryFit {
    var crown:CGPoint
    var scale:CGFloat
    var glassesDrop:CGFloat

    static func frame(id:String,row:Int,column:Int)->Self {
        let bases:[String:(CGFloat,CGFloat,CGFloat,CGFloat)] = [
            // crown y, accessory scale, eye adjustment, walking crown y
            "pixel-cat":(171,1.12,9,151), "shibe":(170,1.16,9,153),
            "fox":(171,1.10,9,154), "bunny":(170,0.96,17,151),
            "bear":(172,1.10,2,164), "panda":(172,1.12,4,164),
            "hamster":(171,1.14,8,151), "otter":(171,1.12,5,153),
            "capybara":(172,1.13,8,153)
        ]
        if let base=bases[id] {
            var point=CGPoint(x:0,y:base.0)
            switch row {
            case 1: point=CGPoint(x:38,y:base.3)
            case 2: point=CGPoint(x:-38,y:base.3)
            case 4:
                point=column == 0 ? CGPoint(x:-31,y:120) :
                    column < 4 ? CGPoint(x:-32,y:143) : CGPoint(x:-28,y:127)
            case 5: point=CGPoint(x:-28,y:125)
            default: break
            }
            return Self(crown:point,scale:base.1,glassesDrop:base.2)
        }
        // The six bundled OpenPets companions have very different head shapes.
        let imported:[String:Self] = [
            "openpets-default":Self(crown:CGPoint(x:-5,y:176),scale:0.98,glassesDrop:12),
            "openpets-snoopy":Self(crown:CGPoint(x:-18,y:170),scale:1.05,glassesDrop:-10),
            "openpets-clippit":Self(crown:CGPoint(x:-22,y:150),scale:0.70,glassesDrop:6),
            "openpets-tux":Self(crown:CGPoint(x:-4,y:177),scale:1.05,glassesDrop:14),
            "openpets-wall-e":Self(crown:CGPoint(x:-4,y:184),scale:0.78,glassesDrop:-8),
            "openpets-dobby":Self(crown:CGPoint(x:0,y:174),scale:1.04,glassesDrop:-12)
        ]
        var fit=imported[id] ?? Self(crown:CGPoint(x:0,y:170),scale:1,glassesDrop:15)
        if row == 4 && id == "openpets-default" { fit.crown.y = column < 4 ? 147 : 163; fit.scale *= 0.72 }
        if row == 4 && id == "openpets-clippit" { fit.crown.y = 129; fit.scale *= 0.75 }
        return fit
    }
}
