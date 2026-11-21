;; hint.s - The teaching hint: what to look at next, as tests/hint_model.py
;;
;; A cell is a candidate when it is empty (catdoku_marks 0) and no placed cat
;; shares its row, column or region or touches it. Units are rows, columns and
;; regions (unit u = 9 * family + item; family 0 rows, 1 columns, 2 regions).
;; hint_find returns the first that applies of ERR, RULED, ONE, FIT, TRIAL
;; (see tests/hint_model.py for the exact rules).

.module game_hint
.include "common.inc"

.area _DATA
hint_kind:: .db 0                 ; HINT_*
hint_target:: .db 0               ; cell index (row * n + col)
hint_k:: .db 0                    ; FIT: units involved (1..3)
hint_fam_a:: .db 0                ; ONE: family of the unit; FIT: family A
hint_fam_b:: .db 0                ; FIT: family B
hint_blink:: .ds 81               ; 1: the cell blinks

h_cat: .ds 81                     ; placed cats (marks, or a trial)
h_cand: .ds 81                    ; candidates
h_base: .ds 81                    ; candidates of the real state (trials)
h_sol: .ds 81                     ; 1: a solution cell
h_cr: .ds 81                      ; row of each cell
h_cc: .ds 81                      ; column of each cell
h_rstart: .ds 9                   ; row * n
h_has: .ds 27                     ; unit holds a cat
h_cnt: .ds 27                     ; candidates in the unit
h_last: .ds 27                    ; last candidate of the unit
h_mask: .ds 72                    ; FIT: per pair, family-B bits of each family-A item
h_valid4: .ds 8                   ; FIT: per pair, usable family-A items
h_base_units: .ds 54              ; h_has + h_cnt of the real state (trials)
h_ai: .db 0                       ; _h_add_cat
h_ar: .db 0
h_ac: .db 0
h_ag: .db 0
h_ia: .db 0                       ; FIT: items of the subset
h_ib: .db 0
h_ic: .db 0
h_n: .db 0
h_nn: .db 0
h_i: .db 0
h_j: .db 0
h_f: .db 0
h_u: .db 0
h_tmp: .db 0
h_first: .db 0
h_missing: .db 0
h_pair: .db 0
h_set: .dw 0                      ; FIT: subset S
h_valid: .dw 0                    ; FIT: usable family-A items
h_union: .dw 0
h_limit: .dw 0                    ; 1 << n

.area _CODE

;; Pairs (family A, family B) of FIT, in order.
h_pairs: .db 2, 0, 2, 1, 0, 2, 1, 2
;; 8 neighbours (row, column) of a cell.
h_around: .db 0xFF, 0xFF, 0xFF, 0, 0xFF, 1, 0, 0xFF, 0, 1, 1, 0xFF, 1, 0, 1, 1
;; Bit masks of items 0..8 (little endian words).
h_bits: .dw 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080, 0x0100

;; HL = HL + A. Modifies: AF.
_h_add:
    add a, l
    ld l, a
    adc a, h
    sub l
    ld h, a
    ret

;; In: A = cell, B = family. Out: A = its row, column or region. Modifies: F, HL.
_h_fam:
    push af
    ld a, b
    or a
    ld hl, #h_cr
    jr z, _hf_table
    dec a
    ld hl, #h_cc
    jr z, _hf_table
    ld hl, #catdoku_grid
_hf_table:
    pop af
    call _h_add
    ld a, (hl)
    ret

;; In: A = item. Out: DE = its bit (h_bits). Modifies: AF, HL.
_h_bit:
    add a, a
    ld hl, #h_bits
    call _h_add
    ld e, (hl)
    inc hl
    ld d, (hl)
    ret

;; In: DE. Out: A = number of bits set. Modifies: F, DE.
_h_popcount:
    xor a
_hp_loop:
    srl d
    rr e
    adc a, #0
    push af
    ld a, d
    or e
    jr z, _hp_done
    pop af
    jr _hp_loop
_hp_done:
    pop af
    ret

;; Board tables for this level: n, rows and columns of each cell, solution.
_h_setup:
    ld a, (catdoku_n)
    ld (h_n), a
    ld b, a
    xor a
    ld c, b
