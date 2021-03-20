// ym_dbg_dac.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "config.h"
#include "ym_dbg_dac.h"

struct dac_debug_regs_r {
	volatile uint32_t left;
	volatile uint32_t right;
} __attribute__((packed));

static volatile struct dac_debug_regs_r * const regs_r = (void*)(YM3016_DBG_BASE);

void ym_dbg_dac_previous_inputs(uint16_t *left, uint16_t *right) {
	*left = regs_r->left;
	*right = regs_r->right;
}
