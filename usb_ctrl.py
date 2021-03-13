#!/usr/bin/env python3

# usb_ctrl.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys

import usb.core
import usb.util

import binascii
import struct
import sys
from pathlib import Path
from enum import Enum

import threading
import time

class PCMType(Enum):
	A = 0
	B = 1

class PCMBlock:
	def __init__(self):
		self.offset = 0
		self.data = []
		self.type = PCMType.A

class ProcessedVGM:
	def __init__(self):
		self.data = []
		self.pcm_blocks = []

	def __repr__(self):
		return "ProcessedVGM:\nCommand data length: {:X}\nPCM blocks: {:X}\n" \
			.format(len(self.data), len(self.pcm_blocks))

def get_data_ep(dev):
	cfg = dev.get_active_configuration()
	intf = cfg[(1,0)]

	# The single bulk OUT endpoint is the one that will be used for PCM / VGM data writing
	ep = usb.util.find_descriptor(
		intf,
		custom_match = \
		lambda e: \
			usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT and \
			usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK \
			)

	if ep is None:
		print("Data endpoint not found")
		sys.exit(1)

	return ep

def get_status_ep(dev):
	cfg = dev.get_active_configuration()
	intf = cfg[(1,0)]

	# The status EP that is used by this script to monitor state, respond requests etc.
	ep = usb.util.find_descriptor(
		intf,
		custom_match = \
		lambda e: \
			usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN and \
			usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_INTR \
			)

	if ep is None:
		print("Status endpoint not found")
		sys.exit(1)

	return ep


def read_vgm(path):
	with open(path, "rb") as vgm_file:
		vgm = vgm_file.read()

	if len(vgm) == 0:
		print("VGM file is empty: ", path)
		sys.exit(1)

	return vgm

###

class WriteMode(Enum):
	PCM_A = 0x00
	PCM_B = 0x01
	VGM = 0x02

def set_write_mode(dev, write_mode, length, offset):
	CTRL_SET_WRITE_MODE = 0x00
	REQUEST_TYPE = 0x41

	offset_bytes = offset.to_bytes(4, 'little')
	length_bytes = length.to_bytes(4, 'little')
	data_bytes = offset_bytes + length_bytes 

	dev.ctrl_transfer(REQUEST_TYPE, CTRL_SET_WRITE_MODE, write_mode.value, 0, data_bytes)

def send_vgm(dev, ep, vgm, offset=0, restart_playback=True):
	CTRL_READ_STATUS = 0x80
	CTRL_START_PLAYBACK = 0x01
	REQUEST_TYPE = 0x41

	# Prepare for writing..
	set_write_mode(dev, WriteMode.VGM, len(vgm), offset)

	# ..write..
	ep.write(vgm, 20000)

	if restart_playback:
		# ..start playback after writing
		dev.ctrl_transfer(REQUEST_TYPE, CTRL_START_PLAYBACK, 0, 0)

def send_pcm(dev, ep, block):
	set_write_mode(dev, WriteMode.PCM_A if block.type == PCMType.A else WriteMode.PCM_B, len(block.data), block.offset)
	ep.write(block.data, 20000)

def send_pcm_blocks(dev, ep, pcm_blocks):
	for block in pcm_blocks:
		send_pcm(dev, ep, block)

###

def poll_status(stopping_event, status_ep, data_ep, processed_vgm):
	print("Polling for status...")

	vgm_data = processed_vgm.data

	while not stopping_event.is_set():
		try:
			BUFFERING_REQUEST_HEADER = 0x01
			STATUS_TOTAL_LENGTH = 16

			status_data = status_ep.read(STATUS_TOTAL_LENGTH, 250)
			print("Received status data: ", binascii.hexlify(status_data))

			header = int.from_bytes(status_data[0 : 4], byteorder='little')
			if header != BUFFERING_REQUEST_HEADER:
				print("Ignoring request with header: ", header)
				continue

			buffer_target_offset = int.from_bytes(status_data[4 : 8], byteorder='little')
			vgm_start_offset = int.from_bytes(status_data[8 : 12], byteorder='little')
			vgm_chunk_length = int.from_bytes(status_data[12 : 16], byteorder='little')

			print("Sending VGM chunk to buffer @ {:X}, VGM offset: {:X}, Length: {:X}"\
				  .format(buffer_target_offset, vgm_start_offset, vgm_chunk_length))

			vgm_chunk = vgm_data[vgm_start_offset : vgm_start_offset + vgm_chunk_length]

			send_vgm(dev, data_ep, vgm_chunk, buffer_target_offset, restart_playback=False)

		except usb.core.USBError as e:
			# Swallowing exceptions like this is dirty but there are several coming in as "timeouts"
			# FIXME: filter out the exceptions of interest and raise the non-timeout related ones
			continue

