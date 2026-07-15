cask "dm-lessonmeld" do
  version "0.0.12"
  sha256 "47f387175ff1faadaa10db714a597a74d403fa21f5040f4aec22fb02e7ef61c6"

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

  # v0.0.12 predates the bundled CLI. Keep that published cask installable,
  # then expose dmlesson for every archive built from the current packaging flow.
  binary "#{appdir}/Digital Meld LessonMeld.app/Contents/Resources/bin/dmlesson" if version >= "0.0.13"

  zap trash: "~/Library/Preferences/io.digitalmeld.dm-lessonmeld.plist"
end
