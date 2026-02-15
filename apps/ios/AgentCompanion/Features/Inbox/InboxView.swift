import SwiftUI

/// Inbox feed — "Mail + Notifications for agents".
///
/// Layout per spec 4.2:
/// - Top: Instance selector pill (left), Search button (right)
/// - Below: Filter chips row (horizontal scroll)
/// - Main: Event card list (infinite scroll), pull to refresh
/// - "New items" floating pill if user scrolled
/// - Empty state with CTA
struct InboxView: View {
    @StateObject private var viewModel = InboxViewModel()
    @State private var isSearching = false
    @State private var scrolledPastTop = false
    @Namespace private var topAnchor

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    offlineBanner
                    mainContent
                }
                newItemsPill
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InstancePicker(
                        selectedInstance: $viewModel.selectedInstance,
                        instances: viewModel.instances
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { isSearching.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(String(localized: "Search events"))
                }
            }
            .task {
                await viewModel.loadInitial()
            }
            .onChange(of: viewModel.selectedInstance) { _, _ in
                Task { await viewModel.selectInstance(viewModel.selectedInstance) }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            VStack(spacing: 0) {
                filterBar
                SkeletonCardList()
                    .padding(.top, Space.md)
            }

        case .error(let message):
            VStack(spacing: 0) {
                filterBar
                EmptyStateView(
                    icon: "exclamationmark.icloud",
                    title: "Something Went Wrong",
                    description: LocalizedStringKey(message),
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadInitial() }
                }
            }

        case .loaded, .loadingMore:
            if viewModel.filteredEvents.isEmpty && viewModel.searchText.isEmpty && viewModel.events.isEmpty {
                VStack(spacing: 0) {
                    filterBar
                    EmptyStateView(
                        icon: "tray",
                        title: "No Events Yet",
                        description: "Once your Claw instance starts sending events, they will appear here.",
                        actionTitle: "Send Test Event",
                        action: {}
                    )
                }
            } else if viewModel.filteredEvents.isEmpty && !viewModel.searchText.isEmpty {
                VStack(spacing: 0) {
                    filterBar
                    searchBar
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        description: "Try a different search term or filter."
                    )
                }
            } else {
                eventList
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        FilterChipRow(
            options: InboxFilter.allCases,
            selection: Binding(
                get: { viewModel.selectedFilter },
                set: { newFilter in
                    Task { await viewModel.applyFilter(newFilter) }
                }
            )
        )
        .padding(.vertical, Space.sm)
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        if isSearching {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "Search events..."),
                    text: $viewModel.searchText
                )
                .textFieldStyle(.plain)
                .font(Typography.body)
                .autocorrectionDisabled()

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel(String(localized: "Clear search"))
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Event List

    private var eventList: some View {
        ScrollViewReader { proxy in
            List {
                // Invisible anchor for scroll-to-top
                Color.clear
                    .frame(height: 0)
                    .id("top")
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())

                // Filter + search
                Section {
                    filterBar
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                    searchBar
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                // Events
                ForEach(viewModel.filteredEvents) { event in
                    NavigationLink(value: event) {
                        AgentCardView(
                            icon: iconForEvent(event),
                            title: event.title,
                            subtitle: subtitleForEvent(event),
                            severity: event.severity,
                            timestamp: event.timestamp,
                            skillName: event.skillName,
                            agentName: event.agentName,
                            isUnread: !event.isRead,
                            tags: event.tags
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Space.xs,
                        leading: Space.lg,
                        bottom: Space.xs,
                        trailing: Space.lg
                    ))
                    .task {
                        await viewModel.loadMoreIfNeeded(currentEvent: event)
                    }
                }

                // Loading more indicator
                if viewModel.loadState == .loadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .padding(.vertical, Space.md)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }
            .navigationDestination(for: AgentEvent.self) { event in
                EventDetailView(event: event)
            }
            .onChange(of: viewModel.hasNewItems) { _, hasNew in
                if !hasNew {
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - New Items Pill

    @ViewBuilder
    private var newItemsPill: some View {
        if viewModel.hasNewItems {
            Button {
                viewModel.scrolledToTop()
            } label: {
                Label("New Events", systemImage: "arrow.up")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .elevation(Elevation.floating)
            }
            .padding(.top, Space.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: viewModel.hasNewItems)
            .accessibilityLabel(String(localized: "Scroll to new events"))
        }
    }

    // MARK: - Offline Banner

    @ViewBuilder
    private var offlineBanner: some View {
        if viewModel.isOffline {
            HStack(spacing: Space.sm) {
                Image(systemName: "wifi.slash")
                    .font(Typography.caption)
                Text("Offline — showing cached data")
                    .font(Typography.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
            .background(Color.orange)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "You are offline. Showing cached data."))
        }
    }

    // MARK: - Helpers

    private func iconForEvent(_ event: AgentEvent) -> String {
        if event.bodyStructuredJSON != nil {
            return "doc.richtext"
        }
        switch event.severity {
        case .critical: return "exclamationmark.shield.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "bolt.fill"
        }
    }

    private func subtitleForEvent(_ event: AgentEvent) -> String {
        if let structured = event.bodyStructuredJSON,
           let summary = structured["summary"]?.value as? String {
            return summary
        }
        return event.bodyRaw ?? "\(event.skillName) — \(event.sourceType.rawValue)"
    }
}

#Preview {
    InboxView()
}
