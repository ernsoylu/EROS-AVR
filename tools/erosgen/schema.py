"""The versioned JSON Schema contract for app.yaml + its (optional) validator.

`schema/app.schema.json` (draft 2020-12) is the single declarative source for
the *static* app.yaml shape — section key sets, value types, and MCU-independent
enums/consts. It is plain JSON, so it is loaded with the stdlib (no third-party
dep) and drives `validate.ALLOWED_KEYS`, keeping the dep-free key check and the
schema from ever drifting apart.

Running the *full* schema (all draft-2020-12 keywords) needs the `jsonschema`
library, shipped as the opt-in ``[schema]`` extra. `validate_schema()` is a
no-op unless it is installed; the CLI exposes it behind ``--schema`` and feeds
every violation through the same `Diagnostics` sink as the code validators,
reusing their diagnostic codes via each node's ``x-eros-code`` annotation.
"""
import json
from pathlib import Path

from .diagnostics import Diagnostics

SCHEMA_PATH = Path(__file__).resolve().parent / "schema" / "app.schema.json"


def load_schema():
    """The parsed app.yaml JSON Schema (stdlib only; no jsonschema needed)."""
    return json.loads(SCHEMA_PATH.read_text())


# The `peripherals` $def is a schema-structural container (its properties are
# peripheral NAMES, which are MCU-dependent and policed in code), not a
# check_keys section, so it is excluded from the derived ALLOWED_KEYS.
_NON_SECTION_DEFS = {"peripherals"}


def section_keys():
    """section name -> set of allowed keys, read from the schema so it is the
    single source of truth for `validate.ALLOWED_KEYS`. 'doc' is the root
    object; every other name is a `$defs` entry (bar the structural container
    `peripherals`)."""
    schema = load_schema()
    nodes = {"doc": schema, **schema["$defs"]}
    return {name: set(node.get("properties", {}))
            for name, node in nodes.items() if name not in _NON_SECTION_DEFS}


def schema_available():
    """True if the [schema] extra (jsonschema) is importable."""
    try:
        import jsonschema  # noqa: F401
        return True
    except ImportError:
        return False


def _code(err):
    """The diagnostic code for a jsonschema error: the failing node's
    ``x-eros-code`` when annotated (reuses the engine's vocabulary), else a
    generic ``SCHEMA_<keyword>``."""
    node = err.schema if isinstance(err.schema, dict) else {}
    return node.get("x-eros-code") or f"SCHEMA_{str(err.validator).upper()}"


def _location(err):
    """Dotted path to the offending element, e.g. 'peripherals.spi.mode' or
    'tasks.0.name'; '' for a root-level violation."""
    return ".".join(str(p) for p in err.absolute_path)


def validate_schema(doc, sink=None):
    """Validate `doc` against the JSON Schema, reporting each violation through
    `sink` (a fresh collect-mode Diagnostics if none is given). Returns the
    sink. Requires the [schema] extra; without it, emits one SCHEMA_UNAVAILABLE
    error so the caller never silently skips a requested check."""
    if sink is None:
        sink = Diagnostics(strict=False)
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        sink.warning("SCHEMA_UNAVAILABLE",
                     "schema validation needs the [schema] extra "
                     "(uv sync --extra schema)", "")
        return sink
    validator = Draft202012Validator(load_schema())
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path)):
        sink.error(_code(err), err.message, _location(err))
    return sink
