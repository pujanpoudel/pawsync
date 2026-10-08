import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

@MainActor enum EmotionChecks {
    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw PawError.message(message) } }
        let renderer=try MotionChecks.Renderer()
        let reference=PetStore.imports.filter{$0.origin == "Paw-Paw preview"}
        try require(reference.count == 31,"The reference collection does not have all 31 free varieties.")
        let pets=PetStore.rigIDs.compactMap(PetStore.frameOriginal)+PetStore.imports
        try require(pets.contains{$0.id == "knight-cat" && $0.name == "Knight Cat"},"Knight Cat is not registered in the companion gallery.")
        let columns=PetEmotion.allCases.map(\.title)+["Cuddle dance","Reach out","Caught it","Holding","Fast typing"]
        for spec in pets {
            renderer.scene.removeAllChildren()
            let pet=try FramePetNode(spec:spec);pet.position=CGPoint(x:130,y:24);renderer.scene.addChild(pet)
            if spec.source == "PawSync" || spec.origin == "Paw-Paw preview" {
                try require(PetExpressionProfile.load(spec.directory) != nil,"Missing or invalid facial landmarks for \(spec.name).")
            }
            if let profile=PetExpressionProfile.load(spec.directory) {
                let face=PetExpressionNode(profile:profile,id:spec.id);face.show(.curious)
                try require(face.children.flatMap(\.children).compactMap{$0 as? SKShapeNode}.allSatisfy{$0.fillColor.alphaComponent == 0},"Surprise replaced the original eyes for \(spec.name).")
            }
            if spec.origin == "Paw-Paw preview" {
                try require(PetExpressionProfile.load(spec.directory)?.fullBody == true && pet.hasNativeFilePoses,"\(spec.name) still uses a partial-body preview or lacks authored catching poses.")
                pet.face(-1);pet.setWalking(true);renderer.advance(0.3);pet.setWalking(false);pet.face(1)
            }
            var images:[CGImage]=[]
            for emotion in PetEmotion.allCases {
                pet.express(emotion);renderer.advance(0.24)
                try require(pet.currentEmotion == emotion,"Wrong facial state for \(spec.name).")
                images.append(try renderer.capture());pet.idle()
            }
            pet.cuddle();renderer.advance(0.3)
            try require(pet.requiresContinuousRendering,"Direct affection was not animated for \(spec.name).")
            try require(abs(pet.bodyRotation)<0.001,"Click hop rotated around the feet for \(spec.name).")
            if spec.id == "knight-cat" { try require(pet.displayedFilePose == "cheer","Knight Cat did not lift both paws for its click hop.") }
            try require(pet.affectionLift > 8,"Direct-click kitten hop did not leave the ground for \(spec.name).")
            if spec.id == "bunny" {
                try require(pet.displayedFilePose == nil && pet.currentFrame.row == 4 && pet.currentFrame.column == 2,"Rabbit click hop reused the extra-paw catching pose.")
            }
            images.append(try renderer.capture());pet.typing();renderer.advance(0.1);pet.idle()
            try require(pet.affectionLift == 0,"Typing did not interrupt the click hop for \(spec.name).")
            pet.cuddle();renderer.advance(PetClickMotion.duration+0.1)
            try require(abs(pet.affectionLift)<0.01,"Direct-click hop did not land for \(spec.name).")
            pet.idle()
            if spec.id == "bunny" {
                var hops:[CGImage]=[];pet.cuddle()
                for step in [0.02,0.18,0.12,0.23,0.24,0.13,0.48] {renderer.advance(step);hops.append(try renderer.capture())}
                try MotionChecks.writeGrid([(spec.name,hops)],columns:["Crouch","Takeoff","First hop","Landing","Second takeoff","Second hop","Rest"],to:directory.appendingPathComponent("bunny-click-hop.png"))
                pet.idle()
            }
            if spec.id == "knight-cat" {
                try require(pet.hasNativeFilePoses && PetExpressionProfile.load(spec.directory)?.fullBody == true,"Knight Cat is missing full-body or catching resources.")
                var hops:[CGImage]=[];pet.cuddle()
                for step in [0.02,0.12,0.18,0.20,0.23,0.18,0.47] { renderer.advance(step);hops.append(try renderer.capture()) }
                try MotionChecks.writeGrid([(spec.name,hops)],columns:["Rest","Crouch","First hop","Landing","Crouch again","Second hop","Settled"],to:directory.appendingPathComponent("knight-cat-click-hop.png"));pet.idle()
                var motions:[CGImage]=[]
                pet.ambientBreath();renderer.advance(0.45);motions.append(try renderer.capture());pet.idle()
                for action in [0,1,2,3,4,5] {
                    switch action {
                    case 0: pet.typing(at:ProcessInfo.processInfo.systemUptime+1)
                    case 1: pet.setWalking(true)
                    case 2: pet.wave()
                    case 3: pet.reminderGesture("stretch")
                    case 4: pet.pet(direction:4)
                    default: pet.setDancing(true,beat:0.5)
                    }
                    renderer.advance(0.19);motions.append(try renderer.capture())
                    if action == 0 { try require(pet.tappedPawDisplacement.y>2,"Knight Cat's actual typing hand did not move.") }
                    if action == 1 { try require(pet.affectionLift>0,"Knight Cat's gait has no body bounce.") }
                    pet.setDancing(false,beat:0.5);pet.idle()
                }
                try MotionChecks.writeGrid([(spec.name,motions)],columns:["Breathe","Paw tap","Walk","Greeting","Stretch","Cuddle","Dance"],to:directory.appendingPathComponent("knight-cat-fluid-motions.png"))
                let gifURL=directory.appendingPathComponent("knight-cat-fluid.gif")
                guard let gif=CGImageDestinationCreateWithURL(gifURL as CFURL,UTType.gif.identifier as CFString,120,nil) else { throw PawError.message("Could not export Knight Cat's motion preview.") }
                CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
                let pulseClock=ProcessInfo.processInfo.systemUptime+2
                pet.setWalking(true)
                for frame in 0..<120 {
                    if frame == 39 { pet.setWalking(false) }
                    if (39..<75).contains(frame),frame.isMultiple(of:4) { pet.typing(at:pulseClock+Double(frame)/30) }
                    if frame == 75 { pet.cuddle() }
                    renderer.advance(1.0/30)
                    CGImageDestinationAddImage(gif,try renderer.capture(),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/30,kCGImagePropertyGIFUnclampedDelayTime:1.0/30]] as CFDictionary)
                }
                try require(CGImageDestinationFinalize(gif),"Could not finish the native animation preview.");pet.idle()
                let profile=PetExpressionProfile.load(spec.directory)!
                let grid=KnightCatMotion.geometry(.tapLeft,phase:0.5,profile:profile)
                let paw=profile.pawCenters[0]
                let index=Int((paw[1]*Double(KnightCatMotion.rows)).rounded())*(KnightCatMotion.columns+1)+Int((paw[0]*Double(KnightCatMotion.columns)).rounded())
                let source=KnightCatMotion.sourcePoint(grid.destPosition(at:index),in:grid)
                try require(source != nil && abs(source!.y-grid.sourcePosition(at:index).y)<0.001,"Animated hand hit testing does not follow the visible paw.")
                pet.ambientBreath(at:ProcessInfo.processInfo.systemUptime+20)
                try require(pet.remainingAnimationDuration>2,"The render window truncates Knight Cat's idle motion.")
                pet.setSleeping(true);try require(!pet.requiresContinuousRendering,"Sleeping Knight Cat kept an active rendering deadline.");pet.setSleeping(false)
            }
            pet.setReceivingFiles(true);renderer.advance(0.3)
            try require(pet.receivingFiles && (pet.hasNativeFilePoses ? pet.displayedFilePose == "receive" : pet.leftPawDisplacement.x < -3 && pet.leftPawDisplacement.y > 5),"\(spec.name) did not visibly open its arms.")
            images.append(try renderer.capture())
            pet.typing();pet.click(toward:.zero)
            try require(pet.receivingFiles,"Typing or a click interrupted file receiving.")
            pet.setReceivingFiles(false);renderer.advance(0.1)
            try require(!pet.receivingFiles && pet.leftPawDisplacement == .zero,"Canceled file drag left open arms on \(spec.name).")
            pet.setHeldFileCount(2);pet.setReceivingFiles(true);renderer.advance(0.25);pet.catchFiles();renderer.advance(0.21)
            try require(!pet.receivingFiles && (pet.hasNativeFilePoses ? pet.displayedFilePose == "hold" : pet.leftPawDisplacement.x > 1),"\(spec.name) did not close its arms to catch.")
            images.append(try renderer.capture());pet.idle();renderer.advance(0.03);images.append(try renderer.capture())
            let holdPoint=pet.heldFilesPointInScene
            try require(pet.containsHeldFilesPoint(holdPoint),"Held files cannot be hovered on \(spec.name).")
            pet.setHeldFileCount(0);pet.idle()
            try require(pet.leftPawDisplacement == .zero && pet.displayedFilePose == nil && !pet.containsHeldFilesPoint(holdPoint),"Empty hands did not return to rest on \(spec.name).")
            let now=ProcessInfo.processInfo.systemUptime+10
            for index in 0..<10 { pet.typing(at:now+Double(index)*0.08) }
            pet.advanceFrame(at:now+0.75);renderer.advance(0.1);images.append(try renderer.capture());pet.idle()
            pet.setRenderingSuspended(true)
            try MotionChecks.writeGrid([(spec.name,images)],columns:columns,to:directory.appendingPathComponent("\(spec.id)-expressions.png"))
        }
        for id in PetStore.rigIDs {
            renderer.scene.removeAllChildren()
            let pet=try PetSpriteNode(manifest:PetStore.load(id),directory:PetStore.directory(for:id));pet.position=CGPoint(x:130,y:38);renderer.scene.addChild(pet)
            let rest=pet.joints["left_paw"]!.position
            pet.setReceivingFiles(true);renderer.advance(0.3)
            try require(pet.joints["left_paw"]!.position.x<rest.x-3 && pet.joints["left_paw"]!.zRotation < -0.7,"Custom rig did not open its arms: \(id).")
            pet.setReceivingFiles(false);renderer.advance(0.1)
            try require(pet.joints["left_paw"]!.position == rest,"Canceled rig drag did not restore arms: \(id).")
        }
        print("Emotion checks passed: \(pets.count) pets × \(PetEmotion.allCases.count) emotions; direct cuddle dance, 31 reference varieties; measured arm opening, catch/hug, cancellation, holding/empty hit targets, and nine fallback rigs. Native character sheets: \(directory.path)")
    }
}
