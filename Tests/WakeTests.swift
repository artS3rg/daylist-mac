import Foundation

@main
struct WakeTests {
    static func main() async throws {
        try await checkNotes()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let morning = ReminderSlot.morning
        let evening = ReminderSlot.evening
        precondition(morning.occurrence(at: date(26, 12), calendar: calendar) == "morning-2026-11-26")
        precondition(evening.occurrence(at: date(27, 8), calendar: calendar) == "evening-2026-11-26")
        precondition(evening.occurrence(at: date(30, 8), calendar: calendar) == "evening-2026-11-27")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var messages: [String] = []
        func wake(_ day: Int, _ hour: Int, open: Bool) async throws {
            for slot in ReminderSlot.allCases {
                if let id = slot.occurrence(at: date(day, hour), calendar: calendar) {
                    try await slot.process(id: id, directory: directory, openTasks: open) { messages.append(id) }
                }
            }
        }
        try await wake(26, 21, open: true)
        try await wake(26, 22, open: true)
        precondition(messages == ["morning-2026-11-26", "evening-2026-11-26"])
        try await wake(27, 21, open: false)
        try await wake(28, 21, open: true)
        try await wake(29, 21, open: true)
        precondition(messages.count == 3 && messages.last == "evening-2026-11-27")
        print("Passed weekday, overnight, both slots, duplicate, empty-list and weekend checks.")
    }
}
