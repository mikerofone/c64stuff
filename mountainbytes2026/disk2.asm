// java -jar KickAss.jar foo.asm -o foo.prg
/* tools:
* vim
* Kick assembler
* VICE
* Marq's PETSCII editor (allows PNG in background as reference)
* Petmate (another PETSCII editor, allows fullscreen edit & export to ASM)


*/

.disk [filename="MyDisk.d64"]
{
}
//BasicUpstart2(start)



        // assembler constants for special memory locations
        .const CLEAR_SCREEN_KERNAL_ADDR = $E544     // Kernal routine to clear screen

/*
k.const CLEAR_SCREEN_KERNAL_ADDR = $E544     // Kernal routine to clear screen
//* = $0801          // BASIC start address (#2049)
.byte $0C, $08, $00, $00, $9E, $32, $30, $36
.byte $31, $00, $00, $00
*/

*=$0900 "Sprites"

// sprite 2 / singlecolor / color: $07
sprite_ship:
sprite1:
.byte $8a,$fa,$fe,$8a,$82,$10,$8a,$82
.byte $10,$8a,$82,$10,$8a,$82,$10,$8a
.byte $82,$10,$8a,$82,$10,$8a,$82,$10
.byte $8a,$82,$10,$8a,$fa,$10,$8a,$0a
.byte $10,$8a,$0a,$10,$8a,$0a,$10,$8a
.byte $0a,$10,$52,$0a,$10,$52,$0a,$10
.byte $52,$0a,$10,$22,$0a,$10,$22,$0a
.byte $10,$22,$fa,$10,$00,$00,$00,$07

// sprite 4 / singlecolor / color: $07
sprite_astroid:
sprite2:
.byte $8b,$e8,$20,$8a,$28,$20,$8a,$28
.byte $20,$ca,$28,$20,$ca,$28,$20,$aa
.byte $28,$20,$aa,$28,$20,$9a,$28,$20
.byte $9a,$28,$20,$8a,$28,$20,$8a,$28
.byte $20,$8a,$28,$20,$8a,$29,$20,$8a
.byte $29,$20,$8a,$2a,$a0,$8a,$2a,$a0
.byte $8a,$2c,$60,$8a,$2c,$60,$8a,$28
.byte $20,$8b,$e8,$20,$00,$00,$00,$07





