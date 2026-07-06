/**
 * @file    test_eeprom.c
 * @brief   Pure-firmware test of the EEPROM driver under simavr.
 *
 * simavr models the ATmega328P EEPROM as real memory with the EEPE
 * programming delay, so read/update/wear behaviour is fully verifiable
 * on-chip with no host stimulus.
 */

#include <avr/io.h>
#include "eeprom.h"
#include "testkit.h"

int main(void)
{
    uint8_t buf[4];

    tk_init();

    /* Fresh EEPROM in simavr reads as erased (0xFF). */
    TK_ASSERT(Eep_ReadByte(0) == 0xFFu, "erased-0");
    TK_ASSERT(Eep_ReadByte(EE_SIZE - 1u) == 0xFFu, "erased-last");

    /* Out-of-range read returns the erased value, not garbage. */
    TK_ASSERT(Eep_ReadByte(EE_SIZE) == 0xFFu, "oob-read");

    /* Single-byte update round-trips. */
    Eep_UpdateByte(10u, 0xA5u);
    TK_ASSERT(Eep_ReadByte(10u) == 0xA5u, "update-byte");

    /* Ready flag clear once programming settled. */
    TK_ASSERT(Eep_IsReady() == 1u, "ready-after-write");

    /* Wear-aware skip: rewriting the same value must not corrupt it. */
    Eep_UpdateByte(10u, 0xA5u);
    TK_ASSERT(Eep_ReadByte(10u) == 0xA5u, "wear-skip");

    /* Overwrite with a new value. */
    Eep_UpdateByte(10u, 0x3Cu);
    TK_ASSERT(Eep_ReadByte(10u) == 0x3Cu, "overwrite");

    /* Multi-byte block update + read-back. */
    {
        const uint8_t src[4] = { 0xDEu, 0xADu, 0xBEu, 0xEFu };
        Eep_Update(100u, src, 4u);
        Eep_Read(100u, buf, 4u);
        TK_ASSERT(buf[0] == 0xDEu && buf[1] == 0xADu &&
                  buf[2] == 0xBEu && buf[3] == 0xEFu, "block-rw");
    }

    tk_pass();
}
