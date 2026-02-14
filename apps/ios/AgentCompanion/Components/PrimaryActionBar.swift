import SwiftUI

/// Sticky bottom bar for primary/destructive actions.
/// Each destructive action shows a confirmation sheet before executing.
struct PrimaryActionBar: View {
    let actions: [ActionItem]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: Space.md) {
                ForEach(actions) { action in
                    ActionButton(action: action)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(.bar)
        }
    }
}

/// A single action configuration for the action bar.
struct ActionItem: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let icon: String
    let role: ButtonRole?
    let confirmationMessage: LocalizedStringKey?
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        icon: String,
        role: ButtonRole? = nil,
        confirmationMessage: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.confirmationMessage = confirmationMessage
        self.action = action
    }
}

/// Individual action button with optional confirmation dialog.
private struct ActionButton: View {
    let action: ActionItem
    @State private var showConfirmation = false

    var body: some View {
        Button(role: action.role) {
            if action.confirmationMessage != nil {
                if action.role == .destructive {
                    Haptics.destructive()
                }
                showConfirmation = true
            } else {
                action.action()
            }
        } label: {
            Label(action.title, systemImage: action.icon)
                .font(Typography.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.sm)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .clipShape(RoundedRectangle(cornerRadius: Radii.button))
        .confirmationDialog(
            Text("Confirm Action", comment: "Action bar confirmation title"),
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(action.title, role: action.role) {
                action.action()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let message = action.confirmationMessage {
                Text(message)
            }
        }
        .accessibilityLabel(action.title)
    }
}

#Preview {
    VStack {
        Spacer()
        PrimaryActionBar(actions: [
            ActionItem(
                title: "Pause Instance",
                icon: "pause.circle.fill",
                confirmationMessage: "This will pause all event ingestion for this instance.",
                action: {}
            ),
            ActionItem(
                title: "Kill Switch",
                icon: "power",
                role: .destructive,
                confirmationMessage: "This will immediately revoke all tokens and stop all agent activity.",
                action: {}
            ),
        ])
    }
}
