import CoreData
import Foundation

/// CoreData managed object for cached events.
///
/// The CoreData model is defined programmatically to avoid .xcdatamodeld
/// dependency during initial scaffold. In an Xcode project, this would
/// be generated from the data model editor.
@objc(CachedEvent)
final class CachedEvent: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var instanceID: UUID
    @NSManaged var sourceType: String
    @NSManaged var agentName: String
    @NSManaged var skillName: String
    @NSManaged var timestamp: Date
    @NSManaged var title: String
    @NSManaged var bodyRaw: String?
    @NSManaged var bodyStructuredJSON: Data?   // JSON-encoded
    @NSManaged var tags: Data?                  // JSON-encoded [String]
    @NSManaged var severity: String
    @NSManaged var piiRedacted: Bool
    @NSManaged var createdAt: Date
    @NSManaged var isRead: Bool
    @NSManaged var cachedAt: Date
}

// MARK: - CoreData Model Definition

extension CachedEvent {

    static func entityDescription() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CachedEvent"
        entity.managedObjectClassName = NSStringFromClass(CachedEvent.self)

        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("instanceID", .UUIDAttributeType, optional: false),
            attribute("sourceType", .stringAttributeType, optional: false),
            attribute("agentName", .stringAttributeType, optional: false),
            attribute("skillName", .stringAttributeType, optional: false),
            attribute("timestamp", .dateAttributeType, optional: false),
            attribute("title", .stringAttributeType, optional: false),
            attribute("bodyRaw", .stringAttributeType, optional: true),
            attribute("bodyStructuredJSON", .binaryDataAttributeType, optional: true),
            attribute("tags", .binaryDataAttributeType, optional: true),
            attribute("severity", .stringAttributeType, optional: false),
            attribute("piiRedacted", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("isRead", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("cachedAt", .dateAttributeType, optional: false),
        ]

        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        if let defaultValue {
            attr.defaultValue = defaultValue
        }
        return attr
    }

    /// Create a managed object model programmatically.
    static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [CachedEvent.entityDescription()]
        return model
    }
}

// MARK: - Conversion to/from AgentEvent

extension CachedEvent {

    func toAgentEvent() -> AgentEvent {
        let decoder = JSONDecoder()

        var structuredJSON: [String: AnyCodable]? = nil
        if let data = bodyStructuredJSON {
            structuredJSON = try? decoder.decode([String: AnyCodable].self, from: data)
        }

        var tagArray: [String]? = nil
        if let data = tags {
            tagArray = try? decoder.decode([String].self, from: data)
        }

        var event = AgentEvent(
            id: id,
            instanceID: instanceID,
            sourceType: SourceType(rawValue: sourceType) ?? .skill,
            agentName: agentName,
            skillName: skillName,
            timestamp: timestamp,
            title: title,
            bodyStructuredJSON: structuredJSON,
            tags: tagArray,
            severity: Severity(rawValue: severity) ?? .info,
            piiRedacted: piiRedacted,
            createdAt: createdAt,
            bodyRaw: bodyRaw
        )
        event.isRead = isRead
        return event
    }

    func populate(from event: AgentEvent) {
        let encoder = JSONEncoder()

        id = event.id
        instanceID = event.instanceID
        sourceType = event.sourceType.rawValue
        agentName = event.agentName
        skillName = event.skillName
        timestamp = event.timestamp
        title = event.title
        bodyRaw = event.bodyRaw
        severity = event.severity.rawValue
        piiRedacted = event.piiRedacted
        createdAt = event.createdAt
        isRead = event.isRead
        cachedAt = Date()

        if let json = event.bodyStructuredJSON {
            bodyStructuredJSON = try? encoder.encode(json)
        }
        if let tags = event.tags {
            self.tags = try? encoder.encode(tags)
        }
    }
}
