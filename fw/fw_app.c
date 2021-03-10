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

#include "ym2610/vgm.h"
#include "ym2610/ym_ctrl.h"
#include "ym2610/pcm_mux.h"

extern const struct usb_stack_descriptors app_stack_desc;

static void boot_dfu(void);
static void serial_no_init(void);

static bool playback_active;

void main() {
	console_init();
	puts("\n\n");
	
	puts("Entered main..\n");

	spi_mem_init();

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

	struct vgm_player_context player_context = {
		.initialized = false
	};

	while (true) {
		/* USB poll */
		usb_poll();

		// VGM USB control / data poll
		uint32_t usb_data[16];

		size_t offset = 0;
		enum ymu_write_mode mode = YMU_WM_UNDEFINED;

		size_t length = ymu_data_poll(usb_data, &offset, &mode, 64);

		if (length > 0) {
			playback_active = false;

			switch (mode) {
				case YMU_WM_VGM:
					vgm_write((uint8_t *)usb_data, offset, length);
					break;
				case YMU_WM_PCM_A:
					vgm_pcm_write(usb_data, offset, length);
					break;
				case YMU_WM_PCM_B:
					vgm_pcm_write(usb_data, 0 + offset, length);
					break;
				case YMU_WM_UNDEFINED:
					printf("Received undefined write mode\n");
					break;
			}
		}

		if (playback_active) {
			struct vgm_update_result result;
			vgm_continue_playback(&player_context, &result);

			if (result.buffering_needed) {
				printf("main loop: requesting buffering @ %x, vgm range %x to %x, %x bytes\n",
						result.buffer_target_offset, result.vgm_start_offset, result.vgm_chunk_length);

				ymu_request_vgm_buffering(result.buffer_target_offset, result.vgm_start_offset, result.vgm_chunk_length);
			}
		}

		if (ymu_playback_start_pending()) {
			// Temporary test of status reporting
			while (!ymu_report_status(64 << 16 | 32 << 8 | 48)) {}

			vgm_init_playback(&player_context);
			playback_active = true;
		}
	}
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
