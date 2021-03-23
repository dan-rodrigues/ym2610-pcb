// fm.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef fm_h
#define fm_h

#include <stdint.h>
#include <stdbool.h>

// Assuming 6 on the YM2610*B*

#define FM_CH_COUNT 6
#define FM_DISABLE_EXTRA_CH 1

void fm_init(void);

void fm_mute_all(void);
void fm_mute(uint8_t ch_mask);

void fm_key_mask(uint8_t ch_mask, bool on, uint8_t midi_note);
void fm_key(uint8_t ch, bool on, uint8_t note);

bool fm_should_allow_key_on(uint16_t address, uint8_t data, uint8_t ch_mask);
bool fm_should_allow_pitch_write(uint16_t address, uint8_t data, uint8_t ch_mask);

#endif
