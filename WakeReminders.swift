import AppKit
import ServiceManagement
import UserNotifications

enum ReminderSlot: Int, CaseIterable {
    case morning = 11, evening = 20

    var name: String { self == .morning ? "morning" : "evening" }
    var agent: SMAppService {
        .agent(plistName: "local.daylist.notebook.\(name).plist")
    }
    var legacyIDs: [String] { (2...6).map { "\(name)-\($0)" } }

    func registerIfNeeded() throws {
        let service = agent
        switch service.status {
        case .enabled, .requiresApproval: break
        default: try service.register()
        }
    }

    var content: UNMutableNotificationContent {
        let message = UNMutableNotificationContent()
        message.title = self == .morning ? "Есть открытые задачи" : "Планы на завтра"
        message.body = self == .morning ? "Откройте список и выберите следующую задачу." : "Запишите задачи, которыми хотите заняться завтра."
        message.sound = .default
        return message
    }

    // Each launchd job represents one hour. Sleep can coalesce several runs of
    // the same job, so identify its most recent due weekday, even after midnight.
    func occurrence(at now: Date, calendar: Calendar) -> String? {
        guard (2...6).contains(calendar.component(.weekday, from: now)) else { return nil }
        var day = now
        if calendar.component(.hour, from: now) < rawValue {
            repeat {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
                day = previous
            } while !(2...6).contains(calendar.component(.weekday, from: day))
        }
        let date = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(name)-\(date.year!)-\(date.month!)-\(date.day!)"
    }

    @MainActor
    func deliver() async throws {
        // A maintenance wake need not light the display. If it stays asleep,
        // keep this one pending invocation until the user can see the reminder.
        while CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let id = occurrence(at: Date(), calendar: calendar) else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Daylist", isDirectory: true)
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        var openTasks = false
        if self == .morning {
            let book = Notebook()
            guard book.readable else { throw CocoaError(.fileReadUnknown) }
            openTasks = book.entries.contains(where: { !$0.done })
        }
        try await process(id: id, directory: directory, openTasks: openTasks) {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func process(id: String, directory: URL, openTasks: Bool, send: () async throws -> Void) async throws {
        let receipt = directory.appendingPathComponent("last-" + name)
        if (try? String(contentsOf: receipt, encoding: .utf8)) == id { return }
        if self == .evening || openTasks {
            try await send()
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try id.write(to: receipt, atomically: true, encoding: .utf8)
    }
}

#if !TEST_REMINDERS
@main
enum DaylistLauncher {
    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--reminder",
           let hour = Int(args[2]), let slot = ReminderSlot(rawValue: hour) {
            do {
                try await slot.deliver()
            } catch {
                NSLog("Reminder failed: %@", error.localizedDescription)
                exit(1)
            }
            return
        }
        if args.dropFirst() == ["--check-background"] {
            do {
                for slot in ReminderSlot.allCases {
                    try slot.registerIfNeeded()
                    guard slot.agent.status == .enabled else {
                        NSLog("Agent %@ status %d", slot.name, slot.agent.status.rawValue)
                        exit(1)
                    }
                }
            } catch {
                NSLog("Agent registration failed: %@", String(describing: error))
                exit(1)
            }
            return
        }
        DaylistApp.main()
    }
}
#endif
