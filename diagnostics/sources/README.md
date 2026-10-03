# SELECT THE TARGET BUILD

Open the ```mandelbr8.asm``` file. At the beginning, you will find the following lines:

```asm
; Enable only the build you need (set to 1).
BUILD_TYPE_CARTRIDGE = 1    ; Cartridge (@ $2000).
BUILD_TYPE_KERNAL    = 0    ; Kernal (@ $E000).
```

Enable **only** one build at a time.

# BUILD THE BINARY

Use the 64TASS assembler.

### Cartridge build

Build the raw ROM file:

64tass -b -o 324835C.rom -L 324835C.lst -a 324835.asm

If you want a CRT file, use the VICE emulator **cartconv** command line tool after building the raw ROM:  

```cartconv -i 324835C.rom -o 324835C.crt -t cbm2 -l 0x2000```  

Test with VICE emulator:  

```xcbm2.exe -cart2 324835C.rom```  


### Kernal replacement build

Build the raw ROM file:

64tass -b -o 324835K.rom -L 324835K.lst -a 324835.asm  

Test with VICE emulator:  

```xcbm2.exe" -kernal 324835K.rom```  

The resulting Kernal file has been tested working on real B128 and B256 machines using a OneRom 24E flash ROM.

# LICENSE

Creative Commons, CC BY

https://creativecommons.org/licenses/by/4.0/deed.en

Please add a link to this github project.
