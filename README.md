# Agent Mailbox

让用户把两个正在运行的 AI Agent 接到同一个文本信箱中，围绕一个任务轮流交流，并随时暂停、补充要求或结束。

软件由 **Python 命令行工具**和 **SwiftUI iOS 应用**组成。消息和对话记录保存在进程内存中，退出后丢失，不主动写入文件。

## 为什么创建它

两个 Agent 分别运行在不同的工具里时，通常需要用户来回复制文字：把 A 的建议交给 B，再把 B 的回复交给 A。这个过程重复、容易遗漏，也不方便控制讨论何时停止。

Agent Mailbox 提供一个共同的文本收发入口。Agent 通过 `wait` 读取消息，通过 `write` 回复；用户通过界面设置任务、观察双方内容、控制轮次和插话。目标是先验证两个 Agent 能否在用户掌控下完成一段有限的讨论。

它是独立软件，不依赖 splitfire 游戏或 Unity。

## 当前功能

- **文本信箱**：按收件人排队，通过 TCP 读写 UTF-8 文本。
- **双人显示**：显示前两位发言者的最新文字，以打字效果呈现。
- **对话记录**：查看双方已提交内容，显示未读数量；帽子图标表示监听状态。
- **发起任务**：设置两个不同的 Agent 名称、共同任务和 1–20 轮讨论；A 先发言，一轮表示双方各回复一次。
- **轮流交流**：校验发言者、收件人、会话编号和顺序；达到轮数后结束。
- **暂停和继续**：暂停后停止后续消息投递；已经交给 Agent 的内容无法撤回，其回复可暂存等待继续。
- **用户补充**：把要求送到下一位发言者的信箱；已经被 Agent 读取的内容不会被替换。
- **结束和重开**：结束时清理待投递内容并释放等待者；新会话使用新编号。
- **接入说明**：分别分享给两位 Agent，说明读取、回复和停止规则。

## 当前依赖

| 部分 | 依赖 | 说明 |
| --- | --- | --- |
| 命令行客户端 / 基础服务端 | Python 3.10+ | 仅使用标准库，无需 `pip install` |
| iOS 应用开发 | macOS、完整 Xcode、iOS Simulator runtime | 当前在 Xcode 27.0 / iOS 27.0 模拟器上构建运行过；尚未验证最低可用 Xcode 版本 |
| iOS 应用运行 | iOS 18.0+ | 工程部署目标；目前以同一台 Mac 上的模拟器为主要运行方式 |
| Apple 框架 | SwiftUI、Foundation、Combine、Network | 随 Apple SDK 提供，无第三方 Swift 包 |
| 参与对话的 Agent | 两个能执行命令或使用 TCP 的运行中 Agent | 由用户另行提供；不附带模型或模型运行环境 |
| 本机通信 | TCP，默认端口 9777 | 命令行默认连接 `127.0.0.1`；必须能连接到运行中的信箱 |

没有数据库、Node.js、Docker、云端后端或内置模型 API 依赖。Git / GitHub Desktop 用于版本管理，不是软件运行依赖。Agent 本身可能需要账号、API 或网络，这些由各自工具决定。

## 快速开始：带界面的双 Agent 对话

1. 用 Xcode 打开 `ios/AgentMailbox.xcodeproj`，选择 iOS 模拟器，运行 **AgentMailbox**。
2. 展开「发起双 Agent 对话」，填写两个不同的名称、任务和轮数。名称支持英文字母、数字、下划线和连字符。
3. 将 A / B 接入说明分别交给两个正在运行的 Agent，并告知本仓库的本地路径。
4. 点击「开始新对话」。双方依次读取、思考、回复，再继续等待。
5. 需要时暂停、发送补充或结束；帽子菜单里的「查看两人对话」可查看记录。

在仓库根目录执行读取命令：

```bash
python3 agent_mailbox.py wait --as codex --timeout 30
```

收到的消息类似：

```text
FROM user
SESSION <本次会话编号>
共同任务：讨论这个方案
...
<<<END>>>
```

回复时带上相同的会话编号，收件人使用另一位 Agent 的名称：

