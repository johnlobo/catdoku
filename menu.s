;; menu.s - Main menu and level selection for Catdoku

.module game_menu
.globl menu_update, level_select_update
.globl game_state
.globl menu_dirty
.include "common.inc"

;; ---- Data area ----
.area _DATA

menu_selection:: .db 0       ; current menu item: 0 NEW GAME, 1 CONTINUE, 2 AUTO MARK
menu_dirty:: .db 1           ; redraw only when set
level_select_diff:: .db 0     ; current difficulty (0-4)
level_select_item:: .db 0     ; current level within difficulty (0-39)
game_state:: .db 0           ; global game state (STATE_*)

str_menu_title:: .asciz "CATDOKU"
str_menu_new:: .asciz "NEW GAME"
str_menu_cont:: .asciz "CONTINUE"
str_menu_auto_on: .asciz "AUTO MARK:ON"
str_menu_auto_off: .asciz "AUTO MARK:OFF"
str_ls_title: .asciz "SELECT LEVEL"
str_ls_best: .asciz "BEST:"
str_ls_none: .asciz "--"
str_ls_help: .asciz "RETURN:PLAY SPACE:DIFFICULTY ESC:BACK"
str_diff_0: .asciz "BEGINNER"
str_diff_1: .asciz "EASY"
str_diff_2: .asciz "MEDIUM"
str_diff_3: .asciz "HARD"
str_diff_4: .asciz "EXPERT"
ls_diff_names: .dw str_diff_0, str_diff_1, str_diff_2, str_diff_3, str_diff_4
ls_prev_item: .db 0
ls_keys: .db 0
ls_item: .db 0
ls_x: .db 0
ls_y: .db 0
ls_cy: .db 0
ls_cw: .db 0
ls_cn: .db 0
ls_num: .db 0, 0, 0               ; two digits + NUL

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; menu_update
;;   In: none
;;   Out: none
;;   Modifies: menu_selection, level_select_diff, level_select_item, game_state
;;   Handles menu navigation and input
;; ----------------------------------------------------------------------------
menu_update::
    ;; Handle input
    ld a, (fwk_input_pressed)
    bit 0, a            ; UP
    jr z, _mu_down
    ld a, (menu_selection)
    or a
    jr z, _mu_down
    ;; toggle old, move, toggle new
    call _menu_toggle_indicator
    ld a, (menu_selection)
    dec a
    ld (menu_selection), a
    call _menu_toggle_indicator
_mu_down:
    ld a, (fwk_input_pressed)
    bit 1, a            ; DOWN
    jr z, _mu_enter
    ld a, (menu_selection)
    cp #2                         ; last item: AUTO MARK
    jr z, _mu_enter
    call _menu_toggle_indicator
    ld a, (menu_selection)
    inc a
    ld (menu_selection), a
    call _menu_toggle_indicator
_mu_enter:
    ld a, (fwk_input_pressed)
    bit 4, a            ; ENTER
    jr z, _mu_check_dirty
    ld a, (menu_selection)
    or a
    jr z, _mu_new
    cp #2
    jr nz, _mu_continue
    ;; AUTO MARK: flip it, show it, keep it on the disc
    call save_toggle_auto_mark
    call _menu_draw_auto_mark
    call save_write_settings
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    jp fwk_audio_play_sfx
_mu_continue:
    ;; CONTINUE: open level select on the first level not completed
    ld c, #0
_mu_cont_loop:
    ld a, c
    push bc
    call save_is_completed
    pop bc
    or a
    jr z, _mu_cont_found
    inc c
    ld a, c
    cp #CATDOKU_NUM_LEVELS
    jr nz, _mu_cont_loop
    ld c, #0                      ; all done: start at the first one
_mu_cont_found:
    ld a, c                       ; difficulty = id / 40, item = id % 40
    ld b, #0
_mu_div40:
    cp #CATDOKU_LEVELS_PER_DIFF
    jr c, _mu_div_done
    sub #CATDOKU_LEVELS_PER_DIFF
    inc b
    jr _mu_div40
