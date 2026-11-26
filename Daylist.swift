import AppKit
import SwiftUI
import UserNotifications

struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var notes = ""
    var done = false
}

@MainActor
final class Notebook: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published var problem: String?
    @Published private(set) var readable = true
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Daylist/tasks.json")

    init() {
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // A new notebook starts empty.
        } catch {
            readable = false
            problem = "Не удалось прочитать список задач. Файл сохранён по адресу " + url.path
        }
    }

    @discardableResult
    func save(_ entry: Entry) -> Bool {
        guard readable else { return false }
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == entry.id }) {
            updated[index] = entry
        } else {
            updated.insert(entry, at: 0)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            entries = updated
            return true
        } catch {
            problem = "Не удалось сохранить задачу. " + error.localizedDescription
            return false
        }
    }
}

@MainActor
final class Reminders: ObservableObject {
    @Published var status: UNAuthorizationStatus = .notDetermined
    @Published var problem: String?
    private let center = UNUserNotificationCenter.current()
    private var wanted: Bool?
    private var processing = false

    func authorize() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            problem = error.localizedDescription
        }
    }

    // Coalesce changes while notification requests are in flight.
    func refresh(openTasks: Bool) async {
        wanted = openTasks
        guard !processing else { return }
        processing = true
        defer { processing = false }
        while let hasOpen = wanted {
            wanted = nil
            status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { continue }
            if !hasOpen {
                center.removePendingNotificationRequests(withIdentifiers: (2...6).map { "morning-" + String($0) })
            }
            do {
                for day in 2...6 {
                    for hour in (hasOpen ? [11, 20] : [20]) {
                        let morning = hour == 11
                        let message = UNMutableNotificationContent()
                        message.title = morning ? "Есть открытые задачи" : "Планы на завтра"
                        message.body = morning ? "Откройте список и выберите следующую задачу." : "Запишите задачи, которыми хотите заняться завтра."
                        message.sound = .default
                        var date = DateComponents()
                        date.weekday = day
                        date.hour = hour
                        date.minute = 0
                        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                        let id = (morning ? "morning-" : "evening-") + String(day)
                        try await center.add(UNNotificationRequest(identifier: id, content: message, trigger: trigger))
                    }
                }
                problem = nil
            } catch {
                problem = "Не удалось обновить напоминания. " + error.localizedDescription
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            completion()
        }
    }
}

@main
struct DaylistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Дела", id: "notebook") { NotebookView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 640, height: 620)
    }
}

