;; game.s - Game loop, input, timer, render for Catdoku

.module game_game
.globl str_game_time
.globl str_game_victory
.globl game_update, cursor_row, cursor_col, game_timer_start, game_timer_seconds, game_won, game_dirty, seconds_dirty, str_timeup, cpct_px2byteM0_asm
.globl cursor_row, cursor_col, game_timer_start, game_timer_seconds, game_won
.include "common.inc"
.include "assets/generated/assets.inc"

;; ---- Data area ----
.area _DATA

cursor_row:: .db 0
cursor_col:: .db 0
move_keys: .db 0                  ; cursor bits for this frame (pressed or repeated)
move_repeat: .db 0                ; frames a cursor key has been held
am_cat_row: .db 0                 ; AUTO MARK: the cat just placed
am_cat_col: .db 0
am_region: .db 0
am_row: .db 0                     ; AUTO MARK: cell being checked
am_col: .db 0
fc_region: .db 0                  ; _game_fill_cell: region of the cell
fc_right: .db 0                   ; 1: right neighbour in the same region
fc_down: .db 0                    ; 1: cell below in the same region
fc_corner: .db 0                  ; 1: right, below and diagonal all the same
fc_lines: .db 0                   ; 6, or 8 when joined downwards
cursor_paint: .db 0        ; byte written into the frame pixels (CURSOR_BYTE or 0)
cursor_x: .db 0            ; first frame byte of the current line
cursor_y: .db 0            ; top line of the frame
cursor_hline_masks: .db 0x55, 0xFF, 0xFF, 0xFF, 0xAA

;; Sprite descriptors (8 bytes each)
sprite_cat_desc:: .dw catdoku_cat_pixels, 0, 0
    .db 4, 8                      ; width (bytes), height (lines): .db, not .dw
sprite_mark_desc:: .dw catdoku_mark_pixels, 0, 0
    .db 4, 8
sprite_cell_desc:: .dw catdoku_cell_pixels, 0, 0
    .db 4, 8
sprite_cursor_desc:: .dw catdoku_cursor_pixels, 0, 0
    .db 4, 8
game_timer_start:: .dw 0
game_timer_now:: .dw 0
game_timer_seconds:: .dw 0
game_won:: .db 0
current_level_id:: .db 0
game_dirty:: .db 1
seconds_dirty:: .db 0
game_seconds_buf:: .ds 6
help_ptr: .dw 0
help_x: .db 0
help_y: .db 0
help_colour: .db 0
help_char: .db 0, 0            ; one character + NUL

str_game_title:: .asciz "CATDOKU"
str_game_time:: .asciz "TIME:"
str_game_hint:: .asciz "RETURN:CAT SPACE:MARK H:HINT ESC:MENU"
str_game_victory:: .asciz "LEVEL COMPLETE!"
str_timeup:: .asciz "TIME UP"

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; game_update
;;   In: none
;;   Out: none
;;   Modifies: cursor_row, cursor_col, game_timer_*, game_won, game_state
;; ----------------------------------------------------------------------------
game_update::
    ;; Check if game just started (timer not running)
    ld a, (game_timer_start)
    or a
    ld a, (game_timer_start + 1)
    or a
    jr nz, _gu_timer_running
    ;; Start timer
    ld hl, (fwk_system_frame_count)
    ld (game_timer_start), hl

_gu_timer_running:
    ;; Update timer
    ld hl, (fwk_system_frame_count)
    ld de, (game_timer_start)
    or a
    sbc hl, de
    ;; HL = frames elapsed
    ;; Divide by 50 for seconds
    ld de, #50
    ;; Simple division (HL / 50)
    ld bc, #0
_gu_div_loop:
    ld a, h
    cp d
    jr c, _gu_div_done
    jr nz, _gu_div_sub
    ld a, l
    cp e
    jr c, _gu_div_done
_gu_div_sub:
    or a
    sbc hl, de
    inc bc
    jr _gu_div_loop
