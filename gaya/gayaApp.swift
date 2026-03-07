import SwiftUI
#if canImport(ATAuthSDK)
import ATAuthSDK
#endif

@main
struct gayaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        #if canImport(ATAuthSDK)
        TXCommonHandler.sharedInstance().setAuthSDKInfo(Secrets.pnvsAuthSecret) { result in
            let code = result["resultCode"] as? String ?? ""
            let msg = result["msg"] as? String ?? ""
            print("🔐 ATAuthSDK init: code=\(code) msg=\(msg)")
        }
        #endif
    }
    
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
                    MembershipStore.shared.prepareForAppLaunch()
                    await MembershipStore.shared.handleAppDidBecomeActive()
                    await MemoryCorridorStore.shared.handleAppDidBecomeActive()
                }
            @unknown default:
                break
            }
        }
    }
}
