import AppKit
import SpriteKit

@MainActor final class FramePetNode:SKNode,CompanionAnimating {
    private let sprite=SKSpriteNode()
    private let mask:PetAlphaMask
    private var frames:[[SKTexture]]=[]
    private let cell:CGSize
    private var currentRow=0,currentColumn=0
    var currentFrame:(row:Int,column:Int) { (currentRow,currentColumn) }
    private(set) var sequence:PetFrameSequence?
    private(set) var frameStartedAt:TimeInterval=0
    private var frameTimer:Timer?
    private var typingUntil:TimeInterval?
    private var gazeReset:DispatchWorkItem?
    private var suspended=false
    private var facing:CGFloat=1
    private var flipped=false
    private let petID:String
    private var accessorySKU="none"
    private var hatTransform=HatTransform()
    private var animationState:PetAnimation = .idle
    private let caption=SKLabelNode(fontNamed:NSFont.systemFont(ofSize:10,weight:.semibold).fontName)
    private let accessories=SKNode()
    private let sleepLabel=SKLabelNode(fontNamed:NSFont.systemFont(ofSize:17,weight:.semibold).fontName)
    private let reactionLabel=SKLabelNode(fontNamed:"AppleColorEmoji")
    private var clickMood=0
    private(set) var sleeping=false
    var onNeedsRender:(()->Void)?

