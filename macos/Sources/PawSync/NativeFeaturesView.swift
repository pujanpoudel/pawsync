import SwiftUI

private typealias FeatureState<Value> = SwiftUI.State<Value>
struct NativeFeaturesView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var features:NativeFeatureRegistry
    @ObservedObject var countdown:CountdownService
    @ObservedObject var daily:DailyCompanionService
    @ObservedObject var care:VirtualCareService
    @ObservedObject var resources:ResourceMonitor
    @ObservedObject var practices:PracticeService
    @FeatureState private var minutes=25
    @FeatureState private var timerLabel="A little task"
    @FeatureState private var question=""
    @FeatureState private var moodNote=""
    @FeatureState private var practice:GentlePractice = .breathing
    @FeatureState private var practiceMinutes=2
    private func toggle(_ id:String)->Binding<Bool> { Binding(get:{features.contains(id)},set:{features.set(id,enabled:$0)}) }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            DisclosureGroup("Choose extra tools") { featureList }
            if features.contains("openpets.simple-timer") { timerCard }
            if features.contains("openpets.launch-buddy") { greetingsCard }
            if features.contains("openpets.day-routine") { routineCard }
            if features.contains("openpets.fortune-cookie") { fortuneCard }
            if features.contains("openpets.magic-8-ball") { magicCard }
            if features.contains("openpets.mood-check-in") { moodCard }
            if features.contains("openpets.virtual-pet") { careCard }
            if features.contains("openpets.system-resources") { resourcesCard }
            if features.contains("openpets.anxiety-aid-tools") { practiceCard }
            if features.contains("openpets.water-reminder") { waterCard }
            if !features.error.isEmpty { Text(features.error).foregroundStyle(.red) }
        }
    }
    private var featureList:some View {
        GroupBox("Native companion features") {
            VStack(alignment:.leading,spacing:10) {
                Text("Turn on only the little helpers you want.").font(.caption).foregroundStyle(.secondary)
                ForEach(NativeFeature.all.filter{$0.phase == 2}) { feature in
                    HStack {
                        Toggle(feature.name,isOn:toggle(feature.id)).disabled(feature.phase > 2)
                        Spacer()
                        Text(feature.bundled ? "Built in" : "Optional").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding(8)
        }
    }
    private var timerCard:some View {
        GroupBox("Simple timer") {
            VStack(alignment:.leading,spacing:12) {
                Text(countdown.state.phase == .idle ? "Ready for a little countdown?" : "\(countdown.state.label) · \(countdown.state.phase.rawValue.capitalized)").font(.headline)
                if countdown.state.phase != .idle { Text(countdown.display).font(.system(size:34,weight:.medium,design:.rounded)).monospacedDigit() }
                TextField("Timer label",text:$timerLabel)
                Stepper("\(minutes) minutes",value:$minutes,in:1...1440)
                HStack {
                    ForEach([5,15,25,30,60],id:\.self) { value in Button("\(value)m") { try? countdown.start(minutes:value,label:timerLabel) } }
                    Button("Start") { try? countdown.start(minutes:minutes,label:timerLabel) }
                }
                HStack {
                    if countdown.state.phase == .running { Button("Pause") { countdown.pause() } }
                    if countdown.state.phase == .paused { Button("Resume") { countdown.resume() } }
                    if [.running,.paused].contains(countdown.state.phase) { Button("+5 minutes") { countdown.addFive() } }
                    if countdown.state.phase == .expired { Button("Snooze 5 minutes") { countdown.snooze() }; Button("Show alert") { countdown.show() } }
                    if countdown.state.phase != .idle { Button("Dismiss / cancel") { countdown.cancel() } }
                }
                Text("Your timer survives a restart. A focus session defers its pet alert until a break.").font(.caption).foregroundStyle(.secondary)
                if !countdown.error.isEmpty { Text(countdown.error).foregroundStyle(.red) }
            }.padding(8)
        }
    }
    private var greetingsCard:some View {
        GroupBox("Launch greetings") {
            VStack(alignment:.leading,spacing:10) {
                Picker("When",selection:$daily.state.greetingPolicy) { Text("Every launch").tag("everyLaunch"); Text("Once a day").tag("oncePerDay"); Text("After time away").tag("afterAwayHours") }
                Picker("Style",selection:$daily.state.greetingMode) { Text("Time aware").tag("smart"); Text("Custom").tag("custom"); Text("Random from my list").tag("random") }
                if daily.state.greetingMode == "custom" { TextField("Your greeting",text:$daily.state.customGreeting) }
                if daily.state.greetingMode == "random" { TextEditor(text:$daily.state.randomGreetings).frame(height:75); Text("One greeting per line.").font(.caption) }
                Stepper("Delay: \(daily.state.greetingDelay) seconds",value:$daily.state.greetingDelay,in:0...60)
                Stepper("Away for: \(daily.state.awayHours) hours",value:$daily.state.awayHours,in:1...72)
                Picker("Reaction",selection:$daily.state.greetingReaction) { ForEach(PetReaction.allCases.filter{!$0.loops}) { reaction in Text(reaction.rawValue.capitalized).tag(reaction) } }
                HStack { Button("Greet now") { daily.greet(manual:true) }; Button("Reset greeting history") { daily.resetGreeting() } }
            }.padding(8)
        }
    }
    private var routineCard:some View {
        GroupBox("Morning & evening") {
            VStack(alignment:.leading,spacing:10) {
                TextField("Morning, HH:mm",text:$daily.state.morning); TextField("Morning message",text:$daily.state.morningMessage)
                TextField("Evening, HH:mm",text:$daily.state.evening); TextField("Evening message",text:$daily.state.eveningMessage)
                HStack { ForEach(1...7,id:\.self) { day in Toggle(Calendar.current.shortWeekdaySymbols[day-1],isOn:Binding(get:{daily.state.routineDays.contains(day)},set:{ enabled in daily.state.routineDays.removeAll{$0 == day}; if enabled { daily.state.routineDays.append(day) } })).toggleStyle(.button) } }
                HStack { Button("Morning now") { daily.routine(morning:true) }; Button("Evening now") { daily.routine(morning:false) }; Button("Pause today") { daily.pauseToday("morning"); daily.pauseToday("evening") } }
            }.padding(8)
        }
    }
    private var fortuneCard:some View {
        GroupBox("A little fortune") {
            VStack(alignment:.leading,spacing:10) {
                TextField("Daily time, HH:mm",text:$daily.state.fortuneTime)
                Text(daily.state.lastFortune.isEmpty ? DailyCompanionService.fortune(for:Date()) : daily.state.lastFortune)
                HStack { Button("Today’s fortune") { daily.fortune() }; Button("Another fortune") { daily.fortune(another:true) }; Button("Pause today") { daily.pauseToday("fortune") } }
            }.padding(8)
        }
    }
    private var magicCard:some View {
        GroupBox("Magic 8-Ball") {
            VStack(alignment:.leading,spacing:10) {
                TextField("A question for the paws (optional)",text:$question)
                Text("A local toy. Your question stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Ask the paws") { daily.ask(question) }; Button("Quick answer") { daily.ask("") } }
                if !daily.state.lastAnswer.isEmpty { Text(daily.state.lastAnswer).font(.headline) }
            }.padding(8)
        }
    }
    private var moodCard:some View {
        GroupBox("Private mood check-in") {
            VStack(alignment:.leading,spacing:10) {
                TextField("Check-in time, HH:mm",text:$daily.state.moodTime)
                TextField("A little note (optional)",text:$moodNote)
                HStack { ForEach(CompanionMood.allCases) { mood in Button(mood.rawValue) { daily.mood(mood,note:moodNote); moodNote="" } } }
                Button("Pause today") { daily.pauseToday("mood") }
                Text("Saved locally, up to 180 daily check-ins. This history is never automatically shared with a team or AI provider.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(daily.state.moods.suffix(7).reversed())) { entry in HStack { Text(entry.date,style:.date); Spacer(); Text(entry.mood.rawValue) }; if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) } }
            }.padding(8)
        }
    }
    private var careCard:some View {
        GroupBox("Your buddy’s little needs") {
            VStack(alignment:.leading,spacing:10) {
                Text("\(care.needs.mood) · Bond level \(care.needs.level)").font(.headline)
                ForEach([("Food",care.needs.food),("Energy",care.needs.energy),("Play",care.needs.happiness),("Affection",care.needs.affection)],id:\.0) { label,value in HStack { Text(label).frame(width:70,alignment:.leading); ProgressView(value:value,total:100); Text("\(Int(value))").monospacedDigit().frame(width:30) } }
                HStack { Button("Feed") { care.care("feed") }; Button("Play") { care.care("play") }; Button("Pet") { care.care("pet") }; Button("Nap") { care.care("nap") } }
                Text("Each companion has its own saved needs. A nap restores energy over time.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
    private func percent(_ value:Double?)->String { value.map{String(format:"%.0f%%",$0)} ?? "Waiting for a sample" }
    private var resourcesCard:some View {
        GroupBox("Your Mac at a glance") {
            VStack(alignment:.leading,spacing:10) {
                Text("CPU \(percent(resources.sample.cpu)) · Memory \(percent(resources.sample.memory)) · Disk \(percent(resources.sample.disk))")
                if let battery=resources.sample.battery { Text("Battery \(battery)%") }
                if let down=resources.sample.download,let up=resources.sample.upload { Text(String(format:"Network ↓ %.1f KB/s · ↑ %.1f KB/s",down/1024,up/1024)).font(.caption) }
                Toggle("Gentle high-usage alerts",isOn:$resources.alerts)
                Button("Refresh aggregate metrics") { resources.refresh() }
                Text("Aggregate metrics only; no app or process names. GPU utilization is unavailable through this probe. Network totals may include virtual interfaces.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
    private var practiceCard:some View {
        GroupBox("A gentler moment") {
            VStack(alignment:.leading,spacing:12) {
                Picker("Practice",selection:$practice) { ForEach(GentlePractice.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Sound",selection:$practices.texture) { ForEach(AmbientTexture.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("\(practiceMinutes) minutes",value:$practiceMinutes,in:1...30)
                if practices.kind != nil {
                    if practices.kind == .breathing { Circle().fill(.purple.opacity(0.15)).frame(width:90,height:90).scaleEffect(practices.breathScale).animation(.easeInOut(duration:1),value:practices.breathScale).frame(maxWidth:.infinity) }
                    Text(practices.instruction).font(.headline)
                    Text("\(practices.remaining/60):\(String(format:"%02d",practices.remaining%60)) remaining").monospacedDigit()
                    HStack { Button(practices.paused ? "Resume" : "Pause") { if practices.paused { practices.resume() } else { practices.pause() } }; Button("Finish practice") { practices.stop() } }
                } else { Button("Start a little pause") { practices.start(practice,minutes:practiceMinutes) } }
                Text("Follow at your comfortable pace. Instructions and generated ambient sounds work offline. Guided narration downloads are not connected in this build.").font(.caption).foregroundStyle(.secondary)
                if !practices.error.isEmpty { Text(practices.error).foregroundStyle(.red) }
            }.padding(8)
        }
    }
    private var waterCard:some View {
        GroupBox("Water buddy") {
            VStack(alignment:.leading,spacing:10) {
                Text("Uses your existing hydration reminder, so you receive one nudge per occurrence.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("I drank water") { model.acknowledgeWater() }; Button("Pause water today") { model.pauseWaterToday() }; Button("Preview") { model.reminders.showPreview() } }
                Button("Edit hydration cadence") { model.settingsSection = .reminders }
            }.padding(8)
        }
    }
}
