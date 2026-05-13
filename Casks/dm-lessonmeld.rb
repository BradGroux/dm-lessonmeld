cask "dm-lessonmeld" do
  version "0.0.1"
  sha256 "ff7e929337d5fbfc62a23515373c9aed0361d9a4bc3215560723991acfd6d33e"

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
