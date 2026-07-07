import Foundation

public enum AuthenticationMethod: Equatable, Sendable {
    case userIdentity(tenantID: String?)
    case deviceCodeEnvironment
    case azureCLI(tenantID: String?)
    case azurePowerShell(tenantID: String?)
    case servicePrincipalSecret(applicationID: String, tenantID: String, clientSecret: String)
    case servicePrincipalCertificate(applicationID: String, tenantID: String, certificatePath: String, certificatePassword: String?)
    case managedIdentitySystem
    case managedIdentityClientID(String)
    case managedIdentityObjectID(String)
    case managedIdentityResourceID(String)
    case sas
    case accountKeyDerivedSAS

    public var displayName: String {
        switch self {
        case .userIdentity:
            "Microsoft Entra user login"
        case .deviceCodeEnvironment:
            "Device code"
        case .azureCLI:
            "Azure CLI session"
        case .azurePowerShell:
            "Azure PowerShell session"
        case .servicePrincipalSecret:
            "Service principal with client secret"
        case .servicePrincipalCertificate:
            "Service principal with certificate"
        case .managedIdentitySystem:
            "Managed identity, system-assigned"
        case .managedIdentityClientID:
            "Managed identity, client ID"
        case .managedIdentityObjectID:
            "Managed identity, object ID"
        case .managedIdentityResourceID:
            "Managed identity, resource ID"
        case .sas:
            "SAS token"
        case .accountKeyDerivedSAS:
            "Account key-derived SAS helper"
        }
    }

    public var environment: [String: String] {
        switch self {
        case .userIdentity(let tenantID):
            return tenantEnvironment(tenantID)
        case .deviceCodeEnvironment:
            return ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE"]
        case .azureCLI(let tenantID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "AZCLI"].merging(tenantEnvironment(tenantID)) { _, new in new }
        case .azurePowerShell(let tenantID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "PSCRED"].merging(tenantEnvironment(tenantID)) { _, new in new }
        case .servicePrincipalSecret(let applicationID, let tenantID, let clientSecret):
            return [
                "AZCOPY_AUTO_LOGIN_TYPE": "SPN",
                "AZCOPY_SPA_APPLICATION_ID": applicationID,
                "AZCOPY_SPA_CLIENT_SECRET": clientSecret,
                "AZCOPY_TENANT_ID": tenantID
            ]
        case .servicePrincipalCertificate(let applicationID, let tenantID, let certificatePath, let certificatePassword):
            var environment = [
                "AZCOPY_AUTO_LOGIN_TYPE": "SPN",
                "AZCOPY_SPA_APPLICATION_ID": applicationID,
                "AZCOPY_SPA_CERT_PATH": certificatePath,
                "AZCOPY_TENANT_ID": tenantID
            ]
            if let certificatePassword, !certificatePassword.isEmpty {
                environment["AZCOPY_SPA_CERT_PASSWORD"] = certificatePassword
            }
            return environment
        case .managedIdentitySystem:
            return ["AZCOPY_AUTO_LOGIN_TYPE": "MSI"]
        case .managedIdentityClientID(let clientID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "MSI", "AZCOPY_MSI_CLIENT_ID": clientID]
        case .managedIdentityObjectID(let objectID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "MSI", "AZCOPY_MSI_OBJECT_ID": objectID]
        case .managedIdentityResourceID(let resourceID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "MSI", "AZCOPY_MSI_RESOURCE_STRING": resourceID]
        case .sas, .accountKeyDerivedSAS:
            return [:]
        }
    }

    public var loginArguments: [String]? {
        switch self {
        case .userIdentity(let tenantID):
            var arguments = ["login"]
            if let tenantID, !tenantID.isEmpty {
                arguments.append("--tenant-id=\(tenantID)")
            }
            return arguments
        case .servicePrincipalSecret(let applicationID, let tenantID, _):
            return ["login", "--service-principal", "--application-id", applicationID, "--tenant-id=\(tenantID)"]
        case .servicePrincipalCertificate(let applicationID, let tenantID, let certificatePath, _):
            return ["login", "--service-principal", "--application-id", applicationID, "--certificate-path", certificatePath, "--tenant-id=\(tenantID)"]
        case .managedIdentitySystem:
            return ["login", "--identity"]
        case .managedIdentityClientID(let clientID):
            return ["login", "--identity", "--identity-client-id", clientID]
        case .managedIdentityObjectID(let objectID):
            return ["login", "--identity", "--identity-object-id", objectID]
        case .managedIdentityResourceID(let resourceID):
            return ["login", "--identity", "--identity-resource-id", resourceID]
        case .deviceCodeEnvironment, .azureCLI, .azurePowerShell, .sas, .accountKeyDerivedSAS:
            return nil
        }
    }

    private func tenantEnvironment(_ tenantID: String?) -> [String: String] {
        guard let tenantID, !tenantID.isEmpty else { return [:] }
        return ["AZCOPY_TENANT_ID": tenantID]
    }
}