    init(spec:ImportedPet) throws {
        petID=spec.id
        let decoded=try DecodedPetImage(url:spec.directory.appendingPathComponent("spritesheet.webp"))
        guard spec.columns == 8,[9,11].contains(spec.rows),decoded.width.isMultiple(of:8),decoded.height.isMultiple(of:spec.rows) else { throw PawError.message("Invalid imported sprite sheet.") }
        mask=decoded.mask; cell=CGSize(width:decoded.width/8,height:decoded.height/spec.rows)
        super.init()
        let atlas=SKTexture(cgImage:decoded.image)
        for row in 0..<spec.rows {
            frames.append((0..<8).map { column in
                let texture=SKTexture(rect:CGRect(x:Double(column)/8,y:1-Double(row+1)/Double(spec.rows),width:1.0/8,height:1.0/Double(spec.rows)),in:atlas)
                texture.filteringMode = .linear; return texture
            })
        }
        sprite.size=CGSize(width:192,height:208); sprite.anchorPoint=CGPoint(x:0.5,y:0)
        addChild(sprite); accessories.name="head-accessories"; accessories.zPosition=10; sprite.addChild(accessories)
        caption.fontSize=10; caption.fontColor = .brown; caption.position.y = -25; addChild(caption)
        sleepLabel.text="z z"; sleepLabel.fontSize=17; sleepLabel.fontColor = .systemPurple; sleepLabel.position=CGPoint(x:63,y:154); sleepLabel.isHidden=true; addChild(sleepLabel)
        reactionLabel.fontSize=23;reactionLabel.position=CGPoint(x:58,y:202);reactionLabel.alpha=0;addChild(reactionLabel)
        show(row:0,column:spec.rows == 11 ? 6 : 0)
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    deinit { frameTimer?.invalidate(); gazeReset?.cancel() }
    private func show(row:Int,column:Int) {
        guard frames.indices.contains(row),frames[row].indices.contains(column) else { return }
        guard currentRow != row || currentColumn != column || sprite.texture == nil else { return }
        currentRow=row; currentColumn=column; sprite.texture=frames[row][column]; updateAccessoryFit(); onNeedsRender?()
    }
    private func stopFrames() { frameTimer?.invalidate(); frameTimer=nil; sequence=nil; typingUntil=nil; gazeReset?.cancel(); gazeReset=nil }
    private func begin(_ clip:PetFrameSequence) {
        gazeReset?.cancel(); gazeReset=nil
        if sequence == clip,frameTimer != nil { return }
        stopFrames(); sequence=clip; frameStartedAt=ProcessInfo.processInfo.systemUptime
        show(row:clip.row,column:0); scheduleFrames()
    }
    private func scheduleFrames() {
        frameTimer?.invalidate(); frameTimer=nil
        guard !suspended,!sleeping,let sequence else { return }
        let timer=Timer(timeInterval:sequence.duration/Double(sequence.frames),repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame(at:ProcessInfo.processInfo.systemUptime) }
        }
        timer.tolerance=0.005; RunLoop.main.add(timer,forMode:.common); frameTimer=timer
    }
    func advanceFrame(at now:TimeInterval) {
        guard !suspended,!sleeping,let sequence else { return }
        if let typingUntil,now >= typingUntil { idle(); return }
        guard let column=sequence.column(at:now-frameStartedAt) else { idle(); return }
        show(row:sequence.row,column:column)
    }
    func setRenderingSuspended(_ value:Bool) {
        guard value != suspended else { return }; suspended=value
        if value { frameTimer?.invalidate(); frameTimer=nil; gazeReset?.cancel() }
        else { if typingUntil != nil || sequence == nil { idle() } else { frameStartedAt=ProcessInfo.processInfo.systemUptime; scheduleFrames() }; onNeedsRender?() }
    }
    private func neutral() { stopFrames(); animationState = .idle; show(row:0,column:frames.count == 11 ? 6 : 0) }
    func idle() {
        guard !sleeping else { return }
        animationState = .idle
        if frames.count == 11 { neutral() }
        else { begin(PetFrameSequence(row:0,frames:6,duration:5.5,iterations:nil)) }
    }
    func typing() {
        guard !sleeping else { return }
        animationState = .running
        // Extend activity without restarting the authored work cycle on each key.
        begin(PetFrameSequence(row:7,frames:6,duration:0.82,iterations:nil))
        typingUntil=ProcessInfo.processInfo.systemUptime+0.5
    }
    func click(toward point:CGPoint) {
        guard !sleeping else { return }
        let moods:[(PetAnimation,String)]=[(.review,"❔"),(.waiting,"✨"),(.jumping,"💛"),(.waving,"♡"),(.running,"❕")]
        let mood=moods[clickMood % moods.count];clickMood+=1
        play(mood.0,looping:false,relaxed:true)
        reactionLabel.removeAllActions();reactionLabel.text=mood.1;reactionLabel.alpha=0;reactionLabel.setScale(0.65)
        reactionLabel.run(.sequence([.group([.fadeIn(withDuration:0.12),.scale(to:1,duration:0.18)]),.wait(forDuration:0.48),.group([.fadeOut(withDuration:0.24),.moveBy(x:0,y:16,duration:0.24)]),.run{[weak self] in self?.reactionLabel.position.y=202}]))
    }
    func pet(direction:CGFloat) { play(.review,looping:false,relaxed:true) }
    func setSleeping(_ value:Bool) {
        guard value != sleeping else { return }; sleeping=value; stopFrames(); sprite.removeAllActions(); sprite.position = .zero; sprite.zRotation=0; sprite.setScale(1); sprite.xScale=flipped ? -1 : 1
        sleepLabel.isHidden = !value; sprite.alpha=value ? 0.85 : 1
        neutral(); if !value { idle() }; onNeedsRender?()
    }
    func celebrate() { play(.jumping,looping:false,relaxed:false) }
    func hideInBox() { play(.failed,looping:false,relaxed:false) }
    func wave() { play(.waving,looping:false,relaxed:false) }
    func play(_ animation:PetAnimation,looping:Bool,relaxed:Bool) {
        guard !sleeping else { return }
        if animation == .idle { idle(); return }
        animationState=animation
        let finite=[PetAnimation.waving,.jumping,.failed].contains(animation)
        begin(PetFrameSequence(row:animation.row,frames:animation.frames,duration:animation == .waiting && relaxed ? 2.2 : animation.duration,iterations:finite ? 2 : looping ? nil : 1))
        typingUntil=nil
    }
    func setWalking(_ value:Bool) {
        if value { animationState = .running; begin(PetFrameSequence(row:(facing < 0) != flipped ? 2 : 1,frames:8,duration:1.06,iterations:nil)) }
        else { idle() }
    }
    func face(_ direction:CGFloat) { facing=direction < 0 ? -1 : 1 }
    func look(toward point:CGPoint) {
        guard !sleeping,animationState == .idle,let scene else { return }
        if frames.count == 9 {
            play(.waving,looping:false,relaxed:true)
            return
        }
        guard frames.count == 11 else { return }
        let p=sprite.convert(point,from:scene),center=CGPoint(x:0,y:sprite.size.height/2)
        guard hypot(p.x-center.x,p.y-center.y) > 24 else { return }
        let sector=(Int(floor((atan2(p.x-center.x,p.y-center.y)+CGFloat.pi/16)/(CGFloat.pi/8)))+16)%16
        stopFrames(); show(row:sector < 8 ? 9 : 10,column:sector%8)
        let work=DispatchWorkItem { [weak self] in self?.idle() }; gazeReset=work
        DispatchQueue.main.asyncAfter(deadline:.now()+1.2,execute:work)
    }
    func containsOpaquePoint(_ point:CGPoint)->Bool {
        guard let scene else { return false }; let p=sprite.convert(point,from:scene)
        let x=(p.x/sprite.size.width+0.5)*cell.width,y=p.y/sprite.size.height*cell.height
        guard x >= 0,y >= 0,x < cell.width,y < cell.height else { return false }
        return mask.contains(x:Int(x)+currentColumn*Int(cell.width),y:Int(cell.height-y-1)+currentRow*Int(cell.height))
    }
    private func updateAccessoryFit() {
        let fit=PetAccessoryFit.frame(id:petID,row:currentRow,column:currentColumn)
        accessories.position=fit.crown
        if let node=accessories.childNode(withName:"cosmetic") {
            let earInset:CGFloat = petID == "bunny" && ["free.beanie","free.crown","accessory.hat"].contains(accessorySKU) ? -17 : 0
            node.position=CGPoint(x:hatTransform.x,y:hatTransform.y + earInset - (accessorySKU == "accessory.glasses" ? fit.glassesDrop : 0))
            node.setScale(fit.scale * hatTransform.scale)
            node.zRotation=hatTransform.rotation * .pi/180
            node.isHidden=accessories.childNode(withName:"free-headphones") != nil
        }
        accessories.childNode(withName:"free-headphones")?.setScale(fit.scale)
    }
    func setAccessory(_ sku:String) { accessorySKU=sku; accessories.childNode(withName:"cosmetic")?.removeFromParent(); if let node=PetAccessories.make(sku) { accessories.addChild(node) }; updateAccessoryFit(); onNeedsRender?() }
    func setAccessoryVisibility(_ visible:Bool) { accessories.isHidden = !visible; onNeedsRender?() }
    func setCaption(_ text:String) { guard caption.text != text else { return }; caption.text=text; onNeedsRender?() }
    func presentation(flipped:Bool,hudScale:Double,hat:HatTransform) {
        self.flipped=flipped; hatTransform=hat; sprite.xScale=flipped ? -1 : 1; caption.setScale(hudScale)
        updateAccessoryFit()
        onNeedsRender?()
    }
    func accessoryPlacement(at point:CGPoint)->HatTransform { guard let scene else { return HatTransform() }; let p=accessories.convert(point,from:scene),fit=PetAccessoryFit.frame(id:petID,row:currentRow,column:currentColumn); return HatTransform(x:max(-100,min(100,p.x)),y:max(-100,min(100,p.y+(accessorySKU == "accessory.glasses" ? fit.glassesDrop : 0)))) }
    func setDancing(_ value:Bool,beat:TimeInterval) {
        accessories.childNode(withName:"free-headphones")?.removeFromParent(); sprite.removeAction(forKey:"dance"); sprite.position = .zero; sprite.zRotation=0
        if value {
            let phones=PetAccessories.headphones(); phones.name="free-headphones"; accessories.addChild(phones)
            let half=max(0.33,min(1,beat))/2
            let up=SKAction.moveTo(y:7,duration:half),down=SKAction.moveTo(y:0,duration:half); up.timingMode = .easeOut; down.timingMode = .easeIn
            sprite.run(.repeatForever(.sequence([up,down])),withKey:"dance")
        }; updateAccessoryFit(); onNeedsRender?()
    }
    func reminderGesture(_ kind:String) { play(kind == "stretch" ? .jumping : kind == "eyes" ? .waiting : .waving,looping:false,relaxed:kind == "eyes") }
}
