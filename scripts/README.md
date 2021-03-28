# Scripts

These python scripts can be used in one of two ways:

## USB driver

To upload a YM2610 VGM file and start playback:

```
./usb_ctrl.py <vgm_file_to_play>
```

## VGM converter

A wrapper script can be used to do limited conversion of a YM2612 + SN76489 VGM to a YM2610B VGM. The output could also be played on a YM2608 since they have common FM / SSG sound sources. Note that the regular YM2610 (non-B variant) can play the result but only with 4 out of 6 FM channels.

* All OPN FM pitches are converted according to the input clock to an assumed 8MHz output clock so clock differences should not change the effective pitch.
* PSG square waves are replaced with equivalent SSG square waves with pitch adjustment.

Because the SN76489 and YM2149 don't have identical features, the conversion is only partial. There is currently no attempt to convert noise playback.

```
./vgm_convert.py <input_vgm> <output_vgm>
```

