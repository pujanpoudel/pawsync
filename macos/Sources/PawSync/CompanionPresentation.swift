import AppKit
import Combine
import SpriteKit

enum PetReaction: String, Codable, CaseIterable, Identifiable {
    case idle, thinking, working, editing, running, testing, waiting, waving, success, error, celebrating
    var id:String { rawValue }
    var loops:Bool { [.thinking,.working,.editing,.running,.testing,.waiting].contains(self) }
    var defaultAnimation:PetAnimation {
        switch self { case .idle:return .idle; case .thinking:return .review; case .working,.editing,.running:return .running; case .testing,.waiting:return .waiting; case .waving:return .waving; case .success,.celebrating:return .jumping; case .error:return .failed }
    }
}
enum PetAnimation: String, Codable, CaseIterable, Identifiable {
    case idle, review, running, waiting, waving, jumping, failed
    var id:String { rawValue }
    var row:Int { switch self { case .idle:return 0; case .running:return 7; case .waving:return 3; case .jumping:return 4; case .failed:return 5; case .waiting:return 6; case .review:return 8 } }
    var frames:Int { switch self { case .waving:return 4; case .jumping:return 5; case .failed:return 8; default:return 6 } }
    var duration:Double { switch self { case .idle:return 5.5; case .review:return 1.03; case .running:return 0.82; case .waiting:return 1.01; case .waving:return 0.7; case .jumping:return 0.84; case .failed:return 1.22 } }
}

/// Atomic local state with a version check and preservation of unreadable files.
enum LocalState {
    static func read<T:Decodable>(_ type:T.Type, at url:URL, limit:Int=1_048_576, validate:(T)->Bool) -> T? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        do {
            let size=try url.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
            guard size.isSymbolicLink != true,(size.fileSize ?? Int.max) <= limit else { throw PawError.message("Invalid local state") }
            let value=try JSONDecoder().decode(type,from:Data(contentsOf:url)); guard validate(value) else { throw PawError.message("Unsupported local state") }; return value
        } catch {
            let destination=url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).quarantine-\(UUID().uuidString)")
            try? FileManager.default.moveItem(at:url,to:destination)
            return nil
        }
    }
    static func write<T:Encodable>(_ value:T,at url:URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(value).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}

@MainActor final class ReactionSettings: ObservableObject {
    struct Snapshot:Codable { var version=1; var mapping:[String:PetAnimation]; var relaxedWaiting:Bool }
    @Published var mapping:[String:PetAnimation] { didSet { save() } }
    @Published var relaxedWaiting:Bool { didSet { save() } }
    @Published private(set) var error=""
    private let file:URL
    init(directory:URL=PetStore.root) {
        file=directory.appendingPathComponent("Presentation/reactions.json")
        let saved=LocalState.read(Snapshot.self,at:file,validate:{$0.version == 1 && $0.mapping.count <= PetReaction.allCases.count && $0.mapping.keys.allSatisfy({PetReaction(rawValue:$0) != nil})})
        mapping=Dictionary(uniqueKeysWithValues:PetReaction.allCases.map { ($0.rawValue,saved?.mapping[$0.rawValue] ?? $0.defaultAnimation) })
        relaxedWaiting=saved?.relaxedWaiting ?? false
    }
    func animation(for reaction:PetReaction)->PetAnimation { mapping[reaction.rawValue] ?? reaction.defaultAnimation }
    func restore() { mapping=Dictionary(uniqueKeysWithValues:PetReaction.allCases.map{($0.rawValue,$0.defaultAnimation)}); relaxedWaiting=false }
    private func save() { do { try LocalState.write(Snapshot(mapping:mapping,relaxedWaiting:relaxedWaiting),at:file); error="" } catch { self.error="Could not save reaction preferences." } }
}

struct HatTransform:Codable,Equatable {
    var x:Double=0; var y:Double=0; var scale:Double=1; var rotation:Double=0
    var valid:Bool { x.isFinite && y.isFinite && scale.isFinite && rotation.isFinite && abs(x) <= 100 && abs(y) <= 100 && (0.4...2).contains(scale) && abs(rotation) <= 90 }
}
@MainActor final class PetPresentationStore:ObservableObject {
    struct Snapshot:Codable { var version=1; var flipped:[String:Bool]=[:]; var hats:[String:HatTransform]=[:]; var hudScale:Double=1; var hideInApps:[String]=[]; var walkSpeed:Double?=nil; var wanderInterval:Double?=nil }
    @Published var state:Snapshot { didSet { save() } }
    @Published private(set) var error=""
    private let file:URL
    init(directory:URL=PetStore.root) {
        file=directory.appendingPathComponent("Presentation/pets.json")
        state=LocalState.read(Snapshot.self,at:file,validate:{$0.version == 1 && $0.flipped.count <= 2000 && $0.hats.count <= 2000 && $0.hats.values.allSatisfy(\.valid) && (0.7...1.5).contains($0.hudScale) && $0.hideInApps.count <= 100 && $0.hideInApps.allSatisfy({$0.count <= 200})}) ?? Snapshot()
    }
    // Include the item in the key so a crown's adjustment cannot displace glasses.
    static func placementKey(pet:String,item:String)->String { pet+"::"+item }
    func transform(pet:String,item:String)->HatTransform { state.hats[Self.placementKey(pet:pet,item:item)] ?? HatTransform() }
    func setTransform(_ value:HatTransform,pet:String,item:String) {
        guard value.valid else{return}
        let key=Self.placementKey(pet:pet,item:item)
        guard state.hats[key] != nil || state.hats.count<2000 else {error="The saved placement limit has been reached.";return}
        state.hats[key]=value
    }
    func migratePlacement(pet:String,item:String) {
        let key=Self.placementKey(pet:pet,item:item)
        guard let legacy=state.hats[pet],state.hats[key]==nil else{return}
        state.hats[key]=legacy;state.hats.removeValue(forKey:pet)
    }
    func flip(_ id:String) { state.flipped[id] = !(state.flipped[id] ?? false) }
    private func save() { do { try LocalState.write(state,at:file); error="" } catch { self.error="Could not save pet presentation." } }
}
