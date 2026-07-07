#!/usr/bin/env bash
#
# eros.sh - environment setup + GUI launcher for EROS (the OSEK BCC1 AVR kernel
#           and its erosgen configurator in this repository).
#
# Generating, building and flashing an application now live in the GUI
# (`uv run -m gui`) and the per-app Makefiles, so this script's job is just to
# get the machine ready and launch the configurator.
#
# Usage:
#   ./eros.sh [gui]           check the environment is ready, then launch the GUI
#   ./eros.sh check           verify avr-gcc, avr-libc, simavr, uv + GUI deps
#   ./eros.sh install         install the AVR toolchain, simavr, uv and GUI deps
#   ./eros.sh flash <f.hex>   auto-detect the board and flash a built .hex
#   ./eros.sh help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCU=atmega328p
F_CPU=16000000UL

# ----- pretty output (degrades gracefully when not a TTY) ---------------
if [[ -t 1 ]]; then
    C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[1m'; C_N=$'\e[0m'
else
    C_R=; C_G=; C_Y=; C_B=; C_N=
fi
say()   { printf '%s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_N"; }
ok()    { printf '  %s[ ok ]%s %s\n'  "$C_G" "$C_N" "$*"; }
warn()  { printf '  %s[warn]%s %s\n'  "$C_Y" "$C_N" "$*"; }
bad()   { printf '  %s[MISS]%s %s\n'  "$C_R" "$C_N" "$*"; }
die()   { printf '%serror:%s %s\n' "$C_R" "$C_N" "$*" >&2; exit 1; }

# ----- environment check ------------------------------------------------
MISSING=0        # required components missing
MISSING_OPT=0    # optional components missing

check_tool() {   # check_tool <command> <required:0|1> <hint>
    local tool=$1 required=$2 hint=$3 ver
    if command -v "$tool" >/dev/null 2>&1; then
        ver=$("$tool" --version 2>/dev/null | head -n1 || true)
        ok "$(printf '%-13s %s' "$tool" "$ver")"
    else
        if [[ "$required" -eq 1 ]]; then
            bad "$(printf '%-13s missing  (%s)' "$tool" "$hint")"
            MISSING=$((MISSING + 1))
        else
            warn "$(printf '%-13s missing  (%s)' "$tool" "$hint")"
            MISSING_OPT=$((MISSING_OPT + 1))
        fi
    fi
}

check_avrlibc() {
    # A working avr-gcc does not guarantee avr-libc headers + device support;
    # prove it by compiling a tiny program for the target MCU.
    if ! command -v avr-gcc >/dev/null 2>&1; then
        bad "avr-libc      cannot test (avr-gcc missing)"
        MISSING=$((MISSING + 1)); return
    fi
    local tmp; tmp=$(mktemp "${TMPDIR:-/tmp}/eros_XXXXXX.c")
    printf '#include <avr/io.h>\n#include <avr/interrupt.h>\nint main(void){return 0;}\n' > "$tmp"
    if avr-gcc -mmcu="$MCU" -DF_CPU="$F_CPU" -c -o /dev/null "$tmp" 2>/dev/null; then
        ok "avr-libc      headers + $MCU device support present"
    else
        bad "avr-libc      missing headers or $MCU support"
        MISSING=$((MISSING + 1))
    fi
    rm -f "$tmp"
}

check_uv_gui() {
    # uv drives the Python env; the GUI needs the [gui] extra (PySide6 +
    # ruamel.yaml) importable. (The engine, erosgen, is pure PyYAML.)
    if command -v uv >/dev/null 2>&1; then
        ok "$(printf '%-13s %s' uv "$(uv --version 2>/dev/null | head -n1 || true)")"
    else
        bad "$(printf '%-13s missing  (curl -LsSf https://astral.sh/uv/install.sh | sh)' uv)"
        MISSING=$((MISSING + 1)); return
    fi
    if (cd "$SCRIPT_DIR" && uv run --extra gui python -c 'import PySide6, ruamel.yaml' >/dev/null 2>&1); then
        ok "GUI deps      PySide6 + ruamel.yaml importable"
    else
        bad "GUI deps      missing  (./eros.sh install  ->  uv sync --extra gui)"
        MISSING=$((MISSING + 1))
    fi
}

do_check() {
    head1 "EROS environment check ($MCU @ ${F_CPU%UL})"
    check_tool make        1 "GNU make"
    check_tool avr-gcc     1 "gcc-avr"
    check_tool avr-objcopy 1 "binutils-avr"
    check_tool avr-size    1 "binutils-avr"
    check_avrlibc
    check_tool simavr      1 "simavr (functional simulator; libsimavr for tests/)"
    check_uv_gui
    check_tool avrdude     0 "avrdude, needed only to flash a board"

    echo
    if [[ "$MISSING" -eq 0 ]]; then
        say "${C_G}Environment ready.${C_N}"
        [[ "$MISSING_OPT" -gt 0 ]] && say "Some optional tools are missing (see above)."
        say "Launch the configurator: ${C_B}./eros.sh${C_N}   (or ./eros.sh gui)"
        return 0
    fi
    say "${C_R}$MISSING required component(s) missing.${C_N}"
    say "Install everything with: ${C_B}./eros.sh install${C_N}"
    return 1
}

# ----- install ----------------------------------------------------------
detect_pm() {
    local pm
    for pm in apt-get dnf yum pacman zypper apk brew; do
        command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
    done
    echo ""
}

install_uv() {
    if command -v uv >/dev/null 2>&1; then ok "uv already installed"; return; fi
    say "installing uv (astral.sh)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    command -v uv >/dev/null 2>&1 \
        || die "uv installed but not on PATH; open a new shell (or add ~/.local/bin to PATH) and re-run ./eros.sh install."
}

do_install() {
    head1 "EROS environment install"
    local pm; pm=$(detect_pm)
    [[ -z "$pm" ]] && die "no supported package manager (apt/dnf/yum/pacman/zypper/apk/brew). Install gcc-avr, avr-libc, binutils-avr, simavr, avrdude and make manually, then re-run ./eros.sh install for the uv/GUI deps."

    local sudo_cmd=""
    if [[ "$(id -u)" -ne 0 ]] && [[ "$pm" != "brew" ]]; then
        if command -v sudo >/dev/null 2>&1; then sudo_cmd="sudo"
        else die "not root and sudo not available; re-run as root."; fi
    fi

    say "Package manager: $pm  (AVR toolchain + simavr)"
    case "$pm" in
        apt-get)
            $sudo_cmd apt-get update
            $sudo_cmd apt-get install -y gcc-avr avr-libc binutils-avr avrdude make simavr libsimavr-dev
            ;;
        dnf|yum)
            $sudo_cmd "$pm" install -y avr-gcc avr-libc avr-binutils avrdude make simavr
            ;;
        pacman)
            $sudo_cmd pacman -Sy --needed --noconfirm avr-gcc avr-libc avr-binutils avrdude make simavr
            ;;
        zypper)
            $sudo_cmd zypper --non-interactive install cross-avr-gcc cross-avr-binutils avr-libc avrdude make simavr \
                || die "openSUSE package names vary by release; install a cross-avr-gcc*, cross-avr-binutils, avr-libc, simavr, avrdude and make manually."
            ;;
        apk)
            $sudo_cmd apk add gcc-avr avr-libc binutils-avr avrdude make simavr
            ;;
        brew)
            brew tap osx-cross/avr
            brew install avr-gcc avrdude simavr   # make ships with the Xcode CLT
            ;;
        *)
            die "internal: unhandled package manager '$pm'"
            ;;
    esac

    echo
    install_uv
    say "installing Python + GUI dependencies (uv sync --extra gui)..."
    (cd "$SCRIPT_DIR" && uv sync --extra gui)

    echo
    say "Install step finished; re-checking..."
    MISSING=0; MISSING_OPT=0
    do_check
}

