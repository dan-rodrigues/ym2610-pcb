// vgm.h
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

#ifndef vgm_h
#define vgm_h

struct vgm_player_context {
	bool initialized;
	uint32_t index;
	uint32_t buffer_index;
	uint32_t loop_offset;
	uint32_t loop_count;

	bool write_active;
	uint32_t last_write_index;

	bool filter_fm_key_on;
	bool filter_fm_pitch;
};

struct vgm_update_result {
	bool buffering_needed;
	uint32_t buffer_target_offset;

	uint32_t vgm_start_offset;
	uint32_t vgm_chunk_length;
};

void vgm_write(uint8_t *data, size_t offset, size_t length);
void vgm_pcm_write(uint32_t *data, size_t offset, size_t length);

void vgm_init_playback(struct vgm_player_context *context);

void vgm_continue_playback(struct vgm_player_context *ctx, struct vgm_update_result *update_result);

#endif
