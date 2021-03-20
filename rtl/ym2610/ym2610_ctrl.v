// ym2610_ctrl.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

`default_nettype none

module ym2610_ctrl(
	input clk,
	input reset,

	// 8MHz clk enable events

	input ym_clk_rose,
	input ym_clk_fell,

	// Wishbone interface

	input [2:0] wb_addr,
	input [7:0] wb_wdata,
	input wb_we,
	input wb_cyc,

	output reg [31:0] wb_rdata,
	output reg wb_ack,

	// Shift control

	output ctrl_shift_out,
	output ctrl_shift_load
);
	// --- Wishbone ---

	// Address map:

	// 00-03: YM2610 port A/B writing (address/data)
	// 04-07: YM2610 reset control

	always @(posedge clk) begin
		wb_ack <= wb_cyc && !fifo_full && !wb_ack;
		wb_rdata <= (wb_cyc && !wb_we) ? {31'b0, fifo_full} : 32'b0;
	end

	// --- Write-command FIFO ---

	// Writes shouldn't block the CPU because:
	// - The YM2610 itself has a very long delay between writes (83 cycles @ 8MHz)
	// - The shifters here take a while to work
	//
	// Optimizing the shifter implementation isn't useful because the 2610 the bottleneck

	// FIXME: 12bits where an extra bit flags that this is a reset
	wire [10:0] fifo_wdata = {wb_addr[2:0], wb_wdata[7:0]};
	wire fifo_we = wb_cyc && wb_we && !wb_ack && !fifo_full;
	wire fifo_full;

	wire [7:0] fifo_ym_data;
	wire [1:0] fifo_ym_address;
	wire fifo_ym_reset;

	wire fifo_read_en = !busy && !fifo_empty;
	wire fifo_empty;

	fifo_sync_ram #(
		.DEPTH(512),
		.WIDTH(11)
	) ym_ctrl_fifo (
		.clk(clk),
		.rst(reset),

		.wr_data(fifo_wdata),
		.wr_ena(fifo_we),
		.wr_full(fifo_full),

		.rd_data({fifo_ym_reset, fifo_ym_address, fifo_ym_data}),
		.rd_ena(fifo_read_en),
		.rd_empty(fifo_empty)
	);

	wire ym_ctrl_write_en = fifo_read_en && !fifo_ym_reset;
	wire ym_reset_en = fifo_read_en && fifo_ym_reset;

	// --- YM2610 control ---

	// Write handling:

	// 17 after addr
	// 83 after data write
	localparam WRITE_DELAY = 83;

	reg [$clog2(WRITE_DELAY):0] write_delay_counter;
	wire ym_data_busy = (write_delay_counter > 0);

	always @(posedge clk) begin
		if (reset) begin
			write_delay_counter <= 0;
		end else begin
			if (ym_data_written) begin
				write_delay_counter <= WRITE_DELAY;
			end else if (ym_data_busy && ym_clk_rose) begin
				write_delay_counter <= write_delay_counter - 1;
			end
		end
	end

	// Shift register write FSM:

	localparam [2:0]
		STATE_ADDRESS_SETUP = 0,
		STATE_REG_WRITE = 1,
		STATE_REG_WRITE_HOLD = 2,
		STATE_WRITING = 3,
		STATE_IDLE = 4;

	wire busy = (state != STATE_IDLE);

	reg [2:0] state;
	reg [2:0] next_state;

	reg ym_data_written;
	reg shift_needs_load;

	reg [7:0] din_write;
	reg [1:0] address_write;

	reg [7:0] reg_address_pending_write [0:1];
	reg [7:0] reg_data_pending_write;

	reg [1:0] address_shift;
	reg [7:0] din_shift;
	reg cs_n_shift;
	reg wr_n_shift;
	reg ic_n_shift;

	always @(posedge clk) begin
		if (reset) begin
			ic_n_shift <= 0;
			cs_n_shift <= 1;
			wr_n_shift <= 1;

			address_write <= 0;
			din_write <= 0;

			ym_data_written <= 0;

			shift_needs_load <= 1;
			state <= STATE_WRITING;
			next_state <= STATE_IDLE;
		end else begin
			shift_needs_load <= 0;
			ym_data_written <= 0;

			case (state)
				STATE_IDLE: begin
					if (ym_ctrl_write_en) begin
						if (fifo_ym_address[0]) begin
							address_write <= {fifo_ym_address[1], 1'b0};
							din_write <= reg_address_pending_write[fifo_ym_address[1]];
							reg_data_pending_write <= fifo_ym_data;

							state <= STATE_ADDRESS_SETUP;
						end else begin
							reg_address_pending_write[fifo_ym_address[1]] <= fifo_ym_data;
						end
					end else if (ym_reset_en) begin
						// Unconditionally clear reset, could add support to reset again if needed
						ic_n_shift <= 1;
						cs_n_shift <= 1;
						wr_n_shift <= 1;

						shift_needs_load <= 1;
						state <= STATE_WRITING;
						next_state <= STATE_IDLE;
					end
				end
				STATE_ADDRESS_SETUP: begin
					address_shift <= address_write;
					cs_n_shift <= 1;
					wr_n_shift <= 1;
					din_shift <= din_write;

					shift_needs_load <= 1;
					state <= STATE_WRITING;
					next_state <= STATE_REG_WRITE;
				end
				STATE_REG_WRITE: begin
					address_shift <= address_write;
					cs_n_shift <= 0;
					wr_n_shift <= 0;
					din_shift <= din_write;

					// Can't start the write until write-delay is satisfied
					if (!ym_data_busy) begin
						shift_needs_load <= 1;
						state <= STATE_WRITING;
						next_state <= STATE_REG_WRITE_HOLD;
					end
				end
				STATE_REG_WRITE_HOLD: begin
					// Needed to start the write-delay-counter *only* for data writes
					// Address writes are quick enough that no delay is needed
					if (address_write[0]) begin
						ym_data_written <= 1;
					end

					address_shift <= address_write;
					cs_n_shift <= 1;
					wr_n_shift <= 1;
					din_shift <= din_write;

					if (!address_write[0]) begin
						// Reg address will be written, write data next
						address_write[0] <= 1;
						din_write <= reg_data_pending_write;

						next_state <= STATE_ADDRESS_SETUP;
					end else begin
						// Reg address and data will be both written
						next_state <= STATE_IDLE;
					end

					shift_needs_load <= 1;
					state <= STATE_WRITING;
				end
				STATE_WRITING: begin
					if (shift_completed) begin
						state <= next_state;
					end
				end
			endcase
		end
	end

	// Output shift register:

	// External shift reg is clocked on posedge
	// Output here is shifted on negedge

	localparam SHIFT_BITS = 13;
	localparam SHIFT_MSB = SHIFT_BITS - 1;

	reg [SHIFT_MSB:0] shift;
	assign ctrl_shift_out = shift[SHIFT_MSB];

	reg [2:0] shift_load_r;
	assign ctrl_shift_load = shift_load_r[2];

	reg [3:0] shift_count;
	reg shift_completed;
	reg shifting;

	reg awaiting_ym_clk_fall;

	wire [SHIFT_MSB:0] shift_preload = {
		ic_n_shift, cs_n_shift, wr_n_shift, address_shift, din_shift
	};

	always @(posedge clk) begin
		if (reset) begin
			shift_completed <= 0;
			shift_load_r <= 0;
			shifting <= 0;

			awaiting_ym_clk_fall <= 0;
		end else begin
			shift_completed <= 0;
			shift_load_r <= shift_load_r << 1;

			if (shift_needs_load) begin
				shift <= shift_preload;
				shift_count <= 0;
				shifting <= 1;
				awaiting_ym_clk_fall <= 1;
			end else if (shifting && awaiting_ym_clk_fall) begin
				if (ym_clk_fell) begin
					awaiting_ym_clk_fall <= 0;
				end
			end else if (shifting && ym_clk_rose) begin
				shift <= shift << 1;

				if (shift_count == SHIFT_MSB) begin
					shift_load_r <= 3'b111;

					shift_completed <= 1;
					shifting <= 0;
				end

				shift_count <= shift_count + 1;
			end
		end
	end

endmodule
