import Foundation

/// View model for the Chat tab — manages threads and active conversation.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var threads: [ChatThread] = []
    @Published var activeMessages: [ChatMessage] = []
    @Published var activeThreadId: UUID?
    @Published var activeThreadTitle: String?
    @Published var loadState: ChatLoadState = .idle
    @Published var sendState: ChatSendState = .idle
    @Published var messageText: String = ""
    @Published var selectedInstance: UUID?

    private let api = APIService.shared

    enum ChatLoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    enum ChatSendState: Equatable {
        case idle
        case sending
        case error(String)
    }

    // MARK: - Thread List

    func loadThreads() async {
        loadState = .loading
        do {
            threads = try await api.fetchChatThreads(instanceId: selectedInstance)
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Thread Detail

    func loadThread(_ threadId: UUID) async {
        loadState = .loading
        activeThreadId = threadId
        do {
            let detail = try await api.fetchChatThread(threadId: threadId)
            activeMessages = detail.messages
            activeThreadTitle = detail.title
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard let instanceId = selectedInstance else {
            sendState = .error("No instance selected")
            return
        }

        sendState = .sending
        let threadId = activeThreadId

        do {
            let response = try await api.sendChatMessage(
                threadId: threadId,
                instanceId: instanceId,
                content: content
            )

            messageText = ""
            sendState = .idle

            // Update active thread
            activeThreadId = response.threadId
            activeMessages.append(response.userMessage)
            if let sysMsg = response.systemMessage {
                activeMessages.append(sysMsg)
            }

            // Update thread title if new
            if activeThreadTitle == nil {
                activeThreadTitle = String(content.prefix(100))
            }

            Haptics.success()
        } catch {
            sendState = .error(error.localizedDescription)
            Haptics.warning()
        }
    }

    // MARK: - New Thread

    func startNewThread() {
        activeThreadId = nil
        activeThreadTitle = nil
        activeMessages = []
        messageText = ""
        sendState = .idle
    }

    // MARK: - Approval Decisions

    func decideApproval(approvalId: UUID, decision: String) async {
        do {
            _ = try await api.decideApproval(approvalId: approvalId, decision: decision)

            if decision == "deny" {
                Haptics.destructive()
            } else {
                Haptics.warning()
            }

            // Refresh thread to show updated approval status
            if let threadId = activeThreadId {
                await loadThread(threadId)
            }
        } catch {
            sendState = .error(error.localizedDescription)
            Haptics.warning()
        }
    }

    // MARK: - Polling for Responses

    func pollForResponses() async {
        guard let threadId = activeThreadId else { return }
        do {
            let detail = try await api.fetchChatThread(threadId: threadId)
            // Only update if we have new messages
            if detail.messages.count > activeMessages.count {
                activeMessages = detail.messages
            }
        } catch {
            // Silent failure for polling
        }
    }
}
