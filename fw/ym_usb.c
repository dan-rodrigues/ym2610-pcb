// ym_usb.c
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include <no2usb/usb.h>
#include <no2usb/usb_ac_proto.h>
#include <no2usb/usb_dfu_rt.h>
#include <no2usb/usb_hw.h>
#include <no2usb/usb_priv.h>

#include "ym_usb.h"

#include "config.h"
#include "console.h"
#include "mini-printf.h"
#include "utils.h"
#include "mem_util.h"

static uint8_t bd_index;

static enum ymu_write_mode write_mode;
static size_t start_offset;
static size_t write_offset;
static size_t end_offset;
static bool write_active;
static uint32_t sequence_counter;

static bool playback_start_pending;

static void ymu_enable_write(void);
static void ymu_disable_write(void);

static bool ymu_send_status(const uint32_t *status);

enum ymu_ctrl_req {
	YMU_CTRL_READ_STATUS = 0x80,

	YMU_CTRL_SET_WRITE_MODE = 0x00,
	YMU_CTRL_START_PLAYBACK = 0x01
};

static enum usb_fnd_resp ymu_set_conf(const struct usb_conf_desc *conf) {
	start_offset = 0;
	write_offset = 0;
	end_offset = 0;
	playback_start_pending = false;
	write_active = false;
	ymu_enable_write();

	return USB_FND_SUCCESS;
}

static void ymu_disable_write() {
	usb_ep_regs[2].out.status = 0;
}

static void ymu_enable_write() {
	bd_index = 0;

	// EP2: out, bulk, double buffered
	usb_ep_regs[2].out.status = USB_EP_TYPE_BULK | USB_EP_BD_DUAL;

	// EP3: in, interrupt, single buffered
	usb_ep_regs[3].in.status = USB_EP_TYPE_INT;

	// Prepare 2 buffers
	usb_ep_regs[2].out.bd[0].ptr = 1024;
	usb_ep_regs[2].out.bd[0].csr = USB_BD_STATE_RDY_DATA | USB_BD_LEN(64);
	usb_ep_regs[2].out.bd[1].ptr = 1024 + 64;
	usb_ep_regs[2].out.bd[1].csr = USB_BD_STATE_RDY_DATA | USB_BD_LEN(64);
}

// FIXME: try again if request is stalled for whatever reason
// or spin if there's no waiting, pretty unlikely to be an event pending except for bugs
static bool ymu_send_status(const uint32_t *status) {
	uint32_t csr = usb_ep_regs[3].in.bd[0].csr;
	uint32_t state = csr & USB_BD_STATE_MSK;

	if (state == USB_BD_STATE_RDY_DATA) {
		printf("ymu_send_status: data pending...\n");
		return false;
	}

	uint32_t buffer_offset = 1280;
	usb_data_write(buffer_offset, status, 16);

	usb_ep_regs[3].in.bd[0].ptr = buffer_offset;
	usb_ep_regs[3].in.bd[0].csr = USB_BD_STATE_RDY_DATA | USB_BD_LEN(16);

	return true;
}

bool ymu_request_vgm_buffering(uint32_t target_offset, uint32_t vgm_start_offset, uint32_t vgm_chunk_length) {
	const uint32_t buffer_request_header = 0x01;

	uint32_t header = buffer_request_header | sequence_counter << 8;
	sequence_counter++;
	sequence_counter &= 0xffffff;

	const uint32_t data[4] = {
		header,
		target_offset,
		vgm_start_offset,
		vgm_chunk_length
	};

	return ymu_send_status(data);
}

bool ymu_report_status(uint32_t status) {
	const uint32_t status_header = 0x02;
	const uint32_t data[4] = {
		status_header,
		0, 0, 0
	};

	return ymu_send_status(data);
}

void ymu_reset_sequence_counter() {
	sequence_counter = 0;
}

// Only 32bit aligned addresses seem to be handled by usb_data_read()

size_t ymu_data_poll(uint32_t *data, size_t *offset, enum ymu_write_mode *mode, size_t max_length) {
	if (!write_active) {
		return 0;
	}

	if (usb_ep_regs[2].out.status == 0) {
		return 0;
	}

	/* EP BD Status */
	uint32_t ptr = usb_ep_regs[2].out.bd[bd_index].ptr;
	uint32_t csr = usb_ep_regs[2].out.bd[bd_index].csr;

	/* Check if we have a USB packet */
	if ((csr & USB_BD_STATE_MSK) == USB_BD_STATE_RDY_DATA)
		return 0;

	size_t len = 0;

	/* Valid data ? */
	if ((csr & USB_BD_STATE_MSK) == USB_BD_STATE_DONE_OK) {
		len = (csr & USB_BD_LEN_MSK) - 2; /* Reported length includes CRC */
		size_t next_write_offset = write_offset + len;
		if (next_write_offset > end_offset) {
			printf("ymu_data_poll: received more bytes than expected\n");
			// TODO: determine if .csr below should be set regardless
			ymu_disable_write();
			return 0;
		}

		if (len == 0) {
			printf("USB reported length == 0?\n");
		} else if (len > max_length) {
			printf("USB reported length > max length\n");
		} else {
			usb_data_read(data, ptr, len);
			*offset = write_offset;
			*mode = write_mode;
		}

		if (end_offset == next_write_offset) {
			printf("ymu_data_poll: read complete (%x bytes total)\n",
				   end_offset - start_offset);
			write_active = false;
		}

		write_offset = next_write_offset;
	} else {
		printf("ymu_data_poll: invalid data?\n");
		return 0;
	}

	// Allow next packet
	usb_ep_regs[2].out.bd[bd_index].csr = USB_BD_STATE_RDY_DATA | USB_BD_LEN(64);
	bd_index ^= 1;

	return len;
}

