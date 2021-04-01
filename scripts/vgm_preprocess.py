#!/usr/bin/env python3

# vgm_preprocess.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys
from enum import Enum
from psg_state import PSGState
from opn_state import OPNState

class PCMType(Enum):
	A = 0
	B = 1

class ChipType(Enum):
	YM2610 = 0,
	YM2610B = 1,
	YM2612 = 2,
	SN76489 = 3

class Chip:
	ATTRIBUTES = [
		(ChipType.YM2610, 0x4c, 0),
		(ChipType.YM2610B, 0x4c, 1 << 31),
		(ChipType.YM2612, 0x2c, 0),
		(ChipType.SN76489, 0x0c, 0)
	]

	def __init__(self, chip_type, header_index, clock):
		self.chip_type = chip_type
		self.header_index = header_index
		self.clock = clock

class PCMBlock:
	def __init__(self):
		self.offset = 0
		self.remapped_offset = 0
		self.data = []
		self.type = PCMType.A

class ProcessedVGM:
	def __init__(self):
		self.data = []
		self.pcm_blocks = []

	def __repr__(self):
		return "ProcessedVGM:\nCommand data length: {:X}\nPCM blocks: {:X}\n" \
			.format(len(self.data), len(self.pcm_blocks))

	def sort_pcm_blocks(self, assume_unified_pcm):
		b_offset = 0 if assume_unified_pcm else 0x1000000
		sorted(self.pcm_blocks, key=lambda block: block.offset + b_offset if block.type == PCMType.B else 0)

	def rebase_pcm_blocks(self):
		base = 0

		def bank_cross_check(block, remapped_offset):
			nonlocal base

			# Would inserting this block at its current position cross a 1MB bank?
			# Need to preemptively move to next bank if so
			start = base + remapped_offset
			end = base + remapped_offset + len(block.data)

			if (start & 0xf00000) != (end & 0xf00000):
				base = (base + 0x100000) & 0xf00000
				print("..crossed 1MB bank..")
				return True

			return False

		previous_end_bank = None
		bank_crossed = False

		previous_split_index = 0
		index = 0
		bank_corrected_indexes = []

		while index < len(self.pcm_blocks):
			block = self.pcm_blocks[index]

			block_bank = block.offset >> 16
			block_end_bank = (block.offset + len(block.data)) >> 16
			remapped_offset = block.offset & 0xffff

			if not bank_crossed and previous_end_bank is not None and (previous_end_bank != block_bank):
				base += 0x10000
				previous_split_index = index

			bank_crossed = bank_cross_check(block, remapped_offset)
			if bank_crossed and (index not in bank_corrected_indexes):
				# Need to go back and move all blocks that share a 64K bank
				bank_corrected_indexes.append(index)
				index = previous_split_index
				print("..returning to index {:X} for 1MB bank crossing.."\
					.format(previous_split_index))
			else:
				remapped_offset += base
				block.remapped_offset = remapped_offset

				if block_end_bank != block_bank:
					base += (block_end_bank - block_bank) * 0x10000

				previous_end_bank = block_end_bank

				print("Remapped PCM block at: {:X}, originally: {:X}, size: {:X}"\
					.format(block.remapped_offset, block.offset, len(block.data)))

				index += 1

	def remap_pcm_bank_byte(self, bank_byte):
		for block in self.pcm_blocks:
			block_offset_bank = block.offset >> 16

			end_address = block.offset + len(block.data)
			block_end_bank = end_address >> 16
			block_range = range(block_offset_bank, block_end_bank + 1)
			if bank_byte not in block_range:
				continue

			remapped_bank = block.remapped_offset >> 16
			offset_bank = bank_byte - block_offset_bank
			offset_bank += remapped_bank

			return offset_bank

		return None

	def preprocess_pcm(self, pcm_bank_address_indexes, total_size):
		# PCM blocks need sorting according to their position and type..
		assume_unified_pcm = (total_size >= 0x400000)
		self.sort_pcm_blocks(assume_unified_pcm)
		# ..then offsets need adjusting from a zero-base..
		self.rebase_pcm_blocks()
		# ..then the address high bytes need adjusting according to the newly sorted position
		for bank_index in pcm_bank_address_indexes:
			bank_byte = self.data[bank_index]
			remapped_bank_byte = self.remap_pcm_bank_byte(bank_byte)
			if remapped_bank_byte is None:
				print("Couldn't find matching PCM bank byte: {:X}".format(bank_byte))
				continue

			self.data[bank_index] = remapped_bank_byte

	def write_pcm_blocks(self, start_index, total_size):
		# Inserting all PCM blocks in sequence, presumably at start
		pcm_commands = bytearray()

		for block in self.pcm_blocks:
			# Block header (generic)
			pcm_commands.extend([0x67, 0x66])
			pcm_commands.append(0x82 if block.type == PCMType.A else 0x83)
			pcm_commands.extend((len(block.data) + 8).to_bytes(4, 'little'))
			# PCM data block (sample ROM)
			pcm_commands.extend(total_size.to_bytes(4, 'little'))
			pcm_commands.extend(block.remapped_offset.to_bytes(4, 'little'))
			pcm_commands.extend(block.data)

		self.data[start_index:start_index] = pcm_commands
		return len(pcm_commands)

