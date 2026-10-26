import Foundation
import Darwin

private let limit = 256 * 1024
private let endMarker = "<<<END>>>"

struct ClientError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    let command: String
    var values: [String: String] = [:]

    init(_ arguments: [String]) throws {
        guard let first = arguments.first, ["wait", "write", "ping"].contains(first) else {
            throw ClientError("Usage: mailbox wait --as NAME [--timeout SECONDS] [--port PORT]\n       mailbox write --to NAME --from NAME [--session ID] [--port PORT] < message.txt\n       mailbox ping [--port PORT]")
        }
        command = first
        let allowed: Set<String> = first == "write" ? ["--to", "--from", "--session", "--port"] : first == "wait" ? ["--as", "--timeout", "--port"] : ["--port"]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), index + 1 < arguments.count, values[key] == nil else {
                throw ClientError("Unknown, duplicate, or incomplete option: \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        for key in first == "write" ? ["--to", "--from"] : first == "wait" ? ["--as"] : [] {
            guard let name = values[key], !name.isEmpty,
                  name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
                throw ClientError("\(key) requires a name containing only letters, digits, _ or -")
            }
        }
        if let session = values["--session"], session.isEmpty || session.contains(where: { $0.isWhitespace }) {
            throw ClientError("SESSION must be one nonempty value without whitespace")
        }
    }

    var port: UInt16 {
        get throws {
            guard let value = UInt16(values["--port"] ?? "9777"), value > 0 else {
                throw ClientError("Port must be between 1 and 65535")
            }
            return value
        }
    }

    var timeout: Double? {
        get throws {
            guard let value = values["--timeout"] else { return nil }
            guard let seconds = Double(value), seconds.isFinite, seconds > 0, seconds <= 86400 else {
                throw ClientError("Timeout must be greater than 0 and at most 86400 seconds")
            }
            return seconds
        }
    }

    func request() throws -> String {
        if command == "ping" { return "PING\n" }
        if command == "wait" {
            let suffix = try timeout.map { " \($0)" } ?? ""
            return "WAIT \(values["--as"]!)\(suffix)\n"
        }
        var data = Data()
        while data.count <= limit {
            let chunk = FileHandle.standardInput.readData(ofLength: min(4096, limit + 1 - data.count))
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= limit, let body = String(data: data, encoding: .utf8) else {
            throw ClientError("Message must be UTF-8 and at most 256 KiB")
        }
        guard !body.contains(endMarker) else {
            throw ClientError("Do not include <<<END>>> in the body; mailbox adds it automatically")
        }
        var lines = ["WRITE \(values["--to"]!)", "FROM \(values["--from"]!)"]
        if let session = values["--session"] { lines.append("SESSION \(session)") }
        lines.append(body.trimmingCharacters(in: .newlines))
        lines.append(endMarker)
        let wire = lines.joined(separator: "\n") + "\n"
        guard wire.utf8.count <= limit else { throw ClientError("Message including headers exceeds 256 KiB") }
        return wire
    }
}

func exchange(_ request: String, port: UInt16, timeout: Double?) throws -> Data {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ClientError("Cannot create socket: \(String(cString: strerror(errno)))") }
    defer { Darwin.close(descriptor) }
    var noSignal: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
    // A wait without --timeout has no receive deadline. Otherwise allow the server to report TIMEOUT first.
    var deadline = timeval(tv_sec: Int(timeout.map { ceil($0) + 10 } ?? 0), tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout.size(ofValue: deadline)))
    var sendDeadline = timeval(tv_sec: 30, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &sendDeadline, socklen_t(MemoryLayout.size(ofValue: sendDeadline)))
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else { throw ClientError("Cannot connect to Agent Mailbox at 127.0.0.1:\(port): \(String(cString: strerror(errno))). Open the app first.") }
    let bytes = Array(request.utf8)
    try bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.send(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ClientError("Send failed: \(String(cString: strerror(errno)))") }
            offset += count
        }
    }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw ClientError("Receive failed: \(String(cString: strerror(errno)))") }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
        guard result.count <= limit else { throw ClientError("Response exceeds 256 KiB") }
        if let text = String(data: result, encoding: .utf8), text.hasSuffix("\n") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let last = lines.dropLast().last.map(String.init) ?? ""
            let whole = text.trimmingCharacters(in: .newlines)
            if last == endMarker || ["<<<TIMEOUT>>>", "<<<STOP>>>", "OK", "PONG"].contains(whole) || text.hasPrefix("ERR ") { break }
        }
    }
    guard !result.isEmpty, let text = String(data: result, encoding: .utf8) else { throw ClientError("Server returned an empty or non-UTF-8 response") }
    let last = text.trimmingCharacters(in: .newlines).components(separatedBy: "\n").last ?? ""
    guard [endMarker, "<<<TIMEOUT>>>", "<<<STOP>>>", "OK", "PONG"].contains(last) || text.hasPrefix("ERR ") else {
        throw ClientError("Connection closed before a complete response arrived")
    }
    return result
}

if CommandLine.arguments.count == 2 && ["--help", "-h"].contains(CommandLine.arguments[1]) {
    print("""
    Agent Mailbox native client (no Python required)
    mailbox wait --as NAME [--timeout SECONDS] [--port PORT]
    mailbox write --to NAME --from NAME [--session ID] [--port PORT] < message.txt
    mailbox ping [--port PORT]
    Open Agent Mailbox.app before connecting. Defaults: 127.0.0.1:9777.
    Message text comes from stdin; the client appends <<<END>>>.
    """)
    exit(0)
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let request = try options.request()
    let response = try exchange(request, port: options.port, timeout: options.command == "wait" ? options.timeout : 30)
    let text = String(decoding: response, as: UTF8.self)
    if text.hasPrefix("ERR ") { throw ClientError(text.trimmingCharacters(in: .newlines)) }
    if options.command == "write" {
        guard text.trimmingCharacters(in: .newlines) == "OK" else { throw ClientError("Unexpected write response: \(text)") }
    } else {
        FileHandle.standardOutput.write(response)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