// our assembly code will goto this address
*=$6000 "Main Start"
start:

        // c64 colors
        .const C64_COLOR_BLACK = $00
        .const C64_COLOR_WHITE = $01
        .const C64_COLOR_RED = $02
        .const C64_COLOR_CYAN = $03
        .const C64_COLOR_PURPLE = $04
        .const C64_COLOR_GREEN = $05
        .const C64_COLOR_BLUE = $06
        .const C64_COLOR_YELLOW = $07
        .const C64_COLOR_ORANGE = $08
        .const C64_COLOR_BROWN = $09
        .const C64_COLOR_LITE_RED = $0a
        .const C64_COLOR_DARK_GREY = $0b
        .const C64_COLOR_GREY = $0c
        .const C64_COLOR_LITE_GREEN = $0d
        .const C64_COLOR_LITE_BLUE = $0e
        .const C64_COLOR_LITE_GREY = $0f

        .const SPRITE_ENABLE_REG_ADDR = $d015 // each bit turns on one of the sprites lsb is sprite 0, msb is sprite 7
        .const SPRITE_COLOR_1_ADDR = $D025 // address of color for sprite bits that are binary 01
        .const SPRITE_COLOR_2_ADDR = $D026 // address of color for sprite bits that are binary 11

        .const SPRITE_0_DATA_PTR_ADDR = $07F8  // address of the pointer to sprite_0's data its only 8 bits
                                               // so its implied that this value will be multipled by 64
        .const SPRITE_0_X_ADDR = $D000
        .const SPRITE_0_Y_ADDR = $D001

        .const SPRITE_1_DATA_PTR_ADDR = $07F9  // address of the pointer to sprite_0's data its only 8 bits
                                               // so its implied that this value will be multipled by 64
        .const SPRITE_1_X_ADDR = $D002
        .const SPRITE_1_Y_ADDR = $D003

        // register with one bit for each sprite to indicate high res (one color)
        // or multi color.  Bit 0 (lsb) corresponds to sprite 0
        // set bit to 1 for multi color, or 0 for high res (one color mode)
        .const SPRITE_MODE_REG_ADDR = $D01C

        // since there are more than 255 x locations across the screen
        // the high bit for each sprite's X location is gathered in the
        // byte here.  sprite_0's ninth bit is bit 0 of the byte at this addr.
        .const ALL_SPRITE_X_HIGH_BIT_ADDR = $D010

        // the low 4 bits (0-3) contain the color for sprite 0
        // the hi 4 bits don't seem to be writable
        .const SPRITE_0_COLOR_REG_ADDR = $d027

        // the low 4 bits (0-3) contain the color for sprite 1
        // the hi 4 bits don't seem to be writable
        .const SPRITE_1_COLOR_REG_ADDR = $d028

        //////////////////////////////////////////////////////////////////////
        // clear screeen leave cursor upper left
        jsr CLEAR_SCREEN_KERNAL_ADDR

        //////////////////////////////////////////////////////////////////////
        // Setup and display our two sprites
        // the steps are:
        // Step 1: Set the global multi color sprite colors for
        //         the sprite_ship multi color sprite (sprite_0)
        // Step 2: Setup sprite_0 aka sprite_ship
        //   2a: Set the sprite mode for the sprite to multi color or
        //         high res (one color).  This sprite is multi color
        //   2b: Set the sprite data pointer for sprite 0 to the 64 bytes
        //       at label sprite_ship
        //   2c: Set the distinct color for sprite_ship
        // Step 3: Setup sprite_1 aka sprite_astroid
        //   3a: Set the sprite mode for sprite_astroid to multi color
        //       or high res (one color).  This sprite is high res
        //   3b: Set the sprite data pointer for sprite 1 to the
        //       64 bytes at sprite_astroid label.
        //   3c: Set the individual sprite color for sprite 1
        // Step 4 Enable the sprites
        // Step 5 Set sprites location

        ////// step 1: Set the two global colors for multi color sprites /////
        // here setting colors using the color const, but spritemate
        // will save similar code using literal values
        lda #C64_COLOR_LITE_GREEN // multicolor sprites global color 1
        sta SPRITE_COLOR_1_ADDR   // can also get this from spritemate
        lda #C64_COLOR_WHITE      // multicolor sprites global color 2
        sta SPRITE_COLOR_2_ADDR
        ////// step 1 done ///////////////////////////////////////////////////


        ////// Step 2: setup sprite 0 aka sprite_astroid /////////////////////

        ////// Step 2a: set mode for sprite_0 /////////////////////////////////

        // set it to single color (high res) and override below if needed
        lda SPRITE_MODE_REG_ADDR   // load sprite mode reg
        and #$fe                   // clear bit 0 for sprite 0
        sta SPRITE_MODE_REG_ADDR   // store it back to sprite mode reg

        lda #$F0                // load mask in A, checking for any ones in high nibble
        bit sprite_ship + 63       // set Zero flag if the masked bits are all 0s
                                // if any masked bits in the last byte of sprite_0 are set
                                // then its a multi colored sprite
        beq skip_multicolor_0     // if Zero is set, ie no masked bits were set, then branch
                                // to skip multi color mode.

        // If we didn't skip the multi color, then set sprite 0 to muli color mode
        lda SPRITE_MODE_REG_ADDR // load current contents of sprite mode reg
        ora #$01                 // set bit for sprite 0 (bit 0) to 1 for multi color
        sta SPRITE_MODE_REG_ADDR // leave other bits untouched for sprites 1-7
skip_multicolor_0:
        ////// Step 2a done ///////////////////////////////////////////////////

        ////// Step 2b: set sprite data pointer ///////////////////////////////
        lda #(sprite_ship / 64)            // implied this is multiplied by 64
        sta SPRITE_0_DATA_PTR_ADDR
        ////// step 2b done ///////////////////////////////////////////////////

        ////// step 2c: set sprite_ship unique color /////////////////////////
        // set this sprite's color.
        lda sprite_ship + 63            // The color is the low nibble of the
                                        // last byte of sprite. We'll just
                                        // write the whole byte because the
                                        // only lo 4 bits of reg are writable
        sta SPRITE_0_COLOR_REG_ADDR
        ////// step 2c done //////////////////////////////////////////////////

        //
        ////// step 2 done ///////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////



        ////// Step 3: setup sprite 1 aka sprite_astroid /////////////////////

        ////// Step 3a: set mode for sprite_astroid /////////////////////////////////

        // set it to single color (high res) and override below if needed
        lda SPRITE_MODE_REG_ADDR   // load sprite mode reg
        and #$fd                   // clear bit 1 for sprite 1 (sprite_astroid)
        sta SPRITE_MODE_REG_ADDR   // store it back to sprite mode reg

        lda #$F0                // load mask in A, checking for any ones in high nibble
        bit sprite_astroid + 63 // set Zero flag if the masked bits are all 0s
                                // if any masked bits in the last byte of sprite_0 are set
                                // then its a multi colored sprite
        beq skip_multicolor_1     // if Zero is set, ie no masked bits were set, then branch
                                // to skip multi color mode.

        // If we didn't skip the multi color, then set sprite 0 to muli color mode
        lda SPRITE_MODE_REG_ADDR // load current contents of sprite mode reg
        ora #$02                 // set bit for sprite 1 (bit 1) to 1 for multi color
        sta SPRITE_MODE_REG_ADDR // leave other bits untouched for sprites 1-7
