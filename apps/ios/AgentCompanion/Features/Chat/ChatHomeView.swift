import SwiftUI

/// Chat tab home — shows thread list and new conversation entry.
///
/// Layout:
/// - Top bar: Instance picker (left), New Chat button (right)
/// - Thread list: sorted by most recent, shows title + last message preview
/// - Empty state when no threads exist
struct ChatHomeView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showThread = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    SkeletonCardList()

                case .error(let message):
                    EmptyStateView(
                        icon: "exclamationmark.icloud",
                        title: "Something Went Wrong",
                        description: LocalizedStringKey(message),
                        actionTitle: "Retry"
                    ) {
                        Task { await viewModel.loadThreads() }
                    }

                case .loaded:
                    if viewModel.threads.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "No Conversations",
                            description: "Start a conversation with your Claw assistant.",
                            actionTitle: "New Chat"
                        ) {
                            viewModel.startNewThread()
                            showThread = true
                        }
                    } else {
                        threadList
                    }
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InstancePicker(
                        selectedInstance: $viewModel.selectedInstance,
                        instances: []
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        viewModel.startNewThread()
                        showThread = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(String(localized: "New conversation"))
                }
            }
            .task {
                await viewModel.loadThreads()
            }
            .navigationDestination(isPresented: $showThread) {
                ChatThreadView(viewModel: viewModel)
            }
            .navigationDestination(for: ChatThread.self) { thread in
                ChatThreadView(viewModel: viewModel)
                    .task {
                        await viewModel.loadThread(thread.id)
                    }
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        List(viewModel.threads) { thread in
            NavigationLink(value: thread) {
                threadRow(thread)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Space.xs,
                leading: Space.lg,
                bottom: Space.xs,
                trailing: Space.lg
            ))
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadThreads()
        }
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(thread.title ?? "New Conversation")
                    .font(Typography.headline)
                    .lineLimit(1)

                Spacer()

                Text(thread.updatedAt, style: .relative)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastMsg = thread.lastMessage {
                HStack(spacing: Space.xs) {
                    senderIcon(lastMsg.senderType)
                        .foregroundStyle(.secondary)
                        .font(Typography.caption)

                    Text(lastMsg.content ?? "Structured response")
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .combine)
    }

    private func senderIcon(_ sender: ChatSenderType) -> Image {
        switch sender {
        case .user:
            return Image(systemName: "person.fill")
        case .agent:
            return Image(systemName: "cpu")
        case .assistant:
            return Image(systemName: "sparkles")
        case .system:
            return Image(systemName: "gear")
        }
    }
}

/// Skeleton placeholder while threads load.
private struct SkeletonCardList: View {
    var body: some View {
        List(0..<5, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Space.sm) {
                RoundedRectangle(cornerRadius: Radii.button)
                    .fill(Color(.systemFill))
                    .frame(height: 16)
                    .frame(maxWidth: 200)

                RoundedRectangle(cornerRadius: Radii.button)
                    .fill(Color(.systemFill))
                    .frame(height: 12)
                    .frame(maxWidth: 280)
            }
            .padding(.vertical, Space.sm)
            .listRowSeparator(.hidden)
            .redacted(reason: .placeholder)
        }
        .listStyle(.plain)
    }
}

#Preview {
    ChatHomeView()
}
