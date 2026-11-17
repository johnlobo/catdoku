;; board.s - Core board logic for Catdoku
;; All board-related operations live here.

.module game_board
.globl board_load_level, board_get_cell, board_set_cell, board_check_win, board_get_hint
.globl catdoku_n, catdoku_num_colours, catdoku_num_cats, catdoku_found_cnt
.globl catdoku_grid, catdoku_cats, catdoku_found, catdoku_marks
.globl catdoku_temp_row, catdoku_temp_col, catdoku_temp_val
.include "common.inc"

;; ---- Data area ----
.area _DATA

;; Board state (mutable, one level at a time)
catdoku_n::         .db 0          ; board size n (5..9)
catdoku_num_colours:: .db 0        ; number of colours/regions
catdoku_num_cats::  .db 0          ; number of cats = n
catdoku_found_cnt:: .db 0          ; cats found so far

catdoku_grid::      .ds 81         ; n*n bytes: region index per cell
catdoku_cats::      .ds 18         ; num_cats * 2: (row, col) pairs (solution)
catdoku_found::     .ds 13         ; bitmask: 1 = found, 0 = not found (max 104 bits)
catdoku_marks::     .ds 81         ; 0=empty, 1=cat, 2=mark (X)

;; Decompression buffer

;; Level table (filled by generated/catdoku_levels.s)

;; Scratch
catdoku_temp_row:: .db 0
catdoku_temp_col:: .db 0
catdoku_temp_val:: .db 0

;; ---- Code area ----
.area _CODE

