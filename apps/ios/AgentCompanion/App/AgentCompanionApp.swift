import SwiftUI

@main
struct AgentCompanionApp: App {
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
