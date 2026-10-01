import Foundation
import Combine

struct ActivitySnapshot: Codable {
    var day: String
    var today = 0
    var total = 0
    var focusSessions = 0
}

@MainActor final class CompanionActivity: ObservableObject {
    @Published private(set) var snapshot: ActivitySnapshot
    private let file: URL
    private var saveTimer: Timer?
    private var pending=0
    private var publishWork:DispatchWorkItem?
    private var dirty=false
    var onLevelUp: (() -> Void)?
    var onGoalReached: (() -> Void)?
    var level: Int { Self.level(for: snapshot.total+pending) }
    var progress: Double { Double((snapshot.total+pending) % 500) / 500 }
    static func level(for total: Int) -> Int { max(0, total) / 500 + 1 }
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
    init(directory: URL = PetStore.root) {
        file = directory.appendingPathComponent("activity.json")
        snapshot = (try? JSONDecoder().decode(ActivitySnapshot.self, from: Data(contentsOf: file))) ?? ActivitySnapshot(day: Self.dayKey())
        snapshot.today = max(0, snapshot.today); snapshot.total = max(0, snapshot.total)
        refreshDay()
        // Write aggregate totals periodically, never one disk write per keypress.
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDay(); self?.save() }
        }
        saveTimer?.tolerance = 5
    }
    func refreshDay() {
        let day = Self.dayKey()
        if snapshot.day != day { flush(); snapshot.day = day; snapshot.today = 0; dirty=true }
    }
    func record(goal: Int) {
        refreshDay()
        let oldLevel = level, previous = snapshot.today+pending
        pending+=1; dirty=true
        if publishWork == nil {
            let work=DispatchWorkItem { [weak self] in self?.flush() }; publishWork=work
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
        }
        if level > oldLevel { onLevelUp?() }
        else if previous < goal, snapshot.today+pending >= goal { onGoalReached?() }
    }
    private func flush() {
        publishWork?.cancel(); publishWork=nil
        guard pending > 0 else { return }
        var value=snapshot; value.today+=pending; value.total+=pending; pending=0; snapshot=value
    }
    func completedFocus() { snapshot.focusSessions += 1; dirty=true; save() }
    func save() {
        flush(); guard dirty else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
            dirty=false
        } catch { /* Optional local aggregate stats must not stop the companion. */ }
    }
    func stop() { saveTimer?.invalidate(); saveTimer = nil; save() }
}
