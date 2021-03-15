// fm.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef fm_h
#define fm_h

#include <stdint.h>
#include <stdbool.h>

// Assuming 6 on the YM2610*B*

#define FM_CH_COUNT 6
#define FM_DISABLE_EXTRA_CH 1

struct fm_ctx {
	uint8_t note_table[128];
	uint8_t octave_table[128];

	uint8_t channel_notes[FM_CH_COUNT];
};

void fm_init(struct fm_ctx *ctx);

void fm_mute_all(struct fm_ctx *ctx);
void fm_mute(struct fm_ctx *ctx, uint8_t ch_mask);

void fm_key_mask(struct fm_ctx *ctx, uint8_t ch_mask, bool on, uint8_t midi_note);
void fm_key(struct fm_ctx *ctx, uint8_t ch, bool on, uint8_t note);

#endif
