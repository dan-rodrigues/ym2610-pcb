// mem_util.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "mem_util.h"

uint32_t read32(const uint8_t *bytes) {
	uint32_t word = bytes[0];
	word |= bytes[1] << 8;
	word |= bytes[2] << 16;
	word |= bytes[3] << 24;

	return word;
}