;; ----------------------------------------------------------------------------
;; board_load_level
;;   In: A = level_id (0..199)
;;   Out: none
;;   Modifies: everything
;;   Loads and decompresses a level, extracts grid + cats, resets found state
;; ----------------------------------------------------------------------------
board_load_level::
    push af
    ;; Calculate table offset: level_id * 6
    ld l, a
    ld h, #0
    add hl, hl           ; *2
    ld d, h
    ld e, l
    add hl, hl           ; *4
    add hl, de           ; *6
    ld de, #catdoku_level_table
    add hl, de           ; HL = pointer to entry
    ;; Read entry: offset(2), packed_size(2), unpacked_size(2)
    ld e, (hl)
    inc hl
    ld d, (hl)           ; DE = offset
    inc hl
    ld a, (hl)
    inc hl
    ld (catdoku_temp_val), a       ; packed_size low
    ld a, (hl)
    inc hl
    ld (catdoku_temp_val + 1), a   ; packed_size high
    ld a, (hl)
    inc hl
    ld (catdoku_temp_val + 2), a   ; unpacked_size low
    ld a, (hl)
    ld (catdoku_temp_val + 3), a   ; unpacked_size high

    ;; HL = catdoku_levels_packed + offset
    push de
    ld hl, #catdoku_levels_packed
    pop de
    add hl, de
    ;; HL = packed start; compute packed end = start + packed_size - 1
    ld a, (catdoku_temp_val)
    ld e, a
    ld a, (catdoku_temp_val + 1)
    ld d, a
    ;; DE = packed_size
    add hl, de
    dec hl
    ;; HL = packed end (source end for zx7b)
    push hl
    ;; DE (dest end) = decomp_buffer + unpacked_size - 1
    ld a, (catdoku_temp_val + 2)
    ld e, a
    ld a, (catdoku_temp_val + 3)
    ld d, a
    ;; DE = unpacked_size
    ld hl, #catdoku_decomp_buffer
    add hl, de
    dec hl
    ;; HL = dest end
    ex de, hl
    pop hl
    ;; HL = source end, DE = dest end
    call fwk_zx7b_unpack

    ;; Now extract from decomp buffer
    ld hl, #catdoku_decomp_buffer
    ;; Header: level_id(1), difficulty(1), n(1), num_colours(1), num_cats(1), checksum(1)
    inc hl                ; skip level_id
    inc hl                ; skip difficulty
    ld a, (hl)
    ld (catdoku_n), a
    inc hl
    ld a, (hl)
    ld (catdoku_num_colours), a
    inc hl
    ld a, (hl)
    ld (catdoku_num_cats), a
    inc hl
    inc hl                ; skip checksum

    ;; Extract grid: n*n bytes
    ld de, #catdoku_grid
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; BC = n*n (approx, multiply)
    ;; Simple: copy n*n bytes
    ld a, (catdoku_n)
    ld e, a
    ld d, #0
    ;; DE = n
    push hl
    ld hl, #0
    ld a, (catdoku_n)
    ld l, a
    ld h, #0
    ld de, #0
    ;; DE = n (for outer loop)
    ld a, (catdoku_n)
    ld e, a
    ;; HL = n (for inner)
    ;; Actually just do simple copy: total = n*n
    pop hl
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; BC = n*n (but we need to multiply)
    ;; Use simple approach: copy n*n bytes
    ld a, (catdoku_n)
    ld (catdoku_temp_row), a
    ;; total bytes = n * n
    ld hl, #catdoku_decomp_buffer + 6   ; after header
    ld de, #catdoku_grid
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; multiply: n*n
    ;; Use a loop
    ld a, (catdoku_n)
    ld e, a
    ld d, #0
    ld hl, #catdoku_decomp_buffer + 6
    ld ix, #catdoku_grid
    ;; copy n*n bytes
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; B = n, C = n, total = B*C
    ;; Use nested loop
    push hl
    ld hl, #catdoku_grid
    ;; We'll just copy n*n bytes with a counter
    pop hl
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; multiply n*n into DE
    ld d, #0
    ld e, #0
    ld a, (catdoku_n)
    ld b, a
    ;; E = n, D = 0
    ld a, (catdoku_n)
    ld c, a
    ;; C = n, E = n
    ;; DE = n * n (approx)
    ;; Just use a simple counter
    ld ix, #catdoku_grid
    ld hl, #catdoku_decomp_buffer + 6
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; total = b*c
    push bc
    ;; multiply b*c
    ld a, b
    ld (catdoku_temp_val), a
    ld a, c
    ld (catdoku_temp_val + 1), a
    ;; Use simple: loop b times, each time c bytes
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; Actually, let's just copy n*n bytes sequentially
    pop bc
    ;; BC = n*n (we'll trust n*n < 81)
    ld a, (catdoku_n)
    ;; compute n*n
    ld b, a
    ld c, a
    ;; multiply by repeated addition
    ld d, #0
    ld e, #0
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    ;; total = row * col
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_col)
    ld c, a
    ;; BC = n * n (approx, but BC is 8-bit * 8-bit, need 16-bit)
    ;; Use HL for counter
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_col)
    ld c, a
    ;; HL = b * c
    ld a, b
    ld (catdoku_temp_val), a
    ld a, c
    ld (catdoku_temp_val + 1), a
    ;; Just do: total = n*n using a loop
    ld hl, #0
    ld a, (catdoku_n)
    ld b, a
    ld a, (catdoku_n)
    ld c, a
    ;; HL = B * C
    ld a, b
    or a
    jr z, _bl_skip_grid
    ld a, c
    or a
    jr z, _bl_skip_grid
    ;; multiply
    ld hl, #0
    ld a, (catdoku_n)
    ld b, a
_bl_mul_loop:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bl_no_carry
    inc h
_bl_no_carry:
    djnz _bl_mul_loop
_bl_skip_grid:
    ;; HL = n*n
    ;; Now copy HL bytes from decomp_buffer+6 to grid
    ld de, #catdoku_grid
    ld ix, #catdoku_decomp_buffer + 6
_bl_copy_grid:
    ld a, (ix)
    ld (de), a
    inc ix
    inc de
    dec hl
    ld a, h
    or l
    jr nz, _bl_copy_grid

    ;; Extract cats: num_cats * 2 bytes
    ;; Position after grid: decomp_buffer + 6 + n*n
    ;; Calculate offset
    ld a, (catdoku_n)
    ld b, a
    ld c, a
    ;; n*n
    ld hl, #0
    ld a, (catdoku_n)
    ld b, a
_bl_mul2:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bl_no_carry2
    inc h
_bl_no_carry2:
    djnz _bl_mul2
    ;; HL = n*n
    ld de, #catdoku_decomp_buffer + 6
    add hl, de
    ;; HL = start of cats list
    ld de, #catdoku_cats
    ld a, (catdoku_num_cats)
    ld b, a
    sla b                 ; *2
