// vgm_timer.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-W-2.0

// This timer ticks at approx. 44100Hz
// No IRQ triggers as we're trying to stick to just polling here

`default_nettype none

module vgm_timer(
	input clk,
	input reset,

	input [31:0] wb_wdata,
	input wb_we,
	input wb_cyc,
	output reg [31:0] wb_rdata,
	output reg wb_ack
);
	// --- Wishbone ---

	always @(posedge clk) begin
		wb_ack <= wb_cyc && !wb_ack;
	end

	always @(posedge clk) begin
		if (wb_cyc && !wb_we) begin
			wb_rdata <= {31'b0, counter[16]};
		end else begin
			wb_rdata <= 32'b0;
		end
	end

	// --- 44.1KHz timer ---

	reg [16:0] counter;

	localparam [23:0] FRACTION_44100HZ = 24'd30828;
	reg [24:0] fraction_acc;

	always @(posedge clk) begin
		if (wb_cyc && wb_we) begin
			counter <= {1'b0, wb_wdata[15:0]};
			fraction_acc <= 0;
		end else begin
			if (fraction_acc[24] && !counter[16]) begin
				counter <= counter - 1;
			end

			fraction_acc <= fraction_acc + {1'b0, FRACTION_44100HZ};

		end

		if (fraction_acc[24]) begin
			fraction_acc[24] <= 0;
		end
	end

endmodule
