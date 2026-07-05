/**
 * @file    asw_100ms.c
 * @brief   100 ms rate - TASK_BLINK.
 *
 * Generated once by tools/erosgen.py - edit freely; it will not
 * be overwritten. Keep rate-local state static in this file;
 * cross-rate signals belong in an asw_signals module.
 */

#include "eros.h"

/** TASK_BLINK - 100 ms, WCET <= 1 tick(s). */
void Task_Blink(void)
{
    /* TODO: runnables for this rate */
    TerminateTask();
}
