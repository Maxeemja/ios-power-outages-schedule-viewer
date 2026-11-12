import SwiftUI
import WidgetKit

enum OutageWidgetConstants {
    static let kind = "OutageScheduleWidget"
}

struct WidgetCard: View {
    let snapshot: ScheduleSnapshot
    let now: Date
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme

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
    private var primaryText: Color { colorScheme == .dark ? .white : Color(red: 0.08, green: 0.10, blue: 0.14) }
    private var secondaryText: Color { primaryText.opacity(colorScheme == .dark ? 0.66 : 0.62) }

    var body: some View {
        Group {
            if compact { smallLayout } else { mediumLayout }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.address.city)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                statusLabel
            }
            .foregroundStyle(primaryText)

            Text(snapshot.address.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .padding(.top, 2)

            Spacer(minLength: 8)

            if let transition {
                Text(transitionTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                Text(KyivTime.timeString(transition.date))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(primaryText)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(timerInterval: now...transition.date, countsDown: true)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusColor(transition.status))
                    .lineLimit(1)
            } else {
                Text(currentStatus == .unknown ? "Графік недоступний" : "Змін більше немає")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentStatus == .unknown ? freshnessText : "На сьогодні")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.address.city)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    Text(snapshot.address.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    statusLabel
                    Label(freshnessCaption, systemImage: "checkmark.circle")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transition.map { _ in transitionTitle } ?? (currentStatus == .unknown ? "Статус графіка" : "Наступна зміна"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                    if let transition {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(KyivTime.timeString(transition.date))
                                .font(.system(size: 25, weight: .semibold, design: .rounded))
                                .tracking(-0.8)
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(timerInterval: now...transition.date, countsDown: true)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(statusColor(transition.status))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text("Далі: \(transition.status.title.lowercased())")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    } else {
                        Text(currentStatus == .unknown ? "Немає актуального графіка" : "Змін більше немає")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }

            if schedule != nil {
                timeline
            } else {
                unavailableTimeline
            }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor(currentStatus)).frame(width: 7, height: 7)
            Text(currentStatus.shortTitle)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(statusColor(currentStatus))
        }
        .fixedSize()
    }

    private var timeline: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(schedule?.intervals ?? []) { item in
                            statusColor(item.status)
                                .frame(width: max(0, (geometry.size.width - CGFloat(max(0, (schedule?.intervals.count ?? 1) - 1))) * durationFraction(item)))
                        }
                    }
                    .clipShape(Capsule())

                    Capsule()
                        .fill(primaryText)
                        .frame(width: 2, height: 19)
                        .shadow(color: primaryText.opacity(0.4), radius: 2)
                        .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * timeFraction - 1)))
                }
            }
            .frame(height: 19)

            HStack(spacing: 0) {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { tick in
                    Text(tick)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: tick == "00" ? .leading : (tick == "24" ? .trailing : .center))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Графік на 24 години. Поточний статус: \(currentStatus.title)")
    }

    private var unavailableTimeline: some View {
        VStack(spacing: 5) {
            Capsule().fill(statusColor(.unknown).opacity(0.35)).frame(height: 7)
            Text(freshnessText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transitionTitle: String {
        switch currentStatus {
        case .outage: "Світло з’явиться"
        case .available: "Наступне відключення"
        case .possible: "Можлива зміна"
        case .unknown: "Наступна зміна"
        }
    }

    private var freshnessText: String {
        if snapshot.fetchedAt == .distantPast { return "Очікуємо на дані" }
        if schedule == nil {
            if snapshot.sourceKind == .userEntered, let verified = snapshot.lastVerifiedAt {
                return "Перевірте графік · остання перевірка о \(KyivTime.timeString(verified))"
            }
            return "Немає актуального графіка"
        }
        if snapshot.sourceKind == .userEntered, let verified = snapshot.lastVerifiedAt {
            return "Введено вручну · перевірено о \(KyivTime.timeString(verified))"
        }
        return "Демонстраційні дані"
    }

    private var freshnessCaption: String {
        guard snapshot.sourceKind == .userEntered, let verified = snapshot.lastVerifiedAt else {
            return "Демо · не реальний графік"
        }
        return "Перевірено \(KyivTime.timeString(verified))"
    }

    private var timeFraction: CGFloat {
        let day = KyivTime.dayStart(containing: now)
        let dayEnd = KyivTime.calendar().date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
        return CGFloat(min(1, max(0, now.timeIntervalSince(day) / dayEnd.timeIntervalSince(day))))
    }

    private func durationFraction(_ interval: ScheduleInterval) -> CGFloat {
        let day = KyivTime.dayStart(containing: interval.start)
        let dayEnd = KyivTime.calendar().date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
        return CGFloat(max(0, interval.end.timeIntervalSince(interval.start)) / dayEnd.timeIntervalSince(day))
    }

    private func statusColor(_ status: ScheduleStatus) -> Color {
        if colorScheme == .dark {
            switch status {
            case .available: Color(red: 0.32, green: 0.78, blue: 0.58)
            case .outage: Color(red: 0.91, green: 0.40, blue: 0.45)
            case .possible: Color(red: 0.98, green: 0.72, blue: 0.31)
            case .unknown: Color(red: 0.62, green: 0.66, blue: 0.74)
            }
        } else {
            switch status {
            case .available: Color(red: 0.10, green: 0.46, blue: 0.29)
            case .outage: Color(red: 0.70, green: 0.16, blue: 0.23)
            case .possible: Color(red: 0.55, green: 0.34, blue: 0.04)
            case .unknown: Color(red: 0.34, green: 0.38, blue: 0.46)
            }
        }
    }
}
