import SwiftData
import SwiftUI

@main
struct GerenzhuliApp: App {
    @State private var store = Store()
    @State private var permissions = PermissionsService()
    @AppStorage("gzOnboardingDone") private var onboardingDone = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ReminderItem.self,
            DayEvent.self,
            Subscriber.self,
            Trip.self,
            TripStop.self,
            TripTicket.self,
            BriefingItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 创建失败：\(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(permissions)
                .modelContainer(sharedModelContainer)
        }
    }
}

struct RootView: View {
    @AppStorage("gzOnboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if onboardingDone {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .background(Color.gzBackground.ignoresSafeArea())
        .onAppear {
            store.seedIfNeeded(context: modelContext)
        }
    }
}
