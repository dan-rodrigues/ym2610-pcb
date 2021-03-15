// buttons.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-W-2.0

`default_nettype none

module buttons(
	input clk,
	input reset,

	input wb_we,
	input wb_cyc,
	output reg [31:0] wb_rdata,
	output reg wb_ack,

	input [1:0] btn
);
	// --- Wishbone ---

	always @(posedge clk) begin
		wb_ack <= wb_cyc && !wb_ack;
		wb_rdata <= (wb_cyc && !wb_we) ? {30'b0, btn_r} : 32'b0;
	end

	// --- Buttons ---

	// Not bothering to do proper debouncing here since it's infrequently polled by CPU

	reg [1:0] btn_r;

	always @(posedge clk) begin
		btn_r <= btn;
	end

endmodule
