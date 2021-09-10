// adpcm_a_reader.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

module adpcm_a_reader(
	input clk,
	input reset,

	// Status

	output reg [15:0] rmpx_rise_count,
	output reg [15:0] rmpx_fall_count,
	input rmpx_count_reset,

	// PCM Mux

	// Unlike ADPCM-B, reads can be interrupted
	input pause,

	output reg pcm_mux_needed,
	output reg read_active,

	input rmpx_rose,
	input rmpx_fell,

	input [3:0] ym_io_in,

	output [3:0] ym_io_out,
	output ym_io_en,
	output [2:0] mux_sel,
	output mux_oe_n,
	output pcm_load,

	// PCM data reading

	input [7:0] pcm_mem_rdata,
	input pcm_mem_ready,

	output reg [23:0] pcm_mem_addr,
	output reg pcm_mem_valid
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

	// --- RMPX montioring ---

	reg address_lo_pending;
	reg address_hi_pending;
	reg pcm_read_pending;
	reg pcm_write_pending;

	always @(posedge clk) begin
		if (reset) begin
			address_lo_pending <= 0;
			address_hi_pending <= 0;
			pcm_read_pending <= 0;
			pcm_write_pending <= 0;
		end else begin
			if (rmpx_rose) begin
				address_lo_pending <= 1;
			end else if (address_lo_done) begin
				address_lo_pending <= 0;
			end

			if (rmpx_fell) begin
				address_hi_pending <= 1;
			end else if (address_hi_done) begin
				address_hi_pending <= 0;
				pcm_read_pending <= 1;
			end

			if ((state == S_PCM_READING) && pcm_mem_ready) begin
				pcm_read_pending <= 0;
				pcm_write_pending <= 1;
			end

			if (write_complete) begin
				pcm_write_pending <= 0;
			end
		end
	end

	// --- FSM ---

	// Unlike the ADPCM-B reader, these states are interruptible
	// Each step is given an <action>_pending steps shown below

	localparam [2:0]
		S_IDLE = 0,
		S_ADDRESS_LO_READING = 1,
		S_ADDRESS_HI_READING = 2,
		S_PCM_READING = 3,
		S_PCM_WRITING = 4;

	reg [2:0] state;
	reg [2:0] state_nx;

	always @(posedge clk) begin
		state <= state_nx;
	end

	always @* begin
		if (reset) begin
			state_nx = S_IDLE;
		end else if (pause) begin
			state_nx = S_IDLE;
		end else begin
			state_nx = state;

			case (state)
				S_IDLE: begin
					if (address_lo_pending) begin
						state_nx = S_ADDRESS_LO_READING;
					end else if (address_hi_pending) begin
						state_nx = S_ADDRESS_HI_READING;
					end else if (pcm_read_pending) begin
						state_nx = S_PCM_READING;
					end else if (pcm_write_pending) begin
						state_nx = S_PCM_WRITING;
					end
				end
				S_ADDRESS_LO_READING: begin
					// Can't just jump to ADDRESS_HI since RMPX needs to fall first
					if (address_lo_done) begin
						state_nx = S_IDLE;
					end
				end
				S_ADDRESS_HI_READING: begin
					if (address_hi_done) begin
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

	always @* begin
		if (reset) begin
			read_active = 0;
		end else begin
			read_active = (state != S_IDLE);
		end
	end

	always @* begin
		if (reset) begin
			pcm_mux_needed = 0;
		end else begin
			case (state)
				S_ADDRESS_LO_READING, S_ADDRESS_HI_READING, S_PCM_WRITING: begin
					pcm_mux_needed = 1;
				end
				default: begin
					pcm_mux_needed = 0;
				end
			endcase
		end
	end

	reg [3:0] read_state;

	always @(posedge clk) begin
		if (reset) begin
			read_state <= 0;
		end else begin
			if (state_changing_to(S_IDLE) || state_changing_to(S_ADDRESS_LO_READING)) begin
				read_state <= 0;
			end else if (state_changing_to(S_ADDRESS_HI_READING)) begin
				read_state <= 5;
			end else begin
				case (state)
					S_ADDRESS_LO_READING, S_ADDRESS_HI_READING: begin
						read_state <= read_state + 1;
					end
				endcase
			end
		end
	end

	// PCM mux selection:

	always @* begin
		mux_sel_nx = 0;
		mux_oe_n_nx = 1;
		pcm_load_nx = 0;
		ym_io_out_nx = 0;
		ym_io_en_nx = 0;

		case (state)
			S_ADDRESS_LO_READING, S_ADDRESS_HI_READING: begin
				mux_sel_nx = ar_mux_sel_nx;
				mux_oe_n_nx = ar_mux_oe_n_nx;
			end
			S_PCM_READING: begin
				mux_sel_nx = pr_mux_sel_nx;
				mux_oe_n_nx = pr_mux_oe_n_nx;
			end
			S_PCM_WRITING: begin
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
		MUX_SEL_RAD3_0 = 3'b000,
		MUX_SEL_RAD7_4 = 3'b100,
		MUX_SEL_RA9_8 = 3'b101,
		MUX_SEL_RA23_20 = 3'b001;

	reg [2:0] ar_mux_sel_nx;
	reg ar_mux_oe_n_nx;

	always @* begin
		ar_mux_sel_nx = 0;
		ar_mux_oe_n_nx = 0;

		case (read_state)
			// Address low

			0: begin
				ar_mux_sel_nx = MUX_SEL_RAD3_0;
			end
			1: begin
				ar_mux_sel_nx = MUX_SEL_RAD7_4;
			end
			2: begin
				ar_mux_sel_nx = MUX_SEL_RA9_8;
			end

			// FIXME: gap here, detemrine if it needs to be shortened (/poe time)
			
			// Address high (same as above with the RA23_20 added)

			5: begin
				ar_mux_sel_nx = MUX_SEL_RAD3_0;
			end
			6: begin
				ar_mux_sel_nx = MUX_SEL_RAD7_4;
			end
			7: begin
				ar_mux_sel_nx = MUX_SEL_RA9_8;
			end
			8: begin
				ar_mux_sel_nx = MUX_SEL_RA23_20;
			end
		endcase
	end

	// PCM mux address reading input:

	reg address_lo_done;
	reg address_hi_done;

	always @(posedge clk) begin
		address_lo_done <= 0;
		address_hi_done <= 0;

		case (read_state)
			// States 0, 1 are still waiting for inputs
			2: begin
				pcm_mem_addr[3:0] <= ym_io_in;
			end
			3: begin
				pcm_mem_addr[7:4] <= ym_io_in;
			end
			4: begin
				pcm_mem_addr[9:8] <= ym_io_in[1:0];
				address_lo_done <= 1;
			end

			// Address high

			7: begin
				pcm_mem_addr[13:10] <= ym_io_in;
			end
			8: begin
				pcm_mem_addr[17:14] <= ym_io_in;
			end
			9: begin
				pcm_mem_addr[19:18] <= ym_io_in[1:0];
			end
			10: begin
				pcm_mem_addr[23:20] <= ym_io_in;
				address_hi_done <= 1;
			end
		endcase
	end

	// ---

	// PCM read handling:

	wire [2:0] pr_mux_sel_nx = 0;
	wire pr_mux_oe_n_nx = 1;

	always @(posedge clk) begin
		pcm_mem_valid <= (state_nx == S_PCM_READING) && !pcm_mem_ready;
	end

	reg [7:0] pcm;

	always @(posedge clk) begin
		if (!pause && pcm_mem_ready) begin
			pcm <= pcm_mem_rdata;
		end
	end

	// PCM write handling:

	reg [2:0] write_state;

	always @(posedge clk) begin
		if (state_changing_to(S_IDLE) || state_changing_to(S_PCM_WRITING)) begin
			write_state <= 0;
		end else if (state == S_PCM_WRITING) begin
			write_state <= write_state + 1;
		end
	end	

	reg [2:0] pw_mux_sel_nx;
	reg [3:0] pw_ym_io_out_nx;
	reg pw_pcm_load_nx;
	reg write_complete;

	wire pw_mux_oe_n_nx = 1;
	wire pw_ym_io_en_nx = 1;

	always @* begin
		pw_mux_sel_nx = 0;
		pw_pcm_load_nx = 0;
		pw_ym_io_out_nx = 0;

		write_complete = 0;

		case (write_state)
			0: begin
				// Low nybble: setup + LE high
				pw_mux_sel_nx = 3'b011;
				pw_ym_io_out_nx = pcm[3:0];
			end
			1: begin
				// Low nybble: hold + LE low
				pw_mux_sel_nx = 3'b010;
				pw_ym_io_out_nx = pcm[3:0];
			end
			2: begin
				// High nybble: setup + LE high
				pw_mux_sel_nx = 3'b010;
				// Note the bit reversal
				pw_ym_io_out_nx = {pcm[4], pcm[5], pcm[6], pcm[7]};
				pw_pcm_load_nx = 1;
			end
			3: begin
				// High nybble: hold + LE low
				pw_mux_sel_nx = 3'b010;
				pw_ym_io_out_nx = {pcm[4], pcm[5], pcm[6], pcm[7]};
			end
			4: begin
				// Extra state incase ADPCMB interrupts the write on final cycle
				write_complete = 1;
			end
		endcase
	end

	// --- Status outputs ---

	always @(posedge clk) begin
		if (reset || rmpx_count_reset) begin
			rmpx_rise_count <= 0;
			rmpx_fall_count <= 0;
		end else begin
			if (rmpx_rose) begin
				rmpx_rise_count <= rmpx_rise_count + 1;
			end else if (rmpx_fell) begin
				rmpx_fall_count <= rmpx_fall_count + 1;
			end
		end
	end

	// --- Convenience functions ---

	function [0:0] state_changing_to;
		input [2:0] new_state;

		state_changing_to = (state_nx == new_state) && (state != new_state);
	endfunction

endmodule
