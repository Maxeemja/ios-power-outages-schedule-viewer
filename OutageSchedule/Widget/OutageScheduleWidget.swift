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
        .padding(.horizontal, family == .systemSmall ? 12 : 16)
        .padding(.top, family == .systemSmall ? 10 : 16)
        .padding(.bottom, family == .systemSmall ? 10 : 4)
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

struct OutageScheduleWidget: Widget {
    static let kind = OutageWidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OutageTimelineProvider()) { entry in
            OutageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Графік світла")
        .description("Демонстраційний графік за адресою у Києві.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct OutageScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        OutageScheduleWidget()
    }
}
