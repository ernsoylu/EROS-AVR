"""MCU hardware profiles.

A profile (mcu/<name>.yaml) is the complete set of target-specific facts a
build needs: valid ports, board aliases, toolchain strings, and the
peripheral/pin/driver tables. System loads the one named by `system.mcu`
(default atmega328p) and the emitters read it, so adding a same-family target
is a new YAML file - no Python change. See profile.py.
"""
from .profile import MCUProfile, load_profile

DEFAULT_MCU = "atmega328p"

__all__ = ["MCUProfile", "load_profile", "DEFAULT_MCU"]
