cask "azcopy-mac-ui" do
  version "0.2.1"
  sha256 "deee0af386acae1ab9c4cd03481000fc71adea3d4900ca0c1218079f1b015d12"

  url "https://github.com/rioriost/azcopy-mac-ui/releases/download/v#{version}/azcopy-mac-ui-#{version}-macos-arm64.zip"
  name "AzCopy Mac UI"
  desc "GUI for Azure AzCopy transfers"
  homepage "https://github.com/rioriost/azcopy-mac-ui"

  depends_on arch: :arm64
  depends_on macos: :sonoma
  depends_on formula: "azcopy"

  app "AzCopy Mac UI.app"

  zap trash: [
    "~/Library/Application Support/AzCopy Mac UI",
    "~/Library/Logs/AzCopy Mac UI",
    "~/Library/Preferences/com.github.azcopy-mac-ui.plist",
  ]
end
