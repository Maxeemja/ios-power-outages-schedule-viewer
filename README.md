# Kyiv Outage Schedule

Native SwiftUI app and WidgetKit extension displaying a demonstration electricity schedule for a Kyiv address.

## Project setup

- Open OutageSchedule.xcodeproj in Xcode.
- The app and widget share a versioned JSON snapshot through an App Group.
- Before signing on a developer team, replace group.com.example.OutageSchedule in both entitlement files and ScheduleStore.appGroupIdentifier with an App Group registered to that team. The bundle identifiers use com.example placeholders as well.
- The sample address and schedule intervals are mock data. No provider API or backend is connected.

The widget supports Small and Medium families. WidgetKit controls actual refresh timing, so the current-time marker can update later than its requested timeline cadence.
