.var music = LoadSid("../Hybris.sid")
BasicUpstart2(text_init)

.const screen_base = $0400
.const char_tile_color_base = $D800
.const border_color_addr = $D020
.const background_color_addr = $D021
.const x_wobble_register = $D016
.const y_wobble_register = $D011

.const sprite_base_pointer_addr = $07F8
.const sprite_base_pos = $D000         // Starting from here positions X0,Y0,X1,Y1... are stored
.const sprite_base_color = $D027

// Consts for sprite rendering
.const sprite_x_spacing = 50
.const sprite_y_sine_distance = 8
.const num_sprites = 8
// Text-to-sprite constants
.const first_ascii_code = 32

.const sprite_enable = $D015
.const sprite_xpos_highbyte = $D010
.const sprite_double_x = $D01D
.const sprite_double_y = $D017
.const sprite_center_y_pos = 120


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
// Vars for text printing with cursor
.const zpw_cursoraddr = res_zpw()       // Global: Position of the cursor (0-999).
.const zpw_textaddr = res_zpw()         // Param: Address of text to display
.const zpb_targetrow = res_zpb()        // Param: Screen row to start printing at (0-24)
.const zpb_targetcol = res_zpb()        // Param: Screen column to start printing at (0-39)
.const zpw_screenaddr = res_zpw()       // Local: Screen RAM address computed from cursor.
.const zpw_coloraddr = res_zpw()        // Local: Color RAM address computed from cursor.
.const zpb_color = res_zpb()            // Param: Color to use for writing text.

.const zpb_tempval = res_zpb()          // Local: Temporary byte that might get clobbered by any
                                        //        jump to subroutine.
.const zpw_tempword = res_zpw()          // Local: Temporary word that might get clobbered by any
                                        //        jump to subroutine.

// Sprite flags
.const zpb_num_sprites = res_zpb()      // Global: Number of sprites to use
.const zpb_current_text_index = res_zpb()  // Global: Index into list_of_scrollers to select which text to display
.const zpb_next_char_index = res_zpb()  // Global: Next character from the string to use in the snek

// Main animation counters.
.const zpb_delayctr = res_zpb()         // Global: Delay counter that increases every main loop.
.const zpb_sine_table_idx = res_zpb()   // Global: Index in the sine curve table.

        *=$5000 "Code"

text_init:
        // ----------------- MUSIC INIT -----------------
        ldx #0
        ldy #0
        lda #music.startSong-1
        jsr music.init
        sei
        lda #<irq1
        sta $0314
        lda #>irq1
        sta $0315
        asl $d019
        lda #$7b
        sta $dc0d
        lda #$81
        sta $d01a
        lda #$1b
        sta $d011
        lda #$80
        sta $d012
        cli

        // ---------------- END MUSIC INIT


        // Init color.
        lda #12
        sta border_color_addr           // Border to black.
        lda #00
        sta border_color_addr+1         // Background to black.
        lda #01                         // Don't use black for foreground.
        sta zpb_color
        // Init counters.
        lda #00
        sta zpb_delayctr
        sta zpb_sine_table_idx
        sta zpb_current_text_index
        sta zpb_next_char_index
        jsr clearscreen
create_sprites:
        // Load sprite data from consecutive 64-bytes segments starting at $2040
        // Enable zpb_num_sprites sprites by cycling through them one by one
        // X: index of sprite
        // TODO First init all the double-step addresses, then do it again with single-step for enabling etc
        // Word on stack: xpos of sprite (accumulated over loop)
        lda #num_sprites                          // Number of sprites to enable
        sta zpb_num_sprites
        ldx #0                          // Start with sprite index 0
        lda #0                          // First sprite at x = 0 ($0000)
        pha
        lda #0
        pha
create_sprite:
        cpx zpb_num_sprites                          // Check if we've reached last index
        beq !done+

        // Initially, all sprites point to the first character (space = empty)
        lda #$c2                        // Sprite base address / 64 => $2080/$40=$82
        sta sprite_base_pointer_addr,X

        // The x/y registers are sequential, so steps of 2 are needed. Multiply X by 2.
        txa
        asl
        tax
        // Load X position from stack
        pla
        clc                             // Clear carry
        adc #sprite_x_spacing    // If carry, increment hi byte on stack
        sta sprite_base_pos,X
        pla                             // Pull hi byte (does not change carry)
        adc #0                             // Add carry to hi byte before writing
check_x_pos_hi:
        beq restore_x_to_stack
        // Need to set the high bit for this sprite
        txa                             // Restore real sprite index
        lsr
        tay                             // Count in Y
        lda #1
create_y_mask:
        cpy #0
        beq write_x_pos_hi
        asl
        dey
        jmp create_y_mask
write_x_pos_hi:
        ora sprite_xpos_highbyte        // Enable hi bit for this sprite
        sta sprite_xpos_highbyte
        lda #1                          // Restore x-pos hi byte to A
