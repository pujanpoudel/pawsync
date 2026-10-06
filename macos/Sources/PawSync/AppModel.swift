import AppKit
import Combine

@MainActor final class AppModel: NSObject, ObservableObject {
    let preferences = Preferences()
    let input = InputSupervisor()
    let activity = CompanionActivity()
    let wardrobe = PetWardrobe(preserveExistingPets: UserDefaults.standard.bool(forKey: "onboarded"))
    let library:LibraryProgress
    let librarySync:LibrarySyncService
    let libraryContent:LibraryContentService
    @Published var presentItemEditor=false
    private let libraryToast=LibraryToast()
    @Published var presentGifts=false
    private var cheerTimer:Timer?
    private var lastCheer=Date.distantPast
    private var hiddenUntil:DispatchWorkItem?
    let catalog = PetCatalogService()
    let reactions = ReactionSettings()
    let presentation = PetPresentationStore()
    let shortcuts = HotkeyService()
    let features = NativeFeatureRegistry()
    let countdown = CountdownService()
    let practices = PracticeService()
    let hud = PinnedHUD()
    let daily:DailyCompanionService
    let care:VirtualCareService
    let resources:ResourceMonitor
    let reminders = ReminderService()
    let speech = CompanionSpeech()
    let fileInbox:PetFileInbox
    let fileShelf:PetFileShelfController
    private var quickActions:PetQuickActionsController!
    let windowEdges = WindowEdgeService()
    let music = MusicReactionService()
    @Published var settingsSection: SettingsSection = .gallery
    @Published var quickAddReminder=false
    private var audioConfiguration = ""
    let configuration = AppConfiguration.load()
    let updates = UpdateService()
    let server = LocalWebhookServer()
    let overlay: OverlayController
    let focus: FocusTimer
    let api: APIClient
    let wallet: PetWalletService
    let custom: CustomPetService
    let photoCreator=PhotoPetCreator()
    @Published var notice = ""
    @Published var revealedToken: String?
    @Published var onboarding: Bool
    private var shutdownComplete=false
    private var subscriptions = Set<AnyCancellable>()
    private var validationTimer: Timer?
    private var trialTimer: Timer?
    var openSettings: (() -> Void)?
    var canUseApp: Bool { wallet.licensed || configuration.environment == "development" }

