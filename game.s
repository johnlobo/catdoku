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
am_cat_row: .db 0                 ; AUTO MARK: the cat just placed
am_cat_col: .db 0
am_region: .db 0
am_row: .db 0                     ; AUTO MARK: cell being checked
am_col: .db 0
fc_region: .db 0                  ; _game_fill_cell: region of the cell
fc_right: .db 0                   ; 1: right neighbour in the same region
fc_down: .db 0                    ; 1: cell below in the same region
fc_corner: .db 0                  ; 1: right, below and diagonal all the same
fc_full: .db 0                    ; region pen in both pixels
fc_override: .db 0xFF             ; pen instead of the region one (0xFF: none)
hint_active:: .db 0               ; a hint is shown: the next H acts on it
hint_on:: .db 0                   ; its cells are white now
hint_timer: .db 0
hint_pos: .db 0xFF                ; next cell of a phase being drawn (0xFF: none)
hint_toggles: .db 0
hint_text: .ds 40
fc_e7: .db 0                      ; byte 7 of lines 0..14: region + right gap
fc_e7t: .db 0                     ; byte 7 of lines 7 and 8: region + gap tick
fc_b3: .db 0                      ; line 15, byte 3: region + tick
fc_b4: .db 0                      ; line 15, byte 4: tick + region
fc_b7: .db 0                      ; line 15, byte 7: region + corner
fc_ptr_y: .db 0
gdf_x: .db 0                      ; _game_draw_frame
gdf_y: .db 0
gdf_size: .db 0
fc_x: .db 0
cursor_px: .db 0                  ; cursor corners: left / top pixel
cursor_py: .db 0

;; Sprite descriptors (8 bytes each)
sprite_cat_desc:: .dw catdoku_cat_pixels, 0, 0
    .db 8, 16                     ; width (bytes), height (lines): .db, not .dw
sprite_mark_desc:: .dw catdoku_mark_pixels, 0, 0
    .db 8, 16
cell_pos: .dw 0, 0                ; screen X (bytes), Y (lines) of the cell being drawn
game_timer_start:: .dw 0
game_timer_now:: .dw 0
game_timer_seconds:: .dw 0
game_timer_base:: .dw 0            ; seconds already played (a resumed game)
game_won:: .db 0
current_level_id:: .db 0
game_dirty:: .db 1
seconds_dirty:: .db 0
game_seconds_buf:: .ds 6
game_time_str: .ascii "TIME:"     ; "TIME:" + up to 3 digits + NUL, drawn centred
game_time_digits: .ds 4

str_game_title:: .asciz "CATDOKU"
str_game_time:: .asciz "TIME:"
str_game_hint:: .asciz "RETURN:CAT SPACE:MARK H:HINT ESC:BACK"
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
    ld hl, (game_timer_base)
    add hl, bc
    ld b, h
    ld c, l
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
    ld a, (current_level_id)      ; a resumed game ends here: forget it
    call save_forget_resume
    ld a, #STATE_TIMEUP
    ld (game_state), a
    ld a, #1
    ld (game_dirty), a            ; main_timeup draws its screen once
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ret                           ; leave game_dirty for main_timeup
_gu_time_ok:
    call _game_hint_blink
    ;; Handle input: any other key ends a hint first
    call _game_move_keys
    ld b, a
    ld a, (fwk_input_pressed)
    and #INPUT_CAT | INPUT_MARK | INPUT_BACK
    or b
    call nz, _game_hint_end
    ld a, (move_keys)
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
    ld a, (current_level_id)
    call save_forget_resume
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
    ld a, (hint_active)
    or a
    jr z, _gu_hint_new
    ;; second H: act on the hint shown
    call _game_hint_end
    ld a, (hint_kind)
    cp #HINT_TRIAL
    jr z, _gu_hint_x
    ld a, (hint_target)
    cp #0xFF
    jr z, _gu_back
    call _game_erase_cursor       ; the selector goes to the cell
    ld a, (hint_target)
    call _game_cell_rc
    ld a, b
    ld (cursor_row), a
    ld a, c
    ld (cursor_col), a
    call _game_render_cursor
    jr _gu_back
