// spi_mem.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "config.h"

#include "spi_mem.h"

// static volatile uint8_t * const flash_cmd = (void*)(SPI_CTRL_BASE + 0);
static volatile uint8_t * const psram_cmd = (void*)(SPI_CTRL_BASE + 4);

void spi_mem_init() {
	// All access to PSRAM is using QPI
	const uint8_t QPI_ENABLE_CMD = 0x35;
	*psram_cmd = QPI_ENABLE_CMD;
}
