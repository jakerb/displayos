#!/usr/bin/env python3
"""DisplayOS receiver: capability endpoint and an observable H.264 TCP player."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import logging
import os
import socket
import struct
import subprocess
import threading
import time

STATE_PATH = "/run/displayos/receiver-state"
STATE_LOCK = threading.Lock()
MAX_FRAME_BYTES = 16_000_000
PIPELINE = [
    "gst-launch-1.0", "fdsrc", "!", "h264parse", "!", "decodebin", "!",
    "videoconvert", "!", "kmssink", "sync=false",
]

logging.basicConfig(level=logging.INFO, format="%(asctime)s displayos-receiver: %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


class ClientDisconnected(Exception):
    pass


class PipelineFailed(Exception):
    pass


def set_state(state, detail=""):
    """Atomically publish state for receiver-ui without competing for tty1."""
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with STATE_LOCK:
        temporary_path = f"{STATE_PATH}.tmp"
        with open(temporary_path, "w", encoding="utf-8") as state_file:
            state_file.write(f"{state}\n{detail.strip()}\n")
        os.replace(temporary_path, STATE_PATH)
    logger.info("Receiver state is %s%s", state, f": {detail}" if detail else "")


def receive_exact(client, size):
    data = bytearray()
    while len(data) < size:
        chunk = client.recv(size - len(data))
        if not chunk:
            raise ClientDisconnected()
        data.extend(chunk)
    return data


def relay_pipeline_stderr(player):
    assert player.stderr is not None
    for raw_line in iter(player.stderr.readline, b""):
        line = raw_line.decode("utf-8", errors="replace").strip()
        if line:
            logger.error("GStreamer: %s", line)


def start_player():
    logger.info("Starting GStreamer pipeline: %s", " ".join(PIPELINE))
    player = subprocess.Popen(
        PIPELINE,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    threading.Thread(target=relay_pipeline_stderr, args=(player,), daemon=True).start()
    # Detect immediate failures such as a missing DRM/KMS device before the
    # host begins sending frames.
    time.sleep(0.15)
    if player.poll() is not None:
        raise PipelineFailed(f"GStreamer exited immediately with status {player.returncode}. See journalctl -u displayos-announce.")
    return player


def stop_player(player):
    if player is None:
        return
    if player.stdin is not None:
        try:
            player.stdin.close()
        except BrokenPipeError:
            pass
    if player.poll() is None:
        player.terminate()
        try:
            player.wait(timeout=3)
        except subprocess.TimeoutExpired:
            logger.warning("GStreamer did not exit after SIGTERM; killing it")
            player.kill()
            player.wait()


def video_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 9877))
    server.listen(1)
    logger.info("Listening for H.264 streams on TCP port 9877")
    set_state("waiting")

    while True:
        client, address = server.accept()
        player = None
        streaming = False
        failure = ""
        logger.info("Host connected from %s:%s", *address)
        set_state("connecting", "Waiting for the first video frame")
        try:
            # Do not allocate DRM/KMS resources merely because something opened
            # the advertised port. Discovery checks and port scanners connect
            # without speaking the framed video protocol.
            header = receive_exact(client, 4)
            frame_size = struct.unpack(">I", header)[0]
            if not 0 < frame_size <= MAX_FRAME_BYTES:
                raise PipelineFailed(f"Invalid H.264 frame size: {frame_size}")
            frame = receive_exact(client, frame_size)
            set_state("connecting", "Starting the video pipeline")
            player = start_player()
            while True:
                if player.poll() is not None:
                    raise PipelineFailed(f"GStreamer exited with status {player.returncode}. See journalctl -u displayos-announce.")
                assert player.stdin is not None
                try:
                    player.stdin.write(frame)
                    player.stdin.flush()
                except BrokenPipeError as error:
                    raise PipelineFailed("GStreamer closed its input. See journalctl -u displayos-announce.") from error
                if not streaming:
                    # A live process that accepted the first H.264 access unit
                    # is the strongest signal available from gst-launch that
                    # playback has started.
                    time.sleep(0.05)
                    if player.poll() is not None:
                        raise PipelineFailed(f"GStreamer exited with status {player.returncode}. See journalctl -u displayos-announce.")
                    streaming = True
                    set_state("streaming")
                    logger.info("First frame accepted; streaming is active")
                header = receive_exact(client, 4)
                frame_size = struct.unpack(">I", header)[0]
                if not 0 < frame_size <= MAX_FRAME_BYTES:
                    raise PipelineFailed(f"Invalid H.264 frame size: {frame_size}")
                frame = receive_exact(client, frame_size)
        except ClientDisconnected:
            logger.info("Host disconnected")
        except (OSError, PipelineFailed) as error:
            failure = str(error)
            logger.error("Playback failed: %s", failure)
        finally:
            client.close()
            stop_player(player)
            set_state("failed", failure) if failure else set_state("waiting")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/capabilities"):
            self.send_error(404)
            return
        body = json.dumps({"name": "DisplayOS iMac", "version": "0.1.0", "codecs": ["h264"], "modes": ["2560x1440@60"]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


threading.Thread(target=video_server, daemon=True).start()
HTTPServer(("0.0.0.0", 9876), Handler).serve_forever()
