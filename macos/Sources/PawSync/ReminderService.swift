import AppKit
import Combine
import UserNotifications

struct PetReminder: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var message: String
    var kind: String
    var enabled: Bool
    var intervalMinutes: Int?
    var nextDue: Date
    var specificTimes: [String]? = nil
    var highPriority: Bool? = nil
    var snoozeUntil: Date? = nil
    var effectiveDue: Date { snoozeUntil ?? nextDue }
    var scheduleDescription: String {
        if let times = specificTimes, !times.isEmpty { return times.joined(separator: ", ") + " daily" }
        if let intervalMinutes { return "Every \(intervalMinutes) min" }
        return "One time"
    }
}
struct ReminderPlan: Codable {
    var version:Int? = nil
    var reminders: [PetReminder]
    var quietHours = true
    var quietStart = 22
    var quietEnd = 8
    var pauseDuringFocus = true
}

@MainActor final class ReminderService: ObservableObject {
    @Published private(set) var plan: ReminderPlan
    @Published private(set) var active: PetReminder?
    @Published private(set) var message = ""
    @Published private(set) var notificationStatus = "Optional system notifications cover hidden and full-screen reminders."
    var onReminder: ((PetReminder) -> Void)?
    var onCleared: (() -> Void)?
    var isSuspended: (() -> Bool)?
    var isFocusActive: (() -> Bool)?
    var needsSystemNotification: (() -> Bool)?
    var isReminderSuppressed:((PetReminder)->Bool)?
    @discardableResult func notify(title:String,message:String,id:String)->Bool {
        guard notificationAllowed else { return false }
        let content=UNMutableNotificationContent(); content.title=String(title.prefix(120)); content.body=String(message.prefix(500))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:id,content:content,trigger:nil)) { [weak self] error in if error != nil { Task { @MainActor in self?.message="System notification delivery failed. Your pending pet alert is retained in Settings." } } }
        return true
    }
    private let file: URL
    private var timer: Timer?
    private var preview = false
    private var notificationAllowed = false
    static let presets: [(String, String, String, Int)] = [
        ("water", "Drink some water", "A little sip? Your water bottle misses you.", 60),
        ("stretch", "Time to stretch", "Let’s stand up and take a gentle stretch break.", 45),
        ("posture", "Check your posture", "Relax your shoulders and sit comfortably, buddy.", 50),
        ("eyes", "Rest your eyes", "Look at something far away for twenty seconds. I’ll wait here.", 20)
    ]
    static func defaults(now: Date) -> ReminderPlan {
        ReminderPlan(reminders: presets.map { kind, title, message, interval in
            PetReminder(id: UUID(), title: title, message: message, kind: kind, enabled: kind == "water" || kind == "stretch", intervalMinutes: interval, nextDue: now.addingTimeInterval(Double(interval * 60)))
        })
    }
    init(directory: URL = PetStore.root, startTimer: Bool = true) {
        file = directory.appendingPathComponent("Reminders/reminders.json")
        let old = directory.appendingPathComponent("reminders.json")
        let source = FileManager.default.fileExists(atPath: file.path) ? file : old
        let saved = LocalState.read(ReminderPlan.self,at:source,validate:{ ($0.version == nil || $0.version == 1) && $0.reminders.count <= 1000 }) ?? Self.defaults(now:Date())
        plan = saved
        plan.version = 1
        plan.quietStart = min(23, max(0, plan.quietStart)); plan.quietEnd = min(23, max(0, plan.quietEnd))
        plan.reminders = saved.reminders.filter { !$0.title.isEmpty && $0.title.count <= 120 && $0.message.count <= 500 && ($0.intervalMinutes == nil || (1...10080).contains($0.intervalMinutes!)) && ($0.specificTimes ?? []).allSatisfy(Self.validTime) }
        if startTimer {
            save() // Migrate the earlier local file to the specified Reminders directory.
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            timer?.tolerance = 2
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                Task { @MainActor in self?.notificationAllowed = settings.authorizationStatus == .authorized }
            }
        }
    }
    static func validTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { $0.count == 2 } && Int(parts[0]).map { (0...23).contains($0) } == true && Int(parts[1]).map { (0...59).contains($0) } == true
    }
    static func nextTime(_ times: [String], after now: Date, calendar: Calendar = .current) -> Date? {
        times.filter(validTime).compactMap { text in
            let parts = text.split(separator: ":")
            return calendar.nextDate(after: now, matching: DateComponents(hour: Int(parts[0]), minute: Int(parts[1]), second: 0), matchingPolicy: .nextTime)
        }.min()
    }
    static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? hour >= start && hour < end : hour >= start || hour < end
    }
    func tick(now: Date = Date()) {
        guard active == nil, isSuspended?() != true else { return }
        let hour = Calendar.current.component(.hour, from: now)
        guard !plan.quietHours || !Self.isQuiet(hour: hour, start: plan.quietStart, end: plan.quietEnd) else { return }
        let focus = plan.pauseDuringFocus && isFocusActive?() == true
        guard let due = plan.reminders.filter({ $0.enabled && $0.effectiveDue <= now && (!focus || $0.highPriority == true) && isReminderSuppressed?($0) != true }).min(by: { $0.effectiveDue < $1.effectiveDue }) else { return }
        preview = false; active = due
        if needsSystemNotification?() == true { postNotification(due) }
        onReminder?(due)
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, error in
            Task { @MainActor in
                self?.notificationAllowed = allowed
                self?.notificationStatus = error?.localizedDescription ?? (allowed ? "System notifications enabled." : "Notifications are off. You can enable PawSync in System Settings → Notifications.")
            }
        }
    }
    private func postNotification(_ item: PetReminder) {
        guard notificationAllowed else { return }
        let content = UNMutableNotificationContent(); content.title = item.title; content.body = item.message
        // Pet sound preference is respected by the in-app delivery; system alerts stay silent.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pawsync-\(item.id)", content: content, trigger: nil))
    }
    func configure(_ id: UUID, enabled: Bool? = nil, minutes: Int? = nil, now: Date = Date()) {
        guard let i = plan.reminders.firstIndex(where: { $0.id == id }) else { return }
        if let enabled { plan.reminders[i].enabled = enabled }
        if let minutes {
            let interval = min(10080, max(1, minutes)); plan.reminders[i].intervalMinutes = interval
            plan.reminders[i].specificTimes = nil; plan.reminders[i].snoozeUntil = nil
            plan.reminders[i].nextDue = now.addingTimeInterval(Double(interval * 60))
        }
        if active?.id == id, enabled == false { clear() }
        save()
    }
    func upsert(_ item: PetReminder) throws {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.title.count <= 120, item.message.count <= 500,
              item.intervalMinutes.map({ (1...10080).contains($0) }) ?? true,
              (item.specificTimes ?? []).allSatisfy(Self.validTime) else { throw PawError.message("Check the title, message, interval and times (HH:mm).") }
        if let index = plan.reminders.firstIndex(where: { $0.id == item.id }) { plan.reminders[index] = item }
        else { plan.reminders.append(item) }
        if active?.id == item.id { clear() }
        message = "Reminder saved."; save()
    }
    func addChore(title: String, due: Date, daily: Bool) {
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let times = daily ? [DateFormatter.localizedTime(due)] : nil
        do { try upsert(PetReminder(id: UUID(), title: clean, message: "A little nudge: \(clean).", kind: "chore", enabled: true, intervalMinutes: nil, nextDue: due, specificTimes: times)) }
        catch { message = error.localizedDescription }
    }
    func remove(_ id: UUID) { if active?.id == id { clear() }; plan.reminders.removeAll { $0.id == id }; save() }
    func setQuiet(enabled: Bool? = nil, start: Int? = nil, end: Int? = nil, pauseFocus: Bool? = nil) {
        if let enabled { plan.quietHours = enabled }; if let start { plan.quietStart = min(23, max(0, start)) }
        if let end { plan.quietEnd = min(23, max(0, end)) }; if let pauseFocus { plan.pauseDuringFocus = pauseFocus }; save()
    }
    func showPreview(kind: String = "water") {
        guard let item = plan.reminders.first(where: { $0.kind == kind }) else { return }
        preview = true; active = item; onReminder?(item)
    }
    func complete(now: Date = Date()) {
        guard let active else { return }
        if !preview, let i = plan.reminders.firstIndex(where: { $0.id == active.id }) {
            plan.reminders[i].snoozeUntil = nil
            if let times = plan.reminders[i].specificTimes, let next = Self.nextTime(times, after: now) { plan.reminders[i].nextDue = next }
            else if let interval = plan.reminders[i].intervalMinutes {
                let seconds = Double(interval * 60)
                let elapsed = max(0, now.timeIntervalSince(plan.reminders[i].nextDue))
                plan.reminders[i].nextDue.addTimeInterval((floor(elapsed / seconds) + 1) * seconds)
            } else { plan.reminders.remove(at: i) }
        }
        clear(); save()
    }
    func snooze(now: Date = Date(), minutes: Int = 10) {
        guard let active else { return }
        if !preview, let i = plan.reminders.firstIndex(where: { $0.id == active.id }) { plan.reminders[i].snoozeUntil = now.addingTimeInterval(Double(max(1, minutes) * 60)) }
        clear(); save()
    }
    private func clear() { active = nil; preview = false; onCleared?() }
    func deferActive() { clear() }
    func save() {
        do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(plan).write(to: file, options: .atomic) }
        catch { message = "Could not save reminders: \(error.localizedDescription)" }
    }
    func stop() { timer?.invalidate(); timer = nil; save() }
}
private extension DateFormatter {
    static func localizedTime(_ date: Date) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"; return formatter.string(from: date) }
}
