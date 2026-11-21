;; menu.s - Main menu and level selection for Catdoku

.module game_menu
.globl menu_update, level_select_update
.globl game_state
.globl menu_dirty
.include "common.inc"

;; ---- Data area ----
.area _DATA

menu_selection:: .db 0       ; current menu item: 0 NEW GAME, 1 CONTINUE, 2 RULES, 3 AUTO MARK
menu_dirty:: .db 1           ; redraw only when set
level_select_diff:: .db 0     ; current difficulty (0-4)
level_select_item:: .db 0     ; current level within difficulty (0-39)
game_state:: .db 0           ; global game state (STATE_*)

str_menu_title:: .asciz "CATDOKU"
str_menu_new:: .asciz "NEW GAME"
str_menu_cont:: .asciz "CONTINUE"
str_menu_rules: .asciz "RULES"
str_cn_question: .asciz "ERASE ALL PROGRESS?"
str_cn_detail_1: .asciz "COMPLETED LEVELS AND BEST TIMES"
str_cn_detail_2: .asciz "WILL BE DELETED"
str_cn_keys: .asciz "RETURN:YES   ESC:NO"
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
ls_text_pen: .db 0
ls_partial: .db 0                 ; 1: difficulty change, the background stays
ls_old_diff: .db 0
menu_prev: .db 0                  ; item to redraw unselected after a move
mdi_item: .db 0                   ; _menu_draw_item
mdi_y: .db 0
mdi_pen: .db 0
menu_item_strings: .dw str_menu_new, str_menu_cont, str_menu_rules, str_menu_auto_off
;; Paw in the selected box (5x5, bit 7 = left pixel)
menu_paw: .db 0x50, 0xA8, 0x20, 0x70, 0x70

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
    ld (menu_prev), a
    dec a
    call _menu_skip_continue_up
    ld (menu_selection), a
    call _menu_redraw_moved
_mu_down:
    ld a, (fwk_input_pressed)
    bit 1, a            ; DOWN
    jr z, _mu_enter
    ld a, (menu_selection)
    cp #3                         ; last item: AUTO MARK
    jr z, _mu_enter
    ld a, (menu_selection)
    ld (menu_prev), a
    inc a
    call _menu_skip_continue_down
    ld (menu_selection), a
    call _menu_redraw_moved
_mu_enter:
    ld a, (fwk_input_pressed)
    bit 4, a            ; ENTER
    jr z, _mu_check_dirty
    ld a, (menu_selection)
    or a
    jr z, _mu_new
    cp #2
    jr z, _mu_rules
    cp #3
    jr nz, _mu_continue
    ;; AUTO MARK: flip it, show it, keep it on the disc
    call save_toggle_auto_mark
    ld a, #3
    call _menu_draw_item
    call save_write_settings
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    jp fwk_audio_play_sfx
_mu_rules:
    ld a, #STATE_RULES
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret
_mu_continue:
    ;; CONTINUE: open level select on the first level not completed.
    ;; Disabled (grey) while no level is completed.
    ld a, (catdoku_save_count)
    or a
    ret z
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
    ;; NEW GAME with progress on the disc: confirm erasing it first
    ld a, (catdoku_save_count)
    or a
    jr z, _mu_new_start
    ld a, #STATE_CONFIRM_NEW
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret
_mu_new_start:
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
    ld a, #UI_BG_MENU
    call ui_show_background
    ;; CONTINUE is grey, and never selected, while nothing is completed
    ld a, (catdoku_save_count)
    or a
    jr nz, _mu_items
    ld a, (menu_selection)
    cp #1
    jr nz, _mu_items
    xor a
    ld (menu_selection), a
_mu_items:
    xor a
_mu_item_loop:
    push af
    call _menu_draw_item
    pop af
    inc a
    cp #4
    jr nz, _mu_item_loop
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
    ld (ls_old_diff), a
    inc a
    cp #CATDOKU_DIFFICULTIES
    jr c, _ls_diff_ok
    xor a
_ls_diff_ok:
    ld (level_select_diff), a
    ld a, #1
    ld (menu_dirty), a
    ld (ls_partial), a
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
;; _ls_level_id_of: the same with C = difficulty.
_ls_level_id:
    ld b, a
    ld a, (level_select_diff)
    ld c, a
    jr _ls_level_id_c
_ls_level_id_of:
    ld b, a
    ld a, c
