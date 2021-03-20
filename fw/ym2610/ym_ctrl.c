// ym_ctrl.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stddef.h>

#include "config.h"
#include "ym_ctrl.h"
#include "console.h"
#include "mini-printf.h"

static const bool log_full_fifo = false;

// ---

struct ym_ctrl_regs_r {
	volatile uint32_t busy;
} __attribute__((packed));

struct ym_ctrl_regs_w {
	volatile uint32_t reg_a;
	volatile uint32_t data_a;

	volatile uint32_t reg_b;
	volatile uint32_t data_b;

	volatile uint32_t reset;
} __attribute__((packed));

static volatile struct ym_ctrl_regs_r * const regs_r = (void*)(YM2610_BASE);
static volatile struct ym_ctrl_regs_w * const regs_w = (void*)(YM2610_BASE);

static void ym_busy_wait(void);

void ym_write(uint16_t reg, uint8_t data) {
	if (reg & 0x100) {
		ym_write_b(reg & 0xff, data);
	} else {
		ym_write_a(reg & 0xff, data);
	}
}

void ym_write_a(uint8_t reg, uint8_t data) {
	ym_busy_wait();
	regs_w->reg_a = reg;
	regs_w->data_a = data;
}

void ym_write_b(uint8_t reg, uint8_t data) {
	ym_busy_wait();
	regs_w->reg_b = reg;
	regs_w->data_b = data;
}

void ym_reset(bool reset_active) {
	ym_busy_wait();
	regs_w->reset = !reset_active;
}

static void ym_busy_wait() {
	while (log_full_fifo && (regs_r->busy & 0x01)) {
		printf("YM2610 CMD FIFO unexpectedly full..\n");
	}
}
