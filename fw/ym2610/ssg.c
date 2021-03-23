// ssg.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include "ssg.h"

#include "ym_ctrl.h"

void ssg_mute_all() {
	// Disable all outputs
	ym_write(0x007, ~0);
}
