import Testing
@testable import AzCopyMacUICore

@Suite("AuthenticationMethod")
struct AuthenticationMethodTests {
    @Test("service principal secret maps to AzCopy environment")
    func servicePrincipalSecretEnvironment() {
        let method = AuthenticationMethod.servicePrincipalSecret(
            applicationID: "app",
            tenantID: "tenant",
            clientSecret: "secret"
        )

        #expect(method.environment["AZCOPY_AUTO_LOGIN_TYPE"] == "SPN")
        #expect(method.environment["AZCOPY_SPA_APPLICATION_ID"] == "app")
        #expect(method.environment["AZCOPY_SPA_CLIENT_SECRET"] == "secret")
        #expect(method.environment["AZCOPY_TENANT_ID"] == "tenant")
        #expect(method.loginArguments == ["login", "--service-principal", "--application-id", "app", "--tenant-id=tenant"])
    }

    @Test("managed identity login arguments cover all identity selectors")
    func managedIdentityLoginArguments() {
        #expect(AuthenticationMethod.managedIdentitySystem.loginArguments == ["login", "--identity"])
        #expect(AuthenticationMethod.managedIdentityClientID("client").loginArguments == ["login", "--identity", "--identity-client-id", "client"])
        #expect(AuthenticationMethod.managedIdentityObjectID("object").loginArguments == nil)
        #expect(AuthenticationMethod.managedIdentityResourceID("resource").loginArguments == ["login", "--identity", "--identity-resource-id", "resource"])
    }

