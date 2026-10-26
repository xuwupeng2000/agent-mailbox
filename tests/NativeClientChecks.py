"""Developer-only protocol fixtures; the packaged app/client do not use Python."""
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = Path(os.environ.get('MAILBOX_CLIENT', ROOT / 'dist/Agent Mailbox.app/Contents/MacOS/mailbox'))

class ClientChecks(unittest.TestCase):
    def fixture(self, arguments, reply, body=None, chunks=False, delay=0):
        server = socket.socket()
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        port = server.getsockname()[1]
        received = []
        failures = []
        def peer():
            try:
                server.settimeout(5)
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(5)
                    data = b''
                    while (b'<<<END>>>\n' not in data if arguments[0] == 'write' else b'\n' not in data):
                        part = conn.recv(4096)
                        if not part:
                            break
                        data += part
                    received.append(data.decode())
                    time.sleep(delay)
                    if chunks:
                        for byte in reply.encode():
                            conn.sendall(bytes([byte]))
                            time.sleep(0.001)
                    else:
                        conn.sendall(reply.encode())
                    # Keep the socket open: terminal markers must complete the command themselves.
                    time.sleep(0.2)
            except Exception as error:
                failures.append(error)
            finally:
                server.close()
        thread = threading.Thread(target=peer)
        thread.start()
        result = subprocess.run([str(CLIENT), *arguments, '--port', str(port)], input=body, text=True, capture_output=True, timeout=8)
        thread.join(6)
        self.assertFalse(failures, failures)
        self.assertFalse(thread.is_alive())
        return result, received[0]

    def test_utf8_write_with_session(self):
        result, wire = self.fixture(['write', '--to', 'cursor', '--from', 'codex', '--session', 'session-123'], 'OK\n', '中文法师帽 🧙\n第二行\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(wire, 'WRITE cursor\nFROM codex\nSESSION session-123\n中文法师帽 🧙\n第二行\n<<<END>>>\n')
        self.assertEqual(result.stdout, '')

    def test_wait_fragmented_utf8(self):
        message = 'FROM cursor\nSESSION abc\nOK\n已完成 🧙\n<<<END>>>\n'
        result, wire = self.fixture(['wait', '--as', 'codex', '--timeout', '3'], message, chunks=True, delay=0.1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, message)
        self.assertEqual(wire, 'WAIT codex 3.0\n')

    def test_stop_without_timeout(self):
        result, wire = self.fixture(['wait', '--as', 'codex'], '<<<STOP>>>\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '<<<STOP>>>\n')
        self.assertEqual(wire, 'WAIT codex\n')

    def test_server_timeout(self):
        result, _ = self.fixture(['wait', '--as', 'codex', '--timeout', '0.1'], '<<<TIMEOUT>>>\n', delay=0.1)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '<<<TIMEOUT>>>\n')

    def test_error_exit_status(self):
        result, _ = self.fixture(['write', '--to', 'cursor', '--from', 'codex'], 'ERR wrong SESSION\n', 'message')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERR wrong SESSION', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_ping(self):
        result, wire = self.fixture(['ping'], 'PONG\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'PONG\n')
        self.assertEqual(wire, 'PING\n')

    def test_truncated_reply(self):
        result, _ = self.fixture(['wait', '--as', 'codex'], 'FROM cursor\nunfinished')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('complete response', result.stderr)

    def test_invalid_input(self):
        cases = [(['wait', '--as', 'bad\nname'], ''),
                 (['wait', '--as', 'codex', '--timeout', 'nan'], ''),
                 (['wait', '--as', 'codex', '--port', '0'], ''),
                 (['write', '--to', 'cursor', '--from', 'codex'], 'middle\n<<<END>>>\ntruncated'),
                 (['write', '--to', 'cursor', '--from', 'codex'], 'x' * (256 * 1024 + 1)),
                 (['write', '--to', 'cursor', '--from', 'codex', '--session', 'x\ny'], '')]
        for args, body in cases:
            with self.subTest(args=args):
                result = subprocess.run([str(CLIENT), *args], input=body, text=True, capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Cannot connect', result.stderr)

    def test_help_with_empty_path_and_arbitrary_cwd(self):
        result = subprocess.run([str(CLIENT), '--help'], cwd='/tmp', env={'PATH': '/no-tools-here'}, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn('no Python required', result.stdout)

if __name__ == '__main__':
    unittest.main(verbosity=2)
