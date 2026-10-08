cask "3fingers" do
  version "0.1.0"
  sha256 "defdf456dbe22a5982a2ab8aaff3465af95ed78f36a7b867d5f62dd7e57cfd18"

  url "https://github.com/MPalarya/3Fingers/releases/download/v#{version}/3Fingers.dmg"
  name "3Fingers"
  desc "Turns a 3-finger trackpad tap or click into a middle click"
  homepage "https://github.com/MPalarya/3Fingers"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "3Fingers.app"

  # Release builds are not notarized; clear quarantine so Gatekeeper doesn't block launch.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "3Fingers.app"], chdir: "{{appdir}}"
  end

  uninstall quit: "com.3fingers.app"

  zap trash: "~/Library/Preferences/com.3fingers.app.plist"
end
