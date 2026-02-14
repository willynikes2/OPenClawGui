import SwiftUI

/// Typography helpers that enforce Dynamic Type usage.
/// Never use fixed font sizes — always use these semantic styles.
enum Typography {
    /// Screen titles — maps to .title2
    static let title: Font = .title2
    /// Card headers, section headers — maps to .headline
    static let headline: Font = .headline
    /// Card subtext, secondary labels — maps to .subheadline
    static let subheadline: Font = .subheadline
    /// Body text — maps to .body
    static let body: Font = .body
    /// Metadata, timestamps — maps to .caption
    static let caption: Font = .caption
    /// Smallest metadata — maps to .caption2
    static let caption2: Font = .caption2
}

// MARK: - View Modifiers

extension View {
    func typographyTitle() -> some View {
        self.font(Typography.title)
    }

    func typographyHeadline() -> some View {
        self.font(Typography.headline)
    }

    func typographySubheadline() -> some View {
        self.font(Typography.subheadline)
    }

    func typographyBody() -> some View {
        self.font(Typography.body)
    }

    func typographyCaption() -> some View {
        self.font(Typography.caption)
            .foregroundStyle(.secondary)
    }

    func typographyCaption2() -> some View {
        self.font(Typography.caption2)
            .foregroundStyle(.tertiary)
    }
}
