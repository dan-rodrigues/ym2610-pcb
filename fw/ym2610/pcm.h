// pcm.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef pcm_h
#define pcm_h

#include <stdint.h>

void pcm_mute_all(void);

void pcm_mute_adpcm_a(void);
void pcm_mute_adpcm_b(void);

void pcm_unmute_adpcm_a(uint8_t atl);

#endif
