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
.const zpw_cursoraddr = res_zpw()       // Global: Position of the cursor (0-999).
.const zpw_textaddr = res_zpw()         // Param: Address of text to display
.const zpb_targetrow = res_zpb()        // Param: Screen row to start printing at (0-24)
.const zpb_targetcol = res_zpb()        // Param: Screen column to start printing at (0-39) 
.const zpw_screenaddr = res_zpw()       // Local: Screen RAM address computed from cursor.
.const zpw_coloraddr = res_zpw()        // Local: Color RAM address computed from cursor.
.const zpb_color = res_zpb()            // Param: Color to use for writing text.
.const zpb_tempval = res_zpb()          // Local: Temporary byte that might get clobbered by any
                                        //        jump to subroutine.

        *=$4000 "Code"

main:
        // Init color.
        lda #00
        // sta border_color_addr           // Border to black.
        sta border_color_addr+1         // Background to black.
        lda #01                         // Don't use black for foreground.
        sta zpb_color
        jsr clearscreen
flicker:
        lda #<txtmike
        sta zpw_textaddr
        lda #>txtmike
        sta zpw_textaddr+1
        jsr printtext
        // Move cursor right by # chars printed.
        jsr advance_cursor
        //jsr update_coords
        //jsr down_one_line?

        lda #<txtmountain
        sta zpw_textaddr
        lda #>txtmountain
        sta zpw_textaddr+1
        jsr printtext
        // Move cursor right by # chars printed.
        jsr advance_cursor
        // jsr update_coords
        // ldx #10
        // jsr wait

        jsr cycle_color

        jmp flicker

// Cycles colors through 1-16.
cycle_color:
        lda zpb_color
        ldx #01
        ldy #15
        jsr add_and_clamp
        sta zpb_color
        bne !+                          // If zero (black), increment.
        inc zpb_color
!:
        rts

// Gets row and col from zpb_targetrow/zpb_targetcol, increments them
// by some value and clamping to range, and writes them back.
update_coords:
        // lda zpb_targetrow
        // ldx #03
        // ldy #25
        // jsr add_and_clamp
        // sta zpb_targetrow
        lda zpb_targetcol
        ldx #07
        ldy #40                 // Bug: should be ldy, but results in
                                // more interesting output. ¯\_(ツ)_/¯
        jsr add_and_clamp
        sta zpb_targetcol
        jsr set_cursor_xy       // Update zpw_cursoraddr from zpb_targetcol/row.
        rts


// Move the cursor to zpb_targetrow and zpb_targetcol.
// Clobbers A, X, Y.
set_cursor_xy:
        lda #00                 // Reset cursor to 0.
        sta zpw_cursoraddr
        sta zpw_cursoraddr+1
        ldx zpb_targetrow       // Load rows to add.
add_rows:
        cpx #00                 // Test if more rows.
        beq add_cols            // If none, skip.
        dex
        lda #40                 // Advance cursor by one row of chars.
        jsr advance_cursor
        jmp add_rows
add_cols:
        lda zpb_targetcol       // Advance cursor by column-many chars.
        jsr advance_cursor
        rts

// Move cursor down one line, wrapping around the screen. Clobbers A, Y.
down_one_line:
        lda #40
        // Continue into advance_cursor.
// Moves cursor right by the amount of characters in A. Clobbers A, Y.
// Wraps around the screen.
advance_cursor:
        clc                     // Prepare addition.
        adc zpw_cursoraddr      // Add cursor lo byte to # chars in A.
        sta zpw_cursoraddr      // Update cursor lo byte.
        bcc maybe_wrap_cursor   // If no overflow, no need to increment hi byte.
        ldy zpw_cursoraddr+1    // Load cursor hi byte, increment and write back.
        iny
        sty zpw_cursoraddr+1
// If the cursor goes off screen, wrap it around. Clobbers A and Y.
maybe_wrap_cursor:
        ldy zpw_cursoraddr+1    // Load cursor hi byte.
        // If zpw_cursoraddr > $03E8, then wrap it around.
        cpy #$03                // Compare hi byte.
        bcc !return+            // Carry not set -> hi byte is < $02.
        bne must_wrap           // Carry set, zero unset set -> hi byte is > $03
        // Hi byte is #03, must compare lo byte: No overflow if that's <$E8.
        lda zpw_cursoraddr      // Load lo byte to compare
        cmp #$E8
        bcc !return+            // Carry not set -> lo byte <$E8.
must_wrap:
        // Subtract $03E8.
        sec                     // Set carry for subtraction
        lda zpw_cursoraddr      // Start on lo byte.
        sbc #$E8
        sta zpw_cursoraddr      // Store new lo byte.
        lda zpw_cursoraddr+1
        sbc #$03
        sta zpw_cursoraddr+1    // Store new lo byte. Should now be wrapped back.
!return:
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

// Fills the screen with spaces. Clobbers zpb_textaddr and resets cursor address to 0.
clearscreen:
        lda #<txtemptyblock
        sta zpw_textaddr
        lda #>txtemptyblock
        sta zpw_textaddr+1
        // Step through rows from the top, pasting a 5-row string of spaces.
        lda #00
        sta zpw_cursoraddr
        sta zpw_cursoraddr+1
        jsr printtext
        jsr advance_cursor
        jsr printtext
        jsr advance_cursor
        jsr printtext
        jsr advance_cursor
        jsr printtext
        // Set cursor to top-left.
        lda #00
        sta zpw_cursoraddr
        sta zpw_cursoraddr+1
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


// Print the text at the current cursor position. See set_cursor_xy to set the cursor
// to a specific position.
// Returns number of characters printed in accumulator on return.
printtext:
        // Assemble addresses for screen and color. Only hi byte differs, lo byte
        // can be shared for both screen and color.
        lda #>screen_base       // Init zpw_screenaddr.
        clc
        adc zpw_cursoraddr + 1  // Add cursor hi byte.
        sta zpw_screenaddr + 1
        lda #>color_base        // Init zpw_coloraddr.
        clc
        adc zpw_cursoraddr + 1
        sta zpw_coloraddr + 1
        lda #<screen_base       // If base lo bytes for screen and color are not 00,
                                // this will go wrong.
        clc
        adc zpw_cursoraddr      // Add cursor lo byte.
        sta zpw_screenaddr      // Apply cursor movement to screen...
        sta zpw_coloraddr       // ...and color RAM.

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
        tya                     // Copy # of chars printed from Y to A.
        rts                     // Done, return.

        *=$1000 "Data"
txtstart:
txtmike:
        .text "mikerofone "
        .byte 0
txtmountain:
        .text "at mountainbytes"
        .byte 0
txtemptyblock:  // Can be printed five times to fill the entire screen.
        .fill 200, ' '
        .byte 0