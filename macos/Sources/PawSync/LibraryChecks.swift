import AppKit
import SwiftUI
import SpriteKit

@MainActor enum LibraryChecks {
    private static func require(_ value:@autoclosure()->Bool,_ message:String) throws {guard value() else{throw PawError.message(message)}}
    static func run(directory:URL) throws {
        _=NSApplication.shared;LibraryContent.load()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("PawSync-Library-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:temporary)}
        let wardrobe=PetWardrobe(directory:temporary)
        let game=LibraryProgress(wardrobe:wardrobe,directory:temporary,startTimer:false)
        try require(FreeHat.all.count==228,"Expected 228 actual free vector items.")
        try require(FreeHat.all.filter{$0.track=="season2"}.count==108,"Season 2 does not have 108 items.")
        try require(Set(FreeHat.all.map(\.id)).count==FreeHat.all.count,"Duplicate item IDs.")
        try require(LibraryAchievement.all.count==30 && SecretPair.all.count==7,"Missing achievements or secrets.")
        try require(LibraryProgress.petUnlock("pawpaw-season2-opossum")==39,"Season 2 does not end at level 39.")
        try require(game.canSelect("knight-cat") && !game.canSelect("pawpaw-season2-opossum"),"New-install unlock gating is wrong.")
        var earned=0;game.onAchievement={_ in earned+=1}
        game.earn(in:"season1")
        for i in 0..<8 {game.registerInput(at:Double(i)*0.1+10)};game.flush()
        try require(game.onFire && game.active.xp==9,"Fast live input did not start 2× XP exactly on the eighth event.")
        try require(earned==1 && game.state.achievements["first-spark"] != nil,"On Fire did not independently unlock First Spark.")
        game.coolDown(at:14)
        try require(!game.onFire,"On Fire did not end after silence.")
        game.choosePet("knight-cat")
        try require(game.state.activeTrack=="season1","Changing pets moved the chosen XP track.")
        game.updateOptions(follows:true);game.choosePet("knight-cat")
        try require(game.state.activeTrack=="originals","Follow-my-pet did not switch tracks.")
        for i in 0..<520 {game.registerInput(at:Double(i)+100)};game.flush()
        try require(game.active.level==2 && game.state.gifts.count==1,"Level-up did not enqueue one gift.")
        let before=game.active.xp
        game.record("dress")
        try require(game.active.xp==before,"Achievement wrongly grants XP.")
        let gift=game.state.gifts[0];game.pickGift(gift.id,index:1)
        try require(game.state.gifts[0].selected==gift.choices[1],"Gift choice was not saved.")
        let restarted=LibraryProgress(wardrobe:wardrobe,directory:temporary,startTimer:false)
        try require(restarted.state.gifts.first?.selected==gift.choices[1],"An unopened gift was lost on restart.")
        _=game.collectGift(gift.id)
        try require(wardrobe.ownedHats.contains(gift.choices[1]) && game.state.claimedGifts.contains(gift.id),"Collecting did not unlock its item.")
        try require(game.collectGift(gift.id)==nil,"A gift can be claimed twice.")
        game.pairing(pet:"knight-cat",hat:"free.crown")
        try require(game.state.discoveries==["knight-royalty"],"Secret pairing did not unlock.")
        game.pairing(pet:"knight-cat",hat:"free.crown")
        try require(game.state.counters["secret"]==1,"A discovered secret unlocked twice.")
        var remote=game.export();remote.tracks[1].xp=19000;remote.hats.append("free.star");remote.gifts.append(gift)
        try game.merge(remote)
        try require(game.state.tracks[1].level==39 && wardrobe.ownedHats.contains("free.star") && game.canSelect("pawpaw-season2-opossum"),"Cross-Mac merge lost higher levels or items.")
        try require(game.state.gifts.allSatisfy{$0.id != gift.id},"Merge resurrected a claimed gift.")
        try game.reset(epoch:3)
        try require(game.state.tracks.allSatisfy{$0.level==1} && game.state.achievements.isEmpty && game.state.gifts.isEmpty,"Progress reset retained old rewards.")
        try require(FileManager.default.fileExists(atPath:temporary.appendingPathComponent("Backups").path),"Merge/reset did not keep backups.")
        restarted.stop();game.stop()
        let glasses=PetAccessories.make("accessory.glasses")!
        let eyes=CGPoint(x:3,y:120),slot=CGPoint(x:3,y:170)
        PetWearableFit.apply(glasses,id:"accessory.glasses",petID:"knight-cat",headScale:1,eyePoint:eyes,eyeDistance:44,slot:slot,transform:HatTransform(scale:1.6))
        try require(abs(slot.y+glasses.position.y-33*glasses.yScale-eyes.y)<0.001,"Resizing glasses moved their lenses off the eyes.")
        try accessoryProof(directory:directory)
        try screens(directory:directory)
        print("Library checks passed: 228 vector items, 108 Season 2 items, 30 achievements, 7 secrets; live 2× XP, independent tracks, unlock gating, persistent gifts, once-only claims, merge, backup and reset. Native Library screens and per-pet wearable fit sheets: \(directory.path)")
    }
    private static func accessoryProof(directory:URL) throws {
        let renderer=try MotionChecks.Renderer()
        let pets=PetStore.rigIDs.compactMap(PetStore.frameOriginal)+PetStore.imports
        var rows:[(String,[CGImage])]=[]
        for spec in pets {
            renderer.scene.removeAllChildren();let pet=try FramePetNode(spec:spec);pet.position=CGPoint(x:130,y:24);renderer.scene.addChild(pet)
            var images:[CGImage]=[]
            for id in ["free.sprout","free.bow","free.beanie","free.crown","accessory.glasses","free.s2.rainbow.0"] {
                pet.setAccessory(id);renderer.advance(0.02);images.append(try renderer.capture())
                guard let item=pet.childNode(withName:"//cosmetic") else{throw PawError.message("Missing rendered accessory for \(spec.id).")}
                try require(item.xScale.isFinite && item.xScale>0 && item.xScale<3,"Invalid fitted scale for \(spec.id).")
            }
            pet.setRenderingSuspended(true);rows.append((spec.name,images))
        }
        // Split the tall review sheets into manageable, inspectable pages.
        for start in stride(from:0,to:rows.count,by:8) {try MotionChecks.writeGrid(Array(rows[start..<min(start+8,rows.count)]),columns:["Sprout","Ear bow","Beanie","Crown","Glasses","Rainbow"],to:directory.appendingPathComponent("wearable-fit-\(start/8+1).png"))}
    }
    private static func screens(directory:URL) throws {
        let model=AppModel();defer{model.stop()};model.onboarding=false
        // Do not click real user controls or alter their inventory during previews.
        for section in [SettingsSection.gallery,.items,.achievements,.season2,.general,.activity] {
            model.settingsSection=section
            let host=NSHostingView(rootView:SettingsView(model:model))
            let window=NSWindow(contentRect:CGRect(x:0,y:0,width:1060,height:780),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=host
            host.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.2));host.layoutSubtreeIfNeeded()
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{throw PawError.message("Could not capture Library screen.")}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            guard let png=bitmap.representation(using:.png,properties:[:]) else{throw PawError.message("Could not encode Library screen.")}
            try png.write(to:directory.appendingPathComponent("library-\(section.id.lowercased().replacingOccurrences(of:" ",with:"-")).png"));window.close()
        }
    }
}
