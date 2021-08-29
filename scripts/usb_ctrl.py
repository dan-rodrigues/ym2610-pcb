#!/usr/bin/env python3

# usb_ctrl.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys
import errno

from vgm_preprocess import VGMPreprocessor
from vgm_preprocess import PCMType
from vgm_reader import VGMReader

import usb.core
import usb.util

import binascii
import struct
import sys
from pathlib import Path
from enum import Enum

import threading
import time

###

LOCAL_VGM_PREPROCESS_TEST = False

###

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
	set_write_mode(dev, WriteMode.PCM_A if block.type == PCMType.A else WriteMode.PCM_B, len(block.data), block.remapped_offset)
	ep.write(block.data, 20000)

def send_pcm_blocks(dev, ep, pcm_blocks):
	for block in pcm_blocks:
		send_pcm(dev, ep, block)

###

def poll_status(stopping_event, status_ep, data_ep, processed_vgm):
	print("Polling for status...")

	vgm_data = processed_vgm.data
	sequence_counter = 0

	while not stopping_event.is_set():
		try:
			BUFFERING_REQUEST_HEADER = 0x01
			STATUS_TOTAL_LENGTH = 16

			status_data = status_ep.read(STATUS_TOTAL_LENGTH, 250)
			print("Received status data: ", binascii.hexlify(status_data))

			header = int.from_bytes(status_data[0 : 4], 'little')
			if (header & 0xff) != BUFFERING_REQUEST_HEADER:
				print("Ignoring request with header: ", header)
				continue

			sequence_counter_received = header >> 8
			if sequence_counter != sequence_counter_received:
				print("Ignoring request with nonsequential counter: ", header)
				continue

			sequence_counter += 1
			sequence_counter &= 0xffffff

			buffer_target_offset = int.from_bytes(status_data[4 : 8], 'little')
			vgm_start_offset = int.from_bytes(status_data[8 : 12], 'little')
			vgm_chunk_length = int.from_bytes(status_data[12 : 16], 'little')

			print("Sending VGM chunk to buffer @ {:X}, VGM offset: {:X}, Length: {:X}"\
				  .format(buffer_target_offset, vgm_start_offset, vgm_chunk_length))

			vgm_chunk = vgm_data[vgm_start_offset : vgm_start_offset + vgm_chunk_length]

			send_vgm(dev, data_ep, vgm_chunk, buffer_target_offset, restart_playback=False)
		except usb.core.USBTimeoutError:
			# Timeouts are expected when no data is available since we're polling
			continue
		except usb.core.USBError as e:
			# Incase a libusb version without USBTImeoutError is used, this errno case is also handled
			if e.backend_error_code == -errno.ETIMEDOUT:
				continue

			print("A non-timeout USB exception was thrown. Exiting...")
			raise

def start_polling_status(dev, status_ep, data_ep, processed_vgm):
	stopping_event = threading.Event()
	thread = threading.Thread(target=poll_status, args=(stopping_event, status_ep, data_ep, processed_vgm))
	thread.daemon = True
	thread.start()
	return (thread, stopping_event)

def read_processed_vgm(vgm_path):
	vgm = VGMReader.read(vgm_path)
	processor = VGMPreprocessor()
	processed_vgm = processor.preprocess(vgm)
	return processed_vgm

###

if LOCAL_VGM_PREPROCESS_TEST:
	processed_vgm = read_processed_vgm(sys.argv[1])
	print(processed_vgm)
	sys.exit(0)

###

dev = usb.core.find(idVendor=0x1d50, idProduct=0x6147)

if dev is None:
	print("Bitsy device found not found")
	sys.exit(1)

# Initial USB config

dev.set_configuration()

data_ep = get_data_ep(dev)
status_ep = get_status_ep(dev)

# Read a VGM to send

if len(sys.argv) != 2:
	print("Expected one argument with filename")
	sys.exit(1)

filename = sys.argv[1]
processed_vgm = read_processed_vgm(filename)

send_pcm_blocks(dev, data_ep, processed_vgm.pcm_blocks)
send_vgm(dev, data_ep, processed_vgm.data)

(status_thread, status_stopping_event) = start_polling_status(dev, status_ep, data_ep, processed_vgm)

while True:
	try:
		if not status_thread.is_alive():
			break

		time.sleep(0.5)
	except KeyboardInterrupt:
		status_stopping_event.set()
		status_thread.join()
		sys.exit(1)
