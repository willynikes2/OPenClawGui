import SwiftUI

/// Empty state view with SF Symbol illustration, title, description, and optional CTA.
/// Used when a list or section has no content yet — should teach the user what to expect.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                .accessibilityHidden(true)

            VStack(spacing: Space.sm) {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Typography.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateView(
        icon: "tray",
        title: "No Events Yet",
        description: "Once your Claw instance starts sending events, they will appear here.",
        actionTitle: "Send Test Event",
        action: {}
    )
}
