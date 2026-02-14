import SwiftUI

/// Root view with 4-tab navigation per spec:
/// Inbox, Control, Security, Settings.
/// SF Symbols for tab icons, labels visible.
/// Shows onboarding modal if user has not completed setup.
struct ContentView: View {
    @State private var selectedTab: Tab = .inbox
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(Tab.inbox)

            ControlView()
                .tabItem {
                    Label("Control", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.control)

            SecurityView()
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
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
                .onDisappear {
                    hasCompletedOnboarding = true
                }
        }
    }
}

enum Tab: Hashable {
    case inbox, control, security, settings
}

// MARK: - Settings Tab

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
