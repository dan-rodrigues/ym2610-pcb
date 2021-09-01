/*
 * fw_app.c
 *
 * Copyright (C) 2019 Sylvain Munaut
 * Copyright (C) 2021 Dan Rodrigues
 * All rights reserved.
 *
 * LGPL v3+, see LICENSE.lgpl3
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include <no2usb/usb.h>
#include <no2usb/usb_dfu_rt.h>
#include <no2usb/usb_hw.h>
#include <no2usb/usb_priv.h>

#include "console.h"
#include "led.h"
#include "mini-printf.h"
#include "utils.h"

#include "config.h"
#include "ym_usb.h"
#include "spi_mem.h"
#include "midi.h"
#include "buttons.h"

#include "ym2610/vgm.h"
#include "ym2610/ym_ctrl.h"
#include "ym2610/pcm_mux.h"
#include "ym2610/fm.h"
#include "ym2610/pcm.h"
#include "ym2610/ssg.h"

extern const struct usb_stack_descriptors app_stack_desc;
static struct vgm_player_context player_ctx;
static bool playback_active;

static void boot_dfu(void);
static void serial_no_init(void);
static void mute_all(void);

static void midi_update(void);

void main() {
	console_init();
	puts("\n\n");
	
	puts("Entered main..\n");

	spi_mem_init();
	midi_init();

	pcm_mux_set_enabled(false);

	// It's expected that 192 cycles @ 8MHZ have passed since clearing the reset
	ym_reset(false);

	// LED "breathing" animation (defaults used here)
	// This could be changed based on what "mode" the firmware is in
	led_init();
	led_color(48, 96, 5);
	led_blink(true, 200, 1000);
	led_breathe(true, 100, 200);
	led_state(true);

	puts("Configured LED for breathing..\n");

	// Original USB initialization. Need to sort out DFU issues.
	serial_no_init();
	usb_init(&app_stack_desc);
	usb_dfu_rt_init();

	ymu_init();
	usb_connect();

	playback_active = false;
	puts("Entering main loop..\n");

	// VGM player context / config

	player_ctx.initialized = false;
	fm_init();

	while (true) {
		usb_poll();

		// VGM USB control / data poll
		uint32_t usb_data[16];

		size_t offset = 0;
		enum ymu_write_mode mode = YMU_WM_UNDEFINED;

		// FIXME: slower than it needs to be. should just do a direct copy into target memory
		size_t length = ymu_data_poll(usb_data, &offset, &mode, 64);

		if (length > 0) {
			switch (mode) {
				case YMU_WM_VGM:
					vgm_write(usb_data, offset, length);
					break;
				case YMU_WM_PCM_A:
					// TODO: mute channels if needed
					playback_active = false;
					vgm_pcm_write(usb_data, offset, length);
					break;
				case YMU_WM_PCM_B:
					playback_active = false;
					vgm_pcm_write(usb_data, 0 + offset, length);
					break;
				case YMU_WM_UNDEFINED:
					printf("Received undefined write mode\n");
					break;
			}
		}

		if (ymu_playback_start_pending()) {
			mute_all();
			fm_init();

			ymu_reset_sequence_counter();
			vgm_init_playback(&player_ctx);

			playback_active = true;
		}
		
		if (playback_active) {
			struct vgm_update_result result = { 0 };
			vgm_continue_playback(&player_ctx, &result);

			if (result.player_error) {
				printf("main loop: playback stopped due to player error\n");
				mute_all();

				playback_active = false;
			} else if (result.buffering_needed) {
				printf("main loop: requesting buffering @ %x, vgm range %x, %x bytes\n",
						result.buffer_target_offset, result.vgm_start_offset, result.vgm_chunk_length);

				ymu_request_vgm_buffering(
					result.buffer_target_offset,
					result.vgm_start_offset,
					result.vgm_chunk_length
				);
			}
		}

		// MIDI (simple demo using FM for now):
		// This does nothing if the MIDI UART in the Verilog source is disabled

		midi_update();

		// Buttons (may change their functions)

		btn_poll();

		// Button A: cycle sound sources

		if (btn_a_edge()) {
			static uint8_t filter_index;
			filter_index = filter_index < 2 ? filter_index + 1 : 0;

			const uint8_t fm_ch_mask = 0x3f;

			bool filter_fm = filter_index & 0x01;
			player_ctx.fm_key_on_mask = filter_fm ? 0x0 : fm_ch_mask;
			player_ctx.filter_fm_pitch = filter_fm;

			bool filter_pcm = filter_index & 0x02;
			player_ctx.filter_pcm_key_on = filter_pcm;

			// Force-disable channels if any happen to be playing

			if (filter_pcm) {
				pcm_mute_all();
			} else {
				pcm_unmute_adpcm_a(player_ctx.adpcma_last_atl);
			}

			if (filter_fm) {
				fm_mute_all();
			}
		}

		// Button B: mute / enable all sound sources

		if (btn_b_edge()) {
			static bool filter_all;
			filter_all = !filter_all;

			player_ctx.fm_key_on_mask = filter_all ? 0x0 : 0x3f;
			player_ctx.filter_fm_pitch = filter_all;

			player_ctx.filter_pcm_key_on = filter_all;

			if (filter_all) {
				mute_all();
			} else {
				pcm_unmute_adpcm_a(player_ctx.adpcma_last_atl);
			}
		}
	}
}

// Minimal MIDI demo function
// If it's further developed it would go in its own file with configuration structs etc.

static void midi_update() {
	struct midi_msg midi_msg = { 0 };
	while (midi_pending_msg(&midi_msg)) {
		printf("main loop: received MIDI message of type %x\n", midi_msg.cmd);

		// Temporary test with masking for MIDI keyed notes
		const uint8_t ch_mask = 0x4;

		bool key_on = (midi_msg.cmd == MIDI_CMD_NOTE_ON);
		fm_key_mask(ch_mask, key_on, midi_msg.note_ctx.note);
	}
}

static void mute_all() {
	pcm_mute_all();
	fm_mute_all();
	ssg_mute_all();
}

// Copied from original firmware:

static void serial_no_init() {
	static const char * const placeholder_id = "0123456789abcdef";

	/* Overwrite descriptor string */
	/* In theory in rodata ... but nothing is ro here */
	char *desc = (char*)app_stack_desc.str[1];
	for (uint8_t i=0; i<16; i++)
		desc[2 + (i << 1)] = placeholder_id[i];
}

static void boot_dfu() {
	/* Force re-enumeration */
	usb_disconnect();

	/* Boot firmware */
	volatile uint32_t *boot = (void*)0x80000000;
	*boot = (1 << 2) | (1 << 0);
}

void usb_dfu_rt_cb_reboot(void) {
	boot_dfu();
}
