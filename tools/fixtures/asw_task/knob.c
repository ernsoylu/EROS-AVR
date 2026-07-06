/**
 * @file    knob.c
 * @brief   Hand-authored ASW runnable for 'knob' (10 ms).
 *
 * Generated once by tools/erosgen.py - EDIT FREELY; not overwritten.
 */

#include "knob.h"
#include "knob_Intfc.h"
#include "knob_Param.h"

void knob_initialize(void)
{
    /* no state to initialize */
}

/** knob step: the LED tracks whether the knob reading is at/above the
 *  Knb_Thresh calibration. The RTE moves IN_KnbVal in from the ADC and
 *  OUT_Led out to the dio pin, so the runnable only touches its ports. */
void knob_Runnable(void)
{
    OUT_Led = (uint8_t)(IN_KnbVal >= Knb_Thresh);
}
