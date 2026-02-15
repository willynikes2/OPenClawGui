import SwiftUI

/// Chat thread view — displays messages and input bar.
///
/// Layout:
/// - Messages list: scrollable, newest at bottom
/// - Each message: bubble with sender icon, content, timestamp
/// - Bottom: text input bar with send button
/// - Polls for new responses every 5 seconds while active
struct ChatThreadView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .navigationTitle(viewModel.activeThreadTitle ?? "New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Poll for agent responses every 5 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await viewModel.pollForResponses()
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.sm) {
                    ForEach(viewModel.activeMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.sendState == .sending {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Routing...")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Space.sm)
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
            }
            .onChange(of: viewModel.activeMessages.count) { _, _ in
                if let lastId = viewModel.activeMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            if case .error(let msg) = viewModel.sendState {
                Text(msg)
                    .font(Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.xs)
            }

            HStack(alignment: .bottom, spacing: Space.sm) {
                TextField(
                    String(localized: "Message your assistant..."),
                    text: $viewModel.messageText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(Typography.body)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))

                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSend)
                .accessibilityLabel(String(localized: "Send message"))
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.sendState != .sending
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            if message.senderType == .user {
                Spacer(minLength: Space.xxl)
            }

            if message.senderType != .user {
                senderAvatar
            }

            VStack(alignment: message.senderType == .user ? .trailing : .leading, spacing: Space.xs) {
                bubbleContent

                Text(message.createdAt, style: .time)
                    .font(Typography.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.senderType == .user {
                senderAvatar
            }

            if message.senderType != .user {
                Spacer(minLength: Space.xxl)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var senderAvatar: some View {
        Image(systemName: avatarIcon)
            .font(Typography.caption)
            .foregroundStyle(avatarColor)
            .frame(width: 24, height: 24)
            .background(avatarColor.opacity(0.12))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.messageType == .systemMessage {
            systemBubble
        } else if let structured = message.structuredJson, !structured.isEmpty {
            structuredBubble(structured)
        } else {
            textBubble
        }
    }

    private var textBubble: some View {
        Text(message.content ?? "")
            .font(Typography.body)
            .foregroundStyle(message.senderType == .user ? .white : .primary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
    }

    private var systemBubble: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "arrow.triangle.branch")
                .font(Typography.caption)
            Text(message.content ?? "")
                .font(Typography.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background(Color(.systemFill))
        .clipShape(Capsule())
    }

    private func structuredBubble(_ data: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let content = message.content {
                Text(content)
                    .font(Typography.body)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(data.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top) {
                        Text(key)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(String(describing: data[key]?.value ?? ""))
                            .font(Typography.caption)
                    }
                }
            }
            .padding(Space.sm)
            .background(Color(.systemFill))
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radii.button))
    }

    private var bubbleBackground: Color {
        switch message.senderType {
        case .user:
            return Color.accentColor
        case .agent, .assistant:
            return Color(.secondarySystemGroupedBackground)
        case .system:
            return Color(.systemFill)
        }
    }

    private var avatarIcon: String {
        switch message.senderType {
        case .user: return "person.fill"
        case .agent: return "cpu"
        case .assistant: return "sparkles"
        case .system: return "gear"
        }
    }

    private var avatarColor: Color {
        switch message.senderType {
        case .user: return .accentColor
        case .agent: return .green
        case .assistant: return .purple
        case .system: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        ChatThreadView(viewModel: ChatViewModel())
    }
}
