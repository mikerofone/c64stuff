BasicUpstart2(main)

.const screen_base = $0400

.const zp_textaddr = $10
.const zp_targetrow = $12
.const zp_targetcol = $13
.const zp_targetaddr = $14


        *=$4000 "Code"

main:
        lda #<txtmike
        sta zp_textaddr
        lda #>txtmike
        sta zp_textaddr+1
        lda #10
        sta zp_targetrow
        lda #20
        sta zp_targetcol
        
        jsr printtext
        rts


clearscreen:
        ldx #$00


// TODO
printtext:
        // Assemble screen address.
        lda #>screen_base       // Init zp_targetaddr with base address.
                                // Start with hi byte so we can keep using lo byte.
        sta zp_targetaddr + 1
        lda #<screen_base       
        sta zp_targetaddr
        ldx zp_targetrow        // Load remaining rows.
add_rows:
        cpx #00                 // Test if more rows.
        beq cols_done           // If none, skip.
        clc                     // Prepare addition.
        adc #40                 // Add a line's worth of chars.
        sta zp_targetaddr       // Update zp_targetaddr
        dex                     // Substract row.
        bcc add_rows            // If no overflow, no need to increment hi byte.
        ldy zp_targetaddr+1     // Load hi byte
        iny                     // and increment.
        sty zp_targetaddr+1     // Write hibyte back.
        jmp add_rows
cols_done:
        lda zp_targetaddr       // Ensure lo byte is in A.
        clc                     // Prepare addition.
        adc zp_targetcol        // Add column chars.
        sta zp_targetaddr       // Update zp_targetaddr
        bcc rows_done           // If no overflow, no need to increment hi byte.
        ldy zp_targetaddr+1     // Load hi byte
        iny                     // and increment.
        sty zp_targetaddr+1     // Write hibyte back.
rows_done:

        ldy #$00        // Counter for indexing through characters.

nextchar:
        lda (zp_textaddr),Y        // Load current char into A.
        cmp #$00        // Is end of string?
        beq endstring   // If not, jump over return.
        sta (zp_targetaddr),Y       // Write to indexed screen target.
        iny
        jmp nextchar
endstring:
        rts             // Done, return.

        *=$1000 "Data"
txtstart:
txtmike:
        .text "mikerofone"
        .byte 0
txtmountain:
        .text "at mountainbytes"
        .byte 0