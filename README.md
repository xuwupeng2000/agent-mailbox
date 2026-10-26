# Agent Mailbox

给智能体看的说明。这是一个本机文本信箱，消息只留在内存里，不写文件。iOS 应用负责显示；命令行负责收发。

## 人看到什么

用 Xcode 打开 `ios/AgentMailbox.xcodeproj`，在 iOS 模拟器里运行 **AgentMailbox**。

- 主界面有两块打字区。谁用 `FROM 名字` 写字，字就出现在谁的那一块，最后一行是 `<<<END>>>`。
- 右上角的帽子图标是菜单。有新对话时，菜单上有红色数字。
- 打开菜单，点「查看两人对话」，看双方已经写完的内容。数字随之清掉。

模拟器和这台 Mac 共用网络。应用打开后，智能体连接 `127.0.0.1:9777`。不要同时再运行 `agent_mailbox.py serve`，同一个端口只能有一个信箱。

## 写完必须放的标记

一条消息的最后一行必须是：

```text
<<<END>>>
```

看见这一行，就表示对方写完了。读上面的正文，然后给对方回一条，自己的消息也以 `<<<END>>>` 结束。

限时等待如果没有消息，会收到单独一行：

```text
<<<TIMEOUT>>>
```

这不是对方写的内容，不要当作对话回复。

## 命令

在仓库根目录执行。把 `cursor` 和 `codex` 换成实际使用的两个名字。

写给对方，并告诉界面是谁在打字：

```bash
python3 agent_mailbox.py write --to cursor --from codex <<'EOF'
谱面先只做一段短句。
EOF
```

命令会自动加上 `<<<END>>>`。不要自己再加一遍。

等对方写完：

```bash
python3 agent_mailbox.py wait --as cursor --timeout 30
```

成功时输出类似：

```text
FROM codex
谱面先只做一段短句。
<<<END>>>
```

`FROM` 后面是说话的人。把它下面、`<<<END>>>` 上面的文字当作正文。

## 直接用 TCP

一次连接只做一件事。写：

```text
WRITE cursor
FROM codex
谱面先只做一段短句。
<<<END>>>
```

信箱回答 `OK`。等：

```text
WAIT cursor
```

或 `WAIT cursor 30`。有消息就返回上面那种正文；超时返回 `<<<TIMEOUT>>>`。

`FROM` 可以省略。省略时界面把说话人显示为「未署名」。主界面只留前两位说话人。

## 不要做的事

- 不要把信箱内容写进游戏仓库或另外的文本文件。
- 不要在应用已经打开时再启动 Python 的 `serve`。
- 不要把 `<<<END>>>` 写进正文中间。第一处结尾标记会结束这条消息。

## 用户发起对话

展开「发起双 Agent 对话」，填写两个不同的英文名称、共同任务和轮数。
Agent A 先发言，一轮表示双方各回复一次。分别分享 A / B 接入说明给两个正在运行且能执行命令的 Agent，然后点开始。

Agent 执行 `wait` 读取消息，收到后思考，再执行 `write` 回复。每次回复必须带 `--from` 和 `--session`（值取自收到消息的 SESSION 行）。随后继续等待。

```bash
python3 agent_mailbox.py wait --as codex --timeout 30
python3 agent_mailbox.py write --to cursor --from codex --session SESSION_ID <<'EOF'
你的回复
EOF
```

`<<<TIMEOUT>>>` 表示继续等待；`<<<STOP>>>` 表示会话结束。`ERR` 表示没有接收回复，保留正文并检查会话编号、收件人和轮次。
暂停会阻止后续消息投递，已经交给 Agent 的消息无法撤回；其回复可以暂存在内存中，继续后再投递。
补充要求送给下一位发言者。结束会清除待投递内容并释放等待者，已显示的对话保留到下一次开始。
最后一条回复会显示在对话记录中，达到轮数后不再交给另一位继续回复。

这套会话控制由 iOS 应用提供；Python `serve` 保留为基础信箱，不提供轮次控制。
信箱不启动模型，不推断思考状态，也不会让已停止的 Agent 自动运行。
当前地址用于同一台 Mac 的 iOS 模拟器；实体 iPhone 不能通过 Mac 的 127.0.0.1 接入。

## 验证记录

- 初始版本：Python TCP 收发 demo 通过。
- 2026-10-26：添加会话控制、轮数限制、SESSION 校验、暂停/继续、用户补充和接入说明。
- 真实模型之间的自动多轮沟通尚待人工接入验证；测试客户端不代表真实 Agent。

本次实际验证：Swift 会话状态检查通过（名称校验、开始、重复开始防护、暂停/继续、结束、重新开始）；Python TCP demo 通过；iOS 模拟器构建、安装、启动和 Mac TCP PING 通过。尚未验证 UI 操作后的完整轮次投递、真实 Agent 多轮交流及人工视觉验收。

复现状态检查：
```bash
DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer xcrun swiftc ios/AgentMailbox/MailboxCenter.swift tests/SessionChecks.swift -o /tmp/mailbox-session-checks
/tmp/mailbox-session-checks
python3 agent_mailbox.py demo
```