_hs_nn:
    add a, b
    dec c
    jr nz, _hs_nn
    ld (h_nn), a
    ;; h_rstart, h_cr, h_cc
    ld hl, #h_rstart
    xor a
    ld c, b
_hs_rs:
    ld (hl), a
    inc hl
    add a, b
    dec c
    jr nz, _hs_rs
    ld hl, #h_cr
    ld de, #h_cc
    ld c, #0                      ; row
_hs_row:
    xor a                         ; column
_hs_col:
    ld (hl), c
    inc hl
    ld (de), a
    inc de
    inc a
    cp b
    jr nz, _hs_col
    inc c
    ld a, c
    cp b
    jr nz, _hs_row
    ;; h_sol, h_missing
    ld hl, #h_sol
    ld b, #81
    xor a
_hs_clear:
    ld (hl), a
    inc hl
    djnz _hs_clear
    ld a, #0xFF
    ld (h_missing), a
    ld hl, #catdoku_cats
    ld a, (h_n)
    ld b, a
_hs_cat:
    ld a, (hl)                    ; row
    inc hl
    push hl
    ld hl, #h_rstart
    call _h_add
    ld a, (hl)
    pop hl
    add a, (hl)                   ; + column
    inc hl
    push hl
    ld (h_tmp), a
    ld hl, #h_sol
    call _h_add
    ld (hl), #1
    ld a, (h_missing)             ; first solution cell without its cat
    cp #0xFF
    jr nz, _hs_cat_next
    ld a, (h_tmp)
    ld hl, #catdoku_marks
    call _h_add
    ld a, (hl)
    cp #CELL_CAT
    jr z, _hs_cat_next
    ld a, (h_tmp)
    ld (h_missing), a
_hs_cat_next:
    pop hl
    djnz _hs_cat
    ret

;; h_cat = the placed cats of catdoku_marks.
_h_cats_from_marks:
    ld hl, #catdoku_marks
    ld de, #h_cat
    ld a, (h_nn)
    ld b, a
_hcm:
    ld a, (hl)
    cp #CELL_CAT
    ld a, #0
    jr nz, _hcm_put
    inc a
_hcm_put:
    ld (de), a
    inc hl
    inc de
    djnz _hcm
    ret

;; In: A = cell. Out: h_u = unit of the cell in family h_f. Modifies: AF, B, HL.
_h_unit:
    ld b, a
    ld a, (h_f)
    ld c, a
    ld a, b
    ld b, c
    call _h_fam
    ld b, a
    ld a, (h_f)
    add a, a
    add a, a
    add a, a
    ld c, a
    ld a, (h_f)
    add a, c                      ; 9 * family
    add a, b
    ld (h_u), a
    ret

;; h_has / h_cnt / h_last and h_cand from h_cat and catdoku_marks.
_h_compute:
    ld hl, #h_has
    ld b, #54                     ; h_has and h_cnt
    xor a
_hc_clear:
    ld (hl), a
    inc hl
    djnz _hc_clear
    ;; units holding a cat
    xor a
    ld (h_i), a
_hc_cats:
    ld a, (h_i)
    ld hl, #h_cat
    call _h_add
    ld a, (hl)
    or a
    jr z, _hc_cats_next
    xor a
_hc_cats_fam:
    ld (h_f), a
    ld a, (h_i)
    call _h_unit
    ld hl, #h_has
    call _h_add
    ld (hl), #1
    ld a, (h_f)
    inc a
    cp #3
    jr nz, _hc_cats_fam
_hc_cats_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hc_cats
    ;; candidates
    xor a
    ld (h_i), a
_hc_cell:
    ld a, (h_i)
    ld hl, #h_cand
    call _h_add
    ld (hl), #0
    ld a, (h_i)
    ld hl, #catdoku_marks
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hc_next
    ld a, (h_i)
    ld hl, #h_cat
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hc_next
    xor a                         ; a unit of the cell holds a cat?
_hc_has:
    ld (h_f), a
    ld a, (h_i)
    call _h_unit
    ld hl, #h_has
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hc_next
    ld a, (h_f)
    inc a
    cp #3
    jr nz, _hc_has
    call _h_touched               ; a neighbour holds a cat?
    jr nz, _hc_next
    ld a, (h_i)                   ; a candidate
    ld hl, #h_cand
    call _h_add
    ld (hl), #1
    xor a
_hc_count:
    ld (h_f), a
    ld a, (h_i)
    call _h_unit
    ld a, (h_u)
    ld hl, #h_cnt
    call _h_add
    inc (hl)
    ld a, (h_u)
    ld hl, #h_last
    call _h_add
    ld a, (h_i)
    ld (hl), a
    ld a, (h_f)
    inc a
    cp #3
    jr nz, _hc_count
_hc_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jp nz, _hc_cell
    ret

;; Out: NZ when one of the 8 neighbours of cell h_i holds a cat (h_cat).
;; Modifies: AF, BC, DE, HL.
_h_touched:
    ld a, (h_i)
    ld hl, #h_cr
    call _h_add
    ld d, (hl)                    ; D = row
    ld a, (h_i)
    ld hl, #h_cc
    call _h_add
    ld e, (hl)                    ; E = column
    ld hl, #h_around
    ld b, #8
_ht_loop:
    ld a, (hl)
    inc hl
    add a, d
    ld c, a                       ; C = neighbour row (0xFF when off)
    ld a, (hl)
    inc hl
    add a, e                      ; A = neighbour column
    push hl
    push af
    ld a, (h_n)
    ld h, a
    ld a, c
    cp h
    jr nc, _ht_off_pop
    pop af
    cp h
    jr nc, _ht_off
    push af
    ld a, c
    ld hl, #h_rstart
    call _h_add
    pop af
    add a, (hl)
    ld hl, #h_cat
    call _h_add
    ld a, (hl)
    pop hl
    or a
    ret nz
    djnz _ht_loop
    ret                           ; Z
_ht_off_pop:
    pop af
_ht_off:
    pop hl
    djnz _ht_loop
    xor a
    ret

;; Out: A = 1 when a unit without a cat has no candidate. Modifies: AF, BC, HL.
_h_contradiction:
    ld c, #0                      ; unit
_hx_fam:
    ld a, (h_n)
    ld b, a
_hx_item:
    ld a, c
    ld hl, #h_has
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hx_next
    ld a, c
    ld hl, #h_cnt
    call _h_add
    ld a, (hl)
    or a
    ld a, #1
    ret z
_hx_next:
    inc c
    djnz _hx_item
    ld a, c                       ; skip to the next family (9 units each)
    add a, #9
    ld hl, #h_n
    sub (hl)
    ld c, a
    cp #27
    jr c, _hx_fam
    xor a
    ret

;; Out: A = first unit without a cat with one candidate, 0xFF when none;
;; E = that candidate. Modifies: AF, BC, E, HL.
_h_single:
    ld c, #0
_hsg_fam:
    ld a, (h_n)
    ld b, a
_hsg_item:
    ld a, c
    ld hl, #h_has
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hsg_next
    ld a, c
    ld hl, #h_cnt
    call _h_add
    ld a, (hl)
    cp #1
    jr z, _hsg_found
_hsg_next:
    inc c
    djnz _hsg_item
    ld a, c
    add a, #9
    ld hl, #h_n
    sub (hl)
    ld c, a
    cp #27
    jr c, _hsg_fam
    ld a, #0xFF
    ret
_hsg_found:
    ;; its candidate: the candidate cell whose unit in that family is C
    ld a, c
    ld b, #0
_hsg_div:
    cp #9
    jr c, _hsg_div_done
    sub #9
    inc b
    jr _hsg_div
_hsg_div_done:
    ld (h_u), a                   ; item
    ld a, b
    ld (h_f), a                   ; family
    ld e, #0
_hsg_cell:
    ld a, e
    ld hl, #h_cand
    call _h_add
    ld a, (hl)
    or a
    jr z, _hsg_cell_next
    ld a, (h_f)
    ld b, a
    ld a, e
    call _h_fam
    ld hl, #h_u
    cp (hl)
    jr z, _hsg_cell_done
_hsg_cell_next:
    inc e
    jr _hsg_cell
_hsg_cell_done:
    ld a, c
    ret

