; DDT's improved CBM-II B-series diagnostics, with Kernal replacement option.
; Based on the original Commodore 324835-1 cartridge.
;
; This can be built as a Cartridge or as a diagnostic replacement Kernal.
;
; https://github.com/0x444454/cbm2/tree/main/diagnostics
;
; Use 64TASS Assembler.
;
; Revision history [authors in square brackets]:
;   1983-??-?? (version 324835-1): Commodore original version.
;   2026-10-01 (version 324835-2): Disassembled, analyzed, commented, added Kernal replacement mode and 24-bit ROMs checksum. [DDT]
;
        .cpu "6502"     ; No love for "6509" in 64TASS :-)

; IMPORTANT NOTE: Select one and only one build type.
BUILD_TYPE_PRG       = 0    ; Executable program. **** WARNING **** ALPHA CODE, NOT YET WORKING !!!
BUILD_TYPE_CARTRIDGE = 1    ; Cartridge (@ $2000).
BUILD_TYPE_KERNAL    = 0    ; Kernal (@ $E000).


; Check build type because no one reads important notes ! :-)
;
CHECK_BUILD = BUILD_TYPE_PRG + BUILD_TYPE_CARTRIDGE + BUILD_TYPE_KERNAL
.if CHECK_BUILD < 1 || CHECK_BUILD > 1
    .error "ENABLE ONE AND ONLY ONE BUILD."
.endif


.if BUILD_TYPE_PRG
; ----------------- PRG BUILD ONLY -----------------
        * = $03             ; BASIC code start location (BANK 1).
; BASIC programming in hex is fun !
; We POKE-in this machine-code (4 bytes) to change code execution from BANK 15 (KERNAL and BASIC) to BANK 1, where this PRG has been loaded:
; >     LDA #$01            ; We are in BANK 15 (at the moment).
; >     STA $00             ; Change Execution BANK to 1.
;
    .word end_BASIC
    .word 10
    .text                             $97,$34,$31,$2C,$31,$36,$39,$3A,$97 ; "POKE41,169:POKE"
    .text $34,$32,$2C,$31,$3A,$97,$34,$33,$2C,$31,$33,$33,$3A,$97,$34,$34 ; "42,1:POKE43,133:POKE44"
    .text $2c,$30,$3A
    .byte $9E           ; "SYS"
    .text "41",$00      ; "41"
end_BASIC:
    .word 0
    ; *** WARNING *** DO NOT INSERT ANYTHING HERE.
entry_from_BASIC:
        ; This is address 41. Execution starts here.
        ; 4 NOPs (4 bytes) to align assembler code after POKEd-in bank switch.
        NOP
        NOP
        NOP
        NOP
        ; We are currently in BANK 1, so we need to copy test code to SRAM (BANK 15).
        ;
        sei
        lda  #$0F
        sta  $01            ; Indirection BANK 15.
     
        ; We are running in BANK 1.
RELOC_START = $0002       
        lda  #<RELOC_START
        sta  $10
        lda  #>RELOC_START
        sta  $11
        ; Offsets.
        ldx  #0             ; X = 0.
        ldy  #0             ; Y = 0.
        lda  #(cycle_code_END-RELOC_START+255)/256 ; Number of pages to copy.
        sta  $12            ; Remaining number of pages to copy.
reloc_loop:
        lda  ($10,x)        ; Load from bank 1 (DRAM).
        sta  ($10),y        ; Store to bank 15 (SRAM).
        inc  $10
        bne  reloc_loop
        inc  $11
        dec  $12            ; Dec remaining number of pages to copy.
        bne  reloc_loop
reloc_done:
        ; Switch Execution to BANK 15 (SRAM).
        LDA  #$0F
        STA  $00            ; Execution BANK 15.
        
.elif BUILD_TYPE_CARTRIDGE
; ----------------- CARTRIDGE BUILD ONLY -----------------
        * = $2000           ; ORG of KERNAL ROM. Set to $2000 for cartridge.
cartridge_header:
        jmp  main           ; Cold start entry point (cartridge).
LE003:
        jmp  main           ; Warm start entry point (cartridge).

; CBM2 cartridge signature bytes (C, PETSCII B/M with bit 7 set, ASCII 2); skipped by the jump above.
cbm2_rom_signature:
        .byte $43, $C2, $CD, $32

.elif BUILD_TYPE_KERNAL
; ----------------- KERNAL BUILD ONLY -----------------
        * = $E000           ; ORG of KERNAL ROM. Set to $2000 for cartridge.
.endif
;
; *** WARNING *** DO NOT INSERT ANYTHING HERE.
;
; Main entry point:
; - Select indirection BANK 15 (SRAM and I/O).
; - Initialize the stack and disable decimal arithmetic (if needed by build type).
main:
        sei                 ; Disable interrupts.
        lda  #$0F
        sta  $01            ; Indirection BANK 15.
        ldx  $FF
        txs                 ; Stack top = $1FF.
        ; Set IRQ RAM vectors.
        lda  #<diag_rti
        sta  $0304
        lda  #>diag_rti
        sta  $0305
        lda  #<diag_irq_default
        sta  $0300
        sta  $0302
        lda  #>diag_irq_default
        sta  $0301
        sta  $0303
        ; Clear decimal mode.
        cld
        ldy  #$11

        lda  $DF02          ; Fetch CRT mode (bit 7) from 6525-B.
        bmi  set_timing_HP  ; If set, this is a HP (7xx) machine.
        
        ; Set timing for LP machines (6xx).
-       lda  crtc_timing_LP,y
        sty  $D800
        sta  $D801
        dey
        bpl  -
        lda  #$40
        jmp  prepare_screen

