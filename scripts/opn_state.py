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
		self.pitches = [0] * 12

	def write(self, address, data):
		hi_address_map = {
			0x0a4: 0,
			0x0a5: 1,
			0x0a6: 2,
			0x1a4: 3,
			0x1a5: 4,
			0x1a6: 5,
			# "2CH mode"
			0x0ac: 6,
			0x0ad: 7,
			0x0ae: 8,
			0x1ac: 9,
			0x1ad: 10,
			0x1ae: 11
		}

		lo_address_map = {
			0x0a0: 0,
			0x0a1: 1,
			0x0a2: 2,
			0x1a0: 3,
			0x1a1: 4,
			0x1a2: 5,
			# "2CH mode"
			0x0a8: 6,
			0x0a9: 7,
			0x0aa: 8,
			0x1a8: 9,
			0x1a9: 10,
			0x1aa: 11
		}

		# Filtering all DAC writes as they are handled externally
		if address in [0x02a, 0x02b]:
			return []

		# This would filter out writes to FM CH6 key-on
		# Attempts to key-on CH6 while DAC is playing might cause issues
		# This shouldn't happen either way so it's commented out for now
		
		# if address == 0x28:
		# 	if (data & 0x7) == 6:
		# 		print("Filtering CH6.. ")
		# 		return []

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
