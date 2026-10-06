import SwiftUI
import AppKit
import SpriteKit
import UniformTypeIdentifiers

private let pawAccent = Color(red: 0.45, green: 0.36, blue: 0.72)
// Avoid the newer same-name State macro when building with the standalone SDK.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum SettingsSection: String, CaseIterable, Identifiable {
    case settings = "Settings", wellness = "Wellness", createPet = "Make your own pet", appearance = "Appearance", dashboard = "Overview", general = "Companion", gallery = "Pets", items = "Items", achievements = "Achievements", season1 = "Season 1", season2 = "Season 2", originals = "PawSync originals", about = "About", collections = "Artist collections", features = "Companion tools", reminders = "Reminders", activity = "Progress", focus = "Focus & habits", developer = "Developer", wallet = "Account", privacy = "Privacy"
    var id: String { rawValue }
    static let sidebar:[Self] = [.gallery,.items,.achievements,.createPet,.wellness,.settings]
    var sidebarGroup:Self {
        switch self {
        case .gallery,.season1,.season2,.originals,.collections:return .gallery
        case .reminders,.focus,.wellness:return .wellness
        case .items,.achievements,.createPet:return self
        default:return .settings
        }
    }
    var icon: String {
        switch self { case .settings:return "gearshape";case .wellness:return "heart";case .createPet:return "photo.badge.plus";case .collections:return "paintpalette";case .items:return "bag";case .achievements:return "trophy";case .season1,.season2,.originals:return "sparkles";case .about:return "info.circle";case .appearance: return "slider.horizontal.3"; case .dashboard: return "square.grid.2x2.fill"; case .general: return "pawprint"; case .gallery: return "square.grid.2x2"; case .features: return "leaf"; case .reminders: return "bell"; case .activity: return "sparkles"; case .focus: return "timer"; case .developer: return "terminal"; case .wallet: return "creditcard"; case .privacy: return "hand.raised" }
    }
}

struct SettingsView: View {
    private static var accessoryImages:[String:NSImage]=[:]
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var wallet: PetWalletService
    @ObservedObject var custom: CustomPetService
    @ObservedObject var focus: FocusTimer
    @ObservedObject var input: InputSupervisor
    @ObservedObject var activity: CompanionActivity
    @ObservedObject var wardrobe: PetWardrobe
    @ObservedObject var library:LibraryProgress
    @ObservedObject var sync:LibrarySyncService
    @ObservedObject var content:LibraryContentService
    @ViewState private var launchAtLogin=LoginLaunch.enabled
    @ViewState private var onboardingPage=0
    @ObservedObject var reminders: ReminderService
    private var section: SettingsSection { get { model.settingsSection } nonmutating set { model.settingsSection = newValue } }
    @ObservedObject var music: MusicReactionService
    @ObservedObject var windowEdges: WindowEdgeService
    @ViewState private var editingReminder: PetReminder?
    @ViewState private var email = ""
    @ViewState private var code = ""
    @ViewState private var dropTarget = false
    @ViewState private var choreTitle = ""
    @ViewState private var choreDue = Date().addingTimeInterval(3600)
    @ViewState private var choreDaily = false

