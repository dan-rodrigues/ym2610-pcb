#!/usr/bin/env python3

# opn_state.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

# Subset of OPN FM state required to do pitch adjustment

class OPNWriteAction:
	def __init__(self, address, data):
		self.address = address
		self.data = data

class OPNState:
	def __init__(self, reference_clock=7670400, target_clock=8000000):
		self.reference_clock = reference_clock
		self.target_clock = target_clock
		self.pitch_factor = (reference_clock << 32) // target_clock
		self.pitches = [0] * 6

	def write(self, address, data):
		hi_address_map = {
			0x0a4: 0,
			0x0a5: 1,
			0x0a6: 2,
			0x1a4: 3,
			0x1a5: 4,
			0x1a6: 5
		}

		lo_address_map = {
			0x0a0: 0,
			0x0a1: 1,
			0x0a2: 2,
			0x1a0: 3,
			0x1a1: 4,
			0x1a2: 5
		}

		index = hi_address_map.get(address, None)
		if index is not None:
			self.pitches[index] = data
			# Deferring hi write until lo is written
			return []

		index = lo_address_map.get(address, None)
		if index is None:
			# Pass through original write command
			return [OPNWriteAction(address, data)]

		# Adjust pitch

		lo_pitch_address = address
		hi_pitch_address = address + 4

		hi_data = self.pitches[index]

		pitch = ((hi_data & 0x07) << 8) | data
		pitch = (pitch * self.pitch_factor) >> 32

		block = hi_data & 0xf8

		return [
			# Hi write must come first
			OPNWriteAction(hi_pitch_address, ((pitch >> 8) & 0x07) | block),
			OPNWriteAction(lo_pitch_address, pitch & 0xff)
		]