# ----- gui launcher -----------------------------------------------------
do_gui() {
    # uv + the GUI deps are required to even open the window; the AVR toolchain
    # and simavr are only needed to Build / Simulate, so those are just warnings.
    command -v uv >/dev/null 2>&1 || die "uv not found; run ./eros.sh install"
    if ! (cd "$SCRIPT_DIR" && uv run --extra gui python -c 'import PySide6' >/dev/null 2>&1); then
        die "GUI dependencies missing; run ./eros.sh install (uv sync --extra gui)"
    fi
    command -v avr-gcc >/dev/null 2>&1 || warn "avr-gcc missing - you can edit/generate but not Build (./eros.sh install)"
    command -v simavr  >/dev/null 2>&1 || warn "simavr missing - functional simulation unavailable (./eros.sh install)"

    head1 "Launching EROS Configurator"
    cd "$SCRIPT_DIR"
    exec uv run --extra gui python -m gui "$@"
}

# ----- flash (build now happens in the GUI / the app Makefile) ----------
# Candidate serial ports (Linux ttyUSB/ttyACM, macOS cu.usb*). Only paths that
# actually exist are printed - literal unmatched globs are skipped.
detect_ports() {
    local p
    for p in /dev/ttyUSB* /dev/ttyACM* \
             /dev/cu.usbserial* /dev/cu.wchusbserial* /dev/cu.usbmodem* \
             /dev/tty.usbserial* /dev/tty.wchusbserial*; do
        [[ -e "$p" ]] && printf '%s\n' "$p"
    done
}

