BasicUpstart2(main)

.const screen_base = $0400
.const color_base = $D800
.const border_color_addr = $D020
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
.const zpw_screenaddr = res_zpw()       // Local: Screen RAM address computed from (targetrow, targetcol).
.const zpw_coloraddr = res_zpw()        // Local: Color RAM address computed from (targetrow, targetcol).
.const zpb_color = res_zpb()            // Param: Color to use for writing text.
.const zpb_tempval = res_zpb()          // Local: Temporary byte that might get clobbered by any
                                        //        jump to subroutine.

        *=$4000 "Code"

main:
        // Init row and col.
        lda #2
        sta zpb_targetrow
        pha                             // Push to stack so it can be recovered later.
        lda #7
        sta zpb_targetcol
        pha                             // Push to stack so it can be recovered later.
        // Init color.
        lda #00
        sta border_color_addr           // Border to black.
        sta border_color_addr+1         // Background to black.
        lda #01                         // Don't use black for forground.
        sta zpb_color
        jsr clearscreen
flicker:

        // Recover last values from stack, first col, then row.
        pla
        sta zpb_targetcol
        pla
        sta zpb_targetrow
        lda #<txtmike
        sta zpw_textaddr
        lda #>txtmike
        sta zpw_textaddr+1
        jsr printtext
        jsr update_coords       // Or jsr down_one_line?

        lda #<txtmountain
        sta zpw_textaddr
        lda #>txtmountain
        sta zpw_textaddr+1
        jsr printtext
        jsr update_coords
        // ldx #100
        // jsr wait

        // Save coords to stack so zpb_target{row,col} can be clobbered.
        lda zpb_targetrow
        pha
        lda zpb_targetcol
        pha

        jsr cycle_color

        jmp flicker

// Cycles colors through 1-16.
cycle_color:
        lda zpb_color
        ldx #01
        ldy #16
        jsr add_and_clamp
        sta zpb_color
        bne !+                          // If zero (black), increment.
        inc zpb_color
!:
        rts

// Gets row and col from zpb_targetrow/zpb_targetcol, increments them
// by some value and clamping to range, and writes them back.
update_coords:
        lda zpb_targetrow
        ldx #03
        ldy #25
        jsr add_and_clamp
        sta zpb_targetrow
        lda zpb_targetcol
        ldx #07
        ldx #40                 // Bug: should be ldy, but results in
                                // more interesting output. ¯\_(ツ)_/¯
        jsr add_and_clamp
        sta zpb_targetcol
        rts


// Move cursor down one line, wrapping around the screen.
down_one_line:
        lda zpb_targetrow
        ldx #01
        ldy #25
        jsr add_and_clamp
        sta zpb_targetrow
        rts


// Have value to inc in A, amount to inc in X and max value in Y.
// Returns new value in A.
// Will return garbage if A+X>255.
add_and_clamp:
        stx zpb_tempval
        clc
        adc zpb_tempval
        // A now is A+X
        sty zpb_tempval
        cmp zpb_tempval // Will set carry if A>=zpb_tempval
        bcc !return+    // A+X < Y, so return.
        sbc zpb_tempval // A=A-Y
!return:
        rts

// Fills the screen with spaces. Clobbers zpb_targetcol/row and zpb_textaddr.
clearscreen:
        lda #<txtemptyblock
        sta zpw_textaddr
        lda #>txtemptyblock
        sta zpw_textaddr+1
        // Step through rows in 5-increments, and paste a 5-row string of spaces.
        lda #00
        sta zpb_targetcol
        sta zpb_targetrow               // Start at row 0.
        jsr printtext
        lda #05
        sta zpb_targetrow
        jsr printtext
        lda #10
        sta zpb_targetrow
        jsr printtext
        lda #15
        sta zpb_targetrow
        jsr printtext
        lda #20
        sta zpb_targetrow
        jsr printtext
        rts

// Waits for a while, determined by value in X.
wait:
!loop:        
        cpx #00
        beq !end+
        ldy #255
        dex
!loop:
        dey
        cpy #00
        bne !loop-
        jmp !loop--
!end:
        rts

// Print the text starting at address in zpw_textaddr to the screen at coordinates
// zpb_targetrow and zpb_targetcol.
printtext:
        // Assemble addresses for screen and color. Only hi byte differs, lo byte
        // can be shared for both screen and color.
        lda #>screen_base       // Init zpw_screenaddr.
        sta zpw_screenaddr + 1
        lda #>color_base        // Init zpw_coloraddr.
        sta zpw_coloraddr + 1
        lda #<screen_base       // Low bytes for screen and color must be the same!
        sta zpw_screenaddr
        sta zpw_coloraddr
        ldx zpb_targetrow       // Load remaining rows.
add_rows:
        cpx #00                 // Test if more rows.
        beq rows_done           // If none, skip.
        clc                     // Prepare addition.
        adc #40                 // Add a line's worth of chars.
        sta zpw_screenaddr      // Update screen and color address lo bytes.
        sta zpw_coloraddr 
        dex                     // Substract row.
        bcc add_rows            // If no overflow, no need to increment hi byte.
        ldy zpw_screenaddr+1    // Load screen/color hi bytes, increment and write back.
        iny
        sty zpw_screenaddr+1
        ldy zpw_coloraddr+1
        iny
        sty zpw_coloraddr+1
        jmp add_rows
rows_done:
        lda zpw_screenaddr      // Ensure lo byte is in A.
        clc                     // Prepare addition.
        adc zpb_targetcol       // Add column chars.
        sta zpw_screenaddr      // Update lo bytes for screen and color.
        sta zpw_coloraddr
        bcc copy_chars          // If no overflow, no need to increment hi byte.
        ldy zpw_screenaddr+1    // Load screen/color hi bytes, increment and write back.
        iny
        sty zpw_screenaddr+1
        ldy zpw_coloraddr+1
        iny
        sty zpw_coloraddr+1

copy_chars:
        ldy #$00                // Counter for indexing through characters.
nextchar:
        lda (zpw_textaddr),Y    // Load current char into A.
        cmp #$00                // Is end of string?
        beq endstring           // If not, jump over return.
        sta (zpw_screenaddr),Y  // Write to indexed screen target.
        lda zpb_color           // Load color to use.
        sta (zpw_coloraddr),Y   // Write to indexed color target.
        iny
        jmp nextchar
endstring:
        rts                     // Done, return.

        *=$1000 "Data"
txtstart:
txtmike:
        .text "mikerofone"
        .byte 0
txtmountain:
        .text "at mountainbytes"
        .byte 0
txtemptyblock:  // Can be printed five times to fill the entire screen.
        .fill 200, ' '
        .byte 0