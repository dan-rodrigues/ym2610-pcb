// ym2610_pcm_mux_ctrl.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

module ym2610_pcm_mux_ctrl #(
	parameter [0:0] ENABLE_ADPCM_A = 1,
	parameter [0:0] ENABLE_ADPCM_B = 1,
	parameter [0:0] ENABLE_DEBUG_REGS = 0
) (
	input clk,
	input reset,

	// Wishbone

	input [2:0] wb_addr,
	input [31:0] wb_wdata,
	output reg [31:0] wb_rdata,
	input wb_cyc,
	input wb_we,
	output reg wb_ack,

	// YM2610 PCM control

	inout [3:0] ym_io,
	output [2:0] mux_sel,
	output mux_oe_n,
	output pcm_load,
	input rmpx,
	input pmpx,

	// PCM memory interface

	output [23:0] pcm_mem_addr,
	output pcm_mem_valid,

	input [7:0] pcm_mem_rdata,
	input pcm_mem_ready
);
	// --- Wishbone ---

	// Writes:

	reg enable;

	reg rmpx_count_reset;
	reg pmpx_count_reset;

	always @(posedge clk) begin
		if (reset) begin
			enable <= 0;
			wb_ack <= 0;
		end else begin
			rmpx_count_reset <= 0;
			pmpx_count_reset <= 0;

			if (wb_cyc && wb_we) begin
				if (!wb_addr[0]) begin
					enable <= wb_wdata[0];
				end else begin
					{pmpx_count_reset, rmpx_count_reset} <= wb_wdata[1:0];
				end
			end

			wb_ack <= wb_cyc && !wb_ack;
		end
	end

	// Reads:

	always @(posedge clk) begin
		if (reset) begin
			wb_rdata <= 0;
		end else begin
			wb_rdata <= 0;

			if (wb_cyc && !wb_we && ENABLE_DEBUG_REGS) begin
				case (wb_addr[2:1])
					0: begin
						wb_rdata <= wb_addr[0] ? rmpx_fall_count : rmpx_rise_count;
					end
					1: begin
						wb_rdata <= wb_addr[0] ? pmpx_fall_count : pmpx_rise_count;
					end
					2: begin
						wb_rdata <= {p_dbg_previous_data, p_dbg_previous_addr};
					end
				endcase
			end
		end
	end

	// --- A/B selection ---

	assign mux_sel_nx = p_mux_needed ? p_mux_sel : r_mux_sel;
	assign mux_oe_n_nx = p_mux_needed ? p_mux_oe_n : r_mux_oe_n;
	assign pcm_load_nx = p_mux_needed ? p_pcm_load : r_pcm_load;
	assign ym_io_en_nx = p_mux_needed ? p_ym_io_en : r_ym_io_en;
	assign ym_io_out_nx = p_mux_needed ? p_ym_io_out : r_ym_io_out;

	assign pcm_mem_valid = p_active ? p_pcm_mem_valid : r_pcm_mem_valid;
	assign pcm_mem_addr = p_active ? p_pcm_mem_addr : r_pcm_mem_addr;

	// --- ADPCM-A ---

	reg [1:0] rmpx_sync;
	reg rmpx_rose;
	reg rmpx_fell;

	always @* begin
		rmpx_rose = rmpx_sync[0] && !rmpx_sync[1];

		// We're not going to wait 36 cycles for RMPX to fall before actually reading the address
		// It takes a while and there is limited time before the RAD7-0 bus is tristated
		// ADPCMB may also signal a read and interrupt an in-progress ADPCMA read
		rmpx_fell = rmpx_hi_valid;
	end

	always @(posedge clk) begin
		rmpx_sync <= {rmpx_sync[1:0], rmpx_in};
	end

	// This delay can potentially be reduced because of delays in reading the address
	// 32: OK, 31: all glitches
	//
	// The block below should delay it by 33 cycles which is +2 from where it fails 100% of the time

	reg [5:0] rmpx_delay_counter;
	wire rmpx_delay_counter_msb = rmpx_delay_counter[5];
	reg rmpx_delay_counter_msb_r;
	reg rmpx_hi_valid;

	always @(posedge clk) begin
		if (reset || rmpx_rose) begin
			rmpx_delay_counter <= 0;
			rmpx_delay_counter_msb_r <= 0;
			rmpx_hi_valid <= 0;
		end else begin
			rmpx_hi_valid <= (rmpx_delay_counter_msb && !rmpx_delay_counter_msb_r);
			rmpx_delay_counter_msb_r <= rmpx_delay_counter_msb;

			if (!rmpx_delay_counter_msb) begin
				rmpx_delay_counter <= rmpx_delay_counter + 1;
			end
		end
	end

	wire r_active;
	wire [3:0] r_ym_io_out;
	wire r_ym_io_en;
	wire [2:0] r_mux_sel;
	wire r_pcm_load;
	wire r_mux_oe_n;

	wire r_mux_needed;

	wire [23:0] r_pcm_mem_addr;
	wire r_pcm_mem_valid;

	wire [15:0] rmpx_rise_count;
	wire [15:0] rmpx_fall_count;

	adpcm_a_reader adpcm_a_reader(
		.clk(clk),
		.reset(reset || !enable || !ENABLE_ADPCM_A),
		.pause(p_active),

		.rmpx_rise_count(rmpx_rise_count),
		.rmpx_fall_count(rmpx_fall_count),
		.rmpx_count_reset(rmpx_count_reset),

		.read_active(r_active),
		.pcm_mux_needed(r_mux_needed),

		.rmpx_rose(rmpx_rose),
		.rmpx_fell(rmpx_fell),

		.ym_io_in(ym_io_in),
		.ym_io_out(r_ym_io_out),
		.ym_io_en(r_ym_io_en),
		.mux_sel(r_mux_sel),
		.mux_oe_n(r_mux_oe_n),
		.pcm_load(r_pcm_load),

		.pcm_mem_rdata(pcm_mem_rdata),
		.pcm_mem_ready(pcm_mem_ready),
		.pcm_mem_addr(r_pcm_mem_addr),
		.pcm_mem_valid(r_pcm_mem_valid)
	);

	// --- ADPCM-B ---

	reg pmpx_rose;
	reg pmpx_fell;

	reg [1:0] pmpx_r;
	reg pmpx_stable_low;
	reg pmpx_stable_high;

	always @* begin
		pmpx_rose = !pmpx_r[1] && pmpx_r[0];
		pmpx_fell = pmpx_r[1] && !pmpx_r[0];
	end

	always @(posedge clk) begin
		pmpx_r <= {pmpx_r[0], pmpx_in};
	end

	wire p_active;
	wire [3:0] p_ym_io_out;
	wire p_ym_io_en;
	wire [2:0] p_mux_sel;
	wire p_pcm_load;
	wire p_mux_oe_n;

	wire p_mux_needed;

	wire [23:0] p_pcm_mem_addr;
	wire p_pcm_mem_valid;

	wire [15:0] pmpx_rise_count;
	wire [15:0] pmpx_fall_count;

	wire [23:0] p_dbg_previous_addr;
	wire [7:0] p_dbg_previous_data;

	adpcm_b_reader #(
		// 4M offset assumes A/B have their separate 4MB regions
		// This only works in cases where the audio ROMs are <= 4MB total
		// Total sizes up to 8MB total work for bigger tracks
		// Sizes beyond 8MB need some sort of MMU to do address mapping
		.ADDRESS_OFFSET(24'h000000)
	) adpcm_b_reader(
		.clk(clk),
		.reset(reset || !enable || !ENABLE_ADPCM_B),

		.pmpx_rise_count(pmpx_rise_count),
		.pmpx_fall_count(pmpx_fall_count),
		.pmpx_count_reset(pmpx_count_reset),

		.read_active(p_active),
		.pcm_mux_needed(p_mux_needed),

		.pmpx_rose(pmpx_rose),
		.pmpx_fell(pmpx_fell),

		.ym_io_in(ym_io_in),
		.ym_io_out(p_ym_io_out),
		.ym_io_en(p_ym_io_en),
		.mux_sel(p_mux_sel),
		.mux_oe_n(p_mux_oe_n),
		.pcm_load(p_pcm_load),

		.pcm_mem_rdata(pcm_mem_rdata),
		.pcm_mem_ready(pcm_mem_ready),
		.pcm_mem_addr(p_pcm_mem_addr),
		.pcm_mem_valid(p_pcm_mem_valid),

		.dbg_previous_addr(p_dbg_previous_addr),
		.dbg_previous_data(p_dbg_previous_data)
	);

	// --- IO regs ---

	// ym_io (4bit bidirectional IO to PCM mux on board):

	wire [3:0] ym_io_in;
	wire [3:0] ym_io_out_nx;
	wire ym_io_en_nx;

	SB_IO #(
		.PIN_TYPE(6'b110100),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) ym_io_sbio [3:0] (
		.OUTPUT_CLK(clk),
		.INPUT_CLK(clk),

		.PACKAGE_PIN(ym_io),
		.OUTPUT_ENABLE(ym_io_en_nx),
		.D_OUT_0(ym_io_out_nx),
		.D_IN_0(ym_io_in)
	);

	// Mux control:

	wire [2:0] mux_sel_nx;
	wire mux_oe_n_nx;
	wire pcm_load_nx;

	SB_IO #(
		.PIN_TYPE(6'b010100),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) ym_pcm_mux_ctrl_sbio [4:0] (
		.OUTPUT_CLK(clk),
		.INPUT_CLK(clk),

		.PACKAGE_PIN({mux_oe_n, pcm_load, mux_sel}),
		.D_OUT_0({mux_oe_n_nx, pcm_load_nx, mux_sel_nx})
	);

	// RMPX / PMPX inputs from YM2610:

	wire pmpx_in;
	wire rmpx_in;

	SB_IO #(
		.PIN_TYPE(6'b000000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) ym_mpx_sbio [1:0] (
		.INPUT_CLK(clk),
		.OUTPUT_CLK(clk),

		.PACKAGE_PIN({pmpx, rmpx}),
		.D_IN_0({pmpx_in, rmpx_in})
	);

endmodule
