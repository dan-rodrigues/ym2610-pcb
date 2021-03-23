// pcm.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "pcm.h"

#include "ym_ctrl.h"

void pcm_mute_all() {
	pcm_mute_adpcm_a();
	pcm_mute_adpcm_b();
}

void pcm_mute_adpcm_a() {
	// ATL = 0, since key off doesn't seem to work reliably
	ym_write(0x100, 0x80 | 0x3f);
	ym_write(0x101, 0x00);
}

void pcm_unmute_adpcm_a(uint8_t atl) {
	ym_write(0x101, atl);
}

void pcm_mute_adpcm_b() {
	// Resetting works rather than setting volume
	ym_write(0x010, 0x80);
	ym_write(0x010, 0x00);
}
