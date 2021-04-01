#!/usr/bin/env python3

# delta_t_encoder.py
#
# This is just a Python port of this codec here:
# https://github.com/superjohan/adpcmb/blob/master/adpcmb.c

# Note this doesn't zero pad automatically

class DeltaTEncoder:
	STEP_SIZES = [
		57, 57, 57, 57, 77, 102, 128, 153,
		57, 57, 57, 57, 77, 102, 128, 153
	]

	def encode(self, pcm_s16):
		encoded = bytearray()

		xn = 0
		step_size = 127
		flag = 0
		adpcm_pack = 0

		for sample in pcm_s16:
			dn = sample - xn
			i = (abs(dn) << 16) // (step_size << 14)
			if i > 7:
				i = 7
			adpcm = i & 0xff

			i = (adpcm * 2 + 1) * step_size // 8

			if dn < 0:
				adpcm |= 0x8
				xn -= i
			else:
				xn += i

			step_size = (DeltaTEncoder.STEP_SIZES[adpcm] * step_size) // 64

			if step_size < 127:
				step_size = 127
			elif step_size > 24576:
				step_size = 24576

			if flag == 0:
				adpcm_pack = adpcm << 4
				flag = 1
			else:
				adpcm_pack |= adpcm
				encoded.append(adpcm_pack)
				flag = 0

		return encoded
