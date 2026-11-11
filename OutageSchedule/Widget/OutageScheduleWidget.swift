import SwiftUI
import WidgetKit

struct OutageScheduleWidget: Widget {
    static let kind = "OutageScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OutageTimelineProvider()) { entry in
            OutageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Графік світла")
        .description("Демонстраційний графік за адресою у Києві.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OutageScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        OutageScheduleWidget()
    }
}
