// vgm_timer.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "vgm_timer.h"

#include "config.h"

static volatile uint32_t * const VGM_TIMER_COUNT = (void*)(VGM_TIMER_BASE + 0);
static volatile const uint32_t * const VGM_TIMER_ELAPSED = (void*)(VGM_TIMER_BASE + 0);

void vgm_timer_set(uint16_t count) {
	if (count == 0) {
		return;
	}

	*VGM_TIMER_COUNT = (count - 1);
}

bool vgm_timer_elapsed() {
	return *VGM_TIMER_ELAPSED & 0x01;
}
