# PCB

Included is the schematic and PCB layout of the board.

## Usage

Most ICs on the board are optional but a few are required in any case:

* 2x 74AHCT595: Shift registers to control the YM2610(B) and reset both the 2610 and the 3016.
* 1x 74LV1T34: Clock buffer, also shifts the 8MHz clock from 3.3v to 5v.

If ADPCM-A/B playback is needed, then these are required:

* 4x 74HCT153
* 1x 74LVC257
* 1x 74LVC2G08
* 1x 74LVC244

The analog section is optional assuming the SSG sound source isn't needed. To listen to the digital sound sources using S/PDIF output, there are optional optical and coax outputs. The coax output does not use a pulse transformer and one can be added if needed. 

## License

CERL-OHL-S-2.0. There is a copy of the text included in the licenses/ directory in the root of this repo. License text can also be found [here](https://ohwr.org/cern_ohl_s_v2.txt).

