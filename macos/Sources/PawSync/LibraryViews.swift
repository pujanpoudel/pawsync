import SwiftUI
import AppKit

private typealias LState<V> = SwiftUI.State<V>
enum LibraryStyle {
    static let ink=Color(red:0.25,green:0.19,blue:0.17)
    static let muted=Color(red:0.50,green:0.43,blue:0.38)
    static let paper=Color(red:1,green:0.985,blue:0.97)
    static let cream=Color(red:0.985,green:0.96,blue:0.93)
    static let purple=Color(red:0.48,green:0.34,blue:0.65)
    static let pink=Color(red:0.77,green:0.26,blue:0.55)
}
struct CozyButton:ButtonStyle {
    var prominent=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.semibold,design:.rounded)).padding(.horizontal,16).padding(.vertical,10)
            .foregroundStyle(prominent ? Color.white:LibraryStyle.purple)
            .background(prominent ? LibraryStyle.purple:LibraryStyle.purple.opacity(0.08),in:Capsule())
            .opacity(configuration.isPressed ? 0.72:1).contentShape(Capsule())
    }
}
struct LibraryXPStrip:View {
    @ObservedObject var library:LibraryProgress
    var track:String?=nil
    private var value:ProgressTrack {library.state.tracks.first{$0.id==(track ?? library.state.activeTrack)} ?? library.active}
    var body:some View {
        VStack(spacing:9) {
            HStack {
                Text("LVL \(value.level)").font(.system(size:12,weight:.bold,design:.rounded))
                Text("\(value.xp%500) / 500 XP").font(.caption.monospacedDigit()).foregroundStyle(LibraryStyle.muted)
                Spacer()
                if library.onFire && value.id==library.state.activeTrack {Label("On Fire · 2× XP",systemImage:"flame.fill").font(.caption.bold()).foregroundStyle(.orange)}
                if value.id==library.state.activeTrack {Label("Earning XP",systemImage:"checkmark").font(.caption).foregroundStyle(LibraryStyle.purple)}
                else {Button("Earn XP Here"){library.earn(in:value.id)}.buttonStyle(CozyButton())}
            }
            GeometryReader {g in
                ZStack(alignment:.leading) {
                    Capsule().fill(LibraryStyle.purple.opacity(0.13))
                    Capsule().fill(library.onFire && value.id==library.state.activeTrack ? AnyShapeStyle(LinearGradient(colors:[.pink,.purple,.blue,.green,.orange],startPoint:.leading,endPoint:.trailing)):AnyShapeStyle(LibraryStyle.purple)).frame(width:max(3,g.size.width*value.fraction))
                }
            }.frame(height:7)
        }.padding(17).background(LibraryStyle.purple.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
    }
}
enum LibraryPetGroup:String,CaseIterable,Identifiable {
    case openpets="OpenPets", originals="PawSync originals", animals="Animal friends", custom="Your creations & imports"
    var id:String {rawValue}
    static func group(for id:String)->Self {
        if id.hasPrefix("openpets-"){return .openpets}
        if id == "knight-cat" || PetStore.rigIDs.contains(id){return .originals}
        if id.hasPrefix("pawpaw-"){return .animals}
        return .custom
    }
}
struct LibraryGalleryView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    @ObservedObject var preferences:Preferences
    var track:String?=nil
    @LState private var search=""
    @LState private var favorites=false
    @LState private var preview:String?
    private var names:[String:String] {PetStore.builtInNames.merging(Dictionary(uniqueKeysWithValues:model.custom.customPets.map{($0.id,$0.name)})){_,new in new}}
    private var ids:[String] {
        (["knight-cat"]+PetStore.rigIDs+model.catalog.installed.map(\.id).filter{$0 != "knight-cat"}+model.custom.customPets.map(\.id)).filter {id in
            (track==nil || LibraryProgress.track(for:id)==track) && (!favorites || library.state.favoritePets.contains(id)) && (search.isEmpty || (names[id] ?? id).localizedCaseInsensitiveContains(search))
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                HStack {Image(systemName:"magnifyingglass");TextField("Find a little friend",text:$search).textFieldStyle(.plain)}.padding(11).background(LibraryStyle.paper,in:Capsule()).overlay(Capsule().stroke(LibraryStyle.purple.opacity(0.12)))
                Picker("Show companions",selection:$favorites) {Text("All").tag(false);Text("Favorites").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:160)
            }
            Text("Click a friend to bring them to your desktop. The ⓘ button opens their details.").font(.caption).foregroundStyle(LibraryStyle.muted)
            if ids.isEmpty {ContentUnavailableView("No little friends here yet",systemImage:"pawprint",description:Text("Try another name or add a favorite."))}
            ForEach(LibraryPetGroup.allCases) {group in
                let members=ids.filter{LibraryPetGroup.group(for:$0)==group}
                if !members.isEmpty {
                    HStack {Text(group.rawValue).font(.system(size:18,weight:.bold,design:.rounded));Text("\(members.count)").font(.caption).foregroundStyle(LibraryStyle.muted);Spacer()}
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:13)],spacing:13) {
                        ForEach(members,id:\.self) {id in petCard(id)}
                    }
                }
            }
            Text("\(ids.count) companions · Stars keep your favorites close.").font(.caption).foregroundStyle(LibraryStyle.muted)
            DisclosureGroup("Browse more OpenPets or import a pet") {PetGalleryView(model:model,catalog:model.catalog,preferences:preferences,showInstalled:false)}
        }.sheet(isPresented:Binding(get:{preview != nil},set:{if !$0 {preview=nil}})) {
            if let id=preview {PetPreviewSheet(model:model,library:library,preferences:preferences,id:id,onClose:{preview=nil})}
        }
    }
    private func petCard(_ id:String)->some View {
        let unlocked=library.canSelect(id),active=preferences.companion==id,name=names[id] ?? id
        return VStack(spacing:0) {
            Button {model.selectLibraryPet(id)} label: {
                VStack(alignment:.leading,spacing:7) {
                    Group {if let image=PetStore.preview(id){Image(nsImage:image).resizable().scaledToFit()}else{Image(systemName:"pawprint.fill").font(.largeTitle)}}
                        .frame(maxWidth:.infinity).frame(height:104).opacity(unlocked ? 1:0.4)
                    Text(name).font(.system(size:12,weight:.bold,design:.rounded)).lineLimit(1)
                    Text(active ? "Your buddy":unlocked ? "Click to choose":"Joins at LVL \(LibraryProgress.petUnlock(id))").font(.system(size:10,weight:.medium)).foregroundStyle(active ? LibraryStyle.purple:LibraryStyle.muted)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Choose \(name)")
            HStack {
                Button {library.favorite(id,pet:true)} label:{Image(systemName:library.state.favoritePets.contains(id) ? "star.fill":"star").frame(width:28,height:26)}.accessibilityLabel("Favorite \(name)")
                Spacer()
                Button {preview=id} label:{Image(systemName:"info.circle").frame(width:28,height:26)}.accessibilityLabel("Details about \(name)").help("About this pet")
            }.buttonStyle(.plain).foregroundStyle(LibraryStyle.purple).font(.system(size:13)).padding(.horizontal,7).padding(.bottom,6)
        }.background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(active ? LibraryStyle.purple:LibraryStyle.purple.opacity(0.13),style:StrokeStyle(lineWidth:active ? 1.6:1,dash:unlocked ? []:[4,4])))
    }
}
struct PetPreviewSheet:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    @ObservedObject var preferences:Preferences
    var id:String;var onClose:()->Void
    var body:some View {
        VStack(spacing:18) {
            if let image=PetStore.preview(id){Image(nsImage:image).resizable().scaledToFit().frame(height:220)}
            Text(PetStore.builtInNames[id] ?? model.custom.customPets.first{$0.id==id}?.name ?? id).font(.system(size:26,weight:.bold,design:.rounded))
            Text(library.canSelect(id) ? "A friend for little wins and gentle breaks.":"Keep earning on this companion’s track. Joins at level \(LibraryProgress.petUnlock(id)).").foregroundStyle(LibraryStyle.muted).multilineTextAlignment(.center)
            HStack {Button("Keep me company"){model.selectLibraryPet(id);onClose()}.buttonStyle(CozyButton(prominent:true)).disabled(!library.canSelect(id));Button("Done",action:onClose).buttonStyle(CozyButton())}
            if library.canSelect(id) {HStack {Button("Cuddle"){model.selectLibraryPet(id);DispatchQueue.main.async{model.overlay.reactToPetClick()}};Button("Walk"){model.selectLibraryPet(id);model.library.record("walk");DispatchQueue.main.async{model.overlay.wanderNow()}};Button("Jump"){model.selectLibraryPet(id);model.library.record("jump");DispatchQueue.main.async{model.overlay.jumpNow()}}}.buttonStyle(CozyButton())}
        }.padding(30).frame(width:430).background(LibraryStyle.cream).foregroundStyle(LibraryStyle.ink).onExitCommand(perform:onClose)
    }
}
struct LibraryItemsView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    @ObservedObject var wardrobe:PetWardrobe
    @ObservedObject var preferences:Preferences
    @LState private var search=""
    @LState private var category="All categories"
    @LState private var favorites=false
    @LState private var ownedOnly=false
    @LState private var previewItem:FreeHat?
    private var results:[FreeHat] {FreeHat.all.filter {hat in
        (search.isEmpty || hat.name.localizedCaseInsensitiveContains(search)) && (category=="All categories" || hat.group==category) && (!favorites || library.state.favoriteHats.contains(hat.id)) && (!ownedOnly || wardrobe.ownedHats.contains(hat.id))
    }}
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                HStack {Image(systemName:"magnifyingglass");TextField("Search items",text:$search).textFieldStyle(.plain)}.padding(11).background(LibraryStyle.paper,in:Capsule())
                Picker("Show items",selection:$favorites){Text("All").tag(false);Text("Favorites").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:150)
            }
            HStack {
                Picker("Category",selection:$category){ForEach(["All categories","Plants","Food","Animals","Accessories","Curios"],id:\.self){Text($0)}}.frame(width:200)
                Toggle("Collected",isOn:$ownedOnly).toggleStyle(.checkbox)
                Spacer();Button("Bare ears"){model.equipLibraryItem("none")}.buttonStyle(CozyButton())
            }
            if !library.state.gifts.isEmpty {GiftQueueBanner(model:model,library:library)}
            ForEach(["Common","Uncommon","Rare","Epic","Legendary"],id:\.self) {rarity in
                let items=results.filter{$0.rarity==rarity}
                if !items.isEmpty {
                    HStack {Circle().fill(rarity=="Legendary" ? Color.orange:LibraryStyle.purple).frame(width:6,height:6);Text("\(rarity) · \(items.count)").font(.system(size:12,weight:.semibold,design:.rounded))}
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:108),spacing:11)],spacing:11) {
                        ForEach(items) {hat in
                            let owned=wardrobe.ownedHats.contains(hat.id),active=preferences.accessory==hat.id && preferences.headAccessoriesVisible
                            VStack(alignment:.leading,spacing:7) {
                                HStack {Button {previewItem=hat} label:{Image(systemName:"info.circle").frame(width:24,height:24)}.buttonStyle(.plain).accessibilityLabel("Details about \(hat.name)");Spacer();Button {library.favorite(hat.id,pet:false)} label:{Image(systemName:library.state.favoriteHats.contains(hat.id) ? "star.fill":"star").font(.system(size:10))}.buttonStyle(.plain).accessibilityLabel("Favorite \(hat.name)")}
                                Button {model.equipLibraryItem(hat.id)} label:{
                                    VStack(alignment:.leading,spacing:7) {
                                        Image(nsImage:WearablePreview.image(hat.id)).resizable().scaledToFit().frame(maxWidth:.infinity).frame(height:60).opacity(owned ? 1:0.78)
                                        Text(hat.name).font(.system(size:11,weight:.bold,design:.rounded)).lineLimit(2).frame(height:29,alignment:.topLeading)
                                        Text(hat.group).font(.system(size:9)).foregroundStyle(LibraryStyle.muted)
                                        Text(active ? "Wearing":owned ? (hat.track=="season2" ? "Season 2":"Season 1"):"Earn in gifts").font(.system(size:9,weight:.medium)).foregroundStyle(LibraryStyle.purple)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }.padding(11).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(active ? LibraryStyle.purple:LibraryStyle.purple.opacity(0.12),lineWidth:active ? 1.5:1))
                                .onDrag {guard owned else{return NSItemProvider()};model.overlay.beginHatDrag();return NSItemProvider(object:hat.id as NSString)}
                        }
                    }
                }
            }
            Text("\(wardrobe.ownedHats.count) collected · \(FreeHat.all.count) free items. Every item fits every companion; drag a collected item onto your pet to place it.").font(.caption).foregroundStyle(LibraryStyle.muted)
            SecretDiscoveriesView(library:library)
        }.sheet(item:$previewItem) {item in
            VStack(spacing:18) {
                Text(item.name).font(.system(size:25,weight:.bold,design:.rounded))
                ItemPetPreview(id:preferences.companion,sku:item.id,transform:HatTransform(),flipped:false).frame(width:280,height:260)
                Text("\(item.group) · \(item.rarity)").font(.caption).foregroundStyle(LibraryStyle.muted)
                Text(wardrobe.ownedHats.contains(item.id) ? "Fits your current friend automatically. You can adjust the placement whenever you like.":"A little gift to discover as you level up.").foregroundStyle(LibraryStyle.muted).multilineTextAlignment(.center)
                HStack {
                    if wardrobe.ownedHats.contains(item.id) {Button("Wear it"){model.equipLibraryItem(item.id);previewItem=nil}.buttonStyle(CozyButton(prominent:true))}
                    Button("Done"){previewItem=nil}.buttonStyle(CozyButton()).keyboardShortcut(.defaultAction)
                }
            }.padding(30).background(LibraryStyle.cream).foregroundStyle(LibraryStyle.ink)
        }
    }
}
struct AchievementsView:View {
    @ObservedObject var library:LibraryProgress
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {Label("Little things worth celebrating",systemImage:"heart.fill").foregroundStyle(LibraryStyle.pink);Spacer();Text("\(library.state.achievements.count) / 30").font(.headline)}
            Text("Permanent discoveries, companion milestones, and personal style. Achievements never add XP or gifts.").font(.callout).foregroundStyle(LibraryStyle.muted)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:230))],spacing:14) {
                ForEach(LibraryAchievement.all) {a in
                    let earned=library.state.achievements[a.id] != nil,count=min(a.goal,library.state.counters[a.key] ?? 0)
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:a.icon).font(.system(size:22)).frame(width:46,height:46).foregroundStyle(earned ? LibraryStyle.purple:LibraryStyle.muted.opacity(0.5)).background(LibraryStyle.purple.opacity(earned ? 0.10:0.04),in:Circle())
                        VStack(alignment:.leading,spacing:6) {
                            Text(a.title).font(.system(size:14,weight:.bold,design:.rounded));Text(a.detail).font(.caption).foregroundStyle(LibraryStyle.muted)
                            if earned {Label("Discovered",systemImage:"checkmark").font(.caption2).foregroundStyle(LibraryStyle.purple)}else{Text("\(count) / \(a.goal)").font(.caption2.monospacedDigit()).foregroundStyle(LibraryStyle.muted)}
                        };Spacer(minLength:0)
                    }.padding(17).frame(maxWidth:.infinity,minHeight:110,alignment:.topLeading).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:22))
                }
            }
            SecretDiscoveriesView(library:library)
        }
    }
}
struct SecretDiscoveriesView:View {
    @ObservedObject var library:LibraryProgress
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Secret combinations",systemImage:"wand.and.stars").font(.headline)
            Text("Some buddies and items belong together. Try dressing up to discover seven tiny surprises.").font(.caption).foregroundStyle(LibraryStyle.muted)
            ForEach(SecretPair.all) {pair in
                HStack {Image(systemName:library.state.discoveries.contains(pair.id) ? "sparkles":"lock");Text(library.state.discoveries.contains(pair.id) ? "\(pair.title) · \(PetStore.builtInNames[pair.pet] ?? pair.pet) + \(FreeHat.all.first{$0.id==pair.hat}?.name ?? "Item")":"A little secret, waiting for you").font(.caption);Spacer()}
            }
        }.padding(20).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:22))
    }
}
struct GiftQueueBanner:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    var body:some View {
        HStack(spacing:13) {
            Image(systemName:"gift.fill").font(.title2).foregroundStyle(LibraryStyle.pink)
            VStack(alignment:.leading,spacing:3){Text("\(library.state.gifts.count) little \(library.state.gifts.count==1 ? "gift":"gifts") waiting").font(.system(size:14,weight:.bold,design:.rounded));Text("Pick one of three. The others can wait.").font(.caption).foregroundStyle(LibraryStyle.muted)}
            Spacer();Button("Open a gift"){model.presentGifts=true}.buttonStyle(CozyButton(prominent:true))
            if library.state.gifts.count>=2 {Button("Open All"){model.openAllGifts()}.buttonStyle(CozyButton())}
        }.padding(18).background(LibraryStyle.pink.opacity(0.06),in:RoundedRectangle(cornerRadius:22))
    }
}
struct GiftRevealView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    @LState private var collected:[String]=[]
    private var gift:LibraryGift? {library.state.gifts.first}
    var body:some View {
        VStack(spacing:22) {
            Text(collected.isEmpty ? "A little gift, just for you":"Your new little treasures").font(.system(size:25,weight:.bold,design:.rounded))
            if !collected.isEmpty {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:100))]){ForEach(collected,id:\.self){id in VStack {Image(nsImage:WearablePreview.image(id));Text(FreeHat.all.first{$0.id==id}?.name ?? "Item").font(.caption);Button("Wear It"){model.equipLibraryItem(id);model.presentGifts=false}.buttonStyle(CozyButton(prominent:true))}}}
                Button("Done"){model.presentGifts=false}.buttonStyle(CozyButton())
            } else if let gift {
                if let chosen=gift.selected,let item=FreeHat.all.first(where:{$0.id==chosen}) {
                    Image(nsImage:WearablePreview.image(chosen)).resizable().scaledToFit().frame(width:180,height:140)
                    Text(item.name).font(.system(size:21,weight:.bold,design:.rounded))
                    Text("\(item.rarity) · \(item.track=="season2" ? "Season 2":"Season 1")").foregroundStyle(LibraryStyle.muted)
                    HStack {Button("Wear It"){if let id=library.collectGift(gift.id){model.equipLibraryItem(id)};model.presentGifts=false}.buttonStyle(CozyButton(prominent:true));Button("Add to Items"){_ = library.collectGift(gift.id);model.presentGifts=false}.buttonStyle(CozyButton())}
                    Text("Other gifts will wait until you’re ready.").font(.caption).foregroundStyle(LibraryStyle.muted)
                } else {
                    Text("Choose a cozy gift ball. Use your mouse or keys 1–3.").foregroundStyle(LibraryStyle.muted)
                    HStack(spacing:16) {ForEach(0..<3,id:\.self){i in
                        Button {library.pickGift(gift.id,index:i)} label:{VStack {ZStack {Circle().fill([Color(red:0.94,green:0.67,blue:0.77),Color(red:0.76,green:0.69,blue:0.91),Color(red:0.79,green:0.86,blue:0.66)][i]);Image(systemName:"gift.fill").font(.system(size:36)).foregroundStyle(.white)}.frame(width:96,height:96);Text("\(i+1)").font(.headline)}}.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(i+1))),modifiers:[])
                    }}
                    if library.state.gifts.count>=2 {Button("Open All \(library.state.gifts.count) gifts"){collected=library.openAll()}.buttonStyle(CozyButton())}
                    Button("Save for later"){model.presentGifts=false}.buttonStyle(CozyButton())
                }
            } else {Text("More little treasures arrive as you level up.");Button("Done"){model.presentGifts=false}.buttonStyle(CozyButton())}
        }.padding(34).frame(width:510).background(LibraryStyle.cream).foregroundStyle(LibraryStyle.ink).onExitCommand{model.presentGifts=false}
    }
}

