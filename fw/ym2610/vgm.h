// vgm.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef vgm_h
#define vgm_h

void vgm_write(uint8_t *data, size_t offset, size_t length);
void vgm_pcm_write(uint32_t *data, size_t offset, size_t length);

void vgm_init_playback(void);
uint32_t vgm_continue_playback(void);

#endif
