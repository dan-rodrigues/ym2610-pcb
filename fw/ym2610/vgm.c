// vgm.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "console.h"
#include "mini-printf.h"
#include "utils.h"
#include "config.h"

#include "vgm.h"
#include "ym_ctrl.h"
#include "pcm_mux.h"
#include "ym_dbg_dac.h"
#include "vgm_timer.h"

// Config:

static const bool log_writes = false;
static const bool log_pcm_write_blocks = false;

static const bool enable_adpcm_a = true;
static const bool enable_adpcm_b = true;

static const bool enable_dac_logging = false;

// ---

static void dac_debug_log(void);
static void mux_debug_log(void);

static void vgm_player_sanity_check(void);
static void vgm_player_init(struct vgm_player_context *context);
static uint32_t vgm_player_update(struct vgm_player_context *ctx);
static bool vgm_filter_reg_write(uint8_t port, uint8_t reg, uint8_t data);

// VGM buffer
static uint8_t vgm[0x18000];

void vgm_write(uint8_t *data, size_t offset, size_t length) {
	if (length == 0) {
		printf("vgm_write: expected non-zero length\n");
		return;
	}

	if ((offset + length) >= sizeof(vgm)) {
		printf("vgm_write: expected data to be within vgm buffer bounds\n");
		return;
	}

	for (size_t i = 0; i < length; i++) {
		vgm[offset + i] = data[i];
	}

	printf("vgm_write: wrote vgm block (%x bytes @ %x)\n",
		   length, offset);
}

void vgm_pcm_write(uint32_t *data, size_t offset, size_t length) {
	pcm_mux_set_enabled(false);

	if (length == 0) {
		printf("vgm_pcm_write: expected non-zero length\n");
		return;
	}

	if ((offset + length) >= 0x800000) {
		printf("vgm_pcm_write: expected data to fit within 8MB PSRAM region\n");
		return;
	}

	uint32_t *psram = (void*)(PSRAM_MEM_BASE + offset);

	for (size_t i = 0; i < length / 4; i++) {
		uint32_t bytes = data[i];

		// This could be done in the python script to save time
		bytes =
			(bytes >> 24 & 0xff) |
			(bytes >> 8 & 0xff00) |
			(bytes << 8 & 0xff0000) |
			(bytes << 24 & 0xff000000);

		psram[i] = bytes;
	}

	if (log_pcm_write_blocks) {
		printf("vgm_pcm_write: wrote pcm block (%x bytes @ %x)\n",
			   length, offset);
	}
}

void vgm_init_playback(struct vgm_player_context *ctx) {
	vgm_player_sanity_check();
	vgm_player_init(ctx);
	vgm_timer_set(0);

	// Don't allow PCM access to PSRAM until it's fully loaded
	pcm_mux_set_enabled(true);

	printf("Starting VGM playback...\n");
}

void vgm_continue_playback(struct vgm_player_context *ctx, struct vgm_update_result *result) {
	if (!vgm_timer_elapsed()) {
		return;
	}

	if (!ctx->initialized) {
		printf("vgm_continue_playback: expected context to be initialized\n");
		return;
	}

	uint32_t delay_ticks = vgm_player_update(ctx);
	vgm_timer_set(delay_ticks);

	// TODO: use updated index to configure update_result accordingly to request buffering if needed
	result->buffering_needed = false;
	result->buffer_target_offset = 0;
	result->vgm_start_offset = 0;
	result->vgm_chunk_length = 0;

	if (enable_dac_logging) {
		dac_debug_log();
		mux_debug_log();
	}
}

static void dac_debug_log() {
	uint16_t shift_left = 0, shift_right = 0;
	ym_dbg_dac_previous_inputs(&shift_left, &shift_right);

	printf("DAC: Left %x, Right: %x\n", shift_left, shift_right);
}

static void mux_debug_log() {
	struct pcm_mux_mpx_metrics metrics;	
	pcm_mux_get_mpx_metrics(&metrics);

	printf("PCM: RMPX rose: %x, fell: %x\n", metrics.rmpx_rise_count, metrics.rmpx_fall_count);

	pcm_mux_reset_mpx_metrics();
}

static void vgm_player_sanity_check() {
	static const char * const identity_string = "Vgm ";

	bool identity_matches = true;

	for (size_t i = 0; i < 4; i++) {
		if (vgm[i] != identity_string[i]) {
			identity_matches = false;
			break;
		}
	}

	if (!identity_matches) {
		printf("Error: VGM identify string not found.\n");
		while(true) {}
	} else {
		printf("Found Vgm header\n");
	}
}

