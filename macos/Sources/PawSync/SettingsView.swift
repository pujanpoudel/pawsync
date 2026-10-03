import SwiftUI
import AppKit
import SpriteKit
import UniformTypeIdentifiers

private let pawAccent = Color(red: 0.45, green: 0.36, blue: 0.72)
// Avoid the newer same-name State macro when building with the standalone SDK.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance", dashboard = "Overview", general = "Companion", gallery = "Pet gallery", features = "Companion tools", reminders = "Reminders", activity = "Activity", focus = "Focus & habits", developer = "Developer", wallet = "License & credits", privacy = "Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self { case .appearance: return "slider.horizontal.3"; case .dashboard: return "square.grid.2x2.fill"; case .general: return "pawprint"; case .gallery: return "square.grid.2x2"; case .features: return "leaf"; case .reminders: return "bell"; case .activity: return "sparkles"; case .focus: return "timer"; case .developer: return "terminal"; case .wallet: return "creditcard"; case .privacy: return "hand.raised" }
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
    @ObservedObject var reminders: ReminderService
    private var section: SettingsSection { get { model.settingsSection } nonmutating set { model.settingsSection = newValue } }
    @ObservedObject var music: MusicReactionService
    @ObservedObject var windowEdges: WindowEdgeService
    @ViewState private var advancedExpanded = false
    @ViewState private var editingReminder: PetReminder?
    @ViewState private var email = ""
    @ViewState private var code = ""
    @ViewState private var dropTarget = false
    @ViewState private var choreTitle = ""
    @ViewState private var choreDue = Date().addingTimeInterval(3600)
    @ViewState private var choreDaily = false

    init(model: AppModel) {
        self.model = model; preferences = model.preferences; wallet = model.wallet
        custom = model.custom; focus = model.focus; input = model.input; activity = model.activity; wardrobe = model.wardrobe; reminders = model.reminders; music = model.music; windowEdges = model.windowEdges
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "pawprint.fill").font(.system(size: 25)).foregroundStyle(pawAccent)
                    Text("PawSync").font(.system(size: 23, weight: .bold, design: .rounded))
                }.padding(.bottom, 27).padding(.top, 26)
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach([SettingsSection.general,.gallery,.reminders,.focus]) { item in sidebarItem(item) }
                        Divider().padding(.vertical,10)
                        DisclosureGroup("Advanced",isExpanded:$advancedExpanded) {
                            ForEach([SettingsSection.appearance,.features,.activity,.developer,.privacy,.wallet,.dashboard]) { item in sidebarItem(item) }
                        }.font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                    }
                }.scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: 6) {
                    Label(wallet.licensed ? "License active" : (model.configuration.environment == "development" ? "Development preview" : "Companion preview"), systemImage: wallet.licensed ? "checkmark.seal.fill" : "sparkles")
                        .font(.caption.weight(.medium)).foregroundStyle(pawAccent)
                    Text("A little company. A lighter day.").font(.caption2).foregroundStyle(.secondary)
                    Text("Version 0.1.0").font(.caption2).foregroundStyle(.tertiary)
                }.padding(.bottom, 20)
            }.padding(.horizontal, 18).frame(width: 186).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(.top, 30)
                    if !model.notice.isEmpty { Label(model.notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    if !wallet.message.isEmpty, section != .wallet {
                        Label(wallet.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    switch section {
                    case .dashboard: DashboardView(model: model, catalog: model.catalog, input: input, focus: focus, reminders: reminders)
                    case .general: general
                    case .appearance: advancedAppearance
                    case .gallery: builtInGallery; PetGalleryView(model: model, catalog: model.catalog, preferences: preferences); DisclosureGroup("Create a pet from a photo") { customUpload }
                    case .features:
                        NativeFeaturesView(model:model,features:model.features,countdown:model.countdown,daily:model.daily,care:model.care,resources:model.resources,practices:model.practices)
                        if model.fileInbox.hasEarlierCopies {
                            DisclosureGroup("Files saved by an earlier version") {
                                Text("The pocket now holds temporary references. Earlier saved copies remain available here so none of your files are lost.").font(.caption).foregroundStyle(.secondary)
                                Button("Show earlier copies in Finder") { model.fileInbox.showEarlierCopies() }
                            }
                        }
                    case .reminders: remindersContent
                    case .activity: activityContent
                    case .focus: focusContent
                    case .developer: developer
                    case .wallet: walletContent
                    case .privacy: privacy
                    }
                    Spacer(minLength: 20)
                }.padding(.horizontal, 30).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .controlBackgroundColor))
        }.tint(pawAccent).frame(minWidth: 790, minHeight: 610)
        .onAppear { advancedExpanded = ![SettingsSection.general,.gallery,.reminders,.focus].contains(section) }
        .onChange(of:section) { _,value in if ![SettingsSection.general,.gallery,.reminders,.focus].contains(value) { advancedExpanded=true } }
        .onChange(of:model.quickAddReminder) { _,requested in
            guard requested else { return }
            editingReminder=PetReminder(id:UUID(),title:"",message:"",kind:"chore",enabled:true,intervalMinutes:nil,nextDue:Date().addingTimeInterval(3600))
            model.quickAddReminder=false
        }
        .sheet(isPresented: $model.onboarding) { onboarding }
        .sheet(item: $editingReminder) { item in ReminderEditor(reminder: item, service: reminders) }
    }
    private var subtitle: String {
        switch section {
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
                .foregroundStyle(section == item ? pawAccent : Color.primary)
                .background(section == item ? pawAccent.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var general:some View {
        VStack(alignment:.leading,spacing:20) {
            card {
                HStack(spacing:20) {
                    if let image=PetStore.preview(preferences.companion) { Image(nsImage:image).resizable().scaledToFit().frame(width:105,height:115) }
                    VStack(alignment:.leading,spacing:8) {
                        Text(preferences.nickname.isEmpty ? PetStore.builtInNames[preferences.companion] ?? "Your companion" : preferences.nickname).font(.title2.bold())
                        Text("A little company for your day.").foregroundStyle(.secondary)
                        Button("Choose a companion") { section = .gallery }
                    }; Spacer()
                }
                HStack {
                    Button("Say hello") { model.sayHello(manual:true) }
                    Button("Pet") { model.overlay.reactToPetting(direction:4) }
                    Button("Walk") { model.overlay.wanderNow() }
                    Button("Jump") { model.overlay.jumpNow() }
                }
                Text("Stroke your pet with a click and drag. Hold Option while dragging to move it.").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Toggle("Show my companion",isOn:Binding(get:{!preferences.hidden},set:{preferences.hidden = !$0}))
                HStack { Text("Size"); Slider(value:$preferences.petScale,in:0.4...1.8); Text("\(Int(preferences.petScale*100))%").monospacedDigit().frame(width:45) }
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
                Picker("Accessory",selection:Binding(get:{preferences.accessory},set:{sku in preferences.accessory=sku; preferences.headAccessoriesVisible=sku != "none"; model.presentation.state.hats[preferences.companion]=HatTransform() })) {
                    Text("None").tag("none")
                    ForEach(FreeHat.all.filter{wardrobe.ownedHats.contains($0.id)}) { Text($0.name).tag($0.id) }
                    ForEach(wallet.accessories,id:\.self) { Text($0 == "accessory.hat" ? "Top hat" : "Glasses").tag($0) }
                }
                if preferences.accessory != "none" { Button("Recenter on my pet") { model.presentation.state.hats[preferences.companion]=HatTransform() } }
                Text("Turn accessories off for bare ears, including while dancing.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("My wardrobe") { wardrobeContent }
            }
        }
    }
    private var builtInGallery:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("PawSync originals").font(.headline)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                ForEach(PetStore.rigIDs,id:\.self) { id in companionCard(PetStore.rigNames[id]!,id:id,icon:"pawprint.fill",color:.orange) }
            }
            if !custom.customPets.isEmpty {
                Picker("Your custom pets",selection:$preferences.companion) {
                    Text("Choose a pet").tag(preferences.companion)
                    ForEach(custom.customPets,id:\.id) { Text($0.name).tag($0.id) }
                }
            }
        }
    }
    private var advancedAppearance:some View {
        VStack(alignment:.leading,spacing:18) {
            card {
                TextField("Pet nickname",text:$preferences.nickname)
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
                Text(wardrobe.canSelectPet(id) ? "Desk buddy" : "Joins at level \(PetWardrobe.unlockLevels[id] ?? 1)").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
                    Button { preferences.accessory = hat.id; preferences.headAccessoriesVisible = true; model.presentation.state.hats[preferences.companion]=HatTransform() } label: {
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
                HStack { Image(systemName: "sparkles").font(.title).foregroundStyle(pawAccent); VStack(alignment: .leading) { Text("Level \(activity.level)").font(.title2.bold()); Text("\(activity.snapshot.total % 500) / 500 to the next level").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                ProgressView(value: activity.progress).tint(pawAccent)
                Text("Every typing or click event adds a little progress. Your companion celebrates each new level.").font(.caption).foregroundStyle(.secondary)
            }
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
    private var onboarding: some View {
        VStack(spacing: 22) {
            Image(systemName: "pawprint.fill").font(.system(size: 62)).foregroundStyle(pawAccent).padding(.top, 15)
            Text("Meet your new desk companion.").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("A tiny friend for your workday. Tap along, take a breath,\nand celebrate a little progress.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Label("Input Monitoring makes typing and click reactions work.", systemImage: "keyboard")
                Text("Only the fact that input happened is used. PawSync never reads your keystrokes. Window-edge jumping and music reactions ask for their own permissions only when enabled.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Enable Input Monitoring") { input.requestPermission() }; if input.running { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                Divider()
                Toggle("Share anonymous crash diagnostics (optional)", isOn: $preferences.telemetry)
            }.padding(20).background(pawAccent.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            Button("Make yourself at home") { model.finishOnboarding() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("You can change all of this later in Settings.").font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(width: 490).tint(pawAccent)
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.06)))
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
