import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, NSWindowDelegate {
    private var model: AppModel!
    private var item: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var reopenObserver:NSObjectProtocol?
    private var companionMenu:NSMenu?
    private var accessoryMenu:NSMenu?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        reopenObserver=DistributedNotificationCenter.default().addObserver(forName:SingleInstance.showSettings,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.showSettings() } }
        let appMenu=NSMenu();let appParent=NSMenuItem();let appSubmenu=NSMenu();appParent.submenu=appSubmenu;appMenu.addItem(appParent)
        let quitItem=NSMenuItem(title:"Quit PawSync",action:#selector(quit),keyEquivalent:"q");quitItem.target=self;appSubmenu.addItem(quitItem)
        let edit=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"");let editMenu=NSMenu(title:"Edit");edit.submenu=editMenu;appMenu.addItem(edit)
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {editMenu.addItem(NSMenuItem(title:title,action:action,keyEquivalent:key))}
        NSApp.mainMenu=appMenu
        model = AppModel()
        model.openSettings = { [weak self] in self?.showSettings() }
        model.overlay.isSettingsPoint = { [weak self] point in
            guard let window=self?.settingsWindow,window.isVisible else { return false }
            return window.frame.contains(point)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PawSync")
        let menu = NSMenu(); menu.delegate = self
        func add(_ title:String,_ selector:Selector,_ key:String="") {
            let entry=NSMenuItem(title:title,action:selector,keyEquivalent:key); entry.target=self; menu.addItem(entry)
        }
        add("Open Settings…",#selector(showSettings),",")
        let companions=NSMenuItem(title:"Choose a Companion",action:nil,keyEquivalent:"");let companionSubmenu=NSMenu();companions.submenu=companionSubmenu;menu.addItem(companions);companionMenu=companionSubmenu
        let wardrobe=NSMenuItem(title:"Wear an Accessory",action:nil,keyEquivalent:"");let accessorySubmenu=NSMenu();wardrobe.submenu=accessorySubmenu;menu.addItem(wardrobe);accessoryMenu=accessorySubmenu
        add("Open Wardrobe…",#selector(openWardrobe))
        menu.addItem(.separator())
        add("Hide Pet",#selector(toggleHidden))
        add("Click-Through",#selector(toggleClickThrough))
        add("Mute Sounds",#selector(toggleMute))
        add("Pause Reactions",#selector(togglePaused))
        add("Let Pet Sleep",#selector(toggleSleep))
        add("Next Companion",#selector(nextCompanion))
        add("Say Hello",#selector(sayHello))
        menu.addItem(.separator())
        add("Water Reminder Now",#selector(waterReminder))
        add("Reminders…",#selector(openReminders))
        add("Start Pomodoro",#selector(toggleFocus))
        menu.addItem(.separator())
        add("Check for Updates…",#selector(checkUpdates))
        add("Quit PawSync",#selector(quit),"q")
        item.menu = menu
        showSettings()
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "PawSync Library"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center()
            settingsWindow = window
        }
        model.overlay.setSettingsVisible(true)
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleClickThrough(){model.preferences.clickThrough.toggle();model.overlay.updatePassThrough()}
    @objc func toggleMute(_ sender: NSMenuItem) { model.preferences.muted.toggle(); refreshMenu() }
    @objc func toggleHidden(_ sender: NSMenuItem) { model.preferences.hidden.toggle(); refreshMenu() }
    @objc func togglePaused(_ sender: NSMenuItem) { model.preferences.reactionsPaused.toggle(); refreshMenu() }
    @objc func nextCompanion() {
        let available = (PetStore.builtInIDs + PetStore.customPets().map(\.id)).filter { model.library.canSelect($0) }
        guard !available.isEmpty else { return }
        let index = available.firstIndex(of: model.preferences.companion) ?? -1
        model.preferences.hidden = false
        model.preferences.companion = available[(index + 1) % available.count]
    }
    @objc func sayHello() { model.preferences.hidden = false; model.sayHello(manual: true) }
    @objc func openReminders() { model.settingsSection = .reminders; showSettings() }
    @objc func waterReminder() {
        model.preferences.hidden = false
        if model.reminders.active == nil { model.reminders.showPreview() }
        else { model.settingsSection = .reminders; showSettings() }
    }
    @objc func toggleFocus() {
        if !model.canUseApp { model.settingsSection = .wallet; showSettings(); return }
        if model.focus.phase == .ready { model.startFocus() } else { model.focus.stop() }
        refreshMenu()
    }
    @objc func checkUpdates() { model.updates.check() }
    @objc func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === settingsWindow else { return }
        closing.contentView = nil; settingsWindow = nil
        model.overlay.setSettingsVisible(false)
    }
    func applicationDidResignActive(_ notification: Notification) { model.overlay.setSettingsVisible(false) }
    func applicationDidBecomeActive(_ notification: Notification) {
        model.overlay.setSettingsVisible(settingsWindow?.isVisible == true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func menuWillOpen(_ menu: NSMenu) { refreshMenu();refreshCompanionSubmenu();refreshAccessorySubmenu() }
    private func refreshMenu() {
        guard let menu=item?.menu else { return }
        for entry in menu.items where !entry.isSeparatorItem { _ = validateMenuItem(entry) }
    }
    func validateMenuItem(_ entry: NSMenuItem) -> Bool {
        if entry.isSeparatorItem { return false }
        guard let model else { return true }
        var enabled=true
        switch entry.action {
        case #selector(toggleMute):
            entry.title=model.preferences.muted ? "Unmute Sounds" : "Mute Sounds"
            entry.state=model.preferences.muted ? .on : .off
        case #selector(toggleHidden): entry.title=model.preferences.hidden ? "Show Pet" : "Hide Pet"
        case #selector(togglePaused):
            entry.title=model.preferences.reactionsPaused ? "Resume Reactions" : "Pause Reactions"
            entry.state=model.preferences.reactionsPaused ? .on : .off
        case #selector(toggleSleep): entry.title=model.overlay.isMenuSleeping ? "Wake Pet" : "Let Pet Sleep"
        case #selector(toggleFocus): entry.title=model.focus.phase == .ready ? "Start Pomodoro" : "Stop Pomodoro"
        case #selector(nextCompanion):
            enabled=PetStore.builtInIDs.filter { model.library.canSelect($0) }.count > 1
        default: break
        }
        entry.isEnabled=enabled
        return enabled
    }
    @objc private func chooseCompanion(_ sender:NSMenuItem) {
        guard let id=sender.representedObject as? String,model.wardrobe.canSelectPet(id) else { return }
        model.preferences.companion=id;model.preferences.hidden=false
    }
    @objc private func chooseAccessory(_ sender:NSMenuItem) {
        guard let sku=sender.representedObject as? String else { return }
        model.preferences.accessory=sku;model.preferences.headAccessoriesVisible=sku != "none"
    }
    @objc private func openWardrobe() { model.settingsSection = .gallery;showSettings() }
    @objc private func toggleSleep() { model.overlay.setMenuSleeping(!model.overlay.isMenuSleeping);refreshMenu() }
    private func refreshCompanionSubmenu() {
        guard let menu=companionMenu else { return };menu.removeAllItems()
        let ids=(PetStore.builtInIDs+PetStore.customPets().map(\.id)).filter{model.library.canSelect($0)}
        for id in ids {
            let entry=NSMenuItem(title:PetStore.builtInNames[id] ?? id,action:#selector(chooseCompanion(_:)),keyEquivalent:"")
            entry.target=self;entry.representedObject=id;entry.state=model.preferences.companion == id ? .on:.off;menu.addItem(entry)
        }
    }
    private func refreshAccessorySubmenu() {
        guard let menu=accessoryMenu else { return };menu.removeAllItems()
        let owned=FreeHat.all.filter{model.wardrobe.ownedHats.contains($0.id)}.map{($0.id,$0.name)}
        let paid=model.wallet.accessories.map{($0,$0 == "accessory.glasses" ? "Glasses" : "Top hat")}
        for (sku,name) in [("none","No accessory")]+owned+paid {
            let entry=NSMenuItem(title:name,action:#selector(chooseAccessory(_:)),keyEquivalent:"")
            entry.target=self;entry.representedObject=sku;entry.state=model.preferences.accessory == sku ? .on:.off;menu.addItem(entry)
        }
    }
    func applicationDockMenu(_ sender:NSApplication)->NSMenu? {model.petContextMenu()}
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

MainActor.assumeIsolated {
    if let index=CommandLine.arguments.firstIndex(of:"--relaunch-after"),CommandLine.arguments.indices.contains(index+1),let pid=Int32(CommandLine.arguments[index+1]) {
        let deadline=Date().addingTimeInterval(10)
        while NSRunningApplication(processIdentifier:pid) != nil,Date()<deadline {Thread.sleep(forTimeInterval:0.15)}
        let launcher=Process();launcher.executableURL=URL(fileURLWithPath:"/usr/bin/open");launcher.arguments=["-n",Bundle.main.bundleURL.path];try? launcher.run();exit(0)
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-library"),CommandLine.arguments.indices.contains(index+1) {
        do{try LibraryChecks.run(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))}
        catch{fputs("Library check failed: \(error.localizedDescription)\n",stderr);exit(1)}
    } else if CommandLine.arguments.contains("--check-file-pocket") {
        do { try FilePocketChecks.run() }
        catch { fputs("File pocket check failed: \(error.localizedDescription)\n",stderr);exit(1) }
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-emotions"),CommandLine.arguments.indices.contains(index+1) {
        do { try EmotionChecks.run(directory:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Emotion check failed: \(error.localizedDescription)\n",stderr);exit(1) }
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-companion-ui"),CommandLine.arguments.indices.contains(index+1) {
        do { try PetChromeChecks.run(directory:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Companion UI check failed: \(error.localizedDescription)\n",stderr);exit(1) }
    } else if CommandLine.arguments.contains("--check-input-status") {
        SelfChecks.inputStatus()
    } else if let index=CommandLine.arguments.firstIndex(of:"--export-original-frames"),CommandLine.arguments.indices.contains(index+1) {
        do { try OriginalFrameExporter.run(directory:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Original frame export failed: \(error.localizedDescription)\n",stderr); exit(1) }
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-motion"),CommandLine.arguments.indices.contains(index+1) {
        do { try MotionChecks.run(directory:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Motion check failed: \(error.localizedDescription)\n",stderr); exit(1) }
    } else if CommandLine.arguments.contains("--check-catalog") {
        Task { @MainActor in do { try await SelfChecks.catalog(); exit(0) } catch { fputs("Catalog check failed: \(error.localizedDescription)\n",stderr); exit(1) } }; RunLoop.main.run()
    } else if CommandLine.arguments.contains("--check-companion-tools") {
        do { try SelfChecks.companionTools() } catch { fputs("Companion tools failed: \(error.localizedDescription)\n",stderr); exit(1) }
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-imports"),CommandLine.arguments.indices.contains(index+1) {
        do { try SelfChecks.imports(fixtures:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Import check failed: \(error.localizedDescription)\n",stderr); exit(1) }
    } else if let index=CommandLine.arguments.firstIndex(of:"--check-original-packs"),CommandLine.arguments.indices.contains(index+1) {
        do { try SelfChecks.originalPacks(directory:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        catch { fputs("Original pet pack check failed: \(error.localizedDescription)\n",stderr); exit(1) }
    } else if CommandLine.arguments.contains("--check-assets") {
        do { try SelfChecks.assetsAndLicense() }
        catch { fputs("Native check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    } else if CommandLine.arguments.contains("--check-webhook") {
        Task { @MainActor in
            do { try await SelfChecks.webhook(); exit(0) }
            catch { fputs("Webhook check failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        RunLoop.main.run()
    } else {
        do { guard try SingleInstance.acquire() else { exit(0) } }
        catch { fputs("PawSync could not start: \(error.localizedDescription)\n",stderr); exit(1) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