restore_x_to_stack:
        pha                             // Hi byte still in A
        lda sprite_base_pos,X           // Reload lo byte
        pha
write_y_pos:
        lda #sprite_center_y_pos
        inx                             // Y register is one behind X register
        sta sprite_base_pos,X
restore_index:
        // Restore X by shifting right, chopping off the increment.
        txa
        lsr
        tax

        lda #01
        sta sprite_base_color,X

        lda sprite_enable               // load X-MSB, then shift to left, adding a 1 on the right via carry, enabling one more sprite
        sec
        rol
        sta sprite_enable               // write X-MSB register
        sta sprite_double_x             // Set double-X mode
        sta sprite_double_y             // Set double-Y mode
        inx
        jmp create_sprite
!done:
        pla                             // Clean up stack
        pla
        lda #00                         // Initialize sine table index
        sta zpb_sine_table_idx

once_pre_loop:
        // Reset font parameters
        lda #1
        sta zpb_color

        jsr static_disk1

        // Attribution texts in bottom right corner
        lda #$9C
        sta zpw_cursoraddr
        lda #$03
        sta zpw_cursoraddr+1
        lda #11
        sta zpb_color
        lda #<txtmusicattrib
        sta zpw_textaddr
        lda #>txtmusicattrib
        sta zpw_textaddr+1
        jsr printtext

        lda #$CB
        sta zpw_cursoraddr
        lda #$03
        sta zpw_cursoraddr+1
        lda #11
        sta zpb_color
        lda #<txtfontattrib
        sta zpw_textaddr
        lda #>txtfontattrib
        sta zpw_textaddr+1
        jsr printtext

main_loop:
        //TODO do stuff
        ldx #1
        jsr sleep
        inc zpb_delayctr                // Increment delaycounter. Intended to simply overflow back to 0.
        lda zpb_delayctr
        cmp #2
        bne main_loop
delayed_main_loop:
        // Stuff that should happen when timer reached target
        lda #00                         // Reset delay timer.
        sta zpb_delayctr
!:
        jsr spritebounce
        jmp main_loop

// -------------- FOR MUSIC HANDLING --------------
irq1:
        asl $d019
        inc $d020
        jsr music.play
        dec $d020
        pla
        tay
        pla
        tax
        pla
        rti


// Set sprite with index X to ASCII value in A (range 32-95).
// X: The sprite to update.
// A: The ASCII value to show.
set_sprite_to_char:
        // ASCII bitmaps start in RAM at .ascii32, and are 64bytes in size.
        // The VIC register values contain RAM addresses divided by 64, so single-digit increments suffice.
        sec
        sbc #first_ascii_code           // Chop off the first ASCII codes that are not in the table
        clc
        adc #$c2                        // Add the address of the first ascii bitmap
        sta sprite_base_pointer_addr,X
        rts

spritebounce:
        ldx #0
!step:
        cpx #num_sprites
        beq !end+
        jsr sprite_step
        inx
        jmp !step-
!end:
        inc zpb_sine_table_idx          // Shift Y by one
        rts

// Move a sprite by one step.
// X: The sprite index to move.
// Clobbers A,Y.
//      Internal: Y double step index
sprite_step:
        txa
        tay
        lda zpb_sine_table_idx
!shift_loop:
        cpy #0
        beq !y_idx_found+
        clc
        adc sprite_y_sine_distance
        dey
        jmp !shift_loop-
!y_idx_found:
        tay
        lda sinetable, Y
        sta zpb_tempval                 // Store sine value in temp var
        // Double index to reach base position memory.
        txa
        asl
        tay
        iny                             // Updating Y position is +1 from X
        lda zpb_tempval
        sta sprite_base_pos,Y           // Store new value in Y register
        dey                             // Go back to X
        lda sprite_base_pos,Y           // Get current X address
        sec                             // Set borrow
        sbc #1                          // Will CLEAR carry if underflow
        sta sprite_base_pos,Y
        bcs !gotoend+
        // If underflow, then invert hibyte and set lobyte to respective max value for middle or right of screen.
        lda sprite_xpos_highbyte
        eor sprites_bitmasks,Y
        sta sprite_xpos_highbyte
        and sprites_bitmasks,Y          // Mask all other bits to check for zero
        beq !end+                       // If hibite is now zero, then regular decrement already set xpos to 255.
                                        // Otherwise set xpos to be just offscreen.
        lda #140
        sta sprite_base_pos,Y
        // Character respawns - update to next char from text
        ldy zpb_current_text_index
        cpy #0
        bne !nexttext+
        ldy zpb_next_char_index
        lda txtscroller1,Y
        cmp #0
        bne !print+
        // End of string, loop back and select next text, if any.
        jmp selectnexttext
!nexttext:
        dey
        cpy #0
        bne !nexttext+
        ldy zpb_next_char_index
        lda txtscroller2,Y
        cmp #0
        bne !print+
        // End of string, loop back and select next text, if any.
        jmp selectnexttext
