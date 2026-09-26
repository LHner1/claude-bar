// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Menu bar app
        .executableTarget(name: "ClaudeBar", path: "Sources/ClaudeBar"),
        // Claude Code status line helper (reads the statusLine JSON and stores the limits)
        .executableTarget(name: "claude-bar-statusline", path: "Sources/StatusLine"),
    ]
)