skip_multicolor_1:
        ////// Step 3a done ///////////////////////////////////////////////////

        ////// Step 3b: set sprite data pointer ///////////////////////////////
        lda #(sprite_astroid / 64)            // implied this is multiplied by 64
        sta SPRITE_1_DATA_PTR_ADDR
        ////// step 3b done ///////////////////////////////////////////////////

        ////// step 3c: set sprite_ship unique color /////////////////////////
        // set this sprite's color.
        lda sprite_astroid + 63            // The color is the low nibble of the
                                        // last byte of sprite. We'll just
                                        // write the whole byte because the
                                        // only lo 4 bits of reg are writable
        sta SPRITE_1_COLOR_REG_ADDR
        ////// step 3c done //////////////////////////////////////////////////


        ////// step 4: enable both sprites /////////////////////////////////////////
        lda SPRITE_ENABLE_REG_ADDR      // load with sprite enabled reg
        ora #$03                        // set the bit for sprite 0,
                                        // Leaving other bits untouched
        sta SPRITE_ENABLE_REG_ADDR      // store to sprite enable register
                                        // one bit for each sprite.
        ////// step 4 done ///////////////////////////////////////////////////


        ////// step 5: Set Sprite Location ///////////////////////////////////
        // set sprite_ship X loc
        lda #52                // picking X loc at left of screen
        sta SPRITE_0_X_ADDR

        // set sprite_ship Y loc
        lda #200                 // picking Y loc for top of screen
        sta SPRITE_0_Y_ADDR

        // set sprite_astroid X loc
        lda #252                // picking X loc to the right of ship
        sta SPRITE_1_X_ADDR

        // set sprite_astroid y loc
        lda #200                 // picking Y loc for top of screen
        sta SPRITE_1_Y_ADDR

	lda #3
	sta $d017
	sta $d01d
        ////// step 5 done ///////////////////////////////////////////////////
    //jsr load_diskette


mainloop:

    //jsr vshift
    //jsr hshift

    //jsr vshift
    jsr vreset
    jsr disk1
    jsr hshift8

    jsr hreset
    jsr disk2
    //jsr hshiftr8
    jsr vshift8

    jsr vreset
    jsr disk3
    jsr hshiftr8

    jsr hreset
    jsr disk4
    jsr vshiftr8

/*
    jsr disk4
    jsr vshift8
*/
    jsr wait
    jmp mainloop


hshift8:
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    jsr hshift
    jsr wait
    rts

hshiftr8:
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    jsr hshiftr
    jsr wait
    rts

vshift8:
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    jsr vshift
    jsr wait
    rts

vshiftr8:
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    jsr vshiftr
    jsr wait
    rts

wait:
    lda #3
    sta SPRITE_ENABLE_REG_ADDR      // store to sprite enable register
    lda #1
    ldx #1
    jsr sleep
    jsr wait_for_next_frame
    lda #0
    sta SPRITE_ENABLE_REG_ADDR      // store to sprite enable register
    rts

disk1:
    lda screen_1
    sta $d020
    lda screen_1+1
    sta $d021
    lda #$15
    sta $d018

    ldx #$00
disk1_loop:
    lda screen_1+2,x
    sta $0400,x
    lda screen_1+$3ea,x
    sta $d800,x

    lda screen_1+$102,x
    sta $0500,x
    lda screen_1+$4ea,x
    sta $d900,x

    lda screen_1+$202,x
    sta $0600,x
    lda screen_1+$5ea,x
    sta $da00,x

    lda screen_1+$2ea,x
    sta $06e8,x
    lda screen_1+$6d2,x
    sta $dae8,x
    inx
    bne disk1_loop

    rts


