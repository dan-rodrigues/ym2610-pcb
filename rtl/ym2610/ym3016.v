// ym3016.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Despite the name and the same "floating point DAC" references as YM3012, it doesn't accept floats as input.
// Inputs are (un)signed 16bit depending on the FORM input.
//
// The YM3012 before accepts inputs of 10bit mantissa + 3bit exponent.
// Instead, the YM3016 converts its 16bit inputs to the same 10bit mantissa + 3bit exponent internally.
// It tries to minimize the exponent to maximize precision according to the absolute value of the input.
//
// This implementation just outputs the 16bit signed samples exactly as they are received.
// An optional extra could be to alter the lower bits of the sample to match the loss of precision from using
// the higher exponents. This would sacrifice accuracy to give it a closer sound to a real YM3016.

module ym3016(
	input clk,
	input clk_en,

	input ic_n,

	input form,

	input so,
	input sh1,
	input sh2,

	// Debug output

	output reg [15:0] dbg_shift_left,
	output reg [15:0] dbg_shift_right,

	// Audio output

	output reg signed [15:0] left, 
	output reg signed [15:0] right, 
	output output_valid
);
	assign output_valid = clk_en && ic_n && sh2_fell;

	reg [15:0] shift_in;

	reg sh1_r, sh2_r;
	wire sh1_fell = !sh1 && sh1_r;
	wire sh2_fell = !sh2 && sh2_r;

	always @(posedge clk) begin
		if (clk_en) begin
			sh1_r <= sh1;
			sh2_r <= sh2;
		end
	end

	wire input_msb = form ? !shift_in[15] : shift_in[15];
	wire [15:0] input_signed = {input_msb, shift_in[14:0]};

	always @(posedge clk) begin
		if (clk_en) begin
			if (!ic_n) begin
				left <= 0;
				right <= 0;
			end else if (sh1_fell) begin
				left <= input_signed;
				dbg_shift_left <= shift_in;
			end else if (sh2_fell) begin
				right <= input_signed;
				dbg_shift_right <= shift_in;
			end
		end
	end

	always @(posedge clk) begin
		if (clk_en) begin
			if (!ic_n) begin
				shift_in <= 0;
			end else begin
				shift_in <= {so, shift_in[15:1]};
			end
		end
	end

endmodule