_gu_div_done:
    ;; Mark dirty if seconds changed
    ld a, (game_timer_seconds)
    cp c
    jr nz, _gu_seconds_changed
    ld a, (game_timer_seconds + 1)
    cp b
    jr z, _gu_seconds_same
_gu_seconds_changed:
    ld a, #1
    ld (seconds_dirty), a
_gu_seconds_same:
    ld (game_timer_seconds), bc
    ;; Check 1000-second limit
    ld a, b
    cp #3
    jr c, _gu_time_ok
    jr nz, _gu_time_expired
    ld a, c
    cp #0xE8
    jr c, _gu_time_ok
_gu_time_expired:
    ld a, #STATE_TIMEUP
    ld (game_state), a
    ld a, #1
    ld (game_dirty), a            ; main_timeup draws its screen once
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ret                           ; leave game_dirty for main_timeup
_gu_time_ok: nop

    ;; Handle input
    call _game_move_keys
    ;; UP
    bit 0, a
    jr z, _gu_down
    ld a, (cursor_row)
    or a
    jr z, _gu_down
    call _game_erase_cursor
    ld a, (cursor_row)
    dec a
    ld (cursor_row), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_down:
    ld a, (move_keys)
    bit 1, a
    jr z, _gu_left
    ld a, (cursor_row)
    ld b, a
    ld a, (catdoku_n)
    dec a
    cp b
    jr z, _gu_left
    call _game_erase_cursor
    ld a, (cursor_row)
    inc a
    ld (cursor_row), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_left:
    ld a, (move_keys)
    bit 2, a
    jr z, _gu_right
    ld a, (cursor_col)
    or a
    jr z, _gu_right
    call _game_erase_cursor
    ld a, (cursor_col)
    dec a
    ld (cursor_col), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_right:
    ld a, (move_keys)
    bit 3, a
    jr z, _gu_cat
    ld a, (cursor_col)
    ld b, a
    ld a, (catdoku_n)
    dec a
    cp b
    jr z, _gu_cat
    call _game_erase_cursor
    ld a, (cursor_col)
    inc a
    ld (cursor_col), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_cat:
    ld a, (fwk_input_pressed)
    bit 4, a            ; CAT pressed
    jr z, _gu_mark
    ;; Place cat
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    ld d, #CELL_CAT
    call board_set_cell
    push af                       ; Z = a solution cat
    call _game_redraw_cursor_cell
    pop af
    jr z, _gu_cat_ok
    ;; Not a solution cell: the game is lost
    ld a, #SFX_ERROR
    ld b, #5
    ld c, #2
    call fwk_audio_play_sfx
    xor a
    ld (game_timer_start), a      ; stop the timer
    ld (game_timer_start + 1), a
    ld a, #STATE_LOST
    ld (game_state), a
    ld a, #1
    ld (game_dirty), a            ; main_lost draws its window once
    ret
_gu_cat_ok:
    ld a, #SFX_CAT
    ld b, #15
    ld c, #0
    call fwk_audio_play_sfx
    call _game_auto_mark

_gu_mark:
    ld a, (fwk_input_pressed)
    bit 5, a            ; MARK pressed
    jr z, _gu_hint
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    call board_get_mark           ; SPACE toggles the mark
    ld d, #CELL_MARK
    cp #CELL_MARK
    jr nz, _gu_mark_set
    ld d, #CELL_EMPTY
_gu_mark_set:
    call board_set_cell
    call _game_redraw_cursor_cell
    ld a, #SFX_MARK
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx

_gu_hint:
    ld a, (fwk_input_pressed)
    bit 6, a            ; HINT pressed
    jr z, _gu_back
    ;; erase cursor at old position
    call _game_erase_cursor
    call board_get_hint
    or a
    jr z, _gu_hint_none
    ;; HL = pointer to (row, col) of hint cat
    ld a, (hl)
    ld (cursor_row), a
    inc hl
    ld a, (hl)
    ld (cursor_col), a
_gu_hint_none:
    ;; draw cursor (new position, or old one again when no hint is left)
    call _game_render_cursor

