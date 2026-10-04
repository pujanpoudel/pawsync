import AppKit
import SpriteKit

@MainActor enum EmotionChecks {
    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw PawError.message(message) } }
        let renderer=try MotionChecks.Renderer()
        let reference=PetStore.imports.filter{$0.origin == "Paw-Paw preview"}
        try require(reference.count == 31,"The reference collection does not have all 31 free varieties.")
        let pets=PetStore.rigIDs.compactMap(PetStore.frameOriginal)+PetStore.imports
        let columns=PetEmotion.allCases.map(\.title)+["Cuddle dance","Reach out","Caught it","Holding","Fast typing"]
        for spec in pets {
            renderer.scene.removeAllChildren()
            let pet=try FramePetNode(spec:spec);pet.position=CGPoint(x:130,y:24);renderer.scene.addChild(pet)
            if spec.source == "PawSync" || spec.origin == "Paw-Paw preview" {
                try require(PetExpressionProfile.load(spec.directory) != nil,"Missing or invalid facial landmarks for \(spec.name).")
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
            images.append(try renderer.capture());pet.typing();renderer.advance(0.1);pet.idle()
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
            let now=ProcessInfo.processInfo.systemUptime
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
