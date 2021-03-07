/*
 * usb_desc_app.c
 *
 * Copyright (C) 2020 Sylvain Munaut
 * Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
 * All rights reserved.
 *
 * LGPL v3+, see LICENSE.lgpl3
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#include <no2usb/usb_proto.h>
#include <no2usb/usb_dfu_proto.h>
#include <no2usb/usb.h>

static const struct {
	/* Configuration */
	struct usb_conf_desc conf;

	/* DFU Runtime */
	struct {
		struct usb_intf_desc intf;
		struct usb_dfu_func_desc func;
	} __attribute__ ((packed)) dfu;

	/* YMU */
	struct {
		struct usb_intf_desc intf;
		struct usb_cc_ep_desc ep_data;
		struct usb_cc_ep_desc ep_status;
	} __attribute__ ((packed)) ymu;

} __attribute__ ((packed)) _app_conf_desc = {
	.conf = {
		.bLength                = sizeof(struct usb_conf_desc),
		.bDescriptorType        = USB_DT_CONF,
		.wTotalLength           = sizeof(_app_conf_desc),
		.bNumInterfaces         = 2, // +1 for DFU (TODO: resolve issues)
		.bConfigurationValue    = 1,
		.iConfiguration         = 4,
		.bmAttributes           = 0x80,
		.bMaxPower              = 500 / 2, // 500mA
	},
	.dfu = {
		.intf = {
			.bLength		    = sizeof(struct usb_intf_desc),
			.bDescriptorType	= USB_DT_INTF,
			.bInterfaceNumber	= 0,
			.bAlternateSetting	= 0,
			.bNumEndpoints		= 0,
			.bInterfaceClass	= 0xfe,
			.bInterfaceSubClass	= 0x01,
			.bInterfaceProtocol	= 0x01,
			.iInterface		     = 5,
		},
		.func = {
			.bLength		    = sizeof(struct usb_dfu_func_desc),
			.bDescriptorType	= USB_DFU_DT_FUNC,
			.bmAttributes		= 0x0d,
			.wDetachTimeOut		= 1000,
			.wTransferSize		= 4096,
			.bcdDFUVersion		= 0x0101,
		},
	},
	.ymu = {
		.intf = {
			.bLength		    = sizeof(struct usb_intf_desc),
			.bDescriptorType	= USB_DT_INTF,
			.bInterfaceNumber	= 1,
			.bAlternateSetting	= 0,
			.bNumEndpoints		= 2,
			.bInterfaceClass	= USB_CLS_VENDOR_SPECIFIC,
			.bInterfaceSubClass	= 0x00,
			.bInterfaceProtocol	= 0x00,
			.iInterface		    = 4,
		},
		.ep_data = {
			.bLength		     = sizeof(struct usb_cc_ep_desc),
			.bDescriptorType	= USB_DT_EP,
			.bEndpointAddress	= 0x02, // EP2 - Out
			.bmAttributes		= 0x02, // Bulk
			.wMaxPacketSize		= 64,
			.bInterval		    = 0,
			.bRefresh		    = 0,
			.bSynchAddress		= 0,
		},
		.ep_status = {
			.bLength		     = sizeof(struct usb_cc_ep_desc),
			.bDescriptorType	= USB_DT_EP,
			.bEndpointAddress	= 0x83, // EP3 - In
			.bmAttributes		= 0x03, // Interrupt
			.wMaxPacketSize		= 64,
			.bInterval		    = 0,
			.bRefresh		    = 0,
			.bSynchAddress		= 0,
		}
	},
};

static const struct usb_conf_desc * const _conf_desc_array[] = {
	&_app_conf_desc.conf,
};

static const struct usb_dev_desc _dev_desc = {
	.bLength		    = sizeof(struct usb_dev_desc),
	.bDescriptorType	= USB_DT_DEV,
	.bcdUSB			    = 0x0200,
	.bDeviceClass		= 0,
	.bDeviceSubClass	= 0,
	.bDeviceProtocol	= 0,
	.bMaxPacketSize0	= 64,
	.idVendor		    = 0x1d50,
	.idProduct		    = 0x6147,
	.bcdDevice		    = 0x0001,	/* v0.1 */
	.iManufacturer		= 2,
	.iProduct		    = 3,
	.iSerialNumber		= 1,
	.bNumConfigurations	= num_elem(_conf_desc_array),
};

#include "usb_str_app.gen.h"

const struct usb_stack_descriptors app_stack_desc = {
	.dev = &_dev_desc,
	.conf = _conf_desc_array,
	.n_conf = num_elem(_conf_desc_array),
	.str = _str_desc_array,
	.n_str = num_elem(_str_desc_array),
};
