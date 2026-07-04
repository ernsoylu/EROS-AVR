# ATmega328P — Bare-Metal Arduino Nano Programming

A step-by-step learning path for bare-metal C on the Arduino Nano
(ATmega328P, 16 MHz, 2 KiB SRAM, 32 KiB Flash) **without the Arduino
framework** — just `avr-gcc`, `<avr/io.h>` and the datasheet. The
examples build on each other: each folder introduces one concept, and
the final demo integrates all of them on a small OSEK-style real-time
kernel written in this repo.

| # | Folder | You learn | Peripherals |
|---|--------|-----------|-------------|
| 01 | [`01-Setup`](01-Setup/) | toolchain bring-up, GPIO output, delay-loop blink | GPIO |
| 02 | [`02-GPIO`](02-GPIO/) | GPIO input, internal pull-ups, polling a button | GPIO |
| 03 | [`03-SerialMonitor`](03-SerialMonitor/) | UART 8N1, polled TX/RX, a serial command parser | USART0 |
| 04 | [`04-ManualScheduler`](04-ManualScheduler/) | timer tick interrupt, cooperative flag scheduler | Timer0 |
| 05 | [`05-TinyOS`](05-TinyOS/TinyOS/) | **TinyOS**: an OSEK BCC1 real-time kernel (tasks, alarms, resources, IPC, watchdog) | Timer2, WDT |
| 06 | [`06-PWM`](06-PWM/) | hardware PWM (fast PWM, TOP/duty math) | Timer0/1/2 |
| 07 | [`07-ComprehensiveDemo`](07-ComprehensiveDemo/ComprehensiveDemo/) | **everything above, integrated on TinyOS** | all of them |

