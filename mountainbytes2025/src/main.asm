BasicUpstart2(main)

.const screen_base = $0400

        *=$4000 "Code"

main:
        ldx #txtmike
        jsr printtext
        ldx #txtmountain
        jsr printtext
        rts


clearscreen:
        ldx #$00


// Load the starting address of the text into X.
printtext:
        ldy #$00        // Init counter with 0
nextchar:
        lda datastart,X        // Load current char into A.
        cmp #$00        // Is end of string?
        beq endstring         // If not, jump over return.
        sta screen_base,Y       // Write to indexed screen target.
        inx
        iny
        jmp nextchar
endstring:
        rts             // Done, return.

        *=$1000 "Data"
datastart:
txtmike:
        .text "mikerofone"
        .byte 0
txtmountain:
        .text "at mountainbytes"
        .byte 0