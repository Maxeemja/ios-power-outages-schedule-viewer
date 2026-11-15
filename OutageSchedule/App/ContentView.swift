import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var snapshot: ScheduleSnapshot?
    @State private var yasnoSnapshot: ScheduleSnapshot?
    @State private var mode: DisplayScheduleMode = .manual
    @State private var availableGroups: [String] = []
    @State private var selectedGroup = ""
    @State private var isRefreshing = false
    @State private var yasnoMessage: String?
    @State private var sharedStorageAvailable: Bool?
    @State private var showingEditor = false
    @State private var confirmingVerification = false
    @State private var storageError = false
    private let store = ScheduleStore()

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode == .manual ? "Мій графік" : "Графік YASNO")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(mode == .manual ? "Ручні дані · Київ" : "Груповий графік · Київ")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Picker("Джерело графіка", selection: $mode) {
                        Text("Вручну").tag(DisplayScheduleMode.manual)
                        Text("YASNO").tag(DisplayScheduleMode.yasno)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, newMode in
                        store.activeMode = newMode
                        WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
                        if newMode == .yasno { Task { await loadGroups() } }
                    }

                    if mode == .manual, let snapshot {
                        configuredSchedule(snapshot)
                    } else if mode == .manual {
                        emptyState
                    } else {
                        yasnoScheduleView
                    }

                    if sharedStorageAvailable == false || storageError {
                        Label(
                            "Не вдалося зберегти графік у спільному сховищі. Перевірте App Group.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }

                    if mode == .manual {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.mint)
                        Text("Графік введено вручну й він не оновлюється автоматично. Він показує лише запланований стан, а не фактичну наявність електроенергії.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: restore)
        .sheet(isPresented: $showingEditor) {
            ManualScheduleEditor(snapshot: snapshot) { updated in
                save(updated)
            }
        }
        .confirmationDialog("Ви щойно перевірили цей графік в офіційному джерелі?", isPresented: $confirmingVerification, titleVisibility: .visible) {
            Button("Так, позначити перевіреним") { markVerified() }
            Button("Скасувати", role: .cancel) { }
        } message: {
            Text("Час перевірки оновиться, і графік буде актуальним ще дві години.")
        }
    }

    private var yasnoScheduleView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Оберіть групу безпосередньо зі списку, отриманого від YASNO.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            if availableGroups.isEmpty {
                Button("Завантажити доступні групи") { Task { await loadGroups() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
            } else {
                Picker("Група", selection: $selectedGroup) {
                    Text("Виберіть групу").tag("")
                    ForEach(availableGroups, id: \.self) { group in Text(group).tag(group) }
                }
                .onChange(of: selectedGroup) { _, value in
                    guard !value.isEmpty else { return }
                    store.selectedYasnoGroup = value
                    yasnoSnapshot = displayedYasnoSnapshot(groupID: value)
                    WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
                }
                Button {
                    Task { await refreshYasno() }
                } label: {
                    Label(isRefreshing ? "Оновлення…" : "Оновити графік", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(.mint).disabled(isRefreshing || selectedGroup.isEmpty)
            }
            if let yasnoMessage {
                Text(yasnoMessage).font(.footnote).foregroundStyle(.orange)
            }
            if let yasnoSnapshot {
                WidgetCard(snapshot: yasnoSnapshot, now: .now, compact: false).frame(height: 225)
                Text("Група \(yasnoSnapshot.groupIdentity?.identifier ?? "—")")
                    .font(.headline).foregroundStyle(.white)
                if selectedGroup.isEmpty {
                    Text("Показано останній збережений графік цієї групи; виберіть доступну групу для наступного оновлення.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text(yasnoFreshnessLabel(yasnoSnapshot))
                    .font(.footnote)
                    .foregroundStyle(yasnoSnapshot.providerFreshness(at: .now) == .current ? .mint : .orange)
            } else if !selectedGroup.isEmpty, let waiting = store.loadYasnoWaiting(groupID: selectedGroup) {
                Text("YASNO ще не опублікував графік для групи \(selectedGroup). Перевірено о \(KyivTime.timeString(waiting.fetchedAt)).")
                    .font(.subheadline).foregroundStyle(.orange)
            } else {
                Text("Немає збереженого графіка для вибраної групи.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.68))
            }
            Text("Group schedule; actual outages at your building or apartment may differ.")
                .font(.footnote).foregroundStyle(.white.opacity(0.68))
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    @MainActor private func loadGroups() async {
        do {
            let groups = try await YasnoScheduleSource().fetchAvailableGroupIDs()
            availableGroups = groups
            if let saved = store.selectedYasnoGroup {
                selectedGroup = groups.contains(saved) ? saved : ""
                if !groups.contains(saved) {
                    yasnoMessage = "Обрану раніше групу більше не надано. Виберіть доступну групу вручну."
                }
            } else {
                selectedGroup = ""
            }
        } catch {
            yasnoMessage = "Не вдалося завантажити групи. Перевірте з’єднання та спробуйте ще раз."
        }
    }

    @MainActor private func refreshYasno() async {
        guard availableGroups.contains(selectedGroup) else {
            yasnoMessage = "Вибрана група відсутня у відповіді YASNO."
            return
        }
        isRefreshing = true
        store.selectedYasnoGroup = selectedGroup
        defer { isRefreshing = false }
        do {
            switch try await YasnoScheduleSource().fetchSchedule(groupID: selectedGroup, fetchedAt: .now) {
            case let .schedule(updated):
                guard store.saveYasno(updated) else { throw YasnoScheduleError.invalidResponse }
                yasnoSnapshot = updated
                yasnoMessage = nil
                WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
            case let .waiting(groupID, updatedOn):
                guard store.saveYasnoWaiting(groupID: groupID, updatedOn: updatedOn, fetchedAt: .now) else {
                    throw YasnoScheduleError.invalidResponse
                }
                WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
                yasnoMessage = "YASNO ще не опублікував графік для цієї групи. Збережений графік не змінено."
            }
        } catch YasnoScheduleError.stale(.staleWithStrongWarning) {
            yasnoMessage = "Дані YASNO застаріли понад 12 годин. Збережений графік не змінено."
        } catch YasnoScheduleError.stale(_) {
            yasnoMessage = "Дані YASNO застарілі. Збережений графік не змінено."
        } catch {
            yasnoMessage = "Не вдалося оновити графік. Показуємо останні збережені дані."
        }
    }

    private func yasnoFreshnessLabel(_ snapshot: ScheduleSnapshot) -> String {
        if let waitingAt = snapshot.providerWaitingFetchedAt, waitingAt > snapshot.fetchedAt {
            return "YASNO ще не опублікував графік після останнього оновлення."
        }
        guard let updatedOn = snapshot.sourceUpdatedOn else { return "Немає часу оновлення від провайдера" }
        let time = KyivTime.timeString(updatedOn)
        switch snapshot.providerFreshness(at: .now) {
        case .current: return "Актуально · оновлено YASNO о \(time)"
        case .stale: return "Застаріло · дані YASNO о \(time)"
        case .staleWithStrongWarning: return "Сильно застаріло · дані YASNO о \(time)"
        case .unavailable: return "Немає даних про актуальність"
        case .invalidFutureTimestamp: return "Час оновлення YASNO некоректний"
        }
    }

    private func displayedYasnoSnapshot(groupID: String) -> ScheduleSnapshot? {
        guard var snapshot = store.loadYasno(groupID: groupID),
              let waiting = store.loadYasnoWaiting(groupID: groupID),
              waiting.fetchedAt > snapshot.fetchedAt else { return store.loadYasno(groupID: groupID) }
        snapshot.providerWaitingUpdatedOn = waiting.updatedOn
        snapshot.providerWaitingFetchedAt = waiting.fetchedAt
        return snapshot
    }

    @ViewBuilder
    private func configuredSchedule(_ snapshot: ScheduleSnapshot) -> some View {
        let preview = snapshot.isFreshManualSchedule(at: .now)
            && KyivTime.calendar().isDate(snapshot.scheduleDate, inSameDayAs: .now)
            ? snapshot
            : MockScheduleFactory.unavailableSnapshot(now: .now, basedOn: snapshot)

        VStack(alignment: .leading, spacing: 16) {
            WidgetCard(snapshot: preview, now: .now, compact: false)
                .frame(height: 225)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(snapshot.address?.city ?? "Київ"), \(snapshot.address?.displayName ?? "")")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(freshnessLabel(snapshot))
                    .font(.footnote)
                    .foregroundStyle(snapshot.isFreshManualSchedule(at: .now) ? .mint : .orange)
            }

            if snapshot.schedules.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Моя лінія")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Picker("Графік", selection: scheduleSelection(snapshot)) {
                        ForEach(snapshot.schedules) { schedule in
                            Text(schedule.displayLabel).tag(schedule.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.mint)
                }
            }

            Link(destination: URL(string: "https://www.dtek-kem.com.ua/ua/shutdowns")!) {
                Label("Перевірити графік у ДТЕК", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.mint)

            Button {
                confirmingVerification = true
            } label: {
                Label("Позначити як перевірений", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.white)

            Button {
                showingEditor = true
            } label: {
                Label("Редагувати графік", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
            }
            .foregroundStyle(.mint)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.mint)
            Text("Додайте власний графік")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Вкажіть адресу й внесіть повні інтервали на вибрану дату. Якщо для будинку є дві лінії, додайте обидва графіки та виберіть свій.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
            Link("Спершу перевірити графік у ДТЕК", destination: URL(string: "https://www.dtek-kem.com.ua/ua/shutdowns")!)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.mint)
            Button("Налаштувати графік") { showingEditor = true }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.mint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private func scheduleSelection(_ snapshot: ScheduleSnapshot) -> Binding<String> {
        Binding(
            get: { self.snapshot?.selectedScheduleID ?? snapshot.selectedScheduleID },
            set: { id in
                var updated = snapshot
                updated.selectedScheduleID = id
                updated.fetchedAt = .now
                _ = save(updated)
            }
        )
    }

    private func restore() {
        mode = store.activeMode
        snapshot = store.loadManual()
        selectedGroup = store.selectedYasnoGroup ?? ""
        yasnoSnapshot = displayedYasnoSnapshot(groupID: selectedGroup)
        sharedStorageAvailable = store.isSharedContainerAvailable
        if mode == .yasno { Task { await loadGroups() } }
    }

    private func save(_ updated: ScheduleSnapshot) -> Bool {
        guard store.save(updated) else {
            sharedStorageAvailable = false
            storageError = true
            return false
        }
        snapshot = updated
        sharedStorageAvailable = true
        storageError = false
        WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
        return true
    }

    private func markVerified() {
        guard var updated = snapshot else { return }
        updated.lastVerifiedAt = .now
        updated.fetchedAt = .now
        _ = save(updated)
    }

    private func freshnessLabel(_ snapshot: ScheduleSnapshot) -> String {
        let isToday = KyivTime.calendar().isDate(snapshot.scheduleDate, inSameDayAs: .now)
        let dateLabel: String
        if !isToday {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "uk_UA")
            formatter.timeZone = KyivTime.timeZone
            formatter.dateFormat = "d MMMM"
            dateLabel = "Графік на \(formatter.string(from: snapshot.scheduleDate))"
        } else {
            dateLabel = ""
        }
        guard let lastVerifiedAt = snapshot.lastVerifiedAt else {
            return isToday ? "Ще не перевірено" : "\(dateLabel) · ще не перевірено"
        }
        let time = KyivTime.timeString(lastVerifiedAt)
        if !isToday { return "\(dateLabel) · перевірено о \(time)" }
        return snapshot.isFreshManualSchedule(at: .now)
            ? "Перевірено сьогодні о \(time) · актуально 2 години"
            : "Застаріло · перевірено о \(time)"
    }
}

private struct ScheduleSegmentDraft: Identifiable {
    let id = UUID()
    var endMinute: Int
    var status: ScheduleStatus
}

private struct ScheduleDraft: Identifiable {
    var id: String
    var displayLabel: String
    var segments: [ScheduleSegmentDraft]
}

private struct ManualScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var street: String
    @State private var buildingNumber: String
    @State private var scheduleDate: Date
    @State private var schedules: [ScheduleDraft]
    @State private var selectedScheduleID: String
    @State private var sourceWasVerified = false
    @State private var validationMessage: String?
    @State private var storageError = false

    let onSave: (ScheduleSnapshot) -> Bool

    init(snapshot: ScheduleSnapshot?, onSave: @escaping (ScheduleSnapshot) -> Bool) {
        self.onSave = onSave
        _street = State(initialValue: snapshot?.address?.street ?? "")
        _buildingNumber = State(initialValue: snapshot?.address?.buildingNumber ?? "")
        _scheduleDate = State(initialValue: snapshot?.scheduleDate ?? KyivTime.dayStart(containing: .now))
        let initialSchedules = snapshot?.schedules.map(Self.makeDraft)
            ?? [ScheduleDraft(id: UUID().uuidString, displayLabel: "Графік 1", segments: [ScheduleSegmentDraft(endMinute: 1440, status: .unknown)])]
        _schedules = State(initialValue: initialSchedules)
        _selectedScheduleID = State(initialValue: snapshot?.selectedScheduleID ?? initialSchedules[0].id)
    }

    private var selectedIndex: Int {
        schedules.firstIndex(where: { $0.id == selectedScheduleID }) ?? 0
    }

    private var validationError: String? {
        guard KyivTime.dayStart(containing: scheduleDate) >= KyivTime.dayStart(containing: .now) else {
            return "Виберіть сьогоднішню або майбутню дату."
        }
        guard !street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !buildingNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Вкажіть вулицю та номер будинку в Києві."
        }
        guard !schedules.isEmpty else { return "Додайте щонайменше один графік." }
        guard schedules.contains(where: { $0.id == selectedScheduleID }) else { return "Виберіть графік вашої лінії." }
        for schedule in schedules {
            guard !schedule.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let last = schedule.segments.last, last.endMinute == 1440 else {
                return "Кожен графік має бути заповнений до 24:00."
            }
            var previousEnd = 0
            var previousDate = KyivTime.dayStart(containing: scheduleDate)
            for segment in schedule.segments {
                guard segment.endMinute > previousEnd else { return "Інтервали мають бути послідовними та не перекриватися." }
                guard segment.endMinute <= 1440, segment.status != .unknown else { return "Кожен інтервал має мати коректний час і відомий стан." }
                let boundary = KyivTime.date(on: scheduleDate, minuteOfDay: segment.endMinute)
                guard boundary > previousDate else { return "Один із вибраних часів не існує або збігається з іншим через перехід на літній час." }
                previousDate = boundary
                previousEnd = segment.endMinute
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Адреса") {
                    LabeledContent("Місто", value: "Київ")
                    TextField("Вулиця", text: $street)
                    TextField("Будинок", text: $buildingNumber)
                }

                Section("Дата графіка") {
                    DatePicker("Дійсний на", selection: $scheduleDate, in: KyivTime.dayStart(containing: .now)..., displayedComponents: .date)
                        .environment(\.timeZone, KyivTime.timeZone)
                }

                Section {
                    Picker("Графік", selection: $selectedScheduleID) {
                        ForEach(schedules) { schedule in
                            Text(schedule.displayLabel).tag(schedule.id)
                        }
                    }
                    if !schedules.isEmpty {
                        TextField("Назва графіка", text: $schedules[selectedIndex].displayLabel)
                        segmentEditor
                    }
                    Button { addSchedule() } label: {
                        Label("Додати графік / лінію", systemImage: "plus.circle")
                    }
                    .disabled(schedules.count >= 2)
                    if schedules.count > 1 {
                        Button("Видалити цей графік", role: .destructive) { removeSelectedSchedule() }
                    }
                } header: {
                    Text("Повний графік · оберіть лінію")
                } footer: {
                    Text("Інтервали автоматично йдуть один за одним від 00:00 до 24:00. Для кожного вкажіть стан за графіком.")
                }

                Section {
                    Link("Відкрити офіційну сторінку ДТЕК", destination: URL(string: "https://www.dtek-kem.com.ua/ua/shutdowns")!)
                    Toggle("Я перевірив графік у ДТЕК", isOn: $sourceWasVerified)
                } footer: {
                    Text("Застосунок не завантажує дані з ДТЕК. Позначайте перевірку лише після звірки з офіційною сторінкою. Адреса й графік зберігаються у спільному сховищі застосунку.")
                }

                if let message = validationMessage ?? validationError {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if storageError {
                    Section { Text("Не вдалося зберегти. Перевірте налаштування App Group і повторіть спробу.").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Налаштувати графік")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти", action: save)
                        .disabled(validationError != nil)
                }
            }
        }
    }

    @ViewBuilder
    private var segmentEditor: some View {
        let segments = schedules[selectedIndex].segments
        ForEach(segments.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Від \(Self.timeLabel(index == 0 ? 0 : segments[index - 1].endMinute))")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if index == segments.count - 1 {
                        Text("до 24:00").foregroundStyle(.secondary)
                    } else {
                        MinuteOfDayPicker(minute: $schedules[selectedIndex].segments[index].endMinute)
                    }
                }
                Picker("Стан", selection: $schedules[selectedIndex].segments[index].status) {
                    Text("Світло").tag(ScheduleStatus.available)
                    Text("Відключення").tag(ScheduleStatus.outage)
                    Text("Можливе").tag(ScheduleStatus.possible)
                }
                .pickerStyle(.segmented)
                if segments.count > 1 {
                    Button("Прибрати інтервал", role: .destructive) { removeSegment(at: index) }
                        .font(.caption)
                }
            }
            .padding(.vertical, 5)
        }
        Button { addSegment() } label: {
            Label("Додати інтервал", systemImage: "plus")
        }
        .disabled(schedules[selectedIndex].segments.last.map { $0.endMinute - (schedules[selectedIndex].segments.count > 1 ? schedules[selectedIndex].segments[schedules[selectedIndex].segments.count - 2].endMinute : 0) < 2 } ?? true)
    }

    private func addSegment() {
        let index = selectedIndex
        guard let last = schedules[index].segments.last else { return }
        let start = schedules[index].segments.count > 1 ? schedules[index].segments[schedules[index].segments.count - 2].endMinute : 0
        let midpoint = start + (last.endMinute - start) / 2
        guard midpoint > start, midpoint < last.endMinute else { return }
        let oldStatus = last.status
        schedules[index].segments[schedules[index].segments.count - 1].endMinute = midpoint
        let newStatus: ScheduleStatus = oldStatus == .outage ? .available : .outage
        schedules[index].segments.append(ScheduleSegmentDraft(endMinute: 1440, status: newStatus))
    }

    private func removeSegment(at index: Int) {
        guard schedules[selectedIndex].segments.count > 1 else { return }
        schedules[selectedIndex].segments.remove(at: index)
    }

    private func addSchedule() {
        guard schedules.count < 2 else { return }
        let schedule = ScheduleDraft(
            id: UUID().uuidString,
            displayLabel: "Графік 2",
            segments: [ScheduleSegmentDraft(endMinute: 1440, status: .unknown)]
        )
        schedules.append(schedule)
        selectedScheduleID = schedule.id
    }

    private func removeSelectedSchedule() {
        guard schedules.count > 1 else { return }
        schedules.remove(at: selectedIndex)
        selectedScheduleID = schedules[0].id
    }

    private func save() {
        guard validationError == nil else { return }
        let day = KyivTime.dayStart(containing: scheduleDate)
        let address = SelectedAddress(
            city: "Київ",
            street: street.trimmingCharacters(in: .whitespacesAndNewlines),
            buildingNumber: buildingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let savedSchedules = schedules.map { schedule in
            var startMinute = 0
            let intervals = schedule.segments.enumerated().map { index, segment -> ScheduleInterval in
                defer { startMinute = segment.endMinute }
                return ScheduleInterval(
                    id: "\(schedule.id)-\(index)",
                    start: KyivTime.date(on: day, minuteOfDay: startMinute),
                    end: KyivTime.date(on: day, minuteOfDay: segment.endMinute),
                    status: segment.status
                )
            }
            return AddressSchedule(id: schedule.id, displayLabel: schedule.displayLabel, intervals: intervals)
        }
        let now = Date.now
        let result = ScheduleSnapshot(
            schemaVersion: 1,
            address: address,
            schedules: savedSchedules,
            selectedScheduleID: selectedScheduleID,
            scheduleDate: day,
            fetchedAt: now,
            sourceKind: .userEntered,
            lastVerifiedAt: sourceWasVerified ? now : nil
        )
        if onSave(result) { dismiss() } else { storageError = true }
    }

    private static func makeDraft(from schedule: AddressSchedule) -> ScheduleDraft {
        let segments = schedule.intervals.map { interval in
            let endMinute: Int
            if interval.end > interval.start,
               KyivTime.calendar().isDate(interval.end, inSameDayAs: interval.start) == false,
               KyivTime.calendar().component(.hour, from: interval.end) == 0,
               KyivTime.calendar().component(.minute, from: interval.end) == 0 {
                endMinute = 1440
            } else {
                endMinute = KyivTime.calendar().component(.hour, from: interval.end) * 60
                    + KyivTime.calendar().component(.minute, from: interval.end)
            }
            return ScheduleSegmentDraft(endMinute: endMinute, status: interval.status)
        }
        return ScheduleDraft(id: schedule.id, displayLabel: schedule.displayLabel, segments: segments)
    }

    private static func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private struct MinuteOfDayPicker: View {
    @Binding var minute: Int

    private var hour: Binding<Int> {
        Binding(
            get: { minute / 60 },
            set: { minute = $0 == 24 ? 1439 : $0 * 60 + minute % 60 }
        )
    }
    private var minutePart: Binding<Int> {
        Binding(
            get: { minute % 60 },
            set: { minute = (minute / 60) * 60 + $0 }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Година", selection: hour) {
                ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 64, height: 84)
            Text(":")
            Picker("Хвилина", selection: minutePart) {
                ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 64, height: 84)
        }
        .onChange(of: minute) { _, value in
            if value >= 1440 { minute = 1439 }
        }
    }
}
