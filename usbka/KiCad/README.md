# USBKA schematic

**NOTE: This is a wiring schematic; a PCB layout is still work in progress.**  

## KiCad

[KiCad](https://www.kicad.org) is a free and open source PCB Design Suite.  
This project uses version 9, but should be able to be imported in future versions.  

## Schematic

Open `USBKA.kicad_pro` in KiCad, then open the schematic.  

The sheet shows the wiring for the CBM-II B128/B256 High-Profile DB25 keyboard port.  
A1 and A2 represent the assembled Arduino Mega 2560 and *Mustpoint Ch9350 module*.  
J1 is the male plug on the adapter cable. The MT8816 pin numbers are for the 40-pin DIP chip (MT8816AE1).  

- The Mega's USB supply powers the adapter. The adapter does **not** take power from DB25.
- DB25 pin 22 provides the common ground connection to the CBM-II.
- R1 pulls the active-high RESET node to +5V while Mega D39 is an input. D39 connects directly to U1 pin 3.
- C1 is the 100 nF bypass capacitor for U1. Mount it near U1 pin 40 (VDD).
- Mega D40 shares U1 Y5 and DB25 pin 13 (PC5), as on USBKAV. USBKA leaves D40 as an input without an internal pull-up.
- Connect your USB keyboard to the CH9350L module's USB-A socket. On a *Mustpoint Ch9350 module*, set all five DIP-switches to 1 for *host mode and 115200 baud* (check the PCB for the "1" position; ignore the "ON" label on the DIP-switches). Leave its "485" pin open.

## References

CBM-II [High-Profile keyboard schematics](https://www.zimmers.net/anonftp/pub/cbm/schematics/computers/b/8256059-10.gif).  
MT8816: [MT8816 datasheet, Figure 2 (40-pin DIP)](https://www.mouser.com/datasheet/2/268/Microchip_06182024_MT8816AE1-3459976.pdf#page=2).  
Arduino Mega 2560 Rev3 [pinout](https://docs.arduino.cc/resources/pinouts/A000067-full-pinout.pdf).  
