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
		wb_rdata <= (wb_cyc && !wb_we) ? {30'b0, btn_debounced} : 32'b0;
	end

	// --- Buttons ---

	wire [1:0] btn_debounced;

	debouncer #(
		.BTN_COUNT(2)
	) debouncer (
		.clk(clk),
		.reset(reset),

		.btn(btn),

		.level(btn_debounced)
	);

endmodule
