import AppKit
import SpriteKit

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
