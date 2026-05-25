cask "dm-lessonmeld" do
  version "0.0.5"
  sha256 "10ac1a4f1cd11adf4b3c918d0f3ce1bf6676665f4b2dec78440eb02d3f2f4ef5"

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