enum Appearance: String, CaseIterable {
    case system = "Системная", light = "Светлая", dark = "Тёмная"

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Accent: String, CaseIterable {
    case green = "Зелёный", blue = "Синий", purple = "Фиолетовый", pink = "Розовый"
    case red = "Красный", orange = "Оранжевый", yellow = "Жёлтый", gray = "Серый"

    var color: Color {
        switch self {
        case .green: return Color(nsColor: .systemGreen)
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .gray: return .gray
        }
    }
}

struct NotebookView: View {
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("accent") private var accent = Accent.green
    @State private var showingAppearance = false
    @StateObject private var book = Notebook()
    @StateObject private var reminders = Reminders()
    @Environment(\.scenePhase) private var phase
    @State private var completed = false
    @State private var draft: Entry?
    private var hasOpen: Bool { book.entries.contains { !$0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Мои задачи").font(.system(size: 36, weight: .medium, design: .serif))
                }
                Spacer()
                Button { showingAppearance.toggle() } label: {
                    Image(systemName: "paintpalette").font(.title3)
                }
                .buttonStyle(.plain).help("Оформление").accessibilityLabel("Оформление")
                .popover(isPresented: $showingAppearance) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Оформление").font(.headline)
                        Picker("Тема", selection: $appearance) {
                            ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("Акцентный цвет").font(.subheadline)
                        HStack(spacing: 8) {
                            ForEach(Accent.allCases, id: \.self) { choice in
                                Button { accent = choice } label: {
                                    Circle().fill(choice.color).frame(width: 22, height: 22)
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(choice == accent ? Color.primary : .clear, lineWidth: 2))
                                }.buttonStyle(.plain).help(choice.rawValue)
                                    .accessibilityLabel(choice.rawValue)
                                    .accessibilityAddTraits(choice == accent ? .isSelected : [])
                            }
                        }
                    }.padding(18)
                }
                Button { draft = Entry() } label: {
                    Label("Задача", systemImage: "plus").padding(.horizontal, 5)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut("n").disabled(!book.readable)
            }
            .padding(.bottom, 28)
            HStack(spacing: 22) {
                tab("Открытые", false)
                tab("Готовые", true)
            }
            Divider()
            let visible = book.entries.filter { $0.done == completed }
            if visible.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: completed ? "checkmark.circle" : "list.bullet")
                        .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                    Text(completed ? "Здесь появятся выполненные задачи" : "Открытых задач пока нет")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    var changed = item
                                    changed.done.toggle()
                                    book.save(changed)
                                } label: {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 19)).foregroundStyle(item.done ? accent.color : Color.secondary)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(item.done ? "Вернуть в открытые" : "Отметить выполненной")
                                Button { draft = item } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.headline).strikethrough(item.done)
                                        if !item.notes.isEmpty {
                                            Text(item.notes).lineLimit(2).foregroundStyle(.secondary)
                                        }
                                    }.multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 15)
                            Divider()
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                Image(systemName: "bell")
                Text("По будням · 11:00 и 20:00")
                Spacer()
                if reminders.status == .notDetermined {
                    Button("Включить") {
                        Task { await reminders.authorize(); await reminders.refresh(openTasks: hasOpen) }
                    }
                } else if reminders.status == .denied {
                    Button("Разрешить в настройках") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 14)
            if let error = reminders.problem {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .padding(.horizontal, 32).padding(.top, 30).padding(.bottom, 18)
        .frame(minWidth: 490, minHeight: 400)
        .sheet(item: $draft) { item in
            Editor(entry: item, isNew: !book.entries.contains { $0.id == item.id }) { updated in
                if book.save(updated) {
                    completed = updated.done
                    draft = nil
                }
            }.tint(accent.color).preferredColorScheme(appearance.scheme)
        }
        .tint(accent.color)
        .preferredColorScheme(appearance.scheme)
        .alert("Список задач", isPresented: Binding(get: { book.problem != nil }, set: { if !$0 { book.problem = nil } })) {
            Button("Закрыть") { book.problem = nil }
        } message: { Text(book.problem ?? "") }
        .task {
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
                await reminders.authorize()
            }
            if book.readable { await reminders.refresh(openTasks: hasOpen) }
        }
        .onChange(of: hasOpen) { value in Task { await reminders.refresh(openTasks: value) } }
        .onChange(of: phase) { value in
            if value == .active && book.readable { Task { await reminders.refresh(openTasks: hasOpen) } }
        }
    }

    private func tab(_ title: String, _ done: Bool) -> some View {
        Button { completed = done } label: {
            HStack(spacing: 6) {
                Text(title)
                Text(String(book.entries.filter { $0.done == done }.count)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.bottom, 10)
                .overlay(alignment: .bottom) { if completed == done { Rectangle().fill(accent.color).frame(height: 2) } }
        }.buttonStyle(.plain).foregroundStyle(completed == done ? Color.primary : Color.secondary)
    }
}

struct Editor: View {
    @State var entry: Entry
    let isNew: Bool
    let commit: (Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    init(entry: Entry, isNew: Bool, commit: @escaping (Entry) -> Void) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
        self.commit = commit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Новая задача" : "Редактирование").font(.system(size: 26, design: .serif))
            Text("Название").font(.headline)
            TextField("Что нужно сделать?", text: $entry.title).textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            Text("Описание").font(.headline)
            TextEditor(text: $entry.notes).font(.body).padding(5)
                .scrollContentBackground(.hidden)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.35)))
                .frame(height: 110)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    var updated = entry
                    updated.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    commit(updated)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 430).onAppear { titleFocused = true }
    }
}
