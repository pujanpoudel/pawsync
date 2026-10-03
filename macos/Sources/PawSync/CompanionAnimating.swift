import AppKit
import SpriteKit

@MainActor final class PawPopupPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}

@MainActor protocol CompanionAnimating: AnyObject {
    var sleeping: Bool { get }
    var onNeedsRender:(()->Void)? { get set }
    func setRenderingSuspended(_ value:Bool)
    func containsOpaquePoint(_ point: CGPoint) -> Bool
    func idle()
    func typing()
    func click(toward point: CGPoint)
    func pet(direction: CGFloat)
    func setSleeping(_ value: Bool)
    func celebrate()
    func hideInBox()
    func setAccessory(_ sku: String)
    func setAccessoryVisibility(_ visible: Bool)
    func setCaption(_ text: String)
    func setHeldFileCount(_ count:Int)
    func wave()
    func setWalking(_ value: Bool)
    func face(_ direction: CGFloat)
    func look(toward point: CGPoint)
    func setDancing(_ value: Bool, beat: TimeInterval)
    func reminderGesture(_ kind: String)
    func play(_ animation: PetAnimation, looping: Bool, relaxed: Bool)
    func presentation(flipped: Bool, hudScale: Double, hat: HatTransform)
    func accessoryPlacement(at point:CGPoint) -> HatTransform
}
extension CompanionAnimating {
    func setRenderingSuspended(_ value:Bool) {}
    func setHeldFileCount(_ count:Int) {}
}

@MainActor final class PetHeldFilesIndicator:SKNode {
    private let sheets:[SKShapeNode]=(0..<3).map{_ in SKShapeNode(rectOf:CGSize(width:15,height:20),cornerRadius:3)}
    private let countBadge=SKShapeNode(circleOfRadius:7)
    private let countLabel=SKLabelNode(fontNamed:NSFont.systemFont(ofSize:8,weight:.bold).fontName)
    override init() {
        super.init();zPosition=28;isHidden=true
        let offsets:[CGPoint]=[CGPoint(x:-4,y:0),CGPoint(x:0,y:2),CGPoint(x:4,y:4)]
        let rotations:[CGFloat]=[-0.15,0.03,0.17]
        let colors=[NSColor(calibratedRed:0.98,green:0.79,blue:0.73,alpha:1),NSColor(calibratedRed:0.99,green:0.91,blue:0.70,alpha:1),NSColor(calibratedRed:0.84,green:0.83,blue:0.96,alpha:1)]
        for i in sheets.indices {
            let card=sheets[i];card.position=offsets[i];card.zRotation=rotations[i];card.fillColor=colors[i];card.strokeColor=NSColor.white.withAlphaComponent(0.96);card.lineWidth=1.1
            let line=SKShapeNode(rectOf:CGSize(width:6,height:1.2),cornerRadius:0.6);line.fillColor=NSColor(calibratedRed:0.63,green:0.52,blue:0.56,alpha:0.62);line.strokeColor = .clear;line.position=CGPoint(x:0,y:-4);card.addChild(line)
            addChild(card)
        }
        countBadge.fillColor=NSColor(calibratedRed:0.83,green:0.45,blue:0.60,alpha:1);countBadge.strokeColor = .white;countBadge.lineWidth=1.1;countBadge.position=CGPoint(x:10,y:13);countBadge.addChild(countLabel);addChild(countBadge)
        countLabel.fontSize=8;countLabel.fontColor = .white;countLabel.verticalAlignmentMode = .center;countLabel.horizontalAlignmentMode = .center;countBadge.isHidden=true
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    func setCount(_ count:Int) {
        isHidden=count<1
        for (index,card) in sheets.enumerated() { card.isHidden=index >= min(count,3) }
        countBadge.isHidden=count<2;countLabel.text=count>9 ? "9+":"\(count)"
    }
}
struct ImportedPet: Codable, Identifiable {
    let id: String
    let name: String
    let folder: String
    let columns: Int
    let rows: Int
    let source: String
    let author: String
    var local: Bool? = nil
    var origin:String? = nil
    var directory: URL { local == true ? PetInstallation.root.appendingPathComponent(folder) : Bundle.main.resourceURL!.appendingPathComponent("OpenPets/\(folder)") }
}
