#!/usr/bin/env python3

# vgm_convert.py
#
# Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
#
# SPDX-License-Identifier: MIT

import sys

from vgm_preprocess import VGMPreprocessor
from vgm_preprocess import PCMType
from vgm_reader import VGMReader

if len(sys.argv) != 3:
	print("Usage: vgm_convert.py <input_path> <output_path>")
	sys.exit(1)

input_path = sys.argv[1]
output_path = sys.argv[2]

# Read and convert input

vgm = VGMReader.read(input_path)
processor = VGMPreprocessor()
processed_vgm = processor.preprocess(vgm, rewrite_pcm=True, byteswap_pcm=False)

# Write converted output

with open(output_path, 'wb') as output_file:
	output_file.write(processed_vgm.data)
