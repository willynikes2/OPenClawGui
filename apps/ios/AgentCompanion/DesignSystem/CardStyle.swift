import SwiftUI

/// Standard card container style matching the design system.
/// Uses thin material background, card corner radius, and subtle elevation.
struct CardStyle: ViewModifier {
    var isCritical: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(Space.lg)
            .background {
                RoundedRectangle(cornerRadius: Radii.card)
                    .fill(isCritical ? AppColors.criticalTint : AppColors.cardBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radii.card))
            .elevation(Elevation.card)
    }
}

extension View {
    func cardStyle(isCritical: Bool = false) -> some View {
        modifier(CardStyle(isCritical: isCritical))
    }
}