static void vgm_player_init(struct vgm_player_context *ctx) {
	// VGM start offset

	const size_t relative_offset_index = 0x34;

	uint32_t relative_offset = vgm[relative_offset_index + 0];
	relative_offset |= vgm[relative_offset_index + 1] << 8;
	relative_offset |= vgm[relative_offset_index + 2] << 16;
	relative_offset |= vgm[relative_offset_index + 3] << 24;

	ctx->index = relative_offset ? relative_offset_index + relative_offset : 0x40;

	// VGM loop offset (optional

	const size_t loop_offset_index = 0x1c;

	uint32_t loop_offset = vgm[loop_offset_index + 0];
	loop_offset |= vgm[loop_offset_index + 1] << 8;
	loop_offset |= vgm[loop_offset_index + 2] << 16;
	loop_offset |= vgm[loop_offset_index + 3] << 24;

	ctx->loop_offset = loop_offset ? loop_offset_index + loop_offset : 0;

	// YM2610 clock should always be 8MHz in this case, but read from header anyway

	const size_t ym_clock_offset = 0x4c;

	uint32_t ym_clock = vgm[ym_clock_offset + 0];
	ym_clock |= vgm[ym_clock_offset + 1] << 8;
	ym_clock |= vgm[ym_clock_offset + 2] << 16;

	// Print some stats

	printf("Start offset: 0x%08X\n", ctx->index);
	printf("Loop offset:  0x%08X\n", ctx->loop_offset);

	printf("YM2610 clock: %dHz\n", ym_clock);

	// Update attributes, not used unless buffering is needed

	ctx->write_active = false;
	ctx->target_offset = 0;
	ctx->last_write_index = 0;
	ctx->write_length = 0;

	ctx->initialized = true;
}

static uint8_t vgm_player_read_byte(struct vgm_player_context *ctx) {
	// TODO: adjust pointers as needed according to context
	// ... raise any buffer-needed flags etc.

	// 80kbyte: fixed region at start (should include loop offset)
	// 8kbyte:  buffer A
	// 8kbyte:  buffer B
	const uint32_t buffer_a_offset = 0x14000;
	const uint32_t buffer_b_offset = 0x16000;
	const uint32_t buffer_size = 0x2000;

	uint8_t byte = vgm[ctx->index++];

	// Nothing to do if we aren't in the double buffer region (yet)
	if (ctx->index < buffer_a_offset) {
		return byte;	
	}

	// ..did we just enter buffer A?
	if (ctx->index == buffer_a_offset) {
		// Start writing to B
		ctx->write_active = true;
		ctx->target_offset = buffer_b_offset;
		ctx->write_length = buffer_size;
		ctx->last_write_index = 0;

	// ..did we just finish reading buffer A?
	} else if (ctx->index == buffer_b_offset) {
		// Start writing to A
		ctx->write_active = true;
		ctx->target_offset = buffer_a_offset;
		ctx->write_length = buffer_size;
		ctx->last_write_index = 0;

	// ..did we read the final byte of buffer B?
	} else if (ctx->index == (buffer_b_offset + buffer_size)) {
		// Jump back to start of A
		ctx->index = buffer_a_offset;

		// Start writing to B
		ctx->write_active = true;
		ctx->target_offset = buffer_b_offset;
		ctx->write_length = buffer_size;
		ctx->last_write_index = 0;
	}

	return byte;
}

static uint32_t vgm_player_update(struct vgm_player_context *ctx) {
	while (true) {
		uint8_t cmd = vgm_player_read_byte(ctx);

		if ((cmd & 0xf0) == 0x70) {
			// 0x7X
			// Wait X + 1 samples
			return (cmd & 0x0f) + 1;
		}

		switch (cmd) {
			case 0x58: {
				// 0x58 XX YY
				// Write reg[0][XX] = YY
				uint8_t reg = vgm_player_read_byte(ctx);
				uint8_t data = vgm_player_read_byte(ctx);

				if (vgm_filter_reg_write(0, reg, data)) {
					ym_write_a(reg, data);
				}
			} break;
			case 0x59: {
				// 0x59 XX YY
				// Write reg[1][XX] = YY
				uint8_t reg = vgm_player_read_byte(ctx);
				uint8_t data = vgm_player_read_byte(ctx);

				if (vgm_filter_reg_write(1, reg, data)) {
					ym_write_b(reg, data);
				}
			} break;
			case 0x61: {
				// 0x61 XX XX
				// Wait XXXX samples
				uint16_t delay = vgm_player_read_byte(ctx);
				delay |= vgm_player_read_byte(ctx) << 8;
				return delay;
			}
			case 0x62:
				// 60hz frame wait
				return 735;
			case 0x63:
				// 50hz frame wait
				return 882;
			case 0x66: {
				// End of stream
				ctx->loop_count++;

				if (ctx->loop_offset) {
					ctx->index = ctx->loop_offset;
					printf("Looping..\n\n");
				} else {
					// If there's no loop, just restart the player
					vgm_player_init(ctx);
					printf("Looping..\n\n");
				}

				return 0;
			}

			// Data blocks which should've been stripped out before playback started:

			case 0x67:
				printf("Found PCM block during playback. These should've been removed. \n");
				while(true) {}

			// Other unsupported commands which we should never encounter:

			default:
				printf("Unsupported command: %X\n", cmd);
				while(true) {}
		}
	}
}

static bool vgm_filter_reg_write(uint8_t port, uint8_t reg, uint8_t data) {
	uint16_t address = port << 8 | reg;

	if (address >= 0x010 && address <= 0x01c) {
		if (log_writes) {
			printf("ADPCM-B: (%03x) = %02x: %s\n",
				   address, data, enable_adpcm_b ? "allowed" : "filtered");
		}
		return enable_adpcm_b;
	}

	if (address >= 0x100 && address <= 0x12d) {
		if (log_writes) {
			printf("ADPCM-A: (%03x) = %02x: %s\n",
				   address, data, enable_adpcm_a ? "allowed" : "filtered");
		}
		return enable_adpcm_a;
	}

	if (log_writes) {
		printf("Other reg write: (%03x) = %02x: allowed\n",
			   address, data);
	}

	return true;
}