_gu_back:
    ld a, (fwk_input_pressed)
    bit 7, a            ; BACK pressed
    jr z, _gu_check_win
    ;; Return to menu
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ;; Stop timer
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ld (game_timer_seconds), a
    ld (game_timer_seconds + 1), a
    ;; Force menu redraw
    ld a, #1
    ld (menu_dirty), a

_gu_check_win:
    call board_check_win
    or a
    jr z, _gu_render
    ;; Victory!
    ld a, #1
    ld (game_won), a
    ld a, #1
    ld (game_dirty), a
    ;; Save progress with level_id and time
    ld a, (current_level_id)
    ld hl, (game_timer_seconds)
    call save_write
    ;; Play victory sound
    ld a, #SFX_VICTORY
    ld b, #20
    ld c, #0
    call fwk_audio_play_sfx
    ld a, #STATE_VICTORY
    ld (game_state), a
    ret                           ; leave game_dirty for main_victory

_gu_render:
    ;; Full redraw when game_dirty
    ld a, (game_dirty)
    or a
    jr z, _gu_seconds_update
    xor a
    ld (game_dirty), a
    xor a
    ld (seconds_dirty), a
    ;; Clear screen
    xor a
    call fwk_video_clear_visible
    ;; Draw time label (top line, centered)
    ld hl, #str_game_time
    ld b, #8
    ld c, #37                     ; "TIME:" ends at byte 47, where the seconds start
    call _game_draw_text_at
    ;; Draw seconds (big)
    call _game_draw_seconds
    ;; Controls help, one line at the bottom (37 chars, centred: 40 - 37)
    ld hl, #str_game_hint
    ld b, #190
    ld c, #3
    call help_draw_line
    ;; Render board
    call _game_render_board
    ret

_gu_seconds_update:
    ;; Update only the seconds number each second
    ld a, (seconds_dirty)
    or a
    ret z
    xor a
    ld (seconds_dirty), a
    ;; Clear number area (8 scanlines x 12 bytes)
    ld a, #8
    ld (catdoku_temp_row), a
_clear_sec_loop:
    ld a, (catdoku_temp_row)
    cp #16
    jr z, _clear_sec_done
    ld l, a
    ld h, #0
    ld c, #47
    call fwk_video_get_ptr
    ld b, #12
_clear_sec_bytes:
    xor a
    ld (hl), a
    inc hl
    djnz _clear_sec_bytes
    ld a, (catdoku_temp_row)
    inc a
    ld (catdoku_temp_row), a
    jr _clear_sec_loop
_clear_sec_done: nop
    ;; Draw seconds (big)
    call _game_draw_seconds
    ret

_game_fill_cell:
    ;; In: B=row, C=col. Fills the cell (3 bytes x 6 lines) with its region
    ;; colour (region+1 pen). The 2-pixel gaps to the right and below are
    ;; filled too when the neighbour is in the same region, so each region
    ;; reads as one shape with black lines only on its borders. The gaps hold
    ;; no sprite pixels (cat and X sit inside the 6x6 area).
    ;; Preserves BC (cpct_px2byteM0_asm destroys B and DE).
    push bc
    call board_get_cell
    ld (fc_region), a
    pop bc
    xor a
    ld (fc_right), a
    ld (fc_down), a
    ld (fc_corner), a
    ld a, c                       ; right neighbour
    inc a
    ld hl, #catdoku_n
    cp (hl)
    jr nc, _gfc_no_right
    push bc
    inc c
    call board_get_cell
    pop bc
    ld hl, #fc_region
    cp (hl)
    jr nz, _gfc_no_right
    ld a, #1
    ld (fc_right), a
_gfc_no_right:
    ld a, b                       ; neighbour below
    inc a
    ld hl, #catdoku_n
    cp (hl)
    jr nc, _gfc_joins_done
    push bc
    inc b
    call board_get_cell
    pop bc
    ld hl, #fc_region
    cp (hl)
    jr nz, _gfc_joins_done
    ld a, #1
    ld (fc_down), a
    ld a, (fc_right)              ; corner: right, below and diagonal
    or a
    jr z, _gfc_joins_done
    push bc
    inc b
    inc c
    call board_get_cell
    pop bc
    ld hl, #fc_region
    cp (hl)
    jr nz, _gfc_joins_done
    ld a, #1
    ld (fc_corner), a
