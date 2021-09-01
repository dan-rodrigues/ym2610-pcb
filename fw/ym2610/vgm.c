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
#include "mem_util.h"
#include "fm.h"

// Config:

static const bool log_writes = false;
static const bool log_pcm_write_blocks = false;

static const bool enable_adpcm_a = true;
static const bool enable_adpcm_b = true;
static const bool enable_fm = true;

static const bool enable_dac_logging = false;

// ---

static void dac_debug_log(void);
static void mux_debug_log(void);

static void vgm_player_sanity_check(void);
static void vgm_player_init(struct vgm_player_context *context);
static uint32_t vgm_player_update(struct vgm_player_context *ctx, struct vgm_update_result *result);

static bool vgm_allow_reg_write(uint8_t port, uint8_t reg, uint8_t data, const struct vgm_player_context *ctx);
static void vgm_record_reg_write(uint8_t port, uint8_t reg, uint8_t data, struct vgm_player_context *ctx);

// VGM buffer (96kbyte)
static uint8_t vgm[0x18000];

// 72kbyte: fixed region at start
// 8kbyte:  buffer used to store first block at start of loop
// 8kbyte:  buffer A
// 8kbyte:  buffer B
static const uint32_t buffer_a_offset = 0x14000;
static const uint32_t buffer_b_offset = 0x16000;
static const uint32_t buffer_loop_offset = 0x12000;
static const uint32_t buffer_size = 0x2000;

static bool bounds_error_logged = false;

void vgm_write(const void *data, size_t offset, size_t length) {
	if (length == 0) {
		printf("vgm_write: expected non-zero length\n");
		return;
	}

	if ((offset + length) > sizeof(vgm)) {
		if (!bounds_error_logged) {
			printf("vgm_write: expected data to be within vgm buffer bounds\n");
			bounds_error_logged = true;
		}
		return;
	}

	memcpy(&vgm[offset], data, length);

	if (log_writes) {
		printf("vgm_write: wrote vgm block (%x bytes @ %x)\n",
			   length, offset);
	}
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
		psram[i] = data[i];
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
	result->buffering_needed = false;
	result->player_error = false;

	if (!vgm_timer_elapsed()) {
		return;
	}

	if (!ctx->initialized) {
		printf("vgm_continue_playback: expected context to be initialized\n");
		return;
	}

	uint32_t delay_ticks = vgm_player_update(ctx, result);
	vgm_timer_add(delay_ticks);

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

	uint32_t start_offset = relative_offset ? relative_offset_index + relative_offset : 0x40;
	ctx->start_offset = start_offset;
	ctx->index = start_offset;
	ctx->buffer_index = start_offset;
	ctx->previous_buffer_index = start_offset;

	ctx->loop_buffer_loaded = false;

	// VGM loop offset (optional)

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

	// Other attributes

	ctx->initialized = true;
	ctx->fm_key_on_mask = (1 << FM_CH_COUNT) - 1;
}

static void vgm_player_request_stream_buffering(struct vgm_player_context *ctx, struct vgm_update_result *result, uint32_t offset, uint32_t size) {
	uint32_t bytes_read = ctx->buffer_index - ctx->previous_buffer_index;
	ctx->index += bytes_read;

	result->buffering_needed = true;
	result->buffer_target_offset = offset;
	result->vgm_start_offset = ctx->index + size;
	result->vgm_chunk_length = size;
}

static void vgm_player_request_loop_buffering(struct vgm_player_context *ctx, struct vgm_update_result *result, uint32_t offset, uint32_t size) {
	result->buffering_needed = true;
	result->buffer_target_offset = offset;
	result->vgm_start_offset = ctx->loop_offset;
	result->vgm_chunk_length = size;
}

static uint8_t vgm_player_read_byte(struct vgm_player_context *ctx, struct vgm_update_result *result) {
	uint8_t byte = vgm[ctx->buffer_index++];

	// ..did we just finish reading the loop-start region?
	if (!ctx->loop_buffer_loaded && ctx->loop_offset && (ctx->buffer_index == buffer_a_offset)) {
		// One-time loading of the loop-start region (first data accessed upon looping)
		vgm_player_request_loop_buffering(ctx, result, buffer_loop_offset, buffer_size);
		ctx->loop_buffer_loaded = true;
	// ..did we just finish reading buffer A?
	} else if (ctx->buffer_index == buffer_b_offset) {
		// Start writing to A
		vgm_player_request_stream_buffering(ctx, result, buffer_a_offset, buffer_size);

		ctx->previous_buffer_index = buffer_b_offset;
	// ..did we read the final byte of buffer B?
	} else if (ctx->buffer_index == (buffer_b_offset + buffer_size)) {
		// Start writing to B..
		vgm_player_request_stream_buffering(ctx, result, buffer_b_offset, buffer_size);

		// ..then jump back to start of A
		ctx->buffer_index = buffer_a_offset;
		ctx->previous_buffer_index = buffer_a_offset;
	}

	return byte;
}

