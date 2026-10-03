import AppKit
import SpriteKit

/// Render the actual native controls and check their first-click routing.
@MainActor enum PetChromeChecks {
    static func run(directory:URL) throws {
        _=NSApplication.shared
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var calls:[String]=[]
        let menu=PetQuickActionsNativeView(palette:.companion("bunny")) { calls.append($0) }
        for button in menu.buttons {
            // Test near the edges too: clicking a whole paw, not just its text.
            for point in [CGPoint(x:button.frame.midX,y:button.frame.midY),CGPoint(x:button.frame.minX+5,y:button.frame.minY+10)] {
                guard menu.hitTest(menu.convert(point,to:menu.superview)) === button else { throw PawError.message("Quick-action hit testing missed \(button.title).") }
            }
            guard button.acceptsFirstMouse(for:nil),!button.needsPanelToBecomeKey else { throw PawError.message("A quick action requires a second activating click.") }
            button.performClick(nil)
        }
        guard Set(calls) == ["hello","water","reminder","focus","walk","files"],calls.count == 6,menu.hitTest(menu.convert(CGPoint(x:150,y:155),to:menu.superview)) == nil else { throw PawError.message("Pet actions or transparent menu center failed.") }
        var dismissed=0,snoozed=0
        let speech=PetSpeechNativeView(title:"A little sip?",text:"Your water bottle misses you. Let’s have a drink together!",reminder:true,actions:[],palette:.companion("bunny"),height:208,onDismiss:{dismissed+=1},onSnooze:{snoozed+=1})
        for button in speech.subviews.compactMap({$0 as? PetSoftButton}) {
            guard speech.hitTest(speech.convert(CGPoint(x:button.frame.midX,y:button.frame.midY),to:speech.superview)) === button else { throw PawError.message("Thought-bubble button is outside its hit region.") }
            button.performClick(nil)
        }
        guard dismissed == 2,snoozed == 1 else { throw PawError.message("Thought-bubble actions did not dispatch.") }
        guard speech.hitTest(speech.convert(CGPoint(x:0,y:0),to:speech.superview)) == nil else { throw PawError.message("Thought-bubble transparent corner intercepts clicks.") }
        let fixtures=[PetInboxFile(id:UUID().uuidString,name:"Weekend ideas.pdf",size:240_300,added:Date()),PetInboxFile(id:UUID().uuidString,name:"Little moments.png",size:1_324_000,added:Date())]
        for id in ["bunny","fox","openpets-default"] {
            let spec=PetStore.frameOriginal(id) ?? PetStore.imports.first(where:{$0.id == id})!
            let source=try DecodedPetImage(url:spec.directory.appendingPathComponent("spritesheet.webp"))
            let w=source.width/8,h=source.height/spec.rows
            let column=spec.rows == 11 ? 6:0
            guard let cell=source.image.cropping(to:CGRect(x:column*w,y:0,width:w,height:h)) else { throw PawError.message("Could not preview companion.") }
            let petImage=NSImage(cgImage:cell,size:CGSize(width:192,height:208))
            let palette=PetChromePalette.companion(id)
            for mode in ["actions","thought","pocket","drop"] {
                let root=PetChromePreviewView(frame:CGRect(x:0,y:0,width:640,height:470))
                let pet=NSImageView(frame:CGRect(x:396,y:252,width:192,height:208));pet.image=petImage;pet.imageScaling = .scaleAxesIndependently;root.addSubview(pet)
                let content:NSView
                switch mode {
                case "actions": content=PetQuickActionsNativeView(palette:palette,action:{_ in});content.frame.origin=CGPoint(x:342,y:147)
                case "thought": content=PetSpeechNativeView(title:"A little sip?",text:"Your water bottle misses you. Let’s have a drink together!",reminder:true,actions:[],palette:palette,height:208,onDismiss:{},onSnooze:{});content.frame.origin=CGPoint(x:210,y:43)
                default:
                    content=PetPocketNativeView(files:mode == "drop" ? []:fixtures,dropTarget:mode == "drop",palette:palette,name:id == "bunny" ? "Clover":id == "fox" ? "Maple":"Buddy",onOpen:{_ in},onRemove:{_ in},onFolder:{},onClose:{},onDrop:{_ in false},canDrop:{_ in true},onDragging:{_ in})
                    content.frame.origin=CGPoint(x:120,y:195)
                    if mode == "pocket" {
                        let held=NSImageView(frame:CGRect(x:470,y:402,width:44,height:42));held.image=PetChromeDrawing.heldPocket(size:CGSize(width:44,height:42),palette:palette,count:2);root.addSubview(held)
                    }
                }
                root.addSubview(content)
                let window=NSWindow(contentRect:root.bounds,styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=root
                root.layoutSubtreeIfNeeded()
                func invalidate(_ view:NSView) { view.needsDisplay=true;view.subviews.forEach(invalidate) };invalidate(root)
                guard let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else { throw PawError.message("Could not render companion controls.") }
                root.cacheDisplay(in:root.bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else { throw PawError.message("Could not encode companion preview.") }
                try png.write(to:directory.appendingPathComponent("\(id)-\(mode).png"));window.close()
            }
            let node=try FramePetNode(spec:spec);let scene=SKScene(size:CGSize(width:280,height:260));scene.addChild(node);node.position=CGPoint(x:140,y:32)
            node.setHeldFileCount(2)
            guard node.containsHeldFilesPoint(CGPoint(x:140,y:68)) else { throw PawError.message("Held pocket has no interactive region.") }
            node.setHeldFileCount(0)
            guard !node.containsHeldFilesPoint(CGPoint(x:140,y:68)) else { throw PawError.message("Empty held pocket stayed interactive.") }
            node.setRenderingSuspended(true)
        }
        print("Companion UI checks passed: six whole-paw/first-click targets dispatch; empty menu center passes through; thought dismiss/done/snooze dispatch; held-pocket hit region disappears when empty. Rendered 12 native previews at \(directory.path).")
    }
}

@MainActor private final class PetChromePreviewView:NSView {
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.97,green:0.95,blue:0.92,alpha:1).setFill();bounds.fill()
    }
}
