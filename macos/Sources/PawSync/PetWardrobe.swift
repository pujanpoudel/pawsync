import AppKit
import Combine
import SpriteKit

struct FreeHat: Identifiable, Codable {
    let id: String
    let name: String
    let rarity: String
    let weight: Int
    var category:String?=nil
    var season:String?=nil
    var kind:String?=nil
    var color:String?=nil
    var requiresSKU:String?=nil
    var track:String { season ?? "season1" }
    var group:String { category ?? (id == "free.sprout" || id == "free.flower" ? "Plants":id == "free.star" ? "Curios":"Accessories") }
    static let legacy = [
        FreeHat(id: "free.sprout", name: "Little sprout", rarity: "Common", weight: 40),
        FreeHat(id: "free.bow", name: "Peach bow", rarity: "Common", weight: 40),
        FreeHat(id: "free.beanie", name: "Sleepy beanie", rarity: "Uncommon", weight: 25),
        FreeHat(id: "free.flower", name: "Daisy day", rarity: "Rare", weight: 10),
        FreeHat(id: "free.star", name: "Starry friend", rarity: "Rare", weight: 10),
        FreeHat(id: "free.crown", name: "Tiny royalty", rarity: "Legendary", weight: 3)
    ]
    private static let bundled:[FreeHat] = {
        struct Catalog:Decodable { let items:[FreeHat] }
        let url=Bundle.main.url(forResource:"catalog",withExtension:"json",subdirectory:"Library")
        let extra=url.flatMap{try? Data(contentsOf:$0)}.flatMap{try? JSONDecoder().decode(Catalog.self,from:$0)}?.items ?? []
        return legacy+extra
    }()
    private static let contentLock=NSLock()
    private static var extra:[FreeHat]=[]
    static var all:[FreeHat] { contentLock.lock();defer{contentLock.unlock()};let overrides=Dictionary(uniqueKeysWithValues:extra.map{($0.id,$0)});let known=Set(bundled.map(\.id));return bundled.map{overrides[$0.id] ?? $0}+extra.filter{!known.contains($0.id)} }
    static func installContent(_ items:[FreeHat]) throws {
        let kinds=Set(["leaf","flower","mushroom","fruit","berry","donut","cupcake","dumpling","toast","cup","bow","beanie","beret","crown","star","moon","cloud","rainbow","bird","butterfly"])
        guard items.count<=1000,Set(items.map(\.id)).count==items.count,items.allSatisfy({item in item.id.hasPrefix("free.") && item.id.count<=80 && !item.name.isEmpty && item.name.count<=80 && (1...100).contains(item.weight) && kinds.contains(item.kind ?? "") && (["season1","season2"].contains(item.track) || item.track.hasPrefix("collection.")) && ["Common","Uncommon","Rare","Epic","Legendary"].contains(item.rarity) && ["Plants","Food","Animals","Accessories","Curios"].contains(item.group) && (item.color ?? "").range(of:"^[A-Fa-f0-9]{6}$",options:.regularExpression) != nil}) else{throw PawError.message("Invalid Library content.")}
        contentLock.lock();extra=items;contentLock.unlock()
    }

}

private struct WardrobeSnapshot: Codable {
    var version = 1
    var pets: [String]
    var hats: [String]
    var rewardedLevel: Int
}

@MainActor final class PetWardrobe: ObservableObject {
    @Published private(set) var ownedPets: Set<String>
    @Published private(set) var ownedHats: Set<String>
    @Published private(set) var lastReward = ""
    private var rewardedLevel: Int
    private let file: URL
    var onReward: ((String) -> Void)?
    static let unlockLevels = ["pixel-cat": 1, "shibe": 1, "bunny": 2, "fox": 2, "bear": 3, "hamster": 3, "panda": 4, "otter": 5, "capybara": 6]

