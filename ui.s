;; ui.s - Catdoku screen drawing: backgrounds, pixel boxes and the 3x6 font
;;
;; Coordinates are Mode 0 pixels: x 0..159, y 0..199. A pen is 0..15.
;; The screen is the standard one at 0xC000 (no hardware offset).

.module catdoku_ui
.include "common.inc"

.area _DATA
ui_x: .db 0                       ; current span / rectangle
ui_y: .db 0
ui_w: .db 0
ui_h: .db 0
ui_pbyte: .db 0                   ; pen in both pixels of a byte
ui_tx: .db 0                      ; text cursor
ui_ty: .db 0
ui_row: .db 0
ui_bits: .db 0
ui_repeat: .db 0                  ; lines per glyph row (1, or 2: double height)
ui_trepeat: .db 0                 ; the same for the text routines
ui_left: .db 0
ui_rowbits: .db 0
ui_glyph: .dw 0
ui_tpen: .db 0
ui_mask: .db 0
ui_box_fill: .db 0
ui_help_pen: .db 0
ui_char: .db 0, 0                 ; one character + NUL

.area _CODE

;; Pen n in both pixels of a Mode 0 byte.
ui_pen_bytes::
    .db 0x00, 0xC0, 0x0C, 0xCC, 0x30, 0xF0, 0x3C, 0xFC
    .db 0x03, 0xC3, 0x0F, 0xCF, 0x33, 0xF3, 0x3F, 0xFF

;; ----------------------------------------------------------------------------
;; ui_show_background
;;   In: A = UI_BG_MENU / UI_BG_LEVELS / UI_BG_GAME / UI_BG_PLAIN.
;;   Decompresses the 16 KB screen dump straight into 0xC000..0xFFFF.
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
ui_show_background::
    add a, a
    ld e, a
    ld d, #0
    ld hl, #ui_bg_table
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a                       ; HL = last compressed byte
    ld de, #0xFFFF                ; DE = last screen byte
    jp fwk_zx7b_unpack

;; ----------------------------------------------------------------------------
;; ui_pen_byte
;;   In: A = pen. Out: A = the pen in both pixels. Modifies: AF, DE.
;; ----------------------------------------------------------------------------
ui_pen_byte::
    ld e, a
    ld d, #0
    push hl
    ld hl, #ui_pen_bytes
    add hl, de
    ld a, (hl)
    pop hl
    ret

;; ----------------------------------------------------------------------------
;; ui_rect
;;   In: B = x, C = y, D = width (1..160), E = height (0..200), A = pen.
;;   Fills the rectangle pixel by pixel at the edges, a byte at a time inside.
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
ui_rect::
    push de
    call ui_pen_byte
    pop de
    ld (ui_pbyte), a
    ld a, b
    ld (ui_x), a
    ld a, c
    ld (ui_y), a
    ld a, d
    ld (ui_w), a
    ld a, e
    ld (ui_h), a
    or a
    ret z
    ld a, (ui_y)
    ld l, a
    ld h, #0
    ld a, (ui_x)
    srl a
    ld c, a
    call fwk_video_get_ptr        ; HL = first byte of the first line
_ur_line:
    push hl
    call _ui_span
    pop hl
    ld de, #0x0800                ; next line: +0x800, or back to the
    add hl, de                    ; next character row (+0xC050) when the
    jr nc, _ur_same_row           ; 0xC000..0xFFFF block overflows
    ld de, #0xC050
    add hl, de
_ur_same_row:
    ld a, (ui_h)
    dec a
    ld (ui_h), a
    jr nz, _ur_line
    ret

;; One line: ui_w pixels from HL (the byte holding pixel ui_x) in ui_pbyte.
;; Modifies: AF, BC, DE, HL.
_ui_span:
    ld a, (ui_pbyte)
    ld e, a
    ld a, (ui_w)
    ld b, a                       ; B = pixels left
    ld a, (ui_x)
    and #1
    jr z, _us_bytes
    ld a, #0x55                   ; odd x: the right pixel of the first byte
    call _ui_merge
    inc hl
    dec b
    ret z
_us_bytes:
    ld a, b
    cp #2
    jr c, _us_tail
    ld (hl), e
    inc hl
    dec b
    dec b
    jr _us_bytes
_us_tail:
    or a
    ret z
    ld a, #0xAA                   ; one pixel left: the left pixel of the byte
    ; fall through

;; (HL) = (HL) & ~A | E & A. Modifies: AF, C, D. Preserves B, E, HL.
_ui_merge:
    ld d, a
    cpl
    and (hl)
    ld c, a
    ld a, e
    and d
    or c
    ld (hl), a
    ret