; 6545 CRTC values used when DF02 bit 7 is 0.
; This is for LP models (8x8 characters).
crtc_timing_LP:
        .byte $7F ; R0 Horizontal total: $7F + 1 = 128 character clocks per line.
        .byte $50 ; R1 Horizontal displayed: 80 character positions per line.
        .byte $60 ; R2 Horizontal sync position: character position 96.
        .byte $0A ; R3 HSync width: 10 character clocks; VSYNC high nibble 0 means 16 scan lines.
        .byte $26 ; R4 Vertical total: $26 + 1 = 39 character rows per frame.
        .byte $01 ; R5 Vertical total adjust: add 1 scan line to the frame.
        .byte $19 ; R6 Vertical displayed: 25 character rows.
        .byte $1E ; R7 Vertical sync position: character row 30.
        .byte $00 ; R8 Non-interlace, straight-binary display addressing, no DE/cursor skew.
        .byte $07 ; R9 Character height: $07 + 1 = 8 scan lines per character row.
        .byte $20 ; R10 Cursor start raster 0; cursor mode 01 disables the cursor.
        .byte $00 ; R11 Cursor end raster 0.
        .byte $00 ; R12 Display start address high byte.
        .byte $00 ; R13 Display start address low byte; display begins at $0000.
        .byte $00 ; R14 Cursor address high byte.
        .byte $00 ; R15 Cursor address low byte; cursor address is $0000.
        .byte $00 ; R16 Light-pen address high latch; not used by this diagnostic.
        .byte $00 ; R17 Light-pen address low latch; not used by this diagnostic.


; Set timing for HP machines (7xx).
set_timing_HP:
-       lda  crtc_timing_HP,y
        sty  $D800
        sta  $D801
        dey
        bpl  -
        lda  #$80
        jmp  prepare_screen


; Alternate 6545 CRTC values used when DF02 bit 7 is 1.
; This is for HP models (8x14 characters).
crtc_timing_HP:
        .byte $6C ; R0 Horizontal total: $6C + 1 = 109 character clocks per line.
        .byte $50 ; R1 Horizontal displayed: 80 character positions per line.
        .byte $53 ; R2 Horizontal sync position: character position 83.
        .byte $0F ; R3 HSync width: 15 character clocks; VSYNC high nibble 0 means 16 scan lines.
        .byte $19 ; R4 Vertical total: $19 + 1 = 26 character rows per frame.
        .byte $03 ; R5 Vertical total adjust: add 3 scan lines to the frame.
        .byte $19 ; R6 Vertical displayed: 25 character rows.
        .byte $19 ; R7 Vertical sync position: character row 25.
        .byte $00 ; R8 Non-interlace, straight-binary display addressing, no DE/cursor skew.
        .byte $0D ; R9 Character height: $0D + 1 = 14 scan lines per character row.
        .byte $20 ; R10 Cursor start raster 0; cursor mode 01 disables the cursor.
        .byte $00 ; R11 Cursor end raster 0.
        .byte $00 ; R12 Display start address high byte.
        .byte $00 ; R13 Display start address low byte; display begins at $0000.
        .byte $00 ; R14 Cursor address high byte.
        .byte $00 ; R15 Cursor address low byte; cursor address is $0000.
        .byte $00 ; R16 Light-pen address high latch; not used by this diagnostic.
        .byte $00 ; R17 Light-pen address low latch; not used by this diagnostic.


; Print title, clear the video/display pages, then run the early RAM checks.
prepare_screen:
        sta  $04            ; $04 = Display type: LP=$40, HP=$80.

        ; Clear screen (80x25 = 2000). We actually clear 2048 (no problem).
        ldx  #$00
        lda  #$20           ; Char code for SPACE.
-       sta  $D000,x
        sta  $D100,x
        sta  $D200,x
        sta  $D300,x
        sta  $D400,x
        sta  $D500,x
        sta  $D600,x
        sta  $D700,x
        inx
        bne  -

        ; Detect machine type and memory amount (128K or 256K, more memory is not detected/tested).

        ldx  #$03
        stx  $02            ; $02 = Memory amount: 128K = $03, 256L = $05
        stx  $01            ; 6509 Indirection = BANK 3
        
        ldx  #46            ; X = Title string length.
        
        lda  #$60
        sta  $08            ; $0008 = $60
        lda  #$A5           ; A = $A5 (mem probe test value).
        sta  $05            ; Store A in BANK 15.

; Early scratch-memory probe through the zero-page pointer at ($08 $09).
; NOTE: Mem at $09 is never initialized, so this probe may use a random location in the range [$60 .. $15F].
; On failure, write a BAD marker on the first diagnostic row and continue its failure pattern.

        ; Here Y=$FF.
-       sta  ($08),y        ; Store $A5 in BANK 3.
        lda  ($08),y        ; Load stored value in BANK 3.
        cmp  $05            ; Compare with probe value ($A5), stored in bank 15.
        beq  probe_found    ; Found probe value.
        iny                 ; Try all 256 locations in BANK 3.
        bne  -
        beq  probe_not_found

probe_found:
        lda  #$05
        sta  $02            ; $02 = Memory amount: 128K = $03, 256L = $05
        bne  found_256K

probe_not_found:
        lda  $04
        bmi  found_700_128k

found_600_128k:
-       lda  title_600_128k,x
        and  #$BF
        sta  $D000,x
        dex
        bne  -
        beq  end_detect

found_700_128k:
-       lda  title_700_128k,x
        and  #$BF
        sta  $D000,x
        dex
        bne  -
        beq  end_detect

found_256K:
        lda  $04
        bmi  found_700_256k

found_600_256k:
-       lda  title_600_256k,x
        and  #$BF
        sta  $D000,x
        dex
        bne  -
        beq  end_detect

found_700_256k:
-       lda  title_700_256k,x
        and  #$BF
        sta  $D000,x
        dex
        bne  -

end_detect:
        lda  #$0F
        sta  $01            ; Indirection BANK 15.

        ; Print cycles (i.e. how many times the full diagnostics has run).
        ldx  #$08
-       lda  cycle_header,x
        and  #$BF
        sta  $D050,x
        lda  cycle_counter_source,x
        and  #$BF
        ora  #$80
        sta  $D060,x
        dex
        bne  -


; ZEROPAGE test: write/read walking byte values across $0003-$00FF, then verify each location against an address-derived value. A mismatch leaves a persistent BAD marker.

run_zeropage_test:
        ; Print test name.
        ldx  #$10
-       lda  zeropage_test_name,x
        and  #$BF
        sta  $D0F0,x
        dex
        bne  -
        

        ldy  #$03           ; Y = tested location. Start from address $0003
zploop:
        ldx  #$00           ; Test all 255 byte values.
