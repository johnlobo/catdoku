;; menu.s - Main menu and level selection for Catdoku

.module game_menu
.globl menu_update
.globl game_state
.include "common.inc"

;; ---- Data area ----
.area _DATA

menu_state:: .db 0           ; 0=main menu, 1=level select
menu_selection:: .db 0       ; current menu item (0-2)
level_select_diff:: .db 0     ; current difficulty (0-4)
level_select_item:: .db 0     ; current level within difficulty (0-39)
game_state:: .db 0           ; global game state (STATE_*)

str_menu_title:: .asciz "CATDOKU"
str_menu_new:: .asciz "NUEVA PARTIDA"
str_menu_cont:: .asciz "CONTINUAR"
str_menu_exit:: .asciz "SALIR"
str_menu_diff:: .asciz "INICIACION  FACIL  MEDIO  DIFICIL  EXPERTO"
str_menu_level:: .asciz "NIVEL"
str_menu_completed:: .asciz "[X]"
str_menu_pending:: .asciz "[ ]"

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; menu_update
;;   In: none
;;   Out: none
;;   Modifies: menu_state, menu_selection, level_select_diff, level_select_item, game_state
;;   Handles menu navigation and input
;; ----------------------------------------------------------------------------
menu_update::
    ;; Simple: just clear screen and draw title
    xor a
    call fwk_video_clear_visible
    ;; Test: draw solid line at scanline 0
    ld a, #0xFF
    ld hl, #0
    ld c, #0
    call fwk_video_plot_byte
    ld a, #0xFF
    ld hl, #0
    ld c, #1
    call fwk_video_plot_byte
    ld a, #0xFF
    ld hl, #0
    ld c, #2
    call fwk_video_plot_byte
    ld hl, #str_menu_title
    ld b, #80
    call _menu_draw_text
    ret

_mu_main_menu_unused:
    ;; Handle input
    ld a, (fwk_input_pressed)
    bit 0, a            ; UP pressed
    jr z, _mu_main_down
    ;; Move selection up
    ld a, (menu_selection)
    or a
    jr z, _mu_main_down
    dec a
    ld (menu_selection), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx

_mu_main_down:
    ld a, (fwk_input_pressed)
    bit 1, a            ; DOWN pressed
    jr z, _mu_main_enter
    ld a, (menu_selection)
    cp #2
    jr z, _mu_main_enter
    inc a
    ld (menu_selection), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx

_mu_main_enter:
    ld a, (fwk_input_pressed)
    bit 4, a            ; CAT (ENTER) pressed
    jr z, _mu_main_draw
    ;; Handle selection
    ld a, (menu_selection)
    cp #0
    jr z, _mu_new_game
    cp #1
    jr z, _mu_continue
    ;; Exit
    jr _mu_main_draw

_mu_new_game:
    ;; Go to level select
    ld a, #1
    ld (menu_state), a
    xor a
    ld (level_select_diff), a
    ld (level_select_item), a
    jr _mu_main_draw

_mu_continue:
    ;; Go to level select (continue from last)
    ld a, #1
    ld (menu_state), a
    xor a
    ld (level_select_diff), a
    ld (level_select_item), a
    jr _mu_main_draw

_mu_main_draw:
    ;; Clear screen
    xor a
    call fwk_video_clear_visible
    ;; Draw title
    ld hl, #str_menu_title
    ld b, #20
    call _menu_draw_text
    ;; Draw options
    ld hl, #str_menu_new
    ld b, #60
    call _menu_draw_text
    ld hl, #str_menu_cont
    ld b, #80
    call _menu_draw_text
    ld hl, #str_menu_exit
    ld b, #100
    call _menu_draw_text
    ;; Draw selection indicator
    ld a, (menu_selection)
    sla a
    sla a
    sla a
    sla a
    sla a
    add a, #56
    ld b, a
    ld c, #4
    ld hl, #_menu_cursor_str
    call fwk_video_get_ptr
    ;; Draw ">" cursor
    ld (hl), #'>'
    ret

_mu_level_select:
    ;; Handle input for level selection
    ld a, (fwk_input_pressed)
    bit 0, a            ; UP pressed
    jr z, _mu_ls_down
    ;; Move up within current difficulty
    ld a, (level_select_item)
    or a
    jr z, _mu_ls_diff_up
    dec a
    ld (level_select_item), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx
    jp _mu_ls_draw

_mu_ls_diff_up:
    ;; Move to previous difficulty
    ld a, (level_select_diff)
    or a
    jp z, _mu_ls_draw
    dec a
    ld (level_select_diff), a
    ld a, #39
    ld (level_select_item), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx
    jp _mu_ls_draw

_mu_ls_down:
    ld a, (fwk_input_pressed)
    bit 1, a            ; DOWN pressed
    jr z, _mu_ls_left
    ld a, (level_select_item)
    cp #39
    jr z, _mu_ls_diff_down
    inc a
    ld (level_select_item), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx
    jr _mu_ls_draw

