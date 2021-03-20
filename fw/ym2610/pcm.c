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
	ym_write(0x100, 0x80 | 0x3f);
}

void pcm_mute_adpcm_b() {
	ym_write(0x010, 0x01);
}