-       txa
        sta  $0000,y
        eor  $0000,y
        bne  zp_fail
        inx
        bne  -
        ; Mark the tested zp location with its own zp address.
        tya
        sta  $0000,y
        iny
        bne  zploop
        
        ; Verify all marked locations are correct.
        ldy  #$03
-       tya
        cmp  $0000,y
        bne  zp_fail
        iny
        bne  -

        ; Print OK.
        ldx  #$03
-       lda  str_OK,x
        and  #$BF
        sta  $D100,x
        dex
        bne  -
        jmp  run_sram_test

zp_fail:
        ; Print BAD.
        ldx  #$03
-       lda  str_BAD,x
        and  #$BF
        ora  #$80
        sta  $D100,x
        dex
        bne  -

        ; Stop test, but keep changing the failed location value (for logic analyzer ?).
zp_fail_stop:
        lda  #$01
-       sta  $0000,y
        eor  #$FF
        sta  $0000,y
        asl  a
        bcc  -
        jmp  zp_fail_stop

; STATIC RAM test.
; Test mapped RAM pages $01-$03 with byte patterns, then verify the address-derived contents.
; $02 supplies the selected RAM segment/bank limit.

run_sram_test:
        ldx  #$10
-       lda  sram_test_name,x
        and  #$BF
        sta  $D140,x
        dex
        bne  -

        ; Set ($0B:$0A) pointing to $0100.
        ldx  #$00
        stx  $0A
        inx
        stx  $0B
        
        ldy  #$00
LE16D:
        ldx  #$00
-       txa
        sta  ($0A),y
        eor  ($0A),y
        bne  sram_fail
        inx
        bne  -

        tya
        clc
        adc  $0B
        sta  ($0A),y
        iny
        bne  LE16D
        inc  $0B
        lda  $0B
        cmp  #$04
        bne  LE16D
        lda  #$00
        sta  $0A
        ldx  #$01
        stx  $0B
        ldy  #$00

LE194:
        tya
        clc
        adc  $0B
        cmp  ($0A),y
        bne  sram_fail
        iny
        bne  LE194
        inx
        stx  $0B
        cpx  #$04
        bne  LE194
        
        ; Print OK.
        ldx  #$03
LE1A8:  lda  str_OK,x
        and  #$BF
        sta  $D150,x
        dex
        bne  LE1A8
        jmp  run_other_tests

sram_fail:
        ; Print BAD.
        ldx  #$03
-       lda  str_BAD,x
        and  #$BF
        ora  #$80
        sta  $D150,x
        dex
        bne  -

        ; Iterate values at SRAM failure location (for logic analyzer ?).
-       lda  #$01
        sta  ($0A),y
        eor  #$FF
        sta  ($0A),y
        asl  a
        bcc  -
        jmp  run_other_tests



; DRAM test:
; *** WARNING *** Keep this at the beginning of the exe image, so we can relocate it to SRAM (first 2 KB of BANK 15).
; - Iterate the segments selected by $02.
; - Display the segment name.
; - Test each mapped segment.
; - Restore the normal memory map.
;
run_test_dram:
        lda  #$01           ; Start with indirection BANK 1.
        sta  $03            ; Store current indirection BANK in $03.
        
        ; Print DRAM segment test line.
-       ldx  #>dram_segment_test_name
        ldy  #<dram_segment_test_name
        jsr  print_strz
        ldy  $03
        lda  hex_digits,y
        and  #$BF
        ldy  #$0E
        sta  ($2A),y
        jsr  test_dram_segment
        inc  $03            ; Increase indirection BANK to test (stored in $03).
        lda  $03
        cmp  $02            ; Stop at max indirection BANK available on this machine (stored in $02).
        bne  -

        rts


; Test the selected DRAM segment with $55/$AA patterns.
; On error, print the failing address and data byte.
test_dram_segment:
        lda  #$00
        sta  $0A
        sta  $0B
        lda  $03
        sta  $01            ; Select indirection BANK.
        ldy  #$02
-       lda  #$55           ; Pattern $55.
        sta  ($0A),y
        lda  ($0A),y
        eor  #$55
        bne  dram_byte_error
        lda  #$AA           ; Pattern $AA.
        sta  ($0A),y
        lda  ($0A),y
        eor  #$AA
        bne  dram_byte_error
        tya
        clc
        adc  $0B
        sta  ($0A),y
LE707:
        iny
        bne  -
        inc  $0B
        bne  -

        lda  #$00
        sta  $0B
        ldy  #$02
-       tya
        clc
        adc  $0B
        sta  $08
        lda  ($0A),y
        eor  $08
        bne  LE737
LE720:  iny
        bne  -
        inc  $0B
        bne  -
        
        ; DRAM test OK.
        lda  #$0F           ; Indirection BANK 15.
        sta  $01
        jsr  print_test_OK
        jsr  cursor_down
        rts

dram_byte_error:
        jsr  LE73C          ; JSR
        beq  LE707
LE737:
        jsr  LE73C          ; JSR
        beq  LE720
        ; Fall-through LE73C and return.
LE73C:
        sty  $0A
        sta  $05            ; Failed data bits.
        lda  #$0F
        sta  $01            ; Indirection BANK 15.
        jsr  print_dram_error
        jsr  print_failed_addr
        ldy  $0A
        lda  $03
        sta  $01            ; Indirection BANK change.
        lda  #$00
        sta  $0A
        rts

        lda  $03
        sta  $01            ; Indirection BANK change.
        ldy  #$00

        ; Stop test here, but keep changing the failed location value (for logic analyzer ?).
dram_segment_failure_loop:
        clc
        adc  #$01
        sta  ($0A),y
        jmp  dram_segment_failure_loop


; Initialize the test-row cursor at screen RAM $D190 and run the diagnostics in order. After the last test, update the cycle counter, clear the display area, and repeat.

run_other_tests:
        nop
        nop
        nop
        lda  #$90
        sta  $2A
        lda  #$D1
        sta  $2B
        lda  #$10
        sta  $28
        jsr  run_vram_test
        jsr  run_rom_test
        jsr  run_keyb_test
        jsr  run_rs232_test
        jsr  run_cassette_test
        jsr  run_userport_test
        jsr  run_ieee_test
        jsr  run_timers_test
        jsr  run_interrupt_test
        jsr  run_test_dram
        jsr  run_test_sid
        
        lda  #$05
        jsr  delay
        jsr  inc_cycle_counter
        jmp  run_zeropage_test  ; Next test cycle (loop forever).


