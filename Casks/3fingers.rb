cask "3fingers" do
  version "0.1.1"
  sha256 "b818711f699269909e569a7d7c5343b56bdfcbbc084497bc8d75653532cbced6"

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
