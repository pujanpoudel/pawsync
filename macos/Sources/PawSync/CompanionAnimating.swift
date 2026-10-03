import AppKit
import SpriteKit

@MainActor final class PawPopupPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}

@MainActor protocol CompanionAnimating: AnyObject {
    var sleeping: Bool { get }
    var requiresContinuousRendering:Bool { get }
    var companionBoundsInScene:CGRect { get }
    func containsHeldFilesPoint(_ point:CGPoint)->Bool
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
    func setReceivingFiles(_ active:Bool)
    func catchFiles()
    func express(_ emotion:PetEmotion)
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
    var requiresContinuousRendering:Bool { false }
    var companionBoundsInScene:CGRect { (self as? SKNode)?.calculateAccumulatedFrame() ?? .zero }
    func containsHeldFilesPoint(_ point:CGPoint)->Bool { false }
    func setRenderingSuspended(_ value:Bool) {}
    func setHeldFileCount(_ count:Int) {}
    func setReceivingFiles(_ active:Bool) {}
    func catchFiles() { celebrate() }
    func express(_ emotion:PetEmotion) { play(emotion == .sad ? .failed : emotion == .excited ? .jumping : .review,looping:false,relaxed:true) }
}

@MainActor final class PetHeldFilesIndicator:SKNode {
    private let pouch=SKSpriteNode()
    private var palette=PetChromePalette.companion("bunny")
    private var count=0
    override init() {
        super.init();zPosition=28;isHidden=true
        pouch.size=CGSize(width:34,height:32);addChild(pouch)
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    func setTheme(_ id:String) { palette = .companion(id);if count>0 { render() } }
    func setCount(_ value:Int) {
        guard count != value else { return };count=max(0,value);isHidden=count == 0
        if count>0 { render() }
    }
    private func render() { pouch.texture=SKTexture(image:PetChromeDrawing.heldNote(size:CGSize(width:34,height:32),palette:palette,count:count)) }
    func catchBounce() {
        removeAction(forKey:"catch");setScale(0.7)
        let up=SKAction.scale(to:1.12,duration:0.14),down=SKAction.scale(to:1,duration:0.18)
        up.timingMode = .easeOut;down.timingMode = .easeInEaseOut
        run(.sequence([up,down]),withKey:"catch")
    }
    func containsScenePoint(_ point:CGPoint)->Bool {
        guard !isHidden,let scene else { return false }
        let local=convert(point,from:scene)
        return CGRect(x:-20,y:-20,width:40,height:40).contains(local)
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
