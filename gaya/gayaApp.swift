import SwiftUI

@main
struct gayaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // App 进入后台时保存记忆
                print("📱 App entering background - saving memory...")
                MemoryStore.shared.saveToDisk()
                MemoryCorridorStore.shared.saveToDisk()
            case .inactive:
                // App 变为非活动状态时也保存
                print("📱 App becoming inactive - saving memory...")
                MemoryStore.shared.saveToDisk()
                MemoryCorridorStore.shared.saveToDisk()
            case .active:
                print("📱 App became active")
                Task { @MainActor in
                    await MemoryCorridorStore.shared.handleAppDidBecomeActive()
                }
            @unknown default:
                break
            }
        }
    }
}