cycle_code_END:
.if BUILD_TYPE_PRG
    ; PRG build only.
    .if * > $0400
       .error format("Cycle code ends at * = %04X. Must be < $0400.", *)
    .endif
.endif


; VIDEO RAM test: scan $D000-$D7FF. For every byte, write/read all 256 values, restore the saved original byte, and report the first mismatch or success.

run_vram_test:
        ldx  #>video_ram_test_name
        ldy  #<video_ram_test_name
        jsr  print_strz
        ldy  #$00
        sty  $0A
        lda  #$D0
        sta  $0B
LE21D:
        lda  ($0A),y
        sta  $08
        ldx  #$00
LE223:
        txa
        sta  ($0A),y
        eor  ($0A),y
        bne  LE243
        inx
        bne  LE223
        lda  $08
        sta  ($0A),y
        iny
        bne  LE21D
        inc  $0B
        lda  $0B
        cmp  #$D8
        bne  LE21D
        jsr  print_test_OK
        jsr  cursor_down
        rts
LE243:
        jsr  print_test_BAD
        
        ; Loop forever incrementing the failed VRAM location (for logic analyzer ?).
-       clc
        adc  #$01
        sta  ($0A),y
        jmp  -


; ROM checksums.
; Independently sum the 8 KB BASIC low ($8000), BASIC high ($A000), and KERNAL ($E000) regions and compare each sum with the original reference table.
; We skip the KERNAL ROM check if we are running in Kernal replacement mode.
run_rom_test:
        ldx  #>basic_low_test_name
        ldy  #<basic_low_test_name
        jsr  print_strz
        ldx  #$00           ; BASICL
        jsr  check_rom

        ldx  #>basic_high_test_name
        ldy  #<basic_high_test_name
        jsr  print_strz
        ldx  #$01           ; BASICH
        jsr  check_rom

        ldx  #>kernal_test_name
        ldy  #<kernal_test_name
        jsr  print_strz
.if BUILD_TYPE_CARTRIDGE
        ldx  #$02           ; KERNAL
        jsr  check_rom
.elif BUILD_TYPE_KERNAL
        ; Compute and print checksum anyway (this will help identify this Diagnostics version).
        ldx  #$02           ; KERNAL
        jsr  compute_rom_checksum_ext
        ; Print "DIAG".
        jsr  print_test_DIAG
        jsr  print_checksum_ext
        jsr  cursor_down
        rts
.endif
        rts


; Compute and verify checksum for the given ROM.
; If different than expected, display the checksum after "BAD".
; Input:
; - X : The ROM to diagnose (0 = BASICL, 1 = BASICH, 2 = KERNAL).
check_rom:
        ; Compute extended 24-bit checksum first.
        txa
        pha
        jsr  compute_rom_checksum_ext
        jsr  print_checksum_ext
        pla
        tax
        ; Compute normal 8-bit checksum.
        jsr  compute_rom_checksum
        cmp  rom_region_checksums,x
        bne  rom_check_failed
        
        ; ROM check OK.
        jsr  print_test_OK
        jsr  cursor_down
        rts
    
        ; ROM check BAD.
rom_check_failed:
        jsr  print_test_BAD
        lda  #$18
        jsr  set_print_offset
        lda  $08
        jsr  print_A_hex
        jsr  cursor_down
        rts

; Compute a one-byte checksum for the given ROM and put it in $08.
; Input:
; - X : The ROM to diagnose (0 = BASICL, 1 = BASICH, 2 = KERNAL).
compute_rom_checksum:
        ldy  #0
        sty  $0A
        lda  rom_region_high_bytes,x
        sta  $0B
        lda  rom_region_page_counts,x
        sta  $0C
        clc
        lda  #0
-       adc  ($0A),y
        iny
        bne  -
        inc  $0B
        dec  $0C
        bne  -
        adc  #0
        sta  $08
        rts


; Compute an extended 24-bit checksum for the selected ROM and return it in $10-$12 (hi-byte first).
; Input: X = ROM region index (0 = BASICL, 1 = BASICH, 2 = KERNAL).
compute_rom_checksum_ext:
        lda  #0
        sta  $10
        sta  $11
        sta  $12
        ldy  #0
        sty  $0A
        lda  rom_region_high_bytes,x
        sta  $0B
        lda  rom_region_page_counts,x
        sta  $0C
checksum_ext_byte_loop:
        clc
        lda  $12
        adc  ($0A),y
        sta  $12
        lda  $11
        adc  #0
        sta  $11
        lda  $10
        adc  #0
        sta  $10
        iny
        bne  checksum_ext_byte_loop
        inc  $0B
        dec  $0C
        bne  checksum_ext_byte_loop
        rts


; Print the 24-bit extended checksum at address $10-$12 (hi-byte first).
print_checksum_ext:
        ldx  #0
-       txa
        asl
        clc
        adc  #28                ; Offset from cursor.
        jsr  set_print_offset   ; Does not affect X.
        lda  $10,x
        jsr  print_A_hex        ; Does not affect X.
        inx
        cpx  #3
        bne  -
        rts


; Order: BASICL, BASICH, KERNAL.
rom_region_high_bytes:
        .byte $80, $A0, $E0
rom_region_page_counts:
        .byte $20, $20, $20
rom_region_checksums:
        .byte $80, $A0, $E0


; KEYBOARD test.
; Check row/column select lines, then compare returned low-nibble patterns with keyboard_scan_expected.
run_keyb_test:
        ldx  #>keyboard_test_name
        ldy  #<keyboard_test_name
        jsr  print_strz
        ldy  #0
        sty  $DF03
        sty  $DF04
        sty  $DF05
        ldx  #$01
kb_nxt_port:
        lda  #$3F
        sta  $DF03,x
        ldy  #$C0
-       tya
        sta  $DF00,x
        sta  $09
        lda  $DF02
        eor  $09
        and  #$3F
        bne  keyb_failed
        iny
        bne  -
        lda  #0
        sta  $DF03,x
        dex
        bpl  kb_nxt_port

        lda  #$C0
        sta  $DF00
        sta  $DF01
        sta  $DF03
        sta  $DF04
        lda  #$30
        sta  $09
        ldy  #$07               ; 8 expected values.