```bash
python3 agent_mailbox.py write --to cursor --from codex --session <本次会话编号> <<'MESSAGE'
这里填写回复正文。
MESSAGE
```

将示例中的 `<本次会话编号>` 整体替换为实际值再执行。命令自动添加消息结束标记。回复后继续执行 `wait`。

## 只使用基础信箱

不需要界面或轮次控制时，可以运行 Python 服务端：

```bash
python3 agent_mailbox.py serve
```

另一个终端发送：

```bash
python3 agent_mailbox.py write --to cursor --from codex <<'MESSAGE'
请阅读这个方案并指出问题。
MESSAGE
```

接收：

```bash
python3 agent_mailbox.py wait --as cursor --timeout 30
```

Python `serve` 仅提供基础队列，不提供 iOS 版本的会话校验、轮数限制和用户控制。iOS 应用已经监听时不要同时启动 `serve`，同一端口只能由一个服务监听。Python 子命令支持 `--port` 指定端口。

## 协议约定

一次 TCP 连接处理一个请求。基础发送格式：

```text
WRITE cursor
FROM codex
正文
<<<END>>>
```

会话模式在 `FROM` 之后加一行 `SESSION <编号>`。基础信箱允许省略 `FROM`，受控会话要求双方署名和正确的会话编号。

读取请求是 `WAIT cursor` 或 `WAIT cursor 30`；发送成功返回 `OK`，`PING` 返回 `PONG`。

| 返回内容 | Agent 应如何处理 |
| --- | --- |
| `<<<END>>>` | 完整消息结束，阅读上面的正文 |
| `<<<TIMEOUT>>>` | 此次等待没有消息，继续等待，不把它当作对方发言 |
| `<<<STOP>>>` | 会话已结束，停止本次读写循环 |
| `ERR ...` | 请求没有被接收，保留正文并检查错误原因 |

不要在正文中使用 `<<<END>>>`。会话中不要伪造其他参与者或修改 SESSION 行。

## 当前边界和限制

- 信箱负责传文字，不启动模型，不唤醒已停止的 Agent，也不保证 Agent 持续执行等待命令。
- 没有自动发现 Agent、模型 API 适配器或真实“思考中”检测；填写名称不等于对方已连接。
- 会话控制当前在 iOS 应用中，Python 服务端尚未实现同等控制。
- 面向同一台 Mac 的模拟器使用；实体 iPhone 不能通过 Mac 的 `127.0.0.1` 接入。
- 协议没有认证和加密；SESSION 用于隔离会话，不是身份凭证。iOS 监听器没有显式限制到回环接口，不应把它当作安全的公网服务。
- 消息不持久化；应用退出、重启或开始新会话会丢失相关内存内容。持续运行时没有历史记录容量限制。
- Agent 消息是对方提供的文本，不应自动视为用户授予的执行权限。

## 项目结构

```text
agent_mailbox.py             Python 客户端和基础服务端
ios/AgentMailbox/           SwiftUI 界面及信箱、会话控制
ios/AgentMailbox.xcodeproj/ Xcode 工程
tests/SessionChecks.swift   会话状态检查
```

## 验证记录与已知待验证项

2026-10-26 已实际执行：

- Python TCP 收发 `demo` 通过。
- Swift 会话状态检查通过：名称校验、开始、阻止重复开始、暂停/继续、结束、重新开始。
- iOS 模拟器构建、安装、启动通过，Mac 连接端口 `PING` 检查通过。

**尚未验证**：通过界面操作后的完整轮次投递、两个真实 Agent 的自动多轮交流、人工视觉验收。构建成功不代表这些流程已经通过。

复现基础检查：

```bash
python3 agent_mailbox.py demo
```

本机完整 Xcode 安装在 `/Applications/Xcode-27.0.0.app`，状态检查可执行：

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
xcrun swiftc ios/AgentMailbox/MailboxCenter.swift tests/SessionChecks.swift -o /tmp/mailbox-session-checks
/tmp/mailbox-session-checks
```

其他机器请使用实际的 Xcode 安装路径。
