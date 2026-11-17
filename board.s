;; board.s - Core board logic for Catdoku
;; All board-related operations live here.

.module game_board
.globl board_load_level, board_get_cell, board_set_cell, board_check_win, board_get_hint, board_get_mark
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
catdoku_temp_val:: .ds 4          ; 4 bytes: board_load_level keeps packed/unpacked sizes here

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
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    call _board_mark_ptr        ; HL = &catdoku_marks[row*n+col]
    pop de
    push de
    ld a, d
    cp #CELL_CAT
    jr z, _bsc_cat
    cp #CELL_MARK
    jr z, _bsc_mark
    ld (hl), #CELL_EMPTY
    jr _bsc_nz
_bsc_mark:
    ld (hl), #CELL_MARK
    jr _bsc_nz

_bsc_cat:
    ;; Place the cat, then look for (row, col) in the solution list
    ld (hl), #CELL_CAT
    ld a, (catdoku_num_cats)
    or a
    jr z, _bsc_nz
    ld b, a                     ; B = cats left to check
    ld e, #0                    ; E = cat index
    ld hl, #catdoku_cats
_bsc_search:
    ld a, (catdoku_temp_row)
    cp (hl)
    inc hl                      ; 16-bit inc keeps flags
    jr nz, _bsc_next
    ld a, (catdoku_temp_col)
    cp (hl)
    jr z, _bsc_match
_bsc_next:
    inc hl
    inc e
    djnz _bsc_search
    jr _bsc_nz                  ; not a solution cell

_bsc_match:
    ;; HL = &catdoku_found[E >> 3], C = 1 << (E & 7)
    ld a, e
    srl a
    srl a
    srl a
    ld c, a
    ld b, #0
    ld hl, #catdoku_found
    add hl, bc
    ld c, #1
    ld a, e
    and #7
    jr z, _bsc_bit_ready
_bsc_shift:
    sla c
    dec a
    jr nz, _bsc_shift
_bsc_bit_ready:
    ld a, (hl)
    and c
    jr nz, _bsc_z               ; already counted
    ld a, (hl)
    or c
    ld (hl), a
    ld a, (catdoku_found_cnt)
    inc a
    ld (catdoku_found_cnt), a
_bsc_z:
    pop de
    pop bc
    xor a
    ret
_bsc_nz:
    pop de
    pop bc
    ld a, #1
    or a
    ret

;; ----------------------------------------------------------------------------
;; board_get_mark
;;   In: B = row, C = col
;;   Out: A = CELL_EMPTY, CELL_CAT or CELL_MARK
;;   Preserves BC. Modifies AF, DE, HL, catdoku_temp_row/col.
;; ----------------------------------------------------------------------------
board_get_mark::
    push bc
    ld a, b
    ld (catdoku_temp_row), a
    ld a, c
    ld (catdoku_temp_col), a
    call _board_mark_ptr
    ld a, (hl)
    pop bc
    ret

;; ----------------------------------------------------------------------------
;; _board_mark_ptr
;;   In: catdoku_temp_row, catdoku_temp_col
;;   Out: HL = &catdoku_marks[row * n + col]
;;   Modifies: A, B, DE, HL
;; ----------------------------------------------------------------------------
_board_mark_ptr:
    ld hl, #0
    ld a, (catdoku_n)
    ld e, a
    ld d, #0
    ld a, (catdoku_temp_row)
    or a
    jr z, _bmp_col
    ld b, a
_bmp_mul:
    add hl, de
    djnz _bmp_mul
_bmp_col:
    ld a, (catdoku_temp_col)
    ld e, a
    add hl, de
    ld de, #catdoku_marks
    add hl, de
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
    ld c, b
    ld b, #0
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