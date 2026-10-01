import SwiftUI

private typealias EditorState<Value> = SwiftUI.State<Value>
private enum ReminderSchedule: String, CaseIterable { case once = "One time", interval = "Interval", daily = "Daily times" }
struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: ReminderService
    @EditorState private var draft: PetReminder
    @EditorState private var schedule: ReminderSchedule
    @EditorState private var times: String
    @EditorState private var interval: Int
    @EditorState private var error = ""
    init(reminder: PetReminder, service: ReminderService) {
        self.service = service
        _draft = EditorState(initialValue: reminder)
        _schedule = EditorState(initialValue: reminder.specificTimes?.isEmpty == false ? .daily : reminder.intervalMinutes != nil ? .interval : .once)
        _times = EditorState(initialValue: reminder.specificTimes?.joined(separator: ", ") ?? "09:00, 15:00")
        _interval = EditorState(initialValue: reminder.intervalMinutes ?? 60)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.title.isEmpty ? "New reminder" : "Edit reminder").font(.title2.bold())
            Form {
                TextField("Title", text: $draft.title)
                Picker("Gesture", selection: $draft.kind) {
                    Text("Hydration").tag("water"); Text("Stretch").tag("stretch"); Text("Posture").tag("posture"); Text("Eye rest").tag("eyes"); Text("Custom / chore").tag("chore")
                }
                TextField("Pet’s message (optional)", text: $draft.message, axis: .vertical).lineLimit(2...3)
                Picker("Schedule", selection: $schedule) { ForEach(ReminderSchedule.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if schedule == .interval { Stepper("Every \(interval) minutes", value: $interval, in: 1...10080) }
                if schedule == .once { DatePicker("When", selection: $draft.nextDue) }
                if schedule == .daily {
                    TextField("Times (24-hour HH:mm)", text: $times)
                    Text("Separate daily times with commas, e.g. 09:00, 15:00.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Enabled", isOn: $draft.enabled)
                Toggle("High priority — interrupt focus sessions", isOn: Binding(get: { draft.highPriority == true }, set: { draft.highPriority = $0 }))
            }.formStyle(.grouped)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save reminder") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 490, height: 520)
    }
    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.message.isEmpty { draft.message = "A little nudge: \(draft.title)." }
        draft.snoozeUntil = nil
        switch schedule {
        case .once: draft.intervalMinutes = nil; draft.specificTimes = nil
        case .interval:
            if draft.intervalMinutes != interval || draft.specificTimes != nil { draft.nextDue = Date().addingTimeInterval(Double(interval*60)) }
            draft.intervalMinutes = interval; draft.specificTimes = nil
        case .daily:
            let values = times.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !values.isEmpty, values.count <= 24, values.allSatisfy(ReminderService.validTime), let next = ReminderService.nextTime(values, after: Date()) else { error = "Enter valid daily times, such as 09:00, 15:00."; return }
            draft.intervalMinutes = nil; draft.specificTimes = Array(Set(values)).sorted(); draft.nextDue = next
        }
        do { try service.upsert(draft); dismiss() } catch { self.error = error.localizedDescription }
    }
}
