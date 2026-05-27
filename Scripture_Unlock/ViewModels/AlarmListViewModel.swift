import Foundation
import SwiftData
import Observation

@Observable
final class AlarmListViewModel {

    var alarms: [Alarm] = []
    var showingNewAlarm = false
    var editingAlarm: Alarm?

    private let alarmService: AlarmService

    init(alarmService: AlarmService = .shared) {
        self.alarmService = alarmService

        NotificationCenter.default.addObserver(
            forName: .scriptureUnlockAlarmFired,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let uuid = note.userInfo?["alarmId"] as? UUID else { return }
            self?.handleAlarmFired(id: uuid)
        }
    }

    // MARK: - CRUD

    func toggle(_ alarm: Alarm) {
        alarm.isEnabled.toggle()
        Task {
            if alarm.isEnabled {
                try? await alarmService.schedule(alarm)
            } else {
                await alarmService.cancel(alarm)
            }
        }
    }

    func delete(_ alarm: Alarm, context: ModelContext) {
        Task { await alarmService.cancel(alarm) }
        context.delete(alarm)
    }

    func save(_ alarm: Alarm, context: ModelContext) {
        context.insert(alarm)
        Task { try? await alarmService.schedule(alarm) }
    }

    // MARK: - Computed

    var nextAlarmLabel: String {
        guard let next = alarms.filter(\.isEnabled).min(by: {
            $0.nextFireDate < $1.nextFireDate
        }) else { return "No alarms set" }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return "Next: \(next.label) at \(fmt.string(from: next.nextFireDate))"
    }

    // MARK: - Alarm fired

    private func handleAlarmFired(id: UUID) {
        guard let alarm = alarms.first(where: { $0.id == id }) else { return }
        alarmService.activeAlarm = alarm
    }
}
