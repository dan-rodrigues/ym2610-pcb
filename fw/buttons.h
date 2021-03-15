// buttons.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef buttons_h
#define buttons_h

#include <stdbool.h>

void btn_poll(void);

bool btn_a(void);
bool btn_b(void);
bool btn_a_edge(void);
bool btn_b_edge(void);

#endif