kb_nxt_scan:
        ldx  #$01
-       lda  $09
        ora  #$3F
        sta  $DF00,x
        lda  $DF02
        and  #$0F
        cmp  keyboard_scan_expected,y
        bne  keyb_failed
        dey
        dex
        beq  -
        asl  $09
        cpy  #$FF
        bne  kb_nxt_scan
        jsr  print_test_OK
keyb_end:
        jsr  cursor_down
        rts
keyb_failed:
        jsr  print_test_BAD
        jmp  keyb_end

keyboard_scan_expected:
        .byte $0A, $0B, $0F, $0D, $05, $04, $00, $03


; RS-232 test.
; Send the pattern sequence through the serial interface and poll $DD01 bit 3 until asserted, then compare received data and modem-control bits.
; We timeout in case the RS-232 loopback dongle is missing, and mark the test as BAD.
run_rs232_test:
        ldx  #>rs232_test_name
        ldy  #<rs232_test_name
        jsr  print_strz
        sta  $DD01
        lda  $DD03
        ora  #$10
        sta  $DD03
        lda  $DD02
        ora  #$19
        sta  $DD02
        lda  #$0E
        sta  $08
LE352:
        lda  $DD03
        and  #$F0
        ora  $08
        sta  $DD03
        ldy  $08
        lda  rs232_test_pattern,y
        sta  $DD00
        lda  $DD02
        and  #$F7
        sta  $DD02

; Allow about 65,536 polling iterations for each received byte.
; Fail the test if no serial response, so a missing loopback dongle cannot stall the diagnostics.
        ldx  #$00
        lda  #$FF
        sta  $09
-       lda  $DD01
        and  #$08
        bne  cont_rs232_test
        dex
        bne  -
        dec  $09
        bne  -
        jmp  failed_rs232

cont_rs232_test:
        lda  $DD00
        cmp  rs232_test_pattern,y
        bne  failed_rs232
        dec  $08
        bne  LE352
        lda  $DD02
        and  #$FE
        sta  $DD02
        lda  $DD01
        tax
        and  #$20
        beq  failed_rs232
        txa
        and  #$40
        beq  failed_rs232
        sta  $DD01
        jsr  print_test_OK
end_rs232:
        jsr  cursor_down
        rts

failed_rs232:
        jsr  print_test_BAD
        jmp  end_rs232

rs232_test_pattern:
        .byte $FF, $55, $AA, $00, $01, $02, $04, $08
        .byte $10, $20, $40, $80, $FF, $CC, $33, $FF


; CASSETTE test:
; - Configure cassette control and CIA interrupt state.
; - Toggle the output
; - Check cassette input and timer/edge status.
run_cassette_test:
        ldx  #>cassette_test_name
        ldy  #<cassette_test_name
        jsr  print_strz
        lda  $DE04
        and  #$7F
        ora  #$60
        sta  $DE04
        ldx  #$10
        stx  $DC0D
        ldx  $DC0D

        ldx  #$04
        lda  $DE01
-       ora  #$60
        sta  $DE01
        and  #$DF
        pha
        pla
        sta  $DE01
        pha
        pla
        dex
        bne  -
        
        lda  #$F5
-       adc  #$01
        bne  -

        lda  $DE01
        and  #$80
        bne  failed_cassette

        lda  $DC0D
        and  #$10
        beq  failed_cassette

        lda  $DE01
        and  #$BF
        sta  $DE01

        lda  #$F5
-       adc  #$01
        bne  -

        lda  $DE01
        and  #$80
        beq  failed_cassette

        lda  $DE04
        and  #$DF
        sta  $DE04
        jsr  print_test_OK

end_cassette:
        jsr  cursor_down
        rts

failed_cassette:
        jsr  print_test_BAD
        jmp  end_cassette



; USER PORT test (requires harness):
; - Set port directions to two complementary patterns.
; - Verify data loopback through the port.
; - Check CNT/timer-related status and restore direction regs.
run_userport_test:
        ldx  #>user_port_test_name
        ldy  #<user_port_test_name
        jsr  print_strz

        lda  #$FF
        sta  $DE00
        sta  $DE01
        sta  $DE04
        sta  $DE03
        lda  #$CC
        sta  $DC02
        sta  $DC03
        eor  #$FF
        sta  $08
        jsr  check_userport
        bcs  failed_userport
        lda  #$33
        sta  $DC02
        sta  $DC03
        eor  #$FF
        sta  $08
        jsr  check_userport
        bcs  failed_userport
        ldy  $DC01
        nop
        lda  $DC0D
        and  #$10
        beq  failed_userport
        lda  $DC0E
        and  #$BF
        sta  $DC0E
        ldx  #$10
        clc
-       lda  #$04
        adc  $08
        sta  $08
        ora  #$10
        sta  $DE01
        dex
        bne  -

        lda  $DC0D
        and  #$08
        beq  failed_userport
        lda  $DC0C
        cmp  #$55
        bne  failed_userport
        jsr  print_test_OK
end_userport:
        jsr  cursor_down
        lda  #$FF
        sta  $DE03
        sta  $DC02
        sta  $DC03
        rts

failed_userport:
        jsr  print_test_BAD
        jmp  end_userport


; Exercise the user-port data patterns and compare masked output/readback on both ports.
check_userport:
        ldy  #$0F           ; 16 patterns to check.

nxt_userport_pattern:
        ldx  #$01
-       lda  user_port_test_pattern,y
        sta  $DC00,x
        nop
        lda  $DC00,x
        and  $08
        sta  $09
        lda  user_port_test_pattern,y
        and  $08
        cmp  $09
        bne  userport_pattern_fail
        dex
        bpl  -
        dey
        bpl  nxt_userport_pattern
        
        clc
        rts
userport_pattern_fail:
        sec
        rts

user_port_test_pattern:
        .byte $00, $05, $0A, $0F, $50, $55, $5A, $5F
        .byte $A0, $A5, $AA, $AF, $F0, $F5, $FA, $FF



