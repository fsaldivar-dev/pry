class Pry < Formula
  desc "HTTP/HTTPS proxy CLI for iOS devs — Swift puro, un binario"
  homepage "https://github.com/fsaldivar-dev/pry"
  url "https://github.com/fsaldivar-dev/pry/archive/refs/tags/v0.5.0.tar.gz"
  sha256 ""  # Update with actual sha256 after release
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "-c", "release",
           "--disable-sandbox",
           "--arch", "arm64",
           "--arch", "x86_64"
    bin.install ".build/release/pry"
  end

  test do
    assert_match "Pry", shell_output("#{bin}/pry help")
  end
end
