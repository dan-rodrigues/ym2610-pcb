#!/usr/bin/env python3

# vgm_reader.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import gzip

class VGMReader:
	@staticmethod
	def read(vgm_path):
		vgm = None

		try:
			with gzip.open(vgm_path, 'rb') as file:
				vgm = file.read()
		except gzip.BadGzipFile:
			with open(vgm_path, 'rb') as file:
				vgm = file.read()

		return vgm