_gu_hint_x:
    ld a, (hint_target)           ; TRIAL: the cell gets its X
    call _game_cell_rc
    ld d, #CELL_MARK
    push bc
    call board_set_cell
    pop bc
    call _game_redraw_cell
    call _game_render_cursor
    jr _gu_back
_gu_hint_new:
    call hint_find
    ld a, (hint_kind)
    or a
    jr z, _gu_back
    ld a, #1
    ld (hint_active), a
    ld (hint_timer), a            ; first phase on the next frame
    xor a
    ld (hint_on), a
    ld a, #HINT_BLINKS
    ld (hint_toggles), a
    ld a, #0xFF
    ld (hint_pos), a
    call _game_hint_text

_gu_back:
    ld a, (fwk_input_pressed)
    bit 7, a            ; BACK pressed
    jr z, _gu_check_win
    ;; Keep the game for CONTINUE (writes CATDOKU.SAV), then level select
    call save_store_resume
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
    ;; Save progress with level_id and time; a resumed game is finished
    ld a, (current_level_id)
    call save_drop_resume
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
    jp z, _gu_seconds_update
    xor a
    ld (game_dirty), a
    xor a
    ld (seconds_dirty), a
    ;; Background (frame, TIME box, help bar), then the dynamic parts
    ld a, #UI_BG_GAME
    call ui_show_background
    call _game_draw_time
    ld iy, #str_game_hint
    call ui_help
    call _game_draw_frame
    jp _game_render_board

;; Orange 1-pixel frame two pixels around the board (16n + 4 pixels a side).
;; Modifies: AF, BC, DE, HL.
_game_draw_frame:
    ld a, (catdoku_n)
    add a, a
    add a, a
    add a, a
    add a, a
    add a, #4
    ld (gdf_size), a
    ld a, (board_x)
    add a, a
    sub #2
    ld (gdf_x), a
    ld a, (board_y)
    sub #2
    ld (gdf_y), a
    ;; top
    call _gdf_rect_h
    ld a, (gdf_size)
    dec a
    ld e, a
    ld a, (gdf_y)
    add a, e
    ld c, a                       ; bottom
    ld a, (gdf_x)
    ld b, a
    ld a, (gdf_size)
    ld d, a
    ld e, #1
    ld a, #PEN_ORANGE
    call ui_rect
    ld a, (gdf_x)                 ; left
    ld b, a
    ld a, (gdf_y)
    ld c, a
    ld d, #1
    ld a, (gdf_size)
    ld e, a
    ld a, #PEN_ORANGE
    call ui_rect
    ld a, (gdf_size)              ; right
    dec a
    ld b, a
    ld a, (gdf_x)
    add a, b
    ld b, a
    ld a, (gdf_y)
    ld c, a
    ld d, #1
    ld a, (gdf_size)
    ld e, a
    ld a, #PEN_ORANGE
    jp ui_rect
_gdf_rect_h:
    ld a, (gdf_x)
    ld b, a
    ld a, (gdf_y)
    ld c, a
    ld a, (gdf_size)
    ld d, a
    ld e, #1
    ld a, #PEN_ORANGE
    jp ui_rect

_gu_seconds_update:
    ;; Redraw the time each second
    ld a, (seconds_dirty)
    or a
    ret z
    xor a
    ld (seconds_dirty), a
    jp _game_draw_time

_game_fill_cell:
    ;; In: B=row, C=col. Draws the cell: 15x15 pixels of its region colour
    ;; (pen region+3), then its gaps: the pixel column on the right and the
    ;; line below. A gap towards a cell of the same region takes the region
    ;; colour with a 2-pixel tick in the middle; towards another region it is
    ;; black. The bottom-right corner pixel joins when the right, lower and
    ;; diagonal cells are all in the region. Preserves BC.
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
    push bc
    ld a, (fc_region)
    ld e, a
    ld d, #0
    ld hl, #fc_tick_pens
    add hl, de
    ld a, (hl)
    call ui_pen_byte
    ld (fc_b4), a                 ; tick pen in both pixels, for now
    ld a, (fc_region)
    add a, #REGION_FIRST_PEN
    ld c, a
    ld a, (fc_override)
    cp #0xFF
    jr nz, _gfc_pen
    ld a, c
_gfc_pen:
    call ui_pen_byte
    ld (fc_full), a
    ;; byte 7, lines 0..14: region pixel, then the gap (region or black)
    and #0xAA
    ld c, a                       ; C = region in the left pixel only
    ld a, (fc_right)
    or a
    ld a, c
    jr z, _gfc_e7
    ld a, (fc_full)