    init(directory: URL = PetStore.root, preserveExistingPets: Bool = false) {
        file = directory.appendingPathComponent("Wardrobe/inventory.json")
        let saved = LocalState.read(WardrobeSnapshot.self,at:file,validate:{$0.version == 1 && $0.pets.count <= 2000 && $0.hats.count <= 1000 && (1...1_000_000).contains($0.rewardedLevel)})
        ownedPets = Set(saved?.pets ?? (preserveExistingPets ? PetStore.rigIDs : ["pixel-cat", "shibe"]))
        ownedHats = Set((saved?.hats ?? ["free.sprout"]).filter { id in FreeHat.all.contains { $0.id == id } })
        rewardedLevel = max(1, saved?.rewardedLevel ?? 1)
        ownedHats.insert("free.sprout")
        save()
    }
    func canSelectPet(_ id: String) -> Bool { !PetStore.rigIDs.contains(id) || ownedPets.contains(id) }
    func canEquipFreeHat(_ id: String) -> Bool { ownedHats.contains(id) && FreeHat.all.contains { $0.id == id } }
    func adopt(pets:Set<String>,hats:Set<String>,replace:Bool=false) {
        ownedPets=replace ? pets:ownedPets.union(pets)
        ownedHats=replace ? hats:ownedHats.union(hats)
        save()
    }
    func reconcile(level: Int, announce: Bool = true) {
        var gained: [String] = []
        for id in PetStore.rigIDs where level >= (Self.unlockLevels[id] ?? Int.max) && !ownedPets.contains(id) {
            ownedPets.insert(id); gained.append(PetStore.rigNames[id]?.components(separatedBy: " the ").first ?? id)
        }
        if level > rewardedLevel {
            // No duplicate drops; weights apply only to hats still unowned.
            for _ in 0..<min(level - rewardedLevel, FreeHat.all.count) {
                let available = FreeHat.all.filter { !ownedHats.contains($0.id) }
                let weight = available.reduce(0) { $0 + $1.weight }
                guard weight > 0 else { break }
                var roll = Int.random(in: 0..<weight)
                for hat in available {
                    if roll < hat.weight { ownedHats.insert(hat.id); gained.append(hat.name); break }
                    roll -= hat.weight
                }
            }
            rewardedLevel = level
        }
        save()
        if !gained.isEmpty {
            lastReward = gained.joined(separator: ", ")
            if announce { onReward?(lastReward) }
        }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = WardrobeSnapshot(pets: ownedPets.sorted(), hats: ownedHats.sorted(), rewardedLevel: rewardedLevel)
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        } catch { lastReward = "Could not save your wardrobe: \(error.localizedDescription)" }
    }
}

