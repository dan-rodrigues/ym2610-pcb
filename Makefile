# Project config
PROJ = ym2610_pcb

PROJ_DEPS := no2usb no2misc no2ice40
PROJ_RTL_SRCS := $(addprefix rtl/, \
	dfu_helper.v \
	picorv32.v \
	picorv32_ice40_regs.v \
	soc_bram.v \
	soc_picorv32_base.v \
	soc_picorv32_bridge.v \
	soc_spram.v \
	soc_usb.v \
	sysmgr.v \
	spi_mem.v \
	vgm_timer.v \
	buttons.v \
	debouncer.v \
	ym2610/ym2610_ctrl.v \
	ym2610/ym2610_pcm_mux_ctrl.v \
	ym2610/ym3016.v \
	ym2610/adpcm_b_reader.v \
	ym2610/adpcm_a_reader.v \
	spdif_tx.v \
)
PROJ_SIM_SRCS := $(addprefix sim/, \
	spiflash.v \
	ym2610_mock.v \
	ym2610_pcm_mux.v \
	tbuart.v \
)
PROJ_SIM_SRCS += rtl/top.v
PROJ_TESTBENCHES := \
	ym_tb
PROJ_PREREQ = \
	$(BUILD_TMP)/boot.hex
PROJ_TOP_SRC := rtl/top.v
PROJ_TOP_MOD := top

# Target config
BOARD ?= bitsy-v1
DEVICE := $(shell awk '/^\#\# dev:/{print $$3; exit 1}' data/top-$(BOARD).pcf && echo up5k)
PACKAGE := $(shell awk '/^\#\# pkg:/{print $$3; exit 1}' data/top-$(BOARD).pcf && echo sg48)

YOSYS_SYNTH_ARGS = -dffe_min_ce_use 4 -dsp
NEXTPNR_ARGS = --pre-pack data/clocks.py --seed 2

# Include default rules
include no2fpga/build/project-rules.mk

# Custom rules
fw/boot.hex:
	make -C fw boot.hex

$(BUILD_TMP)/boot.hex: fw/boot.hex
	cp $< $@
