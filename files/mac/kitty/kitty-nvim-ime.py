import base64
import os
import subprocess
import time

ENGLISH = "com.apple.keylayout.ABC"
MACISM = "@macism@"
STATE_FILE = f"/tmp/kitty-nvim-ime-last-{os.environ.get('USER', 'user')}"

# How long a switch we requested may take to show up in a query.
SETTLE_S = 0.5

# Target we last acted on, to skip redundant macism invocations.
_applied = None

# Input source we last asked for, and when, to tell our own output apart from
# the user's choice.
_commanded = None
_commanded_at = 0.0


def _macism(*args):
    try:
        result = subprocess.run(
            (MACISM, *args),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except Exception:
        return ""
    return result.stdout.strip()


def _read_last():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return f.readline().strip()
    except OSError:
        return ""


def _write_last(value):
    if value:
        try:
            with open(STATE_FILE, "w", encoding="utf-8") as f:
                f.write(value + "\n")
        except OSError:
            pass


def _command(source):
    global _commanded, _commanded_at
    _commanded = source
    _commanded_at = time.monotonic()
    _macism(source)


def _trust(current):
    # Anything but ENGLISH is the user's pick: we only ever ask for ENGLISH or
    # for the source we restored, and both mean they chose it.
    if current != ENGLISH:
        return True

    # ENGLISH is ambiguous. It is ours if a restore we requested has not landed
    # yet; past that window the restore must have taken effect, so reading
    # ENGLISH means the user switched to it themselves.
    if _commanded is None or _commanded == ENGLISH:
        return True
    return time.monotonic() - _commanded_at >= SETTLE_S


def _switch_to_normal():
    global _applied
    if _applied == "normal":
        return
    _applied = "normal"

    current = _macism()
    if current and _trust(current):
        _write_last(current)
    if current != ENGLISH:
        _command(ENGLISH)


def _switch_to_insert():
    global _applied
    if _applied == "insert":
        return
    _applied = "insert"

    saved = _read_last()
    # Normal mode already left us in ENGLISH; no need to ask for it again.
    if saved and saved != ENGLISH:
        _command(saved)


def _value(data):
    value = data.get("value")
    if isinstance(value, bytes):
        return value.decode("utf-8", "ignore")
    value = value or ""
    if value in ("insert", "normal"):
        return value
    try:
        return base64.b64decode(value).decode("utf-8", "ignore")
    except Exception:
        return value


def on_set_user_var(boss, window, data):
    if data.get("key") != "NVIM_MODE":
        return

    mode = _value(data)
    if mode == "insert":
        _switch_to_insert()
    elif mode == "normal":
        _switch_to_normal()
