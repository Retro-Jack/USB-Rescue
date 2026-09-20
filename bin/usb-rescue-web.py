#!/usr/bin/env python3
"""usb-rescue-web.py — a phone-friendly page for rescuing a dead keyboard.

When the keyboard and mouse lock up, open the bookmarked address on a phone
and press a button. The page can:

  * take a report — read-only evidence, saved for later
  * reset the hubs — the pair the keyboard and mouse sit behind
  * reset the controller — the whole USB controller they hang off

The resets run through /usr/local/sbin/usb-reset-chain.sh, which sudo allows
for this user without a password (see /etc/sudoers.d/usb-rescue). Nothing else
gains privilege, and neither action writes to a disk.

Reachable only from the local network — firewall the port to your own
subnet — and every request must carry the key held in
~/.config/usb-rescue-token, which is generated on first run. Bookmark the
address the service prints at startup; it has the key in it.

Run by hand for a look:   ~/bin/usb-rescue-web.py
Or as a service:          systemctl --user enable --now usb-rescue-web
"""

import html
import http.server
import os
import pathlib
import secrets
import signal
import socket
import subprocess
import urllib.parse

PORT = int(os.environ.get("WEB_PORT", 8777))
HELPER = "/usr/local/sbin/usb-reset-chain.sh"
REPORT = str(pathlib.Path.home() / "bin" / "usb-lockup-report.sh")
MAPPER = str(pathlib.Path.home() / "bin" / "usb-port-map.sh")
MAP_LOG = pathlib.Path.home() / "usb-port-map.txt"
MAP_PID = pathlib.Path.home() / ".cache" / "usb-port-map.pid"
TOKEN_FILE = pathlib.Path.home() / ".config" / "usb-rescue-token"

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>USB rescue</title>
<style>
  :root {{ color-scheme: dark; --bg:#14161a; --fg:#e8e6e3; --dim:#9aa0a6;
           --line:#2b3038; --go:#2f6f4f; --warn:#7a4a20; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:16px; background:var(--bg); color:var(--fg);
         font:16px/1.5 system-ui, sans-serif; }}
  h1 {{ font-size:1.25rem; margin:0 0 4px; }}
  p.sub {{ color:var(--dim); margin:0 0 20px; font-size:.9rem; }}
  form {{ margin:0 0 12px; }}
  button {{ width:100%; padding:16px; font-size:1rem; font-weight:600;
            color:var(--fg); background:var(--line); border:1px solid #3a414b;
            border-radius:10px; }}
  button.go {{ background:var(--go); }}
  button.warn {{ background:var(--warn); }}
  .hint {{ color:var(--dim); font-size:.82rem; margin:-6px 0 16px; }}
  pre {{ background:#0e1013; border:1px solid var(--line); border-radius:10px;
        padding:12px; overflow-x:auto; font-size:.8rem; white-space:pre-wrap;
        word-break:break-word; }}
</style>
</head>
<body>
<h1>USB rescue</h1>
<p class="sub">{host} · try the buttons in order; stop as soon as typing works</p>

<form method="post" action="/report?k={token}">
  <button class="go">1 · Take report</button>
</form>
<p class="hint">Reads only. Saves the evidence — do this before anything else,
and press some keys while it runs.</p>

<form method="post" action="/hubs?k={token}">
  <button>2 · Reset the hubs</button>
</form>
<p class="hint">Resets the two hubs the keyboard and mouse sit behind.</p>

<form method="post" action="/controller?k={token}">
  <button class="warn">3 · Reset the USB controller</button>
</form>
<p class="hint">Drops keyboard, mouse, sound card and card reader for a few
seconds. External drives are on another controller and aren't affected.</p>

<form method="post" action="/state?k={token}">
  <button>Show USB state</button>
</form>

<h1 style="margin-top:28px">Port mapping</h1>
<p class="sub">which rear socket is which — it speaks each one aloud as you plug it in</p>

<form method="post" action="/map-start?k={token}">
  <button>Start mapping</button>
