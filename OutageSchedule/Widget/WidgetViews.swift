import SwiftUI
import WidgetKit

struct OutageWidgetEntryView: View {
    let entry: OutageWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetCard(
            snapshot: entry.snapshot,
            now: entry.date,
            compact: family == .systemSmall
        )
        .containerBackground(
            LinearGradient(
                colors: [Color(red: 0.075, green: 0.085, blue: 0.12), Color(red: 0.025, green: 0.03, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }
}

struct WidgetCard: View {
    let snapshot: ScheduleSnapshot
    let now: Date
    let compact: Bool

    private var schedule: AddressSchedule? { snapshot.selectedSchedule }
    private var interval: ScheduleInterval? {
        guard let schedule else { return nil }
        return ScheduleCalculator.currentInterval(in: schedule, at: now)
    }
    private var transition: (date: Date, status: ScheduleStatus)? {
        guard let schedule else { return nil }
        return ScheduleCalculator.nextTransition(in: schedule, at: now)
    }
    private var currentStatus: ScheduleStatus { interval?.status ?? .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 0)
            statusBlock
            timeline
            footer
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 10 : 8)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.105, blue: 0.13), Color(red: 0.045, green: 0.05, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: compact ? 25 : 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 25 : 30, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(snapshot.address.city)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        statusLabel
                    }
                    Text(snapshot.address.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.white.opacity(0.62))
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.address.city)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Text(snapshot.address.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer(minLength: 2)
                    VStack(alignment: .trailing, spacing: 3) {
                        statusLabel
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                            Text(KyivTime.timeString(snapshot.fetchedAt))
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                    }
                }
            }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle().fill(color(for: currentStatus)).frame(width: 7, height: 7)
            Text(currentStatus.shortTitle)
                .font(.system(size: compact ? 10 : 12, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(color(for: currentStatus))
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Text(transitionTitle)
                .font(.system(size: compact ? 9 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
            if let transition {
                HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 8) {
                    Text(KyivTime.timeString(transition.date))
                        .font(.system(size: compact ? 26 : 34, weight: .semibold, design: .rounded))
                        .tracking(compact ? -1 : -1.5)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ScheduleCalculator.countdown(until: transition.date, from: now))
                        .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mint)
                        .lineLimit(1)
                }
                Text("Далі: \(transition.status.title.lowercased())")
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: compact ? 26 : 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Дані графіка обмежені")
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: compact ? 3 : 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(schedule?.intervals ?? []) { item in
                            color(for: item.status)
                                .frame(width: geometry.size.width * durationFraction(item))
                        }
                    }
                    .clipShape(Capsule())
                    Rectangle()
                        .fill(.white)
                        .frame(width: compact ? 2 : 2.5, height: compact ? 17 : 21)
                        .shadow(color: .white.opacity(0.7), radius: 4)
                        .offset(x: max(0, min(geometry.size.width - 2.5, geometry.size.width * timeFraction - 1)))
                }
            }
            .frame(height: compact ? 14 : 17)

            HStack {
                ForEach(compact ? ["00", "06", "12", "18", "24"] : ["00", "03", "06", "09", "12", "15", "18", "21", "24"], id: \.self) { tick in
                    Text(tick)
                        .font(.system(size: compact ? 7 : 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                    if tick != (compact ? "24" : "24") { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Графік на 24 години. Поточний статус: \(currentStatus.title)")
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise")
            Text(KyivTime.timeString(snapshot.fetchedAt))
            if let schedule {
                Spacer()
                Text(schedule.displayLabel)
                    .lineLimit(1)
            }
        }
        .font(.system(size: compact ? 8 : 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.44))
    }

    private var transitionTitle: String {
        switch currentStatus {
        case .outage: "Відновлення за графіком"
        case .available: "Наступна зміна за графіком"
        case .possible: "Можлива зміна за графіком"
        case .unknown: "Наступна зміна"
        }
    }

    private var timeFraction: CGFloat {
        let day = KyivTime.dayStart(containing: now)
        let elapsed = now.timeIntervalSince(day)
        return CGFloat(min(1, max(0, elapsed / (24 * 60 * 60))))
    }

    private func durationFraction(_ interval: ScheduleInterval) -> CGFloat {
        CGFloat(interval.end.timeIntervalSince(interval.start) / (24 * 60 * 60))
    }

    private func color(for status: ScheduleStatus) -> Color {
        switch status {
        case .available: Color(red: 0.32, green: 0.78, blue: 0.58)
        case .outage: Color(red: 0.88, green: 0.38, blue: 0.43)
        case .possible: Color(red: 0.93, green: 0.70, blue: 0.30)
        case .unknown: Color(red: 0.40, green: 0.43, blue: 0.50)
        }
    }
}