_gfc_joins_done:
    ld a, (fc_down)
    add a, a
    add a, #6
    ld (fc_lines), a
    push bc
    push bc
    ld a, (fc_region)
    inc a
    cp #CURSOR_PEN
    jr c, _gfc_pen_ok
    inc a                         ; skip the cursor pen
_gfc_pen_ok:
    ld h, a
    ld l, a
    call cpct_px2byteM0_asm
    ld d, a
    pop bc
    ; start scanline = 81 + row*8 (board centered, leave top gap)
    ld a, b
    sla a
    sla a
    sla a
    add a, #81
    ld (catdoku_temp_row), a
    ; start column (bytes) = 30 + col*4
    ld a, c
    sla a
    sla a
    add a, #30
    ld (catdoku_temp_col), a
    ; fill 6 scanlines
    xor a
    ld (catdoku_temp_val), a
_gfc_row:
    ld a, (catdoku_temp_val)
    ld hl, #fc_lines
    cp (hl)
    jr z, _gfc_done
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_val)
    add a, b
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    ld c, a
    push de                       ; fwk_video_get_ptr destroys DE, and D holds the colour byte
    call fwk_video_get_ptr
    pop de
    ld a, (catdoku_temp_val)      ; lines 0..5: 3 bytes + right join
    cp #6                         ; lines 6..7: 3 bytes + corner
    ld a, (fc_right)
    jr c, _gfc_width
    ld a, (fc_corner)
_gfc_width:
    add a, #3
    ld b, a
_gfc_byte:
    ld a, d
    ld (hl), a
    inc hl
    djnz _gfc_byte
    ld a, (catdoku_temp_val)
    inc a
    ld (catdoku_temp_val), a
    jr _gfc_row
_gfc_done:
    pop bc
    ret

_game_redraw_cell:
    ;; In: B=row, C=col. Redraws cell background + overlay
    call _game_fill_cell
    ;; overlay if needed
    push bc
    ;; compute index = row*n+col
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _grc_no_mul
_grc_mul:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _grc_no_carry
    inc h
_grc_no_carry:
    djnz _grc_mul
_grc_no_mul:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _grc_no_carry2
    inc h
_grc_no_carry2:
    ld de, #catdoku_marks
    add hl, de
    ld a, (hl)
    pop bc
    or a
    jr z, _grc_done
    cp #CELL_CAT
    jr z, _grc_cat
    cp #CELL_MARK
    jr z, _grc_mark
    jr _grc_done
