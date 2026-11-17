;; game.s - Game loop, input, timer, render for Catdoku

.module game_game
.globl str_game_time
.globl str_game_victory
.globl game_update, cursor_row, cursor_col, game_timer_start, game_timer_seconds, game_won
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

str_game_title:: .asciz "CATDOKU"
str_game_time:: .asciz "TIEMPO:"
str_game_hint:: .asciz "H:PISTA"
str_game_victory:: .asciz "NIVEL COMPLETADO!"
str_game_back:: .asciz "ESC:MENU"

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
    ld (game_timer_seconds), bc

    ;; Handle input
    ld a, (fwk_input_pressed)
    ;; UP
    bit 0, a
    jr z, _gu_down
    ld a, (cursor_row)
    or a
    jr z, _gu_down
    dec a
    ld (cursor_row), a
    jr _gu_left

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
    inc b
    ld a, b
    ld (cursor_row), a

_gu_left:
    ld a, (fwk_input_pressed)
    bit 2, a
    jr z, _gu_right
    ld a, (cursor_col)
    or a
    jr z, _gu_right
    dec a
    ld (cursor_col), a

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
    inc b
    ld a, b
    ld (cursor_col), a

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
    ld a, #SFX_MARK
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx

_gu_hint:
    ld a, (fwk_input_pressed)
    bit 6, a            ; HINT pressed
    jr z, _gu_back
    call board_get_hint
    or a
    jr z, _gu_back
    ;; HL = pointer to (row, col) of hint cat
    ld a, (hl)
    ld (cursor_row), a
    inc hl
    ld a, (hl)
    ld (cursor_col), a

_gu_back:
    ld a, (fwk_input_pressed)
    bit 7, a            ; BACK pressed
    jr z, _gu_check_win
    ;; Return to level select
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ;; Stop timer
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ret

_gu_check_win:
    call board_check_win
    or a
    jr z, _gu_render
    ;; Victory!
    ld a, #1
    ld (game_won), a
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
    ;; Clear screen
    xor a
    call fwk_video_clear_visible
    ;; Draw title
    ld hl, #str_game_title
    ld b, #4
    call _game_draw_text
    ;; Draw time
    ld hl, #str_game_time
    ld b, #20
    call _game_draw_text
    ;; Draw seconds
    ld a, (game_timer_seconds)
    ld l, a
    ld h, #0
    ld de, #60
    ;; HL = seconds, draw at position
    ;; Use fwk_text_draw_small_u8
    ld b, #20
    ld c, #80
    call fwk_video_get_ptr
    ld a, (game_timer_seconds)
    call fwk_text_draw_small_u8
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
    ;; Render cursor
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
    ;; Draw cell sprite
    ld ix, #sprite_cell_desc
    call fwk_sprite_draw
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

_game_render_cursor:
    ;; Draw cursor sprite at (cursor_row, cursor_col)
    ld a, (cursor_col)
    sla a
    sla a
    sla a
    add a, #CATDOKU_BOARD_OFFSET_X
    ld (sprite_cursor_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_cursor_desc + FWK_SPRITE_X + 1), a
    ld a, (cursor_row)
    sla a
    sla a
    sla a
    add a, #CATDOKU_BOARD_OFFSET_Y
    ld (sprite_cursor_desc + FWK_SPRITE_Y), a
    xor a
    ld (sprite_cursor_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_cursor_desc
    call fwk_sprite_draw_masked
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