;; save.s - Save/load progress for Catdoku
;; Uses fwk_disk_init + fwk_disk_load for reading, AMSDOS CAS OUT for writing

.module game_save
.globl catdoku_save_buffer, catdoku_save_count, catdoku_save_loaded
.globl save_load, save_is_completed, save_write, save_get_time, save_modal_show, save_modal_hide
.include "common.inc"

;; ---- Data area ----
.area _DATA

catdoku_save_buffer:: .ds 256     ; save file buffer (max 256 bytes)
catdoku_save_count:: .db 0        ; number of completed levels in buffer
catdoku_save_loaded:: .db 0       ; 1 if save was loaded successfully
catdoku_save_filename:: .asciz "CATDOKU.SAV"
catdoku_save_filename_len = 11

;; AMSDOS header buffer (2KB for file header)
catdoku_amsdos_header:: .ds 2048

;; Modal state
save_modal_active:: .db 0
save_modal_bg:: .ds 256           ; background capture buffer

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; save_load
;;   In: none
;;   Out: none
;;   Modifies: catdoku_save_buffer, catdoku_save_count, catdoku_save_loaded
;;   Reads CATDOKU.SAV if it exists. If not, creates an empty save.
;; ----------------------------------------------------------------------------
save_load::
    ;; Try to load the save file
    ld hl, #catdoku_save_filename
    ld b, #catdoku_save_filename_len
    ld de, #catdoku_save_buffer
    call fwk_disk_load
    jr nc, _sl_not_found
    ;; File found - parse it
    ;; Check header "CATDOKU"
    ld hl, #catdoku_save_buffer
    ld a, (hl)
    cp #'C'
    jr nz, _sl_not_found
    inc hl
    ld a, (hl)
    cp #'A'
    jr nz, _sl_not_found
    ;; Header OK - count entries
    ld hl, #catdoku_save_buffer + 8   ; after "CATDOKU" + version
    ld de, #catdoku_save_buffer + 256  ; end of buffer
    ld c, #0
_sl_count_loop:
    ld a, l
    cp e
    jr z, _sl_count_done
    ld a, (hl)
    cp #0xFF
    jr z, _sl_count_done
    inc c
    ld a, l
    add a, #5
    ld l, a
    jr nc, _sl_count_loop
    inc h
    jr _sl_count_loop
_sl_count_done:
    ld a, c
    ld (catdoku_save_count), a
    ld a, #1
    ld (catdoku_save_loaded), a
    ret

_sl_not_found:
    ;; Create empty save file
    ld hl, #catdoku_save_buffer
    ld a, #'C'
    ld (hl), a
    inc hl
    ld a, #'A'
    ld (hl), a
    inc hl
    ld a, #'T'
    ld (hl), a
    inc hl
    ld a, #'D'
    ld (hl), a
    inc hl
    ld a, #'O'
    ld (hl), a
    inc hl
    ld a, #'K'
    ld (hl), a
    inc hl
    ld a, #'U'
    ld (hl), a
    inc hl
    ld a, #1              ; version
    ld (hl), a
    ;; Fill rest with 0xFF
    inc hl
    ld b, #256 - 8
_sl_fill:
    ld (hl), #0xFF
    inc hl
    djnz _sl_fill
    xor a
    ld (catdoku_save_count), a
    ld a, #1
    ld (catdoku_save_loaded), a
    ret

;; ----------------------------------------------------------------------------
;; save_is_completed
;;   In: A = level_id
;;   Out: A = 1 if completed, 0 otherwise
;;   Modifies: AF, HL, BC
;; ----------------------------------------------------------------------------
save_is_completed::
    ld b, a
    ld hl, #catdoku_save_buffer + 8   ; first entry
    ld a, (catdoku_save_count)
    ld c, a
_sl_check_loop:
    ld a, c
    or a
    jr z, _sl_not_completed
    ld a, (hl)
    cp b
    jr z, _sl_completed
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    dec c
    jr _sl_check_loop
_sl_completed:
    ld a, #1
    ret
_sl_not_completed:
    xor a
    ret

;; ----------------------------------------------------------------------------
;; save_get_time
;;   In: A = level_id
;;   Out: HL = time in seconds (0 if not completed)
;;   Modifies: AF, BC, DE, HL
;; ----------------------------------------------------------------------------
save_get_time::
    ld b, a
    ld hl, #catdoku_save_buffer + 8   ; first entry
    ld a, (catdoku_save_count)
    ld c, a
_sgt_loop:
    ld a, c
    or a
    jr z, _sgt_not_found
    ld a, (hl)
    cp b
    jr z, _sgt_found
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    dec c
    jr _sgt_loop
_sgt_found:
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ;; DE = time (16-bit), return in HL
    ex de, hl
    ret