_mu_ls_diff_down:
    ;; Move to next difficulty
    ld a, (level_select_diff)
    cp #4
    jr z, _mu_ls_draw
    inc a
    ld (level_select_diff), a
    xor a
    ld (level_select_item), a
    ld a, #SFX_NAV
    ld b, #10
    ld c, #1
    call fwk_audio_play_sfx
    jr _mu_ls_draw

_mu_ls_left:
    ld a, (fwk_input_pressed)
    bit 2, a            ; LEFT pressed
    jr z, _mu_ls_right
    ;; Go back to main menu
    xor a
    ld (menu_state), a
    jr _mu_ls_draw

_mu_ls_right:
    ld a, (fwk_input_pressed)
    bit 3, a            ; RIGHT pressed
    jr z, _mu_ls_enter
    ;; (no action on right for now)
    jr _mu_ls_draw

_mu_ls_enter:
    ld a, (fwk_input_pressed)
    bit 4, a            ; CAT (ENTER) pressed
    jr z, _mu_ls_draw
    ;; Calculate level_id = diff * 40 + item
    ld a, (level_select_diff)
    ;; multiply by 40
    ld b, a
    ld a, #0
    or b
    jr z, _mu_ls_no_mul
    ld c, #40
_mu_ls_mul:
    add a, c
    djnz _mu_ls_mul
_mu_ls_no_mul:
    ld b, a
    ld a, (level_select_item)
    add a, b
    ;; A = level_id
    ld (current_level_id), a
    ;; Reset timer
    xor a
    ld (game_timer_start), a
    ld (game_timer_start + 1), a
    ld (game_timer_seconds), a
    ld (game_timer_seconds + 1), a
    ld (game_won), a
    call board_load_level
    ld a, #STATE_GAME
    ld (game_state), a

_mu_ls_draw:
    ;; Clear screen
    xor a
    call fwk_video_clear_visible
    ;; Draw difficulty title
    ld hl, #str_menu_diff
    ld b, #20
    call _menu_draw_text
    ;; Draw level grid (8 columns x 5 rows)
    ;; For each of 40 levels, draw [ ] or [X]
    ld hl, #catdoku_save_buffer
    ld a, (level_select_diff)
    ;; base level = diff * 40
    ld b, a
    ld a, #0
    or b
    jr z, _mu_ls_base_done
    ld c, #40
_mu_ls_base_mul:
    add a, c
    djnz _mu_ls_base_mul
_mu_ls_base_done:
    ld (catdoku_temp_val), a   ; base level id
    ld c, #0                   ; item index 0..39
_mu_ls_draw_loop:
    ld a, c
    cp #40
    jr z, _mu_ls_draw_done
    ;; Calculate level_id = base + c
    ld a, (catdoku_temp_val)
    add a, c
    ;; Check if completed
    push bc
    call save_is_completed
    pop bc
    or a
    jr z, _mu_ls_pending
    ;; Draw [X]
    ld hl, #str_menu_completed
    jr _mu_ls_draw_item
_mu_ls_pending:
    ;; Draw [ ]
    ld hl, #str_menu_pending
_mu_ls_draw_item:
    ;; Position: row = c / 8, col = c % 8
    ;; For simplicity, draw at fixed positions
    push bc
    ld a, c
    and #7
    sla a
    sla a
    sla a
    sla a
    sla a
    add a, #4
    ld d, a
    ld a, c
    srl a
    srl a
    srl a
    sla a
    sla a
    sla a
    sla a
    add a, #40
    ld b, a
    ld c, d
    call fwk_video_get_ptr
    pop bc
    ;; Draw the string
    push iy
    push hl
    pop iy
    ;; Actually we need to use fwk_text_draw
    pop iy
    inc c
    jr _mu_ls_draw_loop
_mu_ls_draw_done:
    ;; Draw time for selected level at bottom
    ld a, (level_select_diff)
    ld b, a
    ld a, #0
    or b
    jr z, _mu_ls_no_mul_time
    ld c, #40
_mu_ls_time_mul:
    add a, c
    djnz _mu_ls_time_mul
_mu_ls_no_mul_time:
    ld b, a
    ld a, (level_select_item)
    add a, b
    ;; A = level_id
    call save_get_time
    ;; HL = time in seconds
    ;; Display at bottom of screen
    push hl
    ld hl, #_str_time_label
    ld b, #190
    call _menu_draw_text
    pop hl
    ;; Draw time value (seconds) using small digits
    push hl
    ld b, #190
    ld c, #80
    call fwk_video_get_ptr
    pop hl
    ld a, l
    call fwk_text_draw_small_u8

    ;; Draw cursor at current item
    ld a, (level_select_item)
    and #7
    sla a
    sla a
    sla a
    sla a
    sla a
    add a, #4
    ld c, a
    ld a, (level_select_item)
    srl a
    srl a
    srl a
    sla a
    sla a
    sla a
    sla a
    add a, #40
    ld b, a
    ;; Draw ">"
    ld (hl), #'>'
    ret

_menu_draw_text:
    ;; In: HL = string ptr, B = scanline Y
    ;; Out: none
    push hl
    ld l, b
    ld h, #0
    ld c, #4
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_str_time_label:: .asciz "TIEMPO:"
_menu_cursor_str:
    .asciz ">"