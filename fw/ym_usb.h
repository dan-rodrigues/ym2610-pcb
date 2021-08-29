// ym_usb.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef ym_usb_h
#define ym_usb_h

#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>

enum ymu_write_mode {
	YMU_WM_PCM_A = 0x00,
	YMU_WM_PCM_B = 0x01,
	YMU_WM_VGM = 0x02,
	YMU_WM_UNDEFINED = 0xff
};

size_t ymu_data_poll(uint32_t *data, size_t *offset, enum ymu_write_mode *mode, size_t max_length);
void ymu_init(void);
void ymu_reset_sequence_counter(void);

bool ymu_playback_start_pending(void);

bool ymu_request_vgm_buffering(uint32_t target_offset, uint32_t vgm_start_offset, uint32_t vgm_chunk_length);
bool ymu_report_status(uint32_t status);

#endif