;; ----------------------------------------------------------------------------
;; ui_box
;;   In: B = x, C = y, D = width, E = height (both >= 3), H = border pen,
;;       L = fill pen. A 1-pixel border, the fill inside, and the four corner
;;   pixels in dark blue, as every box of the design.
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
ui_box::
    ld a, l
    ld (ui_box_fill), a
    push bc
    push de
    ld a, h
    call ui_rect                  ; border colour over the whole box
    pop de
    pop bc
    push bc
    push de
    inc b
    inc c
    dec d
    dec d
    dec e
    dec e
    ld a, (ui_box_fill)
    call ui_rect
    pop de
    pop bc
    ld a, b                       ; corners: right x and bottom y first,
    add a, d                      ; _ui_plot destroys DE
    dec a
    ld (ui_tx), a
    ld a, c
    add a, e
    dec a
    ld (ui_ty), a
    ld a, #PEN_DARK_BLUE
    call ui_pen_byte
    ld (ui_pbyte), a
    push bc
    call _ui_plot                 ; top left
    pop bc
    push bc
    ld a, (ui_tx)
    ld b, a
    call _ui_plot                 ; top right
    pop bc
    ld a, (ui_ty)
    ld c, a
    push bc
    call _ui_plot                 ; bottom left
    pop bc
    ld a, (ui_tx)
    ld b, a
    jp _ui_plot                   ; bottom right

;; B = x, C = y: one pixel in ui_pbyte. Modifies: AF, C, D, E, HL. Preserves B.
_ui_plot:
    ld l, c
    ld h, #0
    ld a, b
    srl a
    ld c, a
    call fwk_video_get_ptr
    ld a, (ui_pbyte)
    ld e, a
    ld a, b
    and #1
    ld a, #0xAA                   ; even x: left pixel
    jr z, _ui_merge
    ld a, #0x55                   ; odd x: right pixel
    jr _ui_merge

;; ----------------------------------------------------------------------------
;; ui_pattern / ui_pattern_big
;;   In: HL = rows (bit 7 = left pixel), B = x, C = y, D = width (1..8),
;;       E = rows, A = pen. Draws the lit pixels only. ui_pattern_big draws
;;       every row twice (double height: E rows take 2*E lines).
;;   Modifies: AF, BC, DE, HL.
;; ----------------------------------------------------------------------------
ui_pattern::
    push af
    ld a, #1
    ld (ui_repeat), a
    pop af
    jr _ui_pattern
ui_pattern_big::
    push af
    ld a, #2
    ld (ui_repeat), a
    pop af
;; Same, with ui_repeat (1 or 2) already set: the text routines come in here.
_ui_pattern:
    ld (ui_glyph), hl
    push de
    call ui_pen_byte
    pop de
    ld (ui_pbyte), a
    ld a, b
    ld (ui_tx), a
    ld a, c
    ld (ui_ty), a
    ld a, e
    ld (ui_row), a
_up_row:
    ld hl, (ui_glyph)
    ld a, (hl)
    inc hl
    ld (ui_glyph), hl
    ld (ui_rowbits), a
    ld a, (ui_repeat)
    ld (ui_left), a               ; lines left for this row
_up_line:
    ld a, (ui_rowbits)
    ld (ui_bits), a
    ld a, (ui_ty)
    ld l, a
    ld h, #0
    ld a, (ui_tx)
    srl a
    ld c, a
    call fwk_video_get_ptr        ; one address per line
    ld a, (ui_pbyte)
    ld e, a
    ld a, (ui_tx)
    and #1
    ld a, #0xAA                   ; even x: the left pixel first
    jr z, _up_mask
    ld a, #0x55
_up_mask:
    ld (ui_mask), a
_up_col:
    ld a, (ui_bits)
    add a, a
    ld (ui_bits), a
    jr nc, _up_skip
    ld a, (ui_mask)
    call _ui_merge                ; preserves E, HL
_up_skip:
    ld a, (ui_bits)
    or a
    jr z, _up_next
    ld a, (ui_mask)               ; next pixel: right half, or the next byte
    cp #0xAA
    ld a, #0x55
    jr z, _up_mask
    inc hl
    ld a, #0xAA
    jr _up_mask
_up_next:
    ld hl, #ui_ty
    inc (hl)
    ld hl, #ui_left
    dec (hl)
    jr nz, _up_line
    ld hl, #ui_row
    dec (hl)
    jr nz, _up_row
    ret