_sgt_not_found:
    ld hl, #0
    ret

;; ----------------------------------------------------------------------------
;; save_write
;;   In: A = level_id, DE:HL = time_seconds (32-bit)
;;       Actually: time in HL (16-bit seconds) for simplicity
;;   Out: none
;;   Modifies: save buffer, writes to disk
;;   Adds or updates an entry for this level
;; ----------------------------------------------------------------------------
save_write::
    push af
    push de
    push hl
    ;; Show modal "GUARDANDO..."
    call save_modal_show
    ;; Check if level already exists
    pop hl
    pop de
    pop af
    push af
    push de
    push hl
    ld b, a
    ld hl, #catdoku_save_buffer + 8
    ld a, (catdoku_save_count)
    ld c, a
_sw_find_loop:
    ld a, c
    or a
    jr z, _sw_add_new
    ld a, (hl)
    cp b
    jr z, _sw_update
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    dec c
    jr _sw_find_loop

_sw_update:
    ;; Update time at HL+1..HL+4
    pop de              ; time low
    pop af              ; level_id (discard)
    push af
    push de
    inc hl
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld (hl), #0
    inc hl
    ld (hl), #0
    jr _sw_write

_sw_add_new:
    ;; Add new entry at end
    pop de              ; time
    pop af              ; level_id
    push af
    push de
    ld hl, #catdoku_save_buffer + 8
    ld a, (catdoku_save_count)
    ;; offset = count * 5
    ld b, a
    ld c, #5
    ld a, b
    or a
    jr z, _sw_no_offset
_sw_mul:
    add hl, bc
    djnz _sw_mul
_sw_no_offset:
    ;; HL = pointer to new entry
    pop de              ; time
    pop af              ; level_id
    push af
    push de
    ld (hl), a          ; level_id
    inc hl
    ld (hl), e          ; time low
    inc hl
    ld (hl), d          ; time high
    inc hl
    ld (hl), #0
    inc hl
    ld (hl), #0
    ;; Increment count
    ld a, (catdoku_save_count)
    inc a
    ld (catdoku_save_count), a

_sw_write:
    ;; Persisting to DSK requires firmware, which is disabled after boot.
    ;; Keep progress in memory only to avoid hanging in CAS OUT routines.
    ;; Hide modal
    call save_modal_hide
    pop hl
    pop de
    pop af
    ret

_sw_write_disk:
    ;; CAS OUT OPEN (0xBC8C)
    ;; HL = filename, B = length, DE = header buffer, C = file type (0 = binary)
    ld hl, #catdoku_save_filename
    ld b, #catdoku_save_filename_len
    ld de, #catdoku_amsdos_header
    ld c, #0              ; binary file
    call 0xBC8C            ; CAS OUT OPEN
    jr nc, _sw_write_fail
    ;; CAS OUT DIRECT (0xBC98)
    ;; HL = buffer address, DE = size to write, BC = logical file size
    ld hl, #catdoku_save_buffer
    ld de, #256            ; size to write
    ld bc, #256            ; logical file size
    call 0xBC98            ; CAS OUT DIRECT
    ;; CAS OUT CLOSE (0xBC8F)
    call 0xBC8F            ; CAS OUT CLOSE
    ret
_sw_write_fail:
    ;; Write failed - just return
    ret

;; ----------------------------------------------------------------------------
;; save_modal_show
;;   In: none
;;   Out: none
;;   Modifies: screen (draws modal "GUARDANDO...")
;;   Captures background and draws a modal window
;; ----------------------------------------------------------------------------
save_modal_show::
    ld a, #1
    ld (save_modal_active), a
    ;; Capture background at center of screen
    ld hl, #save_modal_bg
    ld b, #80              ; x
    ld c, #80              ; y
    ld d, #16              ; width
    ld e, #8               ; height
    call fwk_window_capture
    ;; Draw window
    ld hl, #save_modal_bg
    ld b, #80
    ld c, #80
    ld d, #16
    ld e, #8
    call fwk_window_draw
    ;; Draw "GUARDANDO..." text
    ld hl, #_str_saving
    ld b, #90
    call _save_draw_text
    ret

;; ----------------------------------------------------------------------------
;; save_modal_hide
;;   In: none
;;   Out: none
;;   Modifies: screen (restores background)
;; ----------------------------------------------------------------------------
save_modal_hide::
    xor a
    ld (save_modal_active), a
    ;; Restore background
    ld hl, #save_modal_bg
    ld b, #80
    ld c, #80
    ld d, #16
    ld e, #8
    call fwk_window_restore
    ret

_save_draw_text:
    push hl
    ld l, b
    ld h, #0
    ld c, #84
    call fwk_video_get_ptr
    pop iy
    jp fwk_text_draw

_str_saving:: .asciz "GUARDANDO..."