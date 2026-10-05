import AppKit
import CryptoKit
import SpriteKit
import Darwin

@MainActor enum SelfChecks {
    static func inputStatus() {
        _=NSApplication.shared
        let supervisor=InputSupervisor(); supervisor.start()
        print("Input Monitoring authorization: \(supervisor.authorized ? "granted" : "missing"); listener: \(supervisor.running ? "registered" : "unavailable"); \(supervisor.status)")
        supervisor.stop()
    }
    static func catalog() async throws {
        let index=try JSONDecoder().decode(PetCatalogService.Index.self,from:await CatalogTransport.get(URL(string:"https://openpets.dev/pets/catalog.v3.json")!))
        guard index.version == 3,let first=index.pages.first else { throw PawError.message("Unsupported gallery index.") }
        let page=try JSONDecoder().decode(PetCatalogService.Page.self,from:await CatalogTransport.get(first))
        guard page.version == 3,page.page == 0,let pet=page.pets.first(where:{$0.original == true}) else { throw PawError.message("Gallery page did not contain original pets.") }
        for pet in page.pets { try pet.validate() }
        guard let thumbnail=pet.thumbnail else { throw PawError.message("The gallery pet has no thumbnail.") }
        let thumb=try await CatalogTransport.get(thumbnail,limit:2*1024*1024)
        let rendered=try GalleryImageDecoder.render(thumb,sheet:false,rows:9,detail:false)
        guard NSImage(data:rendered) != nil else { throw PawError.message("The gallery thumbnail could not be displayed.") }
        let archive=try await CatalogTransport.get(pet.zip,limit:50*1024*1024,zip:true)
        let files=try SafeArchive.unpack(archive),metadata=try PetInstallation.validate(files).0
        guard metadata.id == pet.id else { throw PawError.message("Gallery package identity mismatch.") }
        print("Native live gallery check passed: v3 index (\(index.total) pets), paged catalog, bounded thumbnail decode and ZIP download, atlas validation and matching package ID. No pet was installed.")
    }
    static func companionTools() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("PawSync-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:directory) }
        let now=Date(timeIntervalSince1970:1_700_000_000)
        let timer=CountdownService(directory:directory,startTimer:false)
        try timer.start(minutes:5,label:"Tiny task",now:now)
        timer.pause(now:now.addingTimeInterval(30)); precondition(timer.remaining == 270 && timer.state.phase == .paused)
        let restored=CountdownService(directory:directory,startTimer:false); precondition(restored.state.phase == .paused && restored.remaining == 270)
        restored.resume(now:now.addingTimeInterval(40)); restored.addFive(now:now.addingTimeInterval(40)); precondition(restored.remaining == 570)
        var deliveries=0; restored.onExpired={ _ in deliveries+=1; return true }
        restored.tick(now:now.addingTimeInterval(1000)); restored.tick(now:now.addingTimeInterval(1100)); precondition(deliveries == 1 && restored.state.phase == .expired)
        let expired=CountdownService(directory:directory,startTimer:false); expired.onExpired={ _ in deliveries+=1; return true }; expired.tick(now:now.addingTimeInterval(1200)); precondition(deliveries == 1)
        expired.snooze(now:now.addingTimeInterval(1200)); precondition(expired.remaining == 300); expired.cancel(); precondition(expired.state.phase == .idle)
        let preferences=Preferences(),focus=FocusTimer(preferences:preferences,directory:directory,startTimer:false)
        focus.start(now:now); focus.pause(now:now.addingTimeInterval(20)); let remaining=focus.remaining
        let paused=FocusTimer(preferences:preferences,directory:directory,startTimer:false); precondition(paused.paused && paused.remaining == remaining)
        paused.resume(now:now.addingTimeInterval(30)); paused.tick(now:now.addingTimeInterval(Double(remaining+31))); precondition(paused.phase == .rest && paused.completed == 1)
        paused.stop(); precondition(paused.phase == .ready)
        let features=NativeFeatureRegistry(directory:directory)
        precondition(features.enabled.count == 6 && !features.contains("openpets.virtual-pet"))
        features.set("openpets.virtual-pet",enabled:true)
        let care=VirtualCareService(features:features,directory:directory,startTimer:false)
        care.select("test-buddy",now:now); care.care("feed",now:now); precondition(care.needs.fed == 1 && care.needs.food == 100)
        care.care("play",now:now.addingTimeInterval(2)); precondition(care.needs.played == 1)
        care.care("nap",now:now.addingTimeInterval(4)); let energy=care.needs.energy; care.tick(now:now.addingTimeInterval(1804)); precondition(care.needs.energy > energy)
        let daily=DailyCompanionService(features:features,directory:directory,startTimer:false,now:now)
        daily.state.greetingPolicy="oncePerDay"; var greetings=0
        daily.onMessage={ id,_,_,_ in if id == "launch" { greetings+=1 }; return true }
        daily.greet(now:now); daily.shutdown(now:now)
        let nextLaunch=DailyCompanionService(features:features,directory:directory,startTimer:false,now:now.addingTimeInterval(100))
        nextLaunch.onMessage={ id,_,_,_ in if id == "launch" { greetings+=1 }; return true }
        nextLaunch.tick(now:now.addingTimeInterval(200)); precondition(greetings == 1)
        daily.mood(.okay,note:"A quiet day",now:now); daily.mood(.great,now:now.addingTimeInterval(1)); precondition(daily.state.moods.count == 1 && daily.state.moods[0].mood == .great)
        precondition(DailyCompanionService.fortune(for:now) == DailyCompanionService.fortune(for:now.addingTimeInterval(1)))
        daily.state.morning="09:"; daily.tick(now:now); precondition(!daily.error.isEmpty)
        print("Native companion-tool checks passed: persisted countdown, pause/resume/add/snooze and exactly-once expiry; Pomodoro restoration and transitions; six default features; per-pet needs/nap; once-daily greeting; private daily mood replacement; deterministic fortune; invalid-time handling.")
    }
    static func imports(fixtures: URL) throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PawSync-installer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:root) }
        let archives=try FileManager.default.contentsOfDirectory(at:fixtures,includingPropertiesForKeys:nil)
        var rejected=0
        for url in archives {
            let good=url.lastPathComponent.hasPrefix("valid-")
            do {
                let files=try SafeArchive.unpack(Data(contentsOf:url)); _=try PetInstallation.validate(files)
                guard good else { throw PawError.message("Validator accepted \(url.lastPathComponent)") }
                _=try PetInstallation.install(files,expectedID:"default",root:root)
            } catch {
                if good || error.localizedDescription.hasPrefix("Validator accepted") { throw error }
                rejected+=1
            }
        }
        let files=try SafeArchive.unpack(Data(contentsOf:fixtures.appendingPathComponent("valid-store.zip")))
        precondition(PetInstallation.installed(root:root).count == 1)
        do { _=try PetInstallation.install(files,expectedID:"wrong",root:root); preconditionFailure("Catalog identity was not enforced") } catch { }
        let descriptor=open(root.appendingPathComponent(".install.lock").path,O_RDWR)
        precondition(descriptor >= 0 && flock(descriptor,LOCK_EX|LOCK_NB) == 0)
        do { _=try PetInstallation.install(files,root:root); preconditionFailure("Concurrent installer lock was ignored") } catch { }
        flock(descriptor,LOCK_UN); close(descriptor)
        // Simulate process death after moving the previous version to its backup.
        let nonce=UUID().uuidString,stage=".stage-\(nonce)",backup=".backup-\(nonce)",target=root.appendingPathComponent("default")
        try FileManager.default.copyItem(at:target,to:root.appendingPathComponent(stage))
        let journal:[String:Any]=["folder":"default","stage":stage,"backup":backup,"replacing":true]
        try JSONSerialization.data(withJSONObject:journal).write(to:root.appendingPathComponent(".journal.json"))
        try FileManager.default.moveItem(at:target,to:root.appendingPathComponent(backup))
        try PetInstallation.recover(root:root)
        precondition(PetInstallation.installed(root:root).count == 1)
        precondition(!FileManager.default.fileExists(atPath:root.appendingPathComponent(stage).path))
        // Missing old files fence the recovery instead of deleting the only staged copy.
        try FileManager.default.moveItem(at:target,to:root.appendingPathComponent(stage))
        try JSONSerialization.data(withJSONObject:journal).write(to:root.appendingPathComponent(".journal.json"))
        do { try PetInstallation.recover(root:root); preconditionFailure("Ambiguous recovery was accepted") } catch { }
        precondition(FileManager.default.fileExists(atPath:root.appendingPathComponent(stage).path))
        precondition(!CatalogTransport.permitted(URL(string:"https://openpets.dev.evil.test/pets/catalog.json")!))
        precondition(!CatalogTransport.permitted(URL(string:"http://openpets.dev/pets/catalog.json")!))
        precondition(!CatalogTransport.permitted(URL(string:"https://openpets.dev/pets/a?token=secret")!))
        print("Native import checks passed: stored/deflated/folder ZIPs, \(rejected) malformed packages rejected, catalog identity, interprocess lock, crash recovery and ambiguous-recovery preservation.")
    }
    static func originalPacks(directory:URL) throws {
        for id in PetStore.rigIDs {
            let url=directory.appendingPathComponent("\(id).zip")
            let files=try SafeArchive.unpack(Data(contentsOf:url,options:.mappedIfSafe))
            guard Set(files.keys) == ["pet.json","spritesheet.webp","character-sheet.png","pose-sheet.png"] else { throw PawError.message("Incomplete original pet pack: \(id).") }
            let (metadata,_,image)=try PetInstallation.validate(files)
            guard metadata.id == id,metadata.spriteVersionNumber == 1,
                  let spec=PetStore.frameOriginal(id),
                  image == (try Data(contentsOf:spec.directory.appendingPathComponent("spritesheet.webp"),options:.mappedIfSafe)) else {
                throw PawError.message("The bundled atlas does not match \(id).zip.")
            }
            let node=try FramePetNode(spec:spec)
            node.setWalking(true)
            guard node.sequence?.row == 1 else { throw PawError.message("Walking frames are unavailable for \(id).") }
            node.setWalking(false); node.celebrate()
            guard node.sequence?.row == 4 else { throw PawError.message("Jump frames are unavailable for \(id).") }
            node.wave()
            guard node.sequence?.row == 3 else { throw PawError.message("Wave frames are unavailable for \(id).") }
        }
        print("Original pet packs passed: nine importable character-sheet ZIPs match nine bundled 8 × 9 WebP atlases; frame playback loads walking, jumping and waving for each pet.")
    }
    static func assetsAndLicense() throws {
        let preferences = Preferences()
        precondition((1...120).contains(preferences.focusMinutes))
        precondition((1...30).contains(preferences.breakMinutes))
        for id in PetStore.rigIDs {
            let manifest = try PetStore.load(id)
            let pet = try PetSpriteNode(manifest: manifest, directory: PetStore.directory(for: id))
            let scene = SKScene(size: CGSize(width: 280, height: 260))
            pet.position = CGPoint(x: 140, y: 32); scene.addChild(pet)
            precondition(pet.joints.count == 5)
            precondition(pet.joints["head"]?.parent === pet.joints["body"])
            precondition(pet.containsOpaquePoint(CGPoint(x: 140, y: 123)))
            precondition(!pet.containsOpaquePoint(CGPoint(x: 12, y: 240)))
            pet.typing(at:1)
            precondition(pet.lastTappedPaw == "left_paw")
            precondition(pet.joints["left_paw"]?.action(forKey: "typing") != nil)
            pet.typing(at:1.1)
            precondition(pet.lastTappedPaw == "right_paw")
            precondition(pet.joints["right_paw"]?.action(forKey: "typing") != nil)
            pet.click(toward: CGPoint(x: 20, y: 150))
            precondition(pet.joints["head"]?.action(forKey: "reaction") != nil)
            pet.pet(direction: 2)
            precondition(pet.joints["head"]?.action(forKey: "petting") != nil)
            precondition(pet.joints["head"]?.childNode(withName: "blink") != nil)
            pet.setSleeping(true)
            precondition(pet.sleeping)
            pet.setSleeping(false); precondition(!pet.sleeping)
            pet.setAccessory("free.sprout")
            precondition(pet.accessorySlot.childNode(withName: "cosmetic") != nil)
            precondition(pet.accessorySlot.parent === pet.joints["head"])
            pet.setDancing(true,beat:0.5)
            precondition(pet.accessorySlot.childNode(withName:"free-headphones") != nil)
            pet.setAccessoryVisibility(false)
            precondition(pet.accessorySlot.isHidden)
            pet.setAccessory("none")
            precondition(pet.accessorySlot.childNode(withName:"cosmetic") == nil)
            pet.setDancing(false,beat:0.5)
            pet.setAccessoryVisibility(true)
            precondition(!pet.accessorySlot.isHidden && pet.accessorySlot.childNode(withName:"free-headphones") == nil)
            pet.setWalking(true); precondition(pet.joints["left_paw"]?.action(forKey: "walking") != nil)
            pet.setWalking(false)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PawSync-wardrobe-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        for spec in PetStore.imports {
            let node=try FramePetNode(spec:spec),scene=SKScene(size:CGSize(width:280,height:260))
            node.position=CGPoint(x:140,y:32); scene.addChild(node)
            precondition(node.currentFrame.row == 0 && node.currentFrame.column == (spec.rows == 11 ? 6 : 0))
            if spec.rows == 11 {
                node.look(toward:CGPoint(x:140,y:500)); precondition(node.currentFrame.row == 9 && node.currentFrame.column == 0)
                node.presentation(flipped:true,hudScale:1.2,hat:HatTransform())
                node.look(toward:CGPoint(x:1000,y:32)); precondition(node.currentFrame.row == 10 && node.currentFrame.column == 4)
            }
            node.play(.waiting,looping:true,relaxed:true); precondition(node.sequence?.row == 6 && node.sequence?.duration == 2.2)
            node.typing(); let start=node.frameStartedAt
            node.advanceFrame(at:start+0.3); let column=node.currentFrame.column
            node.typing(); precondition(node.frameStartedAt == start && node.currentFrame.column == column)
            node.setSleeping(true); precondition(node.sleeping); node.setSleeping(false)
            precondition(node.currentFrame.row == 0 && node.currentFrame.column == (spec.rows == 11 ? 6 : 0))
            node.setAccessory("free.sprout"); node.setDancing(true,beat:0.5)
            let slot=node.childNode(withName:"//head-accessories")
            precondition(slot?.childNode(withName:"cosmetic") != nil && slot?.childNode(withName:"free-headphones") != nil)
            node.setAccessoryVisibility(false); precondition(slot?.isHidden == true)
            node.setAccessory("none"); precondition(slot?.childNode(withName:"cosmetic") == nil)
            node.setDancing(false,beat:0.5); node.setAccessoryVisibility(true)
            precondition(slot?.isHidden == false && slot?.childNode(withName:"free-headphones") == nil)
        }
        if let spec=PetStore.imports.first(where:{$0.rows == 11}) ?? PetStore.imports.first {
            let image=try GalleryImageDecoder.render(Data(contentsOf:spec.directory.appendingPathComponent("spritesheet.webp"),options:.mappedIfSafe),sheet:true,rows:spec.rows,detail:true)
            precondition(NSImage(data:image) != nil)
        }
        let reactions=ReactionSettings(directory:temporary)
        precondition(reactions.animation(for:.thinking) == .review && PetReaction.working.loops && !PetReaction.success.loops)
        reactions.mapping["success"] = .waving; reactions.relaxedWaiting=true
        let restoredReactions=ReactionSettings(directory:temporary)
        precondition(restoredReactions.animation(for:.success) == .waving && restoredReactions.relaxedWaiting)
        let presentation=PetPresentationStore(directory:temporary)
        presentation.flip("pixel-cat"); presentation.state.hudScale=1.2
        presentation.setTransform(HatTransform(x:8,y:-4,scale:1.2,rotation:9),pet:"pixel-cat",item:"free.crown")
        presentation.setTransform(HatTransform(x:-3,y:2),pet:"pixel-cat",item:"accessory.glasses")
        let restoredPresentation=PetPresentationStore(directory:temporary)
        precondition(restoredPresentation.state.flipped["pixel-cat"] == true && restoredPresentation.state.hudScale == 1.2)
        precondition(restoredPresentation.transform(pet:"pixel-cat",item:"free.crown").x == 8)
        precondition(restoredPresentation.transform(pet:"pixel-cat",item:"accessory.glasses").x == -3)
        precondition(restoredPresentation.transform(pet:"fox",item:"free.crown") == HatTransform())
        let corrupt=temporary.appendingPathComponent("Presentation/reactions.json")
        try Data("{\"version\":99,\"mapping\":{},\"relaxedWaiting\":false}".utf8).write(to:corrupt)
        let recovered=ReactionSettings(directory:temporary)
        precondition(recovered.animation(for:.success) == .jumping)
        let stateFiles=try FileManager.default.contentsOfDirectory(atPath:corrupt.deletingLastPathComponent().path)
        precondition(stateFiles.contains(where:{$0.contains("quarantine-")}))
        let wardrobe = PetWardrobe(directory: temporary)
        precondition(wardrobe.canSelectPet("pixel-cat") && !wardrobe.canSelectPet("capybara"))
        precondition(wardrobe.canEquipFreeHat("free.sprout") && !wardrobe.canEquipFreeHat("accessory.hat"))
        wardrobe.reconcile(level: 6, announce: false)
        precondition(wardrobe.ownedHats.count == 6 && wardrobe.ownedPets.count == 9)
        let reopened = PetWardrobe(directory: temporary)
        reopened.reconcile(level: 6, announce: false)
        precondition(reopened.ownedHats == wardrobe.ownedHats && reopened.ownedPets == wardrobe.ownedPets)
        let key = Curve25519.Signing.PrivateKey()
        func encoded(_ value: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: value, options: .sortedKeys).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = try encoded(["alg": "EdDSA", "typ": "JWT"])
        let claims = try encoded(["sub": UUID().uuidString, "licensed": true, "iss": "pawsync", "aud": "pawsync-desktop"])
        let message = "\(header).\(claims)"
        let signature = try key.signature(for: Data(message.utf8)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let token = "\(message).\(signature)"
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        precondition(PetWalletService.validOfflineToken(token, publicKey: publicKey))
        precondition(!PetWalletService.validOfflineToken(token + "a", publicKey: publicKey))
        precondition(!PetWalletService.validOfflineToken(token, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        print("Native checks passed: nine rigs, imported V1/V2 neutral frames and mirrored gaze, reaction-map persistence, per-pet flip/HUD state, corrupt-state quarantine, alpha hit tests, alternating paws, click/petting/sleep/walking, free hats, earned inventory, Ed25519 license verification.")
    }

    static func webhook() async throws {
        let server = LocalWebhookServer()
        let token = try KeychainStore.randomToken()
        try server.start(token: token)
        defer { server.stop() }
        // Wait only for the test listener to bind, without input permission or Keychain writes.
        try await Task.sleep(nanoseconds: 150_000_000)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for (supplied, expected) in [("invalid", 401), (token, 200)] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:9876/v1/status")!)
            request.httpMethod = "POST"; request.timeoutInterval = 3
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(supplied)", forHTTPHeaderField: "Authorization")
            request.httpBody = Data("{\"status\":\"build_success\"}".utf8)
            let (_, response) = try await session.data(for: request)
            precondition((response as? HTTPURLResponse)?.statusCode == expected)
        }
        print("Native local webhook checks passed: unauthorized rejected, authenticated accepted.")
    }
}