disk2:
    lda screen_2
    sta $d020
    lda screen_2+1
    sta $d021
    lda #$15
    sta $d018

    ldx #$00
disk2_loop:
    lda screen_2+2,x
    sta $0400,x
    lda screen_2+$3ea,x
    sta $d800,x

    lda screen_2+$102,x
    sta $0500,x
    lda screen_2+$4ea,x
    sta $d900,x

    lda screen_2+$202,x
    sta $0600,x
    lda screen_2+$5ea,x
    sta $da00,x

    lda screen_2+$2ea,x
    sta $06e8,x
    lda screen_2+$6d2,x
    sta $dae8,x
    inx
    bne disk2_loop

    rts


disk3:
    lda screen_3
    sta $d020
    lda screen_3+1
    sta $d021
    lda #$15
    sta $d018

    ldx #$00
disk3_loop:
    lda screen_3+2,x
    sta $0400,x
    lda screen_3+$3ea,x
    sta $d800,x

    lda screen_3+$102,x
    sta $0500,x
    lda screen_3+$4ea,x
    sta $d900,x

    lda screen_3+$202,x
    sta $0600,x
    lda screen_3+$5ea,x
    sta $da00,x

    lda screen_3+$2ea,x
    sta $06e8,x
    lda screen_3+$6d2,x
    sta $dae8,x
    inx
    bne disk3_loop

    rts


disk4:
    lda screen_4
    sta $d020
    lda screen_4+1
    sta $d021
    lda #$15
    sta $d018

    ldx #$00
disk4_loop:
    lda screen_4+2,x
    sta $0400,x
    lda screen_4+$3ea,x
    sta $d800,x

    lda screen_4+$102,x
    sta $0500,x
    lda screen_4+$4ea,x
    sta $d900,x

    lda screen_4+$202,x
    sta $0600,x
    lda screen_4+$5ea,x
    sta $da00,x

    lda screen_4+$2ea,x
    sta $06e8,x
    lda screen_4+$6d2,x
    sta $dae8,x
    inx
    bne disk4_loop

    rts


/*
    WAIT_KEY:
    jsr $FFE4        // Calling KERNAL GETIN
    beq WAIT_KEY     //; If Z, no key was pressed, so try again.
                     //; The key is in A
    sta $0403
  */
    /*
    txa
    and	#7
    sta $d020
    */
    //stx $0401

// lda #$fb

    //clc
    //adc	#1
    //sta $d011
    //inc	$d011
    //sta $d011

    //jmp *


/*
    WAIT_KEY:
    jsr $FFE4        // Calling KERNAL GETIN
    beq WAIT_KEY     //; If Z, no key was pressed, so try again.
                     //; The key is in A
    sta $0403
    lda #$4D
    sta $0401
*/

//jsr wait_for_next_frame

wait_for_next_frame:
    bit $d011
    bpl wait_for_next_frame
    lda $d012
f:   cmp $d012
    bmi f
    rts

preset:
    jsr vreset
    jsr hreset
    rts

vreset:
    lda	$d011
    and	#%11111000
    sta $d011
    rts

hreset:
    lda	$d016
    and	#%11111000
    sta $d016
    rts


vshift:
    lda	$d011
    and #7
    cmp #7
    bne fff

    lda $d011
    clc
    sbc #7

    sta $d011

fff:
    ldx	$d011
    inx
    stx $d011

    rts


vshiftr:
    lda	$d011
    and #7
    cmp #0
    bne fffr

    lda $d011
    clc
    adc #7

    sta $d011

fffr:
    ldx	$d011
    dex
    stx $d011

    rts


hshift:
    lda	$d016
    and #7
    cmp #7
    bne fff2

    lda $d016
    clc
    sbc #7

    sta $d016

fff2:
    ldx	$d016
    inx
    stx $d016

rts

hshiftr:
    lda	$d016
    and #7
    cmp #0
    bne fff2r

    lda $d016
    //and #%11111000
    //and #%00011111
    clc
    adc #7

    sta $d016

fff2r:
    ldx	$d016
    dex
    stx $d016

rts
//jmp hshift


// Subroutine to wait for 0 to 4.25 seconds
// called using JSR with
// time to wait in A in 1/60 seconds
JIFFWAIT:
         clc
         adc   $A2          // Add time to wait to 'now'
JIFFWTLP:
         cmp   $A2          // Are we there yet
         bne   JIFFWTLP     // No -> Continue waiting
         rts                // Done waiting

#import "screens3.asm"
