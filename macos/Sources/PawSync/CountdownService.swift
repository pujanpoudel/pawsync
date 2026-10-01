import Combine
import Foundation

@MainActor final class CountdownService:ObservableObject {
    enum Phase:String,Codable { case idle,running,paused,expired }
    struct Snapshot:Codable { var version=1; var phase:Phase = .idle; var id=UUID(); var label="Little timer"; var duration=1500.0; var deadline:Date?; var pausedRemaining:Double?; var alertDelivered=false }
    @Published private(set) var state:Snapshot
    @Published private(set) var remaining=0
    @Published private(set) var error=""
    var onExpired:((String)->Bool)?
    private let file:URL
    private var timer:Timer?
    var display:String { let hours=remaining/3600; return hours > 0 ? String(format:"%d:%02d:%02d",hours,remaining/60%60,remaining%60) : String(format:"%02d:%02d",remaining/60,remaining%60) }
    init(directory:URL=PetStore.root,startTimer:Bool=true) {
        file=directory.appendingPathComponent("Tools/countdown.json")
        state=LocalState.read(Snapshot.self,at:file,validate:{ value in
            value.version == 1 && value.label.count <= 80 && (60...86400).contains(value.duration) && (value.phase != .running || value.deadline != nil) && (value.phase != .paused || (value.pausedRemaining.map{(0...86400).contains($0)} ?? false))
        }) ?? Snapshot()
        updateRemaining(now:Date())
        if startTimer { timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }; timer?.tolerance=0.2 }
    }
    func start(minutes:Int,label:String="Little timer",now:Date=Date()) throws {
        guard (1...1440).contains(minutes) else { throw PawError.message("Choose a timer between 1 minute and 24 hours.") }
        let clean=label.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        state=Snapshot(phase:.running,label:String((clean.isEmpty ? "Little timer" : clean).prefix(80)),duration:Double(minutes*60),deadline:now.addingTimeInterval(Double(minutes*60)))
        updateRemaining(now:now); save()
    }
    func pause(now:Date=Date()) { guard state.phase == .running else { return }; updateRemaining(now:now); state.pausedRemaining=Double(remaining); state.deadline=nil; state.phase = .paused; save() }
    func resume(now:Date=Date()) { guard state.phase == .paused else { return }; state.deadline=now.addingTimeInterval(state.pausedRemaining ?? 0); state.pausedRemaining=nil; state.phase = .running; save() }
    func addFive(now:Date=Date()) {
        guard state.phase == .running || state.phase == .paused else { return }
        updateRemaining(now:now); let extra=min(300,max(0,86400-remaining)); state.duration=min(86400,state.duration+Double(extra))
        if state.phase == .running { state.deadline=state.deadline?.addingTimeInterval(Double(extra)) } else { state.pausedRemaining=Double(remaining+extra) }
        updateRemaining(now:now); save()
    }
    func snooze(now:Date=Date()) { guard state.phase == .expired else { return }; state.phase = .running; state.duration=300; state.deadline=now.addingTimeInterval(300); state.alertDelivered=false; updateRemaining(now:now); save() }
    func cancel() { state=Snapshot(); remaining=0; save() }
    func show() { if state.phase == .expired { _=onExpired?(state.label) } }
    func tick(now:Date=Date()) {
        updateRemaining(now:now)
        if state.phase == .running,remaining == 0 { state.phase = .expired; state.deadline=nil; state.alertDelivered=false; save() }
        if state.phase == .expired,!state.alertDelivered,onExpired?(state.label) == true { state.alertDelivered=true; save() }
    }
    private func updateRemaining(now:Date) { let value=state.phase == .running ? max(0,Int(ceil(state.deadline?.timeIntervalSince(now) ?? 0))) : state.phase == .paused ? max(0,Int(ceil(state.pausedRemaining ?? 0))) : 0; if remaining != value { remaining=value } }
    private func save() { do { try LocalState.write(state,at:file); error="" } catch { self.error="Could not save your timer." } }
    func shutdown() { timer?.invalidate(); timer=nil; save() }
}
