"""MCU hardware profile loaded from mcu/<name>.yaml.

Phase 0 externalizes the ATmega328P tables into data so adding a target is a
new YAML file, not a code change. Phase 2 (atmega2560) threads an MCUProfile
through System/emitters; today the package __init__ still exposes the default
profile's tables as module-level constants for the single-target consumers.
"""
from dataclasses import dataclass
from pathlib import Path

import yaml

PROFILE_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class MCUProfile:
    name: str
    known_peripherals: dict   # peripheral -> driver source .c
    peripheral_pins: dict     # peripheral -> [pin, ...]
    conflicts: list           # [(a, b, reason), ...]
    driver_init: dict         # peripheral -> Init() call
    driver_header: dict       # peripheral -> header

    @classmethod
    def load(cls, name):
        path = PROFILE_DIR / f"{name}.yaml"
        if not path.exists():
            avail = ", ".join(sorted(p.stem for p in PROFILE_DIR.glob("*.yaml")))
            raise FileNotFoundError(
                f"erosgen: no MCU profile '{name}' at {path} (have: {avail})")
        d = yaml.safe_load(path.read_text()) or {}
        return cls(
            name=d.get("name", name),
            known_peripherals=dict(d.get("peripherals", {})),
            peripheral_pins={k: list(v)
                             for k, v in (d.get("peripheral_pins") or {}).items()},
            conflicts=[tuple(c) for c in (d.get("conflicts") or [])],
            driver_init=dict(d.get("driver_init", {})),
            driver_header=dict(d.get("driver_header", {})),
        )


def load_profile(name="atmega328p"):
    return MCUProfile.load(name)
