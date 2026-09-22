#!/usr/bin/env python3
"""Download a YouTube URL as an MP3 (or MP4) into the current directory.

Usage:
    python ytd.py "https://www.youtube.com/watch?v=XXXXXXXXXXX"
    python ytd.py --video "https://www.youtube.com/watch?v=XXXXXXXXXXX"
    python ytd.py --gui [--video]

Requires: yt-dlp (pip install -U yt-dlp) and ffmpeg on PATH.
"""

import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import unicodedata
import webbrowser
from itertools import count

try:
    from yt_dlp import YoutubeDL
except ImportError:
    sys.exit("yt-dlp is not installed. Run: pip install -U yt-dlp")


MAX_NAME_LEN = 120
# Reserved device names on Windows
_WINDOWS_RESERVED = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


def _strip_parens(name: str) -> str:
    """Drop parenthesised segments, including nested ones.

    "Song (Live) (HD)" -> "Song". If removing them would leave nothing, the
    outermost parentheses are unwrapped instead and we retry on the inside,
    so "(Full Album)" -> "Full Album".
    """
    out: list[str] = []
    depth = 0
    for ch in name:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            out.append(ch)
    stripped = "".join(out)

    # Nothing outside the parentheses: fall back to what was inside them.
    if not re.search(r"[A-Za-z0-9]", stripped):
        inner = re.sub(r"^[^(]*\(|\)[^)]*$", "", name.strip())
        if re.search(r"[A-Za-z0-9]", inner) and inner != name:
            return _strip_parens(inner)
        return name
    return stripped


def sanitize(name: str) -> str:
    """Turn an arbitrary video title into a safe, portable filename stem.

    Parenthesised segments are dropped, accents are stripped (é -> e), every
    character that is not a letter or a digit becomes an underscore, runs of
    underscores collapse into one, and leading/trailing underscores go away.
    """
    # Decompose so accented letters split into base letter + combining mark,
    # then drop the combining marks: "é" -> "e", "ü" -> "u", "ñ" -> "n".
    name = unicodedata.normalize("NFKD", name)
    name = "".join(ch for ch in name if not unicodedata.combining(ch))
    name = _strip_parens(name)
    # Anything left that is not ASCII alphanumeric becomes an underscore
    # (spaces, dashes, parentheses, punctuation, CJK, emoji, ...).
    name = re.sub(r"[^A-Za-z0-9]+", "_", name)
    name = name.strip("_")[:MAX_NAME_LEN].strip("_")
    if not name:
        name = "audio"
    if name.upper() in _WINDOWS_RESERVED:
        name = f"{name}_file"
    return name


# Names handed out but not yet written to disk. Guards against two concurrent
# jobs (GUI mode) picking the same filename before either file exists.
_reserved_names: set[str] = set()
_reserve_lock = threading.Lock()


def unique_path(directory: str, stem: str, ext: str = "mp3") -> str:
    with _reserve_lock:
        candidate = os.path.join(directory, f"{stem}.{ext}")
        counter = 1
        while os.path.exists(candidate) or candidate in _reserved_names:
            candidate = os.path.join(directory, f"{stem}_{counter}.{ext}")
            counter += 1
        _reserved_names.add(candidate)
        return candidate


def _ydl_opts(video: bool, outtmpl: str) -> dict:
    if video:
        # YouTube serves video and audio separately above 720p, so grab both
        # and let ffmpeg mux them (a fast stream copy, not a re-encode).
        return {
            "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
            "merge_output_format": "mp4",
            "outtmpl": outtmpl,
            "noplaylist": True,
            "postprocessors": [{"key": "FFmpegMetadata"}],
            "quiet": False,
            "no_warnings": True,
        }
    return {
        "format": "bestaudio/best",
        "outtmpl": outtmpl,
        "noplaylist": True,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            },
            {"key": "FFmpegMetadata"},
        ],
        "quiet": False,
        "no_warnings": True,
    }