static void vgm_reset_initial_buffer(struct vgm_player_context *ctx, struct vgm_update_result *result) {
	ctx->index = ctx->loop_offset;

	if (ctx->loop_buffer_loaded) {
		// Target the previously loaded loop buffer for reading..
		ctx->buffer_index = buffer_loop_offset;
		ctx->previous_buffer_index = ctx->buffer_index;

		// ..then writing starts after the loop buffer
		result->vgm_start_offset = ctx->loop_offset + buffer_size;
	} else if (ctx->loop_offset) {
		// Reload buffer A/B (whether or not it's actually used)
		ctx->buffer_index = ctx->loop_offset;
		ctx->previous_buffer_index = ctx->buffer_index;

		result->vgm_start_offset = buffer_a_offset;
	} else {
		// No looping, start over from beginning
		uint32_t start_offset = ctx->start_offset;
		ctx->index = start_offset;
		ctx->buffer_index = start_offset;
		ctx->previous_buffer_index = start_offset;

		result->vgm_start_offset = buffer_a_offset;
	}

	result->buffering_needed = true;
	result->buffer_target_offset = buffer_a_offset;
	result->vgm_chunk_length = buffer_size * 2;
}

static uint32_t vgm_player_update(struct vgm_player_context *ctx, struct vgm_update_result *result) {
	while (true) {
		uint8_t cmd = vgm_player_read_byte(ctx, result);

		if ((cmd & 0xf0) == 0x70) {
			// 0x7X
			// Wait X + 1 samples
			return (cmd & 0x0f) + 1;
		}

		switch (cmd) {
			case 0x58: {
				// 0x58 XX YY
				// Write reg[0][XX] = YY
				uint8_t reg = vgm_player_read_byte(ctx, result);
				uint8_t data = vgm_player_read_byte(ctx, result);

				vgm_record_reg_write(0, reg, data, ctx);
				if (vgm_allow_reg_write(0, reg, data, ctx)) {
					ym_write_a(reg, data);
				}
			} break;
			case 0x59: {
				// 0x59 XX YY
				// Write reg[1][XX] = YY
				uint8_t reg = vgm_player_read_byte(ctx, result);
				uint8_t data = vgm_player_read_byte(ctx, result);

				vgm_record_reg_write(1, reg, data, ctx);
				if (vgm_allow_reg_write(1, reg, data, ctx)) {
					ym_write_b(reg, data);
				}
			} break;
			case 0x61: {
				// 0x61 XX XX
				// Wait XXXX samples
				uint16_t delay = vgm_player_read_byte(ctx, result);
				delay |= vgm_player_read_byte(ctx, result) << 8;
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
					printf("Looping..\n\n");
				} else {
					printf("Restarting..\n\n");
				}

				vgm_reset_initial_buffer(ctx, result);

				return 0;
			}

			// Data blocks which should've been stripped out before playback started:

			case 0x67:
				printf("Found PCM block during playback. These should've been removed. \n");
				result->player_error = true;
				return 0;

			// Other unsupported commands which we should never encounter:

			default:
				printf("Unsupported command: %x, buffer index: %x, vgm index: %x\n",
					   cmd, (ctx->buffer_index - 1), (ctx->index - 1));
				result->player_error = true;
				return 0;
		}
	}
}

static void vgm_record_reg_write(uint8_t port, uint8_t reg, uint8_t data, struct vgm_player_context *ctx) {
	uint16_t address = port << 8 | reg;

	if (address == 0x101) {
		ctx->adpcma_last_atl = data;
	}
}

static bool vgm_allow_reg_write(uint8_t port, uint8_t reg, uint8_t data, const struct vgm_player_context *ctx) {
	uint16_t address = port << 8 | reg;

	if (ctx->filter_fm_pitch && (reg >= 0xa0 && reg <= 0xa6)) {
		return false;
	}

	if (ctx->filter_pcm_key_on && ((address == 0x010) || (address == 0x100))) {
		return false;
	}

	if (!fm_should_allow_key_on(address, data, ctx->fm_key_on_mask)) {
		return false;
	}
	if (!fm_should_allow_pitch_write(address, data, ctx->fm_key_on_mask)) {
		return false;
	}

	if ((address >= 0x020 && address <= 0x0b7) || address >= 0x130) {
		return enable_fm;
	}

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
