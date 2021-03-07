// boot.S
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef FLASH_APP_ADDR
#define FLASH_APP_ADDR 0x00100000
#endif

// #define YM2610_TEST
// #define YM2610_PCM_MUX_TEST

	.section .text.start
	.global _start

_start:

#ifdef YM2610_PCM_MUX_TEST

// Need to enable QPI PSRAM access first
	li a0, 0x82000000
	li a1, 0x35
	sw a1, 4(a0)

// Write some test data to PSRAM
	li a0, 0x60000000
	li a1, 0x60000100
	li a2, 0x00010203
	li a3, 0x04040404
pcm_loop:
	sw a2, (a0)

	add a2, a2, a3 
	addi a0, a0, 4
	bne a0, a1, pcm_loop

// Then PCM mux access is enabled
	li a0, 0x8a000000
	li a1, 1
	sw a1,(a0)

spin:
	j spin

#endif

#ifdef YM2610_TEST

// 2610 test

// Busy flag test
	li a0, 0x88000000
busy:
	lb a1, (a0)
	bnez a1, busy

// Write test:
	li a0, 0x88000000
	li a1, 0x55
	sb a1, (a0)

	li a1, 0xaa
	sb a1, 4(a0)

write_busy:
	lb a1, (a0)
	bnez a1, write_busy

	li a1, 0x66
	sb a1, 8(a0)

	li a1, 0xcc
	sb a1, 12(a0)

#endif

// ---

// Setup reboot code
	li t0, 0x0002006f
	sw t0, 0(zero)

// Flash -> SPRAM copy
	li a0, 0x00020000
	li a1, 0x40000000 + FLASH_APP_ADDR
	li a2, 0x40000000 + FLASH_APP_ADDR + 0x10000
flash_copy_loop:
	lw t0, (a1)
	sw t0, (a0)

	add a1, a1, 4
	add a0, a0, 4
	bne a1, a2, flash_copy_loop

	j 0x00020000