def download(url: str, out_dir: str, video: bool = False) -> str:
    """Fetch `url` into `out_dir` as MP3, or as MP4 when `video` is true.

    Returns the path of the file that was written.
    """
    ext = "mp4" if video else "mp3"

    # 1) Probe metadata to build the sanitized name ourselves
    with YoutubeDL({"quiet": True, "no_warnings": True, "noplaylist": True}) as ydl:
        info = ydl.extract_info(url, download=False)
    if "entries" in info:  # playlist/url given anyway -> take first entry
        info = next(e for e in info["entries"] if e)

    stem = sanitize(info.get("title") or info.get("id") or "audio")
    target = unique_path(out_dir, stem, ext)
    # yt-dlp appends the final extension itself
    outtmpl = target[: -len(ext) - 1] + ".%(ext)s"

    try:
        with YoutubeDL(_ydl_opts(video, outtmpl)) as ydl:
            ydl.download([url])
    finally:
        with _reserve_lock:
            _reserved_names.discard(target)

    # Single write so concurrent jobs cannot interleave mid-line.
    print(f"\n==> DONE: {target}\n", flush=True)
    return target


# =====================================================================
# GUI mode (--gui): a tiny localhost web page driving the same download()
# =====================================================================

_jobs: dict[int, dict] = {}
_jobs_lock = threading.Lock()
_ids = count(1)


def _start_job(url: str, out_dir: str, video: bool) -> dict:
    job_id = next(_ids)
    job = {
        "id": job_id,
        "url": url,
        "status": "running",
        "name": url,
        "error": None,
    }
    with _jobs_lock:
        _jobs[job_id] = job

    def work() -> None:
        try:
            path = download(url, out_dir, video=video)
            with _jobs_lock:
                job["status"] = "done"
                job["name"] = os.path.basename(path)
        except Exception as exc:  # noqa: BLE001
            print(f"\n==> FAILED: {url}\n    {exc}\n", flush=True)
            with _jobs_lock:
                job["status"] = "failed"
                job["error"] = str(exc)

    threading.Thread(target=work, daemon=True).start()
    return job


def _snapshot() -> list[dict]:
    with _jobs_lock:
        return [dict(j) for j in _jobs.values()]


def _running_jobs() -> int:
    with _jobs_lock:
        return sum(1 for j in _jobs.values() if j["status"] == "running")


# The page polls /jobs once a second; that poll doubles as a heartbeat.
# When it stops, the tab is gone (closed, crashed, navigated away).
# Chrome throttles timers in background tabs to about once per minute, so the
# timeout must stay comfortably above 60s or switching tabs would kill us.
_last_seen = time.monotonic()
IDLE_TIMEOUT = 90.0  # seconds of silence before we consider the tab closed