_gfc_e7:
    ld (fc_e7), a
    ;; lines 7 and 8: the gap holds the tick when joined
    ld a, (fc_right)
    or a
    ld a, c
    jr z, _gfc_e7t
    ld a, (fc_b4)
    and #0x55
    or c
_gfc_e7t:
    ld (fc_e7t), a
    ;; line 15 (gap below): bytes 3 and 4 hold the 2-pixel tick
    ld a, (fc_b4)
    and #0x55
    or c
    ld (fc_b3), a
    ld a, (fc_full)
    and #0x55
    ld d, a
    ld a, (fc_b4)
    and #0xAA
    or d
    ld (fc_b4), a
    ld a, (fc_corner)
    or a
    ld a, c
    jr z, _gfc_b7
    ld a, (fc_full)
_gfc_b7:
    ld (fc_b7), a
    pop bc
    push bc
    ;; first byte = board_x + col*8, first line = board_y + row*16
    ld a, c
    add a, a
    add a, a
    add a, a
    ld hl, #board_x
    add a, (hl)
    ld (fc_x), a
    ld a, b
    add a, a
    add a, a
    add a, a
    add a, a
    ld hl, #board_y
    add a, (hl)
    ld (fc_ptr_y), a
    ld a, (fc_ptr_y)
    ld l, a
    ld h, #0
    ld a, (fc_x)
    ld c, a
    call fwk_video_get_ptr        ; HL = first byte of line 0
    ld b, #0                      ; B = line 0..15
_gfc_line:
    ld a, b
    cp #15
    jr z, _gfc_last
    push hl
    ld a, (fc_full)
    ld c, #7
_gfc_byte:
    ld (hl), a
    inc hl
    dec c
    jr nz, _gfc_byte
    ld a, b
    cp #7
    jr z, _gfc_tick
    cp #8
    jr z, _gfc_tick
    ld a, (fc_e7)
    jr _gfc_put7
_gfc_tick:
    ld a, (fc_e7t)
_gfc_put7:
    ld (hl), a
    pop hl
    ld de, #0x0800                ; next line
    add hl, de
    jr nc, _gfc_same_row
    ld de, #0xC050
    add hl, de
_gfc_same_row:
    inc b
    jr _gfc_line
_gfc_last:
    ;; line 15: the gap below, region + tick when joined, black otherwise
    ld a, (fc_down)
    or a
    jr nz, _gfc_last_joined
    xor a
    ld b, #8
_gfc_last_black:
    ld (hl), a
    inc hl
    djnz _gfc_last_black
    pop bc
    ret
_gfc_last_joined:
    ld a, (fc_full)
    ld (hl), a
    inc hl
    ld (hl), a
    inc hl
    ld (hl), a
    inc hl
    ld a, (fc_b3)
    ld (hl), a
    inc hl
    ld a, (fc_b4)
    ld (hl), a
    inc hl
    ld a, (fc_full)
    ld (hl), a
    inc hl
    ld (hl), a
    inc hl
    ld a, (fc_b7)
    ld (hl), a
    pop bc
    ret

