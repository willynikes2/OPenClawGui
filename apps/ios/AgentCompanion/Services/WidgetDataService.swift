import Foundation
import WidgetKit

/// Writes data to the shared App Group container so the widget can display it.
/// Call `update()` after fetching fresh data from the API.
enum WidgetDataService {

    private static let suiteName = "group.com.agentcompanion.shared"

    /// Update the widget's shared data store with the latest values.
    /// Call from the main app after loading events, alerts, or instance status.
    static func update(
        alertCount: Int,
        lastEvent: (title: String, severity: String, time: Date)? = nil,
        instanceHealth: String = "unknown"
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        defaults.set(alertCount, forKey: "widget_alert_count")
        defaults.set(instanceHealth, forKey: "widget_instance_health")

        if let event = lastEvent {
            defaults.set(event.title, forKey: "widget_last_event_title")
            defaults.set(event.severity, forKey: "widget_last_event_severity")
            defaults.set(event.time.timeIntervalSince1970, forKey: "widget_last_event_time")
        }

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
}