PAGE = """<!doctype html>
<meta charset="utf-8">
<title>ytd</title>
<style>
  body { font-family: sans-serif; margin: 2rem; max-width: 40rem; }
  input { width: 100%; padding: .5rem; font-size: 1rem; }
  li { margin: .4rem 0; }
  .running { color: #b58900; }
  .done    { color: #268bd2; }
  .failed  { color: #dc322f; }
</style>

<h1>ytd</h1>
<p>Saving <b>{KIND}</b> to <code>{OUT_DIR}</code></p>
<input id="url" placeholder="Paste a YouTube URL and press Enter" autofocus>
<ul id="jobs"></ul>

<script>
let active = 0;

document.getElementById('url').addEventListener('keydown', e => {
  if (e.key !== 'Enter' || !e.target.value.trim()) return;
  const url = e.target.value.trim();
  e.target.value = '';
  fetch('/add', { method: 'POST', body: url }).then(refresh);
});

function refresh() {
  fetch('/jobs').then(r => r.json()).then(jobs => {
    active = jobs.filter(j => j.status === 'running').length;
    document.getElementById('jobs').innerHTML = jobs.map(j =>
      `<li class="${j.status}">[${j.status}] ${escape_(j.error || j.name)}</li>`
    ).reverse().join('');
  });
}

function escape_(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

window.addEventListener('beforeunload', e => {
  if (active > 0) e.preventDefault();
});

// Best-effort "I'm gone" signal; the server also has an idle watchdog in case
// this never arrives (crash, killed tab).
window.addEventListener('pagehide', () => {
  if (active === 0) navigator.sendBeacon('/bye');
});

setInterval(refresh, 1000);
refresh();
</script>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    out_dir = "."
    video = False

    def _send(self, body: bytes, ctype: str) -> None:
        global _last_seen
        _last_seen = time.monotonic()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/":
            page = PAGE.replace("{OUT_DIR}", self.out_dir)
            page = page.replace("{KIND}", "mp4" if self.video else "mp3")
            self._send(page.encode("utf-8"), "text/html; charset=utf-8")
        elif self.path == "/jobs":
            body = json.dumps(_snapshot()).encode("utf-8")
            self._send(body, "application/json")
        else:
            self.send_error(404)

    def do_POST(self) -> None:  # noqa: N802
        global _last_seen
        if self.path == "/bye":
            # Tab closed cleanly: expire the heartbeat so the watchdog exits
            # on its next tick instead of waiting out IDLE_TIMEOUT.
            self._send(b"{}", "application/json")
            _last_seen = time.monotonic() - IDLE_TIMEOUT - 1
            return
        if self.path != "/add":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        url = self.rfile.read(length).decode("utf-8").strip()
        if url:
            _start_job(url, self.out_dir, self.video)
        self._send(b"{}", "application/json")

    def log_message(self, *args) -> None:
        pass  # keep the console clean for yt-dlp output


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


def _open_in_chrome(url: str) -> None:
    """Open Chrome specifically, falling back to the default browser."""
    if sys.platform == "win32":
        candidates = [
            os.path.join(p, "Google", "Chrome", "Application", "chrome.exe")
            for p in (
                os.environ.get("PROGRAMFILES", ""),
                os.environ.get("PROGRAMFILES(X86)", ""),
                os.environ.get("LOCALAPPDATA", ""),
            )
            if p
        ]
    else:
        candidates = [
            "google-chrome",
            "google-chrome-stable",
            "chromium",
            "chromium-browser",
        ]

    for cand in candidates:
        exe = cand if os.path.isfile(cand) else shutil.which(cand)
        if exe:
            subprocess.Popen([exe, url])
            return
    webbrowser.open(url)


def _watchdog(server: "Server") -> None:
    """Stop the server once the browser tab has gone away.

    A refresh only pauses polling for ~1s, well under IDLE_TIMEOUT, so it will
    not trigger. In-flight downloads keep the server alive until they finish.
    """
    while True:
        time.sleep(1.0)
        if _running_jobs():
            continue
        if time.monotonic() - _last_seen > IDLE_TIMEOUT:
            print("Tab closed, shutting down.")
            server.shutdown()
            return


def run_gui(out_dir: str, port: int = 8731, video: bool = False) -> int:
    global _last_seen
    Handler.out_dir = out_dir
    Handler.video = video
    server = Server(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    print(f"ytd GUI on {url}  (Ctrl+C to stop)")
    _open_in_chrome(url)
    # Give Chrome time to start and load the page before the watchdog counts.
    _last_seen = time.monotonic() + 10.0
    threading.Thread(target=_watchdog, args=(server,), daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    return 0


# =====================================================================
# Entry point
# =====================================================================


def main() -> int:
    prog = os.path.basename(sys.argv[0])
    args = sys.argv[1:]

    video = "--video" in args
    args = [a for a in args if a != "--video"]

    if args == ["--gui"]:
        return run_gui(os.getcwd(), video=video)

    if len(args) != 1 or args[0].startswith("--"):
        print(f"Usage: {prog} [--video] <youtube-url>", file=sys.stderr)
        print(f"       {prog} --gui [--video]", file=sys.stderr)
        return 2

    url = args[0]
    out_dir = os.getcwd()
    try:
        download(url, out_dir, video=video)
    except Exception as exc:  # noqa: BLE001
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
