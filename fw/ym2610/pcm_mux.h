// pcm_mux.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>

#ifndef pcm_mux_h
#define pcm_mux_h

struct pcm_mux_mpx_metrics {
	uint16_t rmpx_rise_count;
	uint16_t rmpx_fall_count;
	uint16_t pmpx_rise_count;
	uint16_t pmpx_fall_count;
};

void pcm_mux_set_enabled(bool enabled);

void pcm_mux_get_mpx_metrics(struct pcm_mux_mpx_metrics *metrics);
void pcm_mux_reset_mpx_metrics(void);

#endif
