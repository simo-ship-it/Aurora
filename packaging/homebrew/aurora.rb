cask "aurora" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/simo-ship-it/Aurora/releases/download/v#{version}/Aurora-#{version}.zip"
  name "Aurora"
  desc "Markdown editor that renders as you type"
  homepage "https://github.com/simo-ship-it/Aurora"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Aurora.app"

  zap trash: [
    "~/Library/Preferences/io.github.simo-ship-it.Aurora.plist",
    "~/Library/Saved Application State/io.github.simo-ship-it.Aurora.savedState",
  ]
end