    init(model: AppModel) {
        self.model = model; preferences = model.preferences; wallet = model.wallet
        custom = model.custom; focus = model.focus; input = model.input; activity = model.activity; wardrobe = model.wardrobe;library=model.library;sync=model.librarySync;content=model.libraryContent; reminders = model.reminders; music = model.music; windowEdges = model.windowEdges
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "pawprint.fill").font(.system(size: 25)).foregroundStyle(pawAccent)
                    Text("PawSync").font(.system(size: 23, weight: .bold, design: .rounded))
                }.padding(.bottom, 15).padding(.top, 22)
                ScrollView {
                    VStack(alignment:.leading,spacing:4) {
                        ForEach(SettingsSection.sidebar) { item in sidebarItem(item) }

                    }
                }.scrollIndicators(.hidden)
                VStack(alignment:.leading,spacing:10) {
                    if !library.state.gifts.isEmpty {Button {model.presentGifts=true} label:{Label("\(library.state.gifts.count) gifts waiting",systemImage:"gift.fill")}.buttonStyle(CozyButton(prominent:true))}
                    HStack {
                        if let image=PetStore.preview(preferences.companion){Image(nsImage:image).resizable().scaledToFit().frame(width:44,height:50)}
                        VStack(alignment:.leading,spacing:4){Text(model.petName(preferences.companion)).font(.system(size:11,weight:.semibold,design:.rounded)).lineLimit(1);Text("Keeping you company").font(.system(size:10)).foregroundStyle(LibraryStyle.muted)}
                    }
                }.padding(.bottom,20)
            }.padding(.horizontal,16).frame(width:202).background(LibraryStyle.paper)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.sidebarGroup.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(.top, 30)
                    if !model.notice.isEmpty { Label(model.notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    if !wallet.message.isEmpty, section != .wallet {
                        Label(wallet.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    if section.sidebarGroup == .settings {
                        Picker("Settings page",selection:Binding(get:{section == .settings ? SettingsSection.general:[SettingsSection.appearance,.features,.developer,.dashboard].contains(section) ? .appearance:section},set:{section=$0})) {
                            ForEach([SettingsSection.general,.activity,.wallet,.privacy,.about]) { Text($0.rawValue).tag($0) }
                            Text("Advanced").tag(SettingsSection.appearance)
                        }.pickerStyle(.menu).frame(maxWidth:240,alignment:.leading)
                        if [.appearance,.features,.developer,.dashboard].contains(section) {
                            Picker("Advanced page",selection:Binding(get:{section},set:{section=$0})) {
                                ForEach([SettingsSection.appearance,.features,.developer,.dashboard]) {Text($0.rawValue).tag($0)}
                            }.pickerStyle(.segmented)
                        }
                    }
                    if section.sidebarGroup == .wellness {
                        Picker("Wellness page",selection:Binding(get:{section == .wellness ? SettingsSection.reminders:section},set:{section=$0})) {
                            Text("Reminders").tag(SettingsSection.reminders);Text("Focus timer").tag(SettingsSection.focus)
                        }.pickerStyle(.segmented).frame(maxWidth:300)
                    }
                    switch section {
                    case .dashboard: DashboardView(model: model, catalog: model.catalog, input: input, focus: focus, reminders: reminders)
                    case .general,.settings: general
                    case .appearance: advancedAppearance
                    case .gallery: LibraryGalleryView(model:model,library:library,preferences:preferences)
                    case .createPet:
                        MakePetView(model:model,creator:model.photoCreator,custom:custom)
                        DisclosureGroup("Use PawSync generation credits instead") {customUpload.disabled(model.photoCreator.busy)}
                    case .collections:LibraryCollectionsView(model:model,library:library,wallet:wallet,preferences:preferences)
                    case .items: LibraryItemsView(model:model,library:library,wardrobe:wardrobe,preferences:preferences)
                    case .achievements: AchievementsView(library:library)
                    case .season1,.season2,.originals: LibraryGalleryView(model:model,library:library,preferences:preferences)
                    case .about: aboutContent
                    case .features:
                        NativeFeaturesView(model:model,features:model.features,countdown:model.countdown,daily:model.daily,care:model.care,resources:model.resources,practices:model.practices)
                        if model.fileInbox.hasEarlierCopies {
                            DisclosureGroup("Files saved by an earlier version") {
                                Text("The pocket now holds temporary references. Earlier saved copies remain available here so none of your files are lost.").font(.caption).foregroundStyle(.secondary)
                                Button("Show earlier copies in Finder") { model.fileInbox.showEarlierCopies() }
                            }
                        }
                    case .reminders,.wellness: remindersContent
                    case .activity: progressContent;activityContent
                    case .focus: focusContent
                    case .developer: developer
                    case .wallet: accountSyncContent;walletContent
                    case .privacy: privacy
                    }
                    Spacer(minLength: 20)
                }.padding(.horizontal, 30).frame(maxWidth: .infinity, alignment: .leading)
            }.background(LibraryStyle.cream)
        }.tint(LibraryStyle.purple).foregroundStyle(LibraryStyle.ink).preferredColorScheme(.light).frame(minWidth:940,minHeight:700)
        .onChange(of:model.quickAddReminder) { _,requested in
            guard requested else { return }
            editingReminder=PetReminder(id:UUID(),title:"",message:"",kind:"chore",enabled:true,intervalMinutes:nil,nextDue:Date().addingTimeInterval(3600))
            model.quickAddReminder=false
        }
        .sheet(isPresented:$model.presentItemEditor){ItemEditorView(model:model,preferences:preferences,store:model.presentation)}
        .sheet(isPresented:$model.presentGifts){GiftRevealView(model:model,library:library)}
        .sheet(isPresented: $model.onboarding) { onboarding }
        .sheet(item: $editingReminder) { item in ReminderEditor(reminder: item, service: reminders) }
    }
    private var subtitle: String {
        switch section {
        case .settings:return "A few simple choices, all in one place."
        case .wellness:return "Gentle reminders and a little time to focus."
        case .createPet:return "Turn a photo of your pet into a little desktop companion."
        case .collections:return "Original art, optional one-time collections."
        case .items:return "Little things to wear, collect, and love."
        case .achievements:return "Every small discovery deserves a smile."
        case .season1:return "Eleven friends. A little progress every day."
        case .season2:return "Twenty friends, from Sheep to Opossum."
        case .originals:return "Meet Knight Cat and our original desk buddies."
        case .about:return "Your little companion, cared for."
        case .appearance: return "Fine-tune movement, reactions and placement."
        case .dashboard: return "Your companion’s home base."
        case .general: return "Make a little space for your new desk companion."
        case .gallery: return "Discover a buddy, or bring one of your own."
        case .features: return "Little tools for gentler days."
        case .reminders: return "Friendly nudges from your desk buddy."
        case .activity: return "A little progress, a little celebration."
        case .focus: return "Work in gentle rhythms. Your companion keeps you company."
        case .developer: return "Let your pet celebrate the small wins in your workflow."
        case .wallet: return "Own it once. Create new companions when you want."
        case .privacy: return "Your typing stays yours. Always."
        }
    }
    private func sidebarItem(_ item:SettingsSection)->some View {
        Button { section=item } label: {
            HStack(spacing:8) {
                Image(systemName:item.icon).frame(width:18)
                Text(item.rawValue); Spacer(minLength:0)
            }.font(.system(size:13,weight:.medium))
                .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10)
                .foregroundStyle(section.sidebarGroup == item ? Color.white : LibraryStyle.ink)
                .background(section.sidebarGroup == item ? LibraryStyle.purple : Color.clear,in:RoundedRectangle(cornerRadius:9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var general:some View {
        VStack(alignment:.leading,spacing:20) {
            card {
                HStack(spacing:20) {
                    if let image=PetStore.preview(preferences.companion) { Image(nsImage:image).resizable().scaledToFit().frame(width:105,height:115) }
                    VStack(alignment:.leading,spacing:8) {
                        Text(model.petName(preferences.companion)).font(.title2.bold())
                        Text("A little company for your day.").foregroundStyle(.secondary)
                        Button("Choose a companion") { section = .gallery }
                    }; Spacer()
                }
                PetNameEditor(model:model,id:preferences.companion).id(preferences.companion)
                HStack {
                    Button("Say hello") { model.sayHello(manual:true) }
                    Button("Pet") { model.overlay.reactToPetting(direction:4) }
                    Button("Walk") {library.record("walk"); model.overlay.wanderNow() }
                    Button("Jump") {library.record("jump"); model.overlay.jumpNow() }
                }
                Text("Stroke your pet with a click and drag. Hold Option while dragging to move it.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Toggle("Show my companion",isOn:Binding(get:{!preferences.hidden},set:{preferences.hidden = !$0}))
                Picker("Size",selection:$preferences.petScale) {Text("Small").tag(0.65);Text("Medium").tag(1.0);Text("Large").tag(1.35)}.pickerStyle(.segmented).onChange(of:preferences.petScale){_,_ in library.record("resize")}
                Toggle("Mirror Mode · dock on the left",isOn:Binding(get:{preferences.mirrorDock},set:{model.mirrorMode($0)}))
                HStack{Text("Opacity");Slider(value:$preferences.petOpacity,in:0.2...1);Text("\(Int(preferences.petOpacity*100))%").font(.caption.monospacedDigit())}
                Toggle("Click-through",isOn:$preferences.clickThrough)
                Toggle("Little automatic cheers",isOn:Binding(get:{library.state.automaticCheers},set:{library.updateOptions(cheers:$0)}))
                Toggle("Open PawSync at login",isOn:$launchAtLogin).onChange(of:launchAtLogin){_,enabled in do{try LoginLaunch.set(enabled)}catch{launchAtLogin=LoginLaunch.enabled;model.notice=error.localizedDescription}}
                Text("Double-tap your pet for quick actions. Right-click for favorites and placement controls. Click-through can be turned off here or from the menu bar.").font(.caption).foregroundStyle(LibraryStyle.muted)
                Picker("Movement",selection:$preferences.movement) { ForEach(MovementMode.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("React to typing and clicks",isOn:Binding(get:{!preferences.reactionsPaused},set:{preferences.reactionsPaused = !$0}))
                if !input.running {
                    HStack { Text("Allow Input Monitoring to react to typing in other apps.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Enable typing") { input.requestPermission() } }
                }
                Toggle("Sound effects",isOn:Binding(get:{!preferences.muted},set:{preferences.muted = !$0}))
                Toggle("Dance to music",isOn:$preferences.musicReactive)
                if preferences.musicReactive { Text(music.status).font(.caption).foregroundStyle(.secondary) }
                if focus.phase == .focus { Label("Resting during your focus session",systemImage:"moon").font(.caption).foregroundStyle(pawAccent) }
            }
            card {
                Text("Dress up").font(.headline)
                Toggle("Show head accessories",isOn:$preferences.headAccessoriesVisible)
                Picker("Accessory",selection:Binding(get:{preferences.accessory},set:{sku in preferences.accessory=sku; preferences.headAccessoriesVisible=sku != "none" })) {
                    Text("None").tag("none")
                    ForEach(FreeHat.all.filter{wardrobe.ownedHats.contains($0.id)}) { Text($0.name).tag($0.id) }
                    ForEach(wallet.accessories,id:\.self) { Text($0 == "accessory.hat" ? "Top hat" : "Glasses").tag($0) }
                }
                if preferences.accessory != "none" { Button("Adjust item…") { model.presentItemEditor=true } }
                Text("Turn accessories off for bare ears, including while dancing.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("My wardrobe") { wardrobeContent }
            }
        }
    }
    private var builtInGallery:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("PawSync originals").font(.headline)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                ForEach(PetStore.imports.filter{$0.origin == "PawSync original"}) { pet in companionCard(model.petName(pet.id),id:pet.id,icon:"pawprint.fill",color:.orange) }
                ForEach(PetStore.rigIDs,id:\.self) { id in companionCard(model.petName(id),id:id,icon:"pawprint.fill",color:.orange) }
            }
            if !custom.customPets.isEmpty {
                Picker("Your custom pets",selection:$preferences.companion) {
                    Text("Choose a pet").tag(preferences.companion)
                    ForEach(custom.customPets,id:\.id) { Text(model.petName($0.id)).tag($0.id) }
                }
            }
        }
    }
    private var advancedAppearance:some View {
        VStack(alignment:.leading,spacing:18) {
            card {
                Toggle("Greet me when I return",isOn:$preferences.greetings)
                TextField("Your name (optional)",text:$preferences.userName)
                Picker("Screen anchor",selection:$preferences.anchor) { ForEach(ScreenAnchor.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Jump onto other windows",isOn:$preferences.edgeTraversal)
                if preferences.edgeTraversal { Text("Uses Accessibility to find the front window’s edges.").font(.caption).foregroundStyle(.secondary) }
                if preferences.musicReactive {
                    Toggle("Use Now Playing lite mode",isOn:$preferences.musicLite)
                    Text(music.status).font(.caption).foregroundStyle(.secondary)
                    Button("Recheck music access") { model.configureMusic(force:true) }
                }
                HStack { Button("Test typing") { model.overlay.previewTyping() }; Button("Test click") { model.overlay.previewClick() } }
                DisclosureGroup("Pet expressions") {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:95))],spacing:8) {
                        ForEach(PetEmotion.allCases) { emotion in Button(emotion.title) { model.overlay.showEmotion(emotion) } }
                    }.padding(.top,8)
                }
                if PetStore.rigIDs.contains(preferences.companion) {
                    Button("View character sheet") { if let url=Bundle.main.url(forResource:preferences.companion,withExtension:"png",subdirectory:"CharacterSheets") { NSWorkspace.shared.open(url) } }
                }
            }
            PresentationSettingsView(model:model,store:model.presentation,reactions:model.reactions,preferences:preferences,shortcuts:model.shortcuts)
        }
    }
    private func companionCard(_ name: String, id: String, icon: String, color: Color) -> some View {
        Button { preferences.companion = id } label: {
            VStack(spacing: 11) {
                if let image = PetStore.preview(id) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(height: 100)
                } else { Image(systemName: icon).font(.system(size: 43)).foregroundStyle(color.opacity(0.8)).frame(height: 100) }
                HStack { Text(name).font(.system(size: 13, weight: .semibold)); Spacer(); if preferences.companion == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(pawAccent) } }
                Text(id == "knight-cat" ? "Our main companion" : wardrobe.canSelectPet(id) ? "Desk buddy" : "Joins at level \(PetWardrobe.unlockLevels[id] ?? 1)").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(18).frame(maxWidth: .infinity).background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.companion == id ? pawAccent.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1.5))
        }.buttonStyle(.plain).disabled(!wardrobe.canSelectPet(id))
    }
    private var wardrobeContent: some View {
        card {
            Label("Your little wardrobe", systemImage: "gift").font(.headline)
            Text("Free hats drop when you level up, with no duplicates. Pets join at levels 1–6. Your previously available pets stay unlocked.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 12) {
                ForEach(FreeHat.all) { hat in
                    Button { preferences.accessory = hat.id; preferences.headAccessoriesVisible = true } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: accessoryPreview(hat.id)).resizable().scaledToFit().frame(width: 65, height: 56)
                            Text(hat.name).font(.caption.weight(.semibold))
                            Text(wardrobe.ownedHats.contains(hat.id) ? hat.rarity : "\(hat.rarity) · earn a drop").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(10).background(preferences.accessory == hat.id ? pawAccent.opacity(0.12) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(!wardrobe.ownedHats.contains(hat.id))
                    .onDrag { guard wardrobe.ownedHats.contains(hat.id) else { return NSItemProvider() }; model.overlay.beginHatDrag(); return NSItemProvider(object:hat.id as NSString) }
                }
            }
            HStack { Button("Bare ears") { preferences.accessory = "none"; preferences.headAccessoriesVisible = false }; Spacer(); Text("\(wardrobe.ownedHats.count) / \(FreeHat.all.count) collected").font(.caption).foregroundStyle(.secondary) }
            if !wardrobe.lastReward.isEmpty { Text("Latest treasures: \(wardrobe.lastReward)").font(.caption).foregroundStyle(pawAccent) }
            Text("Optional paid accessories are separate from earned hats and custom-pet credits. Listening headphones remain free while dancing.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func accessoryPreview(_ id: String) -> NSImage {
        if let cached=Self.accessoryImages[id] { return cached }
        let shapes = PetAccessories.make(id)?.children.compactMap { $0 as? SKShapeNode } ?? []
        let image = NSImage(size: NSSize(width: 90, height: 70), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: 45, y: 20)
            context.setLineJoin(.round)
            for shape in shapes {
                guard let path = shape.path else { continue }
                context.saveGState()
                context.translateBy(x: shape.position.x, y: shape.position.y)
                context.rotate(by: shape.zRotation)
                context.addPath(path)
                context.setFillColor(shape.fillColor.cgColor)
                context.setStrokeColor(shape.strokeColor.cgColor)
                context.setLineWidth(shape.lineWidth)
                context.drawPath(using: shape.lineWidth > 0 ? .fillStroke : .fill)
                context.restoreGState()
            }
            context.restoreGState()
            return true
        }
        Self.accessoryImages[id]=image
        return image
    }
    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                HStack { Text("Today’s gentle goal").font(.headline); Spacer(); Text("\(activity.snapshot.today) / \(preferences.dailyGoal)").font(.callout.monospacedDigit()).foregroundStyle(pawAccent) }
                ProgressView(value: min(1, Double(activity.snapshot.today) / Double(preferences.dailyGoal)))
                Stepper("Daily goal: \(preferences.dailyGoal) reactions", value: $preferences.dailyGoal, in: 100...20000, step: 100)
                Text("A reason to celebrate, never a quota. Goals reset each day.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                HStack { Label("All-time reactions", systemImage: "keyboard"); Spacer(); Text("\(activity.snapshot.total)").monospacedDigit() }
                HStack { Label("Completed focus sessions", systemImage: "timer"); Spacer(); Text("\(activity.snapshot.focusSessions)").monospacedDigit() }
                Text("Only totals are saved locally. No key identities, typed text, or individual event history are stored.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var remindersContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let active = reminders.active {
                card {
                    Label(active.title, systemImage: "bell.badge.fill").font(.headline)
                    Text(active.message).font(.callout)
                    HStack { Button("Done") { model.completeReminder() }.buttonStyle(.borderedProminent); Button("Snooze 10 min") { reminders.snooze() } }
                }
            }
            card {
                Text("Quick wellness presets").font(.headline)
                HStack {
                    ForEach(Array(ReminderService.presets.enumerated()), id: \.offset) { _, preset in
                        Button(preset.0 == "water" ? "Water" : preset.0 == "eyes" ? "Eye rest" : preset.0.capitalized) {
                            if let item = reminders.plan.reminders.first(where: { $0.kind == preset.0 }) { reminders.configure(item.id, enabled: true) }
                            else {
                                try? reminders.upsert(PetReminder(id: UUID(), title: preset.1, message: preset.2, kind: preset.0, enabled: true, intervalMinutes: preset.3, nextDue: Date().addingTimeInterval(Double(preset.3*60))))
                            }
                        }
                    }
                }
                HStack { Button("Preview water reminder") { reminders.showPreview() }; Button("Preview stretch reminder") { reminders.showPreview(kind: "stretch") } }
            }
            HStack {
                Text("Your reminders").font(.headline); Spacer()
                Button("Add reminder") { editingReminder = PetReminder(id: UUID(), title: "", message: "", kind: "chore", enabled: true, intervalMinutes: nil, nextDue: Date().addingTimeInterval(3600)) }.buttonStyle(.borderedProminent)
            }
            ForEach(reminders.plan.reminders) { item in
                card {
                    Toggle(item.title, isOn: Binding(get: { item.enabled }, set: { reminders.configure(item.id, enabled: $0) }))
                    Text(item.message).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(item.scheduleDescription).font(.caption)
                        if item.highPriority == true { Label("Priority", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(pawAccent) }
                        Spacer(); Button("Edit") { editingReminder = item }; Button("Delete", role: .destructive) { reminders.remove(item.id) }
                    }
                    if item.enabled { HStack { Text(item.snoozeUntil == nil ? "Next:" : "Snoozed until:"); Text(item.effectiveDue, style: .date); Text(item.effectiveDue, style: .time) }.font(.caption).foregroundStyle(.secondary) }
                }
            }
            card {
                Toggle("Quiet hours", isOn: Binding(get: { reminders.plan.quietHours }, set: { reminders.setQuiet(enabled: $0) }))
                if reminders.plan.quietHours {
                    HStack {
                        Picker("From", selection: Binding(get: { reminders.plan.quietStart }, set: { reminders.setQuiet(start: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                        Picker("Until", selection: Binding(get: { reminders.plan.quietEnd }, set: { reminders.setQuiet(end: $0) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    }
                }
                Toggle("Wait until my focus session ends", isOn: Binding(get: { reminders.plan.pauseDuringFocus }, set: { reminders.setQuiet(pauseFocus: $0) }))
                Text("Priority reminders can interrupt focus. Other overdue reminders wait for your next break. Quiet hours and screen sleep defer every reminder.").font(.caption).foregroundStyle(.secondary)
                Button("Enable system reminder notifications") { reminders.enableNotifications() }
                Text(reminders.notificationStatus).font(.caption).foregroundStyle(.secondary)
                Text("PawSync must be running. Pet bubbles dismiss after 12 seconds; click to dismiss or right-click to snooze for 10 minutes.").font(.caption).foregroundStyle(.secondary)
                if !reminders.message.isEmpty { Text(reminders.message).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var customUpload: some View {
        card {
            HStack { Text("Your pet, on your desktop").font(.headline); Spacer(); Text("\(wallet.credits) credits").font(.caption.weight(.semibold)).foregroundStyle(pawAccent) }
            Button { custom.choosePhoto() } label: {
                VStack(spacing: 9) {
                    if let image = custom.preview { Image(nsImage: image).resizable().scaledToFit().frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    else { Image(systemName: "photo.badge.plus").font(.system(size: 28)).foregroundStyle(pawAccent) }
                    Text(custom.selectedURL == nil ? "Drop a pet photo here, or choose a file" : custom.selectedURL!.lastPathComponent).font(.callout)
                    Text("JPEG, PNG or HEIC · up to 15 MB").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity).background(pawAccent.opacity(dropTarget ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).disabled(custom.busy)
            .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
                guard !custom.busy, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { custom.select(url) } }
                }; return true
            }
            if let error = custom.error { Text(error).font(.caption).foregroundStyle(.red) }
            if custom.busy { HStack { ProgressView().controlSize(.small); Text(custom.progress).font(.caption) } }
            HStack {
                Button(custom.error == nil ? "Create companion · 1 credit" : "Retry generation · 1 credit") { Task { await custom.generate() } }
                    .buttonStyle(.borderedProminent).disabled(custom.selectedURL == nil || custom.busy || !wallet.licensed || (wallet.credits == 0 && !custom.canRetry))
                Spacer()
                Button("Buy credits") { section = .wallet }
            }
            Text("Uploaded only when you create. Failed generations return your credit.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var focusContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 15) {
                Image(systemName: focus.phase == .focus ? "moon.zzz.fill" : "sun.max.fill").font(.system(size: 31)).foregroundStyle(pawAccent)
                Text(focus.phase == .ready ? String(format: "%02d:00", preferences.focusMinutes) : focus.display)
                    .font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                Text(focus.phase == .ready ? "A fresh start, whenever you’re ready." : focus.phase.rawValue).foregroundStyle(.secondary)
                if focus.phase != .ready { HStack { Button(focus.paused ? "Resume" : "Pause") { if focus.paused { focus.resume() } else { focus.pause() } }; if focus.phase == .focus { Button("Skip to break") { focus.skipToBreak() } } } }
                Button(focus.phase == .ready ? "Start focus session" : "End session") {
                    if focus.phase == .ready { focus.start() } else { focus.stop() }
                }.buttonStyle(.borderedProminent).disabled(!model.canUseApp)
            }.padding(30).frame(maxWidth: .infinity).background(pawAccent.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            card {
                Stepper("Focus interval: \(preferences.focusMinutes) minutes", value: $preferences.focusMinutes, in: 1...120)
                Stepper("Break interval: \(preferences.breakMinutes) minutes", value: $preferences.breakMinutes, in: 1...30)
                Text("Your companion rests during focus, then celebrates your break with a gentle chime. Sound follows your mute setting.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var developer: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                Toggle("Enable local status hooks", isOn: $preferences.integrations).disabled(!model.canUseApp)
                Text("Listens only on 127.0.0.1:9876. Every request needs your secret token. Limited to 10 requests per second.").font(.caption).foregroundStyle(.secondary)
                if preferences.integrations {
                    HStack { Label("POST /v1/status", systemImage: "network").font(.system(.caption, design: .monospaced)); Spacer(); Button("Regenerate token", role: .destructive) { model.regenerateWebhookToken() } }
                }
            }
            if let token = model.revealedToken {
                card {
                    Text("Save your token now").font(.headline)
                    Text("Shown once here. Regenerating it invalidates previous scripts.").font(.caption).foregroundStyle(.secondary)
                    Text(token).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack { Button("Copy token") { copy(token) }; Button("I’ve saved it") { model.revealedToken = nil } }
                }
            }
            card {
                Text("Git post-commit hook").font(.headline)
                Text("Set PAWSYNC_TOKEN in your shell, then add this to .git/hooks/post-commit.").font(.caption).foregroundStyle(.secondary)
                Text(hook).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Button("Copy hook") { copy(hook) }
            }
            card {
                Text("Terminal build status").font(.headline)
                Text("Use the included integrations/build-with-pet script around any build command. Successful builds get a flip; failed builds get a cardboard box.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var hook: String {
        "#!/bin/sh\n[ -n \"$PAWSYNC_TOKEN\" ] || exit 0\ncurl --max-time 2 -s -X POST \\\n  http://127.0.0.1:9876/v1/status \\\n  -H \"Authorization: Bearer $PAWSYNC_TOKEN\" \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"status\":\"build_success\"}' >/dev/null || true"
    }
    private var walletContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                HStack { Label(wallet.licensed ? "PawSync is yours" : "One purchase. A lifelong companion.", systemImage: "checkmark.seal").font(.headline); Spacer() }
                Text("The app includes the companion collection, reminders, focus tools, developer hooks, and 3 starter credits. Additional credits never expire. Accessories are separate purchases.").font(.callout).foregroundStyle(.secondary)
                HStack { if !wallet.licensed { Button("Buy PawSync") { wallet.checkout("base") }.buttonStyle(.borderedProminent) }; Button("Refresh license") { Task { await wallet.refresh() } } }
            }
            card {
                HStack { Text("Generation credits").font(.headline); Spacer(); Text("\(wallet.credits)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(pawAccent) }
                HStack { ForEach([5, 15, 40], id: \.self) { amount in Button("Add \(amount) credits") { wallet.checkout("credits.\(amount)") } } }
                Text("One successful companion costs one credit. Your balance is stored securely on the server.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Text("Restore your purchase").font(.headline)
                TextField("Email used at checkout", text: $email).textFieldStyle(.roundedBorder)
                Button("Email me a one-time code") { Task { await wallet.requestRestore(email: email) } }.disabled(wallet.busy || email.isEmpty)
                HStack { TextField("One-time code", text: $code).textFieldStyle(.roundedBorder); Button("Restore") { Task { await wallet.completeRestore(email: email, code: code) } }.disabled(wallet.busy || code.isEmpty) }
                if wallet.busy { ProgressView().controlSize(.small) }
                if !wallet.message.isEmpty { Text(wallet.message).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                Label("Binary reactions, private by design", systemImage: "lock.shield").font(.headline)
                Text("PawSync observes only that typing or a click happened. It never reads, stores, buffers or sends the keys you press. Mouse position is used locally to aim a brief animation.").font(.callout).foregroundStyle(.secondary)
                HStack { Label(input.running ? "Input Monitoring enabled" : "Input Monitoring needed", systemImage: input.running ? "checkmark.circle.fill" : "exclamationmark.circle"); Spacer() }.font(.callout)
                Text(input.status).font(.caption).foregroundStyle(.secondary)
                Text("Keyboard reactions: \(input.typingPulses) · Click reactions: \(input.clicks)").font(.caption.monospacedDigit())
                HStack { Button("Enable Input Monitoring") { input.requestPermission() }; Button("Open System Settings") { input.openPrivacySettings() }; Button("Recheck") { input.start() } }
                Text("macOS may require you to quit and reopen PawSync after granting permission. Accessibility is requested only when you enable window-edge jumping. Screen Recording is requested only for system-audio dancing. Both features start disabled.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Toggle("Share crash diagnostics", isOn: $preferences.telemetry)
                Text("Optional crash reports help fix bugs. Reports exclude input contents, user identity and automatic interaction breadcrumbs. No diagnostics are sent until you opt in.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Check for Updates…") { model.updates.check() }
        }
    }
    private var onboarding:some View {
        VStack(spacing:24) {
            HStack {ForEach(0..<3,id:\.self){i in Capsule().fill(i<=onboardingPage ? LibraryStyle.purple:LibraryStyle.purple.opacity(0.12)).frame(width:36,height:5)}}
            if let image=PetStore.preview("knight-cat"){Image(nsImage:image).resizable().scaledToFit().frame(height:130)}
            Text(["A little friend for your day","Your world stays yours","Let’s tap along"][onboardingPage]).font(.system(size:25,weight:.bold,design:.rounded))
            if onboardingPage==0 {Text("Your collection lives on this Mac. An account is optional for progress sync and purchases.").multilineTextAlignment(.center).foregroundStyle(LibraryStyle.muted)}
            else if onboardingPage==1 {Toggle("Share crash diagnostics (optional)",isOn:$preferences.telemetry);Text("Only aggregate activity totals are saved. No typed text, key identities, or captured audio is stored or sent.").font(.callout).foregroundStyle(LibraryStyle.muted)}
            else {Text("Input Monitoring lets your pet react to typing and clicks in other apps. Window jumps and music dancing ask for separate permissions only when enabled.").multilineTextAlignment(.center).foregroundStyle(LibraryStyle.muted);Button(input.running ? "Typing reactions are ready":"Enable Input Monitoring"){input.requestPermission()}.buttonStyle(CozyButton())}
            HStack {if onboardingPage>0{Button("Back"){onboardingPage-=1}.buttonStyle(CozyButton())};Spacer();Button(onboardingPage==2 ? "Make yourself at home":"Next"){if onboardingPage<2{onboardingPage+=1}else{model.finishOnboarding()}}.buttonStyle(CozyButton(prominent:true))}
            Text("You can change everything later in Settings.").font(.caption).foregroundStyle(LibraryStyle.muted)
        }.padding(34).frame(width:480).background(LibraryStyle.cream).foregroundStyle(LibraryStyle.ink)
    }
    private var progressContent:some View {
        card {
            LibraryXPStrip(library:library)
            Picker("Earn XP in",selection:Binding(get:{library.state.activeTrack},set:{library.earn(in:$0)})){ForEach(library.state.tracks){Text($0.name).tag($0.id)}}
            Toggle("XP follows my companion",isOn:Binding(get:{library.state.followsPet},set:{library.updateOptions(follows:$0)}))
            Text("Changing companions keeps XP in your chosen track. A fast typing/click rhythm earns 2× XP; only live activity earns it.").font(.caption).foregroundStyle(LibraryStyle.muted)
            if !library.state.gifts.isEmpty{GiftQueueBanner(model:model,library:library)}
        }
    }
    private var accountSyncContent:some View {
        card {
            Label("Progress that stays together",systemImage:"icloud").font(.headline)
            Toggle("Keep my Library in sync across Macs",isOn:Binding(get:{library.state.syncEnabled},set:{sync.setEnabled($0)}))
            Text(sync.status).font(.callout).foregroundStyle(LibraryStyle.muted)
            if library.state.syncEnabled {Button(sync.busy ? "Syncing…":"Sync now"){Task{await sync.sync()}}.disabled(sync.busy)}
            Text("Sync combines owned items, companions, achievements, and the higher level of each track. Copies are kept in Backups. No app restart is needed.").font(.caption).foregroundStyle(LibraryStyle.muted)
            Toggle("Get new items and cheers without an app update",isOn:$content.enabled)
            Text(content.status).font(.caption).foregroundStyle(LibraryStyle.muted)
            if content.enabled{Button("Refresh content"){Task{await content.refresh()}}.disabled(content.busy)}
            Button("Show local backups"){NSWorkspace.shared.open(PetStore.root.appendingPathComponent("Backups"))}
        }
    }
    @ViewBuilder private var aboutContent:some View {
        card {
            Text("PawSync").font(.system(size:28,weight:.bold,design:.rounded));Text("A little company. A lighter day.").foregroundStyle(LibraryStyle.muted)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0")").font(.caption).foregroundStyle(LibraryStyle.muted)
            Text("47 companions · \(FreeHat.all.count) free items · 30 achievements · 7 secrets").font(.callout)
            Button("Check for Updates…"){model.updates.check()}.buttonStyle(CozyButton(prominent:true))
            Text("Your signed release feed provides automatic update checks. This local development build does not have a live release feed.").font(.caption).foregroundStyle(LibraryStyle.muted)
        }
        card {
            Text("A fresh start, when you want one").font(.headline)
            Text("Reset earned Library progress, gifts and achievements. Your purchases, companion settings, photo pets and files are kept. A backup is saved first. If sync is enabled, your account resets too.").font(.callout).foregroundStyle(LibraryStyle.muted)
            Button("Reset Progress…"){model.confirmProgressReset()}.buttonStyle(CozyButton())
            DisclosureGroup("Reset local preferences too") {
                Text("This also clears local reminders, aggregate input counters, layout and privacy choices, then reopens setup. Photos and purchases remain backed up or retained.").font(.caption).foregroundStyle(LibraryStyle.muted)
                Button("Reset Local Everything…"){model.confirmResetEverything()}.buttonStyle(CozyButton())
            }
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LibraryStyle.paper,in:RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(LibraryStyle.purple.opacity(0.09)))
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