;; Tick colour of each region (pens 3..11): white on the dark ones, as the design.
fc_tick_pens:
    .db PEN_WHITE, PEN_BLACK, PEN_BLACK, PEN_WHITE, PEN_BLACK
    .db PEN_BLACK, PEN_BLACK, PEN_BLACK, PEN_BLACK

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
    sla a               ; X in bytes: 8 bytes per cell
    ld hl, #board_x
    add a, (hl)
    ld (sprite_cat_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_cat_desc + FWK_SPRITE_X + 1), a
    ld a, b
    sla a
    sla a
    sla a
    sla a               ; Y: 16 lines per cell
    ld hl, #board_y
    add a, (hl)
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
    sla a               ; X in bytes: 8 bytes per cell
    ld hl, #board_x
    add a, (hl)
    ld (sprite_mark_desc + FWK_SPRITE_X), a
    xor a
    ld (sprite_mark_desc + FWK_SPRITE_X + 1), a
    ld a, b
    sla a
    sla a
    sla a
    sla a               ; Y: 16 lines per cell
    ld hl, #board_y
    add a, (hl)
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
    ;; Calculate screen X = board_x + col * 8
    ld a, c
    sla a
    sla a
    sla a               ; X in bytes: 8 bytes per cell
    ld hl, #board_x
    add a, (hl)
    ld (cell_pos), a
    xor a
    ld (cell_pos + 1), a
    ;; Calculate screen Y = board_y + row * 8
    ld a, b
    sla a
    sla a
    sla a
    sla a               ; Y: 16 lines per cell
    ld hl, #board_y
    add a, (hl)
    ld (cell_pos + 2), a
    xor a
    ld (cell_pos + 2 + 1), a
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
    ld a, (cell_pos)
    ld (sprite_cat_desc + FWK_SPRITE_X), a
    ld a, (cell_pos + 1)
    ld (sprite_cat_desc + FWK_SPRITE_X + 1), a
    ld a, (cell_pos + 2)
    ld (sprite_cat_desc + FWK_SPRITE_Y), a
    ld a, (cell_pos + 2 + 1)
    ld (sprite_cat_desc + FWK_SPRITE_Y + 1), a
    ld ix, #sprite_cat_desc
    call fwk_sprite_draw_masked
    jr _grb_no_overlay
_grb_draw_mark:
    ;; Draw mark sprite at same position
    ld a, (cell_pos)
    ld (sprite_mark_desc + FWK_SPRITE_X), a
    ld a, (cell_pos + 1)
    ld (sprite_mark_desc + FWK_SPRITE_X + 1), a
    ld a, (cell_pos + 2)
    ld (sprite_mark_desc + FWK_SPRITE_Y), a
    ld a, (cell_pos + 2 + 1)
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
;; Cursor: four white corners inside the cell, as the design. With X, Y the
;; first pixel of cell (r,c), the corners are at X+1 / X+13 and Y+1 / Y+13,
;; each 4 pixels long. Erasing redraws the cell.
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
;;   frame, from fwk_input_repeat: the keys just pressed, then the held ones
;;   after 15 frames and every 4 after that (framework defaults).
;;   Modifies: AF.
;; ----------------------------------------------------------------------------
_game_move_keys:
    ld a, (fwk_input_repeat)
    and #INPUT_UP | INPUT_DOWN | INPUT_LEFT | INPUT_RIGHT
    ld (move_keys), a
    ret

;; Modifies: AF, BC, DE, HL.
_game_render_cursor:
    ld a, (cursor_col)
    add a, a
    add a, a
    add a, a
    ld hl, #board_x
    add a, (hl)
    add a, a                      ; pixels
    add a, #1
    ld (cursor_px), a
    ld a, (cursor_row)
    add a, a
    add a, a
    add a, a
    add a, a
    ld hl, #board_y
    add a, (hl)
    add a, #1
    ld (cursor_py), a
    ld hl, #cursor_arms
_grc_arm:
    ld a, (hl)
    cp #0xFF
    ret z
    ld a, (cursor_px)
    add a, (hl)
    ld b, a
    inc hl
    ld a, (cursor_py)
    add a, (hl)
    ld c, a
    inc hl
    ld d, (hl)
    inc hl
    ld e, (hl)
    inc hl
    push hl
    ld a, #CURSOR_PEN
    call ui_rect
    pop hl
    jr _grc_arm

;; dx, dy, width, height of the 8 arms, from (X+1, Y+1)
cursor_arms:
    .db 0, 0, 4, 1,   0, 0, 1, 4      ; top left
    .db 9, 0, 4, 1,   12, 0, 1, 4     ; top right
    .db 0, 12, 4, 1,  0, 9, 1, 4      ; bottom left
    .db 9, 12, 4, 1,  12, 9, 1, 4     ; bottom right
    .db 0xFF

;; The corners sit inside the cell: redrawing it erases them.
_game_erase_cursor:
    ld a, (cursor_row)
    ld b, a
    ld a, (cursor_col)
    ld c, a
    jp _game_redraw_cell

