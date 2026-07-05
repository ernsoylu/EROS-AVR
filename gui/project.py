"""GUI-agnostic project model: the bridge between the erosgen engine and the UI.

Holds the loaded app.yaml as a ruamel round-trip document (comments/formatting
preserved on save) and exposes the engine's results as plain data plus
load/save/generate actions. No Qt here - fully unit-testable.
"""
import contextlib
import io
from pathlib import Path

from ruamel.yaml import YAML

import erosgen

_yaml = YAML()          # round-trip by default (preserves comments + key order)
_yaml.preserve_quotes = True
_yaml.indent(mapping=2, sequence=4, offset=2)  # keep indented block sequences
# NOTE: ruamel preserves comments and structure; flow-map inner spacing
# ({ a } -> {a}) may still normalize on save. Comment preservation is the point.


def _plain(x):
    """Deep-convert ruamel CommentedMap/Seq to plain dict/list for the engine."""
    if isinstance(x, dict):
        return {k: _plain(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [_plain(v) for v in x]
    return x


class ProjectModel:
    def __init__(self, path=None):
        self.path = None
        self.doc = {}
        if path:
            self.load(path)

    def load(self, path):
        self.path = Path(path)
        self.doc = _yaml.load(self.path.read_text()) or {}

    def save(self, path=None):
        self.path = Path(path or self.path)
        with self.path.open("w") as f:
            _yaml.dump(self.doc, f)

    @property
    def plain(self):
        return _plain(self.doc)

    def _system(self):
        return self.plain.get("system") or {}

    @property
    def name(self):
        return self._system().get("name", "app")

    @property
    def mcu(self):
        return self._system().get("mcu", "atmega328p")

    def tasks(self):
        rows = []
        for t in self.plain.get("tasks", []) or []:
            if not isinstance(t, dict):
                continue
            if t.get("autostart"):
                kind = "autostart"
            elif t.get("period_ms") is not None:
                kind = f"{t['period_ms']} ms"
            else:
                kind = "aperiodic"
            rows.append({"name": t.get("name", "?"), "kind": kind,
                         "wcet_ms": t.get("wcet_ms", 1)})
        return rows

    def models(self):
        rows = []
        for m in self.plain.get("models", []) or []:
            if isinstance(m, dict):
                rows.append({"name": m.get("name", "?"),
                             "rate_ms": m.get("rate_ms"),
                             "codegen_dir": m.get("codegen_dir", "")})
        return rows

    def diagnostics(self):
        """Live, non-throwing [Diagnostic] for the current (possibly invalid)
        document - the GUI's problem list."""
        return erosgen.collect_diagnostics(self.plain,
                                           self.path or Path("app.yaml"))

    # ---- editing --------------------------------------------------------
    def available_mcus(self):
        """MCU profiles the engine can target (mcu/*.yaml stems)."""
        mcu_dir = Path(erosgen.__file__).resolve().parent / "mcu"
        return sorted(p.stem for p in mcu_dir.glob("*.yaml"))

    def set_mcu(self, name):
        """Edit the target MCU in the live document (diagnostics update next
        time they're read - that's the live-editing loop)."""
        self.doc.setdefault("system", {})["mcu"] = name

    def budget(self):
        """Pre-flash static-RAM plan (bytes) - what the tool's report prints, so
        'too much RAM' is visible before building. None if the config is invalid.
        NOTE: true flash/RAM needs a compile (avr-size); this is the deliberate,
        over-counting non-LTO estimate."""
        try:
            s = erosgen.System(self.plain, self.path or Path("app.yaml"))
        except erosgen.ConfigError:
            return None
        uart = s.peripherals.get("uart")
        rings = 0
        if uart is not None:
            uart = uart or {}
            rings = int(uart.get("tx_ring", 128)) + int(uart.get("rx_ring", 64))
        b = s.budget or {}
        return {
            "kernel": 35,                                  # matches report()
            "arena": s.pool_block * s.pool_blocks,
            "rings": rings,
            "sram_total": int(b.get("sram_total", 2048)),
        }

    # ---- new project + editing -----------------------------------------
    def new(self, name="app", mcu="atmega328p"):
        """Start a fresh, unsaved project from a minimal valid skeleton."""
        self.path = None
        self.doc = {
            "system": {"name": name, "mcu": mcu,
                       "hooks": {"startup": True, "error": True,
                                 "shutdown": True}},
            "tasks": [
                {"name": "init", "autostart": True, "wcet_ms": 1},
                {"name": "main", "period_ms": 100, "wcet_ms": 1},
            ],
            "resources": [{"name": "app", "users": ["main"]}],
        }

    def set_name(self, name):
        self.doc.setdefault("system", {})["name"] = name

    def add_task(self, name, period_ms=None, wcet_ms=1, autostart=False):
        t = {"name": name, "wcet_ms": int(wcet_ms)}
        if autostart:
            t["autostart"] = True
        elif period_ms is not None:
            t["period_ms"] = int(period_ms)
        self.doc.setdefault("tasks", []).append(t)

    def remove_task(self, name):
        tasks = self.doc.get("tasks")
        if isinstance(tasks, list):
            self.doc["tasks"] = [t for t in tasks if not (
                isinstance(t, dict) and t.get("name") == name)]

    def generate(self):
        """Save, then run the generator. Returns (ok, report_text)."""
        if self.path is None:
            raise ValueError("save the project before generating")
        self.save()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = erosgen.main(["erosgen", str(self.path)])
        return rc == 0, buf.getvalue()