# This doesn't necessarily work for cases where (loop index < start index)
# (Any examples of this?)

class VGMPreprocessor:
	def __init__(self, assumed_clock=8000000):
		self.assumed_clock = assumed_clock

	def included_chips(self, vgm):
		chips = []
		clock_mask = ~0x80000000

		for t in Chip.ATTRIBUTES:
			index = t[1]
			clock = int.from_bytes(vgm[index : index + 4], 'little')
			if (clock == 0) or ((clock & clock_mask) > 8000000):
				continue

			presence_mask = t[2]
			if (presence_mask != 0) and ((clock & presence_mask) == 0):
				continue

			chip_type = t[0]
			chips.append(Chip(chip_type, index, clock & clock_mask))

		return chips

	def write_chip_header(self, vgm, chip_type, clock):
		attributes = next(filter(lambda t: t[0] == chip_type, Chip.ATTRIBUTES), None)
		if attributes is None:
			print("write_chip_header: couldn't find chip_type")
			sys.exit(1)

		index = attributes[1]
		header_clock = clock
		if clock > 0:
			header_clock |= attributes[2]

		vgm[index : index + 4] = header_clock.to_bytes(4, 'little')

	def byte_swap(self, data):
		pcm_swapped = bytearray(len(data))

		index = 0
		while index < len(data):
			temp = data[index + 0]
			pcm_swapped[index + 0] = data[index + 3]
			pcm_swapped[index + 3] = temp

			temp = data[index + 1]
			pcm_swapped[index + 1] = data[index + 2]
			pcm_swapped[index + 2] = temp

			index += 4

		return pcm_swapped

	def write_psg(self, vgm, actions):
		for action in actions:
			vgm.extend([0x58, action.address & 0xff, action.data])

	def write_opnb(self, vgm, actions):
		for action in actions:
			write_cmd = 0x59 if action.address >= 0x100 else 0x58
			vgm.extend([write_cmd, action.address & 0xff, action.data])

	def preprocess(self, vgm_in, rewrite_pcm=False, byteswap_pcm=True):
		flag_writes_removed = 0

		processed_vgm = ProcessedVGM()
		vgm_out = bytearray()

		def copy(length):
			nonlocal index, vgm_in, vgm_out

			vgm_out.extend(vgm_in[index : index + length])
			index += length

		# Header adjustments:

		def write_header_offset(header_index, file_index):
			nonlocal vgm_out

			file_offset = file_index - header_index
			vgm_out[header_index : header_index + 4] = file_offset.to_bytes(4, 'little')
			return file_offset

		def displace_header_offset(header_index, delta):
			nonlocal vgm_out

			file_offset_bytes = vgm_out[header_index : header_index + 4]
			file_offset = int.from_bytes(file_offset_bytes, 'little') + header_index
			file_offset += delta
			write_header_offset(header_index, file_offset)

		def read_header_offset(header_index):
			nonlocal vgm_in

			file_offset_bytes = vgm_in[header_index : header_index + 4]
			file_offset = int.from_bytes(file_offset_bytes, 'little')
			return file_offset + header_index if file_offset > 0 else 0

		def write_header_word(header_index, word):
			nonlocal vgm_out

			vgm_out[header_index : header_index + 4] = word.to_bytes(4, 'little')

		# Read source indexes (from relative offsets):
		relative_offset_index = 0x34
		start_index = read_header_offset(relative_offset_index)
		print("VGM start index: {:X}".format(start_index))

		index = start_index

		loop_offset_index = 0x1c
		loop_index = read_header_offset(loop_offset_index)
		print("VGM loop index: {:X}".format(loop_index))

		# What chips are included in this VGM?

		chips = self.included_chips(vgm_in)
		for chip in chips:
			print("Found {:s} @ {:d}Hz".format(chip.chip_type.name, chip.clock))

		ym2610_chip = next(filter(lambda c: c.chip_type in [ChipType.YM2610, ChipType.YM2610B], chips), None)
		ym2612_chip = next(filter(lambda c: c.chip_type == ChipType.YM2612, chips), None)
		psg_chip = next(filter(lambda c: c.chip_type == ChipType.SN76489, chips), None)

		if (ym2610_chip is None) and (ym2612_chip is None):
			print("Error: expected either YM2610 or YM2612")
			sys.exit(1)

		# Copy existing header which will be updated later
		vgm_out.extend(vgm_in[0x00 : 0x100])
		# Clear any leftover junk in the header incase
		if start_index < 0x100:
			vgm_out[start_index : 0x100] = [0] * (0x100 - start_index)
		# Preserve existing loop params if present
		if start_index < 0x80:
			loop_base_index = 0x7e
			loop_modifier_index = 0x7f
			vgm_out[loop_base_index] = 0
			vgm_out[loop_modifier_index] = 0

		# Bump version to 1.70 as some versions predate YM2610(B) support
		version_index = 0x08
		output_version = 0x00000170
		write_header_word(version_index, output_version)

		# Bump the index to 0x100 to make space for full-size header, if needed
		# Some tracks may have a shorter header by setting a lower start-offset
		minimum_start_index = 0x100
		if start_index < minimum_start_index:
			start_index = minimum_start_index
			write_header_offset(relative_offset_index, start_index)

		# Loop index needs adjusting based on data being added / removed
		loop_index_adjusted = None

		# PCM address remapping:

		pcm_address_indexes = []

		def record_reg_write():
			nonlocal index, vgm_in, vgm_out, pcm_address_indexes

			data_index = index + 2

			cmd = vgm_in[index + 0]
			address = vgm_in[index + 1]
			data = vgm_in[data_index]

			if cmd == 0x59:
				address += 0x100

			# ADPCM-A high address
			is_high_address = address in range(0x118, 0x11e) or address in range(0x128, 0x12e)

			# ADPCM-B high address
			is_high_address |= address in [0x013, 0x015]

			if is_high_address:
				# This address will need adjusting later
				output_index = len(vgm_out) + 2
				pcm_address_indexes.append(output_index)

		# Track OPN/PSG state for upcoming conversion (from YM2612):

		opn_state = None
		if ym2612_chip is not None:
			opn_state = OPNState(reference_clock=ym2612_chip.clock, target_clock=self.assumed_clock)

		psg_state = None
		if psg_chip is not None:
			psg_state = PSGState(reference_clock=psg_chip.clock, target_clock=self.assumed_clock)
			self.write_psg(vgm_out, psg_state.preamble())

		# Total size must be tracked as it changes PCM block sorting

		total_size = 0

		while index < len(vgm_in):
			if loop_index == index and loop_index_adjusted is None:
				# End of newly written VGM is the new loop index
				loop_index_adjusted = len(vgm_out)

			cmd = vgm_in[index]

			if cmd in [0x58, 0x59]:
				# YM2610 reg write
				record_reg_write()
				copy(3)
			elif cmd in [0x52, 0x53]:
				# YM2612 reg write
				if opn_state is None:
					print("Found YM2612 reg write but no YM2612 found in header")
					sys.exit(1)

				address = vgm_in[index + 1]
				data = vgm_in[index + 2]
				if cmd == 0x53:
					address += 0x100

				write_actions = opn_state.write(address, data)
				self.write_opnb(vgm_out, write_actions)

				index += 3
			elif cmd == 0x4f:
				# PSG stereo writes which sometimes appear but aren't used
				index += 2
			elif (cmd & 0xf0) == 0x80:
				# YM2612 PCM writes not supported
				index += 1
			elif cmd == 0x50:
				# PSG write, needs mapping
				if psg_state is None:
					print("Found PSG write but no PSG found in header")
					sys.exit(1)

				data = vgm_in[index + 1]

				write_actions = psg_state.write(data)
				self.write_opnb(vgm_out, write_actions)

				index += 2
			elif (cmd & 0xf0) == 0x70:
				# Delay (4bit)
				copy(1)
			elif cmd == 0x61:
				# Delay (16bit)
				copy(3)
			elif cmd in [0x62, 0x63]:
				# Delay (50Hz / 60Hz constants)
				copy(1)
			elif cmd == 0x66:
				# End of stream
				copy(1)
				break
			elif cmd == 0x67:
				# Data block (PCM)

				block_type = vgm_in[index + 2]
				block_size = int.from_bytes(vgm_in[index + 3 : index + 7], 'little')
				block_size -= 8
				if block_size <= 0:
					print("Expected PCM block size to be > 0")

				print('PCM block size: {:X}'.format(block_size))

				if block_type != 0x82 and block_type != 0x83:
					print("Unexpected block type: {:X}".format(block_type))
					sys.exit(1)

				block_total_size = int.from_bytes(vgm_in[index + 7 : index + 11], 'little')
				if block_total_size == 0:
					print('Expected total_size to be > 0')
					sys.exit(1)

				total_size = max(block_total_size, total_size)

				offset = int.from_bytes(vgm_in[index + 11 : index + 15], 'little')

				is_adpcm_a = (block_type == 0x82)

				print("Found block: type ", "A" if is_adpcm_a else "B")
				print("Size: {:X}, offset: {:X}, total: {:X}".format(block_size, offset, block_total_size))

				# Some PCM blocks are 0 size for whatever reason, just ignore them
				if block_size > 0:
					pcm_block = PCMBlock()
					pcm_block.offset = offset

					pcm_data = vgm_in[index + 15 : index + 15 + block_size]
					if byteswap_pcm:
						pcm_block.data = self.byte_swap(pcm_data)
					else:
						pcm_block.data = pcm_data

					pcm_block.type = PCMType.A if is_adpcm_a else PCMType.B
					processed_vgm.pcm_blocks.append(pcm_block)

				# The original PCM command block is stripped out
				index += (block_size + 15)
			else:
				print("Unrecognized command byte: {:X}".format(cmd))
				sys.exit(1)

		# Reassign loop index after possible displacement
		if loop_index_adjusted is not None:
			loop_offset_adjusted = write_header_offset(loop_offset_index, loop_index_adjusted)
			print("VGM adjusted loop offset: {:X}".format(loop_offset_adjusted))

		# Now that PCM blocks are extracted, they need preprocessing too
		# FIXME: multiple references and updates to same bytearray isn't great, refactor as part of cleanup
		processed_vgm.data = vgm_out
		processed_vgm.preprocess_pcm(pcm_address_indexes, total_size)

		if rewrite_pcm:
			total_pcm_size = processed_vgm.write_pcm_blocks(start_index, total_size)
			# Bump loop index which may have been assigned already
			displace_header_offset(loop_offset_index, total_pcm_size)

		# Remove GD3 data as it wasn't copied here (trying to save space, but could add it as an option)
		gd3_offset_index = 0x14
		gd3_input_index = read_header_offset(gd3_offset_index)
		write_header_offset(gd3_offset_index, len(vgm_out))
		# Copied GD3 region assumes it spans (index..<eof)
		vgm_out.extend(vgm_in[gd3_input_index : gd3_input_index + len(vgm_in)])

		# Reassign EOF offset (this particular hardware player doesn't check it but others do)
		eof_offset_index = 0x04
		write_header_offset(eof_offset_index, len(vgm_out))

		# In all cases, the output is a YM2610(B) VGM regardless of original input
		self.write_chip_header(vgm_out, ChipType.YM2610B, self.assumed_clock)
		self.write_chip_header(vgm_out, ChipType.SN76489, 0)
		self.write_chip_header(vgm_out, ChipType.YM2612, 0)

		processed_vgm.data = bytes(vgm_out)
		return processed_vgm