;; ----------------------------------------------------------------------------
;; _h_add_cat
;;   In: A = a candidate cell. Places a cat there in h_cand / h_has / h_cnt:
;;   its units hold a cat, and every candidate it rules out (same row,
;;   column or region, or touching it, itself included) stops being one.
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
_h_add_cat:
    ld (h_ai), a
    ld hl, #h_cr
    call _h_add
    ld a, (hl)
    ld (h_ar), a
    ld hl, #h_has
    call _h_add
    ld (hl), #1
    ld a, (h_ai)
    ld hl, #h_cc
    call _h_add
    ld a, (hl)
    ld (h_ac), a
    add a, #9
    ld hl, #h_has
    call _h_add
    ld (hl), #1
    ld a, (h_ai)
    ld hl, #catdoku_grid
    call _h_add
    ld a, (hl)
    ld (h_ag), a
    add a, #18
    ld hl, #h_has
    call _h_add
    ld (hl), #1
    ld c, #0                      ; cell j
_hac_cell:
    ld a, c
    ld hl, #h_cand
    call _h_add
    ld a, (hl)
    or a
    jr z, _hac_next
    push hl
    ld a, c
    ld hl, #h_cr
    call _h_add
    ld d, (hl)                    ; D = row of j
    ld a, c
    ld hl, #h_cc
    call _h_add
    ld e, (hl)                    ; E = column of j
    ld a, c
    ld hl, #catdoku_grid
    call _h_add
    ld b, (hl)                    ; B = region of j
    pop hl
    ld a, (h_ar)
    cp d
    jr z, _hac_out
    ld a, (h_ac)
    cp e
    jr z, _hac_out
    ld a, (h_ag)
    cp b
    jr z, _hac_out
    ld a, (h_ar)                  ; touching: |row - row| <= 1 and |col - col| <= 1
    sub d
    inc a
    cp #3
    jr nc, _hac_next
    ld a, (h_ac)
    sub e
    inc a
    cp #3
    jr nc, _hac_next
_hac_out:
    ld (hl), #0                   ; no longer a candidate: its counts drop
    ld a, d
    ld hl, #h_cnt
    call _h_add
    dec (hl)
    ld a, e
    add a, #9
    ld hl, #h_cnt
    call _h_add
    dec (hl)
    ld a, b
    add a, #18
    ld hl, #h_cnt
    call _h_add
    dec (hl)
_hac_next:
    inc c
    ld a, (h_nn)
    cp c
    jr nz, _hac_cell
    ret

;; hint_blink |= the cells of unit (family h_f, item h_tmp). Modifies: AF, BC, HL.
_h_blink_unit:
    xor a
    ld (h_i), a
_hbu:
    ld a, (h_f)
    ld b, a
    ld a, (h_i)
    call _h_fam
    ld hl, #h_tmp
    cp (hl)
    jr nz, _hbu_next
    ld a, (h_i)
    ld hl, #hint_blink
    call _h_add
    ld (hl), #1
_hbu_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hbu
    ret

;; ----------------------------------------------------------------------------
;; hint_find
;;   Out: hint_kind (HINT_*), hint_target, hint_blink, hint_k, hint_fam_a,
;;   hint_fam_b for the current board (catdoku_marks, catdoku_grid,
;;   catdoku_cats). Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
hint_find::
    ld hl, #hint_blink
    ld b, #81
    xor a
_hfd_clear:
    ld (hl), a
    inc hl
    djnz _hfd_clear
    call _h_setup
    ;; ERR: an X on a solution cell, in catdoku_cats order
    ld hl, #catdoku_cats
    ld a, (h_n)
    ld b, a
_hfd_err:
    ld a, (hl)
    inc hl
    push hl
    ld hl, #h_rstart
    call _h_add
    ld a, (hl)
    pop hl
    add a, (hl)
    inc hl
    ld (h_tmp), a
    push hl
    ld hl, #catdoku_marks
    call _h_add
    ld a, (hl)
    pop hl
    cp #CELL_MARK
    jr z, _hfd_err_found
    djnz _hfd_err
    ;; RULED: empty cells that are not candidates
    call _h_cats_from_marks
    call _h_compute
    xor a
    ld (h_tmp), a                 ; 1 once one is found
    ld (h_i), a
