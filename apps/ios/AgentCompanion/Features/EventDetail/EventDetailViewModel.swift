import AVFoundation
import Foundation
import SwiftUI

/// View model for the Event Detail screen.
/// Manages raw content loading, TTS playback, and actions.
@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var event: AgentEvent
    @Published var showRawOutput: Bool = false
    @Published var loadState: LoadState = .loaded
    @Published var isSpeaking: Bool = false
    @Published var isPinned: Bool = false
    @Published var alerts: [SecurityAlert] = []

    // Tag management
    @Published var showTagSheet: Bool = false
    @Published var newTag: String = ""

    private let api = APIService.shared
    private let synthesizer = AVSpeechSynthesizer()

    enum LoadState {
        case loaded, loadingRaw, errorRaw(String)
    }

    init(event: AgentEvent) {
        self.event = event
    }

    // MARK: - Load Full Detail (with decrypted body_raw)

    func loadDetail() async {
        guard event.bodyRaw == nil else { return }
        loadState = .loadingRaw

        do {
            let detail = try await api.fetchEventDetail(eventID: event.id)
            event.bodyRaw = detail.bodyRaw
            loadState = .loaded
        } catch {
            loadState = .errorRaw(error.localizedDescription)
        }
    }

    // MARK: - TTS Read Aloud

    func toggleReadAloud() {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }

        let textToSpeak = buildSpeechText()
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func buildSpeechText() -> String {
        var parts: [String] = []
        parts.append("\(event.severity.accessibilityLabel) event from \(event.skillName).")
        parts.append(event.title)

        if let structured = event.bodyStructuredJSON {
            for (key, value) in structured {
                parts.append("\(key): \(value.value)")
            }
        } else if let raw = event.bodyRaw {
            parts.append(raw)
        }

        return parts.joined(separator: ". ")
    }

    // MARK: - Actions

    func togglePin() {
        isPinned.toggle()
        Haptics.success()
    }

    func copyRawToClipboard() {
        if let raw = event.bodyRaw {
            UIPasteboard.general.string = raw
            Haptics.success()
        }
    }

    // MARK: - Rich Content

    var hasStructuredContent: Bool {
        event.bodyStructuredJSON != nil
    }

    var structuredEntries: [(key: String, value: String)] {
        guard let json = event.bodyStructuredJSON else { return [] }
        return json.map { (key: $0.key, value: String(describing: $0.value.value)) }
            .sorted { $0.key < $1.key }
    }
}
