// adpcm_b_reader.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

module adpcm_b_reader #(
	parameter [23:0] ADDRESS_OFFSET = 24'b0
) (
	input clk,
	input reset,

	// Status

	output reg [15:0] pmpx_rise_count,
	output reg [15:0] pmpx_fall_count,
	input pmpx_count_reset,
	
	// PCM Mux

	output reg pcm_mux_needed,
	output reg read_active,

	input pmpx_rose,
	input pmpx_fell,

	input [3:0] ym_io_in,

	output [3:0] ym_io_out,
	output ym_io_en,
	output [2:0] mux_sel,
	output mux_oe_n,
	output pcm_load,

	// PCM data reading

	input [7:0] pcm_mem_rdata,
	input pcm_mem_ready,

	output [23:0] pcm_mem_addr,
	output reg pcm_mem_valid,

	// Debugging

	output reg [23:0] dbg_previous_addr,
	output reg [7:0] dbg_previous_data
);
	// --- IO ---

	reg [3:0] ym_io_out_nx;
	reg [2:0] mux_sel_nx;
	reg pcm_load_nx;
	reg ym_io_en_nx;
	reg mux_oe_n_nx;

	assign ym_io_out = ym_io_out_nx;
	assign mux_sel = mux_sel_nx;
	assign pcm_load = pcm_load_nx;
	assign ym_io_en = ym_io_en_nx;
	assign mux_oe_n = mux_oe_n_nx;

	// --- FSM ---

	localparam [1:0]
		S_IDLE = 0,
		S_ADDRESS_READING = 1,
		S_PCM_READING = 2,
		S_PCM_WRITING = 3;

	reg [1:0] state;
	reg [1:0] state_nx;

	always @(posedge clk) begin
		state <= state_nx;
	end

	always @* begin
		if (reset) begin
			state_nx = S_IDLE;
		end else begin
			state_nx = state;

			case (state)
				S_IDLE: begin
					if (pmpx_rose) begin
						state_nx = S_ADDRESS_READING;
					end
				end
				S_ADDRESS_READING: begin
					if (address_read_complete) begin
						state_nx = S_PCM_READING;
					end
				end
				S_PCM_READING: begin
					if (pcm_mem_ready) begin
						state_nx = S_PCM_WRITING;
					end
				end
				S_PCM_WRITING: begin
					if (write_complete) begin
						state_nx = S_IDLE;
					end
				end
			endcase
		end
	end

	// --- PCM mux control ---

	reg [4:0] read_state;

	always @* begin
		if (reset) begin
			read_active = 0;
		end else begin
			read_active = pmpx_rose || (state != S_IDLE);
		end
	end

	always @* begin
		if (reset) begin
			pcm_mux_needed = 0;
		end else if (pmpx_rose) begin
			pcm_mux_needed = 1;
		end else begin
			case (state)
				S_ADDRESS_READING, S_PCM_WRITING: begin
					pcm_mux_needed = 1;
				end
				S_PCM_READING: begin
					pcm_mux_needed = pcm_mem_ready;
				end
				default: begin
					pcm_mux_needed = 0;
				end
			endcase
		end
	end

	always @(posedge clk) begin
		if (state == S_ADDRESS_READING) begin
			read_state <= read_state + 1;
		end else begin
			read_state <= 0;
		end
	end

	// PCM mux selection:

	localparam [1:0]
		MUX_SRC_ADDRESS = 0,
		MUX_SRC_PCM_READ = 1,
		MUX_SRC_PCM_WRITE = 2;

	reg [1:0] mux_src;

	always @* begin
		if (pmpx_rose || (state == S_ADDRESS_READING)) begin
			mux_src = MUX_SRC_ADDRESS;
		end else if ((pcm_mem_ready && (state == S_PCM_READING)) || (state == S_PCM_WRITING)) begin
			mux_src = MUX_SRC_PCM_WRITE;
		end else begin
			mux_src = MUX_SRC_PCM_READ;
		end
	end

	always @* begin
		mux_sel_nx = 0;
		mux_oe_n_nx = 1;
		pcm_load_nx = 0;
		ym_io_out_nx = 0;
		ym_io_en_nx = 0;

		case (mux_src)
			MUX_SRC_ADDRESS: begin
				mux_sel_nx = ar_mux_sel_nx;
				mux_oe_n_nx = ar_mux_oe_n_nx;
			end
			MUX_SRC_PCM_READ: begin
				mux_sel_nx = pr_mux_sel_nx;
				mux_oe_n_nx = pr_mux_oe_n_nx;
			end
			MUX_SRC_PCM_WRITE: begin
				mux_sel_nx = pw_mux_sel_nx;
				mux_oe_n_nx = pw_mux_oe_n_nx;
				ym_io_en_nx = pw_ym_io_en_nx;

				pcm_load_nx = pw_pcm_load_nx;
				ym_io_out_nx = pw_ym_io_out_nx;
			end
		endcase
	end

	// PCM address reading output:

	localparam [2:0]
		MUX_SEL_PAD3_0 = 3'b010,
		MUX_SEL_PAD7_4 = 3'b110,
		MUX_SEL_PA11_8 = 3'b011;

	reg [2:0] ar_mux_sel_nx;
	wire ar_mux_oe_n_nx = 0;

	always @* begin
		ar_mux_sel_nx = 0;

		if (pmpx_rose) begin
			// Address low (first cycle before entering state)
			ar_mux_sel_nx = MUX_SEL_PAD3_0;
		end else begin
			case (read_state)
				// Address low
				0: begin
					ar_mux_sel_nx = MUX_SEL_PAD7_4;
				end
				1: begin
					ar_mux_sel_nx = MUX_SEL_PA11_8;
				end
				// Address high
				2, 3: begin
					// 2 cycles while we wait for data to change to PMPX-fall output (hi address)
					// We access it before the falling edge to buy time though
					// This was previously 2 cycles delay only but that is right on the edge
					// +1 cycle to give a bit more time for address to settle
					// Waiting too long means read starts too late though, need to balance this
					ar_mux_sel_nx = MUX_SEL_PAD3_0;
				end
				4: begin
					ar_mux_sel_nx = MUX_SEL_PAD7_4;
				end
				5: begin
					ar_mux_sel_nx = MUX_SEL_PA11_8;
				end
			endcase
		end
	end

	// PCM mux address reading input:

	reg [23:0] pcm_mem_addr_base;
	reg address_read_complete;

	assign pcm_mem_addr = pcm_mem_addr_base + ADDRESS_OFFSET;

	always @(posedge clk) begin
		address_read_complete <= 0;

		case (read_state)
			// States 0 are still waiting for inputs
			1: begin
				pcm_mem_addr_base[3:0] <= ym_io_in;
			end
			2: begin
				pcm_mem_addr_base[7:4] <= ym_io_in;
			end
			3: begin
				pcm_mem_addr_base[11:8] <= ym_io_in;
			end
			4: begin
				// ...waiting for the second set of signals to appear
			end
			5: begin
				pcm_mem_addr_base[15:12] <= ym_io_in;
			end
			6: begin
				pcm_mem_addr_base[19:16] <= ym_io_in;
			end
			7: begin
				pcm_mem_addr_base[23:20] <= ym_io_in;
				address_read_complete <= 1;
			end
		endcase
	end

	// PCM read handling:

	wire [2:0] pr_mux_sel_nx = 0;
	wire pr_mux_oe_n_nx = 1;

	always @* begin
		// address_read_complete brings the pcm_mem_valid output 1 cycle earlier
		// The 24bit address is already valid at this stage
		pcm_mem_valid = address_read_complete || (state == S_PCM_READING);
	end

	// PCM write handling:

	reg [1:0] write_state;

	always @(posedge clk) begin
		if (state == S_PCM_WRITING) begin
			write_state <= write_state + 1;
		end else begin
			write_state <= 0;
		end
	end	

	reg [7:0] pcm;

	always @(posedge clk) begin
		if (pcm_mem_ready) begin
			pcm <= pcm_mem_rdata;
		end
	end

	localparam [1:0]
		PCM_WRITE_LO_SETUP = 0,
		PCM_WRITE_LO_HOLD = 1,
		PCM_WRITE_HI_SETUP = 2,
		PCM_WRITE_HI_HOLD = 3;

	reg [1:0] pcm_write_step;

	always @* begin
		pcm_write_step = PCM_WRITE_LO_SETUP;

		if (pcm_mem_ready) begin
			// First step: Low nybble: setup + LE high
			pcm_write_step = PCM_WRITE_LO_SETUP;
		end else begin
			case (write_state)
				0: begin
					// Low nybble: hold + LE low
					pcm_write_step = PCM_WRITE_LO_HOLD;
				end
				1: begin
					// High nybble: setup + LE high
					pcm_write_step = PCM_WRITE_HI_SETUP;
				end
				2: begin
					// High nybble: hold + LE low
					pcm_write_step = PCM_WRITE_HI_HOLD;
				end
			endcase
		end
	end

	reg [2:0] pw_mux_sel_nx;
	reg [3:0] pw_ym_io_out_nx;
	reg pw_pcm_load_nx;

	reg write_complete;

	wire pw_ym_io_en_nx = 1;
	wire pw_mux_oe_n_nx = 1;

	always @* begin
		pw_mux_sel_nx = 0;
		pw_pcm_load_nx = 0;
		write_complete = 0;
		pw_ym_io_out_nx = 0;

		case (pcm_write_step)
			PCM_WRITE_LO_SETUP: begin
				pw_mux_sel_nx = 3'b101;
				pw_ym_io_out_nx = pcm_mem_rdata[3:0];

				// This prematurely drives PAD7-4 with a duplicate nybble
				// There's no ill effect from doing this though, it's set below
				pw_pcm_load_nx = 1;
			end
			PCM_WRITE_LO_HOLD: begin
				pw_mux_sel_nx = 3'b100;
				pw_ym_io_out_nx = pcm[3:0];

				pw_pcm_load_nx = 1;
			end
			PCM_WRITE_HI_SETUP: begin
				pw_mux_sel_nx = 3'b100;
				pw_ym_io_out_nx = pcm[7:4];

				pw_pcm_load_nx = 1;
			end
			PCM_WRITE_HI_HOLD: begin
				pw_mux_sel_nx = 3'b100;
				pw_ym_io_out_nx = pcm[7:4];

				write_complete = 1;
			end
		endcase
	end

	// --- Status outputs ---

	always @(posedge clk) begin
		if (reset || pmpx_count_reset) begin
			pmpx_rise_count <= 0;
			pmpx_fall_count <= 0;
		end else begin
			if (pmpx_rose) begin
				pmpx_rise_count <= pmpx_rise_count + 1;
			end else if (pmpx_fell) begin
				pmpx_fall_count <= pmpx_fall_count + 1;
			end
		end
	end

	// --- Debug ---

	always @(posedge clk) begin
		if (write_complete) begin
			dbg_previous_addr <= pcm_mem_addr;
			dbg_previous_data <= pcm;
		end
	end

	// --- Convenience functions ---

	function [0:0] state_changing_to;
		input [1:0] new_state;

		state_changing_to = (state_nx == new_state) && (state != new_state);
	endfunction

endmodule
