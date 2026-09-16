import AzCopyMacUICore
import AppKit
import SwiftUI

@main
struct AzCopyMacUIApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { appDelegate.model = model }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard model.isRunning || model.isLoadingTenants else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Cancel running commands and quit?"
        alert.informativeText = "AzCopy and any tenant lookup will be stopped before the app quits."
        alert.addButton(withTitle: "Cancel and Quit")
        alert.addButton(withTitle: "Keep Running")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        model.cancelCommand()
        model.cancelTenantLookup()
        Task {
            await model.waitForCommand()
            await model.waitForTenantLookup()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
