import SwiftUI
import WidgetKit

struct OutageWidgetEntryView: View {
    let entry: OutageWidgetEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetCard(
            snapshot: entry.snapshot,
            now: entry.date,
            compact: family == .systemSmall
        )
        .containerBackground(
            colorScheme == .dark
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 0.075, green: 0.085, blue: 0.12), Color(red: 0.025, green: 0.03, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                : AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 0.97, green: 0.975, blue: 0.99), Color(red: 0.89, green: 0.91, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )),
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
        .description("Ваш вручну внесений графік за адресою у Києві.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OutageScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        OutageScheduleWidget()
    }
}
