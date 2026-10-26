#!/usr/bin/env python3
"""In-memory text mailbox for two local agents.

Nothing is written to disk. One process keeps the messages in RAM.
Agents talk to it with plain text over 127.0.0.1.

A finished message always ends with this line:

    <<<END>>>

The waiting agent treats that line as "the other side finished; read the
text above, then write a reply."

Start the mailbox:

    python3 agent_mailbox.py serve

Codex sends a note to Cursor. The optional FROM line tells the iOS app
who is typing. See README.md for the app and the full rules.

    python3 agent_mailbox.py write --to cursor --from codex <<'EOF'
    谱面先只做一段短句。
    EOF

Cursor waits until that marker arrives:

    python3 agent_mailbox.py wait --as cursor

Raw TCP works the same way. One request per connection:

    WRITE cursor
    hello
    <<<END>>>

    WAIT cursor
    WAIT cursor 30
"""

from __future__ import annotations

import argparse
import socket
import threading
import time

HOST = "127.0.0.1"
DEFAULT_PORT = 9777
SENTINEL = "<<<END>>>"
TIMEOUT_MARK = "<<<TIMEOUT>>>"
MAX_MESSAGE_BYTES = 256 * 1024


class Mailbox:
    def __init__(self) -> None:
        self._queues: dict[str, list[str]] = {}
        self._cond = threading.Condition()

    def put(self, recipient: str, body: str) -> None:
        with self._cond:
            self._queues.setdefault(recipient, []).append(body)
            self._cond.notify_all()

    def take(self, recipient: str, timeout: float | None) -> str | None:
        deadline = None if timeout is None else time.monotonic() + timeout
        with self._cond:
            while not self._queues.get(recipient):
                remaining = None
                if deadline is not None:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return None
                self._cond.wait(timeout=remaining)
            return self._queues[recipient].pop(0)


def _recv_until(conn: socket.socket, marker: bytes) -> bytes:
    data = b""
    while marker not in data:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
        if len(data) > MAX_MESSAGE_BYTES:
            raise ValueError("message too large")
    return data


def _read_request(conn: socket.socket) -> str:
    data = _recv_until(conn, b"\n")
    if b"\n" not in data:
        return data.decode("utf-8", errors="replace")
    first, rest = data.split(b"\n", 1)
    command = first.decode("utf-8", errors="replace").strip()
    head = command.split()
    if not head or head[0].upper() != "WRITE":
        return (command + "\n").strip()
    body = rest
    ended = (SENTINEL + "\n").encode("utf-8")
    while ended not in body and not body.rstrip(b"\r\n").endswith(SENTINEL.encode("utf-8")):
        chunk = conn.recv(4096)
        if not chunk:
            break
        body += chunk
        if len(body) > MAX_MESSAGE_BYTES:
            raise ValueError("message too large")
    return command + "\n" + body.decode("utf-8", errors="replace")


def _send(conn: socket.socket, text: str) -> None:
    if not text.endswith("\n"):
        text += "\n"
    conn.sendall(text.encode("utf-8"))


def _handle(conn: socket.socket, mailbox: Mailbox) -> None:
    try:
        raw = _read_request(conn).strip("\n")
        if not raw:
            return
        first, _, rest = raw.partition("\n")
        parts = first.split()
        command = parts[0].upper()
        if command == "WRITE" and len(parts) == 2:
            body = rest.strip("\n")
            if not body.endswith(SENTINEL):
                body = (body + "\n" + SENTINEL) if body else SENTINEL
            mailbox.put(parts[1], body)
            _send(conn, "OK")
            return
        if command == "WAIT" and len(parts) in (2, 3):
            timeout = float(parts[2]) if len(parts) == 3 else None
            message = mailbox.take(parts[1], timeout)
            if message is None:
                _send(conn, TIMEOUT_MARK)
            else:
                _send(conn, message)
            return
        if command == "PING":
            _send(conn, "PONG")
            return
        _send(conn, "ERR expected WRITE <name>, WAIT <name> [seconds], or PING")
    except (ValueError, OSError, UnicodeError) as exc:
        try:
            _send(conn, f"ERR {exc}")
        except OSError:
            pass
    finally:
        conn.close()


