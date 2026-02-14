import SwiftUI

/// Step 1: Welcome screen with value props and CTA.
/// Large, calm layout. Value props: Monitor, Control, Secure, Read out loud.
struct WelcomeStepView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let valueProps: [(icon: String, title: LocalizedStringKey, description: LocalizedStringKey)] = [
        ("eye.fill", "Monitor", "See every agent output in a clean, searchable inbox."),
        ("slider.horizontal.3", "Control", "Start, stop, and pause agents remotely."),
        ("shield.fill", "Secure", "Detect suspicious behavior and contain threats instantly."),
        ("speaker.wave.2.fill", "Read Out Loud", "Listen to agent outputs with text-to-speech."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            Image(systemName: "pawprint.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: reduceMotion ? .nonRepeating : .default)
                .accessibilityHidden(true)
                .padding(.bottom, Space.xl)

            Text("AgentCompanion")
                .font(Typography.title)
                .fontWeight(.bold)
                .padding(.bottom, Space.xs)

            Text("Your AI agents, at your fingertips.")
                .font(Typography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, Space.xxl)

            // Value props
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(valueProps, id: \.icon) { prop in
                    HStack(spacing: Space.md) {
                        Image(systemName: prop.icon)
                            .font(Typography.body)
                            .foregroundStyle(.tint)
                            .frame(width: 28, alignment: .center)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(prop.title)
                                .font(Typography.headline)
                            Text(prop.description)
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)

            Spacer()
            Spacer()

            // CTA
            Button(action: onContinue) {
                Text("Add Your Claw Instance")
                    .font(Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.md)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxl)
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeStepView(onContinue: {})
    }
}
