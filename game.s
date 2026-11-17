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

;; Sprite descriptors (8 bytes each)
sprite_cat_desc:: .dw catdoku_cat_pixels, 0, 0, 4, 8
sprite_mark_desc:: .dw catdoku_mark_pixels, 0, 0, 4, 8
sprite_cell_desc:: .dw catdoku_cell_pixels, 0, 0, 4, 8
sprite_cursor_desc:: .dw catdoku_cursor_pixels, 0, 0, 4, 8
game_timer_start:: .dw 0
game_timer_now:: .dw 0
game_timer_seconds:: .dw 0
game_won:: .db 0
current_level_id:: .db 0
game_dirty:: .db 1
seconds_dirty:: .db 0
game_seconds_buf:: .ds 6

str_game_title:: .asciz "CATDOKU"
str_game_time:: .asciz "TIEMPO:"
str_game_hint:: .asciz "H:PISTA"
str_game_victory:: .asciz "NIVEL COMPLETADO!"
str_game_back:: .asciz "ESC:MENU"
str_timeup:: .asciz "TIEMPO AGOTADO"

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
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
_gu_time_ok: nop

    ;; Handle input
    ld a, (fwk_input_pressed)
    ;; UP
    bit 0, a
    jr z, _gu_down
    ld a, (cursor_row)
    or a
    jr z, _gu_down
    call _game_render_cursor
    ld a, (cursor_row)
    dec a
    ld (cursor_row), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_down:
    ld a, (fwk_input_pressed)
    bit 1, a
    jr z, _gu_left
    ld a, (cursor_row)
    ld b, a
    ld a, (catdoku_n)
    dec a
    cp b
    jr z, _gu_left
    call _game_render_cursor
    ld a, (cursor_row)
    inc a
    ld (cursor_row), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_left:
    ld a, (fwk_input_pressed)
    bit 2, a
    jr z, _gu_right
    ld a, (cursor_col)
    or a
    jr z, _gu_right
    call _game_render_cursor
    ld a, (cursor_col)
    dec a
    ld (cursor_col), a
    call _game_clamp_cursor
    call _game_render_cursor

_gu_right:
    ld a, (fwk_input_pressed)
    bit 3, a
    jr z, _gu_cat
    ld a, (cursor_col)
    ld b, a
    ld a, (catdoku_n)
    dec a
    cp b
    jr z, _gu_cat
    call _game_render_cursor
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
    jr z, _gu_cat_ok
    ;; Invalid
    ld a, #SFX_ERROR
    ld b, #5
    ld c, #2
    call fwk_audio_play_sfx
    jr _gu_mark
_gu_cat_ok:
    ld a, #SFX_CAT
    ld b, #15
    ld c, #0
    call fwk_audio_play_sfx
    ld a, #1
    ld (game_dirty), a

_gu_mark:
    ld a, (fwk_input_pressed)
    bit 5, a            ; MARK pressed
    jr z, _gu_hint
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    ld d, #CELL_MARK
    call board_set_cell
    ld a, #1
    ld (game_dirty), a
    ld a, #SFX_MARK
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx

_gu_hint:
    ld a, (fwk_input_pressed)
    bit 6, a            ; HINT pressed
    jr z, _gu_back
    ;; erase cursor at old position
    call _game_render_cursor
    call board_get_hint
    or a
    jr z, _gu_back
    ;; HL = pointer to (row, col) of hint cat
    ld a, (hl)
    ld (cursor_row), a
    inc hl
    ld a, (hl)
    ld (cursor_col), a
    ;; draw cursor at new position
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
    ld c, #33
    call _game_draw_text_at
    ;; Draw seconds (big)
    call _game_draw_seconds
    ;; Draw hint help
    ld hl, #str_game_hint
    ld b, #180
    call _game_draw_text
    ;; Draw back help
    ld hl, #str_game_back
    ld b, #190
    call _game_draw_text
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
    ;; In: B=row, C=col. Fills 8x8 cell with region color (region+1 pen)
    push bc
    call board_get_cell
    pop bc
    add a, #1
    ld h, a
    ld l, a
    call cpct_px2byteM0_asm
    ld d, a
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
    cp #6
    jr z, _gfc_done
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_val)
    add a, b
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    ld c, a
    call fwk_video_get_ptr
    ld b, #3
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
    sla a
    sla a
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
    sla a
    sla a
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
    sla a
    sla a
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

_game_render_cursor:
    ;; Draw cursor as XOR outline on full 8x8 cell
    ;; base scanline = 80 + cursor_row*8
    ld a, (cursor_row)
    sla a
    sla a
    sla a
    add a, #80
    ld (catdoku_temp_row), a
    ;; base column (bytes) = 30 + cursor_col*4
    ld a, (cursor_col)
    sla a
    sla a
    add a, #30
    ld (catdoku_temp_col), a
    ;; top row (4 bytes) XOR 0x55
    ld a, (catdoku_temp_row)
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    ld c, a
    call fwk_video_get_ptr
    ld b, #4
_gcur_top:
    ld a, (hl)
    xor #0xFF
    ld (hl), a
    inc hl
    djnz _gcur_top
    ;; bottom row (base+7) XOR 0x55
    ld a, (catdoku_temp_row)
    add a, #7
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    ld c, a
    call fwk_video_get_ptr
    ld b, #4
_gcur_bottom:
    ld a, (hl)
    xor #0xFF
    ld (hl), a
    inc hl
    djnz _gcur_bottom
    ;; middle rows 1..6: left and right columns XOR 0x55
    ld a, #1
    ld (catdoku_temp_val), a
_gcur_mid:
    ld a, (catdoku_temp_val)
    cp #7
    jr z, _gcur_done
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_val)
    add a, b
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    ld c, a
    call fwk_video_get_ptr
    ld a, (hl)
    xor #0xFF
    ld (hl), a
    ;; right column = base col + 3
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_val)
    add a, b
    ld l, a
    ld h, #0
    ld a, (catdoku_temp_col)
    add a, #3
    ld c, a
    call fwk_video_get_ptr
    ld a, (hl)
    xor #0xFF
    ld (hl), a
    ld a, (catdoku_temp_val)
    inc a
    ld (catdoku_temp_val), a
    jr _gcur_mid
_gcur_done:
    ret

_game_draw_seconds:
    ;; Convert game_timer_seconds to decimal string and draw with big font
    ld de, (game_timer_seconds)
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
    ld hl, #game_seconds_buf
    ld b, #8
    ld c, #47
    call _game_draw_text_at
    ret

_game_draw_text:
    ;; In: HL = string ptr, B = scanline Y
    push hl
    ld l, b
    ld h, #0
    ld c, #4
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_game_draw_text_at:
    ;; In: HL = string ptr, B = scanline Y, C = column
    push hl
    ld l, b
    ld h, #0
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw