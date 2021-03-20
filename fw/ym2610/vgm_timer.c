// vgm_timer.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "vgm_timer.h"

#include "config.h"

struct vgm_timer_regs_r {
	volatile uint32_t expired;
} __attribute__((packed));

struct vgm_timer_regs_w {
	volatile uint32_t set_counter;
	volatile uint32_t add_counter;
} __attribute__((packed));

static volatile struct vgm_timer_regs_r * const regs_r = (void*)(VGM_TIMER_BASE);
static volatile struct vgm_timer_regs_w * const regs_w = (void*)(VGM_TIMER_BASE);

void vgm_timer_set(uint16_t count) {
	regs_w->set_counter = (count - 1);
}

bool vgm_timer_elapsed() {
	return regs_r->expired;
}

void vgm_timer_add(uint16_t delta) {
	regs_w->add_counter = delta;
}
