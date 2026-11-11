import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var snapshot = MockScheduleFactory.snapshot()
    @State private var sharedStorageAvailable: Bool?
    private let store = ScheduleStore()

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Графік електроенергії")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Демонстраційні дані · Київ")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    WidgetCard(snapshot: snapshot, now: .now, compact: false)
                        .frame(height: 235)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Варіант графіка")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Picker("Варіант графіка", selection: $snapshot.selectedScheduleID) {
                            ForEach(snapshot.schedules) { schedule in
                                Text(schedule.displayLabel).tag(schedule.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: snapshot.selectedScheduleID) {
                            persistAndReload()
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.mint)
                        Text(infoMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    Button {
                        snapshot = MockScheduleFactory.snapshot(now: .now, selectedScheduleID: snapshot.selectedScheduleID)
                        persistAndReload()
                    } label: {
                        Label("Оновити демо-дані", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .foregroundStyle(.white)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: restoreOrSeed)
    }

    private func restoreOrSeed() {
        let today = KyivTime.dayStart(containing: .now)
        if let saved = store.load(), saved.scheduleDate == today {
            snapshot = saved
        } else {
            snapshot = MockScheduleFactory.snapshot(now: .now, selectedScheduleID: snapshot.selectedScheduleID)
            persistAndReload()
        }
    }

    private func persistAndReload() {
        sharedStorageAvailable = store.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: OutageScheduleWidget.kind)
    }

    private var infoMessage: String {
        if sharedStorageAvailable == false {
            return "Спільне сховище недоступне. Перевірте App Group перед підписанням застосунку."
        }
        return "Розклад є демонстраційним і не показує фактичну наявність електроенергії."
    }
}
