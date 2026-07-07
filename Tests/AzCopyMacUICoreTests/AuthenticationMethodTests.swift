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
        #expect(AuthenticationMethod.managedIdentityObjectID("object").loginArguments == ["login", "--identity", "--identity-object-id", "object"])
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
        #expect(AuthenticationMethod.managedIdentityObjectID("object").environment["AZCOPY_MSI_OBJECT_ID"] == "object")
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
}
