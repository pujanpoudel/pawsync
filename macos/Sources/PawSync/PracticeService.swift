import AppKit
import AVFoundation
import Combine

enum GentlePractice:String,CaseIterable,Identifiable { case breathing="Paced breathing",muscle="Unwind your muscles",grounding="Grounding",meditation="Quiet moment",visualization="Peaceful place",sounds="Relaxing sounds"; var id:String{rawValue} }
enum AmbientTexture:String,CaseIterable,Identifiable { case quiet="Silent",rain="Soft rain",ocean="Ocean hush",noise="Soft noise"; var id:String{rawValue} }
@MainActor final class PracticeService:ObservableObject {
    @Published private(set) var kind:GentlePractice?
    @Published private(set) var remaining=0
    @Published private(set) var elapsed=0
    @Published private(set) var paused=false
    @Published var texture:AmbientTexture = .quiet { didSet { configureSound() } }
    var muted=true { didSet { configureSound() } }
    @Published private(set) var error=""
    private var timer:Timer?
    private var deadline:Date?
    private var duration=0
    private var engine:AVAudioEngine?
    var onEnded:(()->Void)?
    var instruction:String {
        guard let kind else { return "A little space for a calmer moment." }
        switch kind {
        case .breathing: switch elapsed%12 { case 0..<5:return "Breathe in gently"; case 5..<6:return "A soft pause"; default:return "Breathe out slowly" }
        case .muscle: return ["Let your hands soften.","Lift, then relax your shoulders.","Unclench your jaw.","Let your feet rest comfortably.","Notice what feels a little looser."][min(4,elapsed/max(1,duration/5))]
        case .grounding: return ["Notice five things you can see.","Notice four things you can feel.","Notice three sounds around you.","Notice two scents, or two colors.","Notice one small thing you appreciate."][min(4,elapsed/max(1,duration/5))]
        case .meditation:return "Let your thoughts pass by. Bring your attention gently back to this moment."
        case .visualization:return "Picture a peaceful place. Notice its colors, its sounds, and a comfortable spot to rest."
        case .sounds:return "Let a little gentle sound keep you company."
        }
    }
    var breathScale:Double { let position=Double(elapsed%12); return position < 5 ? 0.65+position/5*0.35 : position < 6 ? 1 : 1-(position-6)/6*0.35 }
    func start(_ practice:GentlePractice,minutes:Int=2,now:Date=Date()) {
        stop(); kind=practice; duration=max(60,min(1800,minutes*60)); remaining=duration; elapsed=0; paused=false; deadline=now.addingTimeInterval(Double(duration))
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }; timer?.tolerance=0.1; configureSound()
    }
    func tick(now:Date=Date()) { guard !paused,let deadline else { return }; remaining=max(0,Int(ceil(deadline.timeIntervalSince(now)))); elapsed=duration-remaining; if remaining == 0 { stop(); onEnded?() } }
    func pause(now:Date=Date()) { guard kind != nil,!paused else { return }; tick(now:now); paused=true; deadline=nil; engine?.pause() }
    func resume(now:Date=Date()) { guard paused,kind != nil else { return }; paused=false; deadline=now.addingTimeInterval(Double(remaining)); configureSound() }
    func stop() { timer?.invalidate(); timer=nil; deadline=nil; kind=nil; paused=false; remaining=0; elapsed=0; engine?.stop(); engine=nil }
    private func configureSound() {
        engine?.stop(); engine=nil
        guard !muted,kind != nil,!paused,texture != .quiet,let format=AVAudioFormat(standardFormatWithSampleRate:22050,channels:1) else { return }
        let engine=AVAudioEngine(),mode=texture
        // Generated ambience only. No microphone, captured system audio, file or network.
        var random:UInt64=0x7261696e736f6674,low:Float=0,frame:UInt64=0
        let source=AVAudioSourceNode(format:format) { _,_,count,buffers in
            let list=UnsafeMutableAudioBufferListPointer(buffers)
            for index in 0..<Int(count) {
                random ^= random << 13; random ^= random >> 7; random ^= random << 17
                let noise=Float(Double(random & 0xffff)/32768-1); low=low*0.98+noise*0.02
                let wave=Float(0.5+0.5*sin(Double(frame)/22050*0.7)); frame &+= 1
                let value:Float=mode == .rain ? noise*0.025+low*0.1 : mode == .ocean ? low*(0.15+wave*0.18) : noise*0.015
                for buffer in list { buffer.mData?.assumingMemoryBound(to:Float.self)[index]=value }
            }
            return noErr
        }
        engine.attach(source); engine.connect(source,to:engine.mainMixerNode,format:format)
        do { try engine.start(); self.engine=engine; error="" } catch { self.error="Ambient sound could not start. Your quiet practice is still available." }
    }
}
