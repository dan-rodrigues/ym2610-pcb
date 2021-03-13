// ym_ctrl.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MI

#include <stdint.h>
#include <stdbool.h>

#ifndef ym_ctrl_h
#define ym_ctrl_h

void ym_write(uint16_t reg, uint8_t data);

void ym_write_a(uint8_t reg, uint8_t data);
void ym_write_b(uint8_t reg, uint8_t data);

void ym_reset(bool reset_active);

#endif
