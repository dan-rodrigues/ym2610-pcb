// mem_util.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef mem_util_h
#define mem_util_h

#include <stdint.h>
#include <stddef.h>

uint32_t read32(const uint8_t *bytes);
void *memcpy(void *s1, const void *s2, size_t n);

#endif