_mu_div_done:
    ld (level_select_item), a
    ld a, b
    ld (level_select_diff), a
    jr _mu_to_level_select
_mu_new:
    xor a
    ld (level_select_diff), a
    ld (level_select_item), a
_mu_to_level_select:
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret
_mu_check_dirty:
    ;; Redraw only if dirty
    ld a, (menu_dirty)
    or a
    ret z
    xor a
    ld (menu_dirty), a
    ;; Clear and draw
    xor a
    call fwk_video_clear_visible
    ;; Title centered in top third (scanline ~40, column ~33 for 7 chars)
    ld hl, #str_menu_title
    ld b, #40
    ld c, #33
    call _menu_draw_text_at
    ;; Options centered in bottom third
    ld hl, #str_menu_new
    ld b, #140
    ld c, #32                     ; centred: 40 - length
    call _menu_draw_text_at
    ld hl, #str_menu_cont
    ld b, #160
    ld c, #32
    call _menu_draw_text_at
    call _menu_draw_auto_mark
    ;; Selection indicator (XOR marker)
    call _menu_toggle_indicator
    ret

;; ----------------------------------------------------------------------------
;; level_select_update
;;   One difficulty (40 levels) as an 8x5 grid of numbers: yellow = selected,
;;   green = completed, white = pending. Best time of the selected level below.
;;   Cursors move, SPACE changes difficulty, RETURN plays, ESC back to the menu.
;;   The whole screen is drawn only when menu_dirty is set; a move redraws the
;;   two items involved and the best time.
;; ----------------------------------------------------------------------------
level_select_update::
    ld a, (menu_dirty)
    or a
    jr z, _ls_input
    xor a
    ld (menu_dirty), a
    call _ls_draw_all
_ls_input:
    ld a, (level_select_item)
    ld (ls_prev_item), a
    ld a, (fwk_input_pressed)
    ld (ls_keys), a
    bit 7, a                      ; ESC: back to the main menu
    jr z, _ls_play
    ld a, #STATE_MENU
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret
_ls_play:
    bit 4, a                      ; RETURN: play
    jp nz, _ls_start
    bit 5, a                      ; SPACE: next difficulty
    jr z, _ls_move
    ld a, (level_select_diff)
    inc a
    cp #CATDOKU_DIFFICULTIES
    jr c, _ls_diff_ok
    xor a
_ls_diff_ok:
    ld (level_select_diff), a
    ld a, #1
    ld (menu_dirty), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    jp fwk_audio_play_sfx
_ls_move:
    ld a, (level_select_item)
    ld c, a
    ld a, (ls_keys)
    bit 2, a                      ; LEFT
    jr z, _ls_not_left
    ld a, c
    or a
    jr z, _ls_not_left
    dec c
_ls_not_left:
    ld a, (ls_keys)
    bit 3, a                      ; RIGHT
    jr z, _ls_not_right
    ld a, c
    cp #CATDOKU_LEVELS_PER_DIFF - 1
    jr z, _ls_not_right
    inc c
_ls_not_right:
    ld a, (ls_keys)
    bit 0, a                      ; UP: previous row
    jr z, _ls_not_up
    ld a, c
    cp #8
    jr c, _ls_not_up
    sub #8
    ld c, a
_ls_not_up:
    ld a, (ls_keys)
    bit 1, a                      ; DOWN: next row
    jr z, _ls_not_down
    ld a, c
    cp #CATDOKU_LEVELS_PER_DIFF - 8
    jr nc, _ls_not_down
    add a, #8
    ld c, a
_ls_not_down:
    ld a, (ls_prev_item)
    cp c
    ret z
    ld a, c
    ld (level_select_item), a
    ld a, (ls_prev_item)
    call _ls_draw_item            ; old one, no longer yellow
    ld a, (level_select_item)
    call _ls_draw_item
    call _ls_draw_best
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    jp fwk_audio_play_sfx

