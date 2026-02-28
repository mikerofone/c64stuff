BasicUpstart2(init)

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
.const sprite_sprite_x_spacing = 55
.const num_sprites = 8

// .const sprite_0_pointer_addr = $07F8
.const sprite_0_xpos = $D000
.const sprite_0_ypos = $D001
// .const sprite_0_color = $D027
// .const sprite_1_pointer_addr = $07F9
.const sprite_1_xpos = $D002
.const sprite_1_ypos = $D003
// .const sprite_1_color = $D028
// .const sprite_2_pointer_addr = $07FA
.const sprite_2_xpos = $D004
.const sprite_2_ypos = $D005
// .const sprite_2_color = $D029
// .const sprite_3_pointer_addr = $07FB
.const sprite_3_xpos = $D006
.const sprite_3_ypos = $D007
// .const sprite_3_color = $D02A
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

// Sprite flags
.const zpb_num_sprites = res_zpb()      // Global: Number of sprites to use

// Main animation counters.
.const zpb_delayctr = res_zpb()         // Global: Delay counter that increases every main loop.
.const zpb_sine_table_idx = res_zpb()   // Global: Index in the sine curve table.
.const zpb_wobble_mode_counter = res_zpb()      // Global: Currently active wobble variant.
.const zpb_wobble_mode = res_zpb()      // Global: Current wobble mode: 0 none, 1 x, 2 y, 3 x+y

        *=$4000 "Code"

init:
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
        sta zpb_wobble_mode_counter
        sta zpb_wobble_mode
        jsr clearscreen
create_sprites:
        // Load sprite data from consecutive 64-bytes segments starting at $2040
        // Enable zpb_num_sprites sprites by cycling through them one by one
        // X: index of sprite
        // TODO First init all the single-step addresses, then do it again with 2-step for the positions
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

        txa                             // Compute base pointer address as $81+X
        adc #$81                        // Sprite base address / 64 => $2040/$40=$81
        sta sprite_base_pointer_addr,X

        // The x/y registers are sequential, so steps of 2 are needed. Multiply X by 2.
        txa
        asl
        tax
        // Load X position from stack
        pla
        clc                             // Clear carry
        adc #sprite_sprite_x_spacing    // If carry, increment hi byte on stack
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
        // Font attribution text in bottom right corner
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

        // Reset font parameters
        lda #1
        sta zpb_color
        //jsr textcycle
main_loop:
        //TODO do stuff
        ldx #1
        jsr wait
        inc zpb_delayctr                // Increment delaycounter. Intended to simply overflow back to 0.
        lda zpb_delayctr
        cmp #8
        bne main_loop
delayed_main_loop:
        // Stuff that should happen when timer reached target
        lda #00                         // Reset delay timer.
        sta zpb_delayctr
        // inc zpb_wobble_mode_counter     // Tick wobble counter. On overflow go to next wobble mode.
        // bne !+
        // inc zpb_wobble_mode
        // lda zpb_wobble_mode
        // cmp #04                         // Cycle through the four modes.
        // bne !+
        // lda #00                         // Loop around to 0.
        // sta zpb_wobble_mode
!:
        //jsr spritebounce
        // jsr wobble
        jmp main_loop


spritebounce:
        ldx sprite_0_xpos               // Move sprite along x.
        bne !regular_decrement+         // If xpos == 0, then twiddle hibyte and set lobyte to respective max value.
        lda sprite_xpos_highbyte
        eor #%00000001
        sta sprite_xpos_highbyte
        and #%00000001                  // Mask all other bits to check for zero
        beq !regular_decrement+         // If hibite zero, then regular decrement sets xpos to 255.
                                        // Otherwise set xpos to (effectively) 320.
        ldx #65
        stx sprite_0_xpos
        jmp !next_sprite_move+
!regular_decrement:
        dex
        stx sprite_0_xpos
!next_sprite_move:
        ldx sprite_1_xpos               // Move sprite along x.
        bne !regular_decrement+         // If xpos == 0, then twiddle hibyte and set lobyte to respective max value.
        lda sprite_xpos_highbyte
        eor #%00000010
        sta sprite_xpos_highbyte
        and #%00000001                  // Mask all other bits to check for zero
        beq !regular_decrement+         // If hibite zero, then regular decrement sets xpos to 255.
                                        // Otherwise set xpos to (effectively) 320.
        ldx #65
        stx sprite_1_xpos
        jmp !next_sprite_move+
!regular_decrement:
        dex
        stx sprite_1_xpos
!next_sprite_move:

        // TODO: Make letters snake instead of move vertically as a unit
        ldx zpb_sine_table_idx          // Set all sprite's Y to sinewave.
        lda sinetable, x
        sta sprite_0_ypos
        sta sprite_1_ypos
        sta sprite_2_ypos
        sta sprite_3_ypos
        inc zpb_sine_table_idx