    @Test("Azure CLI and PowerShell set documented auto-login values")
    func externalSessionEnvironment() {
        #expect(AuthenticationMethod.azureCLI(tenantID: "tenant").environment == [
            "AZCOPY_AUTO_LOGIN_TYPE": "AZCLI",
            "AZCOPY_TENANT_ID": "tenant"
        ])
        #expect(AuthenticationMethod.azurePowerShell(tenantID: nil).environment == [
            "AZCOPY_AUTO_LOGIN_TYPE": "PSCRED"
        ])
    }

    @Test("all display names are present")
    func displayNames() {
        let methods: [AuthenticationMethod] = [
            .userIdentity(tenantID: nil),
            .deviceCode(tenantID: "tenant"),
            .deviceCodeEnvironment,
            .azureCLI(tenantID: nil),
            .azurePowerShell(tenantID: nil),
            .servicePrincipalSecret(applicationID: "app", tenantID: "tenant", clientSecret: "secret"),
            .servicePrincipalCertificate(applicationID: "app", tenantID: "tenant", certificatePath: "/tmp/cert.pem", certificatePassword: "password"),
            .managedIdentitySystem,
            .managedIdentityClientID("client"),
            .managedIdentityObjectID("object"),
            .managedIdentityResourceID("resource"),
            .sas,
            .accountKeyDerivedSAS
        ]

        #expect(methods.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("environment covers documented auth variants")
    func environmentVariants() {
        #expect(AuthenticationMethod.userIdentity(tenantID: "tenant").environment == ["AZCOPY_TENANT_ID": "tenant"])
        #expect(AuthenticationMethod.deviceCodeEnvironment.environment == ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE"])
        #expect(AuthenticationMethod.servicePrincipalCertificate(
            applicationID: "app",
            tenantID: "tenant",
            certificatePath: "/tmp/cert.pem",
            certificatePassword: "password"
        ).environment["AZCOPY_SPA_CERT_PASSWORD"] == "password")
        #expect(AuthenticationMethod.managedIdentitySystem.environment == ["AZCOPY_AUTO_LOGIN_TYPE": "MSI"])
        #expect(AuthenticationMethod.managedIdentityClientID("client").environment["AZCOPY_MSI_CLIENT_ID"] == "client")
        #expect(AuthenticationMethod.managedIdentityObjectID("object").environment.isEmpty)
        #expect(AuthenticationMethod.managedIdentityResourceID("resource").environment["AZCOPY_MSI_RESOURCE_STRING"] == "resource")
        #expect(AuthenticationMethod.sas.environment.isEmpty)
        #expect(AuthenticationMethod.accountKeyDerivedSAS.environment.isEmpty)
    }

    @Test("login arguments cover user and service principal certificate")
    func loginArgumentVariants() {
        #expect(AuthenticationMethod.userIdentity(tenantID: nil).loginArguments == ["login"])
        #expect(AuthenticationMethod.servicePrincipalCertificate(
            applicationID: "app",
            tenantID: "tenant",
            certificatePath: "/tmp/cert.pem",
            certificatePassword: nil
        ).loginArguments == ["login", "--service-principal", "--application-id", "app", "--certificate-path", "/tmp/cert.pem", "--tenant-id=tenant"])
        #expect(AuthenticationMethod.sas.loginArguments == nil)
    }

    @Test("legacy Object ID is rejected with migration guidance")
    func legacyObjectID() {
        let method = AuthenticationMethod.managedIdentityObjectID("legacy-object")
        #expect(throws: AuthenticationMethod.ValidationError.managedIdentityObjectIDUnsupported) {
            try method.validate()
        }
        let guidance = AuthenticationMethod.ValidationError.managedIdentityObjectIDUnsupported.errorDescription ?? ""
        #expect(guidance.contains("Client ID"))
        #expect(guidance.contains("Resource ID"))
        #expect(!guidance.contains("legacy-object"))
        #expect(method.loginArguments == nil)
        #expect(method.environment.isEmpty)
    }

    @Test("required credential fields reject empty and whitespace-only values")
    func requiredFields() {
        for empty in ["", " \n\t"] {
            let cases: [(AuthenticationMethod, String)] = [
                (.servicePrincipalSecret(applicationID: empty, tenantID: "tenant", clientSecret: "secret"), "Application ID"),
                (.servicePrincipalSecret(applicationID: "app", tenantID: empty, clientSecret: "secret"), "Tenant ID"),
                (.servicePrincipalSecret(applicationID: "app", tenantID: "tenant", clientSecret: empty), "Client secret"),
                (.servicePrincipalCertificate(applicationID: empty, tenantID: "tenant", certificatePath: "/cert.pem", certificatePassword: nil), "Application ID"),
                (.servicePrincipalCertificate(applicationID: "app", tenantID: empty, certificatePath: "/cert.pem", certificatePassword: nil), "Tenant ID"),
                (.servicePrincipalCertificate(applicationID: "app", tenantID: "tenant", certificatePath: empty, certificatePassword: nil), "Certificate path"),
                (.managedIdentityClientID(empty), "Managed identity Client ID"),
                (.managedIdentityResourceID(empty), "Managed identity Resource ID")
            ]
            for (method, field) in cases {
                #expect(throws: AuthenticationMethod.ValidationError.missingRequiredField(field)) {
                    try method.validate()
                }
            }
        }
    }

    @Test("optional tenant and certificate password remain optional")
    func validMethods() throws {
        let methods: [AuthenticationMethod] = [
            .userIdentity(tenantID: nil), .userIdentity(tenantID: " "),
            .deviceCodeEnvironment, .azureCLI(tenantID: nil), .azurePowerShell(tenantID: ""),
            .servicePrincipalSecret(applicationID: "app", tenantID: "tenant", clientSecret: " secret with spaces "),
            .servicePrincipalCertificate(applicationID: "app", tenantID: "tenant", certificatePath: "/cert.pem", certificatePassword: nil),
            .servicePrincipalCertificate(applicationID: "app", tenantID: "tenant", certificatePath: "/cert.pem", certificatePassword: ""),
            .managedIdentitySystem, .managedIdentityClientID("client"), .managedIdentityResourceID("resource"), .sas
        ]
        for method in methods { try method.validate() }
        #expect(AuthenticationMethod.userIdentity(tenantID: " ").environment.isEmpty)
        #expect(AuthenticationMethod.userIdentity(tenantID: " tenant ").environment == ["AZCOPY_TENANT_ID": "tenant"])
        #expect(AuthenticationMethod.userIdentity(tenantID: " tenant ").loginArguments == ["login", "--tenant-id=tenant"])
        #expect(AuthenticationMethod.userIdentity(tenantID: " ").loginArguments == ["login"])
    }

    @Test("null credentials and direct account keys are rejected")
    func invalidCredentials() {
        #expect(throws: AuthenticationMethod.ValidationError.invalidField("Tenant ID")) {
            try AuthenticationMethod.userIdentity(tenantID: "tenant\0").validate()
        }
        #expect(throws: AuthenticationMethod.ValidationError.invalidField("Certificate password")) {
            try AuthenticationMethod.servicePrincipalCertificate(
                applicationID: "app", tenantID: "tenant", certificatePath: "/cert.pem", certificatePassword: "\0"
            ).validate()
        }
        #expect(throws: AuthenticationMethod.ValidationError.accountKeyDirectAuthUnsupported) {
            try AuthenticationMethod.accountKeyDerivedSAS.validate()
        }
    }

    @Test("tenant-aware device code preserves explicit and automatic login tenant")
    func deviceCodeTenant() throws {
        let method = AuthenticationMethod.deviceCode(tenantID: " tenant ")
        try method.validate()
        #expect(method.environment == ["AZCOPY_AUTO_LOGIN_TYPE": "DEVICE", "AZCOPY_TENANT_ID": "tenant"])
        #expect(method.loginArguments == ["login", "--tenant-id=tenant"])
        #expect(AuthenticationMethod.deviceCode(tenantID: nil).environment == AuthenticationMethod.deviceCodeEnvironment.environment)
        #expect(AuthenticationMethod.deviceCode(tenantID: " ").loginArguments == ["login"])
        #expect(throws: AuthenticationMethod.ValidationError.invalidField("Tenant ID")) {
            try AuthenticationMethod.deviceCode(tenantID: "tenant\0").validate()
        }
    }
}
