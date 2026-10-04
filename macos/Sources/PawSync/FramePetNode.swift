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
    private let profile:PetExpressionProfile?
    private var poseProfiles:[Int:PetExpressionProfile]=[:]
    private let expression:PetExpressionNode
    private struct FilePose {
        let texture:SKTexture
        let mask:PetAlphaMask
        let bounds:CGRect
        let profile:PetExpressionProfile?
        init(directory:URL,name:String) throws {
            let image=try DecodedPetImage(url:directory.appendingPathComponent(name+".png"))
            guard image.width == 192,image.height == 208 else { throw PawError.message("Invalid file-catching artwork.") }
            texture=SKTexture(cgImage:image.image);texture.filteringMode = .linear;mask=image.mask
            let rect=mask.opaqueBounds(in:CGRect(x:0,y:0,width:192,height:208))
            bounds=CGRect(x:rect.minX-96,y:208-rect.maxY,width:rect.width,height:rect.height)
            profile=PetExpressionProfile.load(directory.appendingPathComponent(name))
        }
    }
    private var filePoses:[String:FilePose]=[:]
    private(set) var displayedFilePose:String?
    var hasNativeFilePoses:Bool { filePoses.count == 2 }
    var heldFilesPointInScene:CGPoint { guard let scene else { return .zero };return sprite.convert(heldFiles.position,to:scene) }
    private var expressionReset:DispatchWorkItem?
    private(set) var receivingFiles=false
    private var heldCount=0
    var currentEmotion:PetEmotion? { expression.emotion }
    var leftPawDisplacement:CGPoint {
        guard let grid=sprite.warpGeometry as? SKWarpGeometryGrid else { return .zero }
        let paw=profile?.pawCenters.first ?? [0.37,0.32]
        let index=min(16,max(0,Int((paw[1]*16).rounded())))*13+min(12,max(0,Int((paw[0]*12).rounded())))
        let delta=grid.destPosition(at:index)-grid.sourcePosition(at:index)
        return CGPoint(x:CGFloat(delta.x)*sprite.size.width,y:CGFloat(delta.y)*sprite.size.height)
    }
    private var accessorySKU="none"
    private var hatTransform=HatTransform()
    private var animationState:PetAnimation = .idle
    private let caption=SKLabelNode(fontNamed:NSFont.systemFont(ofSize:10,weight:.semibold).fontName)
    private let accessories=SKNode()
    private let sleepLabel=SKLabelNode(fontNamed:NSFont.systemFont(ofSize:17,weight:.semibold).fontName)
    private let heldFiles=PetHeldFilesIndicator()
    private var visualRect:CGRect = .zero
    private var clickMood=0
    private var nextTypingLeft=true
    private var lastTapAt:TimeInterval=0
    private var typingStreak=0
    private var inputMotionUntil:TimeInterval=0
    private(set) var lastTappedPaw:String?
    private let restingWarp=SKWarpGeometryGrid(columns:12,rows:16)
    private lazy var pawWarps:[SKWarpGeometryGrid]=[Self.pawWarp(left:true),Self.pawWarp(left:false)]
    var requiresContinuousRendering:Bool { ProcessInfo.processInfo.systemUptime < inputMotionUntil }
    private static func pawWarp(left:Bool)->SKWarpGeometryGrid {
        var source:[SIMD2<Float>]=[],destination:[SIMD2<Float>]=[]
        for row in 0...16 { for column in 0...12 {
            let x=Float(column)/12,y=Float(row)/16
            source.append(SIMD2<Float>(x,y))
            let dx=(x-(left ? 0.37:0.63))/0.10,dy=(y-0.32)/0.085
            let influence=exp(-(dx*dx+dy*dy)*0.5)
            destination.append(SIMD2<Float>(x+(left ? -0.004:0.004)*influence,y-0.029*influence))
        } }
        return SKWarpGeometryGrid(columns:12,rows:16,sourcePositions:source,destinationPositions:destination)
    }
    private(set) var sleeping=false
    var onNeedsRender:(()->Void)?

    init(spec:ImportedPet) throws {
        petID=spec.id
        profile=PetExpressionProfile.load(spec.directory)
        expression=PetExpressionNode(profile:profile,id:spec.id)
        let decoded=try DecodedPetImage(url:spec.directory.appendingPathComponent("spritesheet.webp"))
        guard spec.columns == 8,[9,11].contains(spec.rows),decoded.width.isMultiple(of:8),decoded.height.isMultiple(of:spec.rows) else { throw PawError.message("Invalid imported sprite sheet.") }
        mask=decoded.mask; cell=CGSize(width:decoded.width/8,height:decoded.height/spec.rows)
        super.init()
        for (index,name) in [(1,"typing-left"),(2,"typing-right"),(3,"receive")] {
            if let value=PetExpressionProfile.load(spec.directory.appendingPathComponent(name)) { poseProfiles[index]=value }
        }
        if let directory=Bundle.main.resourceURL?.appendingPathComponent("FileInteractions/"+spec.id),FileManager.default.fileExists(atPath:directory.appendingPathComponent("receive.png").path) {
            for pose in ["receive","hold"] { filePoses[pose]=try FilePose(directory:directory,name:pose) }
        }
        let atlas=SKTexture(cgImage:decoded.image)
        for row in 0..<spec.rows {
            frames.append((0..<8).map { column in
                let texture=SKTexture(rect:CGRect(x:Double(column)/8,y:1-Double(row+1)/Double(spec.rows),width:1.0/8,height:1.0/Double(spec.rows)),in:atlas)
                texture.filteringMode = .linear; return texture
            })
        }
        sprite.size=CGSize(width:192,height:208); sprite.anchorPoint=CGPoint(x:0.5,y:0)
        addChild(sprite); accessories.name="head-accessories"; accessories.zPosition=10; sprite.addChild(accessories)
        sprite.addChild(expression)
        caption.fontSize=10; caption.fontColor = .brown; caption.position.y = -25; addChild(caption)
        sleepLabel.text="z z"; sleepLabel.fontSize=17; sleepLabel.fontColor = .systemPurple; sleepLabel.position=CGPoint(x:63,y:154); sleepLabel.isHidden=true; addChild(sleepLabel)
        heldFiles.setTheme(spec.id);heldFiles.position=CGPoint(x:0,y:36);sprite.addChild(heldFiles)
        show(row:0,column:spec.rows == 11 ? 6 : 0)
        let pixelBounds=mask.opaqueBounds(in:CGRect(x:currentColumn*Int(cell.width),y:0,width:Int(cell.width),height:Int(cell.height)))
        visualRect=CGRect(x:(pixelBounds.minX/cell.width-0.5)*192,y:(1-pixelBounds.maxY/cell.height)*208,width:pixelBounds.width/cell.width*192,height:pixelBounds.height/cell.height*208)
    }
    required init?(coder:NSCoder) { fatalError("Unsupported") }
    deinit { frameTimer?.invalidate(); gazeReset?.cancel();expressionReset?.cancel() }
    private func show(row:Int,column:Int) {
        guard frames.indices.contains(row),frames[row].indices.contains(column) else { return }
        guard currentRow != row || currentColumn != column || sprite.texture == nil || displayedFilePose != nil else { return }
        if displayedFilePose != nil { displayedFilePose=nil }
        currentRow=row; currentColumn=column; sprite.texture=frames[row][column]
        expression.useProfile(frameProfile,preserveEmotion:true);updateAccessoryFit(); onNeedsRender?()
    }
    private func showFilePose(_ name:String) {
        guard let pose=filePoses[name] else { return }
        displayedFilePose=name;sprite.texture=pose.texture;sprite.warpGeometry=nil
        expression.useProfile(pose.profile);updateAccessoryFit();onNeedsRender?()
    }
    private var frameProfile:PetExpressionProfile? {
        if [1,2,7].contains(currentRow) { return poseProfiles[currentColumn.isMultiple(of:2) ? 1:2] ?? profile }
        if currentRow == 6 { return poseProfiles[3] ?? profile }
        return profile
    }
    private func stopFrames() { frameTimer?.invalidate();frameTimer=nil;sequence=nil;typingUntil=nil;gazeReset?.cancel();gazeReset=nil;expressionReset?.cancel();expressionReset=nil;expression.clear();for key in ["paw-tap","click-perk","emotion","file-arms","cuddle","gait","celebration"] { sprite.removeAction(forKey:key) };sprite.warpGeometry=nil;inputMotionUntil=0;sprite.position = .zero;sprite.zRotation=0;sprite.yScale=1 }
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
        if value { frameTimer?.invalidate(); frameTimer=nil; gazeReset?.cancel();expressionReset?.cancel() }
        else { if typingUntil != nil || sequence == nil { idle() } else { frameStartedAt=ProcessInfo.processInfo.systemUptime; scheduleFrames() }; onNeedsRender?() }
    }
    private func neutral() { stopFrames(); animationState = .idle; show(row:0,column:frames.count == 11 ? 6 : 0) }
    func idle() {
        guard !sleeping,!receivingFiles else { return }
        let hadExpression=expression.emotion != nil
        animationState = .idle
        if hasNativeFilePoses,heldCount>0 { neutral();showFilePose("hold") }
        else if frames.count == 11 { neutral() }
        else { begin(PetFrameSequence(row:0,frames:6,duration:5.5,iterations:nil)) }
        if heldCount>0,!hasNativeFilePoses { sprite.warpGeometry=fileWarp(open:false) }
        if hadExpression { onNeedsRender?() }
    }
    func typing() { typing(at:ProcessInfo.processInfo.systemUptime) }
    func typing(at now:TimeInterval) {
        guard !sleeping,!receivingFiles else { return }
        animationState = .running
        // Imported OpenPets keep their authored work cycle. PawSync originals
        // additionally move the actual illustrated paw pixels on alternate keys.
        begin(PetFrameSequence(row:7,frames:6,duration:0.82,iterations:nil))
        typingUntil=now+0.5
        guard now-lastTapAt >= 0.055 else { return }
        typingStreak=now-lastTapAt<0.25 ? min(12,typingStreak+1):1
        lastTapAt=now;lastTappedPaw=nextTypingLeft ? "left":"right"
        if petID.hasPrefix("pawpaw-") { show(row:7,column:nextTypingLeft ? 0:1) }
        expression.show(typingStreak>=8 ? .excited:.focused)
        let warp=pawWarps[nextTypingLeft ? 0:1];nextTypingLeft.toggle();inputMotionUntil=now+0.25
        guard PetStore.rigIDs.contains(petID) else { onNeedsRender?();return }
        if sprite.warpGeometry == nil { sprite.warpGeometry=restingWarp }
        if let down=SKAction.warp(to:warp,duration:0.065),let up=SKAction.warp(to:restingWarp,duration:0.13) {
            down.timingMode = .easeOut;up.timingMode = .easeInEaseOut
            sprite.run(.sequence([down,up]),withKey:"paw-tap");onNeedsRender?()
        }
    }
    func click(toward point:CGPoint) {
        guard !sleeping,!receivingFiles else { return }
        if profile != nil {
            let moods:[PetEmotion]=[.surprised,.curious,.happy,.shy,.proud]
            express(moods[clickMood % moods.count]);clickMood+=1
            return
        }
        // Ambient clicks are a quick look/blink, rather than a hello or a flip.
        play(clickMood.isMultiple(of:2) ? .review:.waiting,looping:false,relaxed:false);clickMood+=1
        let direction:CGFloat=point.x < position.x ? 1:-1
        inputMotionUntil=ProcessInfo.processInfo.systemUptime+0.35
        let perk=SKAction.group([.rotate(toAngle:direction*0.05,duration:0.09),.scaleY(to:1.035,duration:0.09)])
        let settle=SKAction.group([.rotate(toAngle:0,duration:0.22),.scaleY(to:1,duration:0.22)])
        perk.timingMode = .easeOut;settle.timingMode = .easeInEaseOut
        sprite.run(.sequence([perk,settle]),withKey:"click-perk");onNeedsRender?()
    }
    func pet(direction:CGFloat) { if profile != nil { express(.affectionate) } else { play(.review,looping:false,relaxed:true) } }
    func cuddle() {
        guard !sleeping,!receivingFiles else { return }
        let moods:[PetEmotion]=[.delighted,.playful,.affectionate,.cozy]
        let mood=moods[clickMood % moods.count];clickMood+=1
        neutral();if hasNativeFilePoses,heldCount>0 { showFilePose("hold") }
        animationState = .review;expression.show(mood)
        // A short happy shimmy for direct affection, separate from ambient clicks
        // and the system-audio dance (which alone wears headphones).
        func sway(_ side:CGFloat)->SKAction {
            let action=SKAction.group([.move(to:CGPoint(x:side*3,y:3),duration:0.18),.rotate(toAngle:side*0.045,duration:0.18),.scaleY(to:0.98,duration:0.18)])
            action.timingMode = .easeInEaseOut;return action
        }
        var actions:[SKAction]=[]
        for _ in 0..<3 { actions += [sway(-1),sway(1)] }
        let settle=SKAction.group([.move(to:.zero,duration:0.24),.rotate(toAngle:0,duration:0.24),.scaleY(to:1,duration:0.24)]);settle.timingMode = .easeInEaseOut;actions.append(settle)
        sprite.run(.sequence(actions),withKey:"cuddle")
        if profile != nil {
            sprite.warpGeometry=restingWarp
            if let open=SKAction.warp(to:fileWarp(open:true),duration:0.24),let close=SKAction.warp(to:heldCount>0 ? fileWarp(open:false):restingWarp,duration:0.3) {
                open.timingMode = .easeOut;close.timingMode = .easeInEaseOut;sprite.run(.sequence([open,.wait(forDuration:0.5),close]),withKey:"file-arms")
            }
        }
        inputMotionUntil=ProcessInfo.processInfo.systemUptime+1.5
        let work=DispatchWorkItem { [weak self] in self?.idle() };expressionReset=work
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5,execute:work);onNeedsRender?()
    }
    var companionBoundsInScene:CGRect {
        guard let scene else { return .zero }
        let rect=displayedFilePose.flatMap{filePoses[$0]?.bounds} ?? visualRect
        let a=sprite.convert(rect.origin,to:scene),b=sprite.convert(CGPoint(x:rect.maxX,y:rect.maxY),to:scene)
        return CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(b.x-a.x),height:abs(b.y-a.y))
    }
    func containsHeldFilesPoint(_ point:CGPoint)->Bool { heldFiles.containsScenePoint(point) }
    func setHeldFileCount(_ count:Int) {
        heldCount=max(0,count);heldFiles.setCount(count)
        if !receivingFiles,animationState == .idle {
            if hasNativeFilePoses { idle() }
            else { sprite.warpGeometry=heldCount>0 ? fileWarp(open:false):nil }
        }
        onNeedsRender?()
    }
    private func fileWarp(open:Bool)->SKWarpGeometryGrid {
        let centers=profile?.pawCenters ?? [[0.37,0.32],[0.63,0.32]]
        var source:[SIMD2<Float>]=[],target:[SIMD2<Float>]=[]
        for row in 0...16 { for column in 0...12 {
            let x=Float(column)/12,y=Float(row)/16;source.append(SIMD2<Float>(x,y))
            var tx=x,ty=y
            for (index,paw) in centers.enumerated() {
                let dx=(x-Float(paw[0]))/0.10,dy=(y-Float(paw[1]))/0.11
                let strength=exp(-(dx*dx+dy*dy)*0.5)
                let side:Float=index == 0 ? -1:1
                tx+=side*(open ? 0.064:-0.025)*strength;ty+=(open ? 0.078:0.014)*strength
            }
            target.append(SIMD2<Float>(tx,ty))
        } }
        return SKWarpGeometryGrid(columns:12,rows:16,sourcePositions:source,destinationPositions:target)
    }
    func setReceivingFiles(_ active:Bool) {
        guard active != receivingFiles else { return }
        receivingFiles=active
        if active {
            if sleeping { setSleeping(false) }
            neutral()
            if hasNativeFilePoses {
                showFilePose("receive")
                sprite.run(.sequence([.scaleY(to:1.025,duration:0.12),.scaleY(to:1,duration:0.18)]),withKey:"file-arms")
            } else {
                sprite.warpGeometry=restingWarp
                if let reach=SKAction.warp(to:fileWarp(open:true),duration:0.22) { reach.timingMode = .easeOut;sprite.run(reach,withKey:"file-arms") }
            }
            expression.show(.surprised)
            inputMotionUntil=ProcessInfo.processInfo.systemUptime+0.35
        } else { idle() }
        onNeedsRender?()
    }
    func catchFiles() {
        receivingFiles=false;express(.proud)
        if hasNativeFilePoses {
            if heldCount>0 { heldFiles.catchBounce() }
            inputMotionUntil=ProcessInfo.processInfo.systemUptime+0.9;onNeedsRender?();return
        }
        sprite.warpGeometry=fileWarp(open:true)
        if let close=SKAction.warp(to:fileWarp(open:false),duration:0.18),let rest=SKAction.warp(to:restingWarp,duration:0.25) {
            close.timingMode = .easeInEaseOut;rest.timingMode = .easeOut
            sprite.run(.sequence([close,.wait(forDuration:0.32),rest]),withKey:"file-arms")
        }
        if heldCount>0 { heldFiles.catchBounce() }
        inputMotionUntil=ProcessInfo.processInfo.systemUptime+0.9;onNeedsRender?()
    }
    func express(_ emotion:PetEmotion) {
        guard !sleeping,!receivingFiles else { return }
        if profile == nil {
            let animation:PetAnimation=emotion == .sad || emotion == .shy ? .failed:emotion == .excited || emotion == .proud ? .jumping:emotion == .surprised ? .waving:emotion == .sleepy ? .waiting:.review
            play(animation,looping:false,relaxed:true);expression.show(emotion);onNeedsRender?();return
        }
        neutral();if hasNativeFilePoses,heldCount>0 { showFilePose("hold") };expression.show(emotion)
        let duration:TimeInterval=emotion == .sleepy ? 1.8:1.15
        let tilt:CGFloat=emotion == .curious ? 0.065:emotion == .shy ? -0.04:0
        let lift:CGFloat=emotion == .excited ? 9:emotion == .happy || emotion == .proud ? 3:0
        let upbeat=SKAction.group([.rotate(toAngle:tilt,duration:0.18),.scaleY(to:emotion == .surprised ? 1.04:emotion == .sad ? 0.96:1,duration:0.18),.moveTo(y:lift,duration:0.18)])
        let settle=SKAction.group([.rotate(toAngle:0,duration:0.3),.scaleY(to:1,duration:0.3),.moveTo(y:0,duration:0.3)])
        upbeat.timingMode = .easeOut;settle.timingMode = .easeInEaseOut
        sprite.run(.sequence([upbeat,.wait(forDuration:0.35),settle]),withKey:"emotion")
        inputMotionUntil=ProcessInfo.processInfo.systemUptime+duration
        let work=DispatchWorkItem { [weak self] in self?.idle() };expressionReset=work
        DispatchQueue.main.asyncAfter(deadline:.now()+duration,execute:work);onNeedsRender?()
    }
    func setSleeping(_ value:Bool) {
        guard value != sleeping else { return }; sleeping=value; stopFrames(); sprite.removeAllActions(); sprite.position = .zero; sprite.zRotation=0; sprite.setScale(1); sprite.xScale=flipped ? -1 : 1
        sleepLabel.isHidden = !value; sprite.alpha=value ? 0.85 : 1
        neutral(); if value,profile != nil { show(row:0,column:5);expression.show(.sleepy) };if !value { idle() }; onNeedsRender?()
    }
    func celebrate() {
        play(.jumping,looping:false,relaxed:false)
        if profile?.fullBody == true,!sleeping,!receivingFiles {
            let up=SKAction.moveTo(y:30,duration:0.24),down=SKAction.moveTo(y:0,duration:0.34)
            up.timingMode = .easeOut;down.timingMode = .easeIn
            sprite.run(.group([.sequence([up,down]),.rotate(byAngle:.pi*2,duration:0.58)]),withKey:"celebration")
            inputMotionUntil=ProcessInfo.processInfo.systemUptime+0.8;onNeedsRender?()
        }
    }
    func hideInBox() { play(.failed,looping:false,relaxed:false) }
    func wave() { play(.waving,looping:false,relaxed:false) }
    func play(_ animation:PetAnimation,looping:Bool,relaxed:Bool) {
        guard !sleeping,!receivingFiles else { return }
        if animation == .idle { idle(); return }
        animationState=animation
        let finite=[PetAnimation.waving,.jumping,.failed].contains(animation)
        begin(PetFrameSequence(row:animation.row,frames:animation.frames,duration:animation == .waiting && relaxed ? 2.2 : animation.duration,iterations:finite ? 2 : looping ? nil : 1))
        typingUntil=nil
    }
    func setWalking(_ value:Bool) {
        guard !receivingFiles else { return }
        if value {
            animationState = .running; begin(PetFrameSequence(row:(facing < 0) != flipped ? 2 : 1,frames:8,duration:1.06,iterations:nil))
            if profile?.fullBody == true {
                sprite.xScale=facing * (flipped ? -1:1);sprite.warpGeometry=restingWarp
                if let left=SKAction.warp(to:footWarp(left:true),duration:0.18),let right=SKAction.warp(to:footWarp(left:false),duration:0.18) {
                    left.timingMode = .easeInEaseOut;right.timingMode = .easeInEaseOut;sprite.run(.repeatForever(.sequence([left,right])),withKey:"gait")
                }
            }
        }
        else { idle() }
    }
    private func footWarp(left:Bool)->SKWarpGeometryGrid {
        let feet=profile?.footCenters ?? [[0.32,0.12],[0.68,0.12]]
        var source:[SIMD2<Float>]=[],target:[SIMD2<Float>]=[]
        for row in 0...16 { for column in 0...12 {
            let x=Float(column)/12,y=Float(row)/16;source.append(SIMD2<Float>(x,y));var ty=y,tx=x
            for (index,foot) in feet.enumerated() {
                let dx=(x-Float(foot[0]))/0.10,dy=(y-Float(foot[1]))/0.08,strength=exp(-(dx*dx+dy*dy)*0.5)
                let lifted=(index == 0) == left
                ty+=(lifted ? 0.025:-0.006)*strength;tx+=(lifted ? -0.014:0.014)*strength
            }
            target.append(SIMD2<Float>(tx,ty))
        } }
        return SKWarpGeometryGrid(columns:12,rows:16,sourcePositions:source,destinationPositions:target)
    }
    func face(_ direction:CGFloat) { facing=direction < 0 ? -1 : 1;if profile?.fullBody == true { sprite.xScale=facing * (flipped ? -1:1) } }
    func look(toward point:CGPoint) {
        guard !sleeping,!receivingFiles,animationState == .idle,let scene else { return }
        if profile != nil { express(.curious);return }
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
        if let pose=displayedFilePose.flatMap({filePoses[$0]}) {
            return pose.mask.contains(x:Int(floor(p.x+96)),y:207-Int(floor(p.y)))
        }
        let x=(p.x/sprite.size.width+0.5)*cell.width,y=p.y/sprite.size.height*cell.height
        guard x >= 0,y >= 0,x < cell.width,y < cell.height else { return false }
        return mask.contains(x:Int(x)+currentColumn*Int(cell.width),y:Int(cell.height-y-1)+currentRow*Int(cell.height))
    }
    private func updateAccessoryFit() {
        let fit=PetAccessoryFit.frame(id:petID,row:currentRow,column:currentColumn)
        let activeProfile=displayedFilePose.flatMap{filePoses[$0]?.profile} ?? frameProfile
        let measuredFit=petID.hasPrefix("pawpaw-") || displayedFilePose != nil
        if let profile=activeProfile,measuredFit {
            accessories.position=CGPoint(x:(profile.crown[0]-0.5)*192,y:(1-profile.crown[1])*208+7)
        } else { accessories.position=fit.crown }
        heldFiles.position=CGPoint(x:fit.crown.x*0.55,y:[1,2].contains(currentRow) ? 42:36)
        heldFiles.setScale([1,2].contains(currentRow) ? 0.85:1)
        if petID.hasPrefix("pawpaw-"),let profile {
            heldFiles.position=CGPoint(x:((profile.eyes[0].point[0]+profile.eyes[1].point[0])/2-0.5)*192,y:18)
            heldFiles.setScale(0.82)
        }
        if let profile=activeProfile,displayedFilePose != nil {
            let cx=(profile.eyes[0].point[0]+profile.eyes[1].point[0])/2
            let eyeY=(profile.eyes[0].point[1]+profile.eyes[1].point[1])/2
            heldFiles.position=CGPoint(x:(cx-0.5)*192,y:(1-(eyeY+(0.95-eyeY)*0.60))*208)
            heldFiles.setScale(1)
        }
        if let node=accessories.childNode(withName:"cosmetic") {
            let earInset:CGFloat = petID == "bunny" && ["free.beanie","free.crown","accessory.hat"].contains(accessorySKU) ? -17 : 0
            var eyeDrop=fit.glassesDrop
            if let profile=activeProfile,measuredFit {
                let eyeY=(1-(profile.eyes[0].point[1]+profile.eyes[1].point[1])/2)*208
                eyeDrop=accessories.position.y-eyeY-33*profile.accessoryScale
            }
            node.position=CGPoint(x:hatTransform.x,y:hatTransform.y + earInset - (accessorySKU == "accessory.glasses" ? eyeDrop : 0))
            node.setScale((measuredFit ? activeProfile?.accessoryScale ?? fit.scale:fit.scale) * hatTransform.scale)
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
        guard !value || !receivingFiles else { return }
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