;; ----------------------------------------------------------------------------
;; _game_draw_time
;;   "TIME:<seconds>" centred in the TIME box of the background: the label in
;;   yellow, the seconds in white. The inside of the box is cleared first.
;;   Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
_game_draw_time:
    ld hl, (game_timer_seconds)
    call _game_format_number
    ld hl, #game_seconds_buf
    ld de, #game_time_digits
    ld bc, #4
    ldir
    ld b, #TIME_BOX_X
    ld c, #TIME_BOX_Y
    ld d, #TIME_BOX_W
    ld e, #TIME_BOX_H
    ld a, #PEN_DARK_RED
    call ui_rect
    ;; x = box x + (box width - text width) / 2
    ld hl, #game_time_str
    ld e, #0
_gdt_len:
    ld a, (hl)
    or a
    jr z, _gdt_len_done
    inc hl
    inc e
    jr _gdt_len
_gdt_len_done:
    ld a, e
    add a, a
    add a, a
    dec a
    ld e, a
    ld a, #TIME_BOX_W
    sub e
    srl a
    add a, #TIME_BOX_X
    ld b, a
    ld c, #TIME_TEXT_Y
    ld iy, #str_game_time
    ld a, #PEN_YELLOW
    call ui_text                  ; B = x after "TIME:"
    ld c, #TIME_TEXT_Y
    ld iy, #game_time_digits
    ld a, #PEN_WHITE
    jp ui_text

;; ----------------------------------------------------------------------------
;; game_draw_number_at
;;   In: HL = 0..999, B = x, C = y (pixels), A = pen. Draws it in the UI font.
;;   Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
game_draw_number_at::
    push af
    push bc
    call _game_format_number
    pop bc
    pop af
    ld iy, #game_seconds_buf
    jp ui_text

;; In: HL = 0..999. Out: game_seconds_buf = its decimal digits, NUL ended.
;; Modifies: AF, BC, DE, HL, IX.
_game_format_number:
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
    ret

;; ----------------------------------------------------------------------------
;; Hint display
;;   _game_hint_blink: every HINT_BLINK_FRAMES, the hint cells switch between
;;   white and their colour, HINT_BLINKS times (ending in their colour).
;;   _game_hint_end: ends the hint shown (cells back, help line back).
;;   _game_hint_text: the hint in words on the help bar.
;;   _game_cell_rc: A = cell -> B = row, C = column.
;; ----------------------------------------------------------------------------
_game_hint_blink:
    ld a, (hint_active)
    or a
    ret z
    ld a, (hint_pos)              ; a phase being drawn: the next cells
    cp #0xFF
    jr nz, _ghb_draw
    ld a, (hint_toggles)
    or a
    ret z
    ld hl, #hint_timer
    dec (hl)
    ret nz
    ld (hl), #HINT_BLINK_FRAMES
    dec a
    ld (hint_toggles), a
    ld a, (hint_on)
    xor #1
    ld (hint_on), a
    xor a
    ld (hint_pos), a
_ghb_draw:
    ld a, #HINT_CELLS_PER_FRAME
    jr _game_hint_cells

_game_hint_end:
    ld a, (hint_active)
    or a
    ret z
    xor a
    ld (hint_active), a
    ld (hint_toggles), a
    ld a, (hint_on)               ; cells white, or a phase half drawn
    ld b, a
    ld a, (hint_pos)
    inc a                         ; 0xFF -> 0
    or b
    jr z, _ghe_help
    xor a
    ld (hint_on), a
    ld (hint_pos), a
    ld a, #81                     ; all of them now
    call _game_hint_cells
_ghe_help:
    call _game_help_clear
    ld iy, #str_game_hint
    jp ui_help

;; Redraws up to A hint cells from hint_pos (white while hint_on); when the
;; last one is drawn, hint_pos = 0xFF and the cursor is drawn again.
_game_hint_cells:
    ld (ghc_left), a
    ld a, (hint_on)
    or a
    ld a, #0xFF
    jr z, _ghc_pen
    ld a, #PEN_WHITE
_ghc_pen:
    ld (fc_override), a
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    xor a
_ghc_nn:
    add a, b
    dec c
    jr nz, _ghc_nn
    ld (ghc_nn), a
    ld a, (hint_pos)
_ghc_cell:
    ld (ghc_i), a
    ld hl, #ghc_nn
    cp (hl)
    jr z, _ghc_done
    ld hl, #hint_blink
    ld e, a
    ld d, #0
    add hl, de
    ld a, (hl)
    or a
    jr z, _ghc_next
    ld a, (ghc_left)
    or a
    jr z, _ghc_pause
    dec a
    ld (ghc_left), a
    ld a, (ghc_i)
    call _game_cell_rc
    call _game_redraw_cell
