// midi.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "midi.h"

#include "console.h"
#include "mini-printf.h"

#include "config.h"

// Config:

static const bool log_incoming_messages = true;

// ---

struct wb_uart {
        uint32_t data;
        uint32_t clkdiv;
} __attribute__((packed,aligned(4)));

static volatile struct wb_uart * const midi_uart_regs = (void*)(MIDI_BASE);

static bool midi_uart_byte(uint8_t *byte);
static void midi_create_msg(struct midi_msg *msg, uint8_t *msg_bytes);
static void midi_create_note_ctx(struct midi_note_ctx *note_ctx, uint8_t *msg_bytes);

// It may take multiple reads for a complete MIDI message to be read
// Not blocking the CPU if there's a partial read
#define MSG_LENGTH 3

static uint8_t partial_msg_index;
static uint8_t partial_msg[MSG_LENGTH];

void midi_init() {
	// 31250 baud
	midi_uart_regs->clkdiv = (768 - 1);

	partial_msg_index = 0;
}

bool midi_pending_msg(struct midi_msg *msg) {
	while (partial_msg_index < MSG_LENGTH) {
		uint8_t byte;
		if (midi_uart_byte(&byte)) {
			partial_msg[partial_msg_index++] = byte;
		} else {
			break;
		}
	}

	if (partial_msg_index == MSG_LENGTH) {
		// There's a complete message, turn it into a struct
		midi_create_msg(msg, partial_msg);

		partial_msg_index = 0;
		return true;
	} else {
		return false;
	}
}

static void midi_create_msg(struct midi_msg *msg, uint8_t *msg_bytes) {
	if (log_incoming_messages) {
		printf("midi_create_msg: creating message from bytes: %x %x %x\n",
			msg_bytes[0], msg_bytes[1], msg_bytes[2]);
	}

	switch (msg_bytes[0] & 0xf0) {
		case 0x80:
			msg->cmd = MIDI_CMD_NOTE_OFF;
			midi_create_note_ctx(&msg->note_ctx, msg_bytes);
			break;
		case 0x90:
			msg->cmd = MIDI_CMD_NOTE_ON;
			midi_create_note_ctx(&msg->note_ctx, msg_bytes);
			break;
		default:
			printf("midi_create_msg: unrecognized command %x\n", msg_bytes[0]);
			break;
	}
}

static void midi_create_note_ctx(struct midi_note_ctx *note_ctx, uint8_t *msg_bytes) {
	note_ctx->note = msg_bytes[1] & 0x7f;
	note_ctx->velocity = msg_bytes[2] & 0x7f;
}

static bool midi_uart_byte(uint8_t *byte) {
	uint32_t data = midi_uart_regs->data;
	if (data & 0x80000000) {
		return false;
	}

	*byte = data & 0xff;
	return true;
}