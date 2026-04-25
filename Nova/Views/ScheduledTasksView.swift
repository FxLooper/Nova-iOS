import SwiftUI
import UserNotifications

struct ScheduledTask: Identifiable, Codable {
    let id: String
    var name: String
    var time: String      // "07:00"
    var days: [String]    // ["mon","tue",...] nebo ["*"]
    var prompt: String
    var enabled: Bool
    var trusted: Bool = false  // automaticky schválené akce (email, kalendář, volání, dev)
}

struct ScheduledTasksView: View {
    @EnvironmentObject var nova: NovaService
    @Environment(\.dismiss) var dismiss

    @State private var tasks: [ScheduledTask] = []
    @State private var showAdd = false
    @State private var loading = false
    @State private var recentResults: [[String: Any]] = []
    @State private var selectedResult: [String: Any]? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "f5f0e8").ignoresSafeArea()

                if tasks.isEmpty && !loading {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.badge")
                            .font(.system(size: 56, weight: .ultraLight))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                        Text("Žádné naplánované úkoly")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                        Text("Klepni na + a vytvoř si první")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                    }
                } else {
                    List {
                        if !tasks.isEmpty {
                            Section("Úkoly") {
                                ForEach(tasks) { task in
                                    TaskRow(task: task) { updated in
                                        Task { await updateTask(updated) }
                                    } onDelete: {
                                        Task { await deleteTask(task) }
                                    }
                                }
                            }
                        }

                        if !recentResults.isEmpty {
                            Section("Poslední výsledky") {
                                ForEach(0..<recentResults.count, id: \.self) { i in
                                    let r = recentResults[i]
                                    Button(action: { selectedResult = r }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(r["taskName"] as? String ?? "")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.7))
                                                Text(r["result"] as? String ?? "")
                                                    .font(.system(size: 12, weight: .light))
                                                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                if let ts = r["timestamp"] as? String {
                                                    Text(ts.prefix(16).replacingOccurrences(of: "T", with: " "))
                                                        .font(.system(size: 10, weight: .light, design: .monospaced))
                                                        .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .light))
                                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.3))
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Naplánované úkoly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hotovo") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAdd = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaskView { newTask in
                Task {
                    await addTask(newTask)
                    showAdd = false
                }
            }
        }
        .sheet(item: Binding<ResultIdentifier?>(
            get: { selectedResult.map { ResultIdentifier(data: $0) } },
            set: { selectedResult = $0?.data }
        )) { item in
            ResultDetailView(result: item.data)
        }
        .onAppear {
            requestNotificationPermission()
            Task {
                await loadTasks()
                openPendingTaskResultIfNeeded()
            }
        }
    }

    /// Když uživatel klepl na push notifikaci cronu/briefingu, AppDelegate uložil
    /// `pendingCronTaskId` do UserDefaults. Po načtení seznamu najdeme odpovídající
    /// poslední výsledek a otevřeme rovnou jeho detail.
    private func openPendingTaskResultIfNeeded() {
        let defaults = UserDefaults.standard
        guard let taskId = defaults.string(forKey: "pendingCronTaskId"), !taskId.isEmpty else { return }
        defaults.removeObject(forKey: "pendingCronTaskId")

        // Najdi match nejdřív přímo podle taskId v recentResults, pak fallback na jméno úkolu
        if let byId = recentResults.first(where: { ($0["taskId"] as? String) == taskId }) {
            selectedResult = byId
            return
        }
        if let task = tasks.first(where: { $0.id == taskId }),
           let byName = recentResults.first(where: { ($0["taskName"] as? String) == task.name }) {
            selectedResult = byName
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func loadTasks() async {
        loading = true
        defer { loading = false }
        guard let url = URL(string: "\(nova.getServerURL())/api/scheduled") else { return }
        var req = URLRequest(url: url)
        req.setValue(nova.getToken(), forHTTPHeaderField: "X-Nova-Token")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let taskData = json["tasks"] as? [[String: Any]] {
                    tasks = taskData.compactMap { dict in
                        guard let id = dict["id"] as? String,
                              let name = dict["name"] as? String,
                              let time = dict["time"] as? String,
                              let prompt = dict["prompt"] as? String else { return nil }
                        return ScheduledTask(
                            id: id, name: name, time: time,
                            days: dict["days"] as? [String] ?? ["*"],
                            prompt: prompt,
                            enabled: dict["enabled"] as? Bool ?? true,
                            trusted: dict["trusted"] as? Bool ?? false
                        )
                    }
                }
                recentResults = json["recentResults"] as? [[String: Any]] ?? []
            }
        } catch { dlog("[scheduled] load error: \(error)") }
    }

    private func addTask(_ task: ScheduledTask) async {
        guard let url = URL(string: "\(nova.getServerURL())/api/scheduled/add") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(nova.getToken(), forHTTPHeaderField: "X-Nova-Token")
        let payload: [String: Any] = [
            "name": task.name, "time": task.time, "days": task.days,
            "prompt": task.prompt, "enabled": task.enabled, "trusted": task.trusted
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
        scheduleLocalNotification(for: task)
        await loadTasks()
    }

    private func updateTask(_ task: ScheduledTask) async {
        guard let url = URL(string: "\(nova.getServerURL())/api/scheduled/\(task.id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(nova.getToken(), forHTTPHeaderField: "X-Nova-Token")
        let payload: [String: Any] = ["enabled": task.enabled, "name": task.name, "time": task.time, "days": task.days, "prompt": task.prompt, "trusted": task.trusted]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
        scheduleLocalNotification(for: task)
        await loadTasks()
    }

    private func deleteTask(_ task: ScheduledTask) async {
        guard let url = URL(string: "\(nova.getServerURL())/api/scheduled/\(task.id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(nova.getToken(), forHTTPHeaderField: "X-Nova-Token")
        _ = try? await URLSession.shared.data(for: req)
        cancelLocalNotification(for: task)
        await loadTasks()
    }

    private func scheduleLocalNotification(for task: ScheduledTask) {
        cancelLocalNotification(for: task)
        guard task.enabled else { return }
        let parts = task.time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }

        let center = UNUserNotificationCenter.current()
        let dayMap = ["sun":1,"mon":2,"tue":3,"wed":4,"thu":5,"fri":6,"sat":7]
        let days: [Int] = task.days.contains("*") || task.days.isEmpty
            ? [1,2,3,4,5,6,7]
            : task.days.compactMap { dayMap[$0.lowercased()] }

        for weekday in days {
            var components = DateComponents()
            components.hour = parts[0]
            components.minute = parts[1]
            components.weekday = weekday

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = "Nova"
            content.body = task.name
            content.sound = .default
            content.userInfo = ["taskId": task.id]

            let identifier = "\(task.id)-\(weekday)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func cancelLocalNotification(for task: ScheduledTask) {
        let ids = (1...7).map { "\(task.id)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Task Row
struct TaskRow: View {
    let task: ScheduledTask
    let onUpdate: (ScheduledTask) -> Void
    let onDelete: () -> Void

    @State private var enabled: Bool
    @State private var showEdit = false
    @State private var showDeleteAlert = false

    init(task: ScheduledTask, onUpdate: @escaping (ScheduledTask) -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _enabled = State(initialValue: task.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                if task.trusted {
                    Text("TRUSTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.2)))
                        .foregroundColor(.orange)
                }
                if isDevTask {
                    Text("DEV")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.2)))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
                if isWebTask {
                    Text("WEB")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.2)))
                        .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.45))
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, new in
                        var updated = task
                        updated.enabled = new
                        onUpdate(updated)
                    }
            }
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text(task.time)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text("·")
                    .opacity(0.3)
                Text(daysLabel)
                    .font(.system(size: 12, weight: .light))
            }
            .foregroundColor(Color(hex: "1a1a2e").opacity(0.5))

            Text(task.prompt)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(Color(hex: "1a1a2e").opacity(0.6))
                .lineLimit(2)

            HStack(spacing: 12) {
                Spacer()
                Button(action: { showEdit = true }) {
                    Label("Upravit", systemImage: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { showDeleteAlert = true }) {
                    Label("Smazat", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEdit) {
            EditTaskView(task: task) { updated in
                onUpdate(updated)
                showEdit = false
            }
        }
        .alert("Smazat úkol?", isPresented: $showDeleteAlert) {
            Button("Smazat", role: .destructive, action: onDelete)
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Úkol \"\(task.name)\" bude smazán.")
        }
    }

    private var daysLabel: String {
        if task.days.contains("*") || task.days.isEmpty { return "Každý den" }
        let map = ["mon":"Po","tue":"Út","wed":"St","thu":"Čt","fri":"Pá","sat":"So","sun":"Ne"]
        return task.days.compactMap { map[$0.lowercased()] }.joined(separator: ", ")
    }

    private var isDevTask: Bool {
        let p = task.prompt.lowercased()
        let devPatterns = [
            "soubor", "kód", "kod", "projekt", "adresář", "adresar", "složka", "slozka",
            "download", "desktop", "documents", "nova-ios", "fxlooper", "server.js",
            ".pages", ".numbers", ".keynote", ".docx", ".xlsx", ".csv", ".zip", ".log",
            ".txt", ".pdf", ".json", ".swift", ".js", ".py", ".md", ".html", ".xml",
            "přečti", "precti", "obsah", "dokument", "faktur", "git", "commit", "build",
        ]
        return devPatterns.contains { p.contains($0) }
    }

    private var isWebTask: Bool {
        let p = task.prompt.lowercased()
        let webPatterns = [
            "počasí", "pocasi", "zprávy", "zpravy", "novinky", "kurz", "kurzy",
            "euro", "dolar", "koruna", "wiki", "wikipedia", "nejbližší", "nejblizsi",
            "restaurace", "kavárna", "kavarna", "lékárna", "lekarna", "hotel",
            "kino", "cinema", "kalendář", "kalendar", "email pošl", "email posl",
            "pošli email", "posli email", "search", "vyhledej", "najdi na", "internet",
        ]
        return webPatterns.contains { p.contains($0) }
    }
}

