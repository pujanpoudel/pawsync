import AppKit
import Combine

@MainActor final class AppModel: NSObject, ObservableObject {
    let preferences = Preferences()
    let input = InputSupervisor()
    let activity = CompanionActivity()
    let wardrobe = PetWardrobe(preserveExistingPets: UserDefaults.standard.bool(forKey: "onboarded"))
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
    let windowEdges = WindowEdgeService()
    let music = MusicReactionService()
    @Published var settingsSection: SettingsSection = .general
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
    @Published var notice = ""
    @Published var revealedToken: String?
    @Published var onboarding: Bool
    private var subscriptions = Set<AnyCancellable>()
    private var validationTimer: Timer?
    private var trialTimer: Timer?
    private var companionDefaultName = "PawSync"
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
        custom = CustomPetService(api: api, wallet: wallet)
        daily=DailyCompanionService(features:features)
        care=VirtualCareService(features:features)
        resources=ResourceMonitor(features:features)
        onboarding = !preferences.onboarded
        super.init()
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
        fileShelf.attach(to:overlay.window)
        overlay.showFileShelf = { [weak self] in self?.fileShelf.show() }
        overlay.canAcceptFiles = { [weak self] urls in self?.fileInbox.canAccept(urls) ?? false }
        overlay.onFileDrop = { [weak self] urls in
            guard let self,self.canUseApp else { return false }
            do {
                let count=try self.fileInbox.catchFiles(urls)
                self.overlay.catchFiles(count:count)
                self.fileShelf.show(near:self.overlay.window)
                return true
            } catch { self.notice=error.localizedDescription;return false }
        }
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
            guard let self, self.wardrobe.canEquipFreeHat(id), let pet=self.overlay.pet else { return false }
            self.preferences.accessory=id; self.preferences.headAccessoriesVisible=true
            self.presentation.state.hats[self.preferences.companion]=pet.accessoryPlacement(at:point); return true
        }
        speech.attach(to: overlay.window)
        hud.attach(to:overlay.window)
        speech.onVisibility = { [weak self] visible in self?.hud.setSuspended(visible || self?.overlay.isHidden == true || self?.overlay.isScreenSleeping == true) }
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
        music.onSignal = { [weak self] audible, beat in self?.overlay.musicSignal(audible, beat: beat) }
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
            guard let self else { return }; self.care.care("pet"); if !self.preferences.muted { self.playSound("meow") }
        }
        custom.onInstalled = { [weak self] id in self?.preferences.companion = id }
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
        focus.onCelebration = { [weak self] in self?.activity.completedFocus(); self?.overlay.celebrate() }
        wardrobe.onReward = { [weak self] reward in
            guard let self else { return }
            self.notice = "New little treasures: \(reward)"
            if !self.preferences.hidden, self.reminders.active == nil, !self.overlay.focusSleeping {
                self.speech.show(title: "A little surprise!", text: "You earned \(reward). Take a peek in your wardrobe.")
            }
        }
        activity.onLevelUp = { [weak self] in
            guard let self else { return }; self.wardrobe.reconcile(level: self.activity.level); self.overlay.celebrate()
        }
        activity.onGoalReached = { [weak self] in self?.overlay.celebrate() }
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
            self.applyPresentation()
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
        preferences.$nickname.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateCaption() } }.store(in: &subscriptions)
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
        wardrobe.reconcile(level: activity.level, announce: false)
        input.start(); loadPet(preferences.companion); configureServer()
        overlay.focusSleeping = focus.phase == .focus && !focus.paused && features.contains("openpets.focus-buddy")
        configureMusic()
        Task { await wallet.refresh() }
        validationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.wallet.refresh() }
        }
        if !canUseApp {
            notice = "Ten-minute companion preview. Purchase and restore your license to unlock PawSync."
            trialTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { guard let self, !self.canUseApp else { return }; self.preferences.hidden = true; self.notice = "Your preview has ended. Restore your purchase to bring your companion back." }
            }
        }
    }
    private func loadPet(_ id: String) {
        guard wardrobe.canSelectPet(id) else { preferences.companion = "openpets-default"; notice = "This buddy joins at level \(PetWardrobe.unlockLevels[id] ?? 1). Keep making little progress!"; return }
        companionDefaultName = PetStore.builtInNames[id]?.components(separatedBy: " the ").first ?? (try? PetStore.load(id).name) ?? "PawSync"
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
    func canEquipAccessory(_ id: String) -> Bool {
        if id == "none" { return true }
        if FreeHat.all.contains(where: { $0.id == id }) { return wardrobe.canEquipFreeHat(id) }
        return wallet.accessories.contains(id)
    }
    func applyPresentation() {
        let id=preferences.companion,state=presentation.state
        overlay.pet?.presentation(flipped:state.flipped[id] ?? false,hudScale:state.hudScale,hat:state.hats[id] ?? HatTransform())
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
    private func petContextMenu() -> NSMenu {
        let menu=NSMenu()
        func item(_ title:String,_ action:Selector) { let entry=NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target=self; menu.addItem(entry) }
        item(preferences.reactionsPaused ? "Resume reactions" : "Pause reactions",#selector(menuPause))
        item("Add reminder…",#selector(menuAddReminder));item("Drink water reminder",#selector(menuWater))
        item("Pet your buddy",#selector(menuPet)); item("Say hello",#selector(menuHello))
        item("Files in my pocket…",#selector(menuFiles));item("Flip horizontally",#selector(menuFlip)); item("Take a walk",#selector(menuWalk)); item("Jump!",#selector(menuJump))
        if reminders.active != nil { menu.addItem(.separator()); item("Reminder done",#selector(menuReminderDone)); item("Snooze 10 min",#selector(menuSnooze)) }
        if focus.phase == .ready { item("Start Pomodoro",#selector(menuFocus)) } else { item("Stop Pomodoro",#selector(menuStopFocus)) }
        menu.addItem(.separator()); item("Pet gallery…",#selector(menuGallery)); item("Settings…",#selector(menuSettings)); item("Hide pet",#selector(menuHide))
        return menu
    }
    @objc private func menuPause() { preferences.reactionsPaused.toggle() }
    @objc private func menuPet() { overlay.reactToPetting(direction:5) }
    @objc private func menuAddReminder() { settingsSection = .reminders;quickAddReminder=true;openSettings?() }
    @objc private func menuWater() { preferences.hidden=false;reminders.showPreview() }
    @objc private func menuFiles() { fileShelf.show() }
    @objc private func menuHello() { sayHello(manual:true) }
    @objc private func menuFlip() { presentation.flip(preferences.companion) }
    @objc private func menuWalk() { overlay.wanderNow() }
    @objc private func menuJump() { overlay.jumpNow() }
    @objc private func menuReminderDone() { completeReminder() }
    @objc private func menuSnooze() { reminders.snooze() }
    func startFocus() { guard canUseApp else { notice="Restore your purchase to start a Pomodoro session."; return }; focus.start() }
    @objc private func menuFocus() { startFocus() }
    @objc private func menuStopFocus() { focus.stop() }
    @objc private func menuGallery() { settingsSection = .gallery; openSettings?() }
    @objc private func menuSettings() { openSettings?() }
    @objc private func menuHide() { preferences.hidden=true }
    private func updateCaption() {
        let name = preferences.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        overlay.pet?.setCaption("\(name.isEmpty ? companionDefaultName : String(name.prefix(24))) · Lv.\(activity.level)")
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
        guard (manual || preferences.greetings), !overlay.isHidden, reminders.active == nil else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        speech.show(title: "\(salutation)\(name.isEmpty ? "!" : ", \(String(name.prefix(24)))!")", text: "I’m here to keep you company. We’ll make room for little breaks together.")
        overlay.wave()
    }
    func completeReminder() { reminders.complete(); if !overlay.focusSleeping { overlay.celebrate() } }
    func playSound(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
    func stop() {
        fileShelf.stop();hud.shutdown(); practices.stop(); daily.shutdown(); care.shutdown(); resources.shutdown(); countdown.shutdown()
        shortcuts.stop(); catalog.stop(); music.stop(); input.stop(); server.stop(); focus.shutdown(); overlay.stop()
        activity.stop()
        reminders.stop(); speech.stop()
        validationTimer?.invalidate(); trialTimer?.invalidate()
        Diagnostics.configure(enabled: false, configuration: configuration)
    }
}
