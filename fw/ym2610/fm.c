// fm.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "fm.h"

#include "ym_ctrl.h"

struct fm_ctx {
	uint8_t note_table[128];
	uint8_t octave_table[128];

	uint8_t channel_notes[FM_CH_COUNT];
};

static struct fm_ctx ctx;

static const uint8_t key_ch_map[] = {
	0, 1, 5, 6,
	// Only on 2610B:
	2, 4
};

static uint16_t fm_reg_base(uint8_t ch);
static void fm_set_pitch(uint8_t ch, uint8_t midi_note);

void fm_init() {
	static const struct fm_ctx initialized_ctx = {
		.channel_notes = { -1, -1, -1, -1, -1, -1 }
	};

	ctx = initialized_ctx;

	// Precompute note/octave tables

	for (uint32_t octave = 0; octave < 10; octave++) {
		for (uint32_t note = 0; note < 12; note++) {
			uint8_t index = octave * 12 + note;
			ctx.note_table[index] = note;
			ctx.octave_table[index] = octave;
		}
	}
}

void fm_mute_all() {
	fm_mute((1 << FM_CH_COUNT) - 1);
}

void fm_mute(uint8_t ch_mask) {
	for (uint32_t i = 0; i < FM_CH_COUNT; i++) {
		if ((ch_mask >> i) & 0x01) {
			fm_key(i, false, ctx.channel_notes[i]);
		}
	}
}

void fm_key_mask(uint8_t ch_mask, bool on, uint8_t midi_note) {
	for (uint32_t i = 0; i < FM_CH_COUNT; i++) {
		if ((ch_mask >> i) & 0x01) {
			fm_key(i, on, midi_note);
		}
	}
}

void fm_key(uint8_t ch, bool on, uint8_t midi_note) {
	// if (FM_DISABLE_EXTRA_CH && (ch >= 4)) {
	// 	// These channels only exist on the YM2610B
	// 	return;
	// }

	// Only key-off if note matches the original
	// Unintentional muting otherwise
	if (!on && (ctx.channel_notes[ch] != midi_note)) {
		return;
	}

	if (on) {
		fm_set_pitch(ch, midi_note);
		ctx.channel_notes[ch] = midi_note;
	} else {
		ctx.channel_notes[ch] = -1;
	}

	// Key-on/off after any pitch config

	// Not all cases will use all slots so this might need configuring
	const uint8_t op = 0xf;

	const uint8_t op_mask = (on ? op : 0);
	const uint8_t kon_reg = 0x28;

	uint8_t data = op_mask << 4 | key_ch_map[ch];

	ym_write_a(kon_reg, data);
}

static void fm_set_pitch(uint8_t ch, uint8_t midi_note) {
	static const uint16_t pitch_table[] = {
		// C, C#, D, D#
		617, 654, 693, 734,
		// E, F, F#, G
		778, 824, 873, 925,
		// G#, A, A#, B
		980, 1038, 1100, 1165
	};

	uint8_t octave = ctx.octave_table[midi_note];
	uint16_t pitch = pitch_table[ctx.note_table[midi_note]];

	uint16_t reg_base = fm_reg_base(ch);

	// 0xa4 reg write must come first
	ym_write(reg_base + 0xa4, pitch >> 8 | octave << 3);
	ym_write(reg_base + 0xa0, pitch & 0xff);
}

static uint16_t fm_reg_base(uint8_t ch) {
	static const uint16_t reg_table[] = {
		0x001, 0x002, 0x101, 0x102,
		// Only on 2610B:
		0x000, 0x100
	};

	return reg_table[ch];
}

bool fm_should_allow_key_on(uint16_t address, uint8_t data, uint8_t ch_mask) {
	if (ch_mask == 0x3f) {
		// All channels are included, no point checking anything else
		return true;
	}

	if (address != 0x28) {
		// Not an FM key-on
		return true;
	}

	// if (!(data & 0xf0)) {
	// 	// Not keying any operators
	// 	return true;
	// }

	for (uint32_t i = 0; i < FM_CH_COUNT; i++) {
		if (!(ch_mask >> i & 0x01)) {
			continue;
		}

		uint8_t encoded_ch = data & 0x7;
		if (key_ch_map[i] == encoded_ch) {
			// ch_mask includes this channel, allow it
			return true;
		}
	}

	// ch_mask did not include this channel, disallow it
	return false;
}

bool fm_should_allow_pitch_write(uint16_t address, uint8_t data, uint8_t ch_mask) {
	if ((address & 0x0f0) != 0x0a0) {
		return true;
	}

	for (uint32_t i = 0; i < FM_CH_COUNT; i++) {
		if (!(ch_mask >> i & 0x01)) {
			continue;
		}

		uint16_t reg_base = fm_reg_base(i);

		if (address == (reg_base + 0xa0)) {
			return true;
		}
		if (address == (reg_base + 0xa4)) {
			return true;
		}
	}

	return false;
}