_bl_copy_cats:
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz _bl_copy_cats

    ;; Reset found state
    xor a
    ld (catdoku_found_cnt), a
    ld hl, #catdoku_found
    ld b, #13
_bl_clear_found:
    xor a
    ld (hl), a
    inc hl
    djnz _bl_clear_found

    ;; Reset marks
    ld hl, #catdoku_marks
    ld b, #81
_bl_clear_marks:
    xor a
    ld (hl), a
    inc hl
    djnz _bl_clear_marks

    pop af
    ret

;; ----------------------------------------------------------------------------
;; board_get_cell
;;   In: B = row, C = col
;;   Out: A = color/region 0..num_colours-1
;; ----------------------------------------------------------------------------
board_get_cell::
    ;; index = row * n + col
    ld a, (catdoku_n)
    ld e, a
    ld d, #0
    ld a, b
    ld (catdoku_temp_row), a
    ;; multiply row * n
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _bgc_no_mul
_bgc_mul:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bgc_no_carry
    inc h
_bgc_no_carry:
    djnz _bgc_mul
_bgc_no_mul:
    ;; HL = row * n
    ld a, c
    add a, l
    ld l, a
    jr nc, _bgc_no_carry2
    inc h
_bgc_no_carry2:
    ;; HL = row * n + col
    ld de, #catdoku_grid
    add hl, de
    ld a, (hl)
    ret

;; ----------------------------------------------------------------------------
;; board_set_cell
;;   In: B = row, C = col, D = type (0=EMPTY, 1=CAT, 2=MARK)
;;   Out: Z=1 if valid cat placed (found), Z=0 otherwise
;;   Modifies: marks, found bitmask, found_cnt
;; ----------------------------------------------------------------------------
board_set_cell::
    push bc
    push de
    ;; Calculate cell index = row * n + col
    ld a, (catdoku_n)
    ld e, a
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    ;; multiply row * n
    ld hl, #0
    ld a, b
    ld b, a
    or a
    jr z, _bsc_no_mul
_bsc_mul:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry
    inc h
_bsc_no_carry:
    djnz _bsc_mul
_bsc_no_mul:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry2
    inc h
_bsc_no_carry2:
    ;; HL = cell index
    ld de, #catdoku_marks
    add hl, de
    ;; HL = pointer to mark

    ;; Check type
    ld a, d
    cp #CELL_CAT
    jr z, _bsc_cat
    cp #CELL_MARK
    jr z, _bsc_mark
    ;; CELL_EMPTY: clear
    xor a
    ld (hl), a
    ;; Also remove from found if it was a cat
    ;; (simplified: just clear)
    jp _bsc_done

_bsc_mark:
    ld a, #CELL_MARK
    ld (hl), a
    jp _bsc_done

_bsc_cat:
    ;; Check if this cell matches a solution cat
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_temp_col)
    ld c, a
    ;; Search in cats list
    ld hl, #catdoku_cats
    ld a, (catdoku_num_cats)
    ld e, a
    ld d, #0
_bsc_search_cat:
    ld a, (hl)
    cp b
    jp nz, _bsc_next_cat
    inc hl
    ld a, (hl)
    cp c
    jp nz, _bsc_skip_cat
    ;; Match found! Check if already found
    dec hl
    ;; Calculate bit index
    ;; cat index = (hl - catdoku_cats) / 2
    push hl
    ld de, #catdoku_cats
    sbc hl, de
    sra h
    rr l
    ;; HL = cat index
    ;; Check if bit is set in found bitmask
    ld a, l
    ld (catdoku_temp_val), a
    ;; Calculate byte offset and bit mask
    ld a, (catdoku_temp_val)
    ld b, a
    srl b
    srl b
    srl b           ; /8
    ld hl, #catdoku_found
    add hl, bc
    ld a, (catdoku_temp_val)
    and #7
    ld c, a
    ld a, #1
    ;; shift left by C
    jr z, _bsc_bit_ready
_bsc_shift:
    sla a
    dec c
    jr nz, _bsc_shift
