import AzCopyMacUICore
import SwiftUI

@main
struct AzCopyMacUIApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}