Folders 01–04 and 06 are [PlatformIO](https://platformio.org/) projects
(`pio run -t upload` inside the inner project folder). 05 and 07 use a
plain `avr-gcc` Makefile (`make`, `make flash`) to show exactly what the
toolchain does.

> **Nano bootloader note:** most Nano clones ship the *old* ATmegaBOOT
> bootloader → program at **57600 baud** (`make flash`, or
> `upload_speed = 57600` in `platformio.ini`). Boards re-burned with
> Optiboot use 115200 (`make flash BAUD=115200`).

---

## 01-Setup — SetupAndBlink

The "hello world" of bare metal: configure PB5 (Nano D13, on-board LED)
as an output via the **data direction register**, then toggle it with an
XOR on the **port register** and a busy-wait delay.

```c
DDRB  |= (1 << PB5);   // direction: output
PORTB ^= (1 << PB5);   // toggle output latch
_delay_ms(2000);       // burn 32 million cycles doing nothing
```

What to take away:

- Every GPIO pin is three registers: `DDRx` (direction), `PORTx`
  (output latch / pull-up enable), `PINx` (input readback).
- `_delay_ms()` needs `F_CPU` defined at compile time — it is a
  calibrated busy loop, not a timer.
- **Limitation to notice** (fixed in 04): while the CPU is inside
  `_delay_ms()` it can do *nothing else*. Also note the comment in the
  source says 500 ms while the code waits 2000 ms — trust code, not
  comments.

## 02-GPIO — button input

Reads a push button on PD2 (Nano D2) using the **internal pull-up**
(button wired to GND, no external resistor needed) and mirrors it to the
LED:

```c
DDRD  &= ~(1 << PD2);  // input
PORTD |=  (1 << PD2);  // enable internal pull-up
if ((PIND & (1 << PD2)) == 0) { /* pressed (active low) */ }
```

What to take away:

- Writing `PORTx` bits while the pin is an *input* controls the pull-up.
- With a pull-up the switch is **active-low**: pressed reads 0.
- The 10 ms poll acts as crude debouncing; 07 shows a real 8-sample
  debounce filter.

## 03-SerialMonitor — polled UART

A USART0 driver (9600 8N1) plus a small line parser: type `ON` or `OFF`
in a serial monitor to switch the LED. Baud rate comes from
`UBRR = F_CPU / (16 * baud) - 1`.

What to take away:

- TX: wait for `UDRE0` (data register empty), then write `UDR0`.
  RX: wait for / test `RXC0`, then read `UDR0`.
- 8N1 frame setup via `UCSZ01:UCSZ00`; enable with `RXEN0 | TXEN0`.
- **Limitation to notice** (fixed in 07): this driver is *polled* —
  `uart_print()` blocks ~1 ms per character at 9600 baud. Fine in a
  super-loop; unacceptable inside a scheduler, where one 40-character
  line would stall every task for 40 ms. 07 replaces it with an
  interrupt-driven ring-buffer driver.

## 04-ManualScheduler — tick interrupt + flag scheduler

The first step from "delay loops" to "real-time": Timer0 in CTC mode
fires an interrupt every 1 ms (`16 MHz / 64 / 250`), the ISR raises
period flags (10/50/100 ms), and the main loop runs a task when its flag
is set — a classic cooperative super-loop scheduler.

What to take away:

- CTC math: `OCR0A = 249` with prescaler 64 → exactly 1 kHz.
- ISR/main-loop communication needs `volatile` flags.
- Tasks must be short: a slow task delays every other task (this
  motivates the WCET budgets that TinyOS enforces).
- **Bug to notice** (intentional learning material): the tasks toggle
  pins with `PIND |= (1 << PD2);`. That compiles to a
  read-modify-write: it reads *all* PIND bits and writes back every bit
  that reads 1 — toggling **every** high pin of the port, not just PD2.
  It only appears to work because the demo toggles pins that are rarely
  high simultaneously… on a port with several outputs it corrupts them.
  The correct idiom is a plain store: `PIND = (1 << PD2);` (writing 1
  to a `PINx` bit toggles that pin in hardware — atomic, single
  instruction). 05 and 07 use the correct form.
- **Limitations to notice** (fixed in 05): flags silently overwrite
  (a missed 10 ms slot is lost with no error), there are no priorities,
  no overrun detection, no power management — the loop spins even when
  idle. That is exactly the feature list of TinyOS.

## 05-TinyOS — an OSEK BCC1 real-time kernel

The centrepiece of the repo: **TinyOS**, a statically configured,
non-preemptive, run-to-completion OSEK BCC1 kernel in ~1.8 KiB of Flash
and ~35 bytes of kernel RAM. Highlights:

- O(1) priority scheduler (8-bit ready mask + PROGMEM nibble LUT)
- OSEK task API (`ActivateTask`, `ChainTask`, implicit `TerminateTask`)
  with BCC1 activation limits and `ErrorHook` diagnostics
- Cyclic/one-shot alarms on a wrap-safe 1 kHz Timer2 tick,
  `SetRelAlarm` / `SetAbsAlarm` / `CancelAlarm`
- IPCP resources, single-slot mailbox, O(1) fixed-block memory pool
- Stack canary, watchdog with per-task aliveness supervision,
  `SLEEP_MODE_IDLE` when nothing is ready
- Old-bootloader-safe early watchdog disable in `.init3`

See [`05-TinyOS/TinyOS/README.md`](05-TinyOS/TinyOS/README.md) for the
architecture guide, API reference, memory budgets and scope-measurement
instructions. The kernel itself lives in
[`05-TinyOS/TinyOS/kernel/`](05-TinyOS/TinyOS/kernel/) and is reused
unchanged by example 07 — only the static configuration differs.

## 06-PWM — hardware PWM

A PWM driver for Timer1 (16-bit, fast PWM mode 14 with `ICR1` as TOP)
and Timer2 (8-bit), plus the Timer0 tick scheduler from 04 ramping the
duty cycle on OC1A (Nano D9).

What to take away:

- Fast PWM frequency: `f = F_CPU / (prescaler * (TOP + 1))`; duty is the
  compare register / TOP ratio — the LED brightens as OCR1A rises.
- Non-inverting output needs `COM1A1`; the pin must also be set as
  output via `DDRx`.
- Timer choice matters: each timer has *different* prescaler tables and
  mode bits, and a timer used for PWM can't simultaneously be the system
  tick. (In 07, Timer2 belongs to TinyOS, so PWM moves to Timer1.)
- The 16-bit `OCR1A`/`ICR1` accesses go through a shared TEMP register —
  keep them atomic once interrupts are involved.

## 07-ComprehensiveDemo — everything, integrated on TinyOS

All of the above running concurrently as **five TinyOS tasks**: heartbeat
LED (01), debounced button (02), an interrupt-driven serial monitor with
`ON`/`OFF`/`STAT` commands (03), TinyOS alarms replacing the manual flag
scheduler (04), and a Timer1 PWM breathing LED (06) — plus TinyOS
extras: button events travel to the command task through a memory-pool
block posted into the mailbox, the watchdog supervises all periodic
tasks, and the status line reports the reset cause and error counters.

See [`07-ComprehensiveDemo/ComprehensiveDemo/README.md`](07-ComprehensiveDemo/ComprehensiveDemo/README.md)
for wiring, the serial protocol and expected output.

---

## Suggested path

1. Blink an LED (01), then read a button (02) — registers and polling.
2. Talk to a PC (03) — peripherals with status flags.
3. Replace delays with a tick interrupt (04) — the cooperative pattern.
4. Study TinyOS (05) — what a real kernel adds: priorities, alarms,
   error handling, memory safety, supervision.
5. Add PWM (06) — timers as waveform generators.
6. Read 07 top to bottom — how drivers, tasks and the kernel compose
   into a small but production-shaped firmware.