def serve(port: int) -> None:
    mailbox = Mailbox()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, port))
    server.listen()
    print(f"listening {HOST}:{port}", flush=True)
    print(f"end marker: {SENTINEL}", flush=True)
    while True:
        conn, _addr = server.accept()
        threading.Thread(target=_handle, args=(conn, mailbox), daemon=True).start()


def _exchange(port: int, payload: str) -> str:
    with socket.create_connection((HOST, port), timeout=60) as conn:
        conn.sendall(payload.encode("utf-8"))
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            if data.endswith(b"\n") and (
                SENTINEL.encode() in data
                or data.strip() in (b"OK", TIMEOUT_MARK.encode(), b"PONG")
                or data.startswith(b"ERR ")
            ):
                break
        return data.decode("utf-8")


def write_message(port: int, recipient: str, body: str, sender: str | None, session: str | None = None) -> None:
    text = body.strip("\n")
    if session:
        text = f"SESSION {session}\n{text}"
    if sender and not text.startswith("FROM "):
        text = f"FROM {sender}\n{text}" if text else f"FROM {sender}"
    if not text.endswith(SENTINEL):
        text += "\n" + SENTINEL
    reply = _exchange(port, f"WRITE {recipient}\n{text}\n")
    if reply.strip() != "OK":
        raise SystemExit(reply.strip())


def wait_message(port: int, recipient: str, timeout: float | None) -> None:
    seconds = "" if timeout is None else f" {timeout}"
    print(_exchange(port, f"WAIT {recipient}{seconds}\n"), end="")


def demo() -> None:
    mailbox = Mailbox()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, 0))
    port = server.getsockname()[1]
    server.listen()
    threading.Thread(target=_accept_loop, args=(server, mailbox), daemon=True).start()

    got: list[str] = []

    def reader() -> None:
        got.append(_exchange(port, "WAIT cursor 5\n"))

    thread = threading.Thread(target=reader)
    thread.start()
    time.sleep(0.1)
    reply = _exchange(port, "WRITE cursor\n先做一段短句。\n<<<END>>>\n")
    thread.join(timeout=5)
    if reply.strip() != "OK" or SENTINEL not in "".join(got):
        raise SystemExit(f"demo failed: {reply!r} {got!r}")
    print(got[0], end="")
    print("demo ok")


def _accept_loop(server: socket.socket, mailbox: Mailbox) -> None:
    while True:
        conn, _addr = server.accept()
        threading.Thread(target=_handle, args=(conn, mailbox), daemon=True).start()


def main() -> None:
    parser = argparse.ArgumentParser(description="In-memory text mailbox for two agents.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    serve_cmd = sub.add_parser("serve")
    serve_cmd.add_argument("--port", type=int, default=DEFAULT_PORT)
    write_cmd = sub.add_parser("write")
    write_cmd.add_argument("--session", help="Session ID received from the iOS conversation")
    write_cmd.add_argument("--to", required=True)
    write_cmd.add_argument("--from", dest="sender")
    write_cmd.add_argument("--port", type=int, default=DEFAULT_PORT)
    wait_cmd = sub.add_parser("wait")
    wait_cmd.add_argument("--as", dest="name", required=True)
    wait_cmd.add_argument("--timeout", type=float)
    wait_cmd.add_argument("--port", type=int, default=DEFAULT_PORT)
    sub.add_parser("demo")
    args = parser.parse_args()
    if args.cmd == "serve":
        serve(args.port)
    elif args.cmd == "write":
        write_message(args.port, args.to, input_text(), args.sender, args.session)
    elif args.cmd == "wait":
        wait_message(args.port, args.name, args.timeout)
    else:
        demo()


def input_text() -> str:
    import sys

    return sys.stdin.read()


if __name__ == "__main__":
    main()