_grc_cat:
    ;; set sprite pos
    ld a, c
    sla a
    sla a               ; X in bytes: 4 bytes per cell
    add a, #CATDOKU_BOARD_OFFSET_X
    ld (sprite_cat_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_cat_desc + FWK_SPRITE_X + 1), a
    ld a, b
    sla a
    sla a
    sla a
    add a, #CATDOKU_BOARD_OFFSET_Y
    ld (sprite_cat_desc + FWK_SPRITE_Y), a
    xor a
    ld (sprite_cat_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_cat_desc
    call fwk_sprite_draw_masked
    jr _grc_done
_grc_mark:
    ld a, c
    sla a
    sla a               ; X in bytes: 4 bytes per cell
    add a, #CATDOKU_BOARD_OFFSET_X
    ld (sprite_mark_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_mark_desc + FWK_SPRITE_X + 1), a
    ld a, b
    sla a
    sla a
    sla a
    add a, #CATDOKU_BOARD_OFFSET_Y
    ld (sprite_mark_desc + FWK_SPRITE_Y), a
    xor a
    ld (sprite_mark_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_mark_desc
    call fwk_sprite_draw_masked
_grc_done:
    ret

;; Redraw the cell under the cursor (background + cat/mark), then the cursor.
_game_redraw_cursor_cell:
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    call _game_redraw_cell
    jp _game_render_cursor

_game_render_board:
    ;; Draw each cell as sprite, then overlay cat/mark if present
    ld b, #0
_grb_row_loop:
    ld a, (catdoku_n)
    cp b
    jp z, _grb_done
    ld c, #0
_grb_col_loop:
    ld a, (catdoku_n)
    cp c
    jp z, _grb_next_row
    ;; Save row/col
    push bc
    ;; Calculate screen X = CATDOKU_BOARD_OFFSET_X + col * 8
    ld a, c
    sla a
    sla a               ; X in bytes: 4 bytes per cell
    add a, #CATDOKU_BOARD_OFFSET_X
    ld (sprite_cell_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_cell_desc + FWK_SPRITE_X + 1), a
    ;; Calculate screen Y = CATDOKU_BOARD_OFFSET_Y + row * 8
    ld a, b
    sla a
    sla a
    sla a
    add a, #CATDOKU_BOARD_OFFSET_Y
    ld (sprite_cell_desc + FWK_SPRITE_Y), a
    xor a
    ld (sprite_cell_desc + FWK_SPRITE_Y + 1), a
    ;; Fill cell with region color
    call _game_fill_cell
    ;; Check cell state in marks array
    ;; index = row * n + col
    pop bc
    push bc
    ;; Calculate index
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    ;; row * n
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _grb_no_mul
_grb_mul:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _grb_no_carry
    inc h
_grb_no_carry:
    djnz _grb_mul
_grb_no_mul:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _grb_no_carry2
    inc h
_grb_no_carry2:
    ;; HL = cell index
    ld de, #catdoku_marks
    add hl, de
    ld a, (hl)
    ;; A = cell state (0=empty, 1=cat, 2=mark)
    or a
    jr z, _grb_no_overlay
    cp #CELL_CAT
    jr z, _grb_draw_cat
    cp #CELL_MARK
    jr z, _grb_draw_mark
    jr _grb_no_overlay
_grb_draw_cat:
    ;; Draw cat sprite at same position
    ld a, (sprite_cell_desc + FWK_SPRITE_X)
    ld (sprite_cat_desc + FWK_SPRITE_X), a
    ld a, (sprite_cell_desc + FWK_SPRITE_X + 1)
    ld (sprite_cat_desc + FWK_SPRITE_X + 1), a
    ld a, (sprite_cell_desc + FWK_SPRITE_Y)
    ld (sprite_cat_desc + FWK_SPRITE_Y), a
    ld a, (sprite_cell_desc + FWK_SPRITE_Y + 1)
    ld (sprite_cat_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_cat_desc
    call fwk_sprite_draw_masked
    jr _grb_no_overlay
_grb_draw_mark:
    ;; Draw mark sprite at same position
    ld a, (sprite_cell_desc + FWK_SPRITE_X)
    ld (sprite_mark_desc + FWK_SPRITE_X), a
    ld a, (sprite_cell_desc + FWK_SPRITE_X + 1)
    ld (sprite_mark_desc + FWK_SPRITE_X + 1), a
    ld a, (sprite_cell_desc + FWK_SPRITE_Y)
    ld (sprite_mark_desc + FWK_SPRITE_Y), a
    ld a, (sprite_cell_desc + FWK_SPRITE_Y + 1)
    ld (sprite_mark_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_mark_desc
    call fwk_sprite_draw_masked
_grb_no_overlay:
    pop bc
    inc c
    jp _grb_col_loop
_grb_next_row:
    inc b
    jp _grb_row_loop
_grb_done:
    ;; Draw cursor
    call _game_render_cursor
    ret

_game_clamp_cursor:
    ;; Clamp cursor_row/col to 0..n-1
    ld a, (cursor_row)
    ld b, a
    ld a, (catdoku_n)
    or a
    jr z, _gcc_col
    dec a
    cp b
    jr nc, _gcc_row_ok
    ld a, (catdoku_n)
    dec a
    ld (cursor_row), a
_gcc_row_ok:
_gcc_col:
    ld a, (cursor_col)
    ld b, a
    ld a, (catdoku_n)
    or a
    ret z
    dec a
    cp b
    jr nc, _gcc_done
    ld a, (catdoku_n)
    dec a
    ld (cursor_col), a
_gcc_done:
    ret

;; ----------------------------------------------------------------------------
;; Cursor: yellow frame one pixel outside the 6x6 cell, drawn in the gap between
;; cells. Cell (r,c) covers lines 81+8r..86+8r and bytes 30+4c..32+4c (pixels
;; 60+8c..65+8c). The frame uses lines 80+8r and 87+8r, the right pixel of byte
;; 29+4c and the left pixel of byte 33+4c. Mode 0 packs two pixels per byte, so
;; each byte is masked: 0x55 = right pixel, 0xAA = left pixel, 0xFF = both.
;; Drawing and erasing write only the frame pixels; nothing else is touched.
;; Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
;; ----------------------------------------------------------------------------
;; _game_auto_mark
;;   AUTO MARK option (main menu): after a right cat at the cursor, every empty
;;   cell of its row, its column, its region and its 8 neighbours gets an X,
;;   the cells where no other cat can go. Cats are never removed, so the
;;   marks never need undoing. Does nothing when the option is off.
;;   Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
_game_auto_mark:
    call save_get_auto_mark
    or a
    ret z
    ld a, (cursor_row)
    ld (am_cat_row), a
    ld b, a
    ld a, (cursor_col)
    ld (am_cat_col), a
    ld c, a
    call board_get_cell           ; A = region of the cat
    ld (am_region), a
    xor a
    ld (am_row), a
_gam_row:
    ld a, (catdoku_n)
    ld hl, #am_row
    cp (hl)
    jp z, _game_render_cursor     ; done: the redraws may have hit the frame
    xor a
    ld (am_col), a
_gam_col:
    ld a, (catdoku_n)
    ld hl, #am_col
    cp (hl)
    jp z, _gam_next_row
    ld a, (am_row)
    ld b, a
    ld a, (am_col)
    ld c, a
    call board_get_mark
    or a                          ; only CELL_EMPTY cells change
    jp nz, _gam_next_col
    ld a, (am_row)                ; same row
    ld hl, #am_cat_row
    cp (hl)
    jr z, _gam_mark
    ld a, (am_col)                ; same column
    ld hl, #am_cat_col
    cp (hl)
    jr z, _gam_mark
    ld a, (am_row)                ; neighbour: row - cat_row + 1 in 0..2 ...
    ld hl, #am_cat_row
    sub (hl)
    inc a
    cp #3
    jr nc, _gam_region
    ld a, (am_col)                ; ... and col - cat_col + 1 in 0..2
    ld hl, #am_cat_col
    sub (hl)
    inc a
    cp #3
    jr c, _gam_mark
_gam_region:
    ld a, (am_row)
    ld b, a
    ld a, (am_col)
    ld c, a
    call board_get_cell
    ld hl, #am_region
    cp (hl)
    jp nz, _gam_next_col
_gam_mark:
    ld a, (am_row)
    ld b, a
    ld a, (am_col)
    ld c, a
    ld d, #CELL_MARK
    call board_set_cell
    ld a, (am_row)
    ld b, a
    ld a, (am_col)
    ld c, a
    call _game_redraw_cell
_gam_next_col:
    ld hl, #am_col
    inc (hl)
    jp _gam_col
_gam_next_row:
    ld hl, #am_row
    inc (hl)
    jp _gam_row

;; ----------------------------------------------------------------------------
;; _game_move_keys
;;   Out: A = move_keys = cursor bits (UP/DOWN/LEFT/RIGHT) to act on this
;;   frame: the keys just pressed, plus the held ones once they have been
;;   down MOVE_REPEAT_DELAY frames, then every MOVE_REPEAT_RATE frames.
;;   Modifies: AF, B.
;; ----------------------------------------------------------------------------
_game_move_keys:
    ld a, (fwk_input_held)
    and #INPUT_UP | INPUT_DOWN | INPUT_LEFT | INPUT_RIGHT
    jr nz, _gmk_held
    ld (move_repeat), a           ; nothing held: restart the delay
    ld (move_keys), a
    ret
_gmk_held:
    ld b, a                       ; B = held cursor bits
    ld a, (fwk_input_pressed)
    and #INPUT_UP | INPUT_DOWN | INPUT_LEFT | INPUT_RIGHT
    jr z, _gmk_repeat
    ld (move_keys), a             ; a new press: move now, restart the delay
    xor a
    ld (move_repeat), a
    ld a, (move_keys)
    ret
_gmk_repeat:
    ld a, (move_repeat)
    inc a
    cp #MOVE_REPEAT_LIMIT
    jr c, _gmk_count
    ld a, #MOVE_REPEAT_DELAY      ; keep cycling inside the repeat period
_gmk_count:
    ld (move_repeat), a
    cp #MOVE_REPEAT_DELAY
    ld a, #0
    jr nz, _gmk_out
    ld a, b                       ; delay over / one more period: repeat
_gmk_out:
    ld (move_keys), a
    ret

_game_render_cursor:
    ld a, #CURSOR_BYTE
    jr _game_paint_cursor
;; The frame sits in the gaps between cells, which may hold region joins:
;; paint it black, then redraw the four cells whose joins it covers.
_game_erase_cursor:
    xor a
    call _game_paint_cursor
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    call _gec_cell                ; (row, col): right and bottom gaps
    dec c
    call _gec_cell                ; (row, col-1): left gap
    dec b
    call _gec_cell                ; (row-1, col-1): top-left corner
    inc c
    jp _gec_cell                  ; (row-1, col): top gap

;; B=row, C=col (0xFF when off the board: skipped). Preserves BC.
_gec_cell:
    ld a, b
    cp #CATDOKU_MAX_N
    ret nc
    ld a, c
    cp #CATDOKU_MAX_N
    ret nc
    push bc
    call _game_redraw_cell
    pop bc
    ret

_game_paint_cursor:
    ld (cursor_paint), a
    ld a, (cursor_row)
    add a, a
    add a, a
    add a, a
    add a, #CATDOKU_BOARD_OFFSET_Y
    ld (cursor_y), a
    ld a, (cursor_col)
    add a, a
    add a, a
    add a, #CATDOKU_BOARD_OFFSET_X - 1
    ld (cursor_x), a
    ;; top and bottom lines
    ld a, (cursor_y)
    call _gpc_hline
    ld a, (cursor_y)
    add a, #7
    call _gpc_hline
    ;; sides, lines 1..6
    ld b, #6
    ld a, (cursor_y)
    inc a
_gpc_side_loop:
    push af
    call _gpc_side
    pop af
    inc a
    djnz _gpc_side_loop
    ret

;; A = line: bytes x..x+4 with masks 0x55, 0xFF, 0xFF, 0xFF, 0xAA
_gpc_hline:
    call _gpc_line_ptr
    ld de, #cursor_hline_masks
    ld b, #5
_gpc_hline_byte:
    ld a, (de)
    call _gpc_apply
    inc hl
    inc de
    djnz _gpc_hline_byte
    ret

;; A = line: right pixel of byte x, left pixel of byte x+4
_gpc_side:
    call _gpc_line_ptr
    ld a, #0x55
    call _gpc_apply
    inc hl
    inc hl
    inc hl
    inc hl
    ld a, #0xAA
    jr _gpc_apply

;; A = line -> HL = screen address of (cursor_x, line). Preserves BC.
_gpc_line_ptr:
    ld l, a
    ld h, #0
    push bc
    ld a, (cursor_x)
    ld c, a
    call fwk_video_get_ptr
    pop bc
    ret

;; A = pixel mask: (HL) = (HL) & ~mask | cursor_paint & mask. Preserves BC, DE, HL.
_gpc_apply:
    push bc
    ld c, a
    cpl
    and (hl)
    ld b, a
    ld a, (cursor_paint)
    and c
    or b
    ld (hl), a
    pop bc
    ret

_game_draw_seconds:
    ld hl, (game_timer_seconds)
    ld b, #8
    ld c, #47

;; ----------------------------------------------------------------------------
;; game_draw_number_at
;;   In: HL = 0..999, B = line, C = column (bytes). Draws it in the big font.
;;   Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
game_draw_number_at::
    push bc
    ex de, hl
    ld ix, #game_seconds_buf
    ;; hundreds
    ld b, #0
_gds_hundreds:
    ld a, d
    or e
    jr z, _gds_hundreds_done
    ld a, e
    sub #100
    ld c, a
    ld a, d
    sbc a, #0
    jr c, _gds_hundreds_done
    ld e, c
    ld d, a
    inc b
    jr _gds_hundreds
_gds_hundreds_done:
    ;; tens
    ld c, #0
_gds_tens:
    ld a, d
    or e
    jr z, _gds_tens_done
    ld a, e
    sub #10
    ld l, a
    ld a, d
    sbc a, #0
    jr c, _gds_tens_done
    ld e, l
    ld d, a
    inc c
    jr _gds_tens
_gds_tens_done:
    ;; store hundreds if >0
    ld a, b
    or a
    jr z, _gds_skip_hundreds
    add a, #'0'
    ld (ix), a
    inc ix
_gds_skip_hundreds:
    ;; store tens if hundreds>0 or tens>0
    ld a, b
    or a
    jr nz, _gds_store_tens
    ld a, c
    or a
    jr z, _gds_skip_tens
_gds_store_tens:
    ld a, c
    add a, #'0'
    ld (ix), a
    inc ix
_gds_skip_tens:
    ;; ones always
    ld a, e
    add a, #'0'
    ld (ix), a
    inc ix
    ld (ix), #0
    ;; draw
    pop bc
    ld hl, #game_seconds_buf
    jp _game_draw_text_at

_game_draw_text:
    ;; In: HL = string ptr, B = scanline Y
    push hl
    ld l, b
    ld h, #0
    ld c, #4
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

;; ----------------------------------------------------------------------------
;; help_draw_line
;;   In: HL = "LABEL:VALUE LABEL:VALUE ..." (NUL-terminated), B = line,
;;       C = column (bytes). Each label up to and including ':' is drawn in
;;       TEXT_LABEL, each value in white; a space starts a new label.
;;   Out: text colour back to white. Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
help_draw_line::
    ld (help_ptr), hl
    ld a, b
    ld (help_y), a
    ld a, c
    ld (help_x), a
    ld a, #TEXT_LABEL
    ld (help_colour), a
_hdl_loop:
    ld hl, (help_ptr)
    ld a, (hl)
    or a
    jr z, _hdl_done
    ld (help_char), a
    inc hl
    ld (help_ptr), hl
    cp #' '
    jr nz, _hdl_draw
    ld a, #TEXT_LABEL             ; next word starts with a label
    ld (help_colour), a
    jr _hdl_next
_hdl_draw:
    ld a, (help_colour)
    call fwk_text_set_color
    ld a, (help_y)
    ld l, a
    ld h, #0
    ld a, (help_x)
    ld c, a
    call fwk_video_get_ptr
    ld iy, #help_char
    call fwk_text_draw
    ld a, (help_char)
    cp #':'
    jr nz, _hdl_next
    ld a, #TEXT_WHITE             ; after the colon comes the value
    ld (help_colour), a
_hdl_next:
    ld a, (help_x)
    add a, #2                     ; one character = 2 bytes
    ld (help_x), a
    jr _hdl_loop
_hdl_done:
    xor a
    jp fwk_text_set_color

_game_draw_text_at:
    ;; In: HL = string ptr, B = scanline Y, C = column
    push hl
    ld l, b
    ld h, #0
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw