// ym_ctrl.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "config.h"
#include "ym_ctrl.h"

static volatile uint32_t * const ym2610_ctrl = (void*)(YM2610_BASE);
static void ym_busy_wait(void);

void ym_write_a(uint8_t reg, uint8_t data) {
	ym_busy_wait();
	ym2610_ctrl[0] = reg;
	ym2610_ctrl[1] = data;
}

void ym_write_b(uint8_t reg, uint8_t data) {
	ym_busy_wait();
	ym2610_ctrl[2] = reg;
	ym2610_ctrl[3] = data;
}

void ym_reset(bool reset_active) {
	ym_busy_wait();
	ym2610_ctrl[4] = !reset_active;
}

static void ym_busy_wait() {
	// TODO: restore busy wait when actual YM is used
    while (ym2610_ctrl[0] & 0x01) {}
}
