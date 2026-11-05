# CBM-II Video Output to HDMI

How to use a HDMI display with your CBM-II machine.  
Tested on B-Series (B128/B256 a.k.a. CBM 600/700).  

**NOTE**: The P500 model uses a different video chip (VIC-II) and a different connector. Do **NOT** use this guide for a P500.  

**NOTE**: This contraption is also compatible with the classic Commodore C128 and can be used to convert the VDC (80 column) output to HDMI.  

![overall](media/overall.jpg)  
*The final solution (High-Profile machines)*

## Ingredients

| **Quantity** | **Item** | **Notes** |
|---:|---|---|
| 1 | [RGBtoHDMI](https://github.com/hoglet67/RGBtoHDMI/wiki) | Including RPi Zero, MicroSD card, and USB cable (power) |
| 1 | [RGBtoHDMI TTL Buffer Board](https://github.com/hoglet67/RGBtoHDMI/wiki/Bill-of-Materials-%28TTL-Buffer-Boards%29) | Get the "EGA/CGA/MDA" one with DE9 female port |
| 1 | DE-9 female to DE-9 female cable | This allows also Commodore 128 VDC compatibility |
| 1 | DE-9 male solder-cup connector ||
| 4 | Wires¹ | 4 female to male (or female) jumper wires |
| 1 (6xx models) | 5-pin DIN male 180° solder-cup connector | **Only on Low-Profile (6xx) machines**|
| 1 (optional) | RGBtoHDMI plastic case ||
| 1 (if needed) | Mini-HDMI (Type C) male to HDMI (Type A) female adapter |You need this if your HDMI cable is Type A at both ends|

¹ I recommend using 4 different wire colors to avoid mistakes.

## Video connector pinout

High-Profile and Low-profile machines have different connectors.  
Pick the right one.  

### High-Profile (7xx models) pinout

The video connector on the motherboard is identified as CN10.  
These machines output 18 kHz video, 14 lines per character.  Similar to IBM MDA.   

![pinout](media/hp_pinout.jpg)  
*Motherboard connections (High-Profile machines)*

| **Pin** | **Signal** | **Wire color in photos**|
|---:|---|---|
| 1 | Video (Luma) |Green|
| 2 | GND ||
| 3 | V-Sync |Yellow|
| 4 | GND ||
| 5 | H-Sync |Orange|
| 6 | [key/missing] ||
| 7 | GND |Black|


### Low-Profile (6xx models) pinout

**NOTE: I do not have a Low-Profile machine, so everything in this chapter is untested, and I have no photos.**

The video connector on the motherboard is identified as J3, a 5-pin DIN female socket mounted on the motherboard.  
These machines output 15 kHz video, 8 lines per character.  Similar to IBM CGA.   

| **Pin** | **Signal** |**Wire color**|
|---:|---|---|
| 1 | Video (Luma) |Green|
| 2 | GND |Black|
| 3 | V-Sync |Yellow|
| 4 | Composite |**[Do NOT use]**|
| 5 | H-Sync |Orange|

**NOTE: You will need to wire the DE9 signals to a 5-pin DIN male connector which will plug into the back side of your Low-Profile machine.**

## The RGBtoHDMI

This is an [open source project](https://github.com/hoglet67/RGBtoHDMI/wiki) using a Raspberry Pi Zero to provide pixel-perfect rescaled video output for several different vintage machines.  
I use it in conjunction with its optional [TTL Buffer Board](https://github.com/hoglet67/RGBtoHDMI/wiki/Bill-of-Materials-%28TTL-Buffer-Boards%29) which provides electrical protection and a DE9 female interface connector for RGBI digital input and can be easily adapted to support different vintage machines such as IBM PC with CGA/EGA/MDA, Commodore 128 VDC (80-column chip) and others.  
You can build everything yourself, or buy it (and the TTL board) already made from different resellers.  

Keep in mind you may have to provide your own Pi Zero, and Micro SD card.
I also recommend getting or 3D-printing a case for it.

![RGBtoHDMI](media/rgbtohdmi.jpg)  
*The RGBtoHDMI three board sandwich*

We'll use a **DE-9 male to DE-9 male cable** (often incorrectly called "DB-9" instead of "DE-9").  
One end of this cable connects directly to the RGBtoHDMI TTL board, and the other end can be connected directly to other vintage machines.  
In our case, the other end will need an adapter (see next chapter).  


## DE9 to B128/B256 adapter

### High-Profile (7xx models) adapter

Wire one end of each of the 4 jumper wires to the DE-9 male solder-cup connector.  
This is the DE-9 pinout:

| **Pin** | **Signal** | **Description** |**Wire color in photos**|
|---:|---|---|---|
| 1 | GND | Ground |Black|
| 4 | G | Video (Luma) |Green|
| 8 | H-Sync | Horizontal sync — TTL |Orange|
| 9 | V-Sync| Vertical sync — TTL |Yellow|


### Low-Profile (6xx models) adapter

Same as for High-Profile, but you'll need to cut the female jumper ends of the wires and solder them to a 5-pin DIN male 180° solder-cup connector that can plug into the external DIN socket on the back of the machine.  
See [Low-Profile (6xx models)](#low-profile-6xx-models-pinout).  

**NOTE:** I don't have a Low-Profile machine, so no pictures are provided.  

## RGBtoHDMI Settings

RGBtoHDMI settings for a particular machine are also called "Profiles", which is a bit confusing because they have nothing to do with "Low" and "High" CBM-II machine profiles.    
RGBtoHDMI profiles are simple text file saved on the MicroSD card.  

### High-Profile (7xx models)

The current RGBtoHDMI firmware does not include a default video profile for CBM-II High-Profile machines.

Copy the .txt files in [this "CBM2" folder](https://github.com/0x444454/cbm2/tree/main/hdmi_out/Profiles/6-12_BIT_RGB/Commodore/CBM2) into the "Commodore" folder of your RGBtoHDMI MicroSD card.

My RGBtoHDMI device uses the "6-12_BIT_RGB" TTL Buffer Board, so the files will be copied as:  

```
/Profiles/6-12_BIT_RGB/Commodore/CBM2/Default.txt
/Profiles/6-12_BIT_RGB/Commodore/CBM2/High-Profile.txt
```

NOTE: You may need to create the CBM2 folder.  

Finally reinsert the MicroSD card into the RGBtoHDMI device, and power-cycle it.
You should now be able to select the new profile.

#### Select the profile

- Enter the RGBtoHDMI menu.
- Go to "Profile".
- Change profile until you see "CBM2". Subprofile should be automatically detected as "High-Profile".

### Low-Profile (6xx models)

These machines output classic 15 kHz video, so they should be already supported.  
Try using "IBM CGA" or "Commodore 128" RGBtoHDMI profiles.


## Embedding SID audio

The RGBtoHDMI supports an optional audio board.  
I prefer to use an external HDMI audio embedder.  


## Power on

After you have double checked everything and made sure there are no shorts, you can power on.  
It may take several seconds to see a boot prompt on screen (especially on the B256).  


## Troubleshooting

### Blank Video

If after a few seconds you cannot see anything on your display, then:
- Verify you can see at least the RGBtoHDMI menu when you press the "MENU" button. If not, then the problem is your RGBtoHDMI device. Make sure the MicroSD card with its firmware is correctly inserted, and USB power is active (check LED).
- Verify that you have selected the CBM2 profile using the RGBtoHDMI menu.
- Make sure your video chip is working. The MOS 6545A video chip mounted on most boards is prone to failure. You can replace it directly with a Motorola 68B45P.

### Flashing green or garbage on screen

Make sure you have [selected the correct "CBM2" profile](#select-the-profile).

## FAQ

**Q.** Can I use this contraption to convert a classic Commodore 128 (VDC 80-column output) to HDMI ?  
**A.** Yes. Remove the _DE9 to CBM-II adapter_ at the DE9 cable end and plug the DE9 cable end directly into the C128 HDMI port. Remember to select the right C128 RGBtoHDMI profile for your PAL/NTSC machine.  
  
**Q.** Isn't the connector type "DB9" instead of "DE9" ?  
**A.** No. But some people/manufacturers call it "DB9" anyway.  


# LICENSE

Creative Commons, CC BY

https://creativecommons.org/licenses/by/4.0/deed.en

Please add a link to this github project.