_ls_start:
    ld a, (level_select_item)
    call _ls_level_id
    ld (current_level_id), a
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ld (game_timer_seconds), a
    ld (game_timer_seconds + 1), a
    ld (game_won), a
    ld (cursor_row), a
    ld (cursor_col), a
    ld a, (current_level_id)
    call board_load_level
    ld a, #STATE_GAME
    ld (game_state), a
    ld a, #1
    ld (game_dirty), a
    ret

;; In: A = item 0..39. Out: A = level id = difficulty*40 + item. Modifies B, C.
_ls_level_id:
    ld b, a
    ld a, (level_select_diff)
    ld c, a
    add a, a                      ; x2
    add a, a                      ; x4
    add a, c                      ; x5
    add a, a                      ; x10
    add a, a                      ; x20
    add a, a                      ; x40
    add a, b
    ret

_ls_draw_all:
    xor a
    call fwk_video_clear_visible
    xor a
    call fwk_text_set_color
    ld hl, #str_ls_title
    ld b, #12
    call _menu_draw_centered
    ;; difficulty name, yellow
    ld a, #TEXT_YELLOW
    call fwk_text_set_color
    ld a, (level_select_diff)
    add a, a
    ld e, a
    ld d, #0
    ld hl, #ls_diff_names
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ld b, #30
    call _menu_draw_centered
    xor a
    call fwk_text_set_color
    ;; 40 items
    xor a
_ls_all_items:
    push af
    call _ls_draw_item
    pop af
    inc a
    cp #CATDOKU_LEVELS_PER_DIFF
    jr nz, _ls_all_items
    call _ls_draw_best
    ld hl, #str_ls_help           ; one line at the bottom, 37 chars: column 40 - 37
    ld b, #190
    ld c, #3
    jp help_draw_line

;; In: A = item. Draws its number at col 10+(i%8)*8, line 52+(i/8)*20.
_ls_draw_item:
    ld (ls_item), a
    and #7
    add a, a
    add a, a
    add a, a
    add a, #10
    ld (ls_x), a
    ld a, (ls_item)
    srl a
    srl a
    srl a
    ld c, a
    add a, a
    add a, a
    add a, c                      ; row x5
    add a, a
    add a, a                      ; row x20
    add a, #52
    ld (ls_y), a
    ld b, #4                      ; two characters
    call _ls_clear
    ;; "NN" = item + 1
    ld a, (ls_item)
    inc a
    ld c, #'0'
_ls_tens:
    cp #10
    jr c, _ls_tens_done
    sub #10
    inc c
    jr _ls_tens
_ls_tens_done:
    add a, #'0'
    ld (ls_num + 1), a
    ld a, c
    ld (ls_num), a
    ;; colour: selected yellow, completed green, else white
    ld a, (level_select_item)
    ld b, a
    ld a, (ls_item)
    cp b
    ld a, #TEXT_YELLOW
    jr z, _ls_colour
    ld a, (ls_item)
    call _ls_level_id
    call save_is_completed
    or a
    ld a, #TEXT_WHITE
    jr z, _ls_colour
    ld a, #TEXT_GREEN
_ls_colour:
    call fwk_text_set_color
    ld a, (ls_y)
    ld l, a
    ld h, #0
    ld a, (ls_x)
    ld c, a
    call fwk_video_get_ptr
    ld iy, #ls_num
    call fwk_text_draw
    xor a
    jp fwk_text_set_color

;; "BEST: n" or "BEST: --" for the selected level, line 150.
_ls_draw_best:
    ld a, #20
    ld (ls_x), a
    ld a, #150
    ld b, #40
    call _ls_clear
    ld hl, #str_ls_best
    ld b, #150
    ld c, #30
    call _menu_draw_text_at
    ld a, (level_select_item)
    call _ls_level_id
    call save_get_time
    ld a, h
    or l
    jr z, _ls_no_best
    ld b, #150
    ld c, #42
    jp game_draw_number_at
