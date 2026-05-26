cask "dm-lessonmeld" do
  version "0.0.12"
  sha256 "f546c95fb2c3c5b979fae72a4a5de5d76ac55d3fa0d1eaa3893187fc9f07477b"

  url "https://github.com/BradGroux/dm-lessonmeld/releases/download/v#{version}/dm-lessonmeld-#{version}-macos.zip"
  name "Digital Meld LessonMeld"
  desc "Local-first recording suite for curriculum builders"
  homepage "https://github.com/BradGroux/dm-lessonmeld"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Digital Meld LessonMeld.app"

  zap trash: "~/Library/Preferences/io.digitalmeld.dm-lessonmeld.plist"
end
