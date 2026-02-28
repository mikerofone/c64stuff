static_disk1:
    lda screen_s1
    sta $d020
    lda screen_s1+1
    sta $d021
    lda #$15
    sta $d018

    ldx #$00
sdisk1_loop:
    lda screen_s1+2,x
    sta $0400,x
    lda screen_s1+$3ea,x
    sta $d800,x

    lda screen_s1+$102,x
    sta $0500,x
    lda screen_s1+$4ea,x
    sta $d900,x

    lda screen_s1+$202,x
    sta $0600,x
    lda screen_s1+$5ea,x
    sta $da00,x

    lda screen_s1+$2ea,x
    sta $06e8,x
    lda screen_s1+$6d2,x
    sta $dae8,x
    inx
    bne sdisk1_loop

    rts


#import "screens.asm"

