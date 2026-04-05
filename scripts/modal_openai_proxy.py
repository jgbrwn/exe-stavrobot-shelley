#!/usr/bin/env python3
import http.server
import json
import os
import socketserver
import urllib.error
import urllib.parse
import urllib.request


LISTEN_HOST = os.environ.get("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "11435"))
UPSTREAM_BASE_URL = os.environ.get("UPSTREAM_BASE_URL", "").rstrip("/")
MODAL_TOKEN_ID = os.environ.get("MODAL_TOKEN_ID", "")
MODAL_TOKEN_SECRET = os.environ.get("MODAL_TOKEN_SECRET", "")
REQUEST_TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT_SECONDS", "120"))


def _json(status: int, payload: dict) -> tuple[int, bytes, str]:
    return status, json.dumps(payload).encode("utf-8"), "application/json"


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # keep default stderr logging but include client address
        super().log_message(fmt, *args)

    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Allow", "GET, POST, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _forward(self):
        if not UPSTREAM_BASE_URL:
            status, body, ctype = _json(500, {"error": "UPSTREAM_BASE_URL is required"})
            self._write_response(status, body, ctype)
            return

        upstream_url = UPSTREAM_BASE_URL + self.path
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(content_length) if content_length > 0 else b""

        req = urllib.request.Request(upstream_url, data=body if self.command != "GET" else None, method=self.command)

        for header in ("Content-Type", "Accept", "Authorization"):
            value = self.headers.get(header)
            if value:
                req.add_header(header, value)

        req.add_header("Modal-Key", MODAL_TOKEN_ID)
        req.add_header("Modal-Secret", MODAL_TOKEN_SECRET)

        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                payload = resp.read()
                ctype = resp.headers.get("Content-Type", "application/json")
                self._write_response(resp.status, payload, ctype)
        except urllib.error.HTTPError as exc:
            payload = exc.read() if hasattr(exc, "read") else b""
            ctype = exc.headers.get("Content-Type", "application/json") if exc.headers else "application/json"
            self._write_response(exc.code, payload, ctype)
        except Exception as exc:
            status, payload, ctype = _json(502, {"error": f"proxy_error: {exc}"})
            self._write_response(status, payload, ctype)

    def _write_response(self, status: int, payload: bytes, content_type: str):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    with ThreadedTCPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler) as server:
        print(f"[modal-openai-proxy] listening on {LISTEN_HOST}:{LISTEN_PORT} -> {UPSTREAM_BASE_URL}")
        server.serve_forever()
