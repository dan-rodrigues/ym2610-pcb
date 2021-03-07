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

static volatile uint16_t * const ym3016_left_shift_in = (void*)(YM3016_DBG_BASE + 0);
static volatile uint16_t * const ym3016_right_shift_in = (void*)(YM3016_DBG_BASE + 4);

void ym_dbg_dac_previous_inputs(uint16_t *left, uint16_t *right) {
	*left = *ym3016_left_shift_in;
	*right = *ym3016_right_shift_in;
}
