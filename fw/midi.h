// midi.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef midi_h
#define midi_h

#include <stdint.h>
#include <stdbool.h>

enum midi_cmd {
	MIDI_CMD_UNDEFINED = 0x0,
	MIDI_CMD_NOTE_OFF = 0x8,
	MIDI_CMD_NOTE_ON = 0x9
	// (other messages as required)
};

struct midi_note_ctx {
	uint8_t note;
	uint8_t velocity;
};

struct midi_msg {
	enum midi_cmd cmd;

	union {
		// NOTE_ON / NOTE_OFF
		struct midi_note_ctx note_ctx;
	};
};

void midi_init(void);
bool midi_pending_msg(struct midi_msg *msg);

#endif
