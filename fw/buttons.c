// buttons.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "buttons.h"

#include <stdint.h>

#include "config.h"

static bool btn_a_prev;
static bool btn_b_prev;
static bool btn_a_rose;
static bool btn_b_rose;

static volatile uint32_t * const BUTTONS = (void*)(BUTTONS_BASE);

void btn_poll() {
	bool btn_a_new = !(*BUTTONS & 0x01);
	bool btn_b_new = !(*BUTTONS & 0x02);

	btn_a_rose = !btn_a_prev && btn_a_new;
	btn_b_rose = !btn_b_prev && btn_b_new;

	btn_a_prev = btn_a_new;
	btn_b_prev = btn_b_new;
}

bool btn_a() {
	return btn_a_prev;
}

bool btn_b() {
	return btn_b_prev;
}

bool btn_a_edge() {
	return btn_a_rose;
}

bool btn_b_edge() {
	return btn_b_rose;
}
