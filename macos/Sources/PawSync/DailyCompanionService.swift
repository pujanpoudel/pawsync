import Combine
import Foundation

enum CompanionMood:String,Codable,CaseIterable,Identifiable { case great="Great",okay="Okay",tired="Tired",stressed="Stressed",sad="Sad"; var id:String{rawValue} }
struct MoodEntry:Codable,Identifiable { var id=UUID(); let date:Date; let mood:CompanionMood; let note:String }
@MainActor final class DailyCompanionService:ObservableObject {
    struct Snapshot:Codable {
        var version=1
        var greetingPolicy="everyLaunch"; var greetingMode="smart"; var customGreeting="So happy you’re here, buddy!"; var randomGreetings="A little company for your day.\nWe can take it one tiny step at a time."
        var greetingDelay=3; var awayHours=6; var lastGreeting:Date?; var lastSeen:Date?; var greetingReaction:PetReaction = .waving
        var morning="09:00"; var evening="18:00"; var routineDays=[2,3,4,5,6]; var morningMessage="Good morning! What’s one small thing you’d like to finish today?"; var eveningMessage="Time to leave a little room for rest. You did enough today."
        var delivered:[String:String]=[:]; var pausedDays:[String:String]=[:]
        var fortuneTime="10:00"; var moodTime="16:00"; var moods:[MoodEntry]=[]; var lastAnswer=""; var lastQuestion=""; var lastFortune=""
    }
    @Published var state:Snapshot { didSet { if !updating { save() } } }
    @Published private(set) var error=""
    var onMessage:((String,String,String,PetReaction)->Bool)?
    var onMoodCheck:(()->Bool)?
    var canDeliver:(()->Bool)?
    var greetingsEnabled:(()->Bool)?
    private let file:URL
    private let features:NativeFeatureRegistry
    private var scheduler:Timer?
    private var launchTimer:Timer?
    private var launchDue:Date
    private var shouldGreet:Bool
    private var updating=false
    static let fortunes=["A tiny step is still a step.","There’s room for a softer pace today.","Someone appreciates your quiet effort.","Your next good idea may arrive during a break.","Let curiosity lead you somewhere kind.","You can start again without starting over.","A little courage goes a long way.","The small things you finish count, too.","Save a little kindness for yourself.","A stretch and a sip might change your afternoon.","Your desk buddy believes in second attempts.","A calmer moment is waiting around the corner."]
    static let answers=["Signs point to yes!","A little yes, with extra paws.","Looks promising.","Trust your thoughtful side.","Ask after a little break.","The paws are still pondering.","Give it a bit more time.","Maybe another path will be kinder.","Not today, little friend.","Your patience may help.","A brave small step could help.","There’s a surprise ahead.","Let’s sleep on it.","Definitely worth a try.","Listen to your own answer, too.","The answer is hiding in a snack break."]
    init(features:NativeFeatureRegistry,directory:URL=PetStore.root,startTimer:Bool=true,now:Date=Date()) {
        self.features=features; file=directory.appendingPathComponent("Tools/daily.json")
        let initial=LocalState.read(Snapshot.self,at:file,limit:262144,validate:{ Self.valid($0) }) ?? Snapshot()
        state=initial
        launchDue=now.addingTimeInterval(Double(initial.greetingDelay))
        let today=Self.day(now),last=initial.lastGreeting
        shouldGreet=initial.greetingPolicy == "everyLaunch" || initial.greetingPolicy == "oncePerDay" && last.map{Self.day($0) != today} != false || initial.greetingPolicy == "afterAwayHours" && (initial.lastSeen.map{now.timeIntervalSince($0) >= Double(initial.awayHours*3600)} ?? true)
        if startTimer {
            launchTimer=Timer.scheduledTimer(withTimeInterval:max(0.1,Double(initial.greetingDelay)),repeats:false) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            scheduler=Timer.scheduledTimer(withTimeInterval:10,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }; scheduler?.tolerance=2
        }
    }
    static func valid(_ s:Snapshot)->Bool {
        s.version == 1 && ["everyLaunch","oncePerDay","afterAwayHours"].contains(s.greetingPolicy) && ["smart","custom","random"].contains(s.greetingMode) && (0...60).contains(s.greetingDelay) && (1...72).contains(s.awayHours) && [s.morning,s.evening,s.fortuneTime,s.moodTime].allSatisfy(ReminderService.validTime) && s.routineDays.count <= 7 && s.routineDays.allSatisfy{(1...7).contains($0)} && [s.customGreeting,s.morningMessage,s.eveningMessage].allSatisfy{$0.count <= 500} && s.randomGreetings.count <= 4000 && s.moods.count <= 180 && s.moods.allSatisfy{$0.note.count <= 300} && s.lastQuestion.count <= 300 && s.lastAnswer.count <= 500 && s.lastFortune.count <= 500 && s.delivered.count <= 20 && s.pausedDays.count <= 20
    }
    static func day(_ date:Date)->String { let c=Calendar.current.dateComponents([.year,.month,.day],from:date); return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!) }
    static func fortune(for date:Date)->String { let hash=day(date).utf8.reduce(UInt64(2166136261)){ ($0 ^ UInt64($1)) &* 16777619 }; return fortunes[Int(hash % UInt64(fortunes.count))] }
    func greet(manual:Bool=false,now:Date=Date()) {
        guard manual || shouldGreet else { return }
        let hour=Calendar.current.component(.hour,from:now),salutation=hour < 12 ? "Good morning!" : hour < 18 ? "Good afternoon!" : "Good evening!"
        let choices=state.randomGreetings.split(separator:"\n").map(String.init).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}
        let text=state.greetingMode == "custom" ? state.customGreeting : state.greetingMode == "random" ? choices.randomElement() ?? state.customGreeting : "I’m here for the little wins and the gentle breaks. Let’s make room for both."
        if onMessage?("launch",salutation,String(text.prefix(500)),state.greetingReaction) == true { state.lastGreeting=now; shouldGreet=false }
    }
    func resetGreeting() { state.lastGreeting=nil; shouldGreet=true; launchDue=Date(); tick() }
    func fortune(another:Bool=false,now:Date=Date()) { let text=another ? Self.fortunes.randomElement()! : Self.fortune(for:now); state.lastFortune=text; _=onMessage?("fortune","A little fortune",text,.waving) }
    func ask(_ question:String) { state.lastQuestion=String(question.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300)); state.lastAnswer=Self.answers.randomElement()!; _=onMessage?("8ball","The paws have spoken",state.lastAnswer,.waving) }
    func mood(_ mood:CompanionMood,note:String="",now:Date=Date()) {
        let entry=MoodEntry(date:now,mood:mood,note:String(note.prefix(300)))
        state.moods.removeAll{Self.day($0.date) == Self.day(now)}; state.moods.append(entry); state.moods=Array(state.moods.suffix(180)); state.delivered["mood"]=Self.day(now)
    }
    func pauseToday(_ feature:String,now:Date=Date()) { state.pausedDays[feature]=Self.day(now) }
    func routine(morning:Bool,now:Date=Date()) { let id=morning ? "morning" : "evening"; if onMessage?(id,morning ? "A fresh little morning" : "A softer evening",morning ? state.morningMessage : state.eveningMessage,.waving) == true { state.delivered[id]=Self.day(now) } }
    private func due(_ id:String,time:String,now:Date)->Bool {
        let today=Self.day(now),parts=time.split(separator:":"),clock=Calendar.current.dateComponents([.hour,.minute],from:now)
        return state.delivered[id] != today && state.pausedDays[id] != today && (clock.hour!*60+clock.minute!) >= (Int(parts[0])!*60+Int(parts[1])!)
    }
    func tick(now:Date=Date()) {
        guard Self.valid(state),canDeliver?() != false else { return }
        if greetingsEnabled?() != false,features.contains("openpets.launch-buddy"),now >= launchDue,shouldGreet { greet(now:now); return }
        if features.contains("openpets.day-routine"),state.routineDays.contains(Calendar.current.component(.weekday,from:now)) {
            if due("morning",time:state.morning,now:now),Calendar.current.component(.hour,from:now) < 15 { routine(morning:true,now:now); return }
            if due("evening",time:state.evening,now:now) { routine(morning:false,now:now); return }
        }
        if features.contains("openpets.fortune-cookie"),due("fortune",time:state.fortuneTime,now:now) {
            let text=Self.fortune(for:now); if onMessage?("fortune","A little fortune",text,.waving) == true { state.lastFortune=text; state.delivered["fortune"]=Self.day(now) }; return
        }
        if features.contains("openpets.mood-check-in"),due("mood",time:state.moodTime,now:now),onMoodCheck?() == true { state.delivered["mood"]=Self.day(now) }
    }
    private func save() { guard Self.valid(state) else { error="Please check the times and message lengths."; return }; do { try LocalState.write(state,at:file); error="" } catch { self.error="Could not save your daily companion preferences." } }
    func shutdown(now:Date=Date()) { launchTimer?.invalidate(); launchTimer=nil; scheduler?.invalidate(); scheduler=nil; state.lastSeen=now; save() }
}