_ls_level_id_c:
    add a, a                      ; x2
    add a, a                      ; x4
    add a, c                      ; x5
    add a, a                      ; x10
    add a, a                      ; x20
    add a, a                      ; x40
    add a, b
    ret

_ls_draw_all:
    ;; The background already holds the 40 boxes as unselected, uncompleted
    ;; levels; only the boxes that differ are drawn. A difficulty change keeps
    ;; the background and also redraws the levels completed in the old one.
    ld a, (ls_partial)
    or a
    jr nz, _ls_keep_background
    ld a, #UI_BG_LEVELS
    call ui_show_background
    ld a, #0xFF                   ; no old difficulty to undo
    ld (ls_old_diff), a
_ls_keep_background:
    ;; difficulty name, yellow in the teal box
    ld b, #LS_DIFF_X
    ld c, #LS_DIFF_Y
    ld d, #LS_DIFF_W
    ld e, #LS_DIFF_H
    ld h, #PEN_SEA_GREEN
    ld l, #PEN_TEAL
    call ui_box
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
    push hl
    pop iy
    ld b, #LS_DIFF_X
    ld d, #LS_DIFF_W
    ld c, #LS_DIFF_Y + 5
    ld a, #PEN_YELLOW
    call ui_text_in
    ;; the boxes that are not as in the background
    xor a
_ls_all_items:
    push af
    call _ls_item_differs
    or a
    jr z, _ls_all_skip
    pop af
    push af
    call _ls_draw_item
_ls_all_skip:
    pop af
    inc a
    cp #CATDOKU_LEVELS_PER_DIFF
    jr nz, _ls_all_items
    call _ls_draw_best
    ld a, (ls_partial)
    or a
    ld a, #0
    ld (ls_partial), a
    ret nz
    ld iy, #str_ls_help
    jp ui_help

;; In: A = item. Out: A != 0 when its box differs from the background:
;; selected, completed, or completed in ls_old_diff. Modifies: AF, BC, DE, HL.
_ls_item_differs:
    ld (ls_item), a
    ld b, a
    ld a, (level_select_item)
    cp b
    jr z, _lid_yes
    ld a, (ls_item)
    call _ls_level_id
    call save_is_completed
    or a
    ret nz
    ld a, (ls_old_diff)
    cp #CATDOKU_DIFFICULTIES
    jr nc, _lid_no
    ld c, a
    ld a, (ls_item)
    call _ls_level_id_of
    call save_is_completed
    ret
_lid_no:
    xor a
    ret
_lid_yes:
    ld a, #1
    ret

;; In: A = item. Its box at x 10 + (i%8)*18, y 54 + (i/8)*20: yellow with
;; orange border when selected, else olive border on dark red or black
;; (alternating, as the design); the number black when selected, sea green
;; when completed, white otherwise.
_ls_draw_item:
    ld (ls_item), a
    and #7
    ld c, a
    add a, a
    add a, a
    add a, a
    add a, c                      ; x9
    add a, a                      ; x18
    add a, #LS_BOX_X
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
    add a, #LS_BOX_Y
    ld (ls_y), a
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
    ;; style
    ld a, (level_select_item)
    ld b, a
    ld a, (ls_item)
    cp b
    jr nz, _ls_normal
    ld a, #PEN_BLACK
    ld (ls_text_pen), a
    ld h, #PEN_ORANGE
    ld l, #PEN_YELLOW
    jr _ls_box
_ls_normal:
    ld a, (ls_item)
    call _ls_level_id
    call save_is_completed
    or a
    ld a, #PEN_WHITE
    jr z, _ls_pen
    ld a, #PEN_SEA_GREEN
_ls_pen:
    ld (ls_text_pen), a
    ;; fill: dark red when column + row is even, else black
    ld a, (ls_item)
    ld c, a
    srl a
    srl a
    srl a
    add a, c                      ; row + item: same parity as row + column
    and #1
    ld l, #PEN_DARK_RED
    jr z, _ls_fill
    ld l, #PEN_BLACK
_ls_fill:
    ld h, #PEN_OLIVE
_ls_box:
    ld a, (ls_x)
    ld b, a
    ld a, (ls_y)
    ld c, a
    ld d, #LS_BOX_W
    ld e, #LS_BOX_H
    call ui_box
    ld a, (ls_x)
    add a, #4
    ld b, a
    ld a, (ls_y)
    add a, #4
    ld c, a
    ld iy, #ls_num
    ld a, (ls_text_pen)
    jp ui_text

