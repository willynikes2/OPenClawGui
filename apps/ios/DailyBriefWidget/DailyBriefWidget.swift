import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DailyBriefEntry: TimelineEntry {
    let date: Date
    let alertCount: Int
    let lastEventTitle: String?
    let lastEventSeverity: String?
    let lastEventTime: Date?
    let instanceHealth: String

    static let placeholder = DailyBriefEntry(
        date: .now,
        alertCount: 0,
        lastEventTitle: "Daily Summary Generated",
        lastEventSeverity: "info",
        lastEventTime: Date().addingTimeInterval(-3600),
        instanceHealth: "ok"
    )

    static let empty = DailyBriefEntry(
        date: .now,
        alertCount: 0,
        lastEventTitle: nil,
        lastEventSeverity: nil,
        lastEventTime: nil,
        instanceHealth: "unknown"
    )
}

// MARK: - Timeline Provider

struct DailyBriefProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyBriefEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyBriefEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyBriefEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> DailyBriefEntry {
        let defaults = UserDefaults(suiteName: "group.com.agentcompanion.shared")

        let alertCount = defaults?.integer(forKey: "widget_alert_count") ?? 0
        let lastTitle = defaults?.string(forKey: "widget_last_event_title")
        let lastSeverity = defaults?.string(forKey: "widget_last_event_severity")
        let lastTimeInterval = defaults?.double(forKey: "widget_last_event_time")
        let health = defaults?.string(forKey: "widget_instance_health") ?? "unknown"

        let lastTime: Date? = lastTimeInterval.map { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? nil

        return DailyBriefEntry(
            date: .now,
            alertCount: alertCount,
            lastEventTitle: lastTitle,
            lastEventSeverity: lastSeverity,
            lastEventTime: lastTime,
            instanceHealth: health
        )
    }
}

// MARK: - Widget Views

struct DailyBriefWidgetEntryView: View {
    var entry: DailyBriefEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    // MARK: Small Widget

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Daily Brief")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Alert count
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.alertCount)")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(entry.alertCount > 0 ? .orange : .primary)
                    .monospacedDigit()

                Text("alerts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Health status
            HStack(spacing: 4) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 6, height: 6)
                Text(healthLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Medium Widget

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            // Left: alert count + health
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Daily Brief")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.alertCount)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(entry.alertCount > 0 ? .orange : .primary)
                        .monospacedDigit()

                    Text("alerts today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 6, height: 6)
                    Text(healthLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Right: last event
            VStack(alignment: .leading, spacing: 6) {
                Text("Last Event")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                if let title = entry.lastEventTitle {
                    HStack(spacing: 4) {
                        Image(systemName: severityIcon)
                            .font(.caption)
                            .foregroundStyle(severityColor)

                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }

                    if let time = entry.lastEventTime {
                        Text(time, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Helpers

    private var healthColor: Color {
        switch entry.instanceHealth {
        case "ok": .green
        case "degraded": .orange
        case "offline": .red
        default: .gray
        }
    }

    private var healthLabel: String {
        switch entry.instanceHealth {
        case "ok": "Healthy"
        case "degraded": "Degraded"
        case "offline": "Offline"
        default: "Unknown"
        }
    }

    private var severityIcon: String {
        switch entry.lastEventSeverity {
        case "critical": "exclamationmark.shield.fill"
        case "warn": "exclamationmark.triangle.fill"
        default: "bolt.fill"
        }
    }

    private var severityColor: Color {
        switch entry.lastEventSeverity {
        case "critical": .red
        case "warn": .orange
        default: .blue
        }
    }
}

// MARK: - Widget Configuration

struct DailyBriefWidget: Widget {
    let kind: String = "DailyBriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyBriefProvider()) { entry in
            DailyBriefWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Brief")
        .description("Today's alert count, instance health, and last event at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct DailyBriefWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyBriefWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DailyBriefWidget()
} timeline: {
    DailyBriefEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    DailyBriefWidget()
} timeline: {
    DailyBriefEntry.placeholder
}
