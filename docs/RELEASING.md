# 构建、签名与发布 / Build, sign and release

普通用户只需下载应用，不需要执行本文中的步骤。These steps are for the developer, not end users.

## 证书 / Certificate

站外分发使用 **Developer ID Application**，不是 **Apple Development**。在 Xcode → Settings → Apple Accounts 中选择正确团队，打开 Manage Certificates，创建或导入 Developer ID Application。团队需要相应的 Apple Developer Program 资格与权限。

如果证书来自另一台电脑，应导入包含私钥的 `.p12`；只有 `.cer` 而没有配套私钥不能签名。不要把私钥、`.p12` 密码或公证登录密码提交到 Git 或聊天中。

Outside-App-Store distribution uses a **Developer ID Application** identity, including its private key. Apple Development is for development, not this distribution flow. Select your team in Xcode's account settings and use Manage Certificates to create/import the correct identity. Import a `.p12` with its private key when moving an identity from another Mac.

检查可用身份 / Check available identities:

```bash
security find-identity -v -p codesigning
```

## 构建并签名 / Build and sign

```bash
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAM_ID)' bash scripts/build-macos.sh
```

默认同时构建 arm64 和 x86_64，再合并为通用二进制。客户端与应用均单独签名并启用 Hardened Runtime 和时间戳。没有提供 SIGNING_IDENTITY 时只做本机临时签名，不应把它称为已公证发行包。

The script builds both architectures and signs the helper and app with Hardened Runtime and a secure timestamp. Without SIGNING_IDENTITY it produces an ad-hoc local build, not a notarized public package.

## 配置公证 / Configure notarization

在开发者自己的终端运行一次，按交互提示填 Apple ID、正确团队 ID 和 **App 专用密码**。不要把这些密码写进命令、Git 或聊天。

Run this once in your own terminal and answer the prompts with your Apple ID, the correct Team ID, and an **app-specific password**. Credentials are saved in the local Keychain.

```bash
xcrun notarytool store-credentials agent-mailbox
```

如果团队已有 App Store Connect API key，也可以使用 notarytool 的 API-key 凭据方式；请遵循 Apple 官方文档，避免把密钥加入仓库。

Submit, wait for Apple's result, staple the ticket, check Gatekeeper, and recreate the ZIP:

```bash
NOTARY_PROFILE=agent-mailbox bash scripts/notarize-macos.sh
```

脚本只在 Apple 返回 Accepted 后继续装订公证票据并重新压缩。后续不要再修改应用内部文件或重签名，否则需重新公证。开发者证书不等于公证；只有这一步完成后才能称为已公证。

A signing certificate alone is not notarization. The script proceeds only after Apple returns Accepted. Do not modify or re-sign the app after stapling without notarizing again.

## 发布前 / Before publishing

- 检查 `git diff --check`，运行 Swift 会话检查和原生客户端协议检查。
- 从最终 ZIP 独立解压，验证签名、两种架构、原生工具，以及无需 Python/仓库的启动路径。
- 在 GitHub Release 创建对应版本标签，上传 `dist/Agent-Mailbox-0.1.0-macOS-universal.zip` 和 `dist/SHA256SUMS.txt`。
- 发行说明如实标注支持系统、签名和公证结果、已执行检查，以及 Intel 实机未验证等限制。

Publish the source revision as a versioned GitHub Release with the universal ZIP and checksum. Report actual validation only. The current Intel binary is cross-built, not tested on Intel hardware.

Apple references: [Developer ID](https://developer.apple.com/developer-id/) · [Notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) · [notarytool credentials](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).
