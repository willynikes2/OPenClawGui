import Foundation
import SwiftUI

/// View model for the Inbox feed.
/// Manages pagination, filtering, pull-to-refresh, and new-item detection.
@MainActor
final class InboxViewModel: ObservableObject {

    // MARK: - Published State

    @Published var events: [AgentEvent] = []
    @Published var loadState: LoadState = .idle
    @Published var selectedFilter: InboxFilter = .all
    @Published var searchText: String = ""
    @Published var hasNewItems: Bool = false

    // Instance context
    @Published var instances: [Instance] = []
    @Published var selectedInstance: Instance?

    // MARK: - Private

    private var nextCursor: String?
    private var canLoadMore: Bool { nextCursor != nil }
    private let api = APIService.shared

    // MARK: - Load States

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case loadingMore
        case error(String)
    }

    // MARK: - Initial Load

    func loadInitial() async {
        guard loadState != .loading else { return }
        loadState = .loading

        do {
            let response = try await api.fetchEvents(
                instanceID: selectedInstance?.id,
                severity: selectedFilter.severity
            )
            events = response.events
            nextCursor = response.nextCursor
            loadState = events.isEmpty ? .loaded : .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Refresh (pull to refresh)

    func refresh() async {
        do {
            let response = try await api.fetchEvents(
                instanceID: selectedInstance?.id,
                severity: selectedFilter.severity
            )

            let newIDs = Set(response.events.map(\.id))
            let oldIDs = Set(events.map(\.id))
            if !newIDs.subtracting(oldIDs).isEmpty {
                hasNewItems = true
            }

            events = response.events
            nextCursor = response.nextCursor
            loadState = .loaded
        } catch {
            // Keep existing data on refresh failure
            loadState = .loaded
        }
    }

    // MARK: - Pagination (infinite scroll)

    func loadMoreIfNeeded(currentEvent: AgentEvent) async {
        guard canLoadMore,
              loadState != .loadingMore,
              let lastEvent = events.last,
              currentEvent.id == lastEvent.id
        else { return }

        loadState = .loadingMore

        do {
            let response = try await api.fetchEvents(
                instanceID: selectedInstance?.id,
                severity: selectedFilter.severity,
                cursor: nextCursor
            )
            events.append(contentsOf: response.events)
            nextCursor = response.nextCursor
            loadState = .loaded
        } catch {
            loadState = .loaded
        }
    }

    // MARK: - Filter Change

    func applyFilter(_ filter: InboxFilter) async {
        selectedFilter = filter
        nextCursor = nil
        await loadInitial()
    }

    // MARK: - Instance Change

    func selectInstance(_ instance: Instance?) async {
        selectedInstance = instance
        nextCursor = nil
        await loadInitial()
    }

    // MARK: - Scroll to New Items

    func scrolledToTop() {
        hasNewItems = false
    }

    // MARK: - Filtered Events (local search)

    var filteredEvents: [AgentEvent] {
        guard !searchText.isEmpty else { return events }
        let query = searchText.lowercased()
        return events.filter { event in
            event.title.lowercased().contains(query) ||
            event.skillName.lowercased().contains(query) ||
            event.agentName.lowercased().contains(query) ||
            (event.tags ?? []).contains(where: { $0.lowercased().contains(query) })
        }
    }
}

// MARK: - Filter Enum

enum InboxFilter: String, CaseIterable, CustomStringConvertible, Hashable {
    case all = "All"
    case critical = "Critical"
    case warnings = "Warnings"
    case summaries = "Summaries"
    case tasks = "Tasks"

    var description: String { rawValue }

    var severity: Severity? {
        switch self {
        case .all: nil
        case .critical: .critical
        case .warnings: .warn
        case .summaries: nil
        case .tasks: nil
        }
    }
}
