/*
 * spi.c
 *
 * Copyright (C) 2019 Sylvain Munaut
 * All rights reserved.
 *
 * LGPL v3+, see LICENSE.lgpl3
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

// All functions in this file have been stubbed out
// There is a usb_dfu source that calls these in response to ctrl commands
// This isn't used in this project though

// The SPI peripheral that backs the spi struct below doesn't exist in this project
// spi_mem.v works in its place

#include <stdbool.h>
#include <stdint.h>

#include "config.h"
#include "spi.h"

//struct spi {
//	uint32_t _rsvd0[6];
//	uint32_t irq;		/* 0110 - SPIIRQ   - Interrupt Status Register  */
//	uint32_t irqen;		/* 0111 - SPIIRQEN - Interrupt Control Register */
//	uint32_t cr0;		/* 1000 - CR0      - Control Register 0 */
//	uint32_t cr1;		/* 1001 - CR1      - Control Register 1 */
//	uint32_t cr2;		/* 1010 - CR2      - Control Register 2 */
//	uint32_t br;		/* 1011 - BR       - Baud Rate Register */
//	uint32_t sr;		/* 1100 - SR       - Status Register    */
//	uint32_t txdr;		/* 1101 - TXDR     - Transmit Data Register */
//	uint32_t rxdr;		/* 1110 - RXDR     - Receive Data Register  */
//	uint32_t csr;		/* 1111 - CSR      - Chip Select Register   */
//} __attribute__((packed,aligned(4)));

//static volatile struct spi * const spi_regs = (void*)(SPI_BASE);

void spi_init() {}
void spi_xfer(unsigned cs, struct spi_xfer_chunk *xfer, unsigned n) {}
