# Agent Mailbox

[简体中文](README.md) · English · [Project website / GitHub Pages](https://xuwupeng2000.github.io/agent-mailbox/en.html)

A Mac app you can open with a double-click. Connect two running AI agents to a local text mailbox, assign a shared task, and watch a turn-based discussion. Pause delivery, add instructions, search history, or end the conversation.

**The app and its agent messaging tool are native Swift executables bundled into one `.app`. Normal use requires no Python, pip, terminal setup, or repository checkout.** Models and running agents are supplied by their own applications.

## Requirements

| Scenario | Requirements |
| --- | --- |
| Run the packaged app | macOS 14+; the current local package is Apple Silicon (arm64) |
| Agent collaboration | Two running agents allowed to execute local commands, such as Cursor and Codex; give each its generated connection note |
| Local connection | Available loopback TCP port `127.0.0.1:9777`; run only one mailbox |
| Build from source | macOS 14+, full Xcode (verified with Xcode 27.0), Swift toolchain and macOS SDK; output architecture follows the build machine |
| Optional iOS development | Full Xcode and an iOS simulator runtime; deployment target iOS 18+. Separate from the Mac usage flow |

Running the app or bundled client needs no Python, Node.js, Docker, database, or model API. Xcode and Swift are required only to build from source. Agent accounts, models and network access are managed by their respective tools.

## Use: double-click to open

1. Put `Agent Mailbox.app` in Applications or another folder and double-click it. Confirm that the port is open.
2. Expand the conversation controls. Enter two different participant names (for example `codex` and `cursor`), a shared task, and 1–20 rounds.
3. Give each running agent its own connection note from the app. It includes the absolute path to the bundled native tool; users do not need to type messaging commands.
4. Start the conversation. View both participants and open conversation history from the hat menu to search previous messages.
5. Pause, resume, add an instruction, or end as needed. At the end, each agent reports its completed actions to the user. Ending again skips reports.

Use the mailbox only for collaboration tasks explicitly assigned by the user. Keep ordinary user chat in its original window. After moving the app, regenerate the connection notes so their paths remain valid.

## Build and run from source

From the repository root:

```bash
bash scripts/build-macos.sh
open "dist/Agent Mailbox.app"
```

The script builds both native executables and produces:

- `dist/Agent Mailbox.app`: the complete app, ready to open.
- `dist/Agent-Mailbox-macOS.zip`: a copyable app package for compatible Macs.
- `dist/SHA256SUMS.txt`: the archive checksum.

If the wrong Xcode is selected, set `DEVELOPER_DIR` to your full Xcode installation's `Contents/Developer` directory. Packaging uses the existing `.icns` resource without Python. The package is ad-hoc signed and has not been notarized by Apple.

## How communication works

The app provides the SwiftUI window, menu bar item, in-memory recipient queues, and session controller. The bundled native `mailbox` tool exchanges UTF-8 messages over loopback TCP. Each agent continues using its own model and tools.

```mermaid
sequenceDiagram
    actor U as User
    participant M as Agent Mailbox
    participant A as Agent A
    participant B as Agent B
    U->>M: Set task, names and rounds; start
    A->>M: WAIT A (blocks when empty)
    M-->>A: Task with SESSION
    A->>M: WRITE B with sender and SESSION
    A->>M: WAIT A
    B->>M: WAIT B
    M-->>B: Deliver A's complete message
    B->>M: WRITE A with sender and SESSION
    Note over M: One reply from each agent is one round
    U->>M: Pause, resume, add instructions or end
    M-->>A: Request actions report at end
    M-->>B: Request actions report at end
    A->>M: Report own actions to user
    B->>M: Report own actions to user
    M-->>A: Subsequent WAIT returns STOP
    M-->>B: Subsequent WAIT returns STOP
```

`write` submits a complete message; `wait` blocks until a message, timeout or stop. Blocking itself does not call a model or consume model tokens; processing and replies are billed by each agent platform. A participant name alone does not connect or wake an agent.

The session controller validates sender, recipient, turn and SESSION. A speaks first; one reply from each participant is one round. Pausing prevents further delivery but cannot recall messages already received. The round limit or an explicit end requests both agents' actions reports before stopping.

Messages and history live only in memory and disappear when the app quits. Closing the Mac window keeps the app in the menu bar. Typing animation is presentation; the reading status means a waiting connection exists, not that a model is thinking.

## Agent connection (agents execute these commands)

Use the connection notes generated by the app and [AGENT_README.md](AGENT_README.md). The native tool is at `Agent Mailbox.app/Contents/MacOS/mailbox`; rules are at `Contents/Resources/AGENT_README.md`.

For an app installed in Applications, an agent can run this from any working directory:

```bash
"/Applications/Agent Mailbox.app/Contents/MacOS/mailbox" wait --as codex --timeout 30
```

This is not how the user launches the app. Users open the app and share tasks and connection notes. The client supports `wait`, `write`, `ping` and `--help`, appends `<<<END>>>` automatically, and requires the received SESSION for managed-session replies. It does not use a Python interpreter.

## Limits

- The Mac listener binds to loopback. There is no authentication or encryption; SESSION is not a credential.
- The app does not include models, take over chats, or wake stopped agents automatically.
- The iOS project remains for development. A physical iPhone cannot access the Mac through its own `127.0.0.1`; the iOS listener is not explicitly restricted to loopback.
- `agent_mailbox.py` is retained for legacy developer compatibility. It is not bundled or needed by the new Mac app. Optional Python development tests and icon regeneration have separate tooling requirements.
- Historical screenshots may contain old Python commands. Use the running app's native connection notes for current instructions.

## Source layout

```text
Package.swift                 Native app and client targets
cli/main.swift                Native messaging client (no Python)
ios/AgentMailbox/             Shared SwiftUI UI, mailbox, sessions and translations
AGENT_README.md                Rules for collaborating agents
macos/                        Icon resources
scripts/build-macos.sh        Build, package and ad-hoc sign
docs/index.html / en.html      Chinese and English project pages
```

## Validation

Executed in this iteration on 2026-10-26: Mac release build and signature verification, plus native client protocol checks for UTF-8/emoji, fragmented replies, SESSION forwarding, blocking delivery, timeout, STOP, server rejection, truncation, invalid input and execution with an empty tool PATH. The protocol fixtures use Python for developer testing only; the product does not.

Existing Swift session checks and native connection notes for all three languages were rerun and passed in this iteration. The 1024-wide history sheet was visually checked in the previous iteration. Light/dark menu-bar switching, every language's visual layout, and a full real-agent multi-round session have not all been accepted. Build success does not imply those checks passed.
