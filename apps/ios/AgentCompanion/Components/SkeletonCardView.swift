import SwiftUI

/// Loading placeholder card with shimmer animation.
/// Respects the Reduce Motion accessibility setting.
struct SkeletonCardView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            // Icon placeholder
            skeletonRect(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: Space.sm) {
                // Title placeholder
                skeletonRect(width: 180, height: 14)

                // Subtitle placeholder
                skeletonRect(width: 240, height: 12)

                // Chips placeholder
                HStack(spacing: Space.xs) {
                    skeletonRect(width: 60, height: 18)
                        .clipShape(Capsule())
                    skeletonRect(width: 50, height: 18)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Time placeholder
            skeletonRect(width: 40, height: 12)
        }
        .cardStyle()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
        .accessibilityLabel(String(localized: "Loading"))
    }

    private func skeletonRect(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.4 : 1.0)
    }
}

/// Convenience view that shows multiple skeleton cards for loading states.
struct SkeletonCardList: View {
    var count: Int = 5

    var body: some View {
        VStack(spacing: Space.md) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCardView()
            }
        }
        .padding(.horizontal, Space.lg)
    }
}

#Preview {
    ScrollView {
        SkeletonCardList()
    }
}
