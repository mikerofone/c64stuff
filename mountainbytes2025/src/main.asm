BasicUpstart2(main)

.const screen_base = $0400

// We don't use BASIC, so make use of the entire zero page starting at $02.
.var next_zp = $02
// Reserve a zero space address for a byte.
.function res_zpb() {
        .return next_zp++
}
// Reserve a zero space address for a word.
.function res_zpw() {
        .eval next_zp++
        .return next_zp++ - 1
}
// zpw: Word (address), zpb: Byte
.const zpw_textaddr = res_zpw()         // Param: Address of text to display
.const zpb_targetrow = res_zpb()        // Param: Screen row to start printing at (0-24)
.const zpb_targetcol = res_zpb()        // Param: Screen column to start printing at (0-39) 
.const zpw_targetaddr = res_zpw()       // Local: Address computed from (targetrow, targetcol).
.const zpb_temp1 = res_zpb()            // Local: Temporary byte that might get clobbered by any
                                        //        jump to subroutine.

        *=$4000 "Code"

main:
        // Init row and col.
        lda #0
        sta zpb_targetrow
        lda #0
        sta zpb_targetcol
flicker:
        lda #<txtmike
        sta zpw_textaddr
        lda #>txtmike
        sta zpw_textaddr+1
        jsr printtext
        jsr update_coords

        lda #<txtmountain
        sta zpw_textaddr
        lda #>txtmountain
        sta zpw_textaddr+1
        jsr printtext
        jsr update_coords
        
        jmp flicker

// Gets row and col from zpb_targetrow/zpb_targetcol, increments by
// 7 (col) / 3 (row) clamping to value range, and writes them back.
update_coords:
        lda zpb_targetrow
        ldx #03
        ldy #25
        jsr add_and_clamp
        sta zpb_targetrow
        lda zpb_targetcol
        ldx #07
        ldx #40
        jsr add_and_clamp
        sta zpb_targetcol
        rts

// Have value to inc in A, amount to inc in X and max value in Y.
// Returns new value in A.
// Will return garbage if A+X>255.
add_and_clamp:
        stx zpb_temp1
        clc
        adc zpb_temp1
        // A now is A+X
        sty zpb_temp1
        cmp zpb_temp1   // Will set carry if A>=zpb_temp1
        bcc !return+    // A+X < Y, so return.
        sbc zpb_temp1   // A=A-Y
!return:
        rts

clearscreen:
        ldx #$00


// Print the text starting at address in zpw_textaddr to the screen at coordinates
// zpb_targetrow and zp_targercol.
printtext:
        // Assemble screen address.
        lda #>screen_base       // Init zpw_targetaddr with base address.
                                // Start with hi byte so we can keep using lo byte.
        sta zpw_targetaddr + 1
        lda #<screen_base       
        sta zpw_targetaddr
        ldx zpb_targetrow        // Load remaining rows.
add_rows:
        cpx #00                 // Test if more rows.
        beq cols_done           // If none, skip.
        clc                     // Prepare addition.
        adc #40                 // Add a line's worth of chars.
        sta zpw_targetaddr       // Update zpw_targetaddr
        dex                     // Substract row.
        bcc add_rows            // If no overflow, no need to increment hi byte.
        ldy zpw_targetaddr+1     // Load hi byte
        iny                     // and increment.
        sty zpw_targetaddr+1     // Write hibyte back.
        jmp add_rows
cols_done:
        lda zpw_targetaddr       // Ensure lo byte is in A.
        clc                     // Prepare addition.
        adc zpb_targetcol        // Add column chars.
        sta zpw_targetaddr       // Update zpw_targetaddr
        bcc rows_done           // If no overflow, no need to increment hi byte.
        ldy zpw_targetaddr+1     // Load hi byte
        iny                     // and increment.
        sty zpw_targetaddr+1     // Write hibyte back.
rows_done:
        ldy #$00        // Counter for indexing through characters.

nextchar:
        lda (zpw_textaddr),Y        // Load current char into A.
        cmp #$00        // Is end of string?
        beq endstring   // If not, jump over return.
        sta (zpw_targetaddr),Y       // Write to indexed screen target.
        iny
        jmp nextchar
endstring:
        rts             // Done, return.

        *=$1000 "Data"
txtstart:
txtmike:
        .text "mikerofone "
        .byte 0
txtmountain:
        .text "at mountainbytes "
        .byte 0