// MARK: - Result Detail
struct ResultIdentifier: Identifiable {
    let id = UUID()
    let data: [String: Any]
}

struct ResultDetailView: View {
    let result: [String: Any]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let prompt = result["prompt"] as? String {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PROMPT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            Text(prompt)
                                .font(.system(size: 13, weight: .light, design: .rounded))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.65))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "1a1a2e").opacity(0.04))
                                .cornerRadius(10)
                        }
                    }

                    if let res = result["result"] as? String {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("VÝSLEDEK")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.4))
                            Text(res)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(hex: "1a1a2e").opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }

                    if let ts = result["timestamp"] as? String {
                        Text("Vykonáno: \(ts.prefix(19).replacingOccurrences(of: "T", with: " "))")
                            .font(.system(size: 11, weight: .light, design: .monospaced))
                            .foregroundColor(Color(hex: "1a1a2e").opacity(0.35))
                    }
                }
                .padding(20)
            }
            .navigationTitle(result["taskName"] as? String ?? "Výsledek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit Task Form
struct EditTaskView: View {
    let task: ScheduledTask
    let onSave: (ScheduledTask) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var time: Date
    @State private var prompt: String
    @State private var schedule: AddTaskView.ScheduleType
    @State private var customDays: Set<String>
    @State private var trusted: Bool

    init(task: ScheduledTask, onSave: @escaping (ScheduledTask) -> Void) {
        self.task = task
        self.onSave = onSave
        _name = State(initialValue: task.name)
        _prompt = State(initialValue: task.prompt)
        _trusted = State(initialValue: task.trusted)

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        _time = State(initialValue: formatter.date(from: task.time) ?? Date())

        let weekdays: Set<String> = ["mon","tue","wed","thu","fri"]
        let weekends: Set<String> = ["sat","sun"]
        let taskDays = Set(task.days)
        if task.days.contains("*") || task.days.isEmpty {
            _schedule = State(initialValue: .daily)
            _customDays = State(initialValue: [])
        } else if taskDays == weekdays {
            _schedule = State(initialValue: .weekdays)
            _customDays = State(initialValue: [])
        } else if taskDays == weekends {
            _schedule = State(initialValue: .weekends)
            _customDays = State(initialValue: [])
        } else {
            _schedule = State(initialValue: .custom)
            _customDays = State(initialValue: taskDays)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Název") { TextField("Název", text: $name) }
                Section("Čas") { DatePicker("Čas", selection: $time, displayedComponents: .hourAndMinute) }
                Section("Frekvence") {
                    Picker("", selection: $schedule) {
                        ForEach(AddTaskView.ScheduleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if schedule == .custom {
                        let allDays = [("mon","Po"),("tue","Út"),("wed","St"),("thu","Čt"),("fri","Pá"),("sat","So"),("sun","Ne")]
                        HStack(spacing: 6) {
                            ForEach(allDays, id: \.0) { day in
                                Button(day.1) {
                                    if customDays.contains(day.0) { customDays.remove(day.0) }
                                    else { customDays.insert(day.0) }
                                }
                                .buttonStyle(.bordered)
                                .tint(customDays.contains(day.0) ? .accentColor : .secondary)
                            }
                        }
                    }
                }
                Section("Co má Nova udělat") { TextEditor(text: $prompt).frame(minHeight: 80) }

                Section("Bezpečnost") {
                    Toggle("Povolit automatické akce", isOn: $trusted).tint(.orange)
                    if trusted {
                        Text("⚠️ Úkol bude automaticky odesílat emaily, číst soubory, měnit kód. Bez potvrzení.")
                            .font(.system(size: 11, weight: .light))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Upravit úkol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Zrušit") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Uložit") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm"
                        let timeStr = formatter.string(from: time)
                        let days: [String]
                        switch schedule {
                        case .daily: days = ["*"]
                        case .weekdays: days = ["mon","tue","wed","thu","fri"]
                        case .weekends: days = ["sat","sun"]
                        case .custom: days = Array(customDays)
                        }
                        var updated = task
                        updated.name = name; updated.time = timeStr; updated.days = days; updated.prompt = prompt; updated.trusted = trusted
                        onSave(updated)
                    }
                    .disabled(name.isEmpty || prompt.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Task Form
struct AddTaskView: View {
    let onSave: (ScheduledTask) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var time = Date()
    @State private var prompt = ""
    @State private var schedule: ScheduleType = .daily
    @State private var customDays: Set<String> = []
    @State private var trusted = false
    @State private var showTrustedAlert = false

    enum ScheduleType: String, CaseIterable {
        case daily = "Každý den"
        case weekdays = "Pracovní dny"
        case weekends = "Víkendy"
        case custom = "Vlastní"
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Název") {
                    TextField("Např. Ranní souhrn", text: $name)
                }

                Section("Čas") {
                    DatePicker("Čas", selection: $time, displayedComponents: .hourAndMinute)
                }

                Section("Frekvence") {
                    Picker("", selection: $schedule) {
                        ForEach(ScheduleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if schedule == .custom {
                        let allDays = [("mon","Po"),("tue","Út"),("wed","St"),("thu","Čt"),("fri","Pá"),("sat","So"),("sun","Ne")]
                        HStack(spacing: 6) {
                            ForEach(allDays, id: \.0) { day in
                                Button(day.1) {
                                    if customDays.contains(day.0) { customDays.remove(day.0) }
                                    else { customDays.insert(day.0) }
                                }
                                .buttonStyle(.bordered)
                                .tint(customDays.contains(day.0) ? .accentColor : .secondary)
                            }
                        }
                    }
                }

                Section("Co má Nova udělat") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 80)
                }

                Section {
                    Toggle("Povolit automatické akce", isOn: $trusted)
                        .tint(.orange)
                    if trusted {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Předschválené akce")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text("Úkol bude automaticky odesílat emaily, volat, přidávat do kalendáře nebo měnit soubory v projektech. Bez dalšího potvrzení. Zapni jen pokud víš co děláš.")
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Bezpečnost")
                }
            }
            .navigationTitle("Nový úkol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Uložit") {
                        if trusted {
                            showTrustedAlert = true
                        } else {
                            saveTask()
                        }
                    }
                    .disabled(name.isEmpty || prompt.isEmpty)
                }
            }
            .alert("Potvrdit automatické akce", isPresented: $showTrustedAlert) {
                Button("Povolit", role: .destructive) { saveTask() }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Úkol \"\(name)\" bude moci automaticky odesílat zprávy, emaily, přidávat do kalendáře a měnit soubory bez dalšího potvrzení. Chceš pokračovat?")
            }
        }
    }

    private func saveTask() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: time)
        let days: [String]
        switch schedule {
        case .daily: days = ["*"]
        case .weekdays: days = ["mon","tue","wed","thu","fri"]
        case .weekends: days = ["sat","sun"]
        case .custom: days = Array(customDays)
        }
        let task = ScheduledTask(
            id: UUID().uuidString, name: name, time: timeStr,
            days: days, prompt: prompt, enabled: true, trusted: trusted
        )
        onSave(task)
    }
}