_ls_no_best:
    ld hl, #str_ls_none
    ld b, #150
    ld c, #42
    jp _menu_draw_text_at

;; In: A = top line, B = width in bytes, ls_x = first byte. Clears 9 lines.
_ls_clear:
    ld (ls_cy), a
    ld a, b
    ld (ls_cw), a
    ld a, #9
    ld (ls_cn), a
_ls_clear_line:
    ld a, (ls_cy)
    ld l, a
    ld h, #0
    ld a, (ls_x)
    ld c, a
    call fwk_video_get_ptr
    ld a, (ls_cw)
    ld b, a
_ls_clear_byte:
    ld (hl), #0
    inc hl
    djnz _ls_clear_byte
    ld a, (ls_cy)
    inc a
    ld (ls_cy), a
    ld a, (ls_cn)
    dec a
    ld (ls_cn), a
    jr nz, _ls_clear_line
    ret

;; In: HL = string, B = line. Draws it centred (column = 40 - length).
_menu_draw_centered:
    push hl
    ld c, #0
_mdc_len:
    ld a, (hl)
    or a
    jr z, _mdc_go
    inc hl
    inc c
    jr _mdc_len
_mdc_go:
    pop hl
    ld a, #40
    sub c
    ld c, a
    jp _menu_draw_text_at

_menu_draw_text:
    ;; In: HL = string ptr, B = scanline Y (column 4)
    ;; Out: none
    push hl
    ld l, b
    ld h, #0
    ld c, #4
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_menu_draw_text_at:
    ;; In: HL = string ptr, B = scanline Y, C = column
    ;; Out: none
    push hl
    ld l, b
    ld h, #0
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

;; AUTO MARK:ON / AUTO MARK:OFF on the third line (13 characters: 40 - 13)
_menu_draw_auto_mark:
    ;; Clear the old text first: fwk_text_draw does not paint spaces
    ld hl, #180
    ld c, #27
    call fwk_video_get_ptr
    ex de, hl
    xor a
    ld b, #9                      ; FWK_TEXT_FONT_HEIGHT
    ld c, #26
    call cpct_drawSolidBox_asm
    call save_get_auto_mark
    ld hl, #str_menu_auto_off
    or a
    jr z, _mdam_draw
    ld hl, #str_menu_auto_on
_mdam_draw:
    ld b, #180
    ld c, #27
    jp _menu_draw_text_at

_menu_sel_y:
    ;; In: none; uses menu_selection
    ;; Out: A = scanline Y (140 + selection*20)
    ld a, (menu_selection)
    ld b, a
    ld a, #0
    or b
    jr z, _msy_done
    ld c, #20
_msy_mul:
    add a, c
    djnz _msy_mul
_msy_done:
    add a, #140
    ret

_menu_toggle_indicator:
    ;; XOR a cat sprite at the current selection's indicator position
    call _menu_sel_y
    ld (catdoku_temp_row), a   ; base Y
    xor a
    ld (catdoku_temp_col), a   ; row 0
_mt_row:
    ld a, (catdoku_temp_col)
    cp #8
    jr z, _mt_done
    ; scanline = base Y + row
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_col)
    add a, b
    ld l, a
    ld h, #0
    ld c, #22                    ; marker left of the centred items
    call fwk_video_get_ptr       ; HL = dest
    push hl
    ; sprite row pointer = catdoku_cat_pixels + row*4
    ld a, (catdoku_temp_col)
    sla a
    sla a
    ld c, a
    ld b, #0
    ld hl, #catdoku_cat_pixels
    add hl, bc
    ex de, hl                    ; DE = sprite row
    pop hl                       ; HL = dest
    ; XOR 4 bytes
    ld b, #4
_mt_byte:
    ld a, (de)
    xor (hl)
    ld (hl), a
    inc de
    inc hl
    djnz _mt_byte
    ; next row
    ld a, (catdoku_temp_col)
    inc a
    ld (catdoku_temp_col), a
    jr _mt_row
_mt_done:
    ret