;; ----------------------------------------------------------------------------
;; ui_text / ui_text_big
;;   In: IY = NUL-terminated string (ASCII 32..95), B = x, C = y (top of the
;;   glyphs), A = pen. Each character is 3x6 pixels plus a 1-pixel gap;
;;   ui_text_big draws it 3x12 (each row twice, same font).
;;   Out: B = x after the last character. Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
ui_text::
    push af
    ld a, #1
    ld (ui_trepeat), a
    pop af
    jr _ui_text
ui_text_big::
    push af
    ld a, #2
    ld (ui_trepeat), a
    pop af
;; Same, with ui_trepeat already set (ui_text_in / ui_text_in_big).
_ui_text:
    ld (ui_tpen), a
    ld a, b
    ld (ui_x), a                  ; ui_x: x of the next character
    ld a, c
    ld (ui_y), a
_ut_char:
    ld a, (iy)
    or a
    jr z, _ut_done
    inc iy
    sub #32
    jr c, _ut_next
    cp #64
    jr nc, _ut_next
    ld l, a
    ld h, #0
    add hl, hl
    ld d, h
    ld e, l
    add hl, hl
    add hl, de                    ; x6
    ld de, #ui_font
    add hl, de
    ld a, (ui_trepeat)
    ld (ui_repeat), a
    ld a, (ui_x)
    ld b, a
    ld a, (ui_y)
    ld c, a
    ld de, #0x0306                ; 3 columns, 6 rows
    ld a, (ui_tpen)
    call _ui_pattern
_ut_next:
    ld hl, #ui_x
    ld a, (hl)
    add a, #4
    ld (hl), a
    jr _ut_char
_ut_done:
    ld a, (ui_x)
    ld b, a
    ret

;; ----------------------------------------------------------------------------
;; ui_text_in / ui_text_in_big
;;   In: IY = string, B = box x, D = box width, C = y, A = pen.
;;   Draws the text centred in [B, B + D) (normal or double height: the width
;;   is the same). Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
ui_text_in::
    push af
    ld a, #1
    ld (ui_trepeat), a
    pop af
    jr _ui_text_in
ui_text_in_big::
    push af
    ld a, #2
    ld (ui_trepeat), a
    pop af
_ui_text_in:
    ld (ui_tpen), a
    push iy
    pop hl
    ld e, #0
_uti_len:
    ld a, (hl)
    or a
    jr z, _uti_len_done
    inc hl
    inc e
    jr _uti_len
_uti_len_done:
    ld a, e
    add a, a
    add a, a
    dec a                         ; text width
    ld e, a
    ld a, d
    sub e
    srl a
    add a, b
    ld b, a
    ld a, (ui_tpen)
    jr _ui_text

;; ----------------------------------------------------------------------------
;; ui_help
;;   In: IY = "LABEL:VALUE LABEL:VALUE" (NUL-terminated). Draws it on the help
;;   bar (x 6, y 186): each label up to and including ':' in yellow, each value
;;   in white; a space starts a new label. Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
ui_help::
    ld a, #HELP_X
    ld (ui_tx), a
ui_help_from_x:
    ld a, #PEN_YELLOW
    ld (ui_help_pen), a
_uh_loop:
    ld a, (iy)
    or a
    ret z
    inc iy
    ld (ui_char), a
    cp #' '
    jr nz, _uh_draw
    ld a, #PEN_YELLOW
    ld (ui_help_pen), a
    jr _uh_next
_uh_draw:
    push iy
    ld iy, #ui_char
    ld a, (ui_tx)
    ld b, a
    ld c, #HELP_Y
    ld a, (ui_help_pen)
    call ui_text
    pop iy
    ld a, (ui_char)
    cp #':'
    jr nz, _uh_next
    ld a, #PEN_WHITE
    ld (ui_help_pen), a
_uh_next:
    ld hl, #ui_tx
    ld a, (hl)
    add a, #4
    ld (hl), a
    jr _uh_loop

;; ----------------------------------------------------------------------------
;; ui_help_centred
;;   In: IY = string. Like ui_help, centred on the 148-pixel help bar.
;;   Modifies: AF, BC, DE, HL, IY.
;; ----------------------------------------------------------------------------
ui_help_centred::
    push iy
    pop hl
    ld e, #0
_uhc_len:
    ld a, (hl)
    or a
    jr z, _uhc_done
    inc hl
    inc e
    jr _uhc_len
_uhc_done:
    ld a, e
    add a, a
    add a, a
    dec a
    ld e, a
    ld a, #HELP_WIDTH
    sub e
    srl a
    add a, #HELP_X
    ld (ui_tx), a
    jr ui_help_from_x
