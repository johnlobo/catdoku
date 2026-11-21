;; main.s - Entry point for Catdoku

.module game_main
.globl game_timer_seconds
.globl _main, game_state
.include "common.inc"
.include "generated/project.inc"

.area _DATA
game_status:: .db 0              ; 0x5A once running, else error code
catdoku_game_palette::
    ;; The 13 colours of the design (assets/palette.json, PEN_* in common.inc),
    ;; pens 13..15 unused.
    .db 0x14, 0x04, 0x00, 0x06, 0x0A, 0x0F, 0x1C, 0x0E, 0x1E, 0x02, 0x1B, 0x0C, 0x0B, 0x18, 0x1A, 0x03

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
    ld a, #UI_BG_PLAIN
    call ui_show_background
    ld iy, #str_game_victory      ; "LEVEL COMPLETE!" in a title box
    ld c, #70
    call menu_title_box
    ld iy, #str_game_time         ; "TIME:" yellow, the seconds white
    ld b, #MV_TIME_X
    ld c, #105
    ld a, #PEN_YELLOW
    call ui_text
    ld hl, (game_timer_seconds)
    ld c, #105
    ld a, #PEN_WHITE
    call game_draw_number_at
    ld iy, #str_press_key
    call ui_help_centred
_mv_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    jp _main_to_level_select

main_timeup:
    ld a, (game_dirty)
    or a
    jr z, _mt_wait
    xor a
    ld (game_dirty), a
    ld a, #UI_BG_PLAIN
    call ui_show_background
    ld iy, #str_timeup            ; "TIME UP" in a title box
    ld c, #80
    call menu_title_box
    ld iy, #str_press_key
    call ui_help_centred
_mt_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    jp _main_to_level_select

main_lost:
    ;; A box over the board, drawn once, then back to level select
    ld a, (game_dirty)
    or a
    jr z, _ml_wait
    xor a
    ld (game_dirty), a
    ld b, #ML_BOX_X
    ld c, #ML_BOX_Y
    ld d, #ML_BOX_W
    ld e, #ML_BOX_H
    ld h, #PEN_ORANGE
    ld l, #PEN_DARK_RED
    call ui_box
    ld iy, #str_lost_1
    ld b, #ML_BOX_X
    ld d, #ML_BOX_W
    ld c, #ML_BOX_Y + 6
    ld a, #PEN_YELLOW
    call ui_text_in
    ld iy, #str_lost_2
    ld b, #ML_BOX_X
    ld d, #ML_BOX_W
    ld c, #ML_BOX_Y + 16
    ld a, #PEN_WHITE
    call ui_text_in
    ld iy, #str_press_key
    ld b, #ML_BOX_X
    ld d, #ML_BOX_W
    ld c, #ML_BOX_Y + 26
    ld a, #PEN_WHITE
    call ui_text_in
_ml_wait:
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
_main_to_level_select:
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    ld a, #1
    ld (menu_dirty), a
    jp main_loop

MV_TIME_X = 62                    ; "TIME:999": 32 pixels, (160 - 32) / 2 - 2
ML_BOX_X = 36                     ; game over box over the board
ML_BOX_Y = 80
ML_BOX_W = 88
ML_BOX_H = 39
str_lost_1: .asciz "NO CAT THERE"
str_lost_2: .asciz "GAME OVER"
str_press_key: .asciz "PRESS ANY KEY"

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