bool ymu_playback_start_pending() {
	// Control request to start playback may arrive before remaining data does
	if (write_active) {
		return false;
	}

	bool was_pending = playback_start_pending;
	playback_start_pending = false;

	return was_pending;
}

// Shared USB driver
// ---------------------------------------------------------------------------

// Control request handling:

typedef bool (*usb_control_fn)(uint16_t wValue, uint8_t *data, int *len);

static struct {
	struct usb_ctrl_req *req;
	usb_control_fn fn;
} g_cb_ctx;

static bool ymu_ctrl_req_cb(struct usb_xfer *xfer) {
	struct usb_ctrl_req *req = g_cb_ctx.req;
	usb_control_fn fn = g_cb_ctx.fn;
	return fn(req->wValue, xfer->data, &xfer->len);
}

static bool ymu_ctrl_set_write_mode(uint16_t wValue, uint8_t *data, int *len) {
	if (wValue != YMU_WM_PCM_A && wValue != YMU_WM_PCM_B && wValue != YMU_WM_VGM) {
		printf("ymu_ctrl_set_write_mode: unexpected write mode: %x\n", wValue);
		return false;
	}

	if (*len != 8) {
		printf("ymu_ctrl_set_write_mode: expected 8 bytes of data (got %x)\n", *len);
		return false;
	}

	start_offset = read32(&data[0]);
	write_offset = start_offset;
	size_t write_length = read32(&data[4]);
	end_offset = write_offset + write_length;

	if (write_length == 0) {
		printf("ymu_ctrl_set_write_mode: expected non-zero write length\n");
		return false;
	}

	write_mode = (enum ymu_write_mode)(wValue & 0xff);
	printf("ymu_ctrl_set_write_mode: start address: %x\n", write_offset);
	printf("ymu_ctrl_set_write_mode: write length: %x\n", write_length);
	printf("ymu_ctrl_set_write_mode: set write_mode to: %x\n", write_mode);

	write_active = true;

	return true;
}

// Functions of reach control request:

typedef enum usb_fnd_resp (*ym_ctrl_handler)(struct usb_ctrl_req *req, struct usb_xfer *xfer);

static enum usb_fnd_resp ymu_ctrl_read_status(struct usb_ctrl_req *req, struct usb_xfer *xfer) {
	// (Temporary dummy status read)
	xfer->data[0] = 0x55;
	xfer->data[1] = 0xaa;
	return USB_FND_SUCCESS;
}

static enum usb_fnd_resp ymu_ctrl_start_playback(struct usb_ctrl_req *req, struct usb_xfer *xfer) {
	playback_start_pending = true;
	return USB_FND_SUCCESS;
}

static enum usb_fnd_resp ymu_ctrl_defer_set_write_mode(struct usb_ctrl_req *req, struct usb_xfer *xfer) {
	// Request is a write, we need to hold off until end of data phase
	g_cb_ctx.req = req;
	g_cb_ctx.fn = ymu_ctrl_set_write_mode;
	xfer->len = req->wLength;
	xfer->cb_done = ymu_ctrl_req_cb;
	return USB_FND_SUCCESS;
}

struct ym_ctrl_handler {
	enum ymu_ctrl_req request;
	bool is_read;
	ym_ctrl_handler handler;
};

static const struct ym_ctrl_handler ctrl_handlers[] = {
	{.request = YMU_CTRL_READ_STATUS, .is_read = true, .handler = ymu_ctrl_read_status},
	{.request = YMU_CTRL_START_PLAYBACK, .is_read = false, .handler = ymu_ctrl_start_playback},
	{.request = YMU_CTRL_SET_WRITE_MODE, .is_read = false, .handler = ymu_ctrl_defer_set_write_mode}
};
static const size_t ym_ctrl_handler_count = sizeof(ctrl_handlers) / sizeof(ym_ctrl_handler);

// Control request dispatch:

static enum usb_fnd_resp ymu_ctrl_req(struct usb_ctrl_req *req, struct usb_xfer *xfer) {
	printf("Received control request: %X\n", req->bRequest);

	if (USB_REQ_TYPE(req) != USB_REQ_TYPE_VENDOR) {
		return USB_FND_CONTINUE;
	}
	if ((req->bmRequestType ^ req->bRequest) & 0x80
		|| req->wIndex != 0
		|| USB_REQ_RCPT(req) != USB_REQ_RCPT_INTF)
	{
		return USB_FND_ERROR;
	}

	for (uint32_t i = 0; i < ym_ctrl_handler_count; i++) {
		const struct ym_ctrl_handler *ctx = &ctrl_handlers[i];

		if (ctx->request != req->bRequest) {
			continue;
		}

		if (USB_REQ_IS_READ(req) ^ ctx->is_read) {
			printf("Control request RW type mismatch\n");
			return USB_FND_ERROR;
		}

		return ctx->handler(req, xfer);
	}

	printf("Couldn't find match control request handler\n");
	return USB_FND_ERROR;
}

// Shared driver definition:

static struct usb_fn_drv _ymu_drv = {
	.ctrl_req = ymu_ctrl_req,
	.set_conf = ymu_set_conf,
	.set_intf = NULL,
	.get_intf = NULL
};

// Exposed API
// ---------------------------------------------------------------------------

void ymu_init(void) {
	/* Register function driver */
	usb_register_function_driver(&_ymu_drv);
	ymu_reset_sequence_counter();
}
