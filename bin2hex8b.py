#!/usr/bin/env python3

import struct
import sys


def main(argv0, in_name, out_name):
	with open(in_name, 'rb') as in_fh, open(out_name, 'w') as out_fh:
		padding = 0xa0000
		for _ in range(padding):
			out_fh.write('00\n')

		while True:
			b = in_fh.read(1)
			if len(b) < 1:
				break
			out_fh.write('%02x\n' % b[0])

if __name__ == '__main__':
	main(*sys.argv)
