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
            guard !button.caption.isHidden,button.caption.stringValue == button.title,button.caption.font?.pointSize == 11,button.caption.fittingSize.width <= button.caption.frame.width,button.bounds.contains(button.caption.frame) else { throw PawError.message("Quick-action label is hidden or clipped: \(button.title).") }
            guard menu.hitTest(menu.convert(CGPoint(x:button.frame.midX,y:button.frame.minY+65),to:menu.superview)) === button else { throw PawError.message("The action caption does not click the whole paw.") }
            button.performClick(nil)
        }
        guard Set(calls) == ["hello","water","reminder","focus","walk","files"],calls.count == 6,menu.hitTest(menu.convert(CGPoint(x:150,y:155),to:menu.superview)) == nil else { throw PawError.message("Pet actions or transparent menu center failed.") }
        let overlay=OverlayController(preferences:Preferences())
        defer { overlay.stop() }
        try overlay.loadPet("bunny")
        var opened=0;overlay.showQuickActions={opened+=1}
        func pointer(_ type:NSEvent.EventType,clicks:Int=0)->NSEvent {
            NSEvent.mouseEvent(with:type,location:CGPoint(x:140,y:100),modifierFlags:[],timestamp:0,windowNumber:overlay.window.windowNumber,context:nil,eventNumber:0,clickCount:clicks,pressure:0)!
        }
        let movement=pointer(.mouseMoved)
        overlay.view.mouseEntered(with:movement);overlay.view.mouseMoved(with:movement)
        overlay.view.mouseDown(with:pointer(.leftMouseDown,clicks:1));overlay.view.mouseUp(with:pointer(.leftMouseUp,clicks:1))
        guard opened == 0,overlay.view.acceptsFirstMouse(for:nil) else { throw PawError.message("Hover or a single click opened the menu, or the first tap was ignored.") }
        overlay.view.mouseDown(with:pointer(.leftMouseDown,clicks:2));overlay.view.mouseUp(with:pointer(.leftMouseUp,clicks:2))
        overlay.view.mouseDown(with:pointer(.leftMouseDown,clicks:3))
        guard opened == 1,!overlay.isInteracting else { throw PawError.message("Double tap did not open the menu exactly once.") }
        var dismissed=0,snoozed=0
        let speech=PetSpeechNativeView(title:"A little sip?",text:"Your water bottle misses you. Let’s have a drink together!",reminder:true,actions:[],palette:.companion("bunny"),height:208,onDismiss:{dismissed+=1},onSnooze:{snoozed+=1})
        for button in speech.subviews.compactMap({$0 as? PetSoftButton}) {
            guard speech.hitTest(speech.convert(CGPoint(x:button.frame.midX,y:button.frame.midY),to:speech.superview)) === button else { throw PawError.message("Thought-bubble button is outside its hit region.") }
            button.performClick(nil)
        }
        guard dismissed == 2,snoozed == 1 else { throw PawError.message("Thought-bubble actions did not dispatch.") }
        guard speech.hitTest(speech.convert(CGPoint(x:0,y:0),to:speech.superview)) == nil else { throw PawError.message("Thought-bubble transparent corner intercepts clicks.") }
        let fixtures=[PetInboxFile(id:UUID().uuidString,name:"Weekend ideas.pdf",size:240_300,added:Date(),url:URL(fileURLWithPath:"/tmp/Weekend ideas.pdf")),PetInboxFile(id:UUID().uuidString,name:"Little moments.png",size:1_324_000,added:Date(),url:URL(fileURLWithPath:"/tmp/Little moments.png"))]
        var cleared=0
        let pocket=PetPocketNativeView(files:fixtures,dropTarget:false,palette:.companion("hamster"),name:"Peaches",onOpen:{_ in},onRemove:{_ in},onFolder:{},onClose:{},onDrop:{_ in false},canDrop:{_ in true},onDragging:{_ in},onClear:{cleared+=1})
        guard let clear=pocket.subviews.compactMap({$0 as? PetSoftButton}).first(where:{$0.title == "Clear all"}),pocket.hitTest(pocket.convert(CGPoint(x:clear.frame.midX,y:clear.frame.midY),to:pocket.superview)) === clear else { throw PawError.message("Clear all is missing or not clickable.") }
        clear.performClick(nil)
        guard cleared == 1 else { throw PawError.message("Clear all did not dispatch.") }
        for id in ["bunny","fox","hamster","openpets-default","pawpaw-season2-frog","pawpaw-season2-axolotl","knight-cat"] {
            let spec=PetStore.frameOriginal(id) ?? PetStore.imports.first(where:{$0.id == id})!
            let source=try DecodedPetImage(url:spec.directory.appendingPathComponent("spritesheet.webp"))
            let w=source.width/8,h=source.height/spec.rows
            let column=spec.rows == 11 ? 6:0
            guard let cell=source.image.cropping(to:CGRect(x:column*w,y:0,width:w,height:h)) else { throw PawError.message("Could not preview companion.") }
            let petImage=NSImage(cgImage:cell,size:CGSize(width:192,height:208))
            let palette=PetChromePalette.companion(id)
            for mode in ["actions","actions-dark","thought","thought-dark","pocket","drop"] {
                let root=PetChromePreviewView(frame:CGRect(x:0,y:0,width:640,height:470))
                if mode.hasSuffix("-dark") { root.background=NSColor(calibratedRed:0.12,green:0.10,blue:0.18,alpha:1) }
                let pet=NSImageView(frame:CGRect(x:396,y:252,width:192,height:208));pet.image=petImage;pet.imageScaling = .scaleAxesIndependently;root.addSubview(pet)
                let content:NSView
                switch mode {
                case "actions","actions-dark": content=PetQuickActionsNativeView(palette:palette,action:{_ in});content.frame.origin=CGPoint(x:291,y:125)
                case "thought","thought-dark": content=PetSpeechNativeView(title:"A little sip?",text:"Your water bottle misses you. Let’s have a drink together!",reminder:true,actions:[],palette:palette,height:208,onDismiss:{},onSnooze:{});content.frame.origin=CGPoint(x:210,y:43)
                default:
                    content=PetPocketNativeView(files:mode == "drop" ? []:fixtures,dropTarget:mode == "drop",palette:palette,name:id == "bunny" ? "Clover":id == "fox" ? "Maple":"Buddy",onOpen:{_ in},onRemove:{_ in},onFolder:{},onClose:{},onDrop:{_ in false},canDrop:{_ in true},onDragging:{_ in})
                    content.frame.origin=CGPoint(x:120,y:195)
                    if mode == "pocket" {
                        let held=NSImageView(frame:CGRect(x:477,y:408,width:34,height:32));held.image=PetChromeDrawing.heldNote(size:CGSize(width:34,height:32),palette:palette,count:2);root.addSubview(held)
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
            let heldPoint=node.heldFilesPointInScene
            guard node.containsHeldFilesPoint(heldPoint) else { throw PawError.message("Held pocket has no interactive region.") }
            node.setHeldFileCount(0)
            guard !node.containsHeldFilesPoint(heldPoint) else { throw PawError.message("Empty held pocket stayed interactive.") }
            node.setRenderingSuspended(true)
        }
        print("Companion UI checks passed: double-tap-only actions; readable whole-paw targets; thought dismiss/done/snooze; Clear all dispatch; empty held-note hit region. Rendered 42 native previews, including dark backgrounds and seven pet palettes, at \(directory.path).")
    }
}

@MainActor private final class PetChromePreviewView:NSView {
    var background=NSColor(calibratedRed:0.97,green:0.95,blue:0.92,alpha:1)
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        background.setFill();bounds.fill()
    }
}
