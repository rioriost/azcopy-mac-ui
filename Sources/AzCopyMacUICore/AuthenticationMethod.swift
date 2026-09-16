import Foundation

public enum AuthenticationMethod: Equatable, Sendable {
    case userIdentity(tenantID: String?)
    case deviceCode(tenantID: String?)
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

    public enum ValidationError: Error, Equatable, LocalizedError {
        case missingRequiredField(String)
        case invalidField(String)
        case managedIdentityObjectIDUnsupported
        case accountKeyDirectAuthUnsupported

        public var errorDescription: String? {
            switch self {
            case .missingRequiredField(let field):
                "\(field) is required for the selected authentication method."
            case .invalidField(let field):
                "\(field) cannot contain null characters."
            case .managedIdentityObjectIDUnsupported:
                "Managed identity Object ID is no longer supported by AzCopy. Select Client ID or Resource ID and enter the corresponding identifier; do not reuse the Object ID."
            case .accountKeyDirectAuthUnsupported:
                "AzCopy v10 does not support direct account-key authentication. Use a SAS URL instead."
            }
        }
    }

    public func validate() throws {
        switch self {
        case .servicePrincipalSecret(let applicationID, let tenantID, let clientSecret):
            try require(applicationID, field: "Application ID")
            try require(tenantID, field: "Tenant ID")
            try require(clientSecret, field: "Client secret")
        case .servicePrincipalCertificate(let applicationID, let tenantID, let certificatePath, let password):
            try require(applicationID, field: "Application ID")
            try require(tenantID, field: "Tenant ID")
            try require(certificatePath, field: "Certificate path")
            try validateOptional(password, field: "Certificate password")
        case .managedIdentityClientID(let identifier):
            try require(identifier, field: "Managed identity Client ID")
        case .managedIdentityResourceID(let identifier):
            try require(identifier, field: "Managed identity Resource ID")
        case .managedIdentityObjectID:
            throw ValidationError.managedIdentityObjectIDUnsupported
        case .accountKeyDerivedSAS:
            throw ValidationError.accountKeyDirectAuthUnsupported
        case .userIdentity(let tenantID), .deviceCode(let tenantID), .azureCLI(let tenantID), .azurePowerShell(let tenantID):
            try validateOptional(tenantID, field: "Tenant ID")
        case .deviceCodeEnvironment, .managedIdentitySystem, .sas:
            break
        }
    }

    public var displayName: String {
        switch self {
        case .userIdentity:
            "Microsoft Entra user login"
        case .deviceCode, .deviceCodeEnvironment:
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
            "Managed identity, object ID (unsupported)"
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
        case .deviceCode(let tenantID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE"].merging(tenantEnvironment(tenantID)) { _, new in new }
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
        case .managedIdentityObjectID:
            return [:]
        case .managedIdentityResourceID(let resourceID):
            return ["AZCOPY_AUTO_LOGIN_TYPE": "MSI", "AZCOPY_MSI_RESOURCE_STRING": resourceID]
        case .sas, .accountKeyDerivedSAS:
            return [:]
        }
    }

    public var loginArguments: [String]? {
        switch self {
        case .userIdentity(let tenantID), .deviceCode(let tenantID):
            var arguments = ["login"]
            if let tenantID = normalizedTenant(tenantID) {
                arguments.append("--tenant-id=\(tenantID)")
            }
            return arguments
        case .deviceCodeEnvironment:
            return ["login"]
        case .servicePrincipalSecret(let applicationID, let tenantID, _):
            return ["login", "--service-principal", "--application-id", applicationID, "--tenant-id=\(tenantID)"]
        case .servicePrincipalCertificate(let applicationID, let tenantID, let certificatePath, _):
            return ["login", "--service-principal", "--application-id", applicationID, "--certificate-path", certificatePath, "--tenant-id=\(tenantID)"]
        case .managedIdentitySystem:
            return ["login", "--identity"]
        case .managedIdentityClientID(let clientID):
            return ["login", "--identity", "--identity-client-id", clientID]
        case .managedIdentityResourceID(let resourceID):
            return ["login", "--identity", "--identity-resource-id", resourceID]
        case .managedIdentityObjectID, .azureCLI, .azurePowerShell, .sas, .accountKeyDerivedSAS:
            return nil
        }
    }

    var signInGuidance: String {
        switch self {
        case .azureCLI:
            "Sign in using `az login` first, then use the Azure CLI session for transfers."
        case .azurePowerShell:
            "Sign in using `Connect-AzAccount` first, then use the Azure PowerShell session for transfers."
        case .sas:
            "SAS authentication does not use Sign In. Supply a SAS URL or token for the transfer."
        default:
            "This authentication method cannot sign in. Select Microsoft Entra user login or a supported identity."
        }
    }

    private func tenantEnvironment(_ tenantID: String?) -> [String: String] {
        guard let tenantID = normalizedTenant(tenantID) else { return [:] }
        return ["AZCOPY_TENANT_ID": tenantID]
    }

    private func normalizedTenant(_ tenantID: String?) -> String? {
        guard let trimmed = tenantID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func require(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingRequiredField(field)
        }
        try validateOptional(value, field: field)
    }

    private func validateOptional(_ value: String?, field: String) throws {
        if value?.contains("\0") == true {
            throw ValidationError.invalidField(field)
        }
    }
}
