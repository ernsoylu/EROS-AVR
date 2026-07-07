/**
 * @file    usb_cdc.h
 * @brief   Native USB CDC-ACM console for the ATmega32U4 (Leonardo / Micro).
 *
 * A drop-in replacement for the USART `uart.c` console on parts with an on-chip
 * USB device: it exports the SAME `Uart_*` API (so application code and the
 * erosgen-generated `Uart_Init()` call are unchanged), but the bytes travel over
 * a USB CDC virtual serial port instead of a USART. Link `usb_cdc.c` INSTEAD of
 * `uart.c` (they define the same symbols).
 *
 *   TX: Uart_PutChar()/Uart_Print*() enqueue into a ring; the USB SOF / endpoint
 *       ISR flushes it to the bulk-IN endpoint. Ring full -> byte dropped+counted
 *       (a task never blocks on the host).
 *   RX: the bulk-OUT endpoint ISR captures bytes into a second ring; tasks poll
 *       with Uart_GetChar().
 *
 * ISR category (OSEK): the two USB ISRs (USB_GEN / USB_COM) are Category 1 - they
 * touch only the rings and the USB hardware and MUST NOT call any OS service.
 *
 * Scope: this implements USB 2.0 CDC-ACM enumeration + a single virtual COM port
 * per the ATmega32U4 datasheet (USB device mode) and the CDC-ACM class spec. It
 * is compile/link-verified in CI; enumeration against a USB host is validated on
 * hardware (CI has no USB host). On parts without an on-chip USB controller the
 * whole translation unit compiles to nothing (guarded by `#if defined(USBCON)`),
 * so it is safe in the all-MCU driver gate.
 */
#ifndef USB_CDC_H
#define USB_CDC_H

#include <stdint.h>
#include <avr/pgmspace.h>

/** Bring up the USB device (PLL, controller, attach) and arm enumeration.
 *  Non-blocking: the host enumerates asynchronously - poll Cdc_IsConfigured().
 *  Call with interrupts disabled (e.g. from StartupHook()), like Uart_Init(). */
void Uart_Init(void);

/** Enqueue one byte for background transmission over the CDC IN endpoint.
 *  @return 1 = queued, 0 = ring full (byte dropped and counted). */
uint8_t Uart_PutChar(char c);

/** Enqueue a RAM string. */
void Uart_Print(const char *s);

/** Enqueue a PROGMEM string (use with PSTR("...")). */
void Uart_Print_P(PGM_P s);

/** Enqueue an unsigned 16-bit value in decimal. */
void Uart_PrintU16(uint16_t value);

/** Enqueue an 8-bit value as two hex digits. */
void Uart_PrintHex8(uint8_t value);

/** Fetch one received byte if available.
 *  @return 1 = *c valid, 0 = RX ring empty. */
uint8_t Uart_GetChar(char *c);

/** Number of TX bytes dropped because the ring was full (diagnostic). */
uint8_t Uart_TxDropped(void);

/** 1 once the host has enumerated + configured the device (SET_CONFIGURATION);
 *  0 before then. Useful to gate first output until the port is open. */
uint8_t Cdc_IsConfigured(void);

#endif /* USB_CDC_H */