    override init() {
        let fileInbox=PetFileInbox()
        self.fileInbox=fileInbox
        fileShelf=PetFileShelfController(inbox:fileInbox)
        overlay = OverlayController(preferences: preferences)
        focus = FocusTimer(preferences: preferences)
        api = APIClient(config: configuration)
        wallet = PetWalletService(api: api)
        libraryContent=LibraryContentService(api:api)
        library=LibraryProgress(wardrobe:wardrobe,legacyXP:activity.snapshot.total,preservePets:preferences.onboarded ? PetStore.builtInIDs:[])
        librarySync=LibrarySyncService(library:library,api:api)
        custom = CustomPetService(api: api, wallet: wallet)
        daily=DailyCompanionService(features:features)
        care=VirtualCareService(features:features)
        resources=ResourceMonitor(features:features)
        onboarding = !preferences.onboarded
        super.init()
        if !preferences.nickname.isEmpty {
            if presentation.name(for:preferences.companion) != nil || presentation.setName(preferences.nickname,for:preferences.companion) {preferences.nickname=""}
        }
        overlay.companionName = { [weak self] in
            guard let self else{return "Buddy"}
            return self.presentation.name(for:self.preferences.companion) ?? self.originalPetName(self.preferences.companion).components(separatedBy:" the ").first ?? "Buddy"
        }
        presentation.$state.map(\.names).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {guard let self else{return};self.objectWillChange.send();self.updateCaption()}
        }.store(in:&subscriptions)
        fileInbox.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return };self.overlay.setHeldFileCount(self.fileInbox.files.count) }
        }.store(in:&subscriptions)
        quickActions=PetQuickActionsController { [weak self] id in
            guard let self else { return }
            switch id {
            case "water": self.menuWater()
            case "reminder": self.menuAddReminder()
            case "focus": self.focus.phase == .ready ? self.menuFocus() : self.menuStopFocus()
            case "walk": self.menuWalk()
            case "files":
                if self.fileInbox.files.isEmpty { self.speech.show(title:"My paws are free!",text:"Drop a file on me for a temporary helping paw. Hover over my pocket, then drag it out. Your original stays put.") }
                else { self.overlay.stopWalking();self.fileShelf.show(near:self.overlay.window) }
            case "hello": self.menuHello()
            default: break
            }
        }
        quickActions.attachment = { [weak self] in self?.overlay.chromeAnchor ?? .unattached }
        fileShelf.attachment = { [weak self] in self?.overlay.chromeAnchor ?? .unattached }
        speech.attachment = { [weak self] in self?.overlay.chromeAnchor ?? .unattached }
        overlay.showSettings = { [weak self] in self?.openSettings?() }
        overlay.shouldTemporarilyHide = { [weak self] in
            guard let self,let id=NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
            return self.presentation.state.hideInApps.contains(id)
        }
        overlay.reactionSettings = reactions
        overlay.movementSettings = presentation
        overlay.restorePresentation = { [weak self] in self?.applyPresentation() }
        shortcuts.onToggle = { [weak self] in self?.preferences.hidden.toggle() }
        overlay.makeContextMenu = { [weak self] in self?.petContextMenu() ?? NSMenu() }
        overlay.showQuickActions = { [weak self] in
            guard let self else { return }
            if self.quickActions.isVisible { self.quickActions.dismiss();return }
            self.fileShelf.dismiss()
            if self.speech.isReminder { self.speech.onAutoDismiss?() }
            self.speech.dismiss()
            self.overlay.stopWalking()
            self.quickActions.show(near:self.overlay.window)
        }
        fileShelf.attach(to:overlay.window)
        overlay.showFileShelf = { [weak self] in guard let self,!self.speech.isVisible,!self.quickActions.isVisible,!self.fileInbox.files.isEmpty else { return };self.overlay.stopWalking();self.fileShelf.show(near:self.overlay.window) }
        overlay.companionUIActive = { [weak self] in self?.quickActions.isVisible == true || self?.fileShelf.isVisible == true || self?.speech.isVisible == true }
        overlay.storedFileCount = { [weak self] in self?.fileInbox.files.count ?? 0 }
        overlay.showDropTarget = { [weak self] in guard let self else { return };self.quickActions.dismiss();self.fileShelf.showDropTarget(near:self.overlay.window) }
        overlay.hideDropTarget = { [weak self] in self?.fileShelf.hideDropTarget() }
        overlay.canAcceptFiles = { [weak self] urls in self?.fileInbox.canAcceptDrop(urls) ?? false }
        overlay.onFileDrop = { [weak self] urls in
            guard let self,self.canUseApp else { return false }
            do {
                let count=try self.fileInbox.catchFiles(urls)
                self.library.record("catch")
                self.overlay.catchFiles(count:count)
                self.fileShelf.show(near:self.overlay.window)
                return true
            } catch { self.notice=error.localizedDescription;return false }
        }
        fileShelf.onFileDrop = { [weak self] urls in self?.overlay.onFileDrop?(urls) ?? false }
        fileShelf.onReceivingFiles = { [weak self] active in self?.overlay.setDropHighlight(active) }
        daily.canDeliver = { [weak self] in self?.canDeliverCompanionMessage ?? false }
        daily.greetingsEnabled = { [weak self] in self?.preferences.greetings ?? false }
        daily.onMessage = { [weak self] _,title,text,reaction in
            guard let self,self.canDeliverCompanionMessage else { return false }
            self.overlay.react(reaction); return self.speech.show(title:title,text:text)
        }
        daily.onMoodCheck = { [weak self] in
            guard let self,self.canDeliverCompanionMessage else { return false }
            return self.speech.show(title:"How’s your little world?",text:"You can keep a private check-in with your buddy.",actions:[SpeechAction(id:"check-in",title:"Check in",icon:"heart",action:{ [weak self] in self?.settingsSection = .features; self?.openSettings?(); self?.speech.dismiss() })])
        }
        countdown.onExpired = { [weak self] label in
            guard let self,self.features.contains("openpets.simple-timer"),!self.overlay.focusSleeping,!self.overlay.isScreenSleeping else { return false }
            if self.overlay.isHidden { return self.reminders.notify(title:"Time’s up, buddy!",message:label,id:"pawsync.timer.\(self.countdown.state.id)") }
            guard self.canDeliverCompanionMessage else { return false }
            if !self.preferences.muted { NSSound(named:"Glass")?.play() }
            self.overlay.wave()
            return self.speech.show(title:"Time’s up, buddy!",text:label,actions:[
                SpeechAction(id:"snooze",title:"5 more min",icon:"moon",action:{ [weak self] in self?.countdown.snooze(); self?.speech.dismiss() }),
                SpeechAction(id:"done",title:"All done",icon:"checkmark",action:{ [weak self] in self?.countdown.cancel(); self?.speech.dismiss() })])
        }
        care.onCare = { [weak self] action in
            guard let self else { return }
            self.overlay.careSleeping=action == "nap"
            if action == "play" { self.overlay.celebrate() }
            else if action == "pet" { self.overlay.reactToPetting(direction:5) }
            else if action != "nap" { self.overlay.wave() }
        }
        resources.onWarning = { [weak self] text in guard let self,self.canDeliverCompanionMessage else { return }; self.speech.show(title:"A little breather?",text:text) }
        practices.onEnded = { [weak self] in guard let self,self.canDeliverCompanionMessage else { return }; self.speech.show(title:"A little moment, just for you",text:"Thanks for taking a gentle pause with me."); self.overlay.wave() }
        overlay.onHatDrop = { [weak self] id,point in
            guard let self, self.canEquipAccessory(id), self.overlay.pet != nil else { return false }
            self.preferences.accessory=id; self.preferences.headAccessoriesVisible=true
            self.applyPresentation(accessory:id); return true
        }
        speech.attach(to: overlay.window)
        hud.attach(to:overlay.window)
        speech.onVisibility = { [weak self] visible in if visible { self?.quickActions.dismiss();self?.fileShelf.dismiss();self?.overlay.stopWalking() };self?.hud.setSuspended(visible || self?.overlay.isHidden == true || self?.overlay.isScreenSleeping == true) }
        speech.onDone = { [weak self] in self?.completeReminder() }
        speech.onAutoDismiss = { [weak self] in self?.reminders.complete() }
        speech.onSnooze = { [weak self] in self?.reminders.snooze() }
        reminders.isSuspended = { [weak self] in
            guard let self else { return true }
            return self.overlay.isScreenSleeping || !self.canUseApp || !self.features.contains("openpets.reminders")
        }
        reminders.isReminderSuppressed = { [weak self] reminder in reminder.kind == "water" && self?.daily.state.pausedDays["water"] == DailyCompanionService.day(Date()) }
        reminders.isFocusActive = { [weak self] in self?.focus.phase == .focus && self?.focus.paused == false }
        reminders.needsSystemNotification = { [weak self] in
            guard let self else { return false }
            return self.overlay.isHidden || NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        overlay.windowEdge = { [weak self] in
            guard let self, self.preferences.edgeTraversal else { return nil }
            return self.windowEdges.focusedFrame()
        }
        music.onSignal = { [weak self] audible, beat in if audible,self?.library.state.counters["dance"] == nil {self?.library.record("dance")};self?.overlay.musicSignal(audible, beat: beat) }
        overlay.onVisibilityChanged = { [weak self] in
            self?.configureMusic()
            self?.resources.suspended = self?.overlay.isScreenSleeping == true || self?.overlay.isHidden == true
            self?.hud.setSuspended(self?.speech.isVisible == true || self?.overlay.isScreenSleeping == true || self?.overlay.isHidden == true)
            if self?.overlay.isScreenSleeping == true || self?.overlay.isHidden == true { self?.practices.pause(); self?.speech.dismiss() }
        }
        overlay.onReminderDismiss = { [weak self] in
            guard let self, self.reminders.active != nil else { return false }
            self.completeReminder(); return true
        }
        reminders.onReminder = { [weak self] reminder in
            guard let self else { return }
            if self.overlay.isHidden { self.reminders.complete(); return }
            self.overlay.canRoam = false
            self.overlay.deliverReminder(reminder) { [weak self] in
                guard let self, self.reminders.active?.id == reminder.id else { return }
                self.speech.show(title: reminder.title, text: reminder.message, reminder: true)
                if !self.preferences.muted { NSSound(named: "Pop")?.play() }
            }
        }
        reminders.onCleared = { [weak self] in self?.speech.dismiss(); self?.overlay.finishReminder() }
        overlay.onWake = { [weak self] in self?.daily.tick() }
        overlay.onPetWake = { [weak self] in
            guard let self else { return }
            self.care.wake()
            self.overlay.careSleeping = false
        }
        overlay.onPetting = { [weak self] in
            guard let self else { return }; self.library.record("pet");self.care.care("pet"); if !self.preferences.muted { self.playSound("meow") }
        }
        custom.onInstalled = { [weak self] id in self?.preferences.companion = id }
        photoCreator.onInstalled = { [weak self] id in
            self?.custom.reloadPets();self?.catalog.reloadInstalled()
            self?.preferences.companion=id;self?.settingsSection = .gallery
        }
        catalog.onInstalled = { [weak self] id in self?.preferences.companion = id }
        catalog.onRemoved = { [weak self] id in
            guard let self else { return }; if self.preferences.companion == id { self.preferences.companion = "openpets-default" }
        }
        input.onTyping = { [weak self] in
            guard let self, self.canUseApp else { return }
            self.activity.record(goal: self.preferences.dailyGoal)
            self.overlay.typing()
            if !self.preferences.muted, !self.preferences.reactionsPaused { self.playSound("tap") }
        }
        input.onClick = { [weak self] point in
            guard let self, self.canUseApp else { return }
            self.activity.record(goal: self.preferences.dailyGoal)
            self.overlay.click(at: point)
        }
        input.onPointer = { [weak self] in self?.overlay.updatePassThrough() }
        focus.onFocusChanged = { [weak self] value in
            guard let self else { return }
            self.overlay.focusSleeping=value && self.features.contains("openpets.focus-buddy")
        }
        focus.onCelebration = { [weak self] in self?.activity.completedFocus();self?.library.record("focus"); self?.overlay.celebrate() }
        activity.onInput={ [weak self] in self?.library.registerInput() }
        activity.onLevelUp=nil
        activity.onGoalReached={ [weak self] in self?.overlay.celebrate() }
        library.onAchievement={ [weak self] a in self?.libraryToast.show(a.title,subtitle:"Achievement discovered",icon:a.icon) }
        library.onUnlock={ [weak self] ids in
            guard let self else{return}
            self.notice="New friends: "+ids.map{self.petName($0)}.joined(separator:", ")
            self.overlay.celebrate()
            if !self.overlay.isHidden,!self.overlay.isScreenSleeping {self.libraryToast.show("A new little friend",subtitle:self.notice,icon:"pawprint.fill")}
        }
        library.onSecret={ [weak self] title in self?.overlay.celebrate();self?.libraryToast.show(title,subtitle:"Secret combination discovered",icon:"wand.and.stars") }
        library.ownsCollection={ [weak self] sku in self?.wallet.accessories.contains(sku)==true }
        libraryContent.ownedSKUs={ [weak self] in self?.wallet.accessories ?? [] }
        libraryContent.onInstalled={ [weak self] in self?.catalog.reloadInstalled();self?.library.reconcileCollections() }
        library.reconcileCollections()
        librarySync.onMerged={ [weak self] snapshot in
            guard let self else{return};for (pet,hat) in snapshot.placements where pet.contains("::") && self.presentation.state.hats[pet]==nil {self.presentation.state.hats[pet]=hat}
        }
        library.onChanged={ [weak self] in self?.librarySync.changed() }
        overlay.onDirectClick={ [weak self] in self?.cheer(manual:true) }
        cheerTimer=Timer.scheduledTimer(withTimeInterval:90,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.library.coolDown();self?.cheer() } };cheerTimer?.tolerance=15
        server.onStatus = { [weak self] status in
            DispatchQueue.main.async { guard let self, self.canUseApp else { return }; self.overlay.integration(status) }
        }
        server.onError = { [weak self] message in
            DispatchQueue.main.async { self?.notice = message; self?.preferences.integrations = false }
        }
        preferences.$companion.dropFirst().sink { [weak self] id in self?.loadPet(id) }.store(in: &subscriptions)
        preferences.$muted.removeDuplicates().sink { [weak self] muted in self?.practices.muted=muted }.store(in:&subscriptions)
        features.$enabled.dropFirst().sink { [weak self] enabled in
            guard let self else { return }
            if !enabled.contains("openpets.anxiety-aid-tools") { self.practices.stop() }
            if !enabled.contains("openpets.simple-timer") { self.countdown.pause() }
            if !enabled.contains("openpets.virtual-pet") { self.overlay.careSleeping=false }
            if !enabled.contains("openpets.reminders") { self.reminders.deferActive() }
            self.overlay.focusSleeping=self.focus.phase == .focus && !self.focus.paused && enabled.contains("openpets.focus-buddy")
            self.refreshHUD()
        }.store(in:&subscriptions)
        countdown.$remaining.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        countdown.$state.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        focus.$remaining.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        focus.$phase.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        focus.$paused.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        care.$needs.sink { [weak self] _ in DispatchQueue.main.async { guard let self else { return }; self.overlay.careSleeping=self.features.contains("openpets.virtual-pet") && self.care.needs.asleepUntil.map{$0 > Date()} == true; self.refreshHUD() } }.store(in:&subscriptions)
        resources.$sample.sink { [weak self] _ in DispatchQueue.main.async { self?.refreshHUD() } }.store(in:&subscriptions)
        presentation.$state.map(\.hideInApps).removeDuplicates().dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.overlay.reposition() } }.store(in:&subscriptions)
        preferences.$anchor.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.overlay.reposition() }
        }.store(in: &subscriptions)
        preferences.$hidden.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.overlay.reposition() }
        }.store(in: &subscriptions)
        preferences.$integrations.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.configureServer() }
        }.store(in: &subscriptions)
        preferences.$telemetry.removeDuplicates().sink { [weak self] value in
            guard let self else { return }; Diagnostics.configure(enabled: value, configuration: self.configuration)
        }.store(in: &subscriptions)
        preferences.$accessory.dropFirst().sink { [weak self] sku in
            guard let self else { return }
            self.overlay.animate(for: 0.3)
            self.overlay.pet?.setAccessory(self.canEquipAccessory(sku) ? sku : "none")
            if sku != "none",self.canEquipAccessory(sku) {self.library.record("dress");self.library.pairing(pet:self.preferences.companion,hat:sku)}
            self.applyPresentation(accessory:sku)
        }.store(in: &subscriptions)
        preferences.$headAccessoriesVisible.dropFirst().sink { [weak self] visible in
            self?.overlay.pet?.setAccessoryVisibility(visible)
            self?.overlay.animate(for:0.3)
        }.store(in: &subscriptions)
        presentation.$state.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyPresentation() } }.store(in:&subscriptions)
        wallet.$licensed.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.licenseChanged() }
        }.store(in: &subscriptions)
        input.$running.sink { [weak self] running in self?.overlay.setInputMonitoring(running) }.store(in: &subscriptions)
        preferences.$petScale.dropFirst().sink { [weak self] value in self?.overlay.setScale(value) }.store(in: &subscriptions)
        preferences.$reactionsPaused.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.overlay.refreshAppearance() } }.store(in: &subscriptions)
        preferences.$movement.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.overlay.stopWalking() } }.store(in: &subscriptions)
        preferences.$hidden.dropFirst().sink { [weak self] hidden in if hidden { self?.speech.dismiss(); self?.reminders.complete() }
            DispatchQueue.main.async { self?.configureMusic() } }.store(in: &subscriptions)
        activity.$snapshot.map { CompanionActivity.level(for: $0.total) }.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.updateCaption() } }.store(in: &subscriptions)
        preferences.$edgeTraversal.dropFirst().sink { [weak self] enabled in
            if enabled { self?.windowEdges.requestPermission() }
        }.store(in: &subscriptions)
        preferences.$musicReactive.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.configureMusic(requestPermission: true, force: true) }
        }.store(in: &subscriptions)
        preferences.$musicLite.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.configureMusic(force: true) }
        }.store(in: &subscriptions)
        library.choosePet(preferences.companion)
        library.$state.map{state in state.activeTrack + ":" + String(state.tracks.first{$0.id==state.activeTrack}?.level ?? 1)}.removeDuplicates().sink{[weak self] _ in DispatchQueue.main.async{self?.updateCaption()}}.store(in:&subscriptions)
        preferences.$petOpacity.removeDuplicates().sink{[weak self] value in self?.overlay.window.alphaValue=value}.store(in:&subscriptions)
        preferences.$clickThrough.removeDuplicates().sink{[weak self] _ in DispatchQueue.main.async{self?.overlay.updatePassThrough()}}.store(in:&subscriptions)
        input.start(); loadPet(preferences.companion); configureServer()
        overlay.focusSleeping = focus.phase == .focus && !focus.paused && features.contains("openpets.focus-buddy")
        configureMusic()
        Task {await wallet.refresh();await librarySync.sync();await libraryContent.refresh()}
        validationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.wallet.refresh();await self?.librarySync.sync();await self?.libraryContent.refresh() }
        }
        if !canUseApp {
            notice = "Ten-minute companion preview. Purchase and restore your license to unlock PawSync."
            trialTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, !self.canUseApp else { return }; self.preferences.hidden = true; self.notice = "Your preview has ended. Restore your purchase to bring your companion back." }
            }
        }
    }
    private func loadPet(_ id: String) {
        guard library.canSelect(id) else { preferences.companion = "openpets-default"; notice = "This buddy joins at level \(LibraryProgress.petUnlock(id)). Keep making little progress!"; return }
        library.choosePet(id)
        do { try overlay.loadPet(id) }
        catch {
            notice = error.localizedDescription
            if id != "openpets-default" { preferences.companion = "openpets-default" }
        }
        let sku = preferences.accessory
        overlay.pet?.setAccessory(canEquipAccessory(sku) ? sku : "none")
        overlay.pet?.setAccessoryVisibility(preferences.headAccessoriesVisible)
        applyPresentation()
        care.select(id)
        updateCaption()
    }
    func selectLibraryPet(_ id:String) {guard library.canSelect(id) else{notice="This friend joins at level \(LibraryProgress.petUnlock(id)). Keep earning to unlock them.";return};notice="";preferences.companion=id}
    func originalPetName(_ id:String)->String {PetStore.builtInNames[id] ?? custom.customPets.first{$0.id==id}?.name ?? (try? PetStore.load(id).name) ?? id}
    func petName(_ id:String)->String {presentation.name(for:id) ?? originalPetName(id)}
    @discardableResult func renamePet(_ id:String,to name:String)->Bool {
        let cleaned=PetPresentationStore.cleanName(name)
        return presentation.setName(cleaned == originalPetName(id) ? "":cleaned,for:id)
    }
    func equipLibraryItem(_ id:String) {
        guard canEquipAccessory(id) else{notice="This item is waiting in a future gift. Collected items can be worn right away.";return}
        notice=""
        preferences.accessory=id;preferences.headAccessoriesVisible=id != "none"
    }
    func openAllGifts() {let ids=library.openAll();notice="Collected \(ids.count) little treasures. Find them in Items.";settingsSection = .items}
    func cheer(manual:Bool=false) {
        guard manual || library.state.automaticCheers && Date().timeIntervalSince(lastCheer)>180 else{return}
        let canCheer=canUseApp && !overlay.isHidden && !overlay.isScreenSleeping && !overlay.focusSleeping && reminders.active == nil && !speech.isReminder
        guard canCheer,(manual || !speech.isVisible),!presentGifts else{return}
        lastCheer=Date()
        let text=LibraryContent.lines.randomElement() ?? "I’m cheering for you, paws and all."
        _=speech.show(title:"A little cheer",text:text)
    }
    func hideForHour() {
        hiddenUntil?.cancel();preferences.hidden=true
        let work=DispatchWorkItem{[weak self] in self?.preferences.hidden=false};hiddenUntil=work;DispatchQueue.main.asyncAfter(deadline:.now()+3600,execute:work)
    }
    func mirrorMode(_ enabled:Bool) {
        presentation.state.flipped[preferences.companion]=enabled
        preferences.mirrorDock=enabled;preferences.anchor = .dock
        if enabled {library.record("mirror")}
        overlay.reposition()
    }
    func canEquipAccessory(_ id: String) -> Bool {
        if id == "none" { return true }
        if let item=FreeHat.all.first(where:{$0.id==id}) {return (item.requiresSKU==nil || wallet.accessories.contains(item.requiresSKU!)) && wardrobe.canEquipFreeHat(id)}
        return wallet.accessories.contains(id)
    }
    func applyPresentation(accessory:String?=nil) {
        let id=preferences.companion,item=accessory ?? preferences.accessory
        presentation.migratePlacement(pet:id,item:item)
        let state=presentation.state
        overlay.pet?.presentation(flipped:state.flipped[id] ?? false,hudScale:state.hudScale,hat:presentation.transform(pet:id,item:item))
        for (pet,hat) in state.hats {library.updatePlacement(pet,hat)}
        speech.setScale(state.hudScale); hud.setScale(state.hudScale); overlay.animate(for:0.3)
    }
    func previewReaction(_ reaction:PetReaction) { overlay.react(reaction) }
    func acknowledgeWater(now:Date=Date()) {
        if reminders.active?.kind == "water" { completeReminder() }
        else if var water=reminders.plan.reminders.first(where:{$0.kind == "water"}) {
            water.snoozeUntil=nil
            water.nextDue=water.specificTimes.flatMap{ReminderService.nextTime($0,after:now)} ?? now.addingTimeInterval(Double((water.intervalMinutes ?? 60)*60))
            try? reminders.upsert(water); overlay.wave()
        }
    }
    func pauseWaterToday() { daily.pauseToday("water"); if reminders.active?.kind == "water" { reminders.complete() } }
    var canDeliverCompanionMessage:Bool { canUseApp && !overlay.isHidden && !overlay.isScreenSleeping && !overlay.focusSleeping && reminders.active == nil && !speech.isVisible }
    private func refreshHUD() {
        let focusEntry=focus.phase != .ready ? HUDEntry(source:"focus",title:focus.paused ? "Focus paused" : focus.phase.rawValue,priority:30,metrics:[HUDMetric(id:"time",label:"Remaining",value:focus.display,icon:"timer"),HUDMetric(id:"rounds",label:"Sessions",value:String(focus.completed),icon:"checkmark")]) : nil
        hud.submit(focusEntry,source:"focus")
        hud.submit(countdown.state.phase != .idle && features.contains("openpets.simple-timer") ? HUDEntry(source:"timer",title:countdown.state.label,priority:20,metrics:[HUDMetric(id:"time",label:countdown.state.phase.rawValue.capitalized,value:countdown.display,icon:"hourglass")]) : nil,source:"timer")
        let values=[("food","Food",care.needs.food,"fork.knife"),("energy","Energy",care.needs.energy,"bolt"),("play","Play",care.needs.happiness,"sparkles"),("bond","Bond",care.needs.affection,"heart")]
        hud.submit(features.contains("openpets.virtual-pet") ? HUDEntry(source:"care",title:care.needs.mood,priority:10,metrics:values.map{HUDMetric(id:$0.0,label:$0.1,value:String(Int($0.2)),icon:$0.3)}) : nil,source:"care")
        var metrics:[HUDMetric]=[]
        for (id,label,value,icon) in [("cpu","CPU",resources.sample.cpu,"cpu"),("memory","Memory",resources.sample.memory,"memorychip"),("disk","Disk",resources.sample.disk,"internaldrive")] { if let value { metrics.append(HUDMetric(id:id,label:label,value:String(format:"%.0f%%",value),icon:icon)) } }
        if let battery=resources.sample.battery { metrics.append(HUDMetric(id:"battery",label:"Battery",value:"\(battery)%",icon:"battery.100percent")) }
        hud.submit(features.contains("openpets.system-resources") && !metrics.isEmpty ? HUDEntry(source:"resources",title:"Your Mac",priority:0,metrics:metrics) : nil,source:"resources")
    }
    func petContextMenu() -> NSMenu {
        let menu=NSMenu()
        func item(_ title:String,_ action:Selector) { let entry=NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target=self; menu.addItem(entry) }
        func submenu(_ title:String,_ entries:[(String,String)],_ selector:Selector) {
            let parent=NSMenuItem(title:title,action:nil,keyEquivalent:"");let sub=NSMenu();parent.submenu=sub
            for (id,name) in entries {let e=NSMenuItem(title:name,action:selector,keyEquivalent:"");e.target=self;e.representedObject=id;sub.addItem(e)};menu.addItem(parent)
        }
        let pets=library.state.favoritePets.filter{library.canSelect($0)}
        let fallback=PetStore.builtInIDs.filter{library.canSelect($0)}.prefix(8)
        submenu("Change companion",(pets.isEmpty ? Array(fallback):pets).map{($0,petName($0))},#selector(menuChoosePet(_:)))
        let hats=library.state.favoriteHats.filter{wardrobe.ownedHats.contains($0)}
        let available=FreeHat.all.filter{wardrobe.ownedHats.contains($0.id)}.prefix(12).map(\.id)
        submenu("Change item",[("none","Bare ears")]+(hats.isEmpty ? Array(available):hats).map{id in (id,FreeHat.all.first{$0.id==id}?.name ?? id)},#selector(menuChooseHat(_:)))
        submenu("Earn XP in",library.state.tracks.map{($0.id,$0.name + ($0.id == library.state.activeTrack ? " ✓":""))},#selector(menuEarn(_:)))
        submenu("Opacity",[("1.0","100%"),("0.8","80%"),("0.6","60%"),("0.4","40%")],#selector(menuOpacity(_:)))
        item("Adjust Item…",#selector(menuItemEditor));item(preferences.clickThrough ? "Turn off Click-Through":"Turn on Click-Through",#selector(menuClickThrough))
        item("Hide for 1 Hour",#selector(menuHideHour));item("Reset Position",#selector(menuResetPosition))
        item("Check for Updates…",#selector(menuUpdates));menu.addItem(.separator())
        item(preferences.reactionsPaused ? "Resume reactions" : "Pause reactions",#selector(menuPause))
        item("Add reminder…",#selector(menuAddReminder));item("Drink water reminder",#selector(menuWater))
        item("Pet your buddy",#selector(menuPet)); item("Say hello",#selector(menuHello))
        item("Files in my pocket…",#selector(menuFiles));item("Flip horizontally",#selector(menuFlip)); item("Take a walk",#selector(menuWalk)); item("Jump!",#selector(menuJump))
        if reminders.active != nil { menu.addItem(.separator()); item("Reminder done",#selector(menuReminderDone)); item("Snooze 10 min",#selector(menuSnooze)) }
        if focus.phase == .ready { item("Start Pomodoro",#selector(menuFocus)) } else { item("Stop Pomodoro",#selector(menuStopFocus)) }
        menu.addItem(.separator()); item("Pet gallery…",#selector(menuGallery)); item("Settings…",#selector(menuSettings)); item("Hide pet",#selector(menuHide))
        return menu
    }
    @objc private func menuChoosePet(_ item:NSMenuItem){if let id=item.representedObject as? String{selectLibraryPet(id)}}
    @objc private func menuChooseHat(_ item:NSMenuItem){if let id=item.representedObject as? String{equipLibraryItem(id)}}
    @objc private func menuEarn(_ item:NSMenuItem){if let id=item.representedObject as? String{library.earn(in:id)}}
    @objc private func menuOpacity(_ item:NSMenuItem){if let text=item.representedObject as? String,let n=Double(text){preferences.petOpacity=n}}
    @objc private func menuClickThrough(){preferences.clickThrough.toggle();overlay.updatePassThrough()}
    @objc private func menuHideHour(){hideForHour()}
    @objc private func menuResetPosition(){preferences.anchor = .dock;overlay.reposition()}
    @objc private func menuItemEditor(){settingsSection = .items;presentItemEditor=true;openSettings?()}
    @objc private func menuUpdates(){updates.check()}
    func confirmResetEverything(){
        let alert=NSAlert();alert.messageText="Reset local progress and preferences?";alert.informativeText="PawSync will save a backup, reset earned progress, free items, reminders, counters, preferences and privacy choices, then reopen for setup. Purchases and pet artwork remain. This does not revoke macOS permissions or reset cloud progress; use Reset Progress with sync enabled for that.";alert.addButton(withTitle:"Keep everything");alert.addButton(withTitle:"Reset & Reopen")
        guard alert.runModal() == .alertSecondButtonReturn else{return}
        do{
            stop();try LibraryReset.archiveLocalState()
            let helper=Process();helper.executableURL=Bundle.main.executableURL;helper.arguments=["--relaunch-after",String(ProcessInfo.processInfo.processIdentifier)];try helper.run();NSApp.terminate(nil)
        }catch{notice="Reset could not finish: \(error.localizedDescription). Please reopen PawSync; your backed-up files are retained."}
    }
    func confirmProgressReset(){
        let alert=NSAlert();alert.messageText="Start your Library progress over?";alert.informativeText="A backup is saved first. Earned pets, free items, achievements and gifts will reset. Purchases and settings stay. \(library.state.syncEnabled ? "Your account progress resets too.":"This resets progress on this Mac.")";alert.addButton(withTitle:"Keep my progress");alert.addButton(withTitle:"Reset Progress")
        guard alert.runModal() == .alertSecondButtonReturn else{return}
        Task{do{try await librarySync.resetProgress();preferences.companion="knight-cat";preferences.accessory="none";notice=librarySync.status}catch{notice="Progress was not reset. \(error.localizedDescription)"}}
    }
    @objc private func menuPause() { preferences.reactionsPaused.toggle() }
    @objc private func menuPet() { overlay.reactToPetting(direction:5) }
    @objc private func menuAddReminder() { settingsSection = .reminders;quickAddReminder=true;openSettings?() }
    @objc private func menuWater() { preferences.hidden=false;reminders.showPreview() }
    @objc private func menuFiles() { fileShelf.show() }
    @objc private func menuHello() { sayHello(manual:true) }
    @objc private func menuFlip() { presentation.flip(preferences.companion) }
    @objc private func menuWalk() {library.record("walk");overlay.wanderNow() }
    @objc private func menuJump() {library.record("jump");overlay.jumpNow() }
    @objc private func menuReminderDone() { completeReminder() }
    @objc private func menuSnooze() { reminders.snooze() }
    func startFocus() { guard canUseApp else { notice="Restore your purchase to start a Pomodoro session."; return }; focus.start() }
    @objc private func menuFocus() { startFocus() }
    @objc private func menuStopFocus() { focus.stop() }
    @objc private func menuGallery() { settingsSection = .gallery; openSettings?() }
    @objc private func menuSettings() { openSettings?() }
    @objc private func menuHide() { preferences.hidden=true }
    private func updateCaption() {
        let name = presentation.name(for:preferences.companion) ?? originalPetName(preferences.companion).components(separatedBy:" the ").first ?? "PawSync"
        let hideBearCaption=["bear","pawpaw-bear"].contains(preferences.companion)
        overlay.pet?.setCaption(hideBearCaption ? "" : "\(String(name.prefix(40))) · Lv.\(library.active.level)")
        overlay.animate(for: 0.2)
    }
    private func licenseChanged() {
        configureServer(); configureMusic(force: true)
        if !canUseApp { focus.stop(); preferences.hidden = true; preferences.accessory = "none" }
        else { preferences.hidden = false; trialTimer?.invalidate() }
    }
    func configureMusic(requestPermission: Bool = false, force: Bool = false) {
        let enabled = preferences.musicReactive && canUseApp
        let visible = !overlay.isHidden && !overlay.isScreenSleeping
        let key = "\(enabled)-\(preferences.musicLite)-\(visible)"
        guard force || key != audioConfiguration else { return }; audioConfiguration = key
        let lite = preferences.musicLite
        Task { await music.configure(enabled: enabled, lite: lite, visible: visible, requestPermission: requestPermission && enabled) }
    }
    func configureServer() {
        server.stop()
        guard preferences.integrations, canUseApp else { return }
        do {
            var token = KeychainStore.read("webhook")
            if token == nil { token = try KeychainStore.randomToken(); try KeychainStore.save(token!, key: "webhook"); revealedToken = token }
            try server.start(token: token!)
        } catch { notice = error.localizedDescription; preferences.integrations = false }
    }
    func regenerateWebhookToken() {
        do {
            let token = try KeychainStore.randomToken(); try KeychainStore.save(token, key: "webhook")
            revealedToken = token; configureServer()
        } catch { notice = error.localizedDescription }
    }
    func finishOnboarding() { preferences.onboarded = true; onboarding = false }
    func sayHello(manual: Bool = false) {
        if manual {library.record("hello")}
        guard (manual || preferences.greetings), !overlay.isHidden, reminders.active == nil else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.show(title: "\(salutation)\(name.isEmpty ? "!" : ", \(String(name.prefix(24)))!")", text: "I’m here to keep you company. We’ll make room for little breaks together.")
        overlay.wave()
    }
    func completeReminder() { if let reminder=reminders.active {library.record(reminder.kind)};reminders.complete(); if !overlay.focusSleeping { overlay.celebrate() } }
    func playSound(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
    func stop() {
        guard !shutdownComplete else{return};shutdownComplete=true
        photoCreator.stop()
        library.stop();librarySync.stop();libraryToast.stop();cheerTimer?.invalidate();hiddenUntil?.cancel()
        fileInbox.empty()
        fileShelf.stop();hud.shutdown(); practices.stop(); daily.shutdown(); care.shutdown(); resources.shutdown(); countdown.shutdown()
        shortcuts.stop(); catalog.stop(); music.stop(); input.stop(); server.stop(); focus.shutdown(); overlay.stop()
        activity.stop()
        reminders.stop(); speech.stop()
        validationTimer?.invalidate(); trialTimer?.invalidate()
        Diagnostics.configure(enabled: false, configuration: configuration)
    }
}
