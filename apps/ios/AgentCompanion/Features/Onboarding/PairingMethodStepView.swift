import SwiftUI

/// Step 2: Pairing method selection.
/// Options: Scan QR, Paste Token, Use Telegram Bridge (fallback).
struct PairingMethodStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.bottom, Space.lg)

            Text("Connect Your Instance")
                .font(Typography.title)
                .fontWeight(.bold)
                .padding(.bottom, Space.xs)

            Text("Choose how to pair with your Claw deployment.")
                .font(Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.xxl)

            // Pairing options
            VStack(spacing: Space.md) {
                pairingOptionButton(
                    icon: "qrcode.viewfinder",
                    title: "Scan QR Code",
                    subtitle: "Scan the code shown in your Claw dashboard.",
                    method: .scanQR
                )

                pairingOptionButton(
                    icon: "doc.on.clipboard",
                    title: "Paste Token",
                    subtitle: "Paste an integration token from your instance settings.",
                    method: .pasteToken
                )

                pairingOptionButton(
                    icon: "paperplane",
                    title: "Use Telegram Bridge",
                    subtitle: "Connect via your existing Telegram bot (fallback).",
                    method: .telegramBridge
                )
            }
            .padding(.horizontal, Space.xl)

            // Token input field (shown when paste token selected)
            if viewModel.pairingMethod == .pasteToken {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Integration Token")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)

                    TextField(
                        String(localized: "Paste your token here"),
                        text: $viewModel.pasteToken
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
            Spacer()

            // Continue button
            Button(action: viewModel.advance) {
                Text("Continue")
                    .font(Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.md)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
            .disabled(viewModel.pairingMethod == nil)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.pairingMethod)
    }

    private func pairingOptionButton(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        method: PairingMethod
    ) -> some View {
        let isSelected = viewModel.pairingMethod == method

        return Button {
            Haptics.selection()
            viewModel.pairingMethod = method
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(Typography.headline)
                    .foregroundStyle(isSelected ? .white : .tint)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(Space.lg)
            .background(
                RoundedRectangle(cornerRadius: Radii.card)
                    .fill(isSelected ? Color.accentColor : AppColors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radii.card)
                    .strokeBorder(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        PairingMethodStepView(viewModel: OnboardingViewModel())
    }
}
