cask "dm-lessonmeld" do
  version "0.0.7"
  sha256 "09e151425a9709b50ff97d1541e1c54c1e2f532114d568ee01f021aa676c9db9"

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
