;; save.s - Save/load progress for Catdoku
;; Reads CATDOKU.SAV at boot (fwk_disk_load); progress is kept in memory

.module game_save
.globl catdoku_save_buffer, catdoku_save_count, catdoku_save_loaded
.globl save_load, save_is_completed, save_write, save_get_time
.include "common.inc"

;; ---- Data area ----
.area _DATA

;; "CATDOKU" + version, then one 5-byte entry per completed level:
;; level id, time low, time high, 0, 0. 0xFF ends the list.
SAVE_HEADER_SIZE = 8
SAVE_ENTRY_SIZE = 5
SAVE_BUFFER_SIZE = SAVE_HEADER_SIZE + CATDOKU_NUM_LEVELS * SAVE_ENTRY_SIZE

catdoku_save_buffer:: .ds SAVE_BUFFER_SIZE
catdoku_save_count:: .db 0        ; number of completed levels in buffer
catdoku_save_loaded:: .db 0       ; 1 once save_load ran
catdoku_save_filename:: .asciz "CATDOKU.SAV"
catdoku_save_filename_len = 11
sw_level: .db 0
sw_time: .dw 0

;; "SAVING..." message: framework window over the board (bytes 24..55, lines
;; 88..111), yellow border (pen 6), dark blue fill (pen 14). The background is
;; captured first and put back afterwards.
SAVE_MSG_WIDTH = 32
SAVE_MSG_HEIGHT = 24
SAVE_MSG_FRAMES = 50              ; 1 s on screen so it can be read
save_msg_window: .db 24
    .dw 88
    .db SAVE_MSG_WIDTH, SAVE_MSG_HEIGHT, 0x3C, 0x3F
save_msg_background: .ds SAVE_MSG_WIDTH * SAVE_MSG_HEIGHT

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; save_load
;;   Reads CATDOKU.SAV if the disc has one, else starts an empty save.
;;   Called once at boot, while the firmware is still on.
;;   Modifies: AF, BC, DE, HL, catdoku_save_*.
;; ----------------------------------------------------------------------------
save_load::
    ;; Whole buffer to 0xFF first, so a short file still ends with the marker
    ld hl, #catdoku_save_buffer
    ld (hl), #0xFF
    ld de, #catdoku_save_buffer + 1
    ld bc, #SAVE_BUFFER_SIZE - 1
    ldir
    ld hl, #catdoku_save_filename
    ld b, #catdoku_save_filename_len
    ld de, #catdoku_save_buffer
    call fwk_disk_load
    jr nc, _sl_empty
    ld a, (catdoku_save_buffer)
    cp #'C'
    jr nz, _sl_empty
    ld a, (catdoku_save_buffer + 1)
    cp #'A'
    jr nz, _sl_empty
    ;; Count entries up to the 0xFF marker
    ld hl, #catdoku_save_buffer + SAVE_HEADER_SIZE
    ld de, #SAVE_ENTRY_SIZE
    ld c, #0
_sl_count:
    ld a, (hl)
    cp #0xFF
    jr z, _sl_counted
    ld a, c
    cp #CATDOKU_NUM_LEVELS
    jr z, _sl_counted
    inc c
    add hl, de
    jr _sl_count
_sl_counted:
    ld a, c
    jr _sl_done

_sl_empty:
    ld hl, #catdoku_save_buffer
    ld (hl), #0xFF
    ld de, #catdoku_save_buffer + 1
    ld bc, #SAVE_BUFFER_SIZE - 1
    ldir
    ld hl, #_save_magic
    ld de, #catdoku_save_buffer
    ld bc, #SAVE_HEADER_SIZE
    ldir
    xor a
_sl_done:
    ld (catdoku_save_count), a
    ld a, #1
    ld (catdoku_save_loaded), a
    ret

_save_magic: .ascii "CATDOKU"
    .db 1                         ; version

