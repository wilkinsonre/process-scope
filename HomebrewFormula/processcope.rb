cask "processcope" do
  version "0.3.0"
  sha256 "TODO_UPDATED_BY_RELEASE_WORKFLOW"

  url "https://github.com/wilkinsonre/process-scope/releases/download/v#{version}/ProcessScope.dmg"
  name "ProcessScope"
  desc "Native macOS system monitor with deep process introspection"
  homepage "https://github.com/wilkinsonre/process-scope"

  depends_on macos: ">= :sequoia"

  app "ProcessScope.app"

  zap trash: [
    "~/.processscope",
    "~/Library/Preferences/com.processscope.app.plist",
  ]
end
