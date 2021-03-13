// fm.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "fm.h"

#include "ym_ctrl.h"

static uint16_t fm_reg_base(uint8_t ch);
static void fm_set_pitch(const struct fm_ctx *ctx, uint8_t ch, uint8_t midi_note);

void fm_init(struct fm_ctx *ctx) {
	static const struct fm_ctx initialized_ctx = {
		.channel_notes = { -1, -1, -1, -1, -1, -1 }
	};

	*ctx = initialized_ctx;

	// Precompute note/octave tables

	for (uint32_t octave = 0; octave < 10; octave++) {
		for (uint32_t note = 0; note < 12; note++) {
			uint8_t index = octave * 12 + note;
			ctx->note_table[index] = note;
			ctx->octave_table[index] = octave;
		}
	}
}

void fm_key_mask(struct fm_ctx *ctx, uint8_t ch_mask, bool on, uint8_t midi_note) {
	for (uint32_t i = 0; i < FM_CH_COUNT; i++) {
		if ((ch_mask >> i) & 0x01) {
			fm_key(ctx, i, on, midi_note);
		}
	}
}

void fm_key(struct fm_ctx *ctx, uint8_t ch, bool on, uint8_t midi_note) {
	// Only key-off if note matches the original
	// Unintentional muting otherwise
	if (!on && (ctx->channel_notes[ch] != midi_note)) {
		return;
	}

	if (on) {
		fm_set_pitch(ctx, ch, midi_note);
		ctx->channel_notes[ch] = midi_note;
	} else {
		ctx->channel_notes[ch] = -1;
	}

	// Key-on/off after any pitch config

	// Not all cases will use all slots so this might need configuring
	const uint8_t op = 0xf;

	const uint8_t op_mask = (on ? op : 0);
	const uint8_t kon_reg = 0x28;

	uint8_t data = op_mask << 4 | ch;

	ym_write_a(kon_reg, data);
}

static void fm_set_pitch(const struct fm_ctx *ctx, uint8_t ch, uint8_t midi_note) {
	static const uint16_t pitch_table[] = {
		// C, C#, D, D#
		617, 654, 693, 734,
		// E, F, F#, G
		778, 824, 873, 925,
		// G#, A, A#, B
		980, 1038, 1100, 1165
	};

	uint8_t octave = ctx->octave_table[midi_note];
	uint16_t pitch = pitch_table[ctx->note_table[midi_note]];

	uint16_t reg_base = fm_reg_base(ch);

	// 0xa4 reg write must come first
	ym_write(reg_base + 0xa4, pitch >> 8 | octave << 3);
	ym_write(reg_base + 0xa0, pitch & 0xff);
}

static uint16_t fm_reg_base(uint8_t ch) {
	return (ch >= 4 ? 0x100 : 0x000) + (ch & 0x03);
}
