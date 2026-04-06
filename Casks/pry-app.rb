cask "pry-app" do
  version "1.0.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/fsaldivar-dev/pry/releases/download/v#{version}/Pry-#{version}.dmg"
  name "Pry"
  desc "macOS HTTP/HTTPS debugging proxy with GUI"
  homepage "https://github.com/fsaldivar-dev/pry"

  depends_on macos: ">= :sonoma"

  app "Pry.app"
  binary "#{appdir}/Pry.app/Contents/MacOS/pry"

  zap trash: [
    "~/.pry",
    "~/.prywatch",
    "~/.pryconfig",
    "/tmp/pry.*",
  ]
end
