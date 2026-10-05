import Foundation
import Combine

struct ProgressTrack:Codable,Identifiable {
    var id:String;var name:String;var xp:Int=0
    var level:Int { xp/500+1 };var fraction:Double { Double(xp%500)/500 }
    static let initial=[ProgressTrack(id:"season1",name:"Season 1"),ProgressTrack(id:"season2",name:"Season 2"),ProgressTrack(id:"originals",name:"PawSync originals")]
}
struct LibraryGift:Codable,Identifiable {
    var id=UUID().uuidString;var track:String;var level:Int;var choices:[String];var selected:String?=nil
}
struct LibrarySnapshot:Codable {
    var version=1;var epoch=0;var revision=0
    var tracks=ProgressTrack.initial;var activeTrack="originals";var followsPet=false
    var pets:[String]=[];var hats:[String]=[];var favoritePets:[String]=[];var favoriteHats:[String]=[]
    var gifts:[LibraryGift]=[];var claimedGifts:[String]=[];var achievements:[String:Double]=[:];var discoveries:[String]=[]
    var counters:[String:Int]=[:];var automaticCheers=true;var syncEnabled=false
    var placements:[String:HatTransform]=[:]
    var valid:Bool {
        let known=Set(FreeHat.all.map(\.id))
        return version == 1 && epoch>=0 && revision>=0 && (3...13).contains(tracks.count) && Set(ProgressTrack.initial.map(\.id)).isSubset(of:Set(tracks.map(\.id))) && Set(tracks.map(\.id)).count == tracks.count && tracks.allSatisfy{ProgressTrack.initial.map(\.id).contains($0.id) || $0.id.hasPrefix("collection.")} && tracks.allSatisfy{(0...500_000_000).contains($0.xp)} && tracks.contains{$0.id==activeTrack} && pets.count<=2000 && hats.count<=1000 && gifts.count<=500 && gifts.allSatisfy{$0.choices.count==3 && $0.choices.allSatisfy{known.contains($0)} && ($0.selected==nil || $0.choices.contains($0.selected!))} && claimedGifts.count<=10000 && achievements.count<=100 && discoveries.count<=100 && counters.count<=2100 && counters.values.allSatisfy{(0...1_000_000_000).contains($0)} && placements.count<=2000 && placements.values.allSatisfy(\.valid)
    }
}
struct LibraryAchievement:Identifiable {
    let id:String,title:String,detail:String,icon:String,key:String,goal:Int
    static let all:[Self]=[
        .init(id:"first-spark",title:"First Spark",detail:"Start your first typing rhythm.",icon:"flame.fill",key:"fire",goal:1),
        .init(id:"new-look",title:"New Look",detail:"Dress your buddy in an item.",icon:"crown.fill",key:"dress",goal:1),
        .init(id:"hello",title:"Hello, Friend",detail:"Say hello to your companion.",icon:"hand.wave.fill",key:"hello",goal:1),
        .init(id:"cuddle",title:"Cuddle Club",detail:"Give your buddy a gentle stroke.",icon:"heart.fill",key:"pet",goal:1),
        .init(id:"first-gift",title:"For You",detail:"Collect your first gift.",icon:"gift.fill",key:"gift",goal:1),
        .init(id:"five-gifts",title:"Little Treasures",detail:"Collect five gifts.",icon:"gift",key:"gift",goal:5),
        .init(id:"ten-gifts",title:"A Full Wardrobe",detail:"Collect ten gifts.",icon:"hanger",key:"gift",goal:10),
        .init(id:"first-focus",title:"Quiet Moment",detail:"Finish a focus session.",icon:"timer",key:"focus",goal:1),
        .init(id:"five-focus",title:"Gentle Rhythm",detail:"Finish five focus sessions.",icon:"leaf.fill",key:"focus",goal:5),
        .init(id:"ten-focus",title:"In Your Flow",detail:"Finish ten focus sessions.",icon:"sparkles",key:"focus",goal:10),
        .init(id:"water",title:"A Little Sip",detail:"Complete a water reminder.",icon:"drop.fill",key:"water",goal:1),
        .init(id:"stretch",title:"Paws Up",detail:"Complete a stretch reminder.",icon:"figure.flexibility",key:"stretch",goal:1),
        .init(id:"posture",title:"Sit Tall",detail:"Complete a posture reminder.",icon:"figure.seated.seatbelt",key:"posture",goal:1),
        .init(id:"eyes",title:"Faraway Look",detail:"Complete an eye-rest reminder.",icon:"eye.fill",key:"eyes",goal:1),
        .init(id:"chore",title:"Tiny Task, Done",detail:"Finish a custom reminder.",icon:"checkmark.seal.fill",key:"chore",goal:1),
        .init(id:"catch",title:"Safe Paws",detail:"Let your pet catch a file.",icon:"folder.fill",key:"catch",goal:1),
        .init(id:"ten-catches",title:"Helpful Buddy",detail:"Catch files ten times.",icon:"tray.full.fill",key:"catch",goal:10),
        .init(id:"walk",title:"First Steps",detail:"Take your companion for a walk.",icon:"figure.walk",key:"walk",goal:1),
        .init(id:"jump",title:"Little Leap",detail:"Try a jump.",icon:"arrow.up.heart.fill",key:"jump",goal:1),
        .init(id:"dance",title:"Pawty Time",detail:"Dance along with music.",icon:"music.note",key:"dance",goal:1),
        .init(id:"three-friends",title:"Hello Again",detail:"Try three different companions.",icon:"pawprint.fill",key:"friends",goal:3),
        .init(id:"ten-friends",title:"A Cozy Crowd",detail:"Try ten different companions.",icon:"person.3.fill",key:"friends",goal:10),
        .init(id:"favorite",title:"A Soft Spot",detail:"Star a favorite companion or item.",icon:"star.fill",key:"favorite",goal:1),
        .init(id:"mirror",title:"Other Side",detail:"Try Mirror Mode.",icon:"arrow.left.and.right",key:"mirror",goal:1),
        .init(id:"resize",title:"Just Your Size",detail:"Choose a new companion size.",icon:"arrow.up.left.and.arrow.down.right",key:"resize",goal:1),
        .init(id:"100",title:"One Hundred Smiles",detail:"Make 100 input reactions.",icon:"keyboard",key:"input",goal:100),
        .init(id:"1000",title:"A Thousand Little Wins",detail:"Make 1,000 input reactions.",icon:"sun.max.fill",key:"input",goal:1000),
        .init(id:"10000",title:"Desk Besties",detail:"Make 10,000 input reactions.",icon:"heart.circle.fill",key:"input",goal:10000),
        .init(id:"secret",title:"A Little Secret",detail:"Discover a companion and item pairing.",icon:"wand.and.stars",key:"secret",goal:1),
        .init(id:"all-secrets",title:"Secret Keeper",detail:"Discover all seven pairings.",icon:"sparkles",key:"secret",goal:7)
    ]
}
struct SecretPair:Identifiable {
    let id:String,pet:String,hat:String,title:String
    static let all=[SecretPair(id:"knight-royalty",pet:"knight-cat",hat:"free.crown",title:"A knight to remember"),.init(id:"garden-frog",pet:"pawpaw-season2-frog",hat:"free.sprout",title:"Pond garden"),.init(id:"flower-bunny",pet:"bunny",hat:"free.flower",title:"Meadow friend"),.init(id:"star-fox",pet:"fox",hat:"free.star",title:"Twilight fox"),.init(id:"cozy-bear",pet:"bear",hat:"free.beanie",title:"Hibernation chic"),.init(id:"bow-shiba",pet:"pawpaw-shiba",hat:"free.bow",title:"Best dressed pup"),.init(id:"moon-cat",pet:"pixel-cat",hat:"free.s1.moon.3",title:"Moonlight whiskers")]
}

