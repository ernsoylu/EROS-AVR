"""MCU hardware profiles.

Loads the default target (atmega328p) and re-exposes its tables as module-level
constants, so the current single-target consumers (model / emit) keep importing
KNOWN_PERIPHERALS etc. unchanged. Multi-target support (Phase 2) will thread an
MCUProfile object instead of relying on these module globals.
"""
from .profile import MCUProfile, load_profile

DEFAULT_MCU = "atmega328p"
_profile = load_profile(DEFAULT_MCU)

KNOWN_PERIPHERALS = _profile.known_peripherals
PERIPHERAL_PINS = _profile.peripheral_pins
CONFLICTS_HARD = _profile.conflicts
DRIVER_INIT = _profile.driver_init
DRIVER_HEADER = _profile.driver_header

__all__ = [
    "MCUProfile", "load_profile", "DEFAULT_MCU",
    "KNOWN_PERIPHERALS", "PERIPHERAL_PINS", "CONFLICTS_HARD",
    "DRIVER_INIT", "DRIVER_HEADER",
]
