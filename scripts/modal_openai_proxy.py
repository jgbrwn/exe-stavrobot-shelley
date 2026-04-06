#!/usr/bin/env python3
import http.server
import json
import os
import socketserver
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_REDIRECTS = int(os.environ.get("MAX_REDIRECTS", "8"))


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

        method = self.command
        redirect_count = 0

        while True:
            request_start = time.time()
            req = urllib.request.Request(upstream_url, data=body if method != "GET" else None, method=method)

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
                    elapsed = time.time() - request_start
                    print(f"[modal-openai-proxy] {method} {upstream_url} -> {resp.status} in {elapsed:.2f}s")
                    self._write_response(resp.status, payload, ctype)
                    return
            except urllib.error.HTTPError as exc:
                if exc.code in (301, 302, 303, 307, 308):
                    location = exc.headers.get("Location") if exc.headers else None
                    if not location:
                        payload = exc.read() if hasattr(exc, "read") else b""
                        ctype = exc.headers.get("Content-Type", "application/json") if exc.headers else "application/json"
                        self._write_response(exc.code, payload, ctype)
                        return

                    redirect_count += 1
                    if redirect_count > MAX_REDIRECTS:
                        status, payload, ctype = _json(502, {"error": "proxy_error: too many upstream redirects"})
                        self._write_response(status, payload, ctype)
                        return

                    print(f"[modal-openai-proxy] redirect {redirect_count}/{MAX_REDIRECTS}: {method} {upstream_url} -> {exc.code} {location}")
                    upstream_url = urllib.parse.urljoin(upstream_url, location)
                    if exc.code == 303 and method != "GET":
                        method = "GET"
                        body = b""
                    continue

                payload = exc.read() if hasattr(exc, "read") else b""
                ctype = exc.headers.get("Content-Type", "application/json") if exc.headers else "application/json"
                elapsed = time.time() - request_start
                print(f"[modal-openai-proxy] {method} {upstream_url} -> HTTPError {exc.code} in {elapsed:.2f}s")
                self._write_response(exc.code, payload, ctype)
                return
            except Exception as exc:
                elapsed = time.time() - request_start
                print(f"[modal-openai-proxy] {method} {upstream_url} -> error after {elapsed:.2f}s: {exc}")
                status, payload, ctype = _json(502, {"error": f"proxy_error: {exc}"})
                self._write_response(status, payload, ctype)
                return

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