!gotoend:
        jmp !end+
!nexttext:
        // Third text is the last text.
        ldy zpb_next_char_index
        lda txtscroller3,Y
        cmp #0
        bne !print+
        // End of last string go to final segment.
        jmp end_of_texts
selectnexttext:
        lda #$ED
        sta zpw_cursoraddr
        lda #$01
        sta zpw_cursoraddr+1
        lda #13
        sta zpb_color
        lda #<txturl
        sta zpw_textaddr
        lda #>txturl
        sta zpw_textaddr+1
        jsr printtext
        ldy #0;
        sty zpb_next_char_index
        // Skip to next text
        ldy zpb_current_text_index
        iny
        sty zpb_current_text_index
        lda 32                          // Load a space
        jsr set_sprite_to_char
        jmp !end+

        // Disable SID chip by killing the voices and setting the volume to 0
end_of_texts:
        lda #0
        sta $d418
        sta $d404
        sta $d40d
        sta $d412
        sei
        jsr start
!print:
        jsr set_sprite_to_char
        inc zpb_next_char_index

!end:
        rts

textcycle:
        lda #<txtwebsite
        sta zpw_textaddr
        lda #>txtwebsite
        sta zpw_textaddr+1
        jsr printtext
        // Move cursor right by # chars printed.
        jsr advance_cursor
        //jsr update_coords
        //jsr down_one_line?
        //jsr cycle_color

        ldx #1
        jsr sleep
        rts

// Cycles colors through 1-16.
cycle_color:
        lda zpb_color
        sta border_color_addr           // Border to previous color.
        ldx #01
        ldy #16
        jsr add_and_clamp
        sta zpb_color
        bne !+                          // If zero (black), skip over black and white.
        inc zpb_color
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
sleep:
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
        lda #>char_tile_color_base        // Init zpw_coloraddr.
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

        *=music.location "Music"
