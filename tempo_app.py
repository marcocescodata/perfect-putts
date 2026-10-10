"""Putting tempo app: reads the AirPod, detects putts, and shows each one's tempo in the browser.

Usage: .venv/bin/python tempo_app.py [--demo]

Opens http://localhost:8765. --demo makes up a putt every few seconds, to try the page without
an AirPod. Each real putt is appended to data/tempo/<session start>.csv.
"""

import csv
import json
import queue
import random
import sys
import threading
import time
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import airpods
import putting

PORT = 8765
ADDRESS_SECONDS = 1.5
PAGE = Path(__file__).parent / "web" / "tempo.html"
LOG = Path(__file__).parent / "data" / "tempo" / (datetime.now().strftime("%Y-%m-%d_%H%M%S") + ".csv")

clients = []  # one queue per open page
clients_lock = threading.Lock()
last_status = {"type": "status", "text": "Connecting to putter sensor…", "connected": False}


def publish(event):
    global last_status
    if event["type"] == "status":
        if event == last_status:
            return
        last_status = event
    with clients_lock:
        for q in clients:
            q.put(event)


def status(text, connected=True):
    publish({"type": "status", "text": text, "connected": connected})


def putt(stroke):
    publish({"type": "putt", "back": stroke.backswing, "forward": stroke.downswing})


def save(stroke):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    features = stroke.features()
    new = not LOG.exists()
    with LOG.open("a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(features))
        if new:
            writer.writeheader()
        writer.writerow(features)


def sensor():
    detector = putting.StrokeDetector(putting.DetectorConfig(address_duration=ADDRESS_SECONDS, pre_roll=1.0))
    try:
        for r in airpods.stream():
            if "event" in r:
                if r["event"] in ("error", "disconnected"):
                    status(f"AirPod {r['event']}", connected=False)
                continue
            before = detector.phase
            result = detector.process(r)
            if result:
                putt(result[0])
                save(result[0])
            if detector.phase == "waiting":
                if before == "stroke" and not result:
                    status("Not a putt. Hold still to go again")
                elif detector.still_since is not None:
                    left = max(ADDRESS_SECONDS - (r["t"] - detector.still_since), 0)
                    status(f"Hold still at address… {left:.1f}")
                else:
                    status("Hold still at address")
            elif detector.phase == "ready":
                status("Ready. Putt when you like")
            else:
                status("Putting…")
    except SystemExit as e:  # helper not built
        status(str(e), connected=False)


def demo():
    while True:
        status("Hold still at address")
        time.sleep(2)
        status("Ready. Putt when you like")
        time.sleep(1.5)
        forward = random.uniform(0.3, 0.38)
        publish({"type": "putt", "back": forward * random.gauss(2.0, 0.12), "forward": forward})


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            q = queue.Queue()
            q.put(last_status)
            with clients_lock:
                clients.append(q)
            try:
                while True:
                    try:
                        event = q.get(timeout=15)
                        self.wfile.write(f"data: {json.dumps(event)}\n\n".encode())
                    except queue.Empty:
                        self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                with clients_lock:
                    clients.remove(q)
        elif self.path in ("/", "/index.html"):
            body = PAGE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=demo if "--demo" in sys.argv else sensor, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    url = f"http://localhost:{PORT}"
    print(f"Putting tempo at {url}  (Ctrl-C to stop)")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if "--demo" not in sys.argv:
            airpods.stop()
