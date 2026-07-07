import Foundation

public protocol FileChecking {
    func isExecutableFile(atPath path: String) -> Bool
}

extension FileManager: FileChecking {}

public struct AzCopyLocator {
    public enum LocatorError: Error, Equatable, LocalizedError {
        case notFound

        public var errorDescription: String? {
            switch self {
            case .notFound:
                "AzCopy was not found. Install it with `brew install azcopy`."
            }
        }
    }

    public static let homebrewAppleSiliconPath = "/opt/homebrew/bin/azcopy"

    private let fileChecker: any FileChecking
    private let environmentPath: String

    public init(
        fileChecker: any FileChecking = FileManager.default,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.fileChecker = fileChecker
        self.environmentPath = environmentPath
    }

    public func locate() throws -> URL {
        if fileChecker.isExecutableFile(atPath: Self.homebrewAppleSiliconPath) {
            return URL(fileURLWithPath: Self.homebrewAppleSiliconPath)
        }

        for directory in environmentPath.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("azcopy").path
            if fileChecker.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        throw LocatorError.notFound
    }

    public func isPreferredHomebrewPath(_ url: URL) -> Bool {
        url.path == Self.homebrewAppleSiliconPath
    }
}