_hfd_ruled:
    ld a, (h_i)
    ld hl, #catdoku_marks
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hfd_ruled_next
    ld a, (h_i)
    ld hl, #h_cand
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hfd_ruled_next
    ld a, (h_i)
    ld hl, #hint_blink
    call _h_add
    ld (hl), #1
    ld a, #1
    ld (h_tmp), a
_hfd_ruled_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hfd_ruled
    ld a, (h_tmp)
    or a
    jr z, _hfd_one
    ld a, #HINT_RULED
    jp _hfd_missing
_hfd_err_found:
    ld a, (h_tmp)
    ld (hint_target), a
    ld hl, #hint_blink
    call _h_add
    ld (hl), #1
    ld a, #HINT_ERR
    ld (hint_kind), a
    ret
_hfd_one:
    ;; ONE: a unit without a cat with a single candidate
    call _h_single
    cp #0xFF
    jr z, _hfd_fit
    ld b, #0                      ; unit -> family, item
_hfd_div9:
    cp #9
    jr c, _hfd_div9_done
    sub #9
    inc b
    jr _hfd_div9
_hfd_div9_done:
    ld (h_tmp), a
    ld a, b
    ld (h_f), a
    ld (hint_fam_a), a
    ld a, e
    ld (hint_target), a
    call _h_blink_unit
    ld a, #HINT_ONE
    ld (hint_kind), a
    ret
_hfd_fit:
    call _h_fit
    or a
    jr z, _hfd_trial
    ld a, #HINT_FIT
    jp _hfd_missing
_hfd_trial:
    ;; TRIAL: a non-solution candidate that leads to a contradiction. Each
    ;; trial starts from a copy of the real state and adds cats one by one.
    ld hl, #h_cand
    ld de, #h_base
    ld bc, #81
    ldir
    ld hl, #h_has
    ld de, #h_base_units
    ld bc, #54
    ldir
    ld a, #0xFF
    ld (h_first), a
    xor a
    ld (h_j), a
_hfd_try:
    ld a, (h_j)
    ld hl, #h_base
    call _h_add
    ld a, (hl)
    or a
    jr z, _hfd_try_next
    ld a, (h_j)
    ld hl, #h_sol
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hfd_try_next
    ld a, (h_first)
    cp #0xFF
    jr nz, _hfd_try_sim
    ld a, (h_j)
    ld (h_first), a
_hfd_try_sim:
    ld hl, #h_base
    ld de, #h_cand
    ld bc, #81
    ldir
    ld hl, #h_base_units
    ld de, #h_has
    ld bc, #54
    ldir
    ld a, (h_j)
_hfd_step:
    call _h_add_cat
    call _h_contradiction
    or a
    jr nz, _hfd_try_found
    call _h_single
    cp #0xFF
    jr z, _hfd_try_next
    ld a, e
    jr _hfd_step
_hfd_try_next:
    ld a, (h_j)
    inc a
    ld (h_j), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hfd_try
    ld a, (h_first)
    cp #0xFF
    jr z, _hfd_none
    ld (h_j), a
_hfd_try_found:
    ld a, (h_j)
    ld (hint_target), a
    ld hl, #hint_blink
    call _h_add
    ld (hl), #1
    ld a, #HINT_TRIAL
    ld (hint_kind), a
    ret
_hfd_none:
    xor a                         ; HINT_NONE
    ld (hint_kind), a
    ret
_hfd_missing:
    ld (hint_kind), a
    ld a, (h_missing)
    ld (hint_target), a
    ret

;; ----------------------------------------------------------------------------
;; _h_fit
;;   FIT over k = 1..3 and the four pairs; subsets of k usable items in
;;   increasing bit-mask order (highest item first, as tests/hint_model.py).
;;   Out: A = 1 and hint_k, hint_fam_a, hint_fam_b, hint_blink when found,
;;   else A = 0. Uses h_cand / h_has.
;; ----------------------------------------------------------------------------
_h_fit:
    xor a
