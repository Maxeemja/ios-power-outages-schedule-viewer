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
            var restored = saved
            if let firstSchedule = saved.schedules.first(where: { $0.id == "line-a" }) ?? saved.schedules.first {
                var schedule = firstSchedule
                schedule.displayLabel = "Графік 1"
                restored.schedules = [schedule]
                restored.selectedScheduleID = schedule.id
            }
            snapshot = restored
            if restored != saved {
                persistAndReload()
            }
        } else {
            snapshot = MockScheduleFactory.snapshot(now: .now, selectedScheduleID: snapshot.selectedScheduleID)
            persistAndReload()
        }
    }

    private func persistAndReload() {
        sharedStorageAvailable = store.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: OutageWidgetConstants.kind)
    }

    private var infoMessage: String {
        if sharedStorageAvailable == false {
            return "Спільне сховище недоступне. Перевірте App Group перед підписанням застосунку."
        }
        return "Розклад є демонстраційним і не показує фактичну наявність електроенергії."
    }
}
