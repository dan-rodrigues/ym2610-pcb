#!/usr/bin/env python3

# psg_state.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

# Subset of PSG state is tracked here
# It's translated to approximate SSG commands
#
# It's incomplete and doesn't support repurposing one of three channels for noise

class SSGWriteAction:
	def __init__(self, address, data):
		self.address = address
		self.data = data

class PSGState:
	def __init__(self, reference_clock=3579545, target_clock=8000000):
		self.reference_clock = reference_clock
		self.target_clock = target_clock
		self.pitch_factor = (target_clock << 32) // reference_clock // 2

		self.pitches = [0] * 3
		self.previous_reg = 0

	def write(self, data):
		if data & 0x80:
			return self.latch_write(data & 0x7f)
		else:
			return self.data_write(data & 0x7f)

	def preamble(self):
		# Enable all 3 voices as square waves, not noise
		# This would change if noise support is added
		return [SSGWriteAction(0x007, ~0x07 & 0xff)]

	def latch_write(self, combined):
		reg = (combined >> 4) & 0x07
		data = combined & 0x0f

		if reg < 6:
			# Tone control

			ch = reg // 2
			is_volume = reg & 0x01

			self.previous_reg = reg

			if is_volume:
				# Volume writes don't need deferring
				return [SSGWriteAction(0x008 + ch, ~data & 0x0f)]
			else:
				# Deferring write until high portion of pitch is known
				self.pitches[ch] = data
				return []
		else:
			# Noise control
			# (not implemented for now, would need to "steal" one of three SSG voices for this)
			print("PSG: Ignoring noise control write (TODO) ")
			return []

	def data_write(self, combined):
		data = combined & 0x3f
		ch = self.previous_reg // 2

		self.pitches[ch] |= data << 4
		pitch = (self.pitches[ch] * self.pitch_factor) >> 32

		return [
			SSGWriteAction(0x000 + ch * 2, pitch & 0xff),
			SSGWriteAction(0x001 + ch * 2, pitch >> 8)
		]