</form>
<p class="hint">Then plug a USB stick into each rear socket in turn, in a fixed
order, waiting for it to speak before moving on.</p>

<form method="post" action="/map?k={token}">
  <button>Show the map so far</button>
</form>

<form method="post" action="/map-stop?k={token}">
  <button>Stop mapping</button>
</form>

{output}
</body>
</html>
"""


def token():
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not TOKEN_FILE.exists():
        TOKEN_FILE.write_text(secrets.token_urlsafe(12))
        TOKEN_FILE.chmod(0o600)
    return TOKEN_FILE.read_text().strip()


def run(cmd, timeout=180):
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (done.stdout + done.stderr).strip() or "(no output)"
    except subprocess.TimeoutExpired:
        return "Timed out."
    except FileNotFoundError:
        return f"Not installed: {cmd[0]}"


def stop_mapper():
    """Stop a running mapper by its recorded process group.

    Killing by name (pkill -f usb-port-map.sh) is a trap: it also matches any
    shell whose command line merely mentions the script, and duly kills that
    too. The pid we started is the only thing worth aiming at.
    """
    try:
        pid = int(MAP_PID.read_text().strip())
    except (FileNotFoundError, ValueError):
        return
    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    MAP_PID.unlink(missing_ok=True)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "usb-rescue"

    def log_message(self, fmt, *args):  # quieter journal
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def page(self, output=""):
        body = PAGE.format(
            host=socket.gethostname(),
            token=urllib.parse.quote(TOKEN),
            output=f"<pre>{html.escape(output)}</pre>" if output else "",
        )
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorised(self):
        """The key may be given as ?k=... or as a /k=... path segment.

        A phone keyboard drops the "?" easily, and being locked out by a
        punctuation slip while the keyboard is dead would be a poor joke.
        """
        parts = urllib.parse.urlparse(self.path)
        given = urllib.parse.parse_qs(parts.query).get("k", [""])[0]
        if not given:
            for segment in parts.path.split("/"):
                if segment.startswith("k="):
                    given = urllib.parse.unquote(segment[2:])
                    break
        if secrets.compare_digest(given, TOKEN):
            return True
        self.send_error(403, "Wrong or missing key")
        return False

    def do_GET(self):
        if self.authorised():
            self.page()

    def do_POST(self):
        if not self.authorised():
            return
        action = urllib.parse.urlparse(self.path).path.strip("/")
        action = "/".join(p for p in action.split("/") if not p.startswith("k="))
        if action == "report":
            out = run([REPORT])
        elif action in ("hubs", "controller", "state"):
            out = run(["sudo", "-n", HELPER, action])
        elif action == "map-start":
            stop_mapper()
            # setsid so it outlives this request and keeps listening; the whole
            # process group is recorded, since the script runs journalctl too.
            started = subprocess.Popen(["setsid", MAPPER],
                                       stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL)
            MAP_PID.parent.mkdir(parents=True, exist_ok=True)
            MAP_PID.write_text(str(started.pid))
            out = ("Mapping started — it is listening now.\n\n"
                   "Plug a stick into each rear socket in turn, in one fixed "
                   "order, waiting for each to be spoken aloud.\n"
                   "Then press \u201cShow the map so far\u201d.")
        elif action == "map":
            try:
                out = MAP_LOG.read_text().strip() or "Nothing plugged in yet."
            except FileNotFoundError:
                out = "No map yet — press \u201cStart mapping\u201d first."
        elif action == "map-stop":
            stop_mapper()
            out = "Mapping stopped.\n\n" + (
                MAP_LOG.read_text().strip() if MAP_LOG.exists() else "")
        else:
            self.send_error(404, "No such action")
            return
        self.page(out)


TOKEN = token()

if __name__ == "__main__":
    ip = os.popen("ip -4 -br addr show scope global").read().split()
    address = ip[2].split("/")[0] if len(ip) > 2 else "this machine"
    print(f"USB rescue on http://{address}:{PORT}/?k={TOKEN}", flush=True)
    print("Bookmark that address — the key is part of it.", flush=True)
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
