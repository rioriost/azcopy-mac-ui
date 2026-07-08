import AzCopyMacUICore
import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Section? = .operations

    enum Section: String, CaseIterable, Identifiable {
        case operations = "Operations"
        case settings = "Settings"
        case logs = "Logs"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .operations:
                "arrow.left.arrow.right"
            case .settings:
                "gearshape"
            case .logs:
                "doc.text.magnifyingglass"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.systemImage)
                }
            }
            .navigationTitle("AzCopy")
        } detail: {
            Group {
                switch selection ?? .operations {
                case .operations:
                    OperationsView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

private extension View {
    func topAlignedForm() -> some View {
        frame(maxWidth: FormLayout.formWidth, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum FormLayout {
    static let formWidth: CGFloat = 760
    static let labelWidth: CGFloat = 158
    static let labelTextIndent: CGFloat = 8
    static let rowSpacing: CGFloat = 8
    static let sectionCardPadding: CGFloat = 10
}

private struct FixedLabelRow<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let title, !title.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: FormLayout.rowSpacing) {
                Text(title)
                    .lineLimit(1)
                    .font(title == "Command" ? .headline : .body)
                    .padding(.leading, title == "Command" ? 0 : FormLayout.labelTextIndent)
                    .frame(width: FormLayout.labelWidth, alignment: .leading)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: FormLayout.formWidth, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: FormLayout.rowSpacing) {
                Text("")
                    .frame(width: FormLayout.labelWidth)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: FormLayout.formWidth, alignment: .leading)
        }
    }
}

private struct FixedSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(width: FormLayout.labelWidth, alignment: .leading)
                .frame(width: FormLayout.formWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(FormLayout.sectionCardPadding)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            }
            .padding(.horizontal, -FormLayout.sectionCardPadding)
        }
    }
}

private struct TextInputRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var disabled = false
    var onChange: () -> Void

    var body: some View {
        FixedLabelRow(title: title) {
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .disabled(disabled)
                .onChange(of: text) { _, _ in onChange() }
        }
    }
}

private struct SecureInputRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var onChange: () -> Void = {}

    var body: some View {
        FixedLabelRow(title: title) {
            SecureField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, _ in onChange() }
        }
    }
}

private struct FileInputRow: View {
    let title: String
    let prompt: String
    let buttonHelp: String
    @Binding var text: String
    var disabled = false
    var onChoose: () -> Void
    var onChange: () -> Void

    var body: some View {
        FixedLabelRow(title: title) {
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .disabled(disabled)
                    .onChange(of: text) { _, _ in onChange() }
                Button(action: onChoose) {
                    Image(systemName: "folder")
                }
                .disabled(disabled)
                .help(buttonHelp)
            }
        }
    }
}

private enum CommandCategory: String, CaseIterable, Identifiable {
    case transfer = "Transfer"
    case benchmark = "Benchmark"
    case storage = "Storage"
    case jobs = "Jobs"
    case session = "Session"
    case environment = "Environment"

    var id: String { rawValue }
}

private extension TransferAction {
    var title: String {
        switch self {
        case .copy: "Copy"
        case .sync: "Sync"
        case .list: "List"
        case .remove: "Remove"
        case .bench: "Bench"
        case .make: "Make container/share"
        case .setProperties: "Set properties"
        case .env: "Environment"
        case .jobsList: "List"
        case .jobsShow: "Show"
        case .jobsResume: "Resume"
        case .jobsRemove: "Remove"
        case .jobsClean: "Clean"
        case .loginStatus: "Login status"
        case .logout: "Logout"
        }
    }

    var category: CommandCategory {
        switch self {
        case .copy, .sync, .list, .remove:
            .transfer
        case .bench:
            .benchmark
        case .make, .setProperties:
            .storage
        case .jobsList, .jobsShow, .jobsResume, .jobsRemove, .jobsClean:
            .jobs
        case .loginStatus, .logout:
            .session
        case .env:
            .environment
        }
    }

    var needsSource: Bool {
        switch self {
        case .copy, .sync, .list, .remove, .bench, .make, .setProperties:
            true
        default:
            false
        }
    }

    var needsDestination: Bool {
        self == .copy || self == .sync
    }

    var needsJobID: Bool {
        switch self {
        case .jobsShow, .jobsResume, .jobsRemove:
            true
        default:
            false
        }
    }