;; "BEST: n" or "BEST: --" for the selected level, in its box.
_ls_draw_best:
    ld b, #LS_BEST_X
    ld c, #LS_BEST_Y
    ld d, #LS_BEST_W
    ld e, #LS_BEST_H
    ld h, #PEN_ORANGE
    ld l, #PEN_DARK_RED
    call ui_box
    ld iy, #str_ls_best
    ld b, #LS_BEST_X + 8
    ld c, #LS_BEST_Y + 5
    ld a, #PEN_YELLOW
    call ui_text
    ld a, (level_select_item)
    call _ls_level_id
    call save_get_time
    ld a, h
    or l
    jr z, _ls_no_best
    ld b, #LS_BEST_X + 32
    ld c, #LS_BEST_Y + 5
    ld a, #PEN_WHITE
    jp game_draw_number_at
_ls_no_best:
    ld iy, #str_ls_none
    ld b, #LS_BEST_X + 32
    ld c, #LS_BEST_Y + 5
    ld a, #PEN_WHITE
    jp ui_text

;; In: A = menu item after moving up / down. Out: A, skipping CONTINUE (1)
;; while it is disabled. Modifies: AF.
_menu_skip_continue_up:
    cp #1
    ret nz
    ld a, (catdoku_save_count)
    or a
    ld a, #1
    ret nz
    xor a
    ret
_menu_skip_continue_down:
    cp #1
    ret nz
    ld a, (catdoku_save_count)
    or a
    ld a, #1
    ret nz
    ld a, #2
    ret

;; ----------------------------------------------------------------------------
;; confirm_new_update
;;   STATE_CONFIRM_NEW: "ERASE ALL PROGRESS?" drawn once (menu_dirty).
;;   RETURN erases the progress (save_reset_progress writes CATDOKU.SAV) and
;;   opens level select on the first level; ESC goes back to the menu.
;; ----------------------------------------------------------------------------
confirm_new_update::
    ld a, (menu_dirty)
    or a
    jr z, _cn_input
    xor a
    ld (menu_dirty), a
    ld a, #UI_BG_PLAIN
    call ui_show_background
    ld iy, #str_cn_question
    ld c, #60
    call menu_title_box
    ld iy, #str_cn_detail_1
    ld c, #95
    ld a, #PEN_WHITE
    call menu_text_centred
    ld iy, #str_cn_detail_2
    ld c, #105
    ld a, #PEN_WHITE
    call menu_text_centred
    ld iy, #str_cn_keys
    jp ui_help_centred
_cn_input:
    ld a, (fwk_input_pressed)
    bit 7, a                      ; ESC: keep everything
    jr z, _cn_yes
    ld a, #STATE_MENU
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret
_cn_yes:
    bit 4, a                      ; RETURN: erase and start
    ret z
    call save_reset_progress
    xor a
    ld (level_select_diff), a
    ld (level_select_item), a
    ld (menu_selection), a
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret

;; ----------------------------------------------------------------------------
;; rules_update
;;   STATE_RULES: the rules screen, drawn once (menu_dirty), any key goes
;;   back to the main menu. The big font has no "," or ".": one idea per line.
;; ----------------------------------------------------------------------------
rules_update::
    ld a, (menu_dirty)
    or a
    jr z, _ru_wait
    xor a
    ld (menu_dirty), a
    ld a, #UI_BG_PLAIN
    call ui_show_background
    ld iy, #str_rules_title
    ld c, #16
    call menu_title_box
    ld iy, #str_rules_key
    call ui_help_centred
    ld hl, #rules_lines
_ru_line:
    ld a, (hl)                    ; line, 0 ends the table
    or a
    jr z, _ru_wait
    ld c, a
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)                    ; DE = string
    inc hl
    push hl
    push de
    pop iy
    ld a, #PEN_WHITE
    call menu_text_centred
    pop hl
    jr _ru_line
_ru_wait:
    ld a, (fwk_input_pressed)
    or a
    ret z
    ld a, #STATE_MENU
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    ret

;; line, string; 0 ends
rules_lines:
    .db 48
    .dw str_rules_1
    .db 58
    .dw str_rules_2
    .db 68
    .dw str_rules_3
    .db 90
    .dw str_rules_4
    .db 100
    .dw str_rules_5
    .db 122
    .dw str_rules_6
    .db 144
    .dw str_rules_7
    .db 0
