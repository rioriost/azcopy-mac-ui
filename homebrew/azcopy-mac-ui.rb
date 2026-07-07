cask "azcopy-mac-ui" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/OWNER/azcopy-mac-ui/releases/download/v#{version}/azcopy-mac-ui-#{version}-macos-arm64.notarized.zip"
  name "AzCopy Mac UI"
  desc "Native macOS GUI for Azure AzCopy"
  homepage "https://github.com/OWNER/azcopy-mac-ui"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"
  depends_on formula: "azcopy"

  app "AzCopy Mac UI.app"

  zap trash: [
    "~/Library/Preferences/com.github.azcopy-mac-ui.plist",
    "~/Library/Application Support/AzCopy Mac UI",
    "~/Library/Logs/AzCopy Mac UI"
  ]
end