; IEEE PORT test (requires harness):
; - Drive the data patterns and compare the masked data readback.
; - Toggle and check handshake/control lines.
run_ieee_test:
        ldx  #>ieee_port_test_name
        ldy  #<ieee_port_test_name
        jsr  print_strz
        lda  #$FF
        sta  $DC02
        lda  #$33
        sta  $DE03
        lda  $DE04
        and  #$FE
        ora  #$02
        sta  $DE04

        ldy  #$0F
-       lda  user_port_test_pattern,y
        sta  $DC00
        lda  $DE00
        and  #$CC
        cmp  ieee_port_readback_expected,y
        bne  failed_ieee
        dey
        bpl  -

        ldx  #$FE
        stx  $DC00
        lda  $DE01
        and  #$01
        bne  failed_ieee
        inx
        stx  $DC00
        lda  $DE01
        and  #$01
        beq  failed_ieee
        lda  $DC00
        and  #$F7
        sta  $DC00
        lda  $DE03
        and  #$DF
        ora  #$10
        sta  $DE03
        lda  $DE00
        and  #$EF
        sta  $DE00
        lda  $DE00
        and  #$20
        bne  failed_ieee
        lda  $DE00
        ora  #$10
        sta  $DE00
        lda  $DE00
        and  #$20
        beq  failed_ieee
        lda  #$00
        sta  $DE03
        sta  $DE04
        sta  $DC02
        sta  $DC03
        ; IEEE OK.
        jsr  print_test_OK
end_ieee:
        jsr  cursor_down
        rts

failed_ieee:
        ; IEEE BAD.
        jsr  print_test_BAD
        jmp  end_ieee

ieee_port_readback_expected:
        .byte $00, $04, $08, $0C, $40, $44, $48, $4C
        .byte $80, $84, $88, $8C, $C0, $C4, $C8, $CC



; TIMERS test.
; - Load CIA timers A and B.
; - Start timers.
; - Wait.
; - Check that counters advanced and that timer B tracks the expected timer A value.
;
run_timers_test:
        ldx  #>timers_test_name
        ldy  #<timers_test_name
        jsr  print_strz
        lda  #$80
        sta  $DC0E
        sta  $DC0F
        lda  #$FF
        sta  $DC05
        sta  $DC04
        sta  $DC07
        sta  $DC06
        lda  #$81
        sta  $DC0E
        sta  $DC0F
        lda  #$04
        jsr  delay
        lda  #$80
        sta  $DC0E
        sta  $DC0F
        lda  $DC05
        cmp  #$FF
        beq  failed_timers
        lda  $DC07
        cmp  #$FF
        beq  failed_timers
        cmp  $DC05
        bne  failed_timers
        lda  $DC04
        cmp  #$FF
        beq  failed_timers
        lda  $DC06
        cmp  #$FF
        beq  failed_timers
        sec
        sbc  $DC04
        bcs  +
        adc  #$04
+       cmp  #$02
        bcs  failed_timers
        jsr  print_test_OK
end_timers:
        jsr  cursor_down
        rts

failed_timers:
        jsr  print_test_BAD
        jmp  end_timers



; INTERRUPT test:
; - Install the original temporary handlers in the RAM vectors.
; - Test the CIA interrupt sequence.
; TODO: This seems to loop indefinitely if no interrupt arrives. Implement timeout ?
run_interrupt_test:
        ldx  #>interrupt_test_name
        ldy  #<interrupt_test_name
        jsr  print_strz

        ; Install the primary handler for IRQ and BRK, and the secondary handler for NMI.
        lda  #<irq_handler_primary
        ldx  #>irq_handler_primary
        sta  $0300
        stx  $0301
        sta  $0302
        stx  $0303
        lda  #<irq_handler_NMI
        ldx  #>irq_handler_NMI
        sta  $0304
        stx  $0305

        ; Configure the CBM-II interrupt controller and initialize the CIA source mask and control-register selector.
        lda  $DE06
        and  #$FD
        ora  #$31
        sta  $DE06
        lda  $DE05
        ora  #$04
        sta  $DE05
        lda  #$01
        sta  $07
        lda  #$0E
        sta  $08

        ; Load and start CIA timer A, then wait for its interrupt handler.
        ldy  #$04
        jsr  start_cia_timer

        ; Load and start CIA timer B with the next interrupt mask and control register.
        ldy  #$06
        asl  $07
        inc  $08
        jsr  start_cia_timer

        ; Set the CIA time-of-day clock and alarm, enable the alarm interrupt, and wait for its handler.
        asl  $07
        lda  #$00
        sta  $DC0F
        ldx  #$01
        jsr  set_cia_tod
        lda  #$80
        sta  $DC0F
        ldx  #$04
        jsr  set_cia_tod
        jsr  enable_cia_irq
        lda  #$02
        jsr  delay
        jsr  poll_cia
        jsr  print_test_OK
        jsr  cursor_down
        rts

; Set the CIA time-of-day registers to the value in X, with CRB selecting clock or alarm registers.
set_cia_tod:
        lda  #0
        sta  $DC0B      ; TOD HR    = 0
        sta  $DC0A      ; TOD MIN   = 0
        sta  $DC09      ; TOD SEC   = 0
        stx  $DC08      ; TOD 10THS = X
        rts

; Load the CIA timer latch for the selected (Y offset) timer (A or B).
; Enable its interrupt source, start the timer, and wait for the handler.
start_cia_timer:
        lda  #$FF
        sta  $DC00,y    ; T?L = $FF
        iny
        lda  #$02
        sta  $DC00,y    ; T?H = $02
        jsr  enable_cia_irq
        ldy  $08        ; Note: Fetch CIA register from address $08.
        lda  #$89
        sta  $DC00,y    ; CR? = $89 (start the timer).
        jsr  poll_cia
        rts

; Enable the selected CIA interrupt mask and clear the shared handler result byte.
enable_cia_irq:
        lda  $07
        ora  #$80
        sta  $DC0D
        lda  #0
        sta  $06
        cli
        rts

; Poll the selected CIA interrupt flag indefinitely, then check that its handler changed the result byte.
poll_cia:
        lda  $DC0D
        and  $07
        beq  poll_cia
        lda  #$00
        sta  $DC0D
        sei
        lda  $06
        beq  fail_interrupt
        clc
        rts

; Discard the nested return address, display BAD, and return to the caller of the interrupt test.
fail_interrupt:
        pla
        pla
        jsr  print_test_BAD
        jsr  cursor_down
        sec
        rts