/// Original vector accessories shared by native rigs and imported frame pets.
/// Earned free hats have explicit IDs; paid SKU authorization happens in AppModel.
@MainActor enum PetAccessories {
    static func make(_ id: String) -> SKNode? {
        guard id != "none" else { return nil }
        if let item=FreeHat.all.first(where:{$0.id == id}),item.kind != nil { return LibraryAccessoryArt.make(item) }
        let root = SKNode(); root.name = "cosmetic"
        let ink = NSColor(calibratedRed: 0.38, green: 0.27, blue: 0.29, alpha: 1)
        func shape(_ path: CGPath, _ color: NSColor) -> SKShapeNode {
            let node = SKShapeNode(path: path); node.fillColor = color; node.strokeColor = ink; node.lineWidth = 2.2; node.isAntialiased = true; root.addChild(node); return node
        }
        func line(_ points:[CGPoint],color:NSColor=ink,width:CGFloat=2) {
            let path=CGMutablePath(); guard let first=points.first else { return }; path.move(to:first)
            for point in points.dropFirst() { path.addLine(to:point) }
            let node=SKShapeNode(path:path); node.strokeColor=color; node.lineWidth=width; node.lineCap = .round; root.addChild(node)
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            _ = shape(CGPath(ellipseIn: CGRect(x: x-w/2, y: y-h/2, width: w, height: h), transform: nil), color)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            _ = shape(CGPath(roundedRect: CGRect(x: x-w/2, y: y-h/2, width: w, height: h), cornerWidth: 4, cornerHeight: 4, transform: nil), color)
        }
        switch id {
        case "free.sprout":
            oval(0,1,20,7,NSColor(calibratedRed:0.43,green:0.66,blue:0.38,alpha:1))
            let stemPath=CGMutablePath(); stemPath.move(to:CGPoint(x:0,y:2)); stemPath.addQuadCurve(to:CGPoint(x:1,y:27),control:CGPoint(x:-5,y:15))
            let stem=SKShapeNode(path:stemPath); stem.strokeColor=NSColor(calibratedRed:0.30,green:0.56,blue:0.32,alpha:1); stem.lineWidth=3.4; stem.lineCap = .round; root.addChild(stem)
            let left=shape(CGPath(ellipseIn:CGRect(x:-23,y:18,width:24,height:14),transform:nil),NSColor(calibratedRed:0.54,green:0.77,blue:0.47,alpha:1));left.zRotation = -0.22
            let right=shape(CGPath(ellipseIn:CGRect(x:0,y:20,width:25,height:14),transform:nil),NSColor(calibratedRed:0.72,green:0.85,blue:0.56,alpha:1));right.zRotation = 0.22
            oval(-9,25,8,3,.white.withAlphaComponent(0.36)); oval(11,27,8,3,.white.withAlphaComponent(0.35))
        case "free.bow":
            let pink = NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.68, alpha: 1)
            let leftTail=CGMutablePath(); leftTail.move(to:CGPoint(x:-4,y:3));leftTail.addLine(to:CGPoint(x:-17,y:-15));leftTail.addLine(to:CGPoint(x:-22,y:-5));leftTail.addLine(to:CGPoint(x:-29,y:-9));leftTail.addLine(to:CGPoint(x:-17,y:14));leftTail.closeSubpath();_ = shape(leftTail,pink)
            let rightTail=CGMutablePath(); rightTail.move(to:CGPoint(x:4,y:3));rightTail.addLine(to:CGPoint(x:17,y:-15));rightTail.addLine(to:CGPoint(x:22,y:-5));rightTail.addLine(to:CGPoint(x:29,y:-9));rightTail.addLine(to:CGPoint(x:17,y:14));rightTail.closeSubpath();_ = shape(rightTail,pink)
            for sign: CGFloat in [-1, 1] {
                let path = CGMutablePath(); path.move(to: CGPoint(x: 0, y: 9)); path.addLine(to: CGPoint(x: sign*25, y: 23)); path.addQuadCurve(to: CGPoint(x: sign*25, y: -3), control: CGPoint(x: sign*34, y: 9)); path.closeSubpath(); _ = shape(path, pink)
                oval(sign*17,13,10,5,NSColor.white.withAlphaComponent(0.43))
            }
            oval(0, 10, 14, 19,NSColor(calibratedRed:0.85,green:0.36,blue:0.52,alpha:1))
            oval(-2,14,4,5,.white.withAlphaComponent(0.42))
        case "free.beanie":
            oval(0, 16, 65, 48, NSColor(calibratedRed: 0.68, green: 0.58, blue: 0.79, alpha: 1))
            oval(-8,28,28,13,.white.withAlphaComponent(0.14))
            rect(0, 0, 70, 18, NSColor(calibratedRed: 0.82, green: 0.74, blue: 0.89, alpha: 1))
            for x:CGFloat in [-20,-10,0,10,20] { line([CGPoint(x:x,y:-6),CGPoint(x:x,y:5)],color:NSColor(calibratedRed:0.68,green:0.58,blue:0.78,alpha:0.7),width:1.5) }
            oval(0, 39, 17, 17, NSColor(calibratedRed:0.94,green:0.73,blue:0.82,alpha:1))
        case "free.flower":
            oval(0,-2,16,6,NSColor(calibratedRed:0.52,green:0.70,blue:0.43,alpha:1))
            for index in 0..<7 { let angle = CGFloat(index) * .pi*2/7; oval(cos(angle)*13, 13+sin(angle)*13, 17, 17, .init(calibratedRed: 1, green: 0.96, blue: 0.87, alpha: 1)) }
            oval(0, 13, 17, 17, NSColor(calibratedRed:0.94,green:0.69,blue:0.35,alpha:1))
            oval(-3,17,4,4,.white.withAlphaComponent(0.55))
        case "free.crown":
            let path = CGMutablePath(); path.move(to: CGPoint(x: -29, y: 0)); for point in [CGPoint(x: -33, y: 27), CGPoint(x: -14, y: 16), CGPoint(x: 0, y: 36), CGPoint(x: 14, y: 16), CGPoint(x: 33, y: 27), CGPoint(x: 29, y: 0)] { path.addLine(to: point) }; path.closeSubpath(); _ = shape(path, NSColor(calibratedRed: 0.97, green: 0.76, blue: 0.35, alpha: 1))
            rect(0,2,62,8,NSColor(calibratedRed:0.82,green:0.52,blue:0.24,alpha:1))
            for x:CGFloat in [-22,0,22] { oval(x,x == 0 ? 15 : 11,8,8,x == 0 ? NSColor(calibratedRed:0.94,green:0.47,blue:0.60,alpha:1) : NSColor(calibratedRed:0.62,green:0.79,blue:0.88,alpha:1)) }
            oval(-8,24,13,4,.white.withAlphaComponent(0.4))
        case "free.star":
            let path = CGMutablePath()
            for index in 0..<10 { let angle = CGFloat(index) * .pi / 5 + .pi / 2; let radius: CGFloat = index.isMultiple(of: 2) ? 25 : 11; let p = CGPoint(x: cos(angle)*radius, y: sin(angle)*radius+17); if index == 0 { path.move(to: p) } else { path.addLine(to: p) } }; path.closeSubpath(); _ = shape(path, NSColor(calibratedRed:1,green:0.79,blue:0.38,alpha:1))
            oval(-5,22,8,4,.white.withAlphaComponent(0.46))
        case "accessory.hat":
            oval(0,-1,72,10,NSColor(calibratedRed:0.28,green:0.23,blue:0.35,alpha:1))
            rect(0,17,46,42,NSColor(calibratedRed:0.28,green:0.23,blue:0.35,alpha:1))
            rect(0,7,47,9,NSColor(calibratedRed:0.70,green:0.54,blue:0.78,alpha:1))
            rect(-11,26,5,17,.white.withAlphaComponent(0.12))
            oval(0,0,74,9,NSColor(calibratedRed:0.32,green:0.27,blue:0.40,alpha:1))
        case "accessory.glasses":
            for x: CGFloat in [-22, 22] {
                let lens=shape(CGPath(roundedRect:CGRect(x:x-14,y:-45,width:28,height:24),cornerWidth:10,cornerHeight:10,transform:nil),NSColor(calibratedRed:0.79,green:0.91,blue:0.94,alpha:0.12));lens.lineWidth=3.5
                oval(x-8,-27,13,4,.white.withAlphaComponent(0.25))
            }
            line([CGPoint(x:-4,y:-33),CGPoint(x:4,y:-33)],width:3.3)
            line([CGPoint(x:-36,y:-34),CGPoint(x:-43,y:-30)],width:3)
            line([CGPoint(x:36,y:-34),CGPoint(x:43,y:-30)],width:3)
        default: return nil
        }
        PetWearableFit.recordBounds(root)
        return root
    }
    static func headphones()->SKNode {
        let root=SKNode()
        let bandPath=CGMutablePath(); bandPath.move(to:CGPoint(x:-35,y:-34)); bandPath.addQuadCurve(to:CGPoint(x:35,y:-34),control:CGPoint(x:0,y:43))
        let band=SKShapeNode(path:bandPath); band.strokeColor=NSColor(calibratedRed:0.35,green:0.28,blue:0.43,alpha:1);band.lineWidth=9;band.lineCap = .round;root.addChild(band)
        let shine=SKShapeNode(path:bandPath);shine.strokeColor=NSColor(calibratedRed:0.74,green:0.60,blue:0.83,alpha:0.6);shine.lineWidth=3;root.addChild(shine)
        for x:CGFloat in [-35,35] {
            let cup=SKShapeNode(rectOf:CGSize(width:18,height:32),cornerRadius:8)
            cup.position=CGPoint(x:x,y:-34);cup.fillColor=NSColor(calibratedRed:0.68,green:0.52,blue:0.80,alpha:1);cup.strokeColor=NSColor(calibratedRed:0.35,green:0.28,blue:0.43,alpha:1);cup.lineWidth=3;root.addChild(cup)
            let glint=SKShapeNode(ellipseOf:CGSize(width:4,height:12));glint.position=CGPoint(x:x-4,y:-28);glint.fillColor = .white.withAlphaComponent(0.44);glint.strokeColor = .clear;root.addChild(glint)
        }
        return root
    }
}
