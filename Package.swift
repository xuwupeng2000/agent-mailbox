// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AgentMailbox",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentMailbox", targets: ["AgentMailbox"]),
               .executable(name: "mailbox", targets: ["MailboxCLI"])],
    targets: [.executableTarget(name: "MailboxCLI", path: "cli"),
              .executableTarget(
        name: "AgentMailbox",
        path: "ios/AgentMailbox",
        exclude: ["Assets.xcassets", "en.lproj", "zh-Hans.lproj", "zh-Hant.lproj"]
    )])