; IRQ handler: acknowledge the 6525 source, decrement the result byte, set I in the saved status, restore A/X/Y, and RTI.
irq_handler_primary:
        lda  $DE07
        dec  $06
        tsx
        lda  $0104,x
        ora  #$04
        sta  $0104,x
        pla
        tay
        pla
        tax
        pla
        rti

; NMI handler: decrement the result byte and RTI using the CPU's original NMI stack frame.
irq_handler_NMI:
        dec  $06
        rti





; SID CHIP test:
; - Initialize the sound registers.
; - Emit audible test sounds.
run_test_sid:
        ldx  #>sound_chip_test_name
        ldy  #<sound_chip_test_name
        jsr  print_strz
        
        ; Init SID registers from table.
        ldy  #$14
-       lda  sid_reg_values,y
        sta  $DA00,y
        dey
        bpl  -

        lda  #$0F
        sta  $DA18          ; Mode = 0; Volume = $F.
        lda  #$11
        jsr  pulse_sid
        lda  #$21
        jsr  pulse_sid
        lda  #$41
        jsr  pulse_sid
        lda  #$01
        sta  $DA17          ; RES = 0; Filter voice 1.
        lda  #$2F
        sta  $DA18          ; Mode = Bandpass; Volume = $F.
        lda  #$00
        sta  $DA05          ; Attack/Decay 1.
        lda  #$F0
        sta  $DA06          ; Sustain/Release 1.
        lda  #$81
        sta  $DA04          ; Control Register 1.
        
        ; Is this supposed to be a filter sweep ?
        ldx  #$00
filter_sweep:
        ldy  #$00
-       sty  $DA15          ; Filter Freq Lo = 0.
        pha                 ; Delay some cycles...
        pla
        pha
        pla
        pha
        pla
        iny
        ;cpy  #$80
        cpy  #$07           ; [DDT] Freq Lo is only 3 bits.
        bne  -
        stx  $DA16          ; Filter Freq Hi = X.
        inx
        bne  filter_sweep
        
        stx  $DA18          ; Filter Freq Hi = 0.
        jsr  cursor_down
        rts

; Pulse some SID registers with value in A for a short delay, then clear them.
pulse_sid:
        sta  $DA04  ; Control Register 1
        sta  $DA06  ; Sustain/Release 1
        sta  $DA12  ; Control Register 3
        lda  #$04   ; Delay amount.
        jsr  delay
        lda  #$00
        sta  $DA04
        sta  $DA06
        sta  $DA12
        rts


sid_reg_values:
; Voice 1: frequency word $D61C; pulse width $00FF.
        .byte $1C   ; $DA00 voice 1 frequency low
        .byte $D6   ; $DA01 voice 1 frequency high
        .byte $FF   ; $DA02 voice 1 pulse-width low
        .byte $00   ; $DA03 voice 1 pulse-width high
        .byte $10   ; $DA04 triangle selected; gate, sync, ring, and test clear
        .byte $09   ; $DA05 attack 0, decay 9
        .byte $00   ; $DA06 sustain 0, release 0
; Voice 2: frequency word $5524; pulse width $00FF.
        .byte $24   ; $DA07 voice 2 frequency low
        .byte $55   ; $DA08 voice 2 frequency high
        .byte $FF   ; $DA09 voice 2 pulse-width low
        .byte $00   ; $DA0A voice 2 pulse-width high
        .byte $10   ; $DA0B triangle selected; gate, sync, ring, and test clear
        .byte $09   ; $DA0C attack 0, decay 9
        .byte $00   ; $DA0D sustain 0, release 0
; Voice 3: frequency word $342B; pulse width $00FF.
        .byte $2B   ; $DA0E voice 3 frequency low
        .byte $34   ; $DA0F voice 3 frequency high
        .byte $FF   ; $DA10 voice 3 pulse-width low
        .byte $00   ; $DA11 voice 3 pulse-width high
        .byte $10   ; $DA12 triangle selected; gate, sync, ring, and test clear
        .byte $09   ; $DA13 attack 0, decay 9
        .byte $00   ; $DA14 sustain 0, release 0


; Copy a null-terminated string at the current cursor pos.
; Inputs:
; - X: Str ptr hi.
; - Y: Str ptr lo.
; - ($2A,$2B) : Current screen VRAM location.
print_strz:
        stx  $2D
        sty  $2C
        ;ldy  #$10           ; Max 17 chars.
        ldy  #0
-       lda  ($2C),y
        beq  +              ; Check for zero-termination.
        and  #$BF
        sta  ($2A),y
        iny
        bpl  -
+       rts


; Copy a fixed-length ROM string to the output pointer in $2E/$2F.
; Inputs:
; - A: Str len.
; - X: Str ptr hi.
; - Y: Str ptr lo.
; - ($2E,$2F) : Current screen VRAM location.
print_strl:
        stx  $2D
        sty  $2C
        tay
-       lda  ($2C),y
        and  #$BF
        sta  ($2E),y
        dey
        bpl  -
        rts

; Mark the current test row OK.
print_test_OK:
        lda  #$10
        jsr  set_print_offset
        ldy  #$03
-       lda  str_OK,y
        and  #$BF
        sta  ($2E),y
        dey
        bne  -
        rts

; Mark the current test row BAD using reverse video.
print_test_BAD:
        lda  #$10
        jsr  set_print_offset
        ldy  #$03
-       lda  str_BAD,y
        and  #$BF
        ora  #$80
        sta  ($2E),y
        dey
        bne  -
        rts


; Mark the current test row as DIAG using reverse video.
print_test_DIAG:
        lda  #$10
        jsr  set_print_offset
        ldy  #$04
-       lda  str_DIAG,y
        and  #$BF
        ora  #$80
        sta  ($2E),y
        dey
        bne  -
        rts


; Print DRAM failure information: address/data and the failing byte.
print_dram_error:
        jsr  conv_to_bin_string
        jsr  print_test_BAD
        lda  #$18
        jsr  set_print_offset
        ldx  #>data_bits_error_text
        ldy  #<data_bits_error_text
        lda  #$08           ; Print 8 binary digits, starting at address $10.
        jsr  print_strl
        lda  #$23
        jsr  set_print_offset
        ldx  #$00
        ldy  #$10
        lda  #$07
        jsr  print_strl
        rts


