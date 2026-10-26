import Foundation
import Combine
import Network

struct DialogueTurn: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let recipient: String
    let text: String
    let round: Int
    let isReport: Bool
}

@MainActor
final class MailboxCenter: ObservableObject {
    static let port: UInt16 = 9777
    static let sentinel = "<<<END>>>"
    static let timeoutMark = "<<<TIMEOUT>>>"
    nonisolated static let unsignedSender = "未署名"

    @Published var listenState: ListenState = .opening
    @Published var panels: [String: String] = [:]
    @Published var order: [String] = []
    @Published var turns: [DialogueTurn] = []
    @Published var unread = 0
    @Published var conversationOpen = false
    @Published var isListening = false

    @Published var agentA = "codex"
    @Published var agentB = "cursor"
    @Published var topic = ""
    @Published var rounds = 3
    @Published var phase: SessionPhase = .idle
    @Published var completedReplies = 0
    @Published var expected = ""
    @Published var sessionID = ""
    @Published var notice: Notice = .none
    @Published var sessionActive = false
    @Published var pendingReports: [String] = []
    @Published var reading: [String] = []
    private var managed = false
    private var paused = false
    private var finished = false
    private var reporting = false
    private var sessionLanguage: AppLanguage = .zhHans
    private var finishAfterReports: SessionPhase = .stopped

