#!/usr/bin/env python3
"""DisplayOS receiver: HTTP capabilities plus length-framed Annex-B H.264 TCP input."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, socket, struct, subprocess, threading

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/capabilities"):
            self.send_error(404); return
        body = json.dumps({"name": "DisplayOS iMac", "version": "0.1.0", "codecs": ["h264"], "modes": ["2560x1440@60"]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, format, *args): pass

def video_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 9877)); server.listen(1)
    while True:
        client, _ = server.accept()
        # kmssink renders without X/Wayland and returns to the DisplayOS tty UI
        # when the connection closes. decodebin selects VAAPI where available.
        player = subprocess.Popen(["gst-launch-1.0", "-q", "fdsrc", "!", "h264parse", "!", "decodebin", "!", "videoconvert", "!", "kmssink", "sync=false"], stdin=subprocess.PIPE)
        try:
            while True:
                header = client.recv(4)
                if len(header) != 4: break
                size = struct.unpack(">I", header)[0]
                if size == 0 or size > 16_000_000: break
                chunks = bytearray()
                while len(chunks) < size:
                    chunk = client.recv(size - len(chunks))
                    if not chunk: raise ConnectionError()
                    chunks.extend(chunk)
                player.stdin.write(chunks); player.stdin.flush()
        except (ConnectionError, BrokenPipeError): pass
        finally:
            client.close(); player.terminate(); player.wait(timeout=3)

threading.Thread(target=video_server, daemon=True).start()
HTTPServer(("0.0.0.0", 9876), Handler).serve_forever()