; Advance the cursor by one 80-column row.
cursor_down:
        clc
        lda  $2A
        adc  #80
        sta  $2A
        lda  $2B
        adc  #0
        sta  $2B
        rts


; Set the temporary output pointer to the current cursor pos plus offset A.
set_print_offset:
        clc
        adc  $2A
        sta  $2E
        lda  $2B
        adc  #$00
        sta  $2F
        rts

; Convert the failing data byte in $05 into eight display characters starting from $10.
conv_to_bin_string:
        ldy  #$07
        ldx  $05
-       txa
        lsr  a
        tax
        bcs  +
        lda  hex_digits
        bcc  digit0
+       lda  hex_digits+1
digit0: and  #$BF
        sta  $0010,y
        dey
        bpl  -
        rts


; Convert A to two hexadecimal display characters at the current output pointer.
print_A_hex:
        pha
        lsr  a
        lsr  a
        lsr  a
        lsr  a
        ldy  #$00
        jsr  prt_digit  ; Call tail as a sub for first digit.
        ; Do second digit.
        pla
        and  #$0F
        ; Fall-through...
prt_digit:
        clc
        adc  #$F6
        bcs  +
        adc  #$39
+       adc  #0
        and  #$BF
        sta  ($2E),y
        iny
        rts


; Inc cycle counter.
inc_cycle_counter:
        ldx  #$07
-       inc  $D060,x
        lda  $D060,x
        and  #$7F
        cmp  #$3A
        bcc  clear_test_results
        lda  #$B0
        sta  $D060,x
        dex
        bpl  -
        bmi  inc_cycle_counter

; Clear prev cycle test results.
clear_test_results:
        ldx  #$00
        lda  #$20
LE8C4:
        sta  $D0A0,x
        sta  $D100,x
        sta  $D200,x
        sta  $D300,x
        sta  $D400,x
        sta  $D500,x
        sta  $D600,x
        sta  $D700,x
        inx
        bne  LE8C4
        rts


; Delay some time (amount in A).
delay:
        ldx  #$FF
        ldy  #$FF
-       dex
        bne  -
        dey
        bne  -
        sec
        sbc  #$01
        bne  -
        rts


; Append the failing DRAM address from ($0B:$0A) to the current row.
print_failed_addr:
        lda  #$2D
        jsr  set_print_offset
        ldx  #>address_error_text
        ldy  #<address_error_text
        lda  #$08
        jsr  print_strl
        lda  #$37
        jsr  set_print_offset
        lda  $0B
        jsr  print_A_hex
        lda  #$39
        jsr  set_print_offset
        lda  $0A
        jsr  print_A_hex
        rts


.enc "screen" ; Lowercase source letters become CBM lowercase screen codes.
title_700_256k:
.text " commodore cbm 700 (256k) diag 324835-02 [ddt]"
title_700_128k:
.text " commodore cbm 700 (128k) diag 324835-02 [ddt]"
title_600_256k:
.text " commodore cbm 600 (256k) diag 324835-02 [ddt]"
title_600_128k:
.text " commodore cbm 600 (128k) diag 324835-02 [ddt]"
cycle_header:
.text "  cycle "
cycle_counter_source:
.text "  000001"


; Zero-page RAM test name (must be 17 chars).
zeropage_test_name:
.text " zeropage        "

; Stack-page RAM test name (must be 17 chars).
stackpage_test_name:
.text " stackpage       " ; TODO: Stack does not seem to be tested. Implement ?

; Static RAM test name (must be 17 chars).
sram_test_name:
.text " static ram      "

; Other test names (must be zero terminated).
video_ram_test_name:
.text " video  ram", 0
basic_low_test_name:
.text " basic  rom (l)", 0
basic_high_test_name:
.text " basic  rom (h)", 0
kernal_test_name:
.text " kernal rom", 0
keyboard_test_name:
.text " keyboard", 0
ieee_port_test_name:
.text " ieee port", 0
user_port_test_name:
.text " user port", 0
rs232_test_name:
.text " rs-232", 0
cassette_test_name:
.text " cassette", 0
sound_chip_test_name:
.text " sound chip", 0
vdc_chip_test_name:
.text " vdc   chip", 0
dram_segment_test_name:
.text " dram segment", 0
timers_test_name:
.text " timers", 0
interrupt_test_name:
.text " interrupt", 0

; DRAM error strings (must be 9 chars each).

address_error_text:
.text " address ", 0
data_bits_error_text:
.text " databits", 0

; Test results (must be 4 chars each).

str_OK:
.text " ok "
str_BAD:
.text " bad"
str_DIAG:
.text " diag"

; HEX digits.

hex_digits:
.text "0123456789abcdef"
.byte $AA, $AA

; IRQ entry saves A/X/Y, then dispatches IRQ and BRK through the standard CBM-II RAM vector slots.
diag_irq_dispatch:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda  $0104,x
        and  #$10
        bne  diag_brk_dispatch
        jmp  ($0300)
diag_brk_dispatch:
        jmp  ($0302)

; The default IRQ handler acknowledges the 6525 source, restores registers, and returns from the interrupt.
diag_irq_default:
        lda  $DE07
        pla
        tay
        pla
        tax
        pla
        rti

; NMI handlers own the hardware stack frame and return with RTI.
diag_nmi_dispatch:
        jmp  ($0304)

; Default NMI handler (do nothing).
diag_rti:
        rti



.if BUILD_TYPE_PRG
    ; PRG build only.

.elif BUILD_TYPE_CARTRIDGE
    ; CARTRIDGE build only.
    .if * > $3FFF
       .error "Cartridge size exceeds 8192 bytes."
    .endif
    ; Pad cartridge to 8192 bytes.
    * = $3FFF
    .byte $FF

.elif BUILD_TYPE_KERNAL
    ; KERNAL build only.
    .if * > $FFFA
       .error "Kernal size exceeds 8192 bytes."
    .endif
    ; 6509 VECTORS (KERNAL BUILD ONLY).
    * = $FFFA
    .word diag_nmi_dispatch ; NMI
    .word main              ; RESET (restart diagnostics).
    .word diag_irq_dispatch ; IRQ
.endif
