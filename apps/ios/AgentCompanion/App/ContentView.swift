import SwiftUI

/// Root view with 4-tab navigation per spec:
/// Inbox, Control, Security, Settings.
/// SF Symbols for tab icons, labels visible.
struct ContentView: View {
    @State private var selectedTab: Tab = .inbox

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxTab()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(Tab.inbox)

            ControlTab()
                .tabItem {
                    Label("Control", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.control)

            SecurityTab()
                .tabItem {
                    Label("Security", systemImage: "shield.fill")
                }
                .tag(Tab.security)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
    }
}

enum Tab: Hashable {
    case inbox, control, security, settings
}

// MARK: - Placeholder Tab Views

struct InboxTab: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "tray",
                title: "No Events Yet",
                description: "Once your Claw instance starts sending events, they will appear here.",
                actionTitle: "Send Test Event",
                action: {}
            )
            .navigationTitle("Inbox")
        }
    }
}

struct ControlTab: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "slider.horizontal.3",
                title: "Control Center",
                description: "Connect an instance to manage your agents.",
                actionTitle: "Add Instance",
                action: {}
            )
            .navigationTitle("Control")
        }
    }
}

struct SecurityTab: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "shield",
                title: "All Clear",
                description: "No security alerts. Your agents are behaving normally.",
                action: nil
            )
            .navigationTitle("Security")
        }
    }
}

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Label("Profile", systemImage: "person.crop.circle")
                    Label("Devices", systemImage: "iphone.gen3")
                }
                Section("Instances") {
                    Label("Manage Instances", systemImage: "server.rack")
                }
                Section("Privacy & Data") {
                    Label("Data Retention", systemImage: "clock.arrow.circlepath")
                    Label("Redaction Controls", systemImage: "eye.slash")
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }
                Section("Notifications") {
                    Label("Notification Settings", systemImage: "bell.badge")
                    Label("Quiet Hours", systemImage: "moon.fill")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
}
