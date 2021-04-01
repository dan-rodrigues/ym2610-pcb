#!/usr/bin/env python3

# ym2612_dac_state.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import wave

class YM2612DACState:
	def __init__(self, seek_logging=False):
		self.data_bank = bytearray()
		self.logged_samples = bytearray()
		self.index = 0
		self.seek_logging = seek_logging

	def extend_data_bank(self, data):
		self.data_bank.extend(data)
		print("Extended DAC data bank size: {:X}".format(len(self.data_bank)))

	def seek(self, index):
		self.index = index

		if self.seek_logging:
			print("DAC seek to: {:X}".format(index))

	def set_output(self, data):
		self.logged_samples[-1] = data

	def output_data_bank_sample(self, delay):
		sample = self.read_sample()
		self.logged_samples.extend([sample] * delay)

	def pad_output(self, data, alignment, padding_byte=0x80):
		remainder = len(data) % alignment
		if remainder > 0:
			 data.extend([padding_byte] * (alignment - remainder))

	def delay(self, count):
		sample = 0 if len(self.logged_samples) == 0 else self.logged_samples[-1]
		self.logged_samples.extend([sample] * count)

	def read_sample(self):
		sample = self.data_bank[self.index]
		self.index += 1
		return sample

	### 

	def parition_blocks(self):
		index = 0

		blocks = []
		current_block = None

		while True:
			# Find range of silence
			silence_indexes = self.scan_silence(index)
			if silence_indexes is None:
				# !!! need to terminate the last one?
				break

			index = silence_indexes[1]

			if current_block is not None:
				# ..terminate the current sample block if there was one..
				current_block.data = self.logged_samples[current_block.timestamp : silence_indexes[0]]
				self.pad_output(current_block.data, alignment=0x200)
				blocks.append(current_block)

			# ..then a new sample block starts where the previous one ended
			current_block = DACSampleBlock()
			current_block.timestamp = silence_indexes[1]

		print("Created {:X} DAC sample blocks".format(len(blocks)))
		total_length = 0
		for block in blocks:
			total_length += len(block.data)
		print("Total length {:X}".format(total_length))

		return blocks

	def write_wav(self):
		with wave.open('out.wav', 'wb') as file:
			self.write_wav_data(file, self.logged_samples)

	def write_wav_blocks(self, blocks):
		with wave.open('out_blocks.wav', 'wb') as file:
			combined_block = bytearray()
			for block in blocks:
				combined_block.extend(block.data)

			self.write_wav_data(file, combined_block)

	def write_wav_data(self, file, data):
		file.setnchannels(1)
		file.setsampwidth(2)
		file.setframerate(44100)

		pcm_s16 = map(lambda x: (x - 0x80) * 0x100, data)
		pcm_bytes = bytearray()
		for sample in pcm_s16:
			pcm_bytes.append(sample & 0xff)
			pcm_bytes.append((sample >> 8) & 0xff)

		file.writeframes(pcm_bytes)

	def scan_silence(self, index):
		consecutive = 0
		prev = 0

		start_index = index

		while index < len(self.logged_samples):
			sample = self.logged_samples[index]

			if sample == prev:
				consecutive += 1
			else:
				if consecutive >= 512:
					print("found silence in {:X} samples".format(consecutive))
					return (start_index, index)

				consecutive = 0
				start_index = index

			prev = sample
			index += 1

		return None

class DACSampleBlock:
	def __init__(self):
		self.data = None
		self.timestamp = None