    var canStart: Bool {
        let names = [agentA, agentB]
        return names.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } }
            && agentA != agentB && !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !topic.contains(Self.sentinel) && !topic.contains("\nSESSION ")
    }

    func begin(language: AppLanguage = .zhHans) {
        guard !sessionActive else { return }
        guard canStart else { notice = .invalidStart; return }
        stop()
        queues.removeAll()
        turns.removeAll()
        panels.removeAll()
        order.removeAll()
        pending.removeAll()
        animation?.cancel()
        animation = nil
        unread = 0
        sessionID = UUID().uuidString
        managed = true
        sessionActive = true
        paused = false
        finished = false
        reporting = false
        pendingReports = []
        reading = []
        sessionLanguage = language
        finishAfterReports = .stopped
        completedReplies = 0
        expected = agentA
        phase = .running
        notice = .none
        let body = L10n.openingBody(topic: topic, rounds: rounds, language: language)
        enqueue(agentA, "FROM user\nSESSION \(sessionID)\n\(body)\n\(Self.sentinel)")
    }

    func togglePause() {
        guard managed && !finished else { return }
        paused.toggle()
        phase = paused ? .paused : .running
        if !paused { flushWaiters() }
    }

    func endSession() {
        guard managed, !finished else { return }
        if reporting {
            stop()
            return
        }
        requestReports(then: .stopped)
    }

    func stop() {
        if managed {
            finished = true
            sessionActive = false
            reporting = false
            pendingReports = []
            reading = []
            phase = .stopped
            queues.removeAll()
            let parked = waiters
            waiters.removeAll()
            for list in parked.values {
                for waiter in list { waiter.resume("<<<STOP>>>") }
            }
        }
    }

    func interject(_ text: String, language: AppLanguage = .zhHans) {
        guard managed && !finished && !reporting, !text.isEmpty, !text.contains(Self.sentinel), !text.contains("\nSESSION ") else { return }
        let body = L10n.interjectBody(text, language)
        enqueue(expected, "FROM user\nSESSION \(sessionID)\n\(body)\n\(Self.sentinel)")
    }

    private func enqueue(_ recipient: String, _ wire: String) {
        queues[recipient, default: []].append(wire)
        if !paused { flushWaiters() }
    }

    private func flushWaiters() {
        for recipient in Array(waiters.keys) {
            while !(waiters[recipient] ?? []).isEmpty && !(queues[recipient] ?? []).isEmpty {
                let waiter = waiters[recipient]!.removeFirst()
                let message = queues[recipient]!.removeFirst()
                waiter.resume(message)
            }
        }
    }

    func instructions(for name: String, language: AppLanguage = .zhHans) -> String {
        let peer = name == agentA ? agentB : agentA
        return L10n.instructions(name: name, peer: peer, language: language)
    }

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
            #if os(macOS)
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            #endif
            #if os(macOS)
            let listener = try NWListener(using: parameters)
            #else
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            #endif
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
            listenState = .failed(error.localizedDescription)
        }
    }

    func markConversationRead() {
        unread = 0
    }

    private func apply(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            listenState = .open
        case .failed(let error):
            isListening = false
            listenState = .failed(error.localizedDescription)
        case .waiting(let error):
            isListening = false
            listenState = .waiting(error.localizedDescription)
        case .cancelled:
            isListening = false
            listenState = .cancelled
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
            if parts.count == 3 && (timeout == nil || !timeout!.isFinite || timeout! < 0 || timeout! > 3600) {
                reply(connection, "ERR timeout must be between 0 and 3600"); return true
            }
            if managed && (finished || ![agentA, agentB].contains(name)) {
                reply(connection, finished ? "<<<STOP>>>" : "ERR unknown participant"); return true
            }
            wait(connection, recipient: name, timeout: timeout)
            return true
        }
        if command == "WRITE", parts.count == 2 {
            let rest = String(text[text.index(after: newline)...])
            guard completeWrite(rest) != nil else { return false }
            reply(connection, acceptWrite(recipient: String(parts[1]), body: rest))
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
        var sender = Self.unsignedSender
        if lines.first?.hasPrefix("FROM ") == true {
            sender = String(lines.removeFirst().dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if sender.isEmpty { sender = Self.unsignedSender }
        }
        if lines.last == Self.sentinel {
            lines.removeLast()
        }
        return (wire, sender, lines.joined(separator: "\n"))
    }

    func acceptWrite(recipient: String, body: String) -> String {
        guard let ended = completeWrite(body) else { return "ERR incomplete" }
        if managed && reporting {
            let lines = ended.wire.components(separatedBy: "\n")
            guard !finished,
                  pendingReports.contains(ended.sender),
                  recipient == "user",
                  lines.count > 1,
                  lines[1] == "SESSION \(sessionID)" else {
                return "ERR report must be sent to user by a participant who has not reported, with SESSION"
            }
            pendingReports.removeAll { $0 == ended.sender }
            record(recipient: recipient, sender: ended.sender, spoken: ended.spoken, round: 0, isReport: true)
            if pendingReports.isEmpty {
                let finishedPhase = finishAfterReports
                stop()
                phase = finishedPhase
            }
            return "OK"
        }
        if managed {
            let lines = ended.wire.components(separatedBy: "\n")
            guard !finished, ended.sender == expected,
                  recipient == (expected == agentA ? agentB : agentA),
                  lines.count > 1, lines[1] == "SESSION \(sessionID)" else {
                return "ERR inactive session, wrong turn, recipient or SESSION"
            }
            completedReplies += 1
            expected = recipient
        }
        let round = managed ? (completedReplies - 1) / 2 + 1 : turns.filter { !$0.isReport }.count / 2 + 1
        enqueue(recipient, ended.wire)
        record(recipient: recipient, sender: ended.sender, spoken: ended.spoken, round: round, isReport: false)
        if managed && !reporting && completedReplies >= rounds * 2 {
            requestReports(then: .completed)
        }
        return "OK"
    }

    private func requestReports(then phaseAfter: SessionPhase) {
        guard managed, !finished, !reporting else { return }
        paused = false
        reporting = true
        finishAfterReports = phaseAfter
        phase = .reporting
        pendingReports = [agentA, agentB]
        let body = L10n.reportRequest(sessionLanguage)
        let wire = "FROM user\nSESSION \(sessionID)\n\(body)\n\(Self.sentinel)"
        enqueue(agentA, wire)
        enqueue(agentB, wire)
    }

    private func record(recipient: String, sender: String, spoken: String, round: Int, isReport: Bool) {
        let turn = DialogueTurn(sender: sender, recipient: recipient, text: spoken, round: round, isReport: isReport)
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
                if Task.isCancelled { return }
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
        if !paused, var queued = queues[recipient], !queued.isEmpty {
            let message = queued.removeFirst()
            queues[recipient] = queued
            reply(connection, message)
            return
        }
        let waiter = Waiter(id: UUID()) { [weak self] message in
            guard let self else { return }
            self.reply(connection, message)
            self.finishReading(recipient)
        }
        waiters[recipient, default: []].append(waiter)
        markReading(recipient)
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

    func markReading(_ name: String) {
        guard !reading.contains(name) else { return }
        reading = reading + [name]
    }

    func finishReading(_ name: String) {
        guard (waiters[name] ?? []).isEmpty else { return }
        guard reading.contains(name) else { return }
        reading = reading.filter { $0 != name }
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
