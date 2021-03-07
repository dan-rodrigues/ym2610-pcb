// ym_tb.v
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

`default_nettype none

module ym_tb;

	// Signals
	// -------

	wire [3:0] spi_io;
	wire       spi_clk;
	wire [1:0] spi_cs_n;

	wire usb_dp;
	wire usb_dn;
	wire usb_pu;

	wire uart_rx;
	wire uart_tx;


	// Setup recording
	// ---------------

	initial begin
		$dumpfile("ym_tb.vcd");
		$dumpvars(0,ym_tb);
		# 10000000 $finish;
	end


	// DUT
	// ---

	wire ym_clk;
	wire ym_ctrl_shift_out;
	wire ym_ctrl_shift_load;

	// For testing, eitehr device activates shared flash, could split them
	wire spi_flash_cs_n;
	wire spi_ram_cs_n;

	wire [3:0] ym_io;
	wire [2:0] mux_sel;
	wire pcm_load;
	wire rmpx_fpga;
	wire pmpx_fpga;
	wire mux_oe_n;

	top dut_I (
		.spi_io   (spi_io),
		.spi_clk  (spi_clk),
		.spi_flash_cs_n (spi_flash_cs_n),
		.spi_ram_cs_n (spi_ram_cs_n),

		.usb_dp(usb_dp),
		.usb_dn(usb_dn),
		.usb_pu(usb_pu),
		.uart_rx(uart_rx),
		.uart_tx(uart_tx),
		.rgb(),
		.clk_in(1'b0),

		.ym_clk(ym_clk),
		.ym_shift_out(ym_ctrl_shift_out),
		.ym_shift_load(ym_ctrl_shift_load),

		.ym_io(ym_io),
		.mux_sel(mux_sel),
		.mux_oe_n(mux_oe_n),
		.pcm_load(pcm_load),
		.rmpx(rmpx_fpga),
		.pmpx(pmpx_fpga)
	);

	// UART
	// ----

	tbuart uart(
		.ser_rx(uart_tx)
	);

	// YM2610 mocks for testing
	// ------------------------

	wire ym_ic_n;

	ym_ctrl_mock ym_ctrl_mock(
		.clk(ym_clk),

		.shift_in(ym_ctrl_shift_out),
		.shift_load(ym_ctrl_shift_load),

		// TODO: address / ctrl outputs to 2610 below
		// ...

		.ic_n(ym_ic_n)
	);

	// Mock for PCM mux (on PCB):

	ym2160_pcm_mux ym2160_pcm_mux(
		// FPGA IO

		.ym_io(ym_io),
		.mux_sel(mux_sel),
		.mux_oe_n(mux_oe_n),
		.pcm_load(pcm_load),
		.rmpx_out(rmpx_fpga),
		.pmpx_out(pmpx_fpga),

		// YM2610 IO

		.rad(rad),
		.ra8(ra9_8[0]),
		.ra9(ra9_8[1]),
		.ra20(ra23_20[0]),
		.ra21(ra23_20[1]),
		.ra22(ra23_20[2]),
		.ra23(ra23_20[3]),
		.rmpx(rmpx),
		.roe_n(roe),

		.pad(pad),
		.pa8(pa11_8[0]),
		.pa9(pa11_8[1]),
		.pa10(pa11_8[2]),
		.pa11(pa11_8[3]),
		.pmpx(pmpx),
		.poe_n(poe)
	);

	// Mock for PCM address generation:

	// ADPCM-A

	reg [23:0] a_address;

	wire [7:0] rad;
	wire [1:0] ra9_8;
	wire [3:0] ra23_20;

	wire roe;
	wire rmpx;

	// ADPCM-B

	wire [7:0] pad;
	wire [3:0] pa11_8;

	wire poe;
	wire pmpx;

	// Read data test

	wire [23:0] a_read_address;
	wire [7:0] a_read_data;
	wire a_read_complete;
	
	ym2160_mock #(
		.ENABLE_ADPCM_A(1),
		.ENABLE_ADPCM_B(1)
	) ym2610 (
		.clk(ym_clk),
		.ic_n(ym_ic_n),

		.rad(rad),
		.ra9_8(ra9_8),
		.ra23_20(ra23_20),
		.rmpx(rmpx),
		.roe(roe),

		.pad(pad),
		.pa11_8(pa11_8),
		.pmpx(pmpx),
		.poe(poe),

		// Test

		.a_read_address(a_read_address),
		.a_read_data(a_read_data),
		.a_read_complete(a_read_complete)
	);

	// Support
	// -------

	pullup(usb_dp);
	pullup(usb_dn);

	pullup(uart_tx);
	pullup(uart_rx);

	spiflash flash_I (
		.csb(spi_flash_cs_n && spi_ram_cs_n),
		.clk(spi_clk),
		.io0(spi_io[0]),
		.io1(spi_io[1]),
		.io2(spi_io[2]),
		.io3(spi_io[3])
	);

endmodule // top_tb

// TODO: relocate

module ym_ctrl_mock(
	input clk,

	input shift_in,
	input shift_load,

	// YM2610 outputs

	output ic_n
);
	reg [12:0] shift = 0;
	reg [12:0] mem = 0;

	always @(posedge clk) begin
		shift <= {shift[11:0], shift_in};
	end

	always @(posedge shift_load) begin
		mem <= shift;
	end

	wire [7:0] ym_data = mem[7:0];
	wire [1:0] ym_address = mem[9:8];
	wire ym_wrn = mem[10];
	wire ym_csn = mem[11];
	assign ic_n = mem[12];

	always @* begin
		$display(
			"YM CTRL: data: %x, addr: %d, wr_n: %d, ic_n: %d, cs_n: %d",
			ym_data, ym_address, ym_wrn, ic_n, ym_csn
			);
	end

endmodule