;; ----------------------------------------------------------------------------
;; _save_find
;;   In: A = level id.
;;   Out: Z and HL = its entry when found; NZ and HL = first free entry.
;;   Modifies: AF, BC, HL.
;; ----------------------------------------------------------------------------
_save_find:
    ld b, a
    ld hl, #catdoku_save_buffer + SAVE_HEADER_SIZE
    ld a, (catdoku_save_count)
    ld c, a
_sf_loop:
    ld a, c
    or a
    jr z, _sf_missing
    ld a, (hl)
    cp b
    ret z
    push de
    ld de, #SAVE_ENTRY_SIZE
    add hl, de
    pop de
    dec c
    jr _sf_loop
_sf_missing:
    inc a                         ; A = 1: NZ
    ret

;; ----------------------------------------------------------------------------
;; save_is_completed
;;   In: A = level id. Out: A = 1 if completed, 0 otherwise.
;;   Modifies: AF, BC, HL.
;; ----------------------------------------------------------------------------
save_is_completed::
    call _save_find
    ld a, #1
    ret z
    xor a
    ret

;; ----------------------------------------------------------------------------
;; save_get_time
;;   In: A = level id. Out: HL = best time in seconds, 0 if not completed.
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
save_get_time::
    call _save_find
    jr nz, _sgt_none
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    ret
_sgt_none:
    ld hl, #0
    ret

;; ----------------------------------------------------------------------------
;; _save_message_show / _save_message_hide
;;   Window with "SAVING..." and its background capture.
;;   Modify: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
_save_message_show:
    ld ix, #save_msg_window
    ld de, #save_msg_background
    call fwk_window_capture
    ld ix, #save_msg_window
    call fwk_window_draw
    ld hl, #_str_saving           ; 6 characters, centred: 40 - 6
    push hl
    ld hl, #96
    ld c, #34
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_save_message_hide:
    ;; Count frames with the interrupt-driven counter: cpct_waitVSYNC returns at
    ;; once while the VSYNC pulse is still active, so calling it in a loop does
    ;; not wait one frame per call.
    ld de, (fwk_system_frame_count)
_smh_wait:
    ld hl, (fwk_system_frame_count)
    or a
    sbc hl, de
    ld a, l
    cp #SAVE_MSG_FRAMES
    jr c, _smh_wait
    ld ix, #save_msg_window
    ld hl, #save_msg_background
    jp fwk_window_restore

_str_saving: .asciz "SAVING"     ; the big font has no "."

;; ----------------------------------------------------------------------------
;; save_write
;;   In: A = level id, HL = time in seconds.
;;   Adds the level, or keeps the lower of the stored and the new time.
;;   In memory only: writing the disc needs the firmware, which is off while
;;   the game runs, so progress lasts until the machine is reset.
;;   Shows the "SAVING..." window for SAVE_MSG_FRAMES frames.
;;   Modifies: AF, BC, DE, HL, IX, IY.
;; ----------------------------------------------------------------------------
save_write::
    ld (sw_level), a
    ld (sw_time), hl
    call _save_message_show
    call _save_store
    jp _save_message_hide

_save_store:
    ld a, (sw_level)
    call _save_find
    jr nz, _sw_new
    inc hl                        ; existing: keep the best time
    ld e, (hl)
    inc hl
    ld d, (hl)                    ; DE = stored time, HL -> high byte
    push hl
    ld hl, (sw_time)
    or a
    sbc hl, de                    ; carry when new < stored
    pop hl
    ret nc
    ld de, (sw_time)
    ld (hl), d
    dec hl
    ld (hl), e
    ret
_sw_new:
    ld a, (catdoku_save_count)
    cp #CATDOKU_NUM_LEVELS
    ret nc
    ld a, (sw_level)
    ld (hl), a
    inc hl
    ld de, (sw_time)
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld (hl), #0
    inc hl
    ld (hl), #0
    ld hl, #catdoku_save_count
    inc (hl)
    ret
