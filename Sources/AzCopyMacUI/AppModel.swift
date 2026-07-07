import AzCopyMacUICore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var azCopyPath: String = AzCopyLocator.homebrewAppleSiliconPath
    @Published var source: String = ""
    @Published var destination: String = ""
    @Published var recursive: Bool = true
    @Published var dryRun: Bool = false
    @Published var selectedAction: TransferAction = .copy
    @Published var selectedAuthentication: AuthenticationOption = .userIdentity
    @Published var tenantID: String = ""
    @Published var applicationID: String = ""
    @Published var managedIdentityID: String = ""
    @Published var commandPreview: String = ""
    @Published var statusMessage: String = "Ready"

    private let builder = AzCopyCommandBuilder()

    init() {
        refreshPreview()
    }

    func refreshPreview() {
        let authentication = selectedAuthentication.method(
            tenantID: tenantID,
            applicationID: applicationID,
            managedIdentityID: managedIdentityID
        )
        let request = TransferRequest(
            action: selectedAction,
            source: source,
            destination: destination.isEmpty ? nil : destination,
            recursive: recursive,
            dryRun: dryRun,
            authentication: authentication
        )

        do {
            let invocation = try builder.build(
                request: request,
                azCopyURL: URL(fileURLWithPath: azCopyPath)
            )
            commandPreview = invocation.redactedPreview
            statusMessage = "Command is ready."
        } catch {
            commandPreview = ""
            statusMessage = error.localizedDescription
        }
    }
}

enum AuthenticationOption: String, CaseIterable, Identifiable {
    case userIdentity
    case deviceCode
    case azureCLI
    case azurePowerShell
    case servicePrincipalSecret
    case servicePrincipalCertificate
    case managedIdentitySystem
    case managedIdentityClientID
    case managedIdentityObjectID
    case managedIdentityResourceID
    case sas

    var id: String { rawValue }

    var title: String {
        method(tenantID: nil, applicationID: "", managedIdentityID: "").displayName
    }

    func method(tenantID: String?, applicationID: String, managedIdentityID: String) -> AuthenticationMethod {
        let normalizedTenantID = tenantID?.isEmpty == true ? nil : tenantID
        switch self {
        case .userIdentity:
            return .userIdentity(tenantID: normalizedTenantID)
        case .deviceCode:
            return .deviceCodeEnvironment
        case .azureCLI:
            return .azureCLI(tenantID: normalizedTenantID)
        case .azurePowerShell:
            return .azurePowerShell(tenantID: normalizedTenantID)
        case .servicePrincipalSecret:
            return .servicePrincipalSecret(
                applicationID: applicationID,
                tenantID: normalizedTenantID ?? "",
                clientSecret: "<entered at run time>"
            )
        case .servicePrincipalCertificate:
            return .servicePrincipalCertificate(
                applicationID: applicationID,
                tenantID: normalizedTenantID ?? "",
                certificatePath: "<selected certificate>",
                certificatePassword: nil
            )
        case .managedIdentitySystem:
            return .managedIdentitySystem
        case .managedIdentityClientID:
            return .managedIdentityClientID(managedIdentityID)
        case .managedIdentityObjectID:
            return .managedIdentityObjectID(managedIdentityID)
        case .managedIdentityResourceID:
            return .managedIdentityResourceID(managedIdentityID)
        case .sas:
            return .sas
        }
    }
}