    var supportsRecursive: Bool {
        switch self {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }

    var supportsDryRun: Bool {
        switch self {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }

    var supportsCapMbps: Bool {
        switch self {
        case .copy, .sync, .bench:
            true
        default:
            false
        }
    }

    var supportsIncludeExcludePattern: Bool {
        switch self {
        case .copy, .sync, .remove, .setProperties:
            true
        default:
            false
        }
    }

    var hasStandardOptions: Bool {
        supportsRecursive ||
            supportsDryRun ||
            supportsCapMbps ||
            supportsIncludeExcludePattern ||
            self == .copy ||
            self == .sync
    }

    var sourceTitle: String {
        switch self {
        case .bench:
            "Benchmark target URL"
        case .make:
            "Resource URL"
        case .setProperties:
            "Resource path or URL"
        case .list:
            "Resource URL"
        case .remove:
            "Resource path or URL"
        default:
            "Source path or URL"
        }
    }

    var sourcePrompt: String {
        switch self {
        case .bench:
            "https://account.blob.core.windows.net/container?[SAS]"
        case .make:
            "https://account.blob.core.windows.net/container"
        case .setProperties:
            "https://account.blob.core.windows.net/container/path"
        case .list:
            "https://account.blob.core.windows.net/container"
        case .remove:
            "https://account.blob.core.windows.net/container/blob"
        default:
            "/Users/you/Documents or https://account.blob.core.windows.net/container"
        }
    }

    static func actions(in category: CommandCategory) -> [TransferAction] {
        allCases.filter { $0.category == category }
    }
}

struct OperationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: CommandCategory = .transfer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
            FixedLabelRow(title: nil) {
                Picker("", selection: $category) {
                    ForEach(CommandCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .onChange(of: category) { _, newCategory in
                let actions = TransferAction.actions(in: newCategory)
                if !actions.contains(model.selectedAction), let firstAction = actions.first {
                    model.selectedAction = firstAction
                    model.refreshPreview()
                }
            }

            FixedLabelRow(title: "Command") {
                Picker("", selection: $model.selectedAction) {
                    ForEach(TransferAction.actions(in: category), id: \.self) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .onChange(of: model.selectedAction) { _, newAction in
                category = newAction.category
                model.refreshPreview()
            }

            if model.selectedAction.needsSource {
                if [.copy, .sync].contains(model.selectedAction) {
                    FileInputRow(
                        title: model.selectedAction.sourceTitle,
                        prompt: model.selectedAction.sourcePrompt,
                        buttonHelp: "Choose local source path",
                        text: $model.source,
                        onChoose: {
                            choosePath(title: "Choose Source", binding: $model.source)
                        },
                        onChange: model.refreshPreview
                    )
                } else {
                    TextInputRow(
                        title: model.selectedAction.sourceTitle,
                        prompt: model.selectedAction.sourcePrompt,
                        text: $model.source,
                        onChange: model.refreshPreview
                    )
                }
            }

            if model.selectedAction.needsDestination {
                FileInputRow(
                    title: "Destination path or URL",
                    prompt: "/Users/you/Downloads or https://account.blob.core.windows.net/container",
                    buttonHelp: "Choose local destination path",
                    text: $model.destination,
                    onChoose: {
                        choosePath(title: "Choose Destination", binding: $model.destination)
                    },
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAction.needsJobID {
                TextInputRow(title: "Job ID", prompt: "00000000-0000-0000-0000-000000000000", text: $model.jobID, onChange: model.refreshPreview)
            }

            if model.selectedAction == .bench {
                FixedSection("Benchmark") {
                    FixedLabelRow(title: "Mode") {
                        Picker("", selection: $model.benchMode) {
                            Text("Upload").tag("upload")
                            Text("Download").tag("download")
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.benchMode) { _, _ in model.refreshPreview() }

                    TextInputRow(title: "File count", prompt: "100", text: $model.benchFileCount, onChange: model.refreshPreview)
                    TextInputRow(title: "Size per file", prompt: "250M", text: $model.benchSizePerFile, onChange: model.refreshPreview)
                    TextInputRow(title: "Number of folders", prompt: "5", text: $model.benchNumberOfFolders, onChange: model.refreshPreview)
                    FixedLabelRow(title: nil) {
                        Toggle("Delete test data", isOn: $model.benchDeleteTestData)
                            .onChange(of: model.benchDeleteTestData) { _, _ in model.refreshPreview() }
                    }
                    FixedLabelRow(title: nil) {
                        Toggle("Put MD5", isOn: $model.benchPutMD5)
                            .onChange(of: model.benchPutMD5) { _, _ in model.refreshPreview() }
                    }
                    FixedLabelRow(title: nil) {
                        Toggle("Check length", isOn: $model.benchCheckLength)
                            .onChange(of: model.benchCheckLength) { _, _ in model.refreshPreview() }
                    }
                }
            }

            if model.selectedAction == .make {
                FixedSection("Storage") {
                    TextInputRow(title: "Quota GB", prompt: "100", text: $model.makeQuotaGB, onChange: model.refreshPreview)
                }
            }

            if model.selectedAction == .setProperties {
                FixedSection("Properties") {
                    FixedLabelRow(title: "Block blob tier") {
                        Picker("", selection: $model.blockBlobTier) {
                            ForEach(["None", "Hot", "Cool", "Cold", "Archive"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.blockBlobTier) { _, _ in model.refreshPreview() }

                    FixedLabelRow(title: "Page blob tier") {
                        Picker("", selection: $model.pageBlobTier) {
                            ForEach(["None", "P4", "P6", "P10", "P15", "P20", "P30", "P40", "P50"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.pageBlobTier) { _, _ in model.refreshPreview() }

                    FixedLabelRow(title: "Rehydrate priority") {
                        Picker("", selection: $model.rehydratePriority) {
                            ForEach(["Standard", "High"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.rehydratePriority) { _, _ in model.refreshPreview() }

                    TextInputRow(title: "Metadata", prompt: "key=value;owner=team", text: $model.metadata, onChange: model.refreshPreview)
                    TextInputRow(title: "Blob tags", prompt: "key=value&project=demo", text: $model.blobTags, onChange: model.refreshPreview)
                    TextInputRow(title: "Include pattern", prompt: "*.jpg;*.png", text: $model.includePattern, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude pattern", prompt: "*.tmp;*.log", text: $model.excludePattern, onChange: model.refreshPreview)
                    TextInputRow(title: "Include path", prompt: "folder/file.txt;other/path", text: $model.includePath, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude path", prompt: "tmp;archive/old", text: $model.excludePath, onChange: model.refreshPreview)
                    TextInputRow(title: "List of files", prompt: "/Users/you/files.txt", text: $model.listOfFiles, onChange: model.refreshPreview)
                }
            }

            if model.selectedAction == .jobsShow {
                FixedSection("Job filters") {
                    FixedLabelRow(title: "Transfer status") {
                        Picker("", selection: $model.jobTransferStatus) {
                            Text("Any").tag("")
                            ForEach(["All", "Started", "Success", "Failed"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .onChange(of: model.jobTransferStatus) { _, _ in model.refreshPreview() }
                }
            }

            if model.selectedAction == .jobsResume {
                FixedSection("Resume filters") {
                    SecureInputRow(title: "Source SAS", prompt: "sv=...&sig=...", text: $model.sourceSAS)
                    SecureInputRow(title: "Destination SAS", prompt: "sv=...&sig=...", text: $model.destinationSAS)
                    TextInputRow(title: "Include failed transfers", prompt: "path1;path2", text: $model.includePath, onChange: model.refreshPreview)
                    TextInputRow(title: "Exclude failed transfers", prompt: "path1;path2", text: $model.excludePath, onChange: model.refreshPreview)
                }
                .onChange(of: model.sourceSAS) { _, _ in model.refreshPreview() }
                .onChange(of: model.destinationSAS) { _, _ in model.refreshPreview() }
            }

            if model.selectedAction == .env {
                FixedLabelRow(title: nil) {
                    Toggle("Show sensitive variables", isOn: $model.showSensitiveEnvironment)
                        .onChange(of: model.showSensitiveEnvironment) { _, _ in model.refreshPreview() }
                }
            }

            if model.selectedAction.hasStandardOptions {
                FixedSection("Options") {
                    if model.selectedAction.supportsRecursive {
                        FixedLabelRow(title: nil) {
                            Toggle("Recursive", isOn: $model.recursive)
                                .onChange(of: model.recursive) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction.supportsDryRun {
                        FixedLabelRow(title: nil) {
                            Toggle("Dry run", isOn: $model.dryRun)
                                .onChange(of: model.dryRun) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction == .copy {
                        FixedLabelRow(title: nil) {
                            Toggle("Overwrite existing files", isOn: $model.overwriteExisting)
                                .onChange(of: model.overwriteExisting) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction == .sync {
                        FixedLabelRow(title: nil) {
                            Toggle("Delete destination extras", isOn: $model.deleteDestination)
                                .onChange(of: model.deleteDestination) { _, _ in model.refreshPreview() }
                        }
                    }

                    if model.selectedAction.supportsCapMbps {
                        TextInputRow(title: "Cap Mbps", prompt: "100", text: $model.capMbps, onChange: model.refreshPreview)
                    }

                    if model.selectedAction.supportsIncludeExcludePattern, model.selectedAction != .setProperties {
                        TextInputRow(title: "Include pattern", prompt: "*.jpg;*.png", text: $model.includePattern, onChange: model.refreshPreview)

                        TextInputRow(title: "Exclude pattern", prompt: "*.tmp;*.log", text: $model.excludePattern, onChange: model.refreshPreview)
                    }
                }
            }

            FixedLabelRow(title: "Preview") {
                HStack(alignment: .top, spacing: 8) {
                    Text(model.commandPreview.isEmpty ? model.statusMessage : model.commandPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        copyPreviewToClipboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(model.commandPreview.isEmpty)
                    .help("Copy preview command")
                    .accessibilityLabel("Copy preview command")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {}
                    .disabled(true)
                    .keyboardShortcut(.cancelAction)
                Button("Run") {
                    Task {
                        await model.runSelectedCommand()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.commandPreview.isEmpty || model.isRunning)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Run AzCopy command")
            }
            }
            .frame(width: FormLayout.formWidth, alignment: .leading)
        }
        .topAlignedForm()
        .navigationTitle("Operations")
        .onAppear {
            category = model.selectedAction.category
        }
    }

    private func choosePath(title: String, binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
            model.refreshPreview()
        }
    }

    private func copyPreviewToClipboard() {
        guard !model.commandPreview.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.commandPreview, forType: .string)
    }
}

struct AuthenticationSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        FixedSection("Authentication") {
            FixedLabelRow(title: "Authentication") {
                Picker("", selection: $model.selectedAuthentication) {
                    ForEach(AuthenticationOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            .onChange(of: model.selectedAuthentication) { _, _ in model.refreshPreview() }

            FixedLabelRow(title: "Tenant ID") {
                HStack(spacing: 8) {
                    if model.tenantOptions.isEmpty {
                        TextField("", text: $model.tenantID, prompt: Text("72f988bf-86f1-41af-91ab-2d7cd011db47"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.tenantID) { _, _ in model.refreshPreview() }
                    } else {
                        Picker("", selection: $model.tenantID) {
                            Text("None").tag("")
                            ForEach(model.tenantOptions) { tenant in
                                Text(tenant.title).tag(tenant.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .onChange(of: model.tenantID) { _, _ in model.refreshPreview() }
                    }

                    Button {
                        model.loadTenants()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Load tenants from Azure CLI")
                }
            }

            if !model.tenantLoadMessage.isEmpty {
                FixedLabelRow(title: nil) {
                    Text(model.tenantLoadMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if [.servicePrincipalSecret, .servicePrincipalCertificate].contains(model.selectedAuthentication) {
                TextInputRow(
                    title: "Application ID",
                    prompt: "00000000-0000-0000-0000-000000000000",
                    text: $model.applicationID,
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAuthentication == .servicePrincipalSecret {
                SecureInputRow(
                    title: "Client secret",
                    prompt: "Client secret value",
                    text: $model.servicePrincipalSecret,
                    onChange: model.refreshPreview
                )
            }

            if model.selectedAuthentication == .servicePrincipalCertificate {
                FileInputRow(
                    title: "Certificate path",
                    prompt: "/Users/you/certs/service-principal.pem",
                    buttonHelp: "Choose service principal certificate",
                    text: $model.certificatePath,
                    onChoose: {
                        chooseCertificatePath()
                    },
                    onChange: model.refreshPreview
                )

                SecureInputRow(
                    title: "Certificate password",
                    prompt: "Optional certificate password",
                    text: $model.certificatePassword,
                    onChange: model.refreshPreview
                )
            }

            if [.managedIdentityClientID, .managedIdentityObjectID, .managedIdentityResourceID].contains(model.selectedAuthentication) {
                TextInputRow(
                    title: "Managed identity identifier",
                    prompt: "client ID, object ID, or resource ID",
                    text: $model.managedIdentityID,
                    onChange: model.refreshPreview
                )
            }

            FixedLabelRow(title: nil) {
                Text("Secrets are passed only to the current AzCopy process environment and are redacted from previews and logs.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if model.tenantOptions.isEmpty {
                model.loadTenants()
            }
        }
    }

    private func chooseCertificatePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose Service Principal Certificate"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.certificatePath = url.path
            model.refreshPreview()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                FixedSection("AzCopy") {
                    FileInputRow(
                        title: "AzCopy executable",
                        prompt: AzCopyLocator.homebrewAppleSiliconPath,
                        buttonHelp: "Choose AzCopy executable",
                        text: $model.azCopyPath,
                        onChoose: {
                            chooseAzCopyExecutable()
                        },
                        onChange: model.refreshPreview
                    )
                    FixedLabelRow(title: nil) {
                        Text("Default Apple Silicon Homebrew path: \(AzCopyLocator.homebrewAppleSiliconPath)")
                            .foregroundStyle(.secondary)
                    }
                }

                AuthenticationSettingsSection()

                FixedSection("Advanced") {
                    TextInputRow(
                        title: "Additional flags",
                        prompt: "--log-level=INFO --output-type=json",
                        text: $model.extraFlagsText,
                        onChange: model.refreshPreview
                    )
                }
            }
            .frame(width: FormLayout.formWidth, alignment: .leading)
        }
        .topAlignedForm()
        .navigationTitle("Settings")
    }

    private func chooseAzCopyExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose AzCopy Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.azCopyPath = url.path
            model.refreshPreview()
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.logText.isEmpty {
                    Text("AzCopy output will be streamed here with credentials redacted.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.logText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Logs")
    }
}
