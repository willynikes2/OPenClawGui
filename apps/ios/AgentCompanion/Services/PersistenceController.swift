import CoreData
import Foundation

/// CoreData persistence controller configured for SQLCipher-encrypted storage.
///
/// The store uses a passphrase stored in the Keychain. On first launch, a random
/// 32-byte passphrase is generated and persisted in the Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
///
/// In production, link against a SQLCipher-enabled SQLite build (e.g., via
/// the `SQLCipher` CocoaPod or SPM package). For MVP development without
/// SQLCipher linked, the store falls back to iOS Data Protection
/// (`NSFileProtectionComplete`).
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// In-memory store for previews and testing.
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()

    init(inMemory: Bool = false) {
        // Use programmatic model so no .xcdatamodeld file is required
        let model = CachedEvent.createManagedObjectModel()
        container = NSPersistentContainer(name: "AgentCompanion", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("No persistent store descriptions found")
            }

            // SQLCipher encryption via pragma options
            // When linked with SQLCipher, these pragmas encrypt the database
            let passphrase = KeychainService.getOrCreateDBPassphrase()
            description.setOption(
                ["key": passphrase] as NSDictionary,
                forKey: "NSSQLitePragmasOption" // Interpreted by SQLCipher-backed SQLite
            )

            // iOS Data Protection as belt-and-suspenders encryption
            description.setOption(
                FileProtectionType.complete as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )

            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                // In production: log to crash reporter, show user error
                fatalError("CoreData load failed: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // In production: log error
            print("CoreData save error: \(error)")
        }
    }
}
