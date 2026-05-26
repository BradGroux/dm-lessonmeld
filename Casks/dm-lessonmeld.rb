cask "dm-lessonmeld" do
  version "0.0.11"
  sha256 "a20a81fcbad2d2060944ad15034798d0915d47fbe989d15d97da65bce2bb3207"

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
