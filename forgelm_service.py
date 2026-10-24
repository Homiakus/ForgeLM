#!/usr/bin/env python3
"""ForgeLM Server daemon and controller."""

import os
import sys
import subprocess
import time
import urllib.request
import json
from pathlib import Path

MODEL_DEFAULT = "/run/media/den/Новый том/60-69 ML Artifacts/phi-4mini/Phi-4-Mini-3.8B-Q4_K_L-Tao-Integrated.gguf"
PORT_DEFAULT = 8080
PID_FILE = Path("/tmp/forgelm.pid")
LOG_FILE = Path("/tmp/forgelm.log")

def is_running(port=PORT_DEFAULT):
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/models")
        with urllib.request.urlopen(req, timeout=1) as resp:
            data = json.loads(resp.read().decode())
            return "data" in data or "models" in data
    except Exception:
        return False

def start(model=MODEL_DEFAULT, port=PORT_DEFAULT, ctx=16384, threads=6):
    if is_running(port):
        print(f"[ForgeLM] Server is already running on http://127.0.0.1:{port}")
        return 0

    script_dir = Path(__file__).parent.resolve()
    standalone = script_dir / "bin" / "forgelm_standalone"
    if standalone.exists() and os.access(standalone, os.X_OK):
        print(f"[ForgeLM] Validating model using pure ASM standalone: {model}")
        subprocess.run([str(standalone), model])

    cmd = [
        "/home/den/.local/lib/ollama/llama-server",
        "-m", model,
        "--host", "127.0.0.1",
        "--port", str(port),
        "-c", str(ctx),
        "-np", "1",
        "-t", str(threads),
        "-tb", str(threads),
        "--jinja"
    ]
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"/home/den/.local/lib/ollama:{env.get('LD_LIBRARY_PATH', '')}"

    log_file = open(LOG_FILE, "a")

    proc = subprocess.Popen(cmd, env=env, stdout=log_file, stderr=log_file, start_new_session=True)
    PID_FILE.write_text(str(proc.pid))
    print(f"[ForgeLM] Started model server pid={proc.pid}, logging to {LOG_FILE}")

    # Wait for readiness
    for _ in range(60):
        time.sleep(1)
        if is_running(port):
            print(f"[ForgeLM] Server is ready on http://127.0.0.1:{port}/v1")
            return 0
    print("[ForgeLM] Server started, warming up in background.")
    return 0

def stop():
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, 15)
            print(f"[ForgeLM] Sent SIGTERM to pid {pid}")
            PID_FILE.unlink(missing_ok=True)
        except Exception as e:
            print(f"[ForgeLM] Error stopping pid: {e}")
    subprocess.run(["pkill", "-f", "/home/den/.local/lib/ollama/llama-server.*8080"], stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "start"
    model = sys.argv[2] if len(sys.argv) > 2 else MODEL_DEFAULT
    if action == "start":
        sys.exit(start(model=model))
    elif action == "stop":
        sys.exit(stop())
    elif action == "status":
        running = is_running()
        print(f"[ForgeLM] Status: {'RUNNING' if running else 'STOPPED'}")
        sys.exit(0 if running else 1)
