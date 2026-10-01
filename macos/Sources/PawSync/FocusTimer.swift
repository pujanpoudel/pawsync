import AppKit
import Combine

@MainActor final class FocusTimer: ObservableObject {
    enum Phase: String,Codable { case ready = "Ready", focus = "Focus", rest = "Break" }
    private struct Snapshot:Codable { var version=1; var phase:Phase; var deadline:Date?; var pausedRemaining:Int?; var completed:Int }
    @Published private(set) var phase:Phase = .ready
    @Published private(set) var remaining=0
    @Published private(set) var paused=false
    @Published private(set) var completed=0
    @Published private(set) var error=""
    private var deadline:Date?
    private var timer:Timer?
    private let preferences:Preferences
    private let file:URL
    var onFocusChanged:((Bool)->Void)?
    var onCelebration:(()->Void)?
    init(preferences:Preferences,directory:URL=PetStore.root,startTimer:Bool=true) {
        self.preferences=preferences; file=directory.appendingPathComponent("Tools/focus.json")
        if let state=LocalState.read(Snapshot.self,at:file,validate:{$0.version == 1 && (0...1_000_000).contains($0.completed) && ($0.pausedRemaining == nil || (0...7200).contains($0.pausedRemaining!)) && ($0.phase == .ready || $0.deadline != nil || $0.pausedRemaining != nil)}) {
            phase=state.phase; completed=state.completed; deadline=state.deadline; paused=state.pausedRemaining != nil
            remaining=state.pausedRemaining ?? max(0,Int(ceil(state.deadline?.timeIntervalSinceNow ?? 0)))
        }
        if startTimer { timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }; timer?.tolerance=0.2 }
    }
    var display:String { String(format:"%02d:%02d",remaining/60,remaining%60) }
    func start(now:Date=Date()) {
        phase = .focus; paused=false; remaining=preferences.focusMinutes*60; deadline=now.addingTimeInterval(Double(remaining)); onFocusChanged?(true); save()
    }
    func pause(now:Date=Date()) {
        guard phase != .ready,!paused else { return }; remaining=max(0,Int(ceil(deadline?.timeIntervalSince(now) ?? 0))); paused=true; deadline=nil; onFocusChanged?(false); save()
    }
    func resume(now:Date=Date()) { guard paused,phase != .ready else { return }; paused=false; deadline=now.addingTimeInterval(Double(remaining)); onFocusChanged?(phase == .focus); save() }
    func skipToBreak(now:Date=Date()) { guard phase == .focus else { return }; phase = .rest; paused=false; remaining=preferences.breakMinutes*60; deadline=now.addingTimeInterval(Double(remaining)); onFocusChanged?(false); save() }
    func stop() { deadline=nil; phase = .ready; paused=false; remaining=0; onFocusChanged?(false); save() }
    func tick(now:Date=Date()) {
        guard !paused,phase != .ready,let deadline else { return }
        remaining=max(0,Int(ceil(deadline.timeIntervalSince(now))))
        guard remaining == 0 else { return }
        if phase == .focus {
            completed=min(1_000_000,completed+1); phase = .rest; remaining=preferences.breakMinutes*60; self.deadline=now.addingTimeInterval(Double(remaining))
            onFocusChanged?(false); onCelebration?(); if !preferences.muted { NSSound(named:"Glass")?.play() }; save()
        } else { stop() }
    }
    private func save() { do { try LocalState.write(Snapshot(phase:phase,deadline:deadline,pausedRemaining:paused ? remaining : nil,completed:completed),at:file); error="" } catch { self.error="Could not save your focus session." } }
    func shutdown() { timer?.invalidate(); timer=nil; save() }
}
