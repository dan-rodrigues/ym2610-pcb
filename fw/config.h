/*
 * config.h
 *
 * Copyright (C) 2019 Sylvain Munaut
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

#pragma once

#define FLASH_MEM_BASE  0x40000000
#define PSRAM_MEM_BASE  0x60000000

#define UART_BASE	0x81000000
#define SPI_CTRL_BASE	0x82000000
#define LED_BASE	0x83000000
#define USB_CORE_BASE	0x84000000
#define USB_DATA_BASE	0x85000000
#define AUDIO_PCM_BASE	0x86000000
#define MIDI_BASE	0x87000000
#define YM2610_BASE     0x88000000
#define PCM_MUX_BASE    0x8a000000
#define YM3016_DBG_BASE 0x8b000000
#define VGM_TIMER_BASE 	0x8c000000
#define BUTTONS_BASE 	0x8d000000

