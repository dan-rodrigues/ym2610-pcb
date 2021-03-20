// vgm_timer.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef vgm_timer_h
#define vgm_timer_h

#include <stdint.h>
#include <stdbool.h>

void vgm_timer_set(uint16_t count);
void vgm_timer_add(uint16_t delta);
bool vgm_timer_elapsed(void);

#endif