_ghc_next:
    ld a, (ghc_i)
    inc a
    jr _ghc_cell
_ghc_pause:
    ld a, (ghc_i)                 ; the rest on the next frame
    ld (hint_pos), a
    ld a, #0xFF
    ld (fc_override), a
    ret
_ghc_done:
    ld a, #0xFF
    ld (hint_pos), a
    ld (fc_override), a
    jp _game_render_cursor

_game_cell_rc:
    ld b, #0
    ld hl, #catdoku_n
_gcr:
    cp (hl)
    jr c, _gcr_done
    sub (hl)
    inc b
    jr _gcr
_gcr_done:
    ld c, a
    ret

_game_help_clear:
    ld b, #HELP_X
    ld c, #HELP_Y - 3
    ld d, #HELP_WIDTH
    ld e, #12
    ld a, #PEN_DARK_RED
    jp ui_rect

_game_hint_text:
    ld de, #hint_text
    ld a, (hint_kind)
    cp #HINT_ERR
    ld hl, #str_hint_err
    jr z, _ght_copy
    cp #HINT_RULED
    ld hl, #str_hint_ruled
    jr z, _ght_copy
    cp #HINT_TRIAL
    ld hl, #str_hint_trial
    jr z, _ght_copy
    cp #HINT_ONE
    jr nz, _ght_fit
    ld hl, #str_hint_one
    call _ght_append
    ld a, (hint_fam_a)
    call _ght_name
    jr _ght_show
_ght_fit:
    ld a, (hint_k)
    cp #1
    jr nz, _ght_many
    ld hl, #str_hint_this         ; "THIS <A> FITS IN ONE <B>"
    call _ght_append
    ld a, (hint_fam_a)
    call _ght_name
    ld hl, #str_hint_fits_one
    call _ght_append
    ld a, (hint_fam_b)
    call _ght_name
    jr _ght_show
_ght_many:
    ld hl, #str_hint_these        ; "THESE <k> <A>S FIT IN <k> <B>S"
    call _ght_append
    call _ght_digit
    ld a, (hint_fam_a)
    call _ght_name
    ld a, #'S'
    ld (de), a
    inc de
    ld hl, #str_hint_fit_in
    call _ght_append
    call _ght_digit
    ld a, (hint_fam_b)
    call _ght_name
    ld a, #'S'
    ld (de), a
    inc de
    jr _ght_show
_ght_copy:
    call _ght_append
_ght_show:
    xor a
    ld (de), a
    call _game_help_clear
    ld iy, #hint_text
    jp ui_help_centred

;; Appends the string at HL to DE (without its NUL). Modifies: AF, DE, HL.
_ght_append:
    ld a, (hl)
    or a
    ret z
    ld (de), a
    inc hl
    inc de
    jr _ght_append

;; Appends "ROW", "COLUMN" or "REGION" (A = family). Modifies: AF, DE, HL.
_ght_name:
    ld hl, #str_hint_row
    or a
    jr z, _ght_append
    ld hl, #str_hint_column
    dec a
    jr z, _ght_append
    ld hl, #str_hint_region
    jr _ght_append

;; Appends hint_k and a space. Modifies: AF, DE.
_ght_digit:
    ld a, (hint_k)
    add a, #'0'
    ld (de), a
    inc de
    ld a, #' '
    ld (de), a
    inc de
    ret

ghc_i: .db 0
ghc_left: .db 0
ghc_nn: .db 0
str_hint_err: .asciz "THIS X COVERS A CAT"
str_hint_ruled: .asciz "A CAT RULES OUT THESE CELLS"
str_hint_trial: .asciz "A CAT HERE LEADS TO A CONTRADICTION"
str_hint_one: .asciz "ONLY ONE PLACE LEFT IN THIS "
str_hint_this: .asciz "THIS "
str_hint_fits_one: .asciz " FITS IN ONE "
str_hint_these: .asciz "THESE "
str_hint_fit_in: .asciz " FIT IN "
str_hint_row: .asciz "ROW"
str_hint_column: .asciz "COLUMN"
str_hint_region: .asciz "REGION"