struct ItemEditorView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var preferences:Preferences
    @ObservedObject var store:PetPresentationStore
    @LState private var original=HatTransform()
    private var transform:HatTransform {store.transform(pet:preferences.companion,item:preferences.accessory)}
    private func binding(_ key:WritableKeyPath<HatTransform,Double>)->Binding<Double> {Binding(get:{transform[keyPath:key]},set:{value in var t=transform;t[keyPath:key]=value;store.setTransform(t,pet:preferences.companion,item:preferences.accessory)})}
    var body:some View {
        VStack(spacing:17) {
            Text("Just the right fit").font(.system(size:25,weight:.bold,design:.rounded))
            ItemPetPreview(id:preferences.companion,sku:preferences.accessory,transform:transform,flipped:store.state.flipped[preferences.companion] ?? false).frame(width:280,height:260)
            Text("Arrow keys nudge the item. Reset previews its natural fit.").font(.caption).foregroundStyle(LibraryStyle.muted)
            HStack{Text("Left / right").frame(width:90);Slider(value:binding(\.x),in:-100...100)}
            HStack{Text("Up / down").frame(width:90);Slider(value:binding(\.y),in:-100...100)}
            HStack{Text("Size").frame(width:90);Slider(value:binding(\.scale),in:0.4...2)}
            HStack{Text("Tilt").frame(width:90);Slider(value:binding(\.rotation),in:-90...90)}
            HStack {
                Button("Reset"){store.setTransform(HatTransform(),pet:preferences.companion,item:preferences.accessory)}.buttonStyle(CozyButton())
                Button("Change Item"){model.presentItemEditor=false;model.settingsSection = .items}.buttonStyle(CozyButton())
                Spacer();Button("Cancel"){store.setTransform(original,pet:preferences.companion,item:preferences.accessory);model.presentItemEditor=false}.buttonStyle(CozyButton()).keyboardShortcut(.cancelAction)
                Button("Done"){model.presentItemEditor=false}.buttonStyle(CozyButton(prominent:true)).keyboardShortcut(.defaultAction)
            }
        }.padding(27).frame(width:520).background(LibraryStyle.cream).foregroundStyle(LibraryStyle.ink).onAppear{original=transform}.focusable().onMoveCommand{direction in var t=transform;switch direction{case .left:t.x=max(-100,t.x-2);case .right:t.x=min(100,t.x+2);case .up:t.y=min(100,t.y+2);case .down:t.y=max(-100,t.y-2);@unknown default:break};store.setTransform(t,pet:preferences.companion,item:preferences.accessory)}
    }
}
import SpriteKit
struct ItemPetPreview:NSViewRepresentable {
    var id:String,sku:String,transform:HatTransform,flipped:Bool
    func makeNSView(context:Context)->SKView {let v=SKView();v.allowsTransparency=true;v.preferredFramesPerSecond=30;let s=SKScene(size:CGSize(width:280,height:300));s.backgroundColor = .clear;s.scaleMode = .aspectFit;v.presentScene(s);return v}
    func updateNSView(_ v:SKView,context:Context) {
        guard let s=v.scene else{return}
        var node=s.children.first as? (SKNode & CompanionAnimating)
        if node?.name != id {s.removeAllChildren();if let spec=PetStore.frameOriginal(id) ?? PetStore.imports.first(where:{$0.id==id}){node=try? FramePetNode(spec:spec)}else{node=try? PetSpriteNode(manifest:PetStore.load(id),directory:PetStore.directory(for:id))};if let node{node.name=id;node.position=CGPoint(x:140,y:26);s.addChild(node)}}
        node?.setAccessory(sku);node?.presentation(flipped:flipped,hudScale:1,hat:transform)
        v.isPaused=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.15){[weak v] in v?.isPaused=true}
    }
}

struct LibraryCollectionsView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var library:LibraryProgress
    @ObservedObject var wallet:PetWalletService
    @ObservedObject var preferences:Preferences
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            if LibraryContent.collections.isEmpty {ContentUnavailableView("Artist collections are coming",systemImage:"paintpalette",description:Text("Optional one-time collections appear here when their artwork and checkout are ready. Both free seasons remain available."))}
            ForEach(LibraryContent.collections) {collection in
                VStack(alignment:.leading,spacing:15) {
                    Text(collection.name).font(.system(size:23,weight:.bold,design:.rounded))
                    if wallet.accessories.contains(collection.sku) {
                        LibraryGalleryView(model:model,library:library,preferences:preferences,track:collection.id)
                    }else{
                        Text("An optional one-time artist collection, with its own level track. Purchases unlock the track; you earn its companions and items as you play.").font(.callout).foregroundStyle(LibraryStyle.muted)
                        Button(collection.priceLabel.map{"Unlock · "+$0} ?? "Unlock collection"){wallet.checkout(collection.sku)}.buttonStyle(CozyButton(prominent:true))
                    }
                }.padding(22).background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:24))
            }
        }
    }
}