@MainActor final class LibraryProgress:ObservableObject {
    @Published private(set) var state:LibrarySnapshot { didSet { dirty=true } }
    @Published private(set) var onFire=false
    @Published var message=""
    var onAchievement:((LibraryAchievement)->Void)?
    var onUnlock:(([String])->Void)?
    var onSecret:((String)->Void)?
    var onChanged:(()->Void)?
    var ownsCollection:((String)->Bool)?
    private let file:URL
    private let wardrobe:PetWardrobe
    private var dirty=false
    private var pendingXP:[String:Int]=[:],pendingInputs=0
    private var publish:DispatchWorkItem?,saveTimer:Timer?,coolWork:DispatchWorkItem?
    private var lastEvent:TimeInterval=0,lastHot:TimeInterval=0,rhythm=0
    var active:ProgressTrack { state.tracks.first{$0.id==state.activeTrack} ?? state.tracks[0] }
    static func track(for pet:String)->String? { if let entry=LibraryContent.pets.first(where:{"community-"+$0.id==pet}),let collection=entry.collection{return collection};return pet.hasPrefix("pawpaw-season2-") ? "season2":pet.hasPrefix("pawpaw-") ? "season1":pet.hasPrefix("openpets-") ? nil:"originals" }
    static func petUnlock(_ pet:String)->Int {
        if let entry=LibraryContent.pets.first(where:{"community-"+$0.id==pet}) {return entry.unlockLevel ?? 1}
        if pet == "knight-cat" { return 1 }
        if let level=PetWardrobe.unlockLevels[pet] { return level }
        let peers=PetStore.imports.filter{$0.origin == "Paw-Paw preview" && track(for:$0.id)==track(for:pet)}
        return peers.firstIndex{$0.id==pet}.map{$0*2+1} ?? 1
    }
    init(wardrobe:PetWardrobe,directory:URL=PetStore.root,legacyXP:Int=0,preservePets:[String]=[],startTimer:Bool=true) {
        self.wardrobe=wardrobe;file=directory.appendingPathComponent("Library/progress.json")
        if let saved=LocalState.read(LibrarySnapshot.self,at:file,limit:1_048_576,validate:{$0.valid}) { state=saved }
        else {
            var fresh=LibrarySnapshot();fresh.tracks[0].xp=legacyXP;fresh.tracks[2].xp=legacyXP
            fresh.hats=wardrobe.ownedHats.sorted();fresh.pets=wardrobe.ownedPets.union(preservePets).union(["knight-cat"]).sorted();state=fresh
        }
        unlockEligible(announce:false);adoptInventory();dirty=true;save()
        if startTimer { saveTimer=Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.coolDown();self?.save() } };saveTimer?.tolerance=5 }
    }
    func canSelect(_ id:String)->Bool {
        if let entry=LibraryContent.pets.first(where:{"community-"+$0.id==id}),let sku=entry.requiresSKU,ownsCollection?(sku) != true{return false}
        return Self.track(for:id)==nil || state.pets.contains(id) || !PetStore.builtInIDs.contains(id) }
    func reconcileCollections() {
        for c in LibraryContent.collections where !state.tracks.contains(where:{$0.id==c.id}) {state.tracks.append(ProgressTrack(id:c.id,name:c.name))}
        unlockEligible(announce:false)
    }
    func earn(in track:String) { guard state.tracks.contains(where:{$0.id==track}),LibraryContent.collections.first(where:{$0.id==track}).map({ownsCollection?($0.sku)==true}) != false else{return};flush();state.activeTrack=track;save() }
    func updateOptions(follows:Bool?=nil,cheers:Bool?=nil,sync:Bool?=nil) { if let follows {state.followsPet=follows};if let cheers {state.automaticCheers=cheers};if let sync {state.syncEnabled=sync};save() }
    func choosePet(_ id:String) {
        if state.followsPet,let track=Self.track(for:id) { earn(in:track) }
        let key="tried."+id;if state.counters[key]==nil { state.counters[key]=1;record("friends") }
    }
    func registerInput(at now:TimeInterval=ProcessInfo.processInfo.systemUptime) {
        rhythm=now-lastEvent < 0.28 ? rhythm+1:1;lastEvent=now
        if rhythm>=8 {lastHot=now;if !onFire {onFire=true;record("fire");scheduleCooling()}}
        coolDown(at:now)
        let amount=onFire ? 2:1
        pendingXP[state.activeTrack,default:0]+=amount;pendingInputs+=1;dirty=true
        if publish==nil { let work=DispatchWorkItem { [weak self] in self?.flush() };publish=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work) }
    }
    func coolDown(at now:TimeInterval=ProcessInfo.processInfo.systemUptime) { if onFire,now-lastHot>2.5 {onFire=false} }
    private func scheduleCooling() {
        let work=DispatchWorkItem{[weak self] in guard let self else{return};self.coolDown();if self.onFire{self.scheduleCooling()}}
        coolWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+2.6,execute:work)
    }
    func flush() {
        publish?.cancel();publish=nil
        guard pendingInputs>0 else{return}
        var next=state;var leveled=false
        for i in next.tracks.indices {
            let old=next.tracks[i].level
            next.tracks[i].xp=min(500_000_000,next.tracks[i].xp+(pendingXP[next.tracks[i].id] ?? 0))
            if next.tracks[i].level>old {
                leveled=true
                for level in (old+1)...next.tracks[i].level where next.gifts.count<500 {
                    let track=next.tracks[i].id
                    let choices=giftChoices(track:track,owned:Set(next.hats),queued:next.gifts)
                    if choices.count==3 {next.gifts.append(LibraryGift(id:"\(track)-\(level)",track:track,level:level,choices:choices))}
                }
            }
        }
        next.counters["input",default:0]+=pendingInputs;pendingInputs=0;pendingXP=[:];state=next
        if leveled {unlockEligible(announce:true)}
        evaluateAchievements();dirty=true;onChanged?()
    }
    private func giftChoices(track:String,owned:Set<String>,queued:[LibraryGift])->[String] {
        let reserved=Set(queued.flatMap(\.choices))
        var available=FreeHat.all.filter{($0.track==track || track=="originals" && $0.requiresSKU==nil) && ($0.requiresSKU==nil || ownsCollection?($0.requiresSKU!)==true) && !owned.contains($0.id) && !reserved.contains($0.id)}
        var result:[String]=[]
        for _ in 0..<3 { let total=available.reduce(0){$0+$1.weight};guard total>0 else{break};var roll=Int.random(in:0..<total)
            guard let index=available.firstIndex(where:{item in defer{roll-=item.weight};return roll<item.weight}) else{break}
            result.append(available.remove(at:index).id)
        };return result
    }
    private func unlockEligible(announce:Bool) {
        let gained=PetStore.builtInIDs.filter { id in guard let track=Self.track(for:id),let p=state.tracks.first(where:{$0.id==track}) else{return false};if let entry=LibraryContent.pets.first(where:{"community-"+$0.id==id}),let sku=entry.requiresSKU,ownsCollection?(sku) != true{return false};return p.level>=Self.petUnlock(id) && !state.pets.contains(id) }
        if !gained.isEmpty {state.pets=Set(state.pets).union(gained).sorted();adoptInventory();if announce{onUnlock?(gained)}}
    }
    private func adoptInventory() { wardrobe.adopt(pets:Set(state.pets),hats:Set(state.hats),replace:true) }
    func pickGift(_ giftID:String,index:Int) {
        guard let i=state.gifts.firstIndex(where:{$0.id==giftID}),state.gifts[i].selected==nil,state.gifts[i].choices.indices.contains(index) else{return}
        state.gifts[i].selected=state.gifts[i].choices[index];save()
    }
    @discardableResult func collectGift(_ id:String)->String? {
        guard let i=state.gifts.firstIndex(where:{$0.id==id}),let hat=state.gifts[i].selected else{return nil}
        state.hats=Set(state.hats).union([hat]).sorted();state.claimedGifts=Set(state.claimedGifts).union([id]).sorted();state.gifts.remove(at:i);adoptInventory();record("gift");save();return hat
    }
    func openAll()->[String] {
        let ids=state.gifts.map(\.id)
        return ids.compactMap {id in if let g=state.gifts.first(where:{$0.id==id}),g.selected==nil {pickGift(id,index:Int.random(in:0..<3))};return collectGift(id)}
    }
    func favorite(_ id:String,pet:Bool) {
        var values=pet ? state.favoritePets:state.favoriteHats
        if values.contains(id){values.removeAll{$0==id}} else {values.append(id);record("favorite")}
        if pet {state.favoritePets=values}else{state.favoriteHats=values};save()
    }
    func record(_ key:String) { state.counters[key,default:0]+=1;evaluateAchievements();dirty=true }
    private func evaluateAchievements() {
        for a in LibraryAchievement.all where state.achievements[a.id]==nil && (state.counters[a.key] ?? 0)>=a.goal {
            state.achievements[a.id]=Date().timeIntervalSince1970;onAchievement?(a)
        }
    }
    func pairing(pet:String,hat:String) {
        guard let pair=SecretPair.all.first(where:{$0.pet==pet && $0.hat==hat}),!state.discoveries.contains(pair.id) else{return}
        state.discoveries.append(pair.id);record("secret");save();onSecret?(pair.title)
    }
    func updatePlacement(_ pet:String,_ value:HatTransform) { guard value.valid,state.placements[pet] != value else{return};state.placements[pet]=value;dirty=true }
    func export()->LibrarySnapshot {flush();save();return state}
    func merge(_ remote:LibrarySnapshot) throws {
        guard remote.valid else{throw PawError.message("Invalid cloud progress.")};flush();try backup()
        if remote.epoch != state.epoch {
            let active=state.activeTrack,follows=state.followsPet,cheers=state.automaticCheers,sync=state.syncEnabled
            state=remote;state.activeTrack=active;state.followsPet=follows;state.automaticCheers=cheers;state.syncEnabled=sync
        }
        else if remote.epoch==state.epoch {
            var local=state
            let knownTracks=Set(local.tracks.map(\.id));local.tracks+=remote.tracks.filter{!knownTracks.contains($0.id)}
            for i in local.tracks.indices {local.tracks[i].xp=max(local.tracks[i].xp,remote.tracks.first{$0.id==local.tracks[i].id}?.xp ?? 0)}
            local.pets=Set(local.pets+remote.pets).sorted();local.hats=Set(local.hats+remote.hats).sorted()
            local.favoritePets=Set(local.favoritePets+remote.favoritePets).sorted();local.favoriteHats=Set(local.favoriteHats+remote.favoriteHats).sorted()
            local.claimedGifts=Set(local.claimedGifts+remote.claimedGifts).sorted();local.discoveries=Set(local.discoveries+remote.discoveries).sorted()
            remote.achievements.forEach{if local.achievements[$0.key]==nil {local.achievements[$0.key]=$0.value}}
            remote.counters.forEach{local.counters[$0.key]=max(local.counters[$0.key] ?? 0,$0.value)}
            let known=Set(local.gifts.map(\.id));local.gifts+=remote.gifts.filter{!known.contains($0.id)}
            local.gifts.removeAll{local.claimedGifts.contains($0.id)}
            remote.placements.forEach{if local.placements[$0.key]==nil {local.placements[$0.key]=$0.value}}
            local.revision=max(local.revision,remote.revision);state=local
        }
        unlockEligible(announce:false);adoptInventory();save()
    }
    func backup() throws {
        try LocalState.write(state,at:file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Backups/progress-\(UUID().uuidString).json"))
    }
    func reset(epoch:Int?=nil) throws {
        flush();try backup();var fresh=LibrarySnapshot();fresh.epoch=epoch ?? state.epoch+1;fresh.syncEnabled=state.syncEnabled;fresh.automaticCheers=state.automaticCheers
        fresh.pets=["knight-cat","pixel-cat","shibe"];fresh.hats=["free.sprout"];state=fresh;reconcileCollections()
        onFire=false;rhythm=0;unlockEligible(announce:false);adoptInventory();save()
    }
    func save() {flush();guard dirty else{return};state.revision+=1;do{try LocalState.write(state,at:file);dirty=false;message="";onChanged?()}catch{message="Could not save your Library progress."} }
    func stop() {saveTimer?.invalidate();publish?.cancel();coolWork?.cancel();save()}
}