_bsc_bit_ready:
    ld b, a
    ld a, (hl)
    and b
    jr nz, _bsc_already_found
    ;; Not found yet: set bit
    ld a, (hl)
    or b
    ld (hl), a
    ;; Increment found count
    ld a, (catdoku_found_cnt)
    inc a
    ld (catdoku_found_cnt), a
    ;; Mark cell as cat
    pop hl
    ld hl, #catdoku_marks
    ;; recalculate index
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_n)
    ;; multiply
    ld e, a
    ld d, #0
    ld a, b
    ld (catdoku_temp_row), a
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _bsc_no_mul2
_bsc_mul2:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry3
    inc h
_bsc_no_carry3:
    djnz _bsc_mul2
_bsc_no_mul2:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry4
    inc h
_bsc_no_carry4:
    ld de, #catdoku_marks
    add hl, de
    ld a, #CELL_CAT
    ld (hl), a
    ;; Return with Z=1 (found)
    pop de
    pop bc
    xor a
    ret
_bsc_already_found:
    pop hl
    ;; Already found, just mark as cat
    ld hl, #catdoku_marks
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_n)
    ;; multiply
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _bsc_no_mul3
_bsc_mul3:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry5
    inc h
_bsc_no_carry5:
    djnz _bsc_mul3
_bsc_no_mul3:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry6
    inc h
_bsc_no_carry6:
    ld de, #catdoku_marks
    add hl, de
    ld a, #CELL_CAT
    ld (hl), a
    pop de
    pop bc
    xor a
    ret

_bsc_next_cat:
    inc hl
    inc hl
_bsc_skip_cat:
    ;; advance to next cat entry
    dec b
    jp nz, _bsc_search_cat
    ;; No match found - place cat anyway but don't count as found
    ld hl, #catdoku_marks
    ld a, (catdoku_temp_row)
    ld b, a
    ld a, (catdoku_n)
    ;; multiply
    ld hl, #0
    ld a, (catdoku_temp_row)
    ld b, a
    or a
    jr z, _bsc_no_mul4
_bsc_mul4:
    ld a, (catdoku_n)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry7
    inc h
_bsc_no_carry7:
    djnz _bsc_mul4
_bsc_no_mul4:
    ld a, (catdoku_temp_col)
    add a, l
    ld l, a
    jr nc, _bsc_no_carry8
    inc h
_bsc_no_carry8:
    ld de, #catdoku_marks
    add hl, de
    ld a, #CELL_CAT
    ld (hl), a
    ;; Return with Z=0 (not a solution cat)
    pop de
    pop bc
    ld a, #1
    or a
    ret

_bsc_done:
    pop de
    pop bc
    ld a, #1
    or a
    ret

;; ----------------------------------------------------------------------------
;; board_check_win
;;   Out: A = 1 if won (found_cnt == num_cats), 0 otherwise
;; ----------------------------------------------------------------------------
board_check_win::
    ld a, (catdoku_found_cnt)
    ld b, a
    ld a, (catdoku_num_cats)
    cp b
    jr z, _bcw_won
    xor a
    ret
_bcw_won:
    ld a, #1
    ret

;; ----------------------------------------------------------------------------
;; board_get_hint
;;   Out: HL = pointer to (row, col) of first unfound cat
;;        A = 0 if none (already won)
;; ----------------------------------------------------------------------------
board_get_hint::
    ld hl, #catdoku_cats
    ld a, (catdoku_num_cats)
    ld b, a
    ld c, #0           ; cat index
_bgh_loop:
    ld a, c
    ld (catdoku_temp_val), a
    ;; Check if this cat is found
    ld a, (catdoku_temp_val)
    ld b, a
    srl b
    srl b
    srl b
    ld hl, #catdoku_found
    add hl, bc
    ld a, (catdoku_temp_val)
    and #7
    ld c, a
    ld a, #1
    jr z, _bgh_bit_ready
_bgh_shift:
    sla a
    dec c
    jr nz, _bgh_shift
_bgh_bit_ready:
    ld b, a
    ld a, (hl)
    and b
    jr nz, _bgh_next
    ;; Found unfound cat - return pointer
    ld hl, #catdoku_cats
    ld a, (catdoku_temp_val)
    sla a
    ld e, a
    ld d, #0
    add hl, de
    ld a, #1
    ret
_bgh_next:
    ld a, (catdoku_temp_val)
    inc a
    ld c, a
    ld a, (catdoku_num_cats)
    cp c
    jr nz, _bgh_loop
    ;; No unfound cats
    xor a
    ld hl, #0
    ret