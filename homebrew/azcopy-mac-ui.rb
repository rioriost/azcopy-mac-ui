cask "azcopy-mac-ui" do
  version "0.2.2"
  sha256 "612f9f78ba9c5b932c5054744de7cd2e46bf32a46809a83be1284a8e7c32c3df"

  url "https://github.com/rioriost/azcopy-mac-ui/releases/download/v#{version}/azcopy-mac-ui-#{version}-macos-arm64.zip"
  name "AzCopy Mac UI"
  desc "GUI for Azure AzCopy transfers"
  homepage "https://github.com/rioriost/azcopy-mac-ui"

  depends_on arch: :arm64
  depends_on formula: "azcopy"
  depends_on macos: :sonoma

  app "AzCopy Mac UI.app"

  zap trash: [
    "~/Library/Application Support/AzCopy Mac UI",
    "~/Library/Logs/AzCopy Mac UI",
    "~/Library/Preferences/com.github.azcopy-mac-ui.plist",
  ]
end
