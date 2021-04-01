#!/usr/bin/env python3

# vgm_inserter.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys

class VGMInserter:
	def __init__(self, processed_vgm, base_index):
		self.processed_vgm = processed_vgm
		self.index = base_index
		self.base_timestamp = 0

	def insert_commands(self, command_bytes, timestamp):
		data = self.processed_vgm.data
		while self.index < len(data):
			if self.base_timestamp >= timestamp:
				break

			cmd = data[self.index]

			index_delta = self.non_delay_cmd(cmd)
			if index_delta is not None:
				self.index += index_delta
				continue

			delay_t = self.delay_cmd(cmd, data[self.index + 1 : self.index + 9])
			if delay_t is not None:
				self.base_timestamp += delay_t[0]
				self.index += delay_t[1]
				continue

			if cmd == 0x66:
				break

			print("VGMInserter: unexpected cmd: {:X} @ {:X}".format(cmd, self.index))
			sys.exit(1)

		# If we land in the middle of a delay, could split the command
		# This shouldn't be needed unless the DAC stream commands are used

		data[self.index : self.index] = command_bytes

		# Displace loop offset if the newly inserted commands affect it
		if self.processed_vgm.loop_index() >= self.index:
			self.processed_vgm.displace_loop_offset(len(command_bytes))

		print("VGMInserter: inserted ADPCM-B cmd at index: {:X}".format(self.index))

	def delay_cmd(self, cmd, payload):
		if (cmd & 0xf0) == 0x70:
			return ((cmd & 0x0f) + 1, 1)
		if cmd == 0x62:
			return (735, 1)
		if cmd == 0x63:
			return (882, 1)
		if cmd == 0x61:
			return (int.from_bytes(payload[0 : 2], 'little'), 3)

		return None

	def non_delay_cmd(self, cmd):
		command_lengths = [
			([0x52, 0x53, 0x58, 0x59], 3),
		]

		for t in command_lengths:
			if cmd in t[0]:
				return t[1]

		return None

## TODO: relocate

class DACCommandInserter:
	def __init__(self, processed_vgm, dac_sample_blocks):
		base_index = processed_vgm.read_header_offset(0x34)
		self.inserter = VGMInserter(processed_vgm, base_index)
		self.dac_sample_blocks = dac_sample_blocks
		self.processed_vgm = processed_vgm
		self.encoded_blocks = processed_vgm.pcm_blocks

	def insert(self):
		base_timestamp = 0
		for index in range(0, len(self.dac_sample_blocks)):
			source_block = self.dac_sample_blocks[index]
			encoded_block = self.encoded_blocks[index]

			commands = self.adpcmb_play_commands(encoded_block)
			if source_block.timestamp < base_timestamp:
				print("DACCommandInserter: expected timestamps to be in ascending order")
				sys.exit(1)

			self.inserter.insert_commands(commands, source_block.timestamp)

	def adpcmb_play_commands(self, encoded_block):
		adpcmb_44p1khz = 0xCB6B
		start_address = encoded_block.remapped_offset >> 8
		end_address = start_address + (len(encoded_block.data) >> 8) - 1

		return [
			# Reset
			0x58, 0x10, 0x01,
			0x58, 0x10, 0x00,

			# ADPCM-B start/end address
			0x58, 0x12, start_address & 0xff,
			0x58, 0x13, start_address >> 8,
			0x58, 0x14, end_address & 0xff,
			0x58, 0x15, end_address >> 8,

			# Pitch
			0x58, 0x19, adpcmb_44p1khz & 0xff,
			0x58, 0x1a, adpcmb_44p1khz >> 8,

			# Volume
			0x58, 0x1b, 0x60,

			# Pan
			0x58, 0x11, 0xc0,

			# Start
			0x58, 0x10, 0x80
		]

