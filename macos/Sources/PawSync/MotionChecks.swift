import AppKit
import SpriteKit
import Metal
import ImageIO
import UniformTypeIdentifiers

/// Offscreen native rendering: no input capture, TCC prompts, or UI automation.
@MainActor enum MotionChecks {
    @MainActor private final class Renderer {
        let renderer:SKRenderer
        let queue:any MTLCommandQueue
        let texture:any MTLTexture
        let scene=SKScene(size:CGSize(width:260,height:260))
        var time:TimeInterval=1
        init() throws {
            guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else { throw PawError.message("Metal is unavailable for the motion check.") }
            self.queue=queue; renderer=SKRenderer(device:device)
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:260,height:260,mipmapped:false)
            descriptor.usage = .renderTarget; descriptor.storageMode = .shared
            guard let texture=device.makeTexture(descriptor:descriptor) else { throw PawError.message("Could not create a render target.") }
            self.texture=texture; scene.backgroundColor=NSColor(calibratedRed:0.97,green:0.96,blue:0.99,alpha:1); renderer.scene=scene
            renderer.update(atTime:time)
        }
        func advance(_ duration:TimeInterval) {
            for _ in 0..<Int(ceil(duration*60)) { time+=1.0/60; renderer.update(atTime:time) }
        }
        func capture() throws -> CGImage {
            let pass=MTLRenderPassDescriptor(); pass.colorAttachments[0].texture=texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0.97,0.96,0.99,1)
            guard let buffer=queue.makeCommandBuffer() else { throw PawError.message("Could not create a command buffer.") }
            renderer.render(withViewport:CGRect(x:0,y:0,width:260,height:260),commandBuffer:buffer,renderPassDescriptor:pass)
            buffer.commit(); buffer.waitUntilCompleted()
            if let error=buffer.error { throw error }
            var pixels=[UInt8](repeating:0,count:260*260*4)
            pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow:260*4,from:MTLRegionMake2D(0,0,260,260),mipmapLevel:0) }
            guard let provider=CGDataProvider(data:Data(pixels) as CFData),let image=CGImage(width:260,height:260,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:260*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { throw PawError.message("Could not read the render target.") }
            return image
        }
    }
    private static func require(_ condition:@autoclosure ()->Bool,_ message:String) throws {
        guard condition() else { throw PawError.message(message) }
    }
    private static func writeGrid(_ rows:[(String,[CGImage])],columns:[String],to url:URL) throws {
        let width=columns.count*260,height=rows.count*290+40
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PawError.message("Could not create proof sheet.") }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x:0,y:0,width:width,height:height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        for (column,title) in columns.enumerated() { (title as NSString).draw(at:CGPoint(x:column*260+18,y:height-30),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:NSColor.black]) }
        for (row,pair) in rows.enumerated() {
            let y=height-40-(row+1)*290
            (pair.0 as NSString).draw(at:CGPoint(x:18,y:y+4),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:NSColor.darkGray])
            for (column,image) in pair.1.enumerated() { context.draw(image,in:CGRect(x:column*260,y:y+26,width:260,height:260)) }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image=context.makeImage(),let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw PawError.message("Could not write proof sheet.") }
        CGImageDestinationAddImage(destination,image,nil); guard CGImageDestinationFinalize(destination) else { throw PawError.message("Could not finish proof sheet.") }
    }
    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // Exact finite-cycle endpoints and monotonic frames match the upstream contract.
        for animation in PetAnimation.allCases {
            let clip=PetFrameSequence(row:animation.row,frames:animation.frames,duration:animation.duration,iterations:2)
            for cycle in 0..<2 { for frame in 0..<animation.frames {
                let sample=(Double(cycle)+(Double(frame)+0.5)/Double(animation.frames))*animation.duration
                try require(clip.column(at:sample) == frame,"Frame timing mismatch for \(animation.rawValue).")
            } }
            try require(clip.column(at:animation.duration*2) == nil,"A finite animation did not finish.")
        }
        let renderer=try Renderer()
        renderer.renderer.shouldCullNonVisibleNodes=true
        let driver=SKNode(); driver.position=CGPoint(x:1200,y:100); renderer.scene.addChild(driver)
        let path=CGMutablePath(); path.move(to:driver.position); path.addLine(to:CGPoint(x:1000,y:100))
        driver.run(.follow(path,asOffset:false,orientToPath:false,duration:1.2))
        renderer.advance(0.6)
        try require(driver.position.x < 1190,"An offscreen travel action did not advance.")
        let arc=CGMutablePath(); arc.move(to:CGPoint(x:1200,y:100)); arc.addQuadCurve(to:CGPoint(x:1000,y:100),control:CGPoint(x:1100,y:300))
        driver.removeAllActions(); driver.position=CGPoint(x:1200,y:100)
        driver.run(.follow(arc,asOffset:false,orientToPath:false,duration:1.68))
        renderer.advance(0.84)
        try require(driver.position.y > 150,"The authored jump arc did not rise.")
        driver.removeFromParent()
        var originals:[(String,[CGImage])]=[]
        for id in PetStore.rigIDs {
            renderer.scene.removeAllChildren()
            let node=try PetSpriteNode(manifest:PetStore.load(id),directory:PetStore.directory(for:id))
            node.position=CGPoint(x:130,y:38); renderer.scene.addChild(node)
            let origin=node.position,rest=node.joints["body"]!.position
            node.idle(); renderer.advance(0.3); var images=[try renderer.capture()]
            node.pet(direction:6); renderer.advance(0.32); images.append(try renderer.capture())
            node.setWalking(true); renderer.advance(0.24); images.append(try renderer.capture())
            node.setWalking(false)
            try require(node.joints["body"]!.position == rest && node.joints["body"]!.zRotation == 0,"Walking left a displaced body: \(id).")
            node.celebrate(); renderer.advance(0.34); images.append(try renderer.capture())
            renderer.advance(1.2)
            try require(abs(node.joints["body"]!.position.y-rest.y) < 0.01,"Celebration did not land: \(id).")
            node.setSleeping(true); renderer.advance(0.7); images.append(try renderer.capture())
            node.setSleeping(false); renderer.advance(0.7)
            for _ in 0..<6 {
                node.setDancing(true,beat:0.5); renderer.advance(0.12); node.setDancing(false,beat:0.5)
                node.reminderGesture("custom"); renderer.advance(0.1); node.click(toward:.zero); renderer.advance(0.7)
            }
            try require(node.position == origin && abs(node.joints["body"]!.position.y-rest.y) < 0.01,"Interrupted motions accumulated position drift: \(id).")
            try require(node.joints["head"]?.childNode(withName:"sleep-eyes") == nil,"Sleep expression survived waking: \(id).")
            originals.append((PetStore.rigNames[id] ?? id,images))
        }
        try writeGrid(originals,columns:["Resting","Happy / petting","Walking","Jump","Sleeping"],to:directory.appendingPathComponent("original-motions.png"))
        var frameOriginals:[(String,[CGImage])]=[]
        for id in PetStore.rigIDs {
            guard let spec=PetStore.frameOriginal(id) else { throw PawError.message("Missing frame atlas for \(id).") }
            renderer.scene.removeAllChildren()
            let node=try FramePetNode(spec:spec); node.position=CGPoint(x:130,y:24); renderer.scene.addChild(node)
            try require(node.containsOpaquePoint(CGPoint(x:130,y:115)),"The original pet cannot receive a body click: \(id).")
            try require(!node.containsOpaquePoint(CGPoint(x:10,y:10)),"Transparent space blocks clicks around \(id).")
            renderer.advance(0.02); var images=[try renderer.capture()]
            node.setWalking(true); node.advanceFrame(at:node.frameStartedAt+0.21)
            renderer.advance(0.02); images.append(try renderer.capture())
            node.setWalking(false); node.play(.jumping,looping:false,relaxed:false)
            node.advanceFrame(at:node.frameStartedAt+0.43)
            renderer.advance(0.02); images.append(try renderer.capture())
            node.wave(); node.advanceFrame(at:node.frameStartedAt+0.27)
            renderer.advance(0.02); images.append(try renderer.capture())
            node.typing(); node.advanceFrame(at:node.frameStartedAt+0.20)
            renderer.advance(0.02); images.append(try renderer.capture())
            node.idle(); node.look(toward:CGPoint(x:200,y:120))
            try require(node.sequence?.row == 3,"Cursor dwell did not greet for \(id).")
            node.pet(direction:7)
            try require(node.sequence?.row == 8,"Petting did not show a distinct happy expression for \(id).")
            frameOriginals.append((spec.name,images))
            node.setRenderingSuspended(true)
        }
        try writeGrid(frameOriginals,columns:["Resting","Walking","Jump","Wave","Working paws"],to:directory.appendingPathComponent("original-frame-motions.png"))
        var fittedAccessories:[(String,[CGImage])]=[]
        for id in PetStore.rigIDs {
            guard let spec=PetStore.frameOriginal(id) else { continue }
            renderer.scene.removeAllChildren()
            let node=try FramePetNode(spec:spec); node.position=CGPoint(x:130,y:24); renderer.scene.addChild(node)
            guard let slot=node.childNode(withName:"//head-accessories") else { throw PawError.message("Missing accessory slot for \(id).") }
            let idleCrown=slot.position
            var images:[CGImage]=[]
            for sku in ["free.sprout","free.bow","free.beanie","accessory.glasses"] {
                node.setAccessory(sku); node.presentation(flipped:false,hudScale:1,hat:HatTransform())
                renderer.advance(0.02); images.append(try renderer.capture())
            }
            node.setAccessory("free.crown"); node.setWalking(true); node.advanceFrame(at:node.frameStartedAt+0.21)
            try require(abs(slot.position.x-idleCrown.x)>25,"Walking accessory did not follow \(id)'s head.")
            renderer.advance(0.02); images.append(try renderer.capture())
            node.setWalking(false); node.play(.jumping,looping:false,relaxed:false); node.advanceFrame(at:node.frameStartedAt+0.43)
            try require(slot.position.y < idleCrown.y-12,"Jumping accessory did not follow \(id)'s head.")
            renderer.advance(0.02); images.append(try renderer.capture())
            node.setAccessory("free.beanie"); renderer.advance(0.02); images.append(try renderer.capture())
            node.advanceFrame(at:node.frameStartedAt+0.02); renderer.advance(0.02); images.append(try renderer.capture())
            node.advanceFrame(at:node.frameStartedAt+0.20); renderer.advance(0.02); images.append(try renderer.capture())
            node.setRenderingSuspended(true)
            fittedAccessories.append((spec.name,images))
        }
        try writeGrid(fittedAccessories,columns:["Sprout","Bow","Beanie","Glasses","Walk + crown","Jump + crown","Jump + beanie","Jump start + beanie","Jump rise + beanie"],to:directory.appendingPathComponent("accessory-fit.png"))
        var imports:[(String,[CGImage])]=[]
        for spec in PetStore.imports {
            renderer.scene.removeAllChildren()
            let node=try FramePetNode(spec:spec); node.position=CGPoint(x:130,y:24); renderer.scene.addChild(node)
            renderer.advance(0.02); var images=[try renderer.capture()]
            for (animation,elapsed) in [(PetAnimation.waving,0.22),(.running,0.30),(.jumping,0.32),(.failed,0.60)] {
                node.play(animation,looping:false,relaxed:false); node.advanceFrame(at:node.frameStartedAt+elapsed)
                renderer.advance(0.02); images.append(try renderer.capture())
            }
            node.play(.jumping,looping:false,relaxed:false); let start=node.frameStartedAt
            node.setRenderingSuspended(true); node.advanceFrame(at:start+1)
            try require(node.currentFrame.row == 4 && node.currentFrame.column == 0,"Suspended sprite advanced: \(spec.id).")
            node.setRenderingSuspended(false); node.advanceFrame(at:node.frameStartedAt+1.7)
            try require(node.currentFrame.row == 0,"Finite imported reaction did not return to idle: \(spec.id).")
            var draws=0; node.onNeedsRender={draws+=1}
            if spec.rows == 11 { for _ in 0..<30 { node.idle() }; try require(draws == 0,"Static V2 idle requested redundant drawing.") }
            node.setRenderingSuspended(true); node.onNeedsRender=nil
            imports.append((spec.name,images))
        }
        try writeGrid(imports,columns:["Neutral","Wave","Typing / work","Jump","Oops"],to:directory.appendingPathComponent("openpets-motions.png"))
        var importedAccessories:[(String,[CGImage])]=[]
        for spec in PetStore.imports {
            renderer.scene.removeAllChildren()
            let node=try FramePetNode(spec:spec); node.position=CGPoint(x:130,y:24); renderer.scene.addChild(node)
            var images:[CGImage]=[]
            for sku in ["free.sprout","free.bow","free.beanie","accessory.glasses"] {
                node.setAccessory(sku); node.presentation(flipped:false,hudScale:1,hat:HatTransform())
                renderer.advance(0.02); images.append(try renderer.capture())
            }
            node.setRenderingSuspended(true)
            importedAccessories.append((spec.name,images))
        }
        try writeGrid(importedAccessories,columns:["Sprout","Bow","Beanie","Glasses"],to:directory.appendingPathComponent("openpets-accessory-fit.png"))
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("PawSync-activity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:temporary) }
        let activity=CompanionActivity(directory:temporary); var levels=0,goals=0
        activity.onLevelUp={levels+=1}; activity.onGoalReached={goals+=1}
        for _ in 0..<700 { activity.record(goal:100) }
        try require(activity.snapshot.total == 0 && activity.level == 2 && levels == 1 && goals == 1,"Batched activity lost a threshold or published per event.")
        activity.stop()
        let restored=CompanionActivity(directory:temporary); defer { restored.stop() }
        try require(restored.snapshot.total == 700 && restored.snapshot.today == 700,"Pending activity was not saved on shutdown.")
        try overlayTravel()
        print("Motion checks passed: nine frame-animated originals and nine fallback rigs rendered; interrupted walk/dance/reminder/jump settle without drift; imported authored frame timing, completion, suspension and static-idle draw checks; batched activity persistence. Proof sheets: \(directory.path)")
    }
    private static func overlayTravel() throws {
        let preferences=Preferences()
        guard !preferences.hidden,!preferences.reactionsPaused else { return }
        let controller=OverlayController(preferences:preferences)
        controller.window.alphaValue=0
        defer { controller.stop() }
        try controller.loadPet("openpets-default")
        try require(controller.view.hitTest(CGPoint(x:140,y:136)) === controller.view,"The pet's opaque center did not receive view clicks.")
        try require(controller.view.hitTest(CGPoint(x:3,y:250)) == nil,"Transparent space intercepted background clicks.")
        let start=controller.window.frame.origin
        controller.wanderNow()
        RunLoop.main.run(until:Date().addingTimeInterval(1.2))
        try require(abs(controller.window.frame.minX-start.x) > 12,"The Walk control did not move the real overlay window.")
        let bottom=controller.window.frame.minY
        controller.jumpNow()
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        try require(controller.window.frame.minY > bottom+15,"The Jump control did not lift the real overlay window.")
    }
}
