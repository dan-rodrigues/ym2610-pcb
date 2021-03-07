// ym2160_pcm_mux.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

// This is a model of the discrete logic and routing on the PCB

module ym2160_pcm_mux(
	// FPGA IO

	inout [3:0] ym_io,
	input [2:0] mux_sel,
	input mux_oe_n,
	input pcm_load,
	output rmpx_out,
	output pmpx_out,

	// YM2610 IO

	// A

	inout [7:0] rad,
	input roe_n,
	input ra8, ra9,
	input ra20, ra21, ra22, ra23,
	input rmpx,

	// B

	inout [7:0] pad,
	input poe_n,
	input pa8, pa9, pa10, pa11,
	input pmpx
);
	// Passthrough (74LVC244 on board):

	assign rmpx_out = rmpx;
	assign pmpx_out = pmpx;

	// Mux:

	reg [3:0] ym_io_out;

	// ym_io output:

	assign ym_io = !mux_oe_n ? ym_io_out : 4'bzzzz;

	always @* begin
		case (mux_sel)
			3'b000:
				ym_io_out = rad[3:0];
			3'b001:
				ym_io_out = {ra23, ra22, ra21, ra20};
			3'b010:
				ym_io_out = pad[3:0];
			3'b011:
				ym_io_out = {pa11, pa10, pa9, pa8};
			3'b100:
				ym_io_out = rad[7:4];
			3'b101:
				ym_io_out = {2'bxx, ra9, ra8};
			3'b110:
				ym_io_out = pad[7:4];
		endcase
	end

	// PCM loading:

	assign rad = !roe_n ? pcm_r : 8'hzz;
	assign pad = !poe_n ? pcm_p : 8'hzz;

	reg [7:0] pcm_r;
	reg [7:0] pcm_p;
	reg [3:0] pcm_nybble;

	always @* begin
		if (mux_sel[0]) begin
			pcm_nybble = ym_io;
		end

		if (mux_sel[1] && pcm_load) begin
			pcm_r[3:0] = pcm_nybble;
			pcm_r[7:4] = ym_io;
		end

		if (mux_sel[2] && pcm_load) begin
			pcm_p[3:0] = pcm_nybble;
			pcm_p[7:4] = ym_io;
		end
	end

endmodule