_hft_masks_pair:
    ld (h_pair), a
    call _hft_pair_families
    call _hft_masks
    ld a, (h_pair)
    inc a
    cp #4
    jr nz, _hft_masks_pair
    ld a, #1
    ld (hint_k), a
_hft_k:
    xor a
    ld (h_pair), a
_hft_pair:
    call _hft_pair_families
    xor a                         ; c: highest item
    ld (h_ic), a
_hft_c:
    ld a, (h_ic)
    call _hft_usable
    jp z, _hft_c_next
    ld a, (hint_k)
    cp #1
    jr nz, _hft_b_start
    ld a, (h_ic)
    call _h_bit
    ld (h_set), de
    call _hft_try
    jp nz, _hft_found
    jr _hft_c_next
_hft_b_start:
    xor a
    ld (h_ib), a
_hft_b:
    ld a, (h_ib)
    ld hl, #h_ic
    cp (hl)
    jr z, _hft_c_next
    call _hft_usable
    jr z, _hft_b_next
    ld a, (hint_k)
    cp #2
    jr nz, _hft_a_start
    ld a, (h_ic)
    call _h_bit
    push de
    ld a, (h_ib)
    call _h_bit
    pop hl
    call _hft_or
    call _hft_try
    jr nz, _hft_found
    jr _hft_b_next
_hft_a_start:
    xor a
    ld (h_ia), a
_hft_a:
    ld a, (h_ia)
    ld hl, #h_ib
    cp (hl)
    jr z, _hft_b_next
    call _hft_usable
    jr z, _hft_a_next
    ld a, (h_ic)
    call _h_bit
    push de
    ld a, (h_ib)
    call _h_bit
    pop hl
    call _hft_or_hl
    push hl
    ld a, (h_ia)
    call _h_bit
    pop hl
    call _hft_or
    call _hft_try
    jr nz, _hft_found
_hft_a_next:
    ld hl, #h_ia
    inc (hl)
    jr _hft_a
_hft_b_next:
    ld hl, #h_ib
    inc (hl)
    jr _hft_b
_hft_c_next:
    ld a, (h_ic)
    inc a
    ld (h_ic), a
    ld hl, #h_n
    cp (hl)
    jp nz, _hft_c
    ld a, (h_pair)
    inc a
    ld (h_pair), a
    cp #4
    jp nz, _hft_pair
    ld a, (hint_k)
    inc a
    ld (hint_k), a
    cp #4
    jp nz, _hft_k
    xor a
    ret
_hft_found:
    ;; blink the cells of the family-A items of S
    xor a
    ld (h_i), a
_hft_blink:
    ld a, (hint_fam_a)
    ld b, a
    ld a, (h_i)
    call _h_fam
    call _h_bit
    ld hl, (h_set)
    ld a, e
    and l
    ld c, a
    ld a, d
    and h
    or c
    jr z, _hft_blink_next
    ld a, (h_i)
    ld hl, #hint_blink
    call _h_add
    ld (hl), #1
_hft_blink_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hft_blink
    ld a, #1
    ret

;; HL |= DE, then h_set = HL. Modifies: AF.
_hft_or:
    call _hft_or_hl
    ld (h_set), hl
    ret
_hft_or_hl:
    ld a, l
    or e
    ld l, a
    ld a, h
    or d
    ld h, a
    ret

;; hint_fam_a / hint_fam_b of pair h_pair. Modifies: AF, HL.
_hft_pair_families:
    ld a, (h_pair)
    add a, a
    ld hl, #h_pairs
    call _h_add
    ld a, (hl)
    ld (hint_fam_a), a
    inc hl
    ld a, (hl)
    ld (hint_fam_b), a
    ret

;; In: A = item. Out: NZ when usable in pair h_pair. Modifies: AF, DE, HL.
_hft_usable:
    call _h_bit
    ld a, (h_pair)
    add a, a
    ld hl, #h_valid4
    call _h_add
    ld a, (hl)
    and e
    ret nz
    inc hl
    ld a, (hl)
    and d
    ret

;; HL = &h_mask[pair][0]. Modifies: AF, HL.
_hft_mask_base:
    ld a, (h_pair)
    add a, a                      ; x2
    ld l, a
    add a, a                      ; x4
    add a, a                      ; x8
    add a, a                      ; x16
    add a, l                      ; x18
    ld hl, #h_mask
    jp _h_add

