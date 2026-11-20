;; main.s - Entry point for Catdoku

.module game_main
.globl game_timer_seconds
.globl _main, game_state
.include "common.inc"
.include "generated/project.inc"

.area _DATA
game_status:: .db 0              ; 0x5A once running, else error code
catdoku_game_palette::
    ;; pen 1 = firmware 8 (bright magenta, HW 0x0D) as in assets/palette.json;
    ;; it was 0x0A, the same bright yellow as pen 6, so regions 0 and 5 matched.
    .db 0x14, 0x0D, 0x00, 0x1C, 0x0C, 0x0E, 0x0A, 0x07, 0x16, 0x1E, 0x13, 0x1F, 0x15, 0x18, 0x04, 0x0B
_game_palette:
    .db 0x14, 0x0D, 0x00, 0x1C, 0x0C, 0x0E, 0x0A, 0x07, 0x16, 0x1E, 0x13, 0x1F, 0x15, 0x18, 0x04, 0x0B

.area _CODE

;; ----------------------------------------------------------------------------
;; _main
;;   Entry point (0x0200). Initializes framework, audio, palette, save.
;;   Enters state machine loop.
;; ----------------------------------------------------------------------------
_main::
    ;; Initialize disk first (before system init disables firmware); it also
    ;; keeps the firmware interrupt that fwk_disk_save needs later
    call fwk_disk_init

    ;; Load save file while firmware is still available (creates if missing)
    call save_load

    ;; Initialize project (disables firmware and installs IRQ handler)
    call fwk_project_init
    call fwk_video_init
    call fwk_text_init
    ld a, #0
    call fwk_text_set_color

    ;; Install fixed palette
    ld hl, #catdoku_game_palette
    ld de, #16
    call cpct_setPalette_asm

    ;; Clear screen
    xor a
    call fwk_video_clear_visible

    ;; Initialize input
    call fwk_input_init

    ;; Set up keyboard bindings
    ld hl, #catdoku_bindings
    call fwk_input_set_bindings

    ;; Initialize audio
    ;; Music: use AKG song from examples/audio
    ld hl, #audio_songStart
    ld a, #0
    call fwk_audio_init_music
    ld hl, #audio_sfxSoundEffects
    call fwk_audio_init_sfx
    call fwk_audio_start

    ;; Set initial state to MENU
    xor a
    ld (game_state), a

    ;; Mark as running
    ld a, #0x5A
    ld (game_status), a

;; ----------------------------------------------------------------------------
;; Main loop - dispatch by game_state
;; ----------------------------------------------------------------------------
main_loop:
    call fwk_system_wait_frame
    call fwk_input_update

    ld a, (game_state)
    cp #STATE_MENU
    jr z, main_menu
    cp #STATE_LEVEL_SELECT
    jr z, main_level_select
    cp #STATE_GAME
    jr z, main_game
    cp #STATE_VICTORY
    jr z, main_victory
    cp #STATE_TIMEUP
    jr z, main_timeup
    cp #STATE_LOST
    jp z, main_lost               ; too far for jr
    cp #STATE_RULES
    jp z, main_rules
    cp #STATE_CONFIRM_NEW
    jp z, main_confirm_new
    jr main_loop

main_menu:
    call menu_update
    jr main_loop

main_level_select:
    call level_select_update
    jr main_loop

main_rules:
    call rules_update
    jp main_loop

main_confirm_new:
    call confirm_new_update
    jp main_loop

main_game:
    call game_update
    jr main_loop

main_victory:
    ;; Drawn once (game_dirty is set by the win), then wait for a key
    ld a, (game_dirty)
    or a
    jr z, _mv_wait
    xor a
    ld (game_dirty), a
    call fwk_video_clear_visible
    ld hl, #str_game_victory      ; "LEVEL COMPLETE!" centred
    ld b, #70
    ld c, #25
    call _main_draw_text_at
    ld hl, #str_game_time         ; "TIME:" then the seconds
    ld b, #100
    ld c, #30
    call _main_draw_text_at
    ld hl, (game_timer_seconds)
    ld b, #100
    ld c, #42
    call game_draw_number_at
    ld hl, #str_press_key
    ld b, #150
    ld c, #27
    call _main_draw_text_at
_mv_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    jp main_loop

main_timeup:
    ld a, (game_dirty)
    or a
    jr z, _mt_wait
    xor a
    ld (game_dirty), a
    call fwk_video_clear_visible
    ld hl, #str_timeup            ; "TIME UP" centred
    ld b, #80
    ld c, #33
    call _main_draw_text_at
    ld hl, #str_press_key
    ld b, #150
    ld c, #27
    call _main_draw_text_at
_mt_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    jp main_loop

main_lost:
    ;; Framework window over the board, drawn once, then back to level select
    ld a, (game_dirty)
    or a
    jr z, _ml_wait
    xor a
    ld (game_dirty), a
    ld ix, #lost_window
    call fwk_window_draw
    ld hl, #str_lost_1            ; 12 chars: column 40 - 12
    ld b, #86
    ld c, #28
    call _main_draw_text_at
    ld hl, #str_lost_2            ; 9 chars
    ld b, #98
    ld c, #31
    call _main_draw_text_at
    ld hl, #str_press_key         ; 13 chars
    ld b, #110
    ld c, #27
    call _main_draw_text_at
_ml_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    jp main_loop

;; fwk_window descriptor (x, y.w, width, height, border, fill): bytes 20..59,
;; lines 80..119, over the board. Red border (pen 4), dark blue fill (pen 14).
lost_window: .db 20
    .dw 80
    .db 40, 40, 0x30, 0x3F
str_lost_1: .asciz "NO CAT THERE"
str_lost_2: .asciz "GAME OVER"
str_press_key: .asciz "PRESS ANY KEY"

_main_draw_text:
    push hl
    ld l, b
    ld h, #0
    ld c, #4
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_main_draw_text_at:
    push hl
    ld l, b
    ld h, #0
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

;; ---- Keyboard bindings table ----
catdoku_bindings:
    .dw Key_CursorUp
    .db INPUT_UP
    .dw Key_CursorDown
    .db INPUT_DOWN
    .dw Key_CursorLeft
    .db INPUT_LEFT
    .dw Key_CursorRight
    .db INPUT_RIGHT
    .dw Key_Return
    .db INPUT_CAT
    .dw Key_Space
    .db INPUT_MARK
    .dw Key_H
    .db INPUT_HINT
    .dw Key_Esc
    .db INPUT_BACK
    .dw 0
    .db 0

;; ---- Strings ----
