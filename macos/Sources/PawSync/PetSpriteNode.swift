import AppKit
import SpriteKit

@MainActor final class PetSpriteNode: SKNode, CompanionAnimating {
    private(set) var joints: [String: SKSpriteNode] = [:]
    let accessorySlot = SKNode()
    private var alphaImages: [String: PetAlphaMask] = [:]
    private var eyelidColors:[NSColor]=[]
    private var sourceRects: [String: CGRect] = [:]
    private var eyeLocations: [[Double]]?
    private let sleepLabel = SKLabelNode(fontNamed: NSFont.systemFont(ofSize:19,weight:.semibold).fontName)
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 115, height: 14))
    private var nextLeftPaw = true
    private(set) var lastTappedPaw: String?
    private let caption = SKLabelNode(fontNamed: NSFont.systemFont(ofSize:10,weight:.semibold).fontName)
    private var restPositions: [String: CGPoint] = [:]
    private(set) var sleeping = false
    var onNeedsRender:(()->Void)?
    private var motionMode="idle"
    private var lastTap:TimeInterval = -1
    private var lastStroke:TimeInterval = -1
    private var clickMood=0
    private var accessorySKU="none"
    private var hatTransform=HatTransform()

    init(manifest: PetManifest, directory: URL) throws {
        super.init()
        try manifest.validate()
        shadow.fillColor = .black.withAlphaComponent(0.14)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -10
        addChild(shadow)

        var bitmaps: [String: DecodedPetImage] = [:]
        for key in PetManifest.required {
            let part = manifest.parts[key]!
            let url = directory.appendingPathComponent(part.file ?? "\(key).png")
            let filename = url.lastPathComponent
            if bitmaps[filename] == nil {
                let bitmap=try DecodedPetImage(url:url,maximumDimension:2048)
                bitmaps[filename] = bitmap
            }
            let bitmap = bitmaps[filename]!
            let full = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            let values = part.textureRect
            let rect = values.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) } ?? full
            guard full.contains(rect), rect.width <= 512, rect.height <= 512 else { throw PawError.message("Texture region is outside its atlas.") }
            guard let crop=bitmap.image.cropping(to:rect),
                  let context=CGContext(data:nil,width:Int(rect.width),height:Int(rect.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PawError.message("Could not prepare a pet part.") }
            // Copy the small part out of the atlas. A cropped CGImage can still
            // retain the entire decoded atlas, so drawing into a new bitmap is
            // necessary before handing it to SpriteKit.
            context.draw(crop,in:CGRect(x:0,y:0,width:rect.width,height:rect.height))
            guard let partImage=context.makeImage() else { throw PawError.message("Could not prepare a pet part.") }
            let texture = SKTexture(cgImage:partImage)
            texture.filteringMode = .linear
            let node = SKSpriteNode(texture: texture)
            if let size = part.displaySize {
                let scale = min(size[0] / rect.width, size[1] / rect.height)
                node.size = CGSize(width: rect.width * scale, height: rect.height * scale)
            } else { node.size = rect.size }
            node.anchorPoint = CGPoint(x: part.anchor[0], y: part.anchor[1])
            let offset = part.parentOffset ?? [0, 0]
            node.position = CGPoint(x: offset[0], y: offset[1])
            node.name = key
            node.zPosition = key == "tail" ? -1 : (key == "head" ? 3 : 7)
            joints[key] = node; alphaImages[key] = bitmap.mask
            sourceRects[key] = rect
            if key == "head" {
                eyeLocations = part.eyes
                eyelidColors=(part.eyes ?? [[0.31,0.60],[0.69,0.60]]).map { eye in
                    // Peaches has large brown irises extending into the usual lid
                    // sample. Sample the pale fur toward the center of her face.
                    let sampleX=manifest.id == "hamster" ? eye[0]+(eye[0] < 0.5 ? 0.1 : -0.1) : eye[0]
                    let sampleY=manifest.id == "hamster" ? eye[1] : max(0,eye[1]-0.085)
                    return bitmap.color(x:Int(rect.minX+rect.width*sampleX),y:Int(rect.minY+rect.height*sampleY))
                }
            }
            restPositions[key] = node.position
        }
        let body = joints["body"]!
        addChild(body)
        for key in PetManifest.required where key != "body" { body.addChild(joints[key]!) }
        accessorySlot.position = CGPoint(x: 0, y: joints["head"]!.size.height * (1-joints["head"]!.anchorPoint.y) - 5)
        accessorySlot.zPosition = 30
        joints["head"]!.addChild(accessorySlot)
        sleepLabel.text = "z Z"
        sleepLabel.fontSize = 19
        sleepLabel.fontColor = NSColor(calibratedRed: 0.50, green: 0.49, blue: 0.69, alpha: 1)
        sleepLabel.position = CGPoint(x: 62, y: 143)
        sleepLabel.isHidden = true
        addChild(sleepLabel)
        caption.fontSize = 10; caption.fontColor = NSColor(calibratedRed: 0.38, green: 0.29, blue: 0.23, alpha: 1)
        caption.position = CGPoint(x: 0, y: -25); addChild(caption)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func containsOpaquePoint(_ scenePoint: CGPoint) -> Bool {
        guard let scene else { return false }
        for (name, node) in joints {
            guard !node.isHidden, node.alpha > 0.1, let image = alphaImages[name], let rect = sourceRects[name] else { continue }
            let local = node.convert(scenePoint, from: scene)
            let px = (local.x / node.size.width + node.anchorPoint.x) * rect.width
            let py = (local.y / node.size.height + node.anchorPoint.y) * rect.height
            guard px >= 0, py >= 0, px < rect.width, py < rect.height else { continue }
            let x = Int(rect.minX + floor(px))
            let y = Int(rect.maxY - 1 - floor(py))
            if image.contains(x:x,y:y) { return true }
        }
        return false
    }
    private func eased(_ action:SKAction,_ mode:SKActionTimingMode = .easeInEaseOut)->SKAction { action.timingMode=mode; return action }
    private func transition(_ mode:String) {
        guard motionMode != mode else { return }
        let mirror=joints["body"]?.xScale.sign == .minus ? CGFloat(-1) : 1
        for (key,node) in joints { node.removeAllActions(); node.position=restPositions[key]!; node.setScale(1); node.zRotation=0 }
        joints["body"]?.xScale=mirror
        joints["head"]?.childNode(withName:"blink")?.removeFromParent()
        joints["head"]?.childNode(withName:"emotion")?.removeFromParent()
        childNode(withName:"reminder-prop")?.removeFromParent()
        childNode(withName:"box")?.removeFromParent()
        motionMode=mode
    }
    private func blink(slow:Bool=false) {
        guard joints["head"]?.childNode(withName:"blink") == nil else { return }
        let node=closedEyes(); node.name="blink"; node.alpha=0; joints["head"]?.addChild(node)
        node.run(.sequence([.fadeIn(withDuration:slow ? 0.18 : 0.06),.wait(forDuration:slow ? 0.25 : 0.06),.fadeOut(withDuration:slow ? 0.3 : 0.10),.removeFromParent()]))
    }
    private func cheeks() {
        guard let head=joints["head"],head.childNode(withName:"emotion") == nil else { return }
        let group=SKNode(); group.name="emotion"; group.zPosition=18; group.alpha=0; head.addChild(group)
        for eye in eyeLocations ?? [[0.31,0.60],[0.69,0.60]] {
            let blush=SKShapeNode(ellipseOf:CGSize(width:head.size.width*0.12,height:head.size.height*0.055))
            blush.fillColor=NSColor.systemPink.withAlphaComponent(0.26); blush.strokeColor = .clear
            blush.position=CGPoint(x:head.size.width*(eye[0]-head.anchorPoint.x),y:head.size.height*(1-eye[1]-head.anchorPoint.y-0.10)); group.addChild(blush)
        }
        group.run(.sequence([.fadeIn(withDuration:0.2),.wait(forDuration:0.7),.fadeOut(withDuration:0.5),.removeFromParent()]))
    }
    func idle() {
        guard !sleeping else { return }
        transition("idle")
        let breath = SKAction.sequence([eased(.scaleY(to:0.98,duration:1.1)),eased(.scaleY(to:1,duration:1.1))])
        joints["body"]?.run(breath, withKey: "breathing")
        joints["tail"]?.run(.sequence([eased(.rotate(toAngle:-0.12,duration:0.55)),eased(.rotate(toAngle:0.12,duration:1.1)),eased(.rotate(toAngle:0,duration:0.55))]),withKey:"sway")
        joints["head"]?.run(.sequence([.wait(forDuration:0.7),.run { [weak self] in self?.blink() }]),withKey:"natural-blink")
    }
    func typing() {
        typing(at:ProcessInfo.processInfo.systemUptime)
    }
    func typing(at now:TimeInterval) {
        guard !sleeping else { return }
        guard now-lastTap >= 0.065 else { return }; lastTap=now
        transition("typing")
        let key = nextLeftPaw ? "left_paw" : "right_paw"
        let direction: CGFloat = nextLeftPaw ? -1 : 1
        nextLeftPaw.toggle(); lastTappedPaw = key
        let node = joints[key]!
        node.removeAction(forKey: "typing")
        let rest = restPositions[key]!
        node.run(.sequence([
            eased(.group([.rotate(toAngle:direction*0.22,duration:0.055),.move(to:CGPoint(x:rest.x,y:rest.y+6),duration:0.055)]),.easeOut),
            eased(.group([.rotate(toAngle:direction*0.07,duration:0.08),.move(to:CGPoint(x:rest.x,y:rest.y-1),duration:0.08)])),
            eased(.group([.rotate(toAngle:0,duration:0.15),.move(to:rest,duration:0.15)]))
        ]), withKey: "typing")
        joints["tail"]?.run(.sequence([eased(.rotate(toAngle:direction*0.12,duration:0.15)),eased(.rotate(toAngle:0,duration:0.25))]),withKey:"sway")
    }
    func click(toward point: CGPoint) {
        guard !sleeping else { return }
        transition("click")
        let tilt:CGFloat = point.x < position.x ? 0.105 : -0.105
        let head=joints["head"],body=joints["body"]
        switch clickMood % 4 {
        case 0:
            head?.run(.sequence([eased(.group([.rotate(toAngle:tilt,duration:0.16),.scale(to:1.045,duration:0.16)]),.easeOut),.run{[weak self] in self?.blink()},.wait(forDuration:0.1),eased(.group([.rotate(toAngle:0,duration:0.30),.scale(to:1,duration:0.30)]))]),withKey:"reaction")
        case 1:
            blink();cheeks();body?.run(.sequence([eased(.scaleY(to:0.92,duration:0.12)),eased(.scaleY(to:1.05,duration:0.13)),eased(.scaleY(to:1,duration:0.2))]),withKey:"reaction")
        case 2:
            let key=nextLeftPaw ? "left_paw":"right_paw";let paw=joints[key];nextLeftPaw.toggle();let rest=restPositions[key] ?? .zero
            paw?.run(.sequence([eased(.group([.moveBy(x:0,y:15,duration:0.14),.rotate(toAngle:tilt*1.5,duration:0.14)])),.wait(forDuration:0.12),eased(.move(to:rest,duration:0.2)),eased(.rotate(toAngle:0,duration:0.2))]),withKey:"reaction")
        default:
            cheeks();head?.run(.sequence([eased(.rotate(toAngle:tilt*1.7,duration:0.2)),.wait(forDuration:0.22),eased(.rotate(toAngle:-tilt*0.65,duration:0.2)),.wait(forDuration:0.12),eased(.rotate(toAngle:0,duration:0.28))]),withKey:"reaction")
        }
        clickMood+=1
    }
    func pet(direction: CGFloat) {
        guard !sleeping else { return }
        let now=ProcessInfo.processInfo.systemUptime; guard now-lastStroke >= 0.15 else { return }; lastStroke=now
        transition("petting"); blink(slow:true); cheeks()
        joints["head"]?.run(.sequence([eased(.group([.rotate(toAngle:max(-0.16,min(0.16,-direction*0.015)),duration:0.22),.scaleY(to:0.97,duration:0.22)])),eased(.group([.rotate(toAngle:0,duration:0.45),.scaleY(to:1,duration:0.45)]))]),withKey:"petting")
    }
    func setSleeping(_ value: Bool) {
        guard value != sleeping else { return }
        sleeping = value
        transition(value ? "sleep" : "idle")
        sleepLabel.isHidden = !value
        joints["head"]?.childNode(withName: "sleep-eyes")?.removeFromParent()
        joints["body"]?.run(eased(.group([.scaleY(to:value ? 0.9 : 1,duration:0.55),.moveTo(y:value ? -4 : restPositions["body"]!.y,duration:0.55)])))
        joints["head"]?.run(eased(.rotate(toAngle:value ? -0.08 : 0,duration:0.55)))
        if value {
            let eyes = closedEyes(); eyes.name = "sleep-eyes"; joints["head"]?.addChild(eyes)
        }
    }
    private func closedEyes() -> SKNode {
        let group = SKNode(); group.zPosition = 20
        guard let head = joints["head"] else { return group }
        let width = head.size.width, height = head.size.height
        for (index,eye) in (eyeLocations ?? [[0.31,0.60],[0.69,0.60]]).enumerated() {
            let lid = SKShapeNode(ellipseOf: CGSize(width: width * 0.15, height: min(height*0.16,width*0.17)))
            lid.fillColor = eyelidColors.indices.contains(index) ? eyelidColors[index] : .systemGray; lid.strokeColor = .clear
            lid.position = CGPoint(x: width * (eye[0] - head.anchorPoint.x), y: height * (1 - eye[1] - head.anchorPoint.y))
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -width * 0.055, y: 1))
            path.addQuadCurve(to: CGPoint(x: width * 0.055, y: 1), control: CGPoint(x: 0, y: -3))
            let line = SKShapeNode(path: path); line.strokeColor = NSColor(calibratedRed:0.30,green:0.24,blue:0.23,alpha:1); line.lineWidth = 1.5
            lid.addChild(line); group.addChild(lid)
        }
        return group
    }
    func celebrate() {
        guard !sleeping else { return }; transition("celebration"); cheeks()
        guard let body=joints["body"] else { return }; let rest=restPositions["body"]!
        body.run(.sequence([eased(.scaleY(to:0.94,duration:0.12)),eased(.group([.moveTo(y:rest.y+28,duration:0.25),.scaleY(to:1.03,duration:0.25),.rotate(toAngle:-0.06,duration:0.25)]),.easeOut),eased(.group([.moveTo(y:rest.y,duration:0.28),.scaleY(to:0.95,duration:0.28),.rotate(toAngle:0,duration:0.28)]),.easeIn),eased(.scaleY(to:1,duration:0.2))]),withKey:"celebration")
    }
    func hideInBox() {
        guard !sleeping else { return }; transition("shy"); blink(slow:true)
        childNode(withName: "box")?.removeFromParent()
        let box = SKShapeNode(rectOf: CGSize(width: 135, height: 92), cornerRadius: 5)
        box.name = "box"; box.position = CGPoint(x: 0, y: 43); box.zPosition = 15
        box.fillColor = NSColor(calibratedRed: 0.67, green: 0.49, blue: 0.30, alpha: 1)
        box.strokeColor = .brown; box.lineWidth = 2
        addChild(box)
        let label = SKLabelNode(text: "…"); label.fontSize = 24; label.position.y = 15; box.addChild(label)
        box.run(.sequence([.wait(forDuration: 2), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
    func setAccessory(_ sku: String) {
        accessorySKU=sku
        accessorySlot.childNode(withName: "cosmetic")?.removeFromParent()
        guard sku != "none" else { return }
        if let node = PetAccessories.make(sku) { accessorySlot.addChild(node); updateAccessoryFit() }
    }
    private func updateAccessoryFit() {
        let scale=1.16 * hatTransform.scale
        if let node=accessorySlot.childNode(withName:"cosmetic") {
            node.position=CGPoint(x:hatTransform.x,y:hatTransform.y - (accessorySKU == "accessory.glasses" ? 18 : 0))
            node.setScale(scale);node.zRotation=hatTransform.rotation * .pi/180
            node.isHidden=accessorySlot.childNode(withName:"free-headphones") != nil
        }
    }
    func setAccessoryVisibility(_ visible: Bool) { accessorySlot.isHidden = !visible }
    func setCaption(_ text: String) { if caption.text != text { caption.text = text } }
    func wave() {
        guard !sleeping else { return }; transition("wave"); cheeks()
        let node = joints["right_paw"]!
        node.run(.sequence([eased(.rotate(toAngle:-0.85,duration:0.22)),eased(.rotate(toAngle:-0.5,duration:0.16)),eased(.rotate(toAngle:-0.85,duration:0.16)),eased(.rotate(toAngle:0,duration:0.26))]),withKey:"wave")
    }
    func play(_ animation: PetAnimation, looping: Bool, relaxed: Bool) {
        guard !sleeping else { return }
        removeAction(forKey: "mapped-reaction")
        let action = SKAction.run { [weak self] in
            guard let self else { return }
            switch animation {
            case .idle: self.idle()
            case .review: self.look(toward: CGPoint(x:self.position.x+70,y:self.position.y+150))
            case .running: self.typing()
            case .waiting: self.joints["head"]?.run(.sequence([.rotate(toAngle:0.07,duration:0.45),.rotate(toAngle:0,duration:0.45)]),withKey:"reaction")
            case .waving: self.wave()
            case .jumping: self.celebrate()
            case .failed: self.hideInBox()
            }
        }
        let sequence = SKAction.sequence([action,.wait(forDuration:animation == .waiting && relaxed ? 2.2 : max(1.1,animation.duration))])
        run(looping ? .repeatForever(sequence) : sequence,withKey:"mapped-reaction")
    }
    func presentation(flipped: Bool, hudScale: Double, hat: HatTransform) {
        hatTransform=hat
        joints["body"]?.xScale = flipped ? -1 : 1; caption.setScale(hudScale)
        updateAccessoryFit()
    }
    func accessoryPlacement(at point:CGPoint) -> HatTransform {
        guard let scene else { return HatTransform() }; let p=accessorySlot.convert(point,from:scene)
        return HatTransform(x:max(-100,min(100,p.x)),y:max(-100,min(100,p.y+(accessorySKU == "accessory.glasses" ? 18 : 0))))
    }
    func face(_ direction: CGFloat) { joints["body"]?.xScale = direction < 0 ? -1 : 1 }
    func look(toward point: CGPoint) {
        guard !sleeping else { return }
        joints["head"]?.run(.sequence([eased(.rotate(toAngle:point.x < position.x ? 0.09 : -0.09,duration:0.25)),.wait(forDuration:0.45),eased(.rotate(toAngle:0,duration:0.35))]),withKey:"look")
    }
    func setWalking(_ value: Bool) {
        guard let body = joints["body"] else { return }
        if value {
            transition("walking")
            let base=restPositions["body"]!.y
            body.run(.repeatForever(.sequence([eased(.group([.rotate(toAngle:-0.025,duration:0.18),.moveTo(y:base+1.5,duration:0.18)])),eased(.group([.rotate(toAngle:0.025,duration:0.18),.moveTo(y:base,duration:0.18)]))])),withKey:"walking")
            for (key, sign) in [("left_paw", CGFloat(1)), ("right_paw", CGFloat(-1))] {
                joints[key]?.run(.repeatForever(.sequence([eased(.rotate(toAngle:sign*0.25,duration:0.18)),eased(.rotate(toAngle:-sign*0.25,duration:0.18))])),withKey:"walking")
            }
        } else if motionMode == "walking" { transition("idle") }
    }
    func setDancing(_ value: Bool, beat: TimeInterval) {
        // This state indicator has no SKU and never consults accessory ownership.
        accessorySlot.childNode(withName: "free-headphones")?.removeFromParent()
        for key in ["body", "head", "left_paw", "right_paw"] { joints[key]?.removeAction(forKey: "dance") }
        guard let body = joints["body"], let head = joints["head"] else { return }
        if value {
            transition("dance")
            let phones = PetAccessories.headphones(); phones.name = "free-headphones"; phones.setScale(1.16)
            accessorySlot.addChild(phones)
            updateAccessoryFit()
            let interval = max(0.33, min(1, beat))/2
            let base=restPositions["body"]!.y
            body.run(.repeatForever(.sequence([eased(.moveTo(y:base+6,duration:interval),.easeOut),eased(.moveTo(y:base,duration:interval),.easeIn)])),withKey:"dance")
            head.run(.repeatForever(.sequence([eased(.rotate(toAngle:-0.07,duration:interval)),eased(.rotate(toAngle:0.07,duration:interval))])),withKey:"dance")
            for (key, sign) in [("left_paw", CGFloat(1)), ("right_paw", CGFloat(-1))] { joints[key]?.run(.repeatForever(.sequence([.rotate(toAngle: sign*0.4, duration: interval), .rotate(toAngle: -sign*0.2, duration: interval)])), withKey: "dance") }
        } else {
            if motionMode == "dance" { transition("idle") }
            updateAccessoryFit()
        }
    }
    func reminderGesture(_ kind: String) {
        transition("reminder")
        if kind == "water" {
            childNode(withName: "reminder-prop")?.removeFromParent()
            let cup = SKShapeNode(rectOf: CGSize(width: 22, height: 26), cornerRadius: 4)
            cup.name = "reminder-prop"; cup.position = CGPoint(x: 48, y: 64); cup.zPosition = 12
            cup.fillColor = .systemTeal; cup.strokeColor = .brown; cup.lineWidth = 2; addChild(cup)
            cup.run(.sequence([.moveBy(x: -12, y: 25, duration: 0.6), .rotate(toAngle: 0.25, duration: 0.3), .wait(forDuration: 1), .fadeOut(withDuration: 0.5), .removeFromParent()]))
            joints["right_paw"]?.run(.sequence([.rotate(toAngle: -0.6, duration: 0.6), .wait(forDuration: 1), .rotate(toAngle: 0, duration: 0.5)]), withKey: "reminder")
        } else if kind == "stretch" {
            for (key, angle) in [("left_paw", CGFloat(1.2)), ("right_paw", CGFloat(-1.2))] { joints[key]?.run(.sequence([.rotate(toAngle: angle, duration: 0.6), .wait(forDuration: 0.8), .rotate(toAngle: 0, duration: 0.5)]), withKey: "reminder") }
            joints["body"]?.run(.sequence([.scaleY(to: 1.08, duration: 0.6), .scaleY(to: 1, duration: 0.8)]), withKey: "reminder")
        } else if kind == "posture" {
            joints["left_paw"]?.run(.sequence([.repeat(.sequence([eased(.rotate(toAngle:0.8,duration:0.3)),eased(.rotate(toAngle:0.3,duration:0.3))]),count:2),eased(.rotate(toAngle:0,duration:0.3))]),withKey:"reminder")
        } else if kind == "eyes" { pet(direction: 0) }
        else { wave(); let base=restPositions["body"]!.y; joints["body"]?.run(.sequence([eased(.moveTo(y:base+8,duration:0.2),.easeOut),eased(.moveTo(y:base,duration:0.25),.easeIn)]),withKey:"reminder") }
    }

    /// Deterministic key poses used to bake the original characters into the
    /// same eight-column, nine-row frame contract as OpenPets v1 pets.
    func setExportPose(row: Int, frame: Int) {
        motionMode = ""
        transition("export")
        let phase = CGFloat(frame) * .pi / 4
        let body = joints["body"]!, head = joints["head"]!
        let left = joints["left_paw"]!, right = joints["right_paw"]!
        let tail = joints["tail"]!
        head.childNode(withName:"export-expression")?.removeFromParent()
        childNode(withName:"export-feet")?.removeFromParent()
        shadow.isHidden = true; caption.isHidden = true; sleepLabel.isHidden = true
        switch row {
        case 0: // quiet idle, including an occasional soft blink
            body.yScale = 1 - 0.018 * (1 + sin(phase))
            tail.zRotation = 0.08 * sin(phase)
            if frame == 5 { exportEyes(on:head) }
        case 1, 2: // left/right footfalls with a grounded passing pose
            let sign:CGFloat = row == 1 ? 1 : -1
            let stride = sin(phase)
            body.position.y += 2.5 * abs(stride)
            body.zRotation = sign * 0.025 * stride
            head.zRotation = -sign * 0.035 * stride
            left.position.x += sign * 8 * stride
            left.position.y += max(0, 7 * stride)
            right.position.x -= sign * 8 * stride
            right.position.y += max(0, -7 * stride)
            left.zRotation = sign * 0.3 * stride
            right.zRotation = -sign * 0.3 * stride
            tail.zRotation = 0.16 * stride
            if let feet = exportFeet() {
                feet.name = "export-feet"
                feet.children.first?.position.x += sign * 8 * stride
                feet.children.last?.position.x -= sign * 8 * stride
                addChild(feet)
            }
            if row == 2 { body.xScale = -1 }
        case 3: // paw-pad wave, with ears/head leaning into the hello
            right.position.x += 5
            right.position.y += 34 + 3 * sin(phase)
            right.zRotation = -0.5 + 0.18 * sin(phase)
            head.zRotation = -0.045 + 0.035 * sin(phase)
            tail.zRotation = 0.12 * sin(phase)
            if frame == 4 { exportEyes(on:head) }
        case 4: // anticipation, launch, airborne apex, then soft landing
            let heights:[CGFloat] = [0,-5,9,25,34,29,11,-2]
            body.position.y += heights[frame]
            body.yScale = frame < 2 ? 0.93 : frame > 5 ? 0.95 : 1.04
            left.position.y += frame >= 2 && frame <= 5 ? 11 : 0
            right.position.y += frame >= 2 && frame <= 5 ? 11 : 0
            left.zRotation = frame >= 2 && frame <= 5 ? 0.45 : 0
            right.zRotation = frame >= 2 && frame <= 5 ? -0.45 : 0
            head.zRotation = frame >= 2 && frame <= 5 ? -0.07 : 0
            tail.zRotation = 0.22 * sin(phase)
            if (2...5).contains(frame) { exportEyes(on:head) }
        case 5: // shy/oops expression
            body.yScale = 0.92
            head.zRotation = -0.08
            head.position.y -= 5
            left.position.y += 3; right.position.y += 3
            if frame >= 2 { exportEyes(on:head) }
        case 6: // waiting / looking around
            head.zRotation = 0.075 * sin(phase)
            tail.zRotation = -0.1 * sin(phase)
            if frame == 6 { exportEyes(on:head) }
        case 7: // alternating usable paws, without a keyboard prop
            let tap = sin(phase * 2)
            left.position.y += max(0, tap) * 8
            right.position.y += max(0, -tap) * 8
            left.position.x -= 3; right.position.x += 3
            left.zRotation = -0.2 * max(0, tap)
            right.zRotation = 0.2 * max(0, -tap)
            head.zRotation = 0.025 * sin(phase)
        case 8: // thinking/review
            head.zRotation = -0.06 + 0.04 * sin(phase)
            right.position.y += 10
            right.zRotation = -0.2
            if frame == 3 { exportEyes(on:head) }
        default: break
        }
    }
    private func exportEyes(on head: SKSpriteNode) {
        let expression=closedEyes()
        expression.name="export-expression"
        head.addChild(expression)
    }
    private func exportFeet() -> SKNode? {
        guard let paw=joints["left_paw"]?.texture else { return nil }
        let feet=SKNode()
        for x:CGFloat in [-38,38] {
            let foot=SKSpriteNode(texture:paw,size:CGSize(width:24,height:25))
            foot.position=CGPoint(x:x,y:12)
            foot.zPosition = -2
            feet.addChild(foot)
        }
        return feet
    }
}