str_rules_title: .asciz "RULES"
str_rules_1: .asciz "PLACE ONE CAT IN EVERY ROW"
str_rules_2: .asciz "IN EVERY COLUMN"
str_rules_3: .asciz "AND IN EVERY COLOUR REGION"
str_rules_4: .asciz "CATS NEVER TOUCH EACH OTHER"
str_rules_5: .asciz "NOT EVEN DIAGONALLY"
str_rules_6: .asciz "NO GUESSING NEEDED: MARK WITH X"
str_rules_7: .asciz "A CAT IN THE WRONG CELL ENDS THE GAME"
str_rules_key: .asciz "PRESS ANY KEY"

;; ----------------------------------------------------------------------------
;; _menu_redraw_moved
;;   After a move: menu_prev drawn unselected, menu_selection selected.
;; _menu_draw_item
;;   In: A = item 0..3. Its box: yellow with orange border, the paw and black
;;   text when selected; else dark red with olive border and white text (grey
;;   for CONTINUE while nothing is completed). Item 3 shows AUTO MARK:ON/OFF.
;;   Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
_menu_redraw_moved:
    ld a, (menu_prev)
    call _menu_draw_item
    ld a, (menu_selection)
    ; fall through
_menu_draw_item:
    ld (mdi_item), a
    ld c, a
    add a, a
    add a, a
    add a, a
    add a, a
    add a, c                      ; x17
    add a, #MENU_ITEM_Y
    ld (mdi_y), a
    ld a, (menu_selection)
    ld b, a
    ld a, (mdi_item)
    cp b
    jr nz, _mdi_normal
    ld a, #PEN_BLACK
    ld (mdi_pen), a
    ld h, #PEN_ORANGE
    ld l, #PEN_YELLOW
    call _mdi_box
    ld hl, #menu_paw
    ld b, #MENU_BOX_X + 5
    ld a, (mdi_y)
    add a, #4
    ld c, a
    ld de, #0x0505
    ld a, #PEN_DARK_RED
    call ui_pattern
    jr _mdi_text
_mdi_normal:
    ld a, #PEN_WHITE
    ld (mdi_pen), a
    ld a, (mdi_item)
    cp #1
    jr nz, _mdi_box_normal
    ld a, (catdoku_save_count)
    or a
    jr nz, _mdi_box_normal
    ld a, #PEN_GREY
    ld (mdi_pen), a
_mdi_box_normal:
    ld h, #PEN_OLIVE
    ld l, #PEN_DARK_RED
    call _mdi_box
_mdi_text:
    ld a, (mdi_item)
    add a, a
    ld e, a
    ld d, #0
    ld hl, #menu_item_strings
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ld a, (mdi_item)
    cp #3
    jr nz, _mdi_string
    call save_get_auto_mark
    or a
    ld hl, #str_menu_auto_off
    jr z, _mdi_string
    ld hl, #str_menu_auto_on
_mdi_string:
    push hl
    pop iy
    ld b, #MENU_BOX_X
    ld d, #MENU_BOX_W
    ld a, (mdi_y)
    add a, #4
    ld c, a
    ld a, (mdi_pen)
    jp ui_text_in
_mdi_box:
    ld b, #MENU_BOX_X
    ld a, (mdi_y)
    ld c, a
    ld d, #MENU_BOX_W
    ld e, #MENU_BOX_H
    jp ui_box

;; ----------------------------------------------------------------------------
;; menu_title_box
;;   In: IY = string, C = top line. A 15-line box with orange border and dark
;;   red fill, as wide as the text plus 12 pixels and centred, the text yellow.
;;   Modifies: AF, BC, DE, HL, IY.
;; menu_text_centred
;;   In: IY = string, C = line, A = pen. Centred on the screen.
;;   Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
menu_title_box::
    push iy
    pop hl
    ld e, #0
_mtb_len:
    ld a, (hl)
    or a
    jr z, _mtb_len_done
    inc hl
    inc e
    jr _mtb_len
_mtb_len_done:
    ld a, e
    add a, a
    add a, a
    add a, #11                    ; text width (4n - 1) + 12
    ld d, a
    ld a, #160
    sub d
    srl a
    ld b, a
    push bc
    push de
    push iy
    ld e, #15
    ld h, #PEN_ORANGE
    ld l, #PEN_DARK_RED
    call ui_box
    pop iy
    pop de
    pop bc
    ld a, c
    add a, #5
    ld c, a
    ld a, #PEN_YELLOW
    jp ui_text_in
menu_text_centred::
    ld b, #0
    ld d, #160
    jp ui_text_in
