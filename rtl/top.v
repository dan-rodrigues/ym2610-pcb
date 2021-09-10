/*
 * top.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2019-2020  Sylvain Munaut <tnt@246tNt.com>
 * Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
 *
 * SPDX-License-Identifier: CERN-OHL-S-2.0
 */

`default_nettype none

`include "boards.vh"

module top #(
	parameter [0:0] ENABLE_DAC_DEBUG_REGS = 0,
	parameter [0:0] ENABLE_MIDI = 0
) (
	// SPI
	inout  wire [3:0] spi_io,
	output  wire       spi_clk,
	output  wire spi_flash_cs_n,
	output  wire spi_ram_cs_n,

	// MIDI (input only)
	input midi_rx,

	// USB
	inout  wire usb_dp,
	inout  wire usb_dn,
	output wire usb_pu,

	// Debug UART
	input  wire uart_rx,
	output wire uart_tx,

	// Button (on bitsy)
	input  wire btn,

	// Extra buttons (on PCB)
	input wire btn_a,
	input wire btn_b,

	// LED
	output wire [2:0] rgb,
	// output reg led,

	// Clock
	input  wire clk_in,

	// YM2610 control
	output ym_clk,
	output ym_shift_out,
	output ym_shift_load,

	// YM2610 PCM mux
	inout [3:0] ym_io,
	output [2:0] mux_sel,
	output mux_oe_n,
	output pcm_load,
	input rmpx,
	input pmpx,

	// YM3016 DAC (digital input only)
	input dac_clk,
	input dac_sh1,
	input dac_sh2,
	input dac_so,

	// SPDIF output (from DAC)
	output spdif_out
);
	localparam integer SPRAM_AW = 15; /* 14 => 64k, 15 => 128k */
	localparam integer WB_N  =  14;

	localparam integer WB_DW = 32;
	localparam integer WB_AW = 16;
	localparam integer WB_RW = WB_DW * WB_N;
	localparam integer WB_MW = WB_DW / 8;

	genvar i;

	// Signals
	// -------

	// Wishbone
	wire [WB_AW-1:0] wb_addr;
	wire [WB_DW-1:0] wb_rdata [0:WB_N-1];
	wire [WB_RW-1:0] wb_rdata_flat;
	wire [WB_DW-1:0] wb_wdata;
	wire [WB_MW-1:0] wb_wmsk;
	wire [WB_N -1:0] wb_cyc;
	wire             wb_we;
	wire [WB_N -1:0] wb_ack;

	// USB
	wire usb_sof;

	// WarmBoot
	reg boot_now;
	reg [1:0] boot_sel;

	// Clock / Reset logic
	wire clk_24m;
	wire clk_48m;
	wire rst;


	// SoC
	// ---

	wire [23:0] spi_addr;
	wire [31:0] spi_rdata;
	wire [31:0] spi_mem_wdata;
	wire spi_valid;
	wire spi_ready;
	wire spi_we;
	wire spi_mem_select;

	soc_picorv32_base #(
		.WB_N    (WB_N),
		.WB_DW   (WB_DW),
		.WB_AW   (WB_AW),
		.SPRAM_AW(SPRAM_AW)
	) base_I (
		.wb_addr (wb_addr),
		.wb_rdata(wb_rdata_flat),
		.wb_wdata(wb_wdata),
		.wb_wmsk (wb_wmsk),
		.wb_we   (wb_we),
		.wb_cyc  (wb_cyc),
		.wb_ack  (wb_ack),

		.spi_addr(spi_addr[23:0]),
		.spi_valid(spi_valid),
		.spi_we(spi_we),
		.spi_rdata(spi_rdata),
		.spi_wdata(spi_mem_wdata),
		.spi_ready(spi_ready),
		.spi_mem_select(spi_mem_select),

		.clk     (clk_24m),
		.rst     (rst)
	);

	for (i=0; i<WB_N; i=i+1)
		assign wb_rdata_flat[i*WB_DW+:WB_DW] = wb_rdata[i];

	// UART [1]
	// ----

	uart_wb #(
		.DIV_WIDTH(12),
		.DW(WB_DW)
	) uart_I (
		.uart_tx  (uart_tx),

		// Disabling UART RX until it's actually needed
		// .uart_rx  (uart_rx),
		.uart_rx  (),

		.wb_addr  (wb_addr[1:0]),
		.wb_rdata (wb_rdata[1]),
		.wb_we    (wb_we),
		.wb_wdata (wb_wdata),
		.wb_cyc   (wb_cyc[1]),
		.wb_ack   (wb_ack[1]),
		.clk      (clk_24m),
		.rst      (rst)
	);

	// QSPI [2]
	// --------

	spi_mem spi_mem(
		.clk(clk_24m),
		.clk_2x(clk_48m),
		.reset(rst),

		// Flash / PSRAM access

		.mem_addr(spi_valid ? spi_addr : pcm_mem_addr),
		.mem_valid(spi_valid || pcm_mem_valid),
		.mem_we(spi_valid ? spi_we : 1'b0),
		.mem_ready(spi_ready),
		.mem_length(spi_valid ? 2'b11 : 2'b00),
		.mem_rdata(spi_rdata),
		.mem_wdata(spi_mem_wdata),
		.mem_select(spi_valid ? spi_mem_select : 1'b1),

		// Wishbone

		.wb_addr(wb_addr[0]),
		.wb_wdata(wb_wdata),
		.wb_we(wb_we),
		.wb_cyc(wb_cyc[2]),
		.wb_rdata(wb_rdata[2]),
		.wb_ack(wb_ack[2]),

		// SPI

		.spi_clk(spi_clk),
		.spi_csn({spi_ram_cs_n, spi_flash_cs_n}),
		.spi_io(spi_io)
	);

	// RGB LEDs [3]
	// --------

	ice40_rgb_wb #(
		.CURRENT_MODE("0b1"),
		.RGB0_CURRENT("0b000001"),
		.RGB1_CURRENT("0b000001"),
		.RGB2_CURRENT("0b000001")
	) rgb_I (
		.pad_rgb    (rgb),
		.wb_addr    (wb_addr[4:0]),
		.wb_rdata   (wb_rdata[3]),
		.wb_wdata   (wb_wdata),
		.wb_we      (wb_we),
		.wb_cyc     (wb_cyc[3]),
		.wb_ack     (wb_ack[3]),
		.clk        (clk_24m),
		.rst        (rst)
	);

	// USB [4 & 5]
	// ---

	soc_usb #(
		.DW(WB_DW)
	) usb_I (
		.usb_dp   (usb_dp),
		.usb_dn   (usb_dn),
		.usb_pu   (usb_pu),
		.wb_addr  (wb_addr[11:0]),
		.wb_rdata (wb_rdata[4]),
		.wb_wdata (wb_wdata),
		.wb_we    (wb_we),
		.wb_cyc   (wb_cyc[5:4]),
		.wb_ack   (wb_ack[5:4]),
		.usb_sof  (usb_sof),
		.clk_sys  (clk_24m),
		.clk_48m  (clk_48m),
		.rst      (rst)
	);

	assign wb_rdata[5] = 0;

	// (Unused) [6]
	// -------------

	assign wb_rdata[6] = 0;
	assign wb_ack[6] = wb_cyc[6];

	// Midi [7]
	//---------

	uart_wb #(
		.DIV_WIDTH(12),
		.DW(WB_DW)
	) midi_I (
		.uart_tx  (),
		.uart_rx  (ENABLE_MIDI ? midi_rx : 1'b1),

		.wb_addr  (wb_addr[1:0]),
		.wb_rdata (wb_rdata[7]),
		.wb_we    (wb_we),
		.wb_wdata (wb_wdata),
		.wb_cyc   (wb_cyc[7]),
		.wb_ack   (wb_ack[7]),
		.clk      (clk_24m),
		.rst      (rst)
	);

	// YM2610 Control (shift register output) [8]
	//-------------------------------------------

	wire ym_clk_rose = (clk_8m_ddr == 2'b11);
	wire ym_clk_fell = (clk_8m_ddr == 2'b10);

	wire ym_shift_out_nx;
	wire ym_shift_load_nx;

	ym2610_ctrl ym2610_ctrl(
		.clk(clk_24m),
		.reset(rst),

		.ym_clk_rose(ym_clk_rose),
		.ym_clk_fell(ym_clk_fell),

		.wb_addr(wb_addr[2:0]),
		.wb_rdata(wb_rdata[8]),
		.wb_we(wb_we),
		.wb_wdata(wb_wdata[7:0]),
		.wb_cyc(wb_cyc[8]),
		.wb_ack(wb_ack[8]),

		.ctrl_shift_out(ym_shift_out_nx),
		.ctrl_shift_load(ym_shift_load_nx)
	);

	SB_IO #(
		.PIN_TYPE(6'b010100),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b1),
		.IO_STANDARD("SB_LVCMOS")
	) ym_shift_sbio [1:0] (
		.INPUT_CLK(clk_24m),
		.OUTPUT_CLK(clk_24m),
		.CLOCK_ENABLE(1'b1),

		.PACKAGE_PIN({ym_shift_out, ym_shift_load}),
		.D_OUT_0({ym_shift_out_nx, ym_shift_load_nx})
	);

	// LED (red) [9]
	//--------------

	// (determine what to do with LED since it's also used elsewhere)

	assign wb_rdata[9] = 0;
	assign wb_ack[9] = wb_cyc[9];

	// reg led_ack;
	// assign wb_ack[9] = led_ack;
	// assign wb_rdata[9] = 32'b0;

	// always @(posedge clk_24m) begin
	// 	if (wb_cyc[9] && wb_we) begin
	// 		// led <= wb_wdata[0];
	// 	end

	// 	led_ack <= wb_cyc[9] && !led_ack;
	// end

	// YM2610 PCM mux control [10]
	//----------------------------

	wire [23:0] pcm_mem_addr;
	wire pcm_mem_valid;
	wire pcm_mem_ready = pcm_mem_valid && spi_ready;

	ym2610_pcm_mux_ctrl ym2610_pcm_mux_ctrl(
		.clk(clk_24m),
		.reset(rst),

		// Wishbone

		.wb_addr(wb_addr[2:0]),
		.wb_wdata(wb_wdata),
		.wb_rdata(wb_rdata[10]),
		.wb_cyc(wb_cyc[10]),
		.wb_ack(wb_ack[10]),
		.wb_we(wb_we),

		// YM2610 PCM control

		.ym_io(ym_io),
		.mux_sel(mux_sel),
		.mux_oe_n(mux_oe_n),
		.pcm_load(pcm_load),
		.rmpx(rmpx),
		.pmpx(pmpx),

		// Memory interface

		.pcm_mem_addr(pcm_mem_addr),
		.pcm_mem_valid(pcm_mem_valid),
		.pcm_mem_rdata(spi_rdata[7:0]),
		.pcm_mem_ready(pcm_mem_ready)
	);

	// YM3016 DAC debug reading [11]
	//------------------------------

	reg dbg_dac_ack;
	reg [31:0] dbg_dac_rdata;
	assign wb_rdata[11] = dbg_dac_rdata;
	assign wb_ack[11] = dbg_dac_ack;

	always @(posedge clk_24m) begin
		if (wb_cyc[11] && !wb_we && ENABLE_DAC_DEBUG_REGS) begin
			dbg_dac_rdata <= wb_addr[0] ? dbg_dac_shift_right : dbg_dac_shift_left;
		end else begin
			dbg_dac_rdata <= 32'b0;
		end

		dbg_dac_ack <= wb_cyc[11] && !dbg_dac_ack;
	end

	// Timer [12]
	//-----------

	vgm_timer vgm_timer(
		.clk(clk_24m),
		.reset(rst),

		.wb_addr(wb_addr[0]),
		.wb_wdata(wb_wdata),
		.wb_we(wb_we),
		.wb_cyc(wb_cyc[12]),
		.wb_rdata(wb_rdata[12]),
		.wb_ack(wb_ack[12])
	);

	// Buttons [13]
	//-----------

	buttons buttons(
		.clk(clk_24m),
		.reset(rst),

		.wb_we(wb_we),
		.wb_cyc(wb_cyc[13]),
		.wb_rdata(wb_rdata[13]),
		.wb_ack(wb_ack[13]),

		.btn({btn_b_r, btn_a_r})
	);

	wire btn_a_r;
	wire btn_b_r;

	SB_IO #(
		.PIN_TYPE(6'b000001),
		.PULLUP(1'b1),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) btn_sbio [1:0] (
		.INPUT_CLK(clk_24m),
		.OUTPUT_CLK(clk_24m),

		.PACKAGE_PIN({btn_b, btn_a}),
		.D_IN_0({btn_b_r, btn_a_r})
	);

	// YM3016 DAC
	//-----------

	// Clock enable (based on DAC input)

	reg [2:0] dac_clk_sync_r;
	// FIXME: this is wrong, falling edge is used, _rose here is actually falling edge
	wire dac_clk_rose = dac_clk_sync_r[2] && !dac_clk_sync_r[1];
	wire dac_clk_fell = !dac_clk_sync_r[2] && dac_clk_sync_r[1];

	always @(posedge clk_24m) begin
		dac_clk_sync_r <= {dac_clk_sync_r[1:0], dac_clk_r};
	end

	// Sample inputs:

	reg [2:0] dac_so_sync_r, dac_sh1_sync_r, dac_sh2_sync_r;
	wire dac_so_sync = dac_so_sync_r[2];
	wire dac_sh1_sync = dac_sh1_sync_r[2];
	wire dac_sh2_sync = dac_sh2_sync_r[2];

	always @(posedge clk_24m) begin
		dac_so_sync_r <= {dac_so_sync_r[1:0], dac_so_r};
		dac_sh1_sync_r <= {dac_sh1_sync_r[1:0], dac_sh1_r};
		dac_sh2_sync_r <= {dac_sh2_sync_r[1:0], dac_sh2_r};
	end

	reg [15:0] dac_pcm_l_valid;
	reg [15:0] dac_pcm_r_valid;

	always @(posedge clk_24m) begin
		if (dac_pcm_valid) begin
			dac_pcm_l_valid <= dac_pcm_l;
			dac_pcm_r_valid <= dac_pcm_r;
		end
	end

	wire dac_pcm_valid;
	wire [15:0] dac_pcm_l;
	wire [15:0] dac_pcm_r;

	wire [15:0] dbg_dac_shift_left;
	wire [15:0] dbg_dac_shift_right;

	ym3016 ym3016 (
		.clk(clk_24m),
		.clk_en(dac_clk_rose),
		.ic_n(!rst),

		// FORM always tied to VCC
		.form(1'b1),

		.so(dac_so_sync),
		.sh1(dac_sh1_sync),
		.sh2(dac_sh2_sync),

		.dbg_shift_left(dbg_dac_shift_left),
		.dbg_shift_right(dbg_dac_shift_right),

		.left(dac_pcm_l),
		.right(dac_pcm_r),
		.output_valid(dac_pcm_valid)
	);

	// YM2610 PMOD inputs (DAC):

	wire dac_sh1_r;
	wire dac_sh2_r;
	wire dac_clk_r;
	wire dac_so_r;

	SB_IO #(
		.PIN_TYPE(6'b000000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) ym_pmod_out_sbio [3:0] (
		.INPUT_CLK(clk_24m),
		.OUTPUT_CLK(clk_24m),

		.PACKAGE_PIN({dac_sh1, dac_sh2, dac_clk, dac_so}),
		.D_IN_0({dac_sh1_r, dac_sh2_r, dac_clk_r, dac_so_r})
	);

	// SPDIF:

	wire [15:0] spdif_selected_sample = spdif_channel_select ? dac_pcm_l_valid : dac_pcm_r_valid;
	wire [23:0] spdif_pcm_in = {spdif_selected_sample, 8'b0};
	wire spdif_channel_select;

	wire spdif_tx_nx;

	spdif_tx #(
		.C_clk_freq(24000000),
		.C_sample_freq(48000)
	) spdif_tx (
		.clk(clk_24m),
		.data_in(spdif_pcm_in),
		.address_out(spdif_channel_select),
		.spdif_out(spdif_tx_nx)
	);

	SB_IO #(
		.PIN_TYPE(6'b010100),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) spdif_tx_sbio (
		.OUTPUT_CLK(clk_24m),
		.INPUT_CLK(clk_24m),

		.PACKAGE_PIN(spdif_out),
		.D_OUT_0(spdif_tx_nx)
	);

	// Warm Boot
	// ---------

	// Bus interface
	always @(posedge clk_24m or posedge rst)
		if (rst) begin
			boot_now <= 1'b0;
			boot_sel <= 2'b00;
		end else if (wb_cyc[0] & wb_we & (wb_addr[2:0] == 3'b000)) begin
			boot_now <= wb_wdata[2];
			boot_sel <= wb_wdata[1:0];
		end

	assign wb_rdata[0] = 0;
	assign wb_ack[0] = wb_cyc[0];

	// Helper
	dfu_helper #(
		.TIMER_WIDTH(24),
		.BTN_MODE(3),
		.DFU_MODE(0)
	) dfu_helper_I (
		.boot_now(boot_now),
		.boot_sel(boot_sel),
		.btn_pad(btn),
		.btn_val(),
		.rst_req(),
		.clk(clk_24m),
		.rst(rst)
	);

	// Clock / Reset
	// -------------

`ifdef SIM
	reg clk_48m_s = 1'b1;
	reg clk_24m_s = 1'b1;

	reg rst_s = 1'b1;

	always #10.42 clk_48m_s <= !clk_48m_s;
	always #20.84 clk_24m_s <= !clk_24m_s;

	initial begin
		#200 rst_s = 0;
	end

	assign clk_48m = clk_48m_s;
	assign clk_24m = clk_24m_s;
	assign rst = rst_s;
`else

	sysmgr sys_mgr_I (
		.clk_in(clk_in),
		.rst_in(1'b0),
		.clk_48m(clk_48m),
		.clk_24m(clk_24m),
		.rst_out(rst)
	);
	
`endif

	// 8MHz clock generation (for YM2610 + shifters)

	localparam [5:0] CLK_8M_PATTERN = 6'b111000;

	reg [2:0] clk8m_shift_n;
	reg [2:0] clk8m_shift_p;

	wire clk_8m_n = clk8m_shift_n[2];
	wire clk_8m_p = clk8m_shift_p[2];
	wire [1:0] clk_8m_ddr = {clk_8m_n, clk_8m_p};

	always @(posedge clk_24m) begin
		if (rst) begin
			clk8m_shift_n <= {CLK_8M_PATTERN[5], CLK_8M_PATTERN[3], CLK_8M_PATTERN[1]};
			clk8m_shift_p <= {CLK_8M_PATTERN[4], CLK_8M_PATTERN[2], CLK_8M_PATTERN[0]};
		end else begin
			clk8m_shift_n <= {clk8m_shift_n[1:0], clk8m_shift_n[2]};
			clk8m_shift_p <= {clk8m_shift_p[1:0], clk8m_shift_p[2]};
		end
	end

	SB_IO #(
		.PIN_TYPE(6'b010000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) ym_clk_sbio (
		.OUTPUT_CLK(clk_24m),
		.INPUT_CLK(clk_24m),

		.PACKAGE_PIN(ym_clk),
		.D_OUT_0(clk_8m_p),
		.D_OUT_1(clk_8m_n)
	);

endmodule // top
