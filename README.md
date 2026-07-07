# azcopy-mac-ui

Native macOS GUI for [AzCopy](https://github.com/Azure/azure-storage-azcopy), written in Swift 6.

## Status

Initial version: `0.1.0`.

This app does not bundle AzCopy. Install AzCopy with Homebrew:

```sh
brew install azcopy
```

The app resolves `/opt/homebrew/bin/azcopy` first on Apple Silicon and treats Homebrew `azcopy` as a distribution dependency.

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon / arm64
- Xcode 26 or newer with Swift 6
- Homebrew `azcopy`

## Development

```sh
swift test --enable-code-coverage
Scripts/check-coverage.sh
Scripts/security-review.sh
xcodebuild -project AzCopyMacUI.xcodeproj -scheme AzCopyMacUI -destination 'platform=macOS,arch=arm64' build
```

## Distribution

Release builds are designed for a custom Homebrew tap cask. Release artifacts must be signed with hardened runtime, notarized, stapled, and checksumed before cask publication.

## License

MIT.

