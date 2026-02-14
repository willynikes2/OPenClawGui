import SwiftUI

/// Top pill showing current instance name + health status dot.
/// Tap opens a sheet with the full instance list.
struct InstancePicker: View {
    @Binding var selectedInstance: Instance?
    let instances: [Instance]
    var onManage: ((Instance) -> Void)? = nil

    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.selection()
            showSheet = true
        } label: {
            HStack(spacing: Space.sm) {
                if let instance = selectedInstance {
                    Circle()
                        .fill(instance.health.dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(instance.health.label)

                    Text(instance.name)
                        .font(Typography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("No Instance", comment: "Instance picker placeholder")
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .accessibilityLabel(String(localized: "Select instance"))
        .accessibilityHint(selectedInstance?.name ?? String(localized: "No instance selected"))
        .sheet(isPresented: $showSheet) {
            instanceListSheet
        }
    }

    private var instanceListSheet: some View {
        NavigationStack {
            List(instances) { instance in
                Button {
                    selectedInstance = instance
                    showSheet = false
                } label: {
                    instanceRow(instance)
                }
                .listRowInsets(EdgeInsets(
                    top: Space.md,
                    leading: Space.lg,
                    bottom: Space.md,
                    trailing: Space.lg
                ))
            }
            .navigationTitle(String(localized: "Instances"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        showSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func instanceRow(_ instance: Instance) -> some View {
        HStack(spacing: Space.md) {
            Circle()
                .fill(instance.health.dotColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(instance.name)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: Space.sm) {
                    Text(instance.health.label)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)

                    if let lastSeen = instance.lastSeen {
                        Text("Last seen \(lastSeen, style: .relative) ago")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if instance.id == selectedInstance?.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(String(localized: "Selected"))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(instance.name), \(instance.health.label)")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selected: Instance? = Instance(
            id: UUID(),
            name: "My Claw",
            mode: .active,
            health: .ok,
            lastSeen: Date().addingTimeInterval(-600),
            createdAt: Date()
        )

        var body: some View {
            InstancePicker(
                selectedInstance: $selected,
                instances: [
                    selected!,
                    Instance(
                        id: UUID(),
                        name: "Work Server",
                        mode: .paused,
                        health: .degraded,
                        lastSeen: Date().addingTimeInterval(-7200),
                        createdAt: Date()
                    ),
                ]
            )
        }
    }

    return PreviewWrapper()
        .padding()
}
