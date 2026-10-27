#!/usr/bin/env python3
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _respond(self, status, payload=None, headers=None):
        body = b""
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        stamp = time.strftime("%H:%M:%S")
        auth = "yes" if self.headers.get("Authorization") else "no"
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        print(f"{stamp} {self.command} {self.path} auth={auth}", flush=True)

        if self.path.startswith("/rate-limit"):
            self._respond(429, {"error": "rate limited"}, {"Retry-After": "2"})
        elif self.path.startswith("/error500"):
            self._respond(500, {"error": "mock internal error"})
        elif self.path.startswith("/slow"):
            time.sleep(3)
            self._respond(200, {"balance": 88.8, "usage": {"today": 12.5}})
        elif self.path.startswith("/kimi"):
            self._respond(200, {
                "code": 0,
                "data": {
                    "available_balance": 66.6,
                    "voucher_balance": 10,
                    "cash_balance": 56.6,
                },
            })
        elif self.path.startswith("/post"):
            self._respond(200, {
                "received": True,
                "balance_infos": [{"currency": "USD", "total_balance": "42.42"}],
            })
        else:
            self._respond(200, {
                "is_available": True,
                "balance_infos": [{
                    "currency": "CNY",
                    "total_balance": "123.45",
                    "granted_balance": "23.45",
                    "topped_up_balance": "100.00",
                }],
                "usage": {"today_cost": 1.23, "month_cost": 45.67},
            })

    do_GET = _handle
    do_POST = _handle

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"mock server on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
