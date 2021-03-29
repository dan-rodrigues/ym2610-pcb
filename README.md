# YM2610 PCB (WIP)

This project allows the user to control a YM2610(B) FM synthesis / ADPCM / SSG sound chip. Software is included to play back YM2610(B) VGM files which includes any Neo Geo arcade game and various others. It can also play certain Sega Genesis tracks using an included converter script. There is also a MIDI input that can be paired with new software to control the synth.

Included is also an SoC implementation for the FPGA (in the `rtl/` directory) and firmware that runs on this SoC (in the `fw/` directory). There's also a set of helper scripts to control the SoC over the USB port.

The goal is to make the complete system both low-cost and flexible which increases the complexity of the FPGA design but allows the use of cheaper hardware (i.e. a $35USD FPGA board and a fairly straightforward PCB).

ADPCM samples are fetched from the FPGA board PSRAM. The host PCB itself doesn't include any extra memory, only some standard logic to mux the PCM buses to the limited number of FPGA IO available.

The iCEBreaker Bitsy USB port is used to upload music data and also for control. The USB stack used and firmware can be customised as needed i.e. to allow a PC MIDI interface to drive the OPNB, or to record the raw digital output to store on a file, or any other possible use.

## Partially assembled PCB (v1.0.0)

![v1.0.0 PCB partially assembled](photo/pcb3.jpg)

## Video/Audio demos

* [Metal Slug 2 soundtrack](https://www.youtube.com/watch?v=nlexW8DgMvw) - Neo Geo VGM playback demo using S/PDIF audio output.
* [Thunder Force IV soundtrack](https://www.youtube.com/watch?v=O-OgxfgEnMU) - Sega Genesis playback demo using analog line-out output.

The Sega Genesis demos are made using a converter script to compensate for incompatible hardware and different clock rates.

## Usage

### Build and flash

This project uses submodules which must be cloned first.

```
git submodule update --init --recursive
```

Building and flashing FPGA bitstream (which implements the SoC):

```
make dfuprog
```

Building and flashing SoC firmware:

```
make -C fw dfuprog
```

### Playing VGM files

After flashing the firmware, the RGB LED should slowly flash indicating that it's ready to use.

```
./scripts/usb_ctrl.py track.vgm
```

## TODO

A new revision of the PCB with many changes to the analog section is also being tested. What's currently in the main branch is out of date but the newer revision will be available in one of the non-default branches.

