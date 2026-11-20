# CBM-II (B128/B256) SID player

Play C64 SID tunes on your CBM-II computer.  
Currently supports B128/B256 only.  

![screenshot](media/screenshot.png)

## F.A.Q. / Troubleshooting

**Q.** Are tunes playing samples supported ?  
**A.** Some ways of playing samples are supported (e.g. _Giana Sisters_, _BMX Kidz_).  

**Q.** My modern SID replacement is not working.  
**A.** Make sure it supports 2 MHz operation, and you have installed the latest firmware upgrade.  

**Q.** The filter does not sound right, or leads sound muffled.  
**A.** This is because the filter capacitors installed on CBM-II machines are 2200 pF, like in a few early C64 machines (most Silver Label ones). You may try replacing them with 470 pF, as used by most C64 machines.  If this does not help, your SID may be faulty.  

**Q.** Some tunes are not played correctly.  
**A.** SID tunes are made to run on a C64 on a 1 MHz chip.  The C64 hardware is partially emulated, but not completely.  Some advanced SID tunes will not play correctly (or even hang the machine).  

**Q.** Are multiple SID chips supported ?  
**A.** No.  

**Q.** Some tunes require special C64 hardware features you have not emulated. Any workaround ?  
**A.** Play them on a C64.  :-)  

**Q.** My SID 6581 is missing/defective.  Can I replace it with a SID 8580 ?  
**A.** No. Without a specific adapter you will damage your 8580 chip.  Also, I am not sure an 8580 will work at 2 MHz.  


# LICENSE

Creative Commons, CC BY

https://creativecommons.org/licenses/by/4.0/deed.en

Please add a link to this github project.