!end:
        rts

// wobble:
//         // Wobble based on zpb_wobble_mode.
// x_wobble:
//         lda x_wobble_register
//         and #%11111000                  // Clear last three bits.
//         sta zpb_tempval
//         lda zpb_sine_table_idx          // Set sprite Y to sinewave.
//         clc
//         adc #96                        // min_val is aligned, so shift by a 3/4-cycle.
//                                         // Cycle length is 128, so add 96.
//         tax
//         lda flatsine, X                 // Get offset value.
//         ora zpb_tempval
//         sta x_wobble_register
// y_wobble:
//         lda y_wobble_register
//         and #%11111000                  // Clear last three bits.
//         sta zpb_tempval
//         ldx zpb_sine_table_idx          // Set sprite Y to sinewave.
//         lda flatsine, X                 // Get offset value.
//         ora zpb_tempval
//         sta y_wobble_register
// !end:
//         rts

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

        // //lda #<txtwobbel
        // sta zpw_textaddr
        // //lda #>txtwobbel
        // sta zpw_textaddr+1
        // jsr printtext
        // // Move cursor right by # chars printed.
        // jsr advance_cursor
        // // jsr update_coords
        // // jsr cycle_color

        // //lda #<txt2k
        // sta zpw_textaddr
        // //lda #>txt2k
        // sta zpw_textaddr+1
        // jsr printtext
        // // Move cursor right by # chars printed.
        // jsr advance_cursor
        // // jsr update_coords
        // jsr cycle_color


        ldx #1
        jsr wait
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

        *=$2040 "Sprites"
        // 26 sprites generated with spritemate on 2/28/2026, 2:20:48 AM
        // Byte 64 of each sprite contains multicolor (high nibble) & color (low nibble) information

        // sprite 1 / singlecolor / color: $01
        sprite_data_a:
        .byte $00,$00,$00,$00,$18,$00,$00,$18
        .byte $00,$00,$7e,$00,$00,$7e,$00,$01
        .byte $e7,$80,$01,$e7,$80,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$ff,$e0,$07,$ff,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$01

        // sprite 2 / singlecolor / color: $01
        sprite_data_b:
        .byte $00,$00,$00,$07,$ff,$80,$07,$ff
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$ff,$80,$01,$ff
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$e1,$e0,$01,$e1
        .byte $e0,$07,$ff,$80,$07,$ff,$80,$01

        // sprite 3 / singlecolor / color: $01
        sprite_data_c:
        .byte $00,$00,$00,$00,$7f,$80,$00,$7f
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$07
        .byte $80,$60,$07,$80,$60,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$00,$07,$80,$00,$07
        .byte $80,$00,$07,$80,$00,$07,$80,$60
        .byte $07,$80,$60,$01,$e1,$e0,$01,$e1
        .byte $e0,$00,$7f,$80,$00,$7f,$80,$01

        // sprite 4 / singlecolor / color: $01
        sprite_data_d:
        .byte $00,$00,$00,$07,$fe,$00,$07,$fe
        .byte $00,$01,$e7,$80,$01,$e7,$80,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$e1,$e0,$01,$e1
        .byte $e0,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$e7,$80,$01,$e7
        .byte $80,$07,$fe,$00,$07,$fe,$00,$01

        // sprite 5 / singlecolor / color: $01
        sprite_data_e:
        .byte $00,$00,$00,$07,$ff,$e0,$07,$ff
        .byte $e0,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e0,$60,$01,$e0,$60,$01,$e6,$00
        .byte $01,$e6,$00,$01,$fe,$00,$01,$fe
        .byte $00,$01,$e6,$00,$01,$e6,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$60
        .byte $01,$e0,$60,$01,$e1,$e0,$01,$e1
        .byte $e0,$07,$ff,$e0,$07,$ff,$e0,$01

        // sprite 6 / singlecolor / color: $01
        sprite_data_f:
        .byte $00,$00,$00,$07,$ff,$e0,$07,$ff
        .byte $e0,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e0,$60,$01,$e0,$60,$01,$e6,$00
        .byte $01,$e6,$00,$01,$fe,$00,$01,$fe
        .byte $00,$01,$e6,$00,$01,$e6,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$07,$f8,$00,$07,$f8,$00,$01

        // sprite 7 / singlecolor / color: $01
        sprite_data_g:
        .byte $00,$00,$00,$00,$7f,$80,$00,$7f
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$07
        .byte $80,$60,$07,$80,$60,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$9f,$e0,$07,$9f,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$01,$e1,$e0,$01,$e1
        .byte $e0,$00,$7e,$60,$00,$7e,$60,$01

        // sprite 8 / singlecolor / color: $01
        sprite_data_h:
        .byte $00,$00,$00,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$ff,$e0,$07,$ff
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$01

        // sprite 9 / singlecolor / color: $01
        sprite_data_i:
        .byte $00,$00,$00,$00,$7f,$80,$00,$7f
        .byte $80,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$7f,$80,$00,$7f,$80,$01

        // sprite 10 / singlecolor / color: $01
        sprite_data_j:
        .byte $00,$00,$00,$00,$1f,$e0,$00,$1f
        .byte $e0,$00,$07,$80,$00,$07,$80,$00
        .byte $07,$80,$00,$07,$80,$00,$07,$80
        .byte $00,$07,$80,$00,$07,$80,$00,$07
        .byte $80,$00,$07,$80,$00,$07,$80,$07
        .byte $87,$80,$07,$87,$80,$07,$87,$80
        .byte $07,$87,$80,$07,$87,$80,$07,$87
        .byte $80,$01,$fe,$00,$01,$fe,$00,$01

        // sprite 11 / singlecolor / color: $01
        sprite_data_k:
        .byte $00,$00,$00,$07,$e1,$e0,$07,$e1
        .byte $e0,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e7,$80
        .byte $01,$e7,$80,$01,$fe,$00,$01,$fe
        .byte $00,$01,$fe,$00,$01,$fe,$00,$01
        .byte $e7,$80,$01,$e7,$80,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$e1,$e0,$01,$e1
        .byte $e0,$07,$e1,$e0,$07,$e1,$e0,$01

        // sprite 12 / singlecolor / color: $01
        sprite_data_l:
        .byte $00,$00,$00,$07,$f8,$00,$07,$f8
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$01,$e0,$00,$01,$e0,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$60
        .byte $01,$e0,$60,$01,$e1,$e0,$01,$e1
        .byte $e0,$07,$ff,$e0,$07,$ff,$e0,$01

        // sprite 13 / singlecolor / color: $01
        sprite_data_m:
        .byte $00,$00,$00,$07,$80,$78,$07,$80
        .byte $78,$07,$e1,$f8,$07,$e1,$f8,$07
        .byte $ff,$f8,$07,$ff,$f8,$07,$ff,$f8
        .byte $07,$ff,$f8,$07,$9e,$78,$07,$9e
        .byte $78,$07,$80,$78,$07,$80,$78,$07
        .byte $80,$78,$07,$80,$78,$07,$80,$78
        .byte $07,$80,$78,$07,$80,$78,$07,$80
        .byte $78,$07,$80,$78,$07,$80,$78,$01

        // sprite 14 / singlecolor / color: $01
        sprite_data_n:
        .byte $00,$00,$00,$07,$81,$e0,$07,$81
        .byte $e0,$07,$e1,$e0,$07,$e1,$e0,$07
        .byte $f9,$e0,$07,$f9,$e0,$07,$ff,$e0
        .byte $07,$ff,$e0,$07,$9f,$e0,$07,$9f
        .byte $e0,$07,$87,$e0,$07,$87,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$01

        // sprite 15 / singlecolor / color: $01
        sprite_data_o:
        .byte $00,$00,$00,$01,$ff,$80,$01,$ff
        .byte $80,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$01,$ff,$80,$01,$ff,$80,$01

        // sprite 16 / singlecolor / color: $01
        sprite_data_p:
        .byte $00,$00,$00,$07,$ff,$80,$07,$ff
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$ff,$80,$01,$ff
        .byte $80,$01,$e0,$00,$01,$e0,$00,$01
        .byte $e0,$00,$01,$e0,$00,$01,$e0,$00
        .byte $01,$e0,$00,$01,$e0,$00,$01,$e0
        .byte $00,$07,$f8,$00,$07,$f8,$00,$01

        // sprite 17 / singlecolor / color: $01
        sprite_data_q:
        .byte $00,$00,$00,$01,$ff,$80,$01,$ff
        .byte $80,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$99,$e0,$07,$99,$e0,$07
        .byte $9f,$e0,$07,$9f,$e0,$01,$ff,$80
        .byte $01,$ff,$80,$00,$07,$80,$00,$07
        .byte $80,$00,$07,$e0,$00,$07,$e0,$01

        // sprite 18 / singlecolor / color: $01
        sprite_data_r:
        .byte $00,$00,$00,$07,$ff,$80,$07,$ff
        .byte $80,$01,$e1,$e0,$01,$e1,$e0,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$ff,$80,$01,$ff
        .byte $80,$01,$e7,$80,$01,$e7,$80,$01
        .byte $e1,$e0,$01,$e1,$e0,$01,$e1,$e0
        .byte $01,$e1,$e0,$01,$e1,$e0,$01,$e1
        .byte $e0,$07,$e1,$e0,$07,$e1,$e0,$01

        // sprite 19 / singlecolor / color: $01
        sprite_data_s:
        .byte $00,$00,$00,$01,$ff,$80,$01,$ff
        .byte $80,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$01,$e0,$00
        .byte $01,$e0,$00,$00,$7e,$00,$00,$7e
        .byte $00,$00,$07,$80,$00,$07,$80,$00
        .byte $01,$e0,$00,$01,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$01,$ff,$80,$01,$ff,$80,$01

        // sprite 20 / singlecolor / color: $01
        sprite_data_t:
        .byte $00,$00,$00,$07,$ff,$f8,$07,$ff
        .byte $f8,$07,$9e,$78,$07,$9e,$78,$06
        .byte $1e,$18,$06,$1e,$18,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$1e,$00,$00,$1e,$00,$00
        .byte $1e,$00,$00,$1e,$00,$00,$1e,$00
        .byte $00,$1e,$00,$00,$1e,$00,$00,$1e
        .byte $00,$00,$7f,$80,$00,$7f,$80,$01

        // sprite 21 / singlecolor / color: $01
        sprite_data_u:
        .byte $00,$00,$00,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$07,$81,$e0,$07,$81,$e0,$07
        .byte $81,$e0,$07,$81,$e0,$07,$81,$e0
        .byte $07,$81,$e0,$07,$81,$e0,$07,$81
        .byte $e0,$01,$ff,$80,$01,$ff,$80,$01

        // sprite 22 / multicolor / color: $01
        sprite_data_v:
        .byte $00,$00,$00,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$05
        .byte $00,$50,$05,$00,$50,$05,$00,$50
        .byte $05,$00,$50,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$05
        .byte $00,$50,$05,$00,$50,$01,$41,$40
        .byte $01,$41,$40,$00,$55,$00,$00,$55
        .byte $00,$00,$14,$00,$00,$14,$00,$81

        // sprite 23 / multicolor / color: $01
        sprite_data_w:
        .byte $00,$00,$00,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$05
        .byte $00,$50,$05,$00,$50,$05,$00,$50
        .byte $05,$00,$50,$05,$00,$50,$05,$00
        .byte $50,$05,$14,$50,$05,$14,$50,$05
        .byte $14,$50,$05,$14,$50,$05,$55,$50
        .byte $05,$55,$50,$01,$41,$40,$01,$41
        .byte $40,$01,$41,$40,$01,$41,$40,$81

        // sprite 24 / multicolor / color: $01
        sprite_data_x:
        .byte $00,$00,$00,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$01
        .byte $41,$40,$01,$41,$40,$00,$55,$00
        .byte $00,$55,$00,$00,$14,$00,$00,$14
        .byte $00,$00,$14,$00,$00,$14,$00,$00
        .byte $55,$00,$00,$55,$00,$01,$41,$40
        .byte $01,$41,$40,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$81

        // sprite 25 / multicolor / color: $01
        sprite_data_y:
        .byte $00,$00,$00,$05,$00,$50,$05,$00
        .byte $50,$05,$00,$50,$05,$00,$50,$05
        .byte $00,$50,$05,$00,$50,$01,$41,$40
        .byte $01,$41,$40,$00,$55,$00,$00,$55
        .byte $00,$00,$14,$00,$00,$14,$00,$00
        .byte $14,$00,$00,$14,$00,$00,$14,$00
        .byte $00,$14,$00,$00,$14,$00,$00,$14
        .byte $00,$00,$55,$00,$00,$55,$00,$81

        // sprite 26 / multicolor / color: $01
        sprite_data_z:
        .byte $00,$00,$00,$05,$55,$50,$05,$55
        .byte $50,$05,$00,$50,$05,$00,$50,$04
        .byte $01,$40,$04,$01,$40,$00,$05,$00
        .byte $00,$05,$00,$00,$14,$00,$00,$14
        .byte $00,$00,$50,$00,$00,$50,$00,$01
        .byte $40,$00,$01,$40,$00,$05,$00,$10
        .byte $05,$00,$10,$05,$00,$50,$05,$00
        .byte $50,$05,$55,$50,$05,$55,$50,$81


        *=$1000 "Textdata"
txtstart:
txtwebsite:
        .text "diskette.ch"
        .byte 0
txtfontattrib:
        .text "vga font by viler int10h.org"
        .byte 0
txtemptyblock:  // Can be printed five times to fill the entire screen.
        .fill 200, ' '
        .byte 0


        *=$3000 "Tables"
sinetable:
        .fill 256, 177 + 30*sin(toRadians(i*360/256))
flatsine:
        .fill 256, 3.5 + 3.5*sin(toRadians(i*720/256))
sprites_start_x: // Spaced out in steps of 73 pixels
        .fill 8, i*73