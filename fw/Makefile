BOARD ?= bitsy-v1
CROSS ?= riscv-none-embed-
CC = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
ICEPROG = iceprog
DFU_UTIL = dfu-util

BOARD_DEFINE=BOARD_$(shell echo $(BOARD) | tr a-z\- A-Z_)
CFLAGS=-Wall -Wextra -Wno-unused-parameter -Os -march=rv32i -mabi=ilp32 -ffreestanding -flto -nostartfiles -fomit-frame-pointer -Wl,--gc-section --specs=nano.specs -D$(BOARD_DEFINE) -I.

# Common / Shared
COMMON_PATH=common/
CFLAGS += -I$(COMMON_PATH)

HEADERS_common=$(addprefix $(COMMON_PATH), \
	console.h \
	led.h \
	mini-printf.h \
	utils.h \
)

SOURCES_common=$(addprefix $(COMMON_PATH), \
	start.S \
	console.c \
	led.c \
	mini-printf.c  \
	utils.c \
)


# USB
NO2USB_FW_VERSION=0
include ../no2fpga/cores/no2usb/fw/fw.mk
CFLAGS += $(INC_no2usb)

SOURCES_common += $(SOURCES_no2usb)
HEADERS_common += $(HEADERS_no2usb)


# Local
HEADERS_app=\
	config.h \
	ym_usb.h \
	usb_str_app.gen.h \
	spi_mem.h \
	mem_util.h \
	midi.h \
	buttons.h \
	ym2610/vgm.h \
	ym2610/vgm_timer.h \
	ym2610/ym_ctrl.h \
	ym2610/fm.h \
	ym2610/ssg.h \
	ym2610/pcm.h \
	ym2610/pcm_mux.h \
	ym2610/ym_dbg_dac.h \
	$(NULL)

SOURCES_app=\
	ym_usb.c \
	spi_mem.c \
	mem_util.c \
	midi.c \
	buttons.c \
	fw_app.c \
	usb_desc_app.c \
	ym2610/vgm.c \
	ym2610/vgm_timer.c \
	ym2610/ym_ctrl.c \
	ym2610/fm.c \
	ym2610/ssg.c \
	ym2610/pcm.c \
	ym2610/pcm_mux.c \
	ym2610/ym_dbg_dac.c \
	$(NULL)

all: boot.hex fw_app.bin

boot.elf: lnk-boot.lds boot.S
	$(CC) $(CFLAGS) -Wl,-Bstatic,-T,lnk-boot.lds,--strip-debug -DFLASH_APP_ADDR=0x000a0000 -o $@ boot.S

fw_app.elf: $(COMMON_PATH)/lnk-app.lds $(HEADERS_app) $(SOURCES_app) $(HEADERS_common) $(SOURCES_common)
	$(CC) $(CFLAGS) -Wl,-Bstatic,-T,$(COMMON_PATH)/lnk-app.lds,--strip-debug,--defsym=SPRAM128K=1 -o $@ $(SOURCES_common) $(SOURCES_app)

%.hex: %.bin
	$(COMMON_PATH)/bin2hex.py $< $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

prog: fw_app.bin
	$(ICEPROG) -o 640k $<

dfuprog: fw_app.bin
ifeq ($(DFU_SERIAL),)
	$(DFU_UTIL) -R -a 1 -D $<
else
	$(DFU_UTIL) -R -S $(DFU_SERIAL) -a 1 -D $<
endif

# Custom rules:

HEADER_GEN := ../header_gen/header_gen

$(HEADER_GEN):
	make -C ../header_gen

%.h %.c: %.vgm $(HEADER_GEN)
	$(HEADER_GEN) -t uint8_t -s -i $(basename $(@F)) -o $* $*.vgm

dasm: fw_app.elf
	$(CROSS)objdump -d $(DFLAGS) fw_app.elf > dasm

clean:
	rm -f *.bin *.hex *.elf *.o *.gen.h

.PHONY: prog_app clean
