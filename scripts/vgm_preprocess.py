#!/usr/bin/env python3

# vgm_preprocess.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys
from enum import Enum

class PCMType(Enum):
	A = 0
	B = 1

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

	def sort_pcm_blocks(self):
		# FIXME:
		# this could cause problems for ADPCMB samples sandwiched between A samples or vice versa
		# for MERGED tracks, separate ones might have other issues
		sorted(self.pcm_blocks, key=lambda block: block.offset + 0x1000000 if block.type == PCMType.B else 0)

	def merge_contiguous_pcm_blocks(self):
		last_end_address = None
		indexes_to_remove = []

		for i in range(0, len(self.pcm_blocks)):
			block = self.pcm_blocks[i]
			if last_end_address is None:
				last_end_address = block.offset + len(block.data)
				continue

			if last_end_address == block.offset:
				# Blocks needs merging to prevent discontinuity when rebasing
				merged_block = self.pcm_blocks[i - 1]
				merged_block.data.extend(block.data)
				indexes_to_remove.append(i)

			last_end_address = block.offset + len(block.data)

		indexes_to_remove.reverse()
		for i in indexes_to_remove:
			del self.pcm_blocks[i]

		print("Merged {:d} PCM blocks".format(len(indexes_to_remove)))

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

		previous_split_index = 0
		index = 0
		bank_corrected_indexes = []

		while index < len(self.pcm_blocks):
			block = self.pcm_blocks[index]

			block_bank = block.offset >> 16
			block_end_bank = (block.offset + len(block.data)) >> 16
			remapped_offset = block.offset & 0xffff

			# FIXME: shouldn't be applied if a 1MB bank crossing just happened
			if previous_end_bank is not None and (previous_end_bank != block_bank):
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

# This doesn't necessarily work for cases where (loop index < start index)
# (Are there actually examples of this?)

class VGMPreprocessor:
	def __init__(self):
		# Options? YM2612 reference clock?
		# ...
		pass

	def preprocess(self, vgm_in):
		relative_offset_index = 0x34
		relative_offset = int.from_bytes(vgm_in[relative_offset_index : relative_offset_index + 4], byteorder='little')
		start_index = relative_offset_index + relative_offset if relative_offset else 0x40
		print("VGM start index: {:X}".format(start_index))

		loop_offset_index = 0x1c
		loop_offset = int.from_bytes(vgm_in[loop_offset_index : loop_offset_index + 4], byteorder='little')
		loop_index = loop_offset + loop_offset_index if loop_offset else 0
		print("VGM loop index: {:X}".format(loop_index))

		index = start_index
		flag_writes_removed = 0

		# ...

		processed_vgm = ProcessedVGM()
		vgm_out = bytearray()

		# Copy existing header which will be updated later
		vgm_out.extend(vgm_in[0x00 : start_index])

		# Loop index needs adjusting based on data being added / removed
		loop_index_adjusted = None

		def copy(length):
			nonlocal index, vgm_in, vgm_out

			vgm_out.extend(vgm_in[index : index + length])
			index += length

		def byte_swap(data):
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


		while index < len(vgm_in):
			if loop_index == index and loop_index_adjusted is None:
				# End of newly written VGM is the new loop index
				loop_index_adjusted = len(vgm_out)

			cmd = vgm_in[index]

			if cmd in [0x58, 0x59]:
				# Reg write
				record_reg_write()
				copy(3)
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
				block_size = int.from_bytes(vgm_in[index + 3 : index + 7], byteorder='little')
				block_size -= 8
				if block_size <= 0:
					print("Expected PCM block size to be > 0")

				print('PCM block size: {:X}'.format(block_size))

				if block_type != 0x82 and block_type != 0x83:
					print("Unexpected block type: {:X}".format(block_type))
					sys.exit(1)

				total_size = int.from_bytes(vgm_in[index + 7 : index + 11], byteorder='little')
				if total_size == 0:
					print('Expected total_size to be > 0')
					sys.exit(1)

				offset = int.from_bytes(vgm_in[index + 11 : index + 15], byteorder='little')

				is_adpcm_a = (block_type == 0x82)

				print('Found block: type ', 'A' if is_adpcm_a else 'B')
				print('Size: {:X}, offset: {:X}, total: {:X}'.format(block_size, offset, total_size))

				# Some PCM blocks are 0 size for whatever reason, just ignore them
				if block_size > 0:
					pcm_block = PCMBlock()
					pcm_block.offset = offset
					pcm_swapped = byte_swap(vgm_in[index + 15 : index + 15 + block_size])
					pcm_block.data = pcm_swapped
					pcm_block.type = PCMType.A if is_adpcm_a else PCMType.B
					processed_vgm.pcm_blocks.append(pcm_block)

				# Note the command is NOT copied, it's stripped out entirely
				index += (block_size + 15)
			else:
				print("Unrecognized command byte: {:X}".format(cmd))
				sys.exit(1)

		# PCM blocks need sorting according to their position and type..
		processed_vgm.sort_pcm_blocks()
		# ..then possibly merged into contiguous blocks..
		processed_vgm.merge_contiguous_pcm_blocks()
		# ..then offsets need adjusting from a zero-base..
		processed_vgm.rebase_pcm_blocks()
		# ..then the address high bytes need adjusting according to the newly sorted position
		for bank_index in pcm_address_indexes:
			bank_byte = vgm_out[bank_index]
			remapped_bank_byte = processed_vgm.remap_pcm_bank_byte(bank_byte)
			if remapped_bank_byte is None:
				print("Couldn't find matching PCM bank byte: {:X}".format(bank_byte))
				continue

			vgm_out[bank_index] = remapped_bank_byte

		# Reassign loop index after possible displacement
		loop_index_adjusted -= loop_offset_index
		vgm_out[loop_offset_index : loop_offset_index + 4] = loop_index_adjusted.to_bytes(4, 'little')
		print("VGM adjusted loop offset: {:X}".format(loop_index_adjusted))

		processed_vgm.data = bytes(vgm_out)

		return processed_vgm