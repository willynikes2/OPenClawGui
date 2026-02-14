import SwiftUI

/// Horizontal scrollable filter chip row used in Inbox and Security tabs.
struct FilterChipRow<T: Hashable & CustomStringConvertible>: View {
    let options: [T]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(options, id: \.self) { option in
                    FilterChip(
                        label: option.description,
                        isSelected: selection == option
                    ) {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = option
                        }
                    }
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }
}

/// Individual filter chip button.
struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(label)
    }
}
