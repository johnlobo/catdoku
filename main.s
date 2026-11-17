;; main.s - Entry point for Catdoku

.module game_main
.globl game_timer_seconds
.globl _main, game_state
.include "common.inc"
.include "generated/project.inc"

.area _DATA
game_status:: .db 0              ; 0x5A once running, else error code
_orig_palette:
    .db 0x14, 0x0A, 0x00, 0x1C, 0x0C, 0x0E, 0x0A, 0x07, 0x16, 0x1E, 0x13, 0x1F, 0x15, 0x18, 0x04, 0x0B
_game_palette:
    .db 0x14, 0x0A, 0x00, 0x1C, 0x0C, 0x0E, 0x0A, 0x07, 0x16, 0x1E, 0x13, 0x1F, 0x15, 0x18, 0x04, 0x0B

.area _CODE

;; ----------------------------------------------------------------------------
;; _main
;;   Entry point (0x0200). Initializes framework, audio, palette, save.
;;   Enters state machine loop.
;; ----------------------------------------------------------------------------
_main::
    ;; Initialize disk first (before system init disables firmware)
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
    ld hl, #_orig_palette
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
    jr main_loop

main_menu:
    call menu_update
    jr main_loop

main_level_select:
    call menu_update
    jr main_loop

main_game:
    call game_update
    jr main_loop

main_victory:
    ;; Draw victory screen
    xor a
    call fwk_video_clear_visible
    ld hl, #str_game_victory
    ld b, #60
    call _main_draw_text
    ;; Draw time label
    ld hl, #str_game_time
    ld b, #90
    call _main_draw_text
    ;; Draw time value
    ld hl, #game_timer_seconds
    ld a, (hl)
    ld l, a
    ld h, #0
    ;; Draw at position
    ld b, #90
    ld c, #80
    call fwk_video_get_ptr
    ld a, (game_timer_seconds)
    call fwk_text_draw_small_u8
    ;; Wait for key
    ld a, (fwk_input_pressed)
    or a
    jr z, main_loop
    ;; Go back to level select
    ld a, #STATE_LEVEL_SELECT
    ld (game_state), a
    jr main_loop

main_timeup:
    ;; Draw time-up modal
    xor a
    call fwk_video_clear_visible
    ld hl, #str_timeup
    push hl
    ld l, #80
    ld h, #0
    ld c, #28
    call fwk_video_get_ptr
    pop iy
    call fwk_text_draw
    ;; Wait for key
    ld a, (fwk_input_pressed)
    or a
    jp z, main_loop
    ;; Return to menu
    ld a, #1
    ld (menu_dirty), a
    ld a, #STATE_MENU
    ld (game_state), a
    jp main_loop

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
