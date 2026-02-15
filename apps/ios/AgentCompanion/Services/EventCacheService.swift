import CoreData
import Foundation

/// Offline event cache backed by CoreData + SQLCipher.
///
/// Provides save, fetch, search, mark-read, and purge operations.
/// Used by InboxViewModel as a fallback when the network is unavailable,
/// and for offline-first reads with background refresh.
final class EventCacheService {
    static let shared = EventCacheService()

    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    // MARK: - Save

    /// Save or update events in the local cache.
    func cacheEvents(_ events: [AgentEvent]) {
        let context = persistence.newBackgroundContext()
        context.perform {
            for event in events {
                // Upsert: check if already exists
                let request = NSFetchRequest<CachedEvent>(entityName: "CachedEvent")
                request.predicate = NSPredicate(format: "id == %@", event.id as CVarArg)
                request.fetchLimit = 1

                let existing = try? context.fetch(request).first

                if let existing {
                    existing.populate(from: event)
                } else {
                    let cached = CachedEvent(context: context)
                    cached.populate(from: event)
                }
            }

            try? context.save()
        }
    }

    // MARK: - Fetch

    /// Fetch cached events with optional filters, sorted by createdAt descending.
    func fetchEvents(
        instanceID: UUID? = nil,
        severity: Severity? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) -> [AgentEvent] {
        let context = persistence.viewContext
        let request = NSFetchRequest<CachedEvent>(entityName: "CachedEvent")

        var predicates: [NSPredicate] = []
        if let instanceID {
            predicates.append(NSPredicate(format: "instanceID == %@", instanceID as CVarArg))
        }
        if let severity {
            predicates.append(NSPredicate(format: "severity == %@", severity.rawValue))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset

        do {
            let results = try context.fetch(request)
            return results.map { $0.toAgentEvent() }
        } catch {
            return []
        }
    }

    // MARK: - Search

    /// Basic text search across title, agent name, and skill name.
    func search(query: String, limit: Int = 50) -> [AgentEvent] {
        let context = persistence.viewContext
        let request = NSFetchRequest<CachedEvent>(entityName: "CachedEvent")

        request.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ OR agentName CONTAINS[cd] %@ OR skillName CONTAINS[cd] %@",
            query, query, query
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = limit

        do {
            let results = try context.fetch(request)
            return results.map { $0.toAgentEvent() }
        } catch {
            return []
        }
    }

    // MARK: - Mark Read

    func markAsRead(eventID: UUID) {
        let context = persistence.newBackgroundContext()
        context.perform {
            let request = NSFetchRequest<CachedEvent>(entityName: "CachedEvent")
            request.predicate = NSPredicate(format: "id == %@", eventID as CVarArg)
            request.fetchLimit = 1

            if let event = try? context.fetch(request).first {
                event.isRead = true
                try? context.save()
            }
        }
    }

    // MARK: - Purge by Retention

    /// Delete events older than the specified number of days.
    func purgeOlderThan(days: Int) {
        let context = persistence.newBackgroundContext()
        context.perform {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedEvent")
            request.predicate = NSPredicate(format: "createdAt < %@", cutoff as NSDate)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeCount

            do {
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let count = result?.result as? Int ?? 0
                if count > 0 {
                    // Merge changes into view context
                    try context.save()
                }
            } catch {
                // Log error
            }
        }
    }

    /// Delete all cached events.
    func purgeAll() {
        let context = persistence.newBackgroundContext()
        context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedEvent")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            _ = try? context.execute(deleteRequest)
            try? context.save()
        }
    }

    // MARK: - Cache Size

    /// Estimated size of the cached data in bytes.
    func estimatedCacheSize() -> Int {
        guard let storeURL = persistence.container.persistentStoreDescriptions.first?.url else {
            return 0
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            return (attributes[.size] as? Int) ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Event Count

    func eventCount() -> Int {
        let context = persistence.viewContext
        let request = NSFetchRequest<CachedEvent>(entityName: "CachedEvent")
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Export

    /// Export all cached events as a JSON file in the temp directory.
    func exportAsJSON() -> URL? {
        let events = fetchEvents(limit: 10000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(events) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("agentcompanion_events_\(Date().ISO8601Format()).json")

        do {
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}