.fill music.size, music.getData(i)

        *=$3080 "Sprites"

        // 64 sprites generated with spritemate on 2/28/2026, 9:10:43 PM
        // Byte 64 of each sprite contains multicolor (high nibble) & color (low nibble) information

        // sprite 1 / singlecolor / color: $01
        ascii32:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 2 / singlecolor / color: $01
        ascii33:
        .byte $00,$00,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$fe,$00,$01,$fe,$00,$01
        .byte $fe,$00,$01,$fe,$00,$01,$fe,$00
        .byte $01,$fe,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$01

        // sprite 3 / singlecolor / color: $01
        ascii34:
        .byte $07,$87,$80,$07,$87,$80,$07,$87
        .byte $80,$07,$87,$80,$07,$87,$80,$01
        .byte $86,$00,$01,$86,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 4 / singlecolor / color: $01
        ascii35:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$07,$9e,$00,$07,$9e,$00,$07
        .byte $9e,$00,$07,$9e,$00,$1f,$ff,$80
        .byte $1f,$ff,$80,$07,$9e,$00,$07,$9e
        .byte $00,$07,$9e,$00,$07,$9e,$00,$07
        .byte $9e,$00,$07,$9e,$00,$1f,$ff,$80
        .byte $1f,$ff,$80,$07,$9e,$00,$07,$9e
        .byte $00,$07,$9e,$00,$07,$9e,$00,$01

        // sprite 5 / singlecolor / color: $01
        ascii36:
        .byte $00,$78,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $01,$80,$1e,$01,$80,$1e,$00,$00
        .byte $1e,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$18,$07,$80
        .byte $18,$07,$80,$1e,$07,$80,$1e,$07
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 6 / singlecolor / color: $01
        ascii37:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$1e
        .byte $01,$80,$1e,$01,$80,$1e,$07,$80
        .byte $1e,$07,$80,$00,$1e,$00,$00,$1e
        .byte $00,$00,$78,$00,$00,$78,$00,$01
        .byte $e0,$00,$01,$e0,$00,$07,$80,$00
        .byte $07,$80,$00,$1e,$07,$80,$1e,$07
        .byte $80,$18,$07,$80,$18,$07,$80,$01

        // sprite 7 / singlecolor / color: $01
        ascii38:
        .byte $00,$00,$00,$01,$f8,$00,$01,$f8
        .byte $00,$07,$9e,$00,$07,$9e,$00,$07
        .byte $9e,$00,$07,$9e,$00,$01,$f8,$00
        .byte $01,$f8,$00,$07,$e7,$80,$07,$e7
        .byte $80,$1e,$7e,$00,$1e,$7e,$00,$1e
        .byte $1e,$00,$1e,$1e,$00,$1e,$1e,$00
        .byte $1e,$1e,$00,$1e,$1e,$00,$1e,$1e
        .byte $00,$07,$e7,$80,$07,$e7,$80,$01

        // sprite 8 / singlecolor / color: $01
        ascii39:
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$01,$e0,$00,$01,$e0,$00,$07
        .byte $80,$00,$07,$80,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 9 / singlecolor / color: $01
        ascii40:
        .byte $00,$00,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$78,$00,$00,$78,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$1e,$00,$00,$1e,$00,$01

        // sprite 10 / singlecolor / color: $01
        ascii41:
        .byte $00,$00,$00,$01,$e0,$00,$01,$e0
        .byte $00,$00,$78,$00,$00,$78,$00,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01

        // sprite 11 / singlecolor / color: $01
        ascii42:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$07,$87,$80
        .byte $07,$87,$80,$01,$fe,$00,$01,$fe
        .byte $00,$1f,$ff,$e0,$1f,$ff,$e0,$01
        .byte $fe,$00,$01,$fe,$00,$07,$87,$80
        .byte $07,$87,$80,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 12 / singlecolor / color: $01
        ascii43:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$07,$ff,$80,$07,$ff,$80,$00
        .byte $78,$00,$00,$78,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 13 / singlecolor / color: $01
        ascii44:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01

        // sprite 14 / singlecolor / color: $01
        ascii45:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$1f,$ff,$80,$1f,$ff,$80,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 15 / singlecolor / color: $01
        ascii46:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$01

        // sprite 16 / singlecolor / color: $01
        ascii47:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $01,$80,$00,$01,$80,$00,$07,$80
        .byte $00,$07,$80,$00,$1e,$00,$00,$1e
        .byte $00,$00,$78,$00,$00,$78,$00,$01
        .byte $e0,$00,$01,$e0,$00,$07,$80,$00
        .byte $07,$80,$00,$1e,$00,$00,$1e,$00
        .byte $00,$18,$00,$00,$18,$00,$00,$01

        // sprite 17 / singlecolor / color: $01
        ascii48:
        .byte $00,$00,$00,$01,$fe,$00,$01,$fe
        .byte $00,$07,$87,$80,$07,$87,$80,$1e
        .byte $01,$e0,$1e,$01,$e0,$1e,$01,$e0
        .byte $1e,$01,$e0,$1e,$79,$e0,$1e,$79
        .byte $e0,$1e,$79,$e0,$1e,$79,$e0,$1e
        .byte $01,$e0,$1e,$01,$e0,$1e,$01,$e0
        .byte $1e,$01,$e0,$07,$87,$80,$07,$87
        .byte $80,$01,$fe,$00,$01,$fe,$00,$01

        // sprite 18 / singlecolor / color: $01
        ascii49:
        .byte $00,$00,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$f8,$00,$01,$f8,$00,$07
        .byte $f8,$00,$07,$f8,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$07,$ff,$80,$07,$ff,$80,$01

        // sprite 19 / singlecolor / color: $01
        ascii50:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$1e,$00
        .byte $00,$1e,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$e0,$00,$01,$e0,$00,$07
        .byte $80,$00,$07,$80,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1e,$07,$80,$1e,$07
        .byte $80,$1f,$ff,$80,$1f,$ff,$80,$01

        // sprite 20 / singlecolor / color: $01
        ascii51:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$01,$fe,$00,$01,$fe
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$1e,$07,$80,$1e,$07
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 21 / singlecolor / color: $01
        ascii52:
        .byte $00,$00,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$7e,$00,$00,$7e,$00,$01
        .byte $fe,$00,$01,$fe,$00,$07,$9e,$00
        .byte $07,$9e,$00,$1e,$1e,$00,$1e,$1e
        .byte $00,$1f,$ff,$80,$1f,$ff,$80,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$7f,$80,$00,$7f,$80,$01

        // sprite 22 / singlecolor / color: $01
        ascii53:
        .byte $00,$00,$00,$1f,$ff,$80,$1f,$ff
        .byte $80,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1f,$fe,$00,$1f,$fe
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$1e,$07,$80,$1e,$07
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 23 / singlecolor / color: $01
        ascii54:
        .byte $00,$00,$00,$01,$f8,$00,$01,$f8
        .byte $00,$07,$80,$00,$07,$80,$00,$1e
        .byte $00,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1f,$fe,$00,$1f,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $07,$80,$1e,$07,$80,$1e,$07,$80
        .byte $1e,$07,$80,$1e,$07,$80,$1e,$07
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 24 / singlecolor / color: $01
        ascii55:
        .byte $00,$00,$00,$1f,$ff,$80,$1f,$ff
        .byte $80,$1e,$07,$80,$1e,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$00,$1e,$00,$00,$1e
        .byte $00,$00,$78,$00,$00,$78,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01

        // sprite 25 / singlecolor / color: $01
        ascii56:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $07,$80,$1e,$07,$80,$1e,$07,$80
        .byte $1e,$07,$80,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $07,$80,$1e,$07,$80,$1e,$07,$80
        .byte $1e,$07,$80,$1e,$07,$80,$1e,$07
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 26 / singlecolor / color: $01
        ascii57:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $07,$80,$1e,$07,$80,$1e,$07,$80
        .byte $1e,$07,$80,$07,$ff,$80,$07,$ff
        .byte $80,$00,$07,$80,$00,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$00,$1e,$00,$00,$1e
        .byte $00,$07,$f8,$00,$07,$f8,$00,$01

        // sprite 27 / singlecolor / color: $01
        ascii58:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 28 / singlecolor / color: $01
        ascii59:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$78,$00,$00,$78
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01

        // sprite 29 / singlecolor / color: $01
        ascii60:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $1e,$00,$00,$1e,$00,$00,$78,$00
        .byte $00,$78,$00,$01,$e0,$00,$01,$e0
        .byte $00,$07,$80,$00,$07,$80,$00,$01
        .byte $e0,$00,$01,$e0,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$07,$80,$00,$07,$80,$01

        // sprite 30 / singlecolor / color: $01
        ascii61:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$07,$ff,$80
        .byte $07,$ff,$80,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$07
        .byte $ff,$80,$07,$ff,$80,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 31 / singlecolor / color: $01
        ascii62:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$07,$80,$00,$07,$80,$00,$01
        .byte $e0,$00,$01,$e0,$00,$00,$78,$00
        .byte $00,$78,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $1e,$00,$00,$1e,$00,$00,$78,$00
        .byte $00,$78,$00,$01,$e0,$00,$01,$e0
        .byte $00,$07,$80,$00,$07,$80,$00,$01

        // sprite 32 / singlecolor / color: $01
        ascii63:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$1e,$07,$80,$1e,$07,$80,$1e
        .byte $07,$80,$1e,$07,$80,$00,$1e,$00
        .byte $00,$1e,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$00
        .byte $78,$00,$00,$78,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$78,$00,$00,$78
        .byte $00,$00,$78,$00,$00,$78,$00,$01

        // sprite 33 / singlecolor / color: $01
        ascii64:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$03,$ff,$00,$03,$ff,$00,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$3f,$c0,$0f,$3f
        .byte $c0,$0f,$3f,$c0,$0f,$3f,$c0,$0f
        .byte $3f,$c0,$0f,$3f,$c0,$0f,$3f,$00
        .byte $0f,$3f,$00,$0f,$00,$00,$0f,$00
        .byte $00,$03,$ff,$00,$03,$ff,$00,$01

        // sprite 34 / singlecolor / color: $01
        ascii65:
        .byte $00,$00,$00,$00,$30,$00,$00,$30
        .byte $00,$00,$fc,$00,$00,$fc,$00,$03
        .byte $cf,$00,$03,$cf,$00,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$ff,$c0,$0f,$ff,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$01

        // sprite 35 / singlecolor / color: $01
        ascii66:
        .byte $00,$00,$00,$0f,$ff,$00,$0f,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$ff,$00,$03,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$0f,$ff,$00,$0f,$ff,$00,$01

        // sprite 36 / singlecolor / color: $01
        ascii67:
        .byte $00,$00,$00,$00,$ff,$00,$00,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$0f
        .byte $00,$c0,$0f,$00,$c0,$0f,$00,$00
        .byte $0f,$00,$00,$0f,$00,$00,$0f,$00
        .byte $00,$0f,$00,$00,$0f,$00,$00,$0f
        .byte $00,$00,$0f,$00,$00,$0f,$00,$c0
        .byte $0f,$00,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 37 / singlecolor / color: $01
        ascii68:
        .byte $00,$00,$00,$0f,$fc,$00,$0f,$fc
        .byte $00,$03,$cf,$00,$03,$cf,$00,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$cf,$00,$03,$cf
        .byte $00,$0f,$fc,$00,$0f,$fc,$00,$01

        // sprite 38 / singlecolor / color: $01
        ascii69:
        .byte $00,$00,$00,$0f,$ff,$c0,$0f,$ff
        .byte $c0,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c0,$c0,$03,$c0,$c0,$03,$cc,$00
        .byte $03,$cc,$00,$03,$fc,$00,$03,$fc
        .byte $00,$03,$cc,$00,$03,$cc,$00,$03
        .byte $c0,$00,$03,$c0,$00,$03,$c0,$c0
        .byte $03,$c0,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$0f,$ff,$c0,$0f,$ff,$c0,$01

        // sprite 39 / singlecolor / color: $01
        ascii70:
        .byte $00,$00,$00,$0f,$ff,$c0,$0f,$ff
        .byte $c0,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c0,$c0,$03,$c0,$c0,$03,$cc,$00
        .byte $03,$cc,$00,$03,$fc,$00,$03,$fc
        .byte $00,$03,$cc,$00,$03,$cc,$00,$03
        .byte $c0,$00,$03,$c0,$00,$03,$c0,$00
        .byte $03,$c0,$00,$03,$c0,$00,$03,$c0
        .byte $00,$0f,$f0,$00,$0f,$f0,$00,$01

        // sprite 40 / singlecolor / color: $01
        ascii71:
        .byte $00,$00,$00,$00,$ff,$00,$00,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$0f
        .byte $00,$c0,$0f,$00,$c0,$0f,$00,$00
        .byte $0f,$00,$00,$0f,$00,$00,$0f,$00
        .byte $00,$0f,$3f,$c0,$0f,$3f,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$00,$fc,$c0,$00,$fc,$c0,$01

        // sprite 41 / singlecolor / color: $01
        ascii72:
        .byte $00,$00,$00,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$ff,$c0,$0f,$ff
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$01

        // sprite 42 / singlecolor / color: $01
        ascii73:
        .byte $00,$00,$00,$00,$ff,$00,$00,$ff
        .byte $00,$00,$3c,$00,$00,$3c,$00,$00
        .byte $3c,$00,$00,$3c,$00,$00,$3c,$00
        .byte $00,$3c,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$3c,$00,$00,$3c,$00,$00
        .byte $3c,$00,$00,$3c,$00,$00,$3c,$00
        .byte $00,$3c,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 43 / singlecolor / color: $01
        ascii74:
        .byte $00,$00,$00,$00,$3f,$c0,$00,$3f
        .byte $c0,$00,$0f,$00,$00,$0f,$00,$00
        .byte $0f,$00,$00,$0f,$00,$00,$0f,$00
        .byte $00,$0f,$00,$00,$0f,$00,$00,$0f
        .byte $00,$00,$0f,$00,$00,$0f,$00,$0f
        .byte $0f,$00,$0f,$0f,$00,$0f,$0f,$00
        .byte $0f,$0f,$00,$0f,$0f,$00,$0f,$0f
        .byte $00,$03,$fc,$00,$03,$fc,$00,$01

        // sprite 44 / singlecolor / color: $01
        ascii75:
        .byte $00,$00,$00,$0f,$c3,$c0,$0f,$c3
        .byte $c0,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$cf,$00
        .byte $03,$cf,$00,$03,$fc,$00,$03,$fc
        .byte $00,$03,$fc,$00,$03,$fc,$00,$03
        .byte $cf,$00,$03,$cf,$00,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$0f,$c3,$c0,$0f,$c3,$c0,$01

        // sprite 45 / singlecolor / color: $01
        ascii76:
        .byte $00,$00,$00,$0f,$f0,$00,$0f,$f0
        .byte $00,$03,$c0,$00,$03,$c0,$00,$03
        .byte $c0,$00,$03,$c0,$00,$03,$c0,$00
        .byte $03,$c0,$00,$03,$c0,$00,$03,$c0
        .byte $00,$03,$c0,$00,$03,$c0,$00,$03
        .byte $c0,$00,$03,$c0,$00,$03,$c0,$c0
        .byte $03,$c0,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$0f,$ff,$c0,$0f,$ff,$c0,$01

        // sprite 46 / singlecolor / color: $01
        ascii77:
        .byte $00,$00,$00,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$c3,$f0,$0f,$c3,$f0,$0f
        .byte $ff,$f0,$0f,$ff,$f0,$0f,$ff,$f0
        .byte $0f,$ff,$f0,$0f,$3c,$f0,$0f,$3c
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0f
        .byte $00,$f0,$0f,$00,$f0,$0f,$00,$f0
        .byte $0f,$00,$f0,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$01

        // sprite 47 / singlecolor / color: $01
        ascii78:
        .byte $00,$00,$00,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$c3,$c0,$0f,$c3,$c0,$0f
        .byte $f3,$c0,$0f,$f3,$c0,$0f,$ff,$c0
        .byte $0f,$ff,$c0,$0f,$3f,$c0,$0f,$3f
        .byte $c0,$0f,$0f,$c0,$0f,$0f,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$01

        // sprite 48 / singlecolor / color: $01
        ascii79:
        .byte $00,$00,$00,$03,$ff,$00,$03,$ff
        .byte $00,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$03,$ff,$00,$03,$ff,$00,$01

        // sprite 49 / singlecolor / color: $01
        ascii80:
        .byte $00,$00,$00,$0f,$ff,$00,$0f,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$ff,$00,$03,$ff
        .byte $00,$03,$c0,$00,$03,$c0,$00,$03
        .byte $c0,$00,$03,$c0,$00,$03,$c0,$00
        .byte $03,$c0,$00,$03,$c0,$00,$03,$c0
        .byte $00,$0f,$f0,$00,$0f,$f0,$00,$01

        // sprite 50 / singlecolor / color: $01
        ascii81:
        .byte $00,$00,$00,$03,$ff,$00,$03,$ff
        .byte $00,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$33,$c0,$0f,$33,$c0,$0f
        .byte $3f,$c0,$0f,$3f,$c0,$03,$ff,$00
        .byte $03,$ff,$00,$00,$0f,$00,$00,$0f
        .byte $00,$00,$0f,$c0,$00,$0f,$c0,$01

        // sprite 51 / singlecolor / color: $01
        ascii82:
        .byte $00,$00,$00,$0f,$ff,$00,$0f,$ff
        .byte $00,$03,$c3,$c0,$03,$c3,$c0,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$ff,$00,$03,$ff
        .byte $00,$03,$cf,$00,$03,$cf,$00,$03
        .byte $c3,$c0,$03,$c3,$c0,$03,$c3,$c0
        .byte $03,$c3,$c0,$03,$c3,$c0,$03,$c3
        .byte $c0,$0f,$c3,$c0,$0f,$c3,$c0,$01

        // sprite 52 / singlecolor / color: $01
        ascii83:
        .byte $00,$00,$00,$03,$ff,$00,$03,$ff
        .byte $00,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$03,$c0,$00
        .byte $03,$c0,$00,$00,$fc,$00,$00,$fc
        .byte $00,$00,$0f,$00,$00,$0f,$00,$00
        .byte $03,$c0,$00,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$03,$ff,$00,$03,$ff,$00,$01

        // sprite 53 / singlecolor / color: $01
        ascii84:
        .byte $00,$00,$00,$0f,$ff,$f0,$0f,$ff
        .byte $f0,$0f,$3c,$f0,$0f,$3c,$f0,$0c
        .byte $3c,$30,$0c,$3c,$30,$00,$3c,$00
        .byte $00,$3c,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$3c,$00,$00,$3c,$00,$00
        .byte $3c,$00,$00,$3c,$00,$00,$3c,$00
        .byte $00,$3c,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 54 / singlecolor / color: $01
        ascii85:
        .byte $00,$00,$00,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$0f,$03,$c0,$0f,$03,$c0,$0f
        .byte $03,$c0,$0f,$03,$c0,$0f,$03,$c0
        .byte $0f,$03,$c0,$0f,$03,$c0,$0f,$03
        .byte $c0,$03,$ff,$00,$03,$ff,$00,$01

        // sprite 55 / singlecolor / color: $01
        ascii86:
        .byte $00,$00,$00,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0f
        .byte $00,$f0,$0f,$00,$f0,$0f,$00,$f0
        .byte $0f,$00,$f0,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0f
        .byte $00,$f0,$0f,$00,$f0,$03,$c3,$c0
        .byte $03,$c3,$c0,$00,$ff,$00,$00,$ff
        .byte $00,$00,$3c,$00,$00,$3c,$00,$01

        // sprite 56 / singlecolor / color: $01
        ascii87:
        .byte $00,$00,$00,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0f
        .byte $00,$f0,$0f,$00,$f0,$0f,$00,$f0
        .byte $0f,$00,$f0,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$3c,$f0,$0f,$3c,$f0,$0f
        .byte $3c,$f0,$0f,$3c,$f0,$0f,$ff,$f0
        .byte $0f,$ff,$f0,$03,$c3,$c0,$03,$c3
        .byte $c0,$03,$c3,$c0,$03,$c3,$c0,$01

        // sprite 57 / singlecolor / color: $01
        ascii88:
        .byte $00,$00,$00,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$03
        .byte $c3,$c0,$03,$c3,$c0,$00,$ff,$00
        .byte $00,$ff,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$3c,$00,$00,$3c,$00,$00
        .byte $ff,$00,$00,$ff,$00,$03,$c3,$c0
        .byte $03,$c3,$c0,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$01

        // sprite 58 / singlecolor / color: $01
        ascii89:
        .byte $00,$00,$00,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0f
        .byte $00,$f0,$0f,$00,$f0,$03,$c3,$c0
        .byte $03,$c3,$c0,$00,$ff,$00,$00,$ff
        .byte $00,$00,$3c,$00,$00,$3c,$00,$00
        .byte $3c,$00,$00,$3c,$00,$00,$3c,$00
        .byte $00,$3c,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 59 / singlecolor / color: $01
        ascii90:
        .byte $00,$00,$00,$0f,$ff,$f0,$0f,$ff
        .byte $f0,$0f,$00,$f0,$0f,$00,$f0,$0c
        .byte $03,$c0,$0c,$03,$c0,$00,$0f,$00
        .byte $00,$0f,$00,$00,$3c,$00,$00,$3c
        .byte $00,$00,$f0,$00,$00,$f0,$00,$03
        .byte $c0,$00,$03,$c0,$00,$0f,$00,$30
        .byte $0f,$00,$30,$0f,$00,$f0,$0f,$00
        .byte $f0,$0f,$ff,$f0,$0f,$ff,$f0,$01

        // sprite 60 / singlecolor / color: $01
        ascii91:
        .byte $00,$00,$00,$00,$ff,$00,$00,$ff
        .byte $00,$00,$f0,$00,$00,$f0,$00,$00
        .byte $f0,$00,$00,$f0,$00,$00,$f0,$00
        .byte $00,$f0,$00,$00,$f0,$00,$00,$f0
        .byte $00,$00,$f0,$00,$00,$f0,$00,$00
        .byte $f0,$00,$00,$f0,$00,$00,$f0,$00
        .byte $00,$f0,$00,$00,$f0,$00,$00,$f0
        .byte $00,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 61 / singlecolor / color: $01
        ascii92:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$0c,$00,$00,$0c,$00,$00,$0f
        .byte $00,$00,$0f,$00,$00,$0f,$c0,$00
        .byte $0f,$c0,$00,$03,$f0,$00,$03,$f0
        .byte $00,$00,$fc,$00,$00,$fc,$00,$00
        .byte $3f,$00,$00,$3f,$00,$00,$0f,$c0
        .byte $00,$0f,$c0,$00,$03,$c0,$00,$03
        .byte $c0,$00,$00,$c0,$00,$00,$c0,$01

        // sprite 62 / singlecolor / color: $01
        ascii93:
        .byte $00,$00,$00,$00,$ff,$00,$00,$ff
        .byte $00,$00,$0f,$00,$00,$0f,$00,$00
        .byte $0f,$00,$00,$0f,$00,$00,$0f,$00
        .byte $00,$0f,$00,$00,$0f,$00,$00,$0f
        .byte $00,$00,$0f,$00,$00,$0f,$00,$00
        .byte $0f,$00,$00,$0f,$00,$00,$0f,$00
        .byte $00,$0f,$00,$00,$0f,$00,$00,$0f
        .byte $00,$00,$ff,$00,$00,$ff,$00,$01

        // sprite 63 / singlecolor / color: $01
        ascii94:
        .byte $00,$00,$00,$00,$00,$00,$00,$30
        .byte $00,$00,$30,$00,$00,$fc,$00,$00
        .byte $fc,$00,$03,$cf,$00,$03,$cf,$00
        .byte $0f,$03,$c0,$0f,$03,$c0,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$01

        // sprite 64 / singlecolor / color: $01
        ascii95:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$0f,$ff,$f0,$0f,$ff,$f0,$01


        *=$4B00 "Textdata"
