import Foundation
import Network

struct DialogueTurn: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let recipient: String
    let text: String
}

@MainActor
final class MailboxCenter: ObservableObject {
    static let port: UInt16 = 9777
    static let sentinel = "<<<END>>>"
    static let timeoutMark = "<<<TIMEOUT>>>"

    @Published var status = "正在打开端口"
    @Published var panels: [String: String] = [:]
    @Published var order: [String] = []
    @Published var turns: [DialogueTurn] = []
    @Published var unread = 0
    @Published var conversationOpen = false
    @Published var isListening = false

    private var listener: NWListener?
    private struct Waiter {
        let id: UUID
        let resume: (String) -> Void
    }

    private var queues: [String: [String]] = [:]
    private var waiters: [String: [Waiter]] = [:]
    private var animation: Task<Void, Never>?
    private var pending: [DialogueTurn] = []

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.apply(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = "端口没有打开：\(error.localizedDescription)"
        }
    }

    func markConversationRead() {
        unread = 0
    }

    private func apply(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            status = "127.0.0.1:\(Self.port) 已打开，只在内存里"
        case .failed(let error):
            isListening = false
            status = "端口没有打开：\(error.localizedDescription)"
        case .waiting(let error):
            isListening = false
            status = "端口等待中：\(error.localizedDescription)"
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var next = buffer
                if let data {
                    next.append(data)
                }
                if let error {
                    self.reply(connection, "ERR \(error.localizedDescription)")
                    return
                }
                if self.handle(connection, buffer: &next) {
                    return
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                if next.count > 256 * 1024 {
                    self.reply(connection, "ERR message too large")
                    return
                }
                self.receive(connection, buffer: next)
            }
        }
    }

    private func handle(_ connection: NWConnection, buffer: inout Data) -> Bool {
        guard let text = String(data: buffer, encoding: .utf8), let newline = text.firstIndex(of: "\n") else {
            return false
        }
        let first = String(text[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = first.split(separator: " ")
        guard let command = parts.first?.uppercased() else { return false }
        if command == "PING" {
            reply(connection, "PONG")
            return true
        }
        if command == "WAIT", parts.count == 2 || parts.count == 3 {
            let name = String(parts[1])
            let timeout = parts.count == 3 ? Double(parts[2]) : nil
            wait(connection, recipient: name, timeout: timeout)
            return true
        }
        if command == "WRITE", parts.count == 2 {
            let rest = String(text[text.index(after: newline)...])
            guard let ended = completeWrite(rest) else { return false }
            let recipient = String(parts[1])
            store(recipient: recipient, wire: ended.wire, sender: ended.sender, spoken: ended.spoken)
            reply(connection, "OK")
            return true
        }
        reply(connection, "ERR expected WRITE <name>, WAIT <name> [seconds], or PING")
        return true
    }

    private func completeWrite(_ rest: String) -> (wire: String, sender: String, spoken: String)? {
        let ended = Self.sentinel + "\n"
        let bare = rest.hasSuffix(Self.sentinel) || rest.hasSuffix(Self.sentinel + "\r")
        guard rest.contains(ended) || bare else { return nil }
        var wire = rest.trimmingCharacters(in: .newlines)
        if !wire.hasSuffix(Self.sentinel) {
            wire += "\n" + Self.sentinel
        }
        var lines = wire.components(separatedBy: "\n")
        var sender = "未署名"
        if lines.first?.hasPrefix("FROM ") == true {
            sender = String(lines.removeFirst().dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if sender.isEmpty { sender = "未署名" }
        }
        if lines.last == Self.sentinel {
            lines.removeLast()
        }
        return (wire, sender, lines.joined(separator: "\n"))
    }

    private func store(recipient: String, wire: String, sender: String, spoken: String) {
        if var waiting = waiters[recipient], !waiting.isEmpty {
            let waiter = waiting.removeFirst()
            waiters[recipient] = waiting
            waiter.resume(wire)
        } else {
            queues[recipient, default: []].append(wire)
        }
        let turn = DialogueTurn(sender: sender, recipient: recipient, text: spoken)
        turns.append(turn)
        if !conversationOpen {
            unread += 1
        }
        remember(sender)
        pending.append(turn)
        pump()
    }

    private func remember(_ name: String) {
        guard !order.contains(name) else { return }
        order.append(name)
        if panels[name] == nil {
            panels[name] = ""
        }
    }

    private func pump() {
        guard animation == nil, !pending.isEmpty else { return }
        let turn = pending.removeFirst()
        animation = Task { [weak self] in
            guard let self else { return }
            let characters = Array(turn.text)
            let step = max(1, characters.count / 48)
            var shown = ""
            var index = 0
            while index < characters.count {
                let end = min(characters.count, index + step)
                shown.append(contentsOf: characters[index..<end])
                index = end
                self.panels[turn.sender] = shown
                try? await Task.sleep(nanoseconds: 28_000_000)
            }
            self.panels[turn.sender] = shown.isEmpty ? Self.sentinel : shown + "\n" + Self.sentinel
            self.animation = nil
            self.pump()
        }
    }

    private func wait(_ connection: NWConnection, recipient: String, timeout: Double?) {
        if var queued = queues[recipient], !queued.isEmpty {
            let message = queued.removeFirst()
            queues[recipient] = queued
            reply(connection, message)
            return
        }
        let waiter = Waiter(id: UUID()) { [weak self] message in
            self?.reply(connection, message)
        }
        waiters[recipient, default: []].append(waiter)
        guard let timeout else { return }
        let waiterID = waiter.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.cancelWait(waiterID, recipient: recipient)
        }
    }

    private func cancelWait(_ id: UUID, recipient: String) {
        guard var waiting = waiters[recipient], let index = waiting.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiting.remove(at: index)
        waiters[recipient] = waiting
        waiter.resume(Self.timeoutMark)
    }

    private func reply(_ connection: NWConnection, _ text: String) {
        var payload = text
        if !payload.hasSuffix("\n") {
            payload += "\n"
        }
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
