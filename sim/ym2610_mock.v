// ym2610_mock.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

module ym2160_mock #(
	parameter [0:0] ENABLE_ADPCM_A = 1,
	parameter [0:0] ENABLE_ADPCM_B = 1,
	parameter [23:0] A_ADDRESS_START = 24'h000000,
	parameter [23:0] B_ADDRESS_START = 24'h000000
) (
	// 8MHz core clock

	input clk,
	input ic_n,

	// ADPCM-A

	inout [7:0] rad,
	output reg [1:0] ra9_8,
	output reg [3:0] ra23_20,

	output rmpx,
	output roe,

	// ADPCM-B

	inout [7:0] pad,
	output reg [3:0] pa11_8,

	output pmpx,
	output poe,

	// Test

	output reg [23:0] a_read_address,
	output reg [7:0] a_read_data,
	output reg a_read_complete,

	output reg [23:0] p_read_address,
	output reg [7:0] p_read_data,
	output reg p_read_complete
);
	// --- ADPCM-A ---

	// Clock:

	// 8M / 12 = 667KHz
	localparam A_CLK_PRESCALER = 12;

	reg clk_667khz = 0;

	reg [3:0] a_counter = 0;

	always @(posedge clk) begin
		a_counter <= a_counter + 1;

		if (a_counter == (A_CLK_PRESCALER - 1)) begin
			a_counter <= 0;
			clk_667khz <= !clk_667khz;
		end
	end

	// Bus sequence:

	reg [2:0] a_bus_state = 0;

	always @(posedge clk_667khz) begin
		a_bus_state <= a_bus_state + 1;

		if (a_bus_state == 5) begin
			a_bus_state <= 0;
		end
	end

	assign rmpx = (a_bus_state == 1 || a_bus_state == 2) && ENABLE_ADPCM_A;
	assign roe = !(a_bus_state == 4 || a_bus_state == 5) || !ENABLE_ADPCM_A;

	// Address mux:

	reg [23:0] a_address = 0;

	reg [7:0] rad_r;
	assign rad = rad_r;

	always @* begin
		case (a_bus_state)
			0, 1: begin
				rad_r = a_address[7:0];
				ra9_8 = a_address[9:8];
				// Assuming that ra23_20 is not valid yet (not confirmed)
				ra23_20 = 4'hx;
			end
			2, 3: begin
				rad_r = a_address[17:10];
				ra9_8 = a_address[19:18];
				ra23_20 = a_address[23:20];
			end
			4, 5: begin
				rad_r = 8'hzz;
				ra9_8 = a_address[19:18];
				ra23_20 = a_address[23:20];
			end
			default: begin
				rad_r = 8'hzz;
				ra9_8 = 2'hx;
				ra23_20 = 4'hx;
			end
		endcase
	end

	// ---

	always @(posedge clk_667khz) begin
		if (!ic_n) begin
			a_address <= A_ADDRESS_START;
		end else begin
			a_read_address <= 24'hxxxxxx;
			a_read_data <= 8'hxx;
			a_read_complete <= 0;

			if (a_bus_state == 5) begin
				a_address <= a_address + 1;

				a_read_address <= a_address;
				a_read_data <= rad;
				a_read_complete <= 1;
			end
		end
	end

	// --- ADPCM-B ---

	// Clock:

	// 8M / 2 = 4MHz
	reg clk_4m = 0;

	always @(posedge clk) begin
		clk_4m <= !clk_4m;
	end

	// Bus sequence:

	reg [2:0] b_bus_state = 0;

	always @(posedge clk_4m) begin
		b_bus_state <= b_bus_state + 1;

		if (b_bus_state == 5) begin
			b_bus_state <= 0;
		end
	end

	assign pmpx = (b_bus_state == 1 || b_bus_state == 2) && p_read_needed;
	assign poe = !(b_bus_state == 4 || b_bus_state == 5) || !p_read_needed;

	// Address mux:

	reg [23:0] p_address = B_ADDRESS_START;

	reg [7:0] pad_r;
	assign pad = pad_r;

	always @* begin
		case (b_bus_state)
			0, 1: begin
				pad_r = p_address[7:0];
				pa11_8 = p_address[11:8];
			end
			2, 3: begin
				pad_r = p_address[19:12];
				pa11_8 = p_address[23:20];
			end
			4, 5: begin
				pad_r = 8'hzz;
				pa11_8 = p_address[23:20];
			end
			default: begin
				pad_r = 8'hzz;
				pa11_8 = 4'hx;
			end
		endcase
	end

	// Apparently real 2610 only performs 1 read every other ADPCM-A read at most
	// That is 12 bus cycles apart

	reg [2:0] p_read_interval = 0;
	wire p_read_needed = (p_read_interval == 0) && ENABLE_ADPCM_B;

	always @(posedge clk_4m) begin
		p_read_address <= 24'hxxxxxx;
		p_read_data <= 8'hxx;
		p_read_complete <= 0;

		if (b_bus_state == 5) begin
			p_address <= p_address + 1;

			p_read_address <= p_address;
			p_read_data <= pad;
			p_read_complete <= p_read_needed;

			p_read_interval <= p_read_interval + 1;
			if (p_read_interval == 6) begin
				p_read_interval <= 0;
			end
		end
	end

endmodule