def start_polling_status(dev, status_ep, data_ep, processed_vgm):
	stopping_event = threading.Event()
	thread = threading.Thread(target=poll_status, args=(stopping_event, status_ep, data_ep, processed_vgm))
	thread.daemon = True
	thread.start()
	return (thread, stopping_event)

###

def preprocess_vgm(vgm):
	relative_offset_index = 0x34
	relative_offset = int.from_bytes(vgm[relative_offset_index : relative_offset_index + 4], byteorder='little')
	start_index = relative_offset_index + relative_offset if relative_offset else 0x40
	print("VGM start index: {:X}".format(start_index))

	loop_offset_index = 0x1c
	loop_offset = int.from_bytes(vgm[loop_offset_index : loop_offset_index + 4], byteorder='little')
	loop_index = loop_offset + loop_offset_index if loop_offset else 0
	print("VGM loop index: {:X}".format(loop_index))

	index = start_index

	processed_vgm = ProcessedVGM()
	vgm_bytes = bytearray(vgm)

	while index < len(vgm_bytes):
		cmd = vgm_bytes[index]
		index += 1

		if cmd == 0x58 or cmd == 0x59:
			index += 2
		elif (cmd & 0xf0) == 0x70:
			pass
		elif cmd == 0x61:
			index += 2
		elif cmd == 0x62 or cmd == 0x63:
			pass
		elif cmd == 0x66:
			break
		elif cmd == 0x67:
			block_type = vgm_bytes[index + 1]
			block_size = int.from_bytes(vgm_bytes[index + 2 : index + 6], byteorder='little')
			block_size -= 8
			if block_size <= 0:
				print("Expected PCM block size to be > 0")

			print('PCM block size: {:X}'.format(block_size))

			if block_type != 0x82 and block_type != 0x83:
				print("Unexpected block type: {:X}".format(block_type))
				sys.exit(1)

			total_size = int.from_bytes(vgm_bytes[index + 6 : index + 10], byteorder='little')
			if total_size == 0:
				print('Expected total_size to be > 0')
				sys.exit(1)

			offset = int.from_bytes(vgm_bytes[index + 10 : index + 14], byteorder='little')

			is_adpcm_a = block_type == 0x82

			print('Found block: type ', 'A' if is_adpcm_a else 'B')
			print('Size: {:X}, offset: {:X}, total: {:X}'.format(block_size, offset, total_size))

			# Some PCM blocks are 0 size for whatever reason, just ignore them
			if block_size > 0:
				pcm_block = PCMBlock()
				pcm_block.offset = offset
				pcm_block.data = vgm_bytes[index + 14 : index + 14 + block_size]
				pcm_block.type = PCMType.A if is_adpcm_a else PCMType.B
				processed_vgm.pcm_blocks.append(pcm_block)

			# Remove PCM block portion from VGM as it's preloaded in separate write step(s)
			block_start = index - 1
			block_end = index + 14 + block_size
			block_size = block_end - block_start

			del vgm_bytes[block_start : block_end]

			index -= 1

			# Loop index may need adjusting if removal of PCM block displaced it
			if index < loop_index:
				loop_index -= block_size


	# Reassign possibly adjusted loop offset due to PCM block removal above
	adjusted_loop_offset = loop_index - loop_offset_index
	loop_offset_bytes = adjusted_loop_offset.to_bytes(4, 'little')
	vgm_bytes[loop_offset_index : loop_offset_index + 4] = loop_offset_bytes
	print("VGM adjusted loop offset: {:X}".format(adjusted_loop_offset))

	# Make immutable bytes object since this will be handled by another thread
	processed_vgm.data = bytes(vgm_bytes)
	print(processed_vgm)

	return processed_vgm

###

dev = usb.core.find(idVendor=0x1d50, idProduct=0x6147)

if dev is None:
	print('Bitsy device found not found')
	sys.exit(1)

# Initial USB config

dev.set_configuration()

data_ep = get_data_ep(dev)
status_ep = get_status_ep(dev)

# Read a VGM to send

if len(sys.argv) != 2:
	print('Expected one argument with filename')
	sys.exit(1)

filename = sys.argv[1]

vgm = read_vgm(filename)
processed_vgm = preprocess_vgm(vgm)
send_pcm_blocks(dev, data_ep, processed_vgm.pcm_blocks)
send_vgm(dev, data_ep, processed_vgm.data)

(status_thread, status_stopping_event) = start_polling_status(dev, status_ep, data_ep, processed_vgm)

while True:
	try:
		time.sleep(0.5)
	except KeyboardInterrupt:
		status_stopping_event.set()
		status_thread.join()
		sys.exit(1)
