import Combine
import Foundation

struct NativeFeature:Identifiable {
    let id:String; let name:String; let bundled:Bool; let defaultEnabled:Bool; let phase:Int
    static let all:[NativeFeature] = [
        .init(id:"openpets.reminders",name:"Quick reminders",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.simple-timer",name:"Simple timer",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.anxiety-aid-tools",name:"Gentle practices",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.focus-buddy",name:"Focus buddy",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.launch-buddy",name:"Launch greetings",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.fortune-cookie",name:"Daily fortune",bundled:true,defaultEnabled:true,phase:2),
        .init(id:"openpets.virtual-pet",name:"Virtual pet care",bundled:true,defaultEnabled:false,phase:2),
        .init(id:"openpets.system-resources",name:"System resources",bundled:true,defaultEnabled:false,phase:2),
        .init(id:"openpets.calendar-airmail",name:"Calendar airmail",bundled:false,defaultEnabled:false,phase:5),
        .init(id:"openpets.day-routine",name:"Morning & evening",bundled:false,defaultEnabled:false,phase:2),
        .init(id:"openpets.magic-8-ball",name:"Magic 8-Ball",bundled:false,defaultEnabled:false,phase:2),
        .init(id:"openpets.mood-check-in",name:"Mood check-in",bundled:false,defaultEnabled:false,phase:2),
        .init(id:"openpets.water-reminder",name:"Water buddy",bundled:false,defaultEnabled:false,phase:2),
        .init(id:"openpets.walkabout",name:"Walkabout",bundled:false,defaultEnabled:false,phase:2),
        .init(id:"openpets.spotify-buddy",name:"Spotify buddy",bundled:false,defaultEnabled:false,phase:5),
        .init(id:"openpets.drag-vocab",name:"Vocabulary drop",bundled:false,defaultEnabled:false,phase:5),
        .init(id:"openpets.higgsfield-watch",name:"Higgsfield watch",bundled:false,defaultEnabled:false,phase:5),
        .init(id:"regis.usage-buddy",name:"Usage buddy",bundled:false,defaultEnabled:false,phase:5)
    ]
}
@MainActor final class NativeFeatureRegistry:ObservableObject {
    private struct Snapshot:Codable { var version=1; var enabled:[String] }
    @Published private(set) var enabled:Set<String>
    @Published private(set) var error=""
    private let file:URL
    init(directory:URL=PetStore.root) {
        file=directory.appendingPathComponent("NativeFeatures/enabled.json")
        let stored=LocalState.read(Snapshot.self,at:file,validate:{$0.version == 1 && $0.enabled.count <= NativeFeature.all.count && $0.enabled.allSatisfy({id in NativeFeature.all.contains{$0.id == id}})})
        enabled=Set(stored?.enabled ?? NativeFeature.all.filter(\.defaultEnabled).map(\.id))
    }
    func contains(_ id:String)->Bool { enabled.contains(id) }
    func set(_ id:String,enabled value:Bool) {
        guard let feature=NativeFeature.all.first(where:{$0.id == id}),feature.phase == 2 else { return }
        if value { enabled.insert(id) } else { enabled.remove(id) }
        do { try LocalState.write(Snapshot(enabled:enabled.sorted()),at:file); error="" } catch { self.error="Could not save feature enablement." }
    }
}