txtstart:
txtwebsite:
        .text "diskette.ch"
        .byte 0
txtfontattrib:
        .text "vga font by viler int10h.org"
        .byte 0
txtmusicattrib:
        .text "song 'hybris' by chris wemyss (atl)"
        .byte 0
txturl:
        .text "diskette.ch"
        .byte 0

txtemptyblock:  // Can be printed five times to fill the entire screen.
        .fill 200, ' '
        .byte 0
txtscroller1:
        .text "DEAR MOUNTAINBYTES 2026! GREETINGS FROM THE WORKSHOP - DOMINIKR AND MIKEROFONE HAD A TON OF FUN!          SO, WHY THAT DISKETTE, YOU ASK?!       OR, MAYBE YOU DON'T.       WE'LL TELL YOU ANYWAY.          "
        .byte 0
txtscroller2:
        .text "(THIS IS NOT AN AD - HERE WE CALL IT <AN INVITATION> RIGHT? :P )            MIKEROFONE IS OPENING A VINTAGE COMPUTER PLAYGROUND, <DIE DISKETTE>, HIGH UP NORTH IN THE SHIRE, IN SCHAFFHAUSEN.       HE'D LIKE TO INVITE YOU TO ITS GRAND OPENING!          "
        .byte 0
txtscroller3:
        .text "ON 14TH MARCH 2026, IT OPENS FOR THE FIRST TIME, FROM 11:00 TO 18:00, SHOWING PORTABLE COMPUTERS SINCE 1980. THEY ARE RUNNING AND EAGER FOR YOU TO EXPLORE THEM.     ADMISSION IS FREE!    FIND ALL DETAILS ON DISKETTE.CH.     THANK YOU! <3 <3         "
        .byte 0


        *=$4800 "Tables"
sinetable:
        .fill 256, 185 + 22*sin(toRadians(i*360/256))
flatsine:
        .fill 256, 3.5 + 3.5*sin(toRadians(i*720/256))
sprites_start_x: // Spaced out in steps of 73 pixels
        .fill 8, i*73
sprites_bitmasks: // For easier accessing of single-sprit bits, double-indexed
        .byte %00000001
        .byte %00000001
        .byte %00000010
        .byte %00000010
        .byte %00000100
        .byte %00000100
        .byte %00001000
        .byte %00001000
        .byte %00010000
        .byte %00010000
        .byte %00100000
        .byte %00100000
        .byte %01000000
        .byte %01000000
        .byte %10000000
        .byte %10000000
list_of_scrollers:
        .word txtscroller1
        .word txtscroller2
        .word txtscroller3
        .byte 0


#import "../disk2.asm"
#import "../static-disk.asm"