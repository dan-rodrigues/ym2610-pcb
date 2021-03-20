// pcm_mux.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "config.h"
#include "pcm_mux.h"

struct pcm_mux_regs_r {
	volatile uint32_t rmpx_rise_count;
	volatile uint32_t rmpx_fall_count;
	volatile uint32_t pmpx_rise_count;
	volatile uint32_t pmpx_fall_count;

	// Upper 8 bits: last data read
	// Lower 24bits: last address read
	volatile uint32_t p_last_access_packed;
} __attribute__((packed));

struct pcm_mux_regs_w {
	volatile uint32_t enable;
	volatile uint32_t metrics_reset;
} __attribute__((packed));

static volatile struct pcm_mux_regs_r * const regs_r = (void*)(PCM_MUX_BASE);
static volatile struct pcm_mux_regs_w * const regs_w = (void*)(PCM_MUX_BASE);

void pcm_mux_set_enabled(bool enabled) {
	regs_w->enable = enabled;
}

void pcm_mux_get_mpx_metrics(struct pcm_mux_mpx_metrics *metrics) {
	metrics->rmpx_rise_count = regs_r->rmpx_rise_count;
	metrics->rmpx_fall_count = regs_r->rmpx_fall_count;
	metrics->rmpx_rise_count = regs_r->pmpx_rise_count;
	metrics->rmpx_fall_count = regs_r->pmpx_fall_count;
}

void pcm_mux_reset_mpx_metrics() {
	const uint32_t rmpx_reset_mask = (1 << 0);
	const uint32_t pmpx_reset_mask = (1 << 1);

	regs_w->metrics_reset = rmpx_reset_mask | pmpx_reset_mask;
}
