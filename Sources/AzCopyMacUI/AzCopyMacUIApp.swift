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
                .frame(minWidth: 860, minHeight: 640)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1060, height: 820)
        .commands { OperationCommands() }

        Settings {
            VStack(spacing: 0) {
                ExecutionStatusView()
                    .padding()
                Divider()
                SettingsView()
            }
            .environmentObject(model)
            .frame(width: 720, height: 640)
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

struct AzCopyCommandAction {
    let title: String
    let isEnabled: Bool
    let perform: () -> Void
}

private struct AzCopyCommandKey: FocusedValueKey {
    typealias Value = AzCopyCommandAction
}

extension FocusedValues {
    var azCopyCommand: AzCopyCommandAction? {
        get { self[AzCopyCommandKey.self] }
        set { self[AzCopyCommandKey.self] = newValue }
    }
}

private struct OperationCommands: Commands {
    @FocusedValue(\.azCopyCommand) private var command

    var body: some Commands {
        CommandMenu("Operation") {
            Button(command?.title ?? "Run Selected Command") {
                command?.perform()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(command?.isEnabled != true)
        }
    }
}