;; Subset h_set: Out NZ when its union has k items and rules out a candidate.
_hft_try:
    call _hft_mask_base
    ld bc, (h_set)
    ld de, #0
_hfy_union:
    ld a, b
    or c
    jr z, _hfy_union_done
    srl b
    rr c
    jr nc, _hfy_skip
    ld a, (hl)
    or e
    ld e, a
    inc hl
    ld a, (hl)
    or d
    ld d, a
    dec hl
_hfy_skip:
    inc hl
    inc hl
    jr _hfy_union
_hfy_union_done:
    ld (h_union), de
    call _h_popcount
    ld hl, #hint_k
    cp (hl)
    jr nz, _hfy_no
    call _hft_rules_out
    or a
    ret
_hfy_no:
    xor a
    ret

;; h_mask[pair][a] = family-B bits of the candidates of family-A item a;
;; h_valid4[pair] = items without a cat and with candidates.
_hft_masks:
    call _hft_mask_base
    ld b, #18
    xor a
_hfm_clear:
    ld (hl), a
    inc hl
    djnz _hfm_clear
    xor a
    ld (h_i), a
_hfm_cell:
    ld a, (h_i)
    ld hl, #h_cand
    call _h_add
    ld a, (hl)
    or a
    jr z, _hfm_next
    ld a, (hint_fam_b)
    ld b, a
    ld a, (h_i)
    call _h_fam
    call _h_bit                   ; DE = bit of the B item
    ld a, (hint_fam_a)
    ld b, a
    ld a, (h_i)
    call _h_fam
    add a, a
    push af
    call _hft_mask_base
    pop af
    call _h_add
    ld a, (hl)
    or e
    ld (hl), a
    inc hl
    ld a, (hl)
    or d
    ld (hl), a
_hfm_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hfm_cell
    ;; h_valid4[pair]
    ld hl, #0
    ld (h_valid), hl
    xor a
    ld (h_i), a
_hfm_valid:
    ld a, (hint_fam_a)            ; unit = 9 * family + item
    ld b, a
    add a, a
    add a, a
    add a, a
    add a, b
    ld hl, #h_i
    add a, (hl)
    ld hl, #h_has
    call _h_add
    ld a, (hl)
    or a
    jr nz, _hfm_valid_next
    call _hft_mask_base
    ld a, (h_i)
    add a, a
    call _h_add
    ld a, (hl)
    inc hl
    or (hl)
    jr z, _hfm_valid_next
    ld a, (h_i)
    call _h_bit
    ld hl, (h_valid)
    ld a, l
    or e
    ld l, a
    ld a, h
    or d
    ld h, a
    ld (h_valid), hl
_hfm_valid_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_n
    cp (hl)
    jr nz, _hfm_valid
    ld a, (h_pair)
    add a, a
    ld hl, #h_valid4
    call _h_add
    ld de, (h_valid)
    ld (hl), e
    inc hl
    ld (hl), d
    ret

;; Out: A = 1 when a candidate lies in a family-B item of h_union and
;; outside the family-A items of h_set.
_hft_rules_out:
    xor a
    ld (h_i), a
_hfr_cell:
    ld a, (h_i)
    ld hl, #h_cand
    call _h_add
    ld a, (hl)
    or a
    jr z, _hfr_next
    ld a, (hint_fam_b)
    ld b, a
    ld a, (h_i)
    call _h_fam
    call _h_bit
    ld hl, (h_union)
    ld a, e
    and l
    ld c, a
    ld a, d
    and h
    or c
    jr z, _hfr_next
    ld a, (hint_fam_a)
    ld b, a
    ld a, (h_i)
    call _h_fam
    call _h_bit
    ld hl, (h_set)
    ld a, e
    and l
    ld c, a
    ld a, d
    and h
    or c
    jr nz, _hfr_next
    ld a, #1
    ret
_hfr_next:
    ld a, (h_i)
    inc a
    ld (h_i), a
    ld hl, #h_nn
    cp (hl)
    jr nz, _hfr_cell
    xor a
    ret
