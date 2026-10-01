import Combine
import Foundation

struct PetNeeds:Codable {
    var food=80.0; var energy=80.0; var happiness=80.0; var affection=50.0; var xp=0; var level=1
    var fed=0; var played=0; var petted=0; var napped=0
    var lastSeen=Date(); var asleepUntil:Date?; var lastAction:Date?
    var valid:Bool { [food,energy,happiness,affection].allSatisfy{$0.isFinite && (0...100).contains($0)} && (0...1_000_000).contains(xp) && (1...10000).contains(level) && [fed,played,petted,napped].allSatisfy{(0...1_000_000).contains($0)} }
    var mood:String { if asleepUntil.map({$0 > Date()}) == true { return "Sleeping" }; if food < 30 { return "Hungry" }; if energy < 30 { return "Tired" }; if happiness < 30 { return "Bored" }; return (food+energy+happiness+affection)/4 >= 75 ? "Happy" : "Content" }
    mutating func decay(now:Date) {
        let elapsed=max(0,min(30*86400,now.timeIntervalSince(lastSeen)))
        let sleep=max(0,min(elapsed,(asleepUntil.map{min($0,now).timeIntervalSince(lastSeen)} ?? 0))),wake=elapsed-sleep
        food=max(0,food-elapsed/3600*2); energy=max(0,min(100,energy-wake/3600*3+sleep/3600*15))
        happiness=max(0,happiness-wake/3600*2-sleep/3600*0.5); affection=max(0,affection-wake/3600)
        lastSeen=now; if asleepUntil.map({$0 <= now}) == true { asleepUntil=nil }
    }
    mutating func reward(_ amount:Int) { xp=min(1_000_000,xp+amount); while level < 10000,xp >= level*50 { xp-=level*50; level+=1 } }
}
@MainActor final class VirtualCareService:ObservableObject {
    private struct Snapshot:Codable { var version=1; var pets:[String:PetNeeds] }
    @Published private(set) var needs=PetNeeds()
    @Published private(set) var petID="pixel-cat"
    @Published private(set) var error=""
    var onCare:((String)->Void)?
    private var saved:[String:PetNeeds]
    private let file:URL
    private let features:NativeFeatureRegistry
    private var timer:Timer?
    init(features:NativeFeatureRegistry,directory:URL=PetStore.root,startTimer:Bool=true) {
        self.features=features; file=directory.appendingPathComponent("Tools/care.json")
        saved=LocalState.read(Snapshot.self,at:file,validate:{$0.version == 1 && $0.pets.count <= 2000 && $0.pets.keys.allSatisfy{$0.count <= 100} && $0.pets.values.allSatisfy(\.valid)})?.pets ?? [:]
        needs=saved[petID] ?? PetNeeds()
        if startTimer { timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }; timer?.tolerance=10 }
    }
    func select(_ id:String,now:Date=Date()) { saved[petID]=needs; petID=id; needs=saved[id] ?? PetNeeds(lastSeen:now); if features.contains("openpets.virtual-pet") { tick(now:now) } }
    func tick(now:Date=Date()) { guard features.contains("openpets.virtual-pet") else { return }; needs.decay(now:now); save() }
    func wake(now:Date=Date()) {
        guard features.contains("openpets.virtual-pet"), needs.asleepUntil != nil else { return }
        needs.decay(now:now); needs.asleepUntil=nil; save()
    }
    func care(_ action:String,now:Date=Date()) {
        guard features.contains("openpets.virtual-pet"),["feed","play","pet","nap"].contains(action),(needs.lastAction.map{now.timeIntervalSince($0) >= 1} ?? true) else { return }
        needs.decay(now:now); needs.lastAction=now
        if action != "nap" { needs.asleepUntil=nil }
        switch action {
        case "feed": needs.food=min(100,needs.food+20); needs.affection=min(100,needs.affection+3); needs.fed=min(1_000_000,needs.fed+1); needs.reward(10)
        case "play": needs.happiness=min(100,needs.happiness+20); needs.energy=max(0,needs.energy-5); needs.affection=min(100,needs.affection+5); needs.played=min(1_000_000,needs.played+1); needs.reward(15)
        case "pet": needs.affection=min(100,needs.affection+10); needs.happiness=min(100,needs.happiness+5); needs.petted=min(1_000_000,needs.petted+1); needs.reward(5)
        case "nap": needs.asleepUntil=now.addingTimeInterval(1800); needs.napped=min(1_000_000,needs.napped+1); needs.reward(5)
        default:break
        }
        save(); onCare?(action)
    }
    private func save() { saved[petID]=needs; do { try LocalState.write(Snapshot(pets:saved),at:file); error="" } catch { self.error="Could not save your buddy’s needs." } }
    func shutdown() { timer?.invalidate(); timer=nil; save() }
}
