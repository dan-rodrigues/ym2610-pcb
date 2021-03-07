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

static volatile uint32_t * const PCM_MUX_ENABLE = (void*)(PCM_MUX_BASE + 0);
static volatile uint32_t * const PCM_MUX_MPX_METRICS_RESET = (void*)(PCM_MUX_BASE + 4);

static volatile uint32_t * const PCM_MUX_MPX_METRICS = (void*)(PCM_MUX_BASE + 0);

void pcm_mux_set_enabled(bool enabled) {
	*PCM_MUX_ENABLE = enabled;
}

void pcm_mux_get_mpx_metrics(struct pcm_mux_mpx_metrics *metrics) {
	metrics->rmpx_rise_count = PCM_MUX_MPX_METRICS[0];
	metrics->rmpx_fall_count = PCM_MUX_MPX_METRICS[1];
	metrics->pmpx_rise_count = PCM_MUX_MPX_METRICS[2];
	metrics->pmpx_fall_count = PCM_MUX_MPX_METRICS[3];
}

void pcm_mux_reset_mpx_metrics() {
	const uint32_t rmpx_reset_mask = (1 << 0);
	const uint32_t pmpx_reset_mask = (1 << 1);

	*PCM_MUX_MPX_METRICS_RESET = rmpx_reset_mask | pmpx_reset_mask;
}

