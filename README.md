# Kyiv Outage Schedule

Native SwiftUI app and WidgetKit extension displaying Kyiv electricity schedules.

## Project setup

- Open OutageSchedule.xcodeproj in Xcode.
- The app and widget share a versioned JSON snapshot through an App Group.
- Before signing on a developer team, replace group.com.example.OutageSchedule in both entitlement files and ScheduleStore.appGroupIdentifier with an App Group registered to that team. The bundle identifiers use com.example placeholders as well.
- The app can load YASNO planned outages for a selected Kyiv group and subgroup; these are group schedules, not address-specific schedules. A manually entered schedule remains available when automatic data is unavailable.
- The manual schedule and YASNO group snapshots are stored separately in the App Group. The widget reads saved snapshots locally and does not make network requests.

The widget supports Small and Medium families. WidgetKit controls actual refresh timing, so the current-time marker can update later than its requested timeline cadence.