# Probe: does an ATmega328P answer on this port+baud via the arduino
# (bootloader) programmer? Signature read only, no write.
probe_target() {   # probe_target <port> <baud>
    avrdude -p m328p -c arduino -P "$1" -b "$2" -qq >/dev/null 2>&1
}

do_flash() {
    command -v avrdude >/dev/null 2>&1 \
        || die "avrdude not found; run ./eros.sh install (or install avrdude) to flash."
    local hex=${1:-}
    [[ -z "$hex" ]] && die "usage: ./eros.sh flash <file.hex>  (build it in the GUI, or 'make -C <app-dir>')"
    [[ -f "$hex" ]] || die "firmware not found: $hex"

    head1 "Flashing $(basename "$hex")"

    local pport=${EROS_PORT:-} pbaud=${EROS_BAUD:-}
    local ports=() bauds=()
    if [[ -n "$pport" ]]; then
        ports=("$pport")
    else
        local line
        while IFS= read -r line; do ports+=("$line"); done < <(detect_ports)
        [[ "${#ports[@]}" -eq 0 ]] && die "no serial port found (looked for /dev/ttyUSB*, /dev/ttyACM*, /dev/cu.usb*). Plug in the board, or set EROS_PORT=/dev/..."
    fi
    if [[ -n "$pbaud" ]]; then bauds=("$pbaud"); else bauds=(57600 115200); fi

    say "candidate ports: ${ports[*]}"
    local port baud found_port="" found_baud=""
    for port in "${ports[@]}"; do
        for baud in "${bauds[@]}"; do
            printf '  probing %-16s @ %-6s ... ' "$port" "$baud"
            if probe_target "$port" "$baud"; then
                printf '%sok%s\n' "$C_G" "$C_N"
                found_port=$port; found_baud=$baud; break 2
            fi
            printf 'no response\n'
        done
    done
    [[ -z "$found_port" ]] && die "no ATmega328P responded (ports: ${ports[*]}, bauds: ${bauds[*]}). Check the cable/board, or force with EROS_PORT= and EROS_BAUD=."

    say "target: ${C_B}ATmega328P on $found_port @ $found_baud baud${C_N}"
    echo
    avrdude -p m328p -c arduino -P "$found_port" -b "$found_baud" -U flash:w:"$hex":i
    echo
    say "${C_G}Flashed${C_N} $hex -> $found_port"
}

usage() {
    cat <<'EOF'
eros.sh - environment setup + GUI launcher for EROS.

Generating, building and flashing an application live in the GUI
(`uv run -m gui`) and the per-app Makefiles; this script gets the machine
ready and launches the configurator.

Usage:
  ./eros.sh [gui]           check the environment is ready, then launch the GUI
  ./eros.sh check           verify avr-gcc, avr-libc, simavr, uv + GUI deps
  ./eros.sh install         install the AVR toolchain, simavr, uv and GUI deps
                            (apt/dnf/pacman/zypper/apk/brew + astral.sh + uv sync)
  ./eros.sh flash <f.hex>   auto-detect the board + baud, then flash a built .hex
  ./eros.sh help

flash auto-detects the serial port (/dev/ttyUSB*, /dev/ttyACM*, /dev/cu.usb*
on macOS) and the bootloader baud (57600 old-bootloader Nano, then 115200
Optiboot) by probing the ATmega328P signature. Override with EROS_PORT and/or
EROS_BAUD.
EOF
}

# ----- dispatch ---------------------------------------------------------
case "${1:-gui}" in
    gui|-gui|--gui)             shift 2>/dev/null || true; do_gui "$@" ;;
    check|-check|--check)       do_check ;;
    install|-install|--install) do_install ;;
    flash|-flash|--flash)       shift 2>/dev/null || true; do_flash "${1:-}" ;;
    -h|-help|--help|help)       usage ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
esac
