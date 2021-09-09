// spi_mem.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

`default_nettype none

module spi_mem #(
	parameter [7:0] READ_CMD_0 = 8'h03,
	parameter [7:0] READ_CMD_1 = 8'heb,
	parameter [7:0] WRITE_CMD_1 = 8'h38,

	parameter [0:0] READ_CMD_1_QUAD = READ_CMD_1 == 8'heb,
	parameter [0:0] WRITE_CMD_1_QUAD = WRITE_CMD_1 == 8'h38,

	parameter [0:0] CMD_0_QPI = 1'b0,
	parameter [0:0] CMD_1_QPI = 1'b1
) (
	input clk,
	input clk_2x,
	input reset,

	// Read / Write:

	input [23:0] mem_addr,
	input mem_valid,
	input mem_we,
	input mem_select,
	input [1:0] mem_length,
	input [31:0] mem_wdata,
	output reg [31:0] mem_rdata,
	output reg mem_ready,

	// Wishbone

	input [0:0] wb_addr,
	input [31:0] wb_wdata,
	input wb_we,
	input wb_cyc,
	output [31:0] wb_rdata,
	output reg wb_ack,

	// SPI (flash / PSRAM)

	output spi_clk,
	output [1:0] spi_csn,
	inout [3:0] spi_io
);
	// --- Wishbone ---

	assign wb_rdata = 0;

	// Wishbone writes:

	reg wb_cmd_pending;
	reg [7:0] wb_cmd;
	reg wb_cmd_active;

	wire wb_mem_select = wb_addr[0];

	always @(posedge clk) begin
		if (reset) begin
			wb_cmd_pending <= 0;
			wb_cmd_active <= 0;
			wb_ack <= 0;
		end else begin
			wb_ack <= 0;

			if (state == S_WB_CMD) begin
				wb_cmd_pending <= 0;

				if (state_changing_to(S_IDLE)) begin
					wb_cmd_active <= 0;
					wb_ack <= 1;
				end
			end else if (wb_cyc && wb_we && !wb_ack) begin
				wb_cmd_pending <= 1;
				wb_cmd_active <= 1;
				wb_cmd <= wb_wdata[7:0];
			end
		end
	end

	// Memory R/W:

	reg mem_cmd_pending;
	reg mem_cmd_active;

	always @(posedge clk) begin
		if (reset) begin
			mem_cmd_pending <= 0;
			mem_cmd_active <= 0;
		end else begin
			if (state == S_CMD) begin
				mem_cmd_pending <= 0;
			end else if (state == S_IDLE && mem_valid && !mem_ready) begin
				mem_cmd_pending <= 1;
				mem_cmd_active <= 1;
			end

			if (state_changing_to(S_IDLE)) begin
				mem_cmd_active <= 0;
			end
		end
	end

	reg [1:0] mem_length_r;

	always @(posedge clk) begin
		mem_length_r <= mem_length;
	end

	// --- RW handling ---

	wire spi_active = mem_cmd_active || wb_cmd_active;

	// FSM:

	localparam [3:0]
		S_IDLE = 0,
		S_CMD = 1,
		S_WB_CMD = 2,
		S_ADDR = 3,
		S_DUMMY = 4,
		S_DATA = 5;

	reg [3:0] state;
	reg [3:0] state_nx;

	always @(posedge clk) begin
		if (reset) begin
			state <= S_IDLE;
		end else begin
			state <= state_nx;
		end
	end

	// FSM update:

	always @* begin
		state_nx = state;

		// It's possible for accesses to be interrupted which will deassert mem_valid
		if (mem_cmd_active && !mem_valid) begin
			state_nx = S_IDLE;
		end else begin
			case (state)
				S_IDLE: begin
					if (mem_cmd_pending) begin
						state_nx = S_CMD;
					end else if (wb_cmd_pending) begin
						state_nx = S_WB_CMD;
					end
				end
				S_WB_CMD: begin
					if (wb_cmd_shift_done) begin
						state_nx = S_IDLE;
					end
				end
				S_CMD: begin
					if (cmd_shift_done) begin
						state_nx = S_ADDR;
					end
				end
				S_ADDR: begin
					if (address_shift_done) begin
						state_nx = latency > 0 ? S_DUMMY : S_DATA;
					end
				end
				S_DUMMY: begin
					if (latency_counter == 0) begin
						state_nx = S_DATA;
					end
				end
				S_DATA: begin
					if (data_shift_done) begin
						state_nx = S_IDLE;
					end
				end
			endcase
		end
	end

	// Mem:

	always @(posedge clk) begin
		if (reset) begin
			mem_ready <= 0;
		end else begin
			mem_ready <= 0;

			if (state == S_DATA && state_changing_to(S_IDLE)) begin
				if (quad_data_output) begin
					mem_rdata[31:24] <= {
						shift_in_3[5], shift_in_2[5], shift_in[5], shift_in_0[5],
						shift_in_3[4], shift_in_2[4], shift_in[4], shift_in_0[4]
					};
					mem_rdata[23:16] <= {
						shift_in_3[3], shift_in_2[3], shift_in[3], shift_in_0[3],
						shift_in_3[2], shift_in_2[2], shift_in[2], shift_in_0[2]
					};
					mem_rdata[15:8] <= {
						shift_in_3[1], shift_in_2[1], shift_in[1], shift_in_0[1],
						shift_in_3[0], shift_in_2[0], shift_in[0], shift_in_0[0]
					};
					// Use shifter intput directly to save 1 cycle
					mem_rdata[7:0] <= {
						spi_io_in[3][1], spi_io_in[2][1], spi_io_in[1][1], spi_io_in[0][1],
						spi_io_in[3][0], spi_io_in[2][0], spi_io_in[1][0], spi_io_in[0][0]
					};
				end else begin
					mem_rdata <= {shift_in[7:0], shift_in[15:8], shift_in[23:16], shift_in[31:24]};
				end

				mem_ready <= 1;
			end
		end
	end

	// CMD selection:

	reg [7:0] cmd;

	wire [7:0] read_cmd = selection_source ? READ_CMD_1 : READ_CMD_0;
	wire [7:0] write_cmd = WRITE_CMD_1;

	always @(posedge clk) begin
		cmd <= mem_we ? write_cmd : read_cmd;
	end

	// Latency selection:

	reg [2:0] latency;

	always @* begin
		latency = 0;

		if (quad_data_output && !mem_we) begin
			latency = 2;
		end
	end

	reg [2:0] latency_counter;

	always @(posedge clk) begin
		latency_counter <= latency_counter - 1;

		if (state_changing_to(S_DUMMY)) begin
			latency_counter <= latency;
		end
	end

	// Shift control:

	reg quad_address_output;
	reg quad_data_output;
	reg quad_cmd_output;

	always @(posedge clk) begin
		quad_cmd_output <= 0;
		quad_address_output <= 0;
		quad_data_output <= 0;

		if (CMD_1_QPI && (selection_source == 1'b1)) begin
			quad_cmd_output <= 1;
		end

		if (WRITE_CMD_1_QUAD && (selection_source == 1'b1) && mem_we) begin
			quad_address_output <= 1;
			quad_data_output <= 1;
		end

		if (READ_CMD_1_QUAD && (selection_source == 1'b1) && !mem_we) begin
			quad_address_output <= 1;
			quad_data_output <= 1;
		end
	end

	// Shifter:

	// IO0:
	reg [31:0] shift_out;
	// IO1:
	reg [31:0] shift_in;

	// Additional for quad IO transfer
	reg [7:0] shift_out_1;
	reg [7:0] shift_out_2;
	reg [7:0] shift_out_3;

	reg [7:0] shift_in_0;
	reg [7:0] shift_in_2;
	reg [7:0] shift_in_3;

	always @(posedge clk) begin
		if (reset) begin
			shift_out <= 0;
			shift_in <= 0;
		end else begin
			shift_out <= shift_out << 2;
			shift_in <= {shift_in[29:0], spi_io_in[1][1:0]};

			shift_out_1 <= shift_out_1 << 2;
			shift_out_2 <= shift_out_2 << 2;
			shift_out_3 <= shift_out_3 << 2;

			shift_in_0 <= {shift_in_0[5:0], spi_io_in[0][1:0]};
			shift_in_2 <= {shift_in_2[5:0], spi_io_in[2][1:0]};
			shift_in_3 <= {shift_in_3[5:0], spi_io_in[3][1:0]};

			case (state)
				S_IDLE:
					if (state_changing_to(S_CMD)) begin
						if (quad_cmd_output) begin
							shift_out[31:30] <= {
								cmd[4], cmd[0]
							};
							shift_out_1[7:6] <= {
								cmd[5], cmd[1]
							};
							shift_out_2[7:6] <= {
								cmd[6], cmd[2]
							};
							shift_out_3[7:6] <= {
								cmd[7], cmd[3]
							};
						end else begin
							shift_out[31:24] <= cmd;
						end
					end else if (state_changing_to(S_WB_CMD)) begin
						shift_out[31:24] <= wb_cmd;
					end
				S_CMD: begin
					if (state_changing_to(S_ADDR)) begin
						if (quad_address_output) begin
							shift_out[31:26] <= {
								mem_addr[20], mem_addr[16], mem_addr[12],
								mem_addr[8], mem_addr[4], mem_addr[0]
							};
							shift_out_1[7:2] <= {
								mem_addr[21], mem_addr[17], mem_addr[13],
								mem_addr[9], mem_addr[5], mem_addr[1]
							};
							shift_out_2[7:2] <= {
								mem_addr[22], mem_addr[18], mem_addr[14],
								mem_addr[10], mem_addr[6], mem_addr[2]
							};
							shift_out_3[7:2] <= {
								mem_addr[23], mem_addr[19], mem_addr[15],
								mem_addr[11], mem_addr[7], mem_addr[3]
							};
						end else begin
							shift_out[31:8] <= mem_addr;
						end
					end
				end
				S_WB_CMD: begin
					// ...
				end
				S_ADDR: begin
					if (state_changing_to(S_DATA)) begin
						if (quad_data_output) begin
							shift_out[31:24] <= {
								mem_wdata[28], mem_wdata[24],
								mem_wdata[20], mem_wdata[16],
								mem_wdata[12], mem_wdata[8],
								mem_wdata[4], mem_wdata[0]
							};
							shift_out_1[7:0] <= {
								mem_wdata[29], mem_wdata[25],
								mem_wdata[21], mem_wdata[17],
								mem_wdata[13], mem_wdata[9],
								mem_wdata[5], mem_wdata[1]
							};
							shift_out_2[7:0] <= {
								mem_wdata[30], mem_wdata[26],
								mem_wdata[22], mem_wdata[18],
								mem_wdata[14], mem_wdata[10],
								mem_wdata[6], mem_wdata[2]
							};
							shift_out_3[7:0] <= {
								mem_wdata[31], mem_wdata[27],
								mem_wdata[23], mem_wdata[19],
								mem_wdata[15], mem_wdata[11],
								mem_wdata[7], mem_wdata[3]
							};
						end else begin
							shift_out <= {mem_wdata[7:0], mem_wdata[15:8], mem_wdata[23:16], mem_wdata[31:24]};
						end
					end
				end
			endcase
		end
	end

	// Shift count selection:

	reg [5:0] shift_count;

	reg cmd_shift_done;

	wire wb_cmd_shift_done = (shift_count == 3);

	reg address_shift_done;
	reg data_shift_done;

	always @* begin
		cmd_shift_done = shift_count == (4 - 1);
		if (quad_cmd_output) begin
			cmd_shift_done = shift_count == (1 - 1);
		end

		address_shift_done = shift_count == 11;
		if (quad_address_output) begin
			address_shift_done = shift_count == 2;
		end

		data_shift_done = (shift_count == ((mem_length_r + 1) * 4) + 1);
		if (quad_data_output) begin
			// No "+1" here since shifter input is used on last cycle of read
			data_shift_done = (shift_count == (mem_length_r + 1 + (mem_we ? 1 : 0)));
		end
	end

	always @(posedge clk) begin
		if (reset) begin
			shift_count <= 0;
		end else begin
			if (
				state_changing_to(S_CMD) ||
				state_changing_to(S_WB_CMD) ||
				state_changing_to(S_ADDR) ||
				state_changing_to(S_DATA))
			begin
				shift_count <= 0;
			end else if (state != S_IDLE) begin
				shift_count <= shift_count + 1;
			end else begin
				shift_count <= 0;
			end
		end
	end

	// Clock enable:

	reg [1:0] spi_io_nx [0:3];
	reg [3:0] spi_io_en_nx;

	reg [7:0] spi_clk_counter;

	wire spi_clk_en = !spi_clk_counter[7] && spi_active;

	always @(posedge clk) begin
		if (reset) begin
			spi_clk_counter <= 0;
		end else begin
			if (!spi_clk_counter[7]) begin
				spi_clk_counter <= spi_clk_counter - 1;
			end

			if (state_changing_to(S_CMD)) begin
				// (break this up as needed if timing is an issue)

				spi_clk_counter <= (
					(quad_cmd_output ? 1 : 4) +
					(quad_address_output ? 3 : 12) +
					(latency > 0 ? latency + 1 : 0) +
					(quad_data_output ? ((mem_length_r + 1) * 1) : ((mem_length_r + 1) * 4))
				);
			end else if (state_changing_to(S_WB_CMD)) begin
				spi_clk_counter <= (4 - 1);
			end
		end
	end

	// Device selection:

	reg [1:0] spi_decoded_csn;
	wire selection_source = wb_cyc ? wb_mem_select : mem_select;

	always @* begin
		spi_decoded_csn = selection_source ? 2'b01 : 2'b10;
	end

	// Note these are input to an *unregistered* SB_IO below

	reg [1:0] spi_csn_nx;

	always @(posedge clk) begin
		if (reset) begin
			spi_csn_nx <= 2'b11;
		end else if (state_nx != S_IDLE || state_changing_to(S_IDLE))begin
			spi_csn_nx <= spi_decoded_csn;
		end else begin
			spi_csn_nx <= 2'b11;
		end
	end

	always @* begin
		if (reset) begin
			spi_io_en_nx = 4'b0000;
		end else begin
			case (state)
				S_IDLE:
					spi_io_en_nx = 4'b0000;
				S_CMD:
					spi_io_en_nx = quad_cmd_output ? 4'b1111 : 4'b0001;
				S_WB_CMD:
					spi_io_en_nx = 4'b0001;
				S_ADDR: begin
					if (quad_address_output) begin
						spi_io_en_nx = 4'b1111;
					end else begin
						spi_io_en_nx = 4'b0001;
					end
				end
				S_DATA: begin
					if (quad_data_output) begin
						spi_io_en_nx = mem_we ? 4'b1111 : 4'b0000;
					end else begin
						spi_io_en_nx = mem_we ? 4'b0001 : 4'b0000;
					end
				end
				default:
					spi_io_en_nx = 4'b0000;
			endcase
		end

		spi_io_nx[0] = shift_out[31:30];
		spi_io_nx[1] = shift_out_1[7:6];
		spi_io_nx[2] = shift_out_2[7:6];
		spi_io_nx[3] = shift_out_3[7:6];
	end

	// --- Convenience functions ---

	function [0:0] state_changed_to;
		input [3:0] new_state;

		state_changed_to = !state_previous_mask[new_state] && (state == new_state);
	endfunction

	function [0:0] state_changing_to;
		input [3:0] new_state;

		state_changing_to = (state_nx == new_state) && (state != new_state);
	endfunction

	reg [15:0] state_previous_mask;

	integer state_index;
	always @(posedge clk) begin
		for (state_index = 0; state_index < 16; state_index = state_index + 1) begin
			state_previous_mask[state_index[3:0]] <= (state == state_index[3:0]);
		end
	end

	// --- IO regs ---

	// Bit dirty, this is used to get the OUTPUT_ENABLE on the falling edge of 24M clk

	reg [3:0] spi_io_en_24m_n;

	always @(negedge clk) begin
		spi_io_en_24m_n <= spi_io_en_nx;
	end

	// CLK
	
	reg spi_clk_en_2x;

	always @(negedge clk_2x) begin
		spi_clk_en_2x <= spi_clk_en;
	end

	SB_IO #(
		.PIN_TYPE(6'b010000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) spi_clk_sbio (
		.OUTPUT_CLK(clk_2x),
		.INPUT_CLK(clk_2x),
		.CLOCK_ENABLE(1'b1),

		.PACKAGE_PIN(spi_clk),
		.D_OUT_0(1'b0),
		.D_OUT_1(spi_clk_en_2x)
	);

	// CS

	// This needs to use the 48M clk due to IO tile restrictions, would be 24M otherwise
	// These SB_IOs are unregistered because of this, using 24M clk FFs above as input

	SB_IO #(
		.PIN_TYPE(6'b011000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) spi_csn_sbio [1:0] (
		// These aren't used but here to satisfy the IO tile restriction
		.OUTPUT_CLK(clk_2x),
		.INPUT_CLK(clk_2x),
		.CLOCK_ENABLE(1'b1),

		.PACKAGE_PIN(spi_csn),
		.D_OUT_0(spi_csn_nx)
	);

	// Data

	reg [1:0] spi_io_in [0:3];

	always @(negedge clk_2x) begin
		if (clk) begin
			spi_io_in[0][1] <= spi_io_in_2x[0];
			spi_io_in[1][1] <= spi_io_in_2x[1];
			spi_io_in[2][1] <= spi_io_in_2x[2];
			spi_io_in[3][1] <= spi_io_in_2x[3];
		end else begin
			spi_io_in[0][0] <= spi_io_in_2x[0];
			spi_io_in[1][0] <= spi_io_in_2x[1];
			spi_io_in[2][0] <= spi_io_in_2x[2];
			spi_io_in[3][0] <= spi_io_in_2x[3];
		end
	end

	wire [3:0] spi_io_in_2x;

	// Mind the unregistered OUTPUT_ENABLE in this SB_IO, advance it if needed

	SB_IO #(
		.PIN_TYPE(6'b100000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) spi_io_sbio [3:0] (
		.OUTPUT_CLK(clk),
		.INPUT_CLK(clk_2x),
		.CLOCK_ENABLE(1'b1),

		.PACKAGE_PIN(spi_io),
		.OUTPUT_ENABLE(spi_io_en_24m_n),

		.D_OUT_0({spi_io_nx[3][0], spi_io_nx[2][0], spi_io_nx[1][0], spi_io_nx[0][0]}),
		.D_OUT_1({spi_io_nx[3][1], spi_io_nx[2][1], spi_io_nx[1][1], spi_io_nx[0][1]}),

		// Only falling edge of clk_2x is to be used for input since spi_clk is phase inverted
		// Memory would've output the data half a cycle earlier
		.D_IN_0(),
		.D_IN_1({spi_io_in_2x[3], spi_io_in_2x[2], spi_io_in_2x[1], spi_io_in_2x[0]})
	);

endmodule
