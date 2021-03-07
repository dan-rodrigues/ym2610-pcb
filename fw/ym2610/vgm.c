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

// Config:

static const bool log_writes = false;

static const bool enable_adpcm_a = true;
static const bool enable_adpcm_b = true;

static const bool enable_dac_logging = false;

// ---

static void dac_debug_log(void);
static void mux_debug_log(void);

static uint32_t read32(const uint8_t *bytes);

static void vgm_player_sanity_check(void);
static void vgm_player_init(void);
static uint32_t vgm_player_update(void);
static bool vgm_filter_reg_write(uint8_t port, uint8_t reg, uint8_t data);

static void delay(uint32_t delay);

static size_t vgm_index;
static size_t vgm_loop_offset;
static uint32_t vgm_loop_count;

// VGM buffer (independent of anything preloaded into fw)
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

	printf("vgm_pcm_write: wrote pcm block (%x bytes @ %x)\n",
		   length, offset);
}

void vgm_init_playback() {
	vgm_player_sanity_check();
	vgm_player_init();

	// Don't allow PCM access to PSRAM until it's fully loaded
	pcm_mux_set_enabled(true);

	printf("Starting VGM playback...\n");
}

uint32_t vgm_continue_playback() {
	uint32_t delay_ticks = vgm_player_update();

	// FIXME: use timer peripheral instead of this
	delay(delay_ticks);

	if (enable_dac_logging) {
		dac_debug_log();
		mux_debug_log();
	}

	return delay_ticks;
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

// TODO: replace the below with some WB timer peripheral that CPU can poll between USB tasks

// This delay function is used in absence of IRQ or the timer instructions
// If I end up redoing this properly, there will be a hardware timer instead of this
// This is fine for a demo

__attribute__((noinline))
static void delay(uint32_t delay) {
	if (!delay) {
		return;
	}

	// This constant effectively controls the tempo
	// This assumes PicoRV32 is used as configured in this branch
	// (382.65 CPU cycles per sample)
	const uint32_t inner_loop_iterations = 48;

	uint32_t inner_loop_counter;

	__asm __volatile__
	(
	 "loop_outer:\n"

	 "li %1, %2\n"

	 "loop_inner:\n"
	 "addi %1, %1, -1\n"
	 "bnez %1, loop_inner\n"

	 "addi %0, %0, -1\n"
	 "bnez %0, loop_outer\n"
	 : "+r" (delay), "=r" (inner_loop_counter)
	 : "i" (inner_loop_iterations)
	 :
	);
}

static void vgm_player_init() {
	// VGM start offset

	const size_t relative_offset_index = 0x34;

	uint32_t relative_offset = vgm[relative_offset_index + 0];
	relative_offset |= vgm[relative_offset_index + 1] << 8;
	relative_offset |= vgm[relative_offset_index + 2] << 16;
	relative_offset |= vgm[relative_offset_index + 3] << 24;

	vgm_index = relative_offset ? relative_offset_index + relative_offset : 0x40;

	// VGM loop offset (optional

	const size_t loop_offset_index = 0x1c;

	uint32_t loop_offset = vgm[loop_offset_index + 0];
	loop_offset |= vgm[loop_offset_index + 1] << 8;
	loop_offset |= vgm[loop_offset_index + 2] << 16;
	loop_offset |= vgm[loop_offset_index + 3] << 24;

	vgm_loop_offset = loop_offset ? loop_offset_index + loop_offset : 0;

	// YM2610 clock should always be 8MHz in this case, but read from header anyway

	const size_t ym_clock_offset = 0x4c;

	uint32_t ym_clock = vgm[ym_clock_offset + 0];
	ym_clock |= vgm[ym_clock_offset + 1] << 8;
	ym_clock |= vgm[ym_clock_offset + 2] << 16;

	// Print some stats

	printf("Start offset: 0x%08X\n", vgm_index);
	printf("Loop offset:  0x%08X\n", vgm_loop_offset);

	printf("YM2610 clock: %dHz\n", ym_clock);
}

static uint32_t vgm_player_update() {
	while (true) {
		uint8_t cmd = vgm[vgm_index++];

		if ((cmd & 0xf0) == 0x70) {
			// 0x7X
			// Wait X samples
			return cmd & 0x0f;
		}

		switch (cmd) {
			case 0x58: {
				// 0x58 XX YY
				// Write reg[0][XX] = YY
				uint8_t reg = vgm[vgm_index++];
				uint8_t data = vgm[vgm_index++];

				if (vgm_filter_reg_write(0, reg, data)) {
					ym_write_a(reg, data);
				}
			} break;
			case 0x59: {
				// 0x59 XX YY
				// Write reg[1][XX] = YY
				uint8_t reg = vgm[vgm_index++];
				uint8_t data = vgm[vgm_index++];

				if (vgm_filter_reg_write(1, reg, data)) {
					ym_write_b(reg, data);
				}
			} break;
			case 0x61: {
				// 0x61 XX XX
				// Wait XXXX samples
				uint16_t delay = vgm[vgm_index++];
				delay |= vgm[vgm_index++] << 8;
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
				vgm_loop_count++;

				if (vgm_loop_offset) {
					vgm_index = vgm_loop_offset;
					printf("Looping..\n\n");
				} else {
					// If there's no loop, just restart the player
					vgm_player_init();
					printf("Looping..\n\n");
				}

				return 0;
			}

			// Ignored commands to allow YM2xxx portion to play:

			// OKI PCM:

			case 0xb7: case 0xb8:
				vgm_index += 2;
				break;

			// Sega PCM:

			case 0xc0:
				vgm_index += 3;
				break;

			// Data blocks:

			case 0x67: {
				size_t block_size = read32(&vgm[vgm_index + 2]);
				vgm_index += 6 + block_size;

				printf("Found PCM block during playback. Ignoring...\n");
			} break;

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

static uint32_t read32(const uint8_t *bytes) {
	uint32_t word = bytes[0];
	word |= bytes[1] << 8;
	word |= bytes[2] << 16;
	word |= bytes[3] << 24;

	return word;
}
