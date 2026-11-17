# Catdoku Amstrad CPC Plan

## Project Overview
Catdoku logic puzzle game for Amstrad CPC using GlasnostFWK framework. Based on 5 difficulty levels with 200 pre-generated levels (40 per difficulty). Uses ZX7B compression, AKG audio, and 8x8 sprites.

## Architecture Decisions

### 1. File Structure (projects/catdoku/)
- `main.s` - Entry point, FWK init, audio management, state machine
- `menu.s` - Main menu + level selection grouped by difficulty
- `game.s` - Game loop, input, timer, render, victory
- `board.s` - Core board logic (load, set_cell, check_win, hint)
- `save.s` - Read/write CATDOKU.SAV (creates if missing)
- `common.inc` - Constants, paleta fija, estados del juego
- `generated/catdoku_levels.s` - 200 niveles ZX7B comprimidos (40 por dificultad)
- `generated/catdoku_music.s` - Música AKG (menú + juego)
- `generated/catdoku_sfx.s` - Efectos de sonido AKG
- `assets/` - PNGs: cat.png, mark.png, cell.png, cursor.png + assets.json
- `glasnost.manifest.json` - Manifest del proyecto

### 2. Level Design (200 niveles pregenerados)
- Distribución: 40 niveles por dificultad
- Niveles 1-40: Dificultad 1 (Iniciación), n=5
- Niveles 41-80: Dificultad 2 (Fácil), n=6
- Niveles 81-120: Dificultad 3 (Medio), n=7
- Niveles 121-160: Dificultad 4 (Difícil), n=8
- Niveles 161-200: Dificultad 5 (Experto), n=9
- Cada nivel: header (6 bytes) + grid n² + lista de gatos n*2 bytes
- Total comprimido ZX7B: ~8 KB para los 200 niveles

### 3. Audio (AKG integrado)
- Usa `audio/akg.s` del framework
- `fwk_audio_init_music(HL=song, A=subsong)` para música
- `fwk_audio_init_sfx(HL=sfx_table)` para efectos
- `fwk_audio_start()` conecta IRQ a 50 Hz
- `fwk_audio_stop()` para cambiar entre menú/juego
- `fwk_audio_play_sfx(A=id, B=vol_inv, C=canal)` para SFX
- Música de menú: subsong 0 de song.s de examples/audio
- Música de juego: subsong 1 (distinta atmósfera)
- Efectos SFX (índices):
  - 0: Gato colocado (canal 0, vol alto)
  - 1: Marca X (canal 1, vol medio)
  - 2: Movimiento inválido (canal 2, vol bajo)
  - 3: Victoria (canal 0, vol alto)
  - 4: Navegación menú (corto, canal 1)

### 4. Sprites (8x8 píxeles - modo Mode 0 vertical)
- Los sprites son más altos que anchos por la geometría de Mode 0 (160×200, 16 colores)
- Sprites del tablero:
  - `cat.png` → sprite gato (colocado en celda)
  - `mark.png` → sprite X (marcar celda descartada)
  - `cell.png` → sprite celda vacía (color según región)
  - `cursor.png` → sprite cursor (recoloreado con `fwk_sprite_draw_masked_recolor`)
- API de dibujo:
  - `fwk_sprite_draw_masked` para gato y marca (color clave = pen 0)
  - `fwk_sprite_draw_masked_recolor` para cursor (sustituye pen por color)
  - `fwk_video_get_ptr` → obtener puntero VRAM por celda
- Assets en `assets/` convertidos a `.inc` por el generador del framework

### 5. Guardado (CATDOKU.SAV)
- Formato: cabecera "CATDOKU" (7 bytes) + entradas por nivel
- Cada entrada: byte level_id (0..199) + dword tiempo_segundos (32-bit)
- Si el fichero no existe al inicio, se crea automáticamente con solo la cabecera
- Al completar un nivel, `save_write(level_id, tiempo_segundos)` sobrescribe/añade entrada
- Lectura en `save_load()` al arrancar el juego

### 6. Input y Controles (fwk_input bindings)
- Tabla de bindings en `common.inc`:
  - Cursor arriba/abajo/izquierda/derecha: moverseleccionador
  - ENTER: colocar gato (`board_set_cell` type=1)
  - ESPACIO: marcar X (`board_set_cell` type=2)
  - H: pista (`board_get_hint`)
  - ESC: volver al menú
- Lectura: `fwk_input_init`, `fwk_input_set_bindings`, `fwk_input_update`
- Estados: `fwk_input_pressed`, `fwk_input_held`, `fwk_input_released`
- El temporizador acumula `fwk_system_frame_count / 50` (PAL = 50 fps)

### 7. Bucle de Estados (main.s)
```
ESTADOS: MENU, LEVEL_SELECT, GAME, VICTORY, SAVE

MAIN:
  call fwk_project_init
  call fwk_video_init
  call fwk_text_init
  call cpct_setPalette_asm          ; paleta fija, nunca cambia
  call fwk_audio_init_music         ; música menú
  call fwk_audio_init_sfx           ; efectos
  call save_load                    ; lee CATDOKU.SAV (crea si falta)
  ld a, STATE_MENU
  ld (game_state), a

bucle_principal:
  call fwk_system_wait_frame
  ld a, (game_state)
  cp STATE_MENU
  jr z, menu_update
  cp STATE_LEVEL_SELECT
  jr z, level_select_update
  cp STATE_GAME
  jr z, game_update
  cp STATE_VICTORY
  jr z, victory_update

menu_update:  ; menu.s
  ; input: cursor/enter
  ; opciones: Nueva partida, Continuar, Salir
  ...

level_select_update:  ; level_select.s
  ; muestra niveles agrupados por dificultad
  ; [X] = completado (según save.s)
  ; enter carga nivel -> board_load_level(id) -> STATE_GAME
  ...

game_update:  ; game.s
  ; input: cursor, ENTER=CAT, SPACE=MARK, H=HINT
  ; board_set_cell(cursor_row, cursor_col, type)
  ; fwk_audio_play_sfx para efectos
  ; timer_update: segundos = fwk_system_frame_count / 50
  ; game_render: tablero + HUD tiempo
  ; board_check_win -> si 1: guarda tiempo, STATE_VICTORY
  ...

victory_update:  ; game.s o victory screen
  ; muestra "Nivel # completado! Tiempo: MM:SS"
  ; fwk_audio_play_sfx victoria
  ; espera tecla -> STATE_LEVEL_SELECT
  ...
```

### 8. Board API (board.s - toda la lógica del tablero)
```asm
; board_load_level(level_id)  ; A = level_id 0..199
;   Descomprime nivel desde catdoku_levels.s usando fwk_zx7b_unpack
;   Extrae header + grid n² + lista de gatos
;   Inicializa found_cnt=0, found bitmask (13 bytes max)
;   Setea catdoku_n, catdoku_num_cats, catdoku_num_colours

; board_get_cell(row, col)    ; B=row, C=col
;   Devuelve A = color/región 0..num_colours-1

; board_set_cell(row, col, type)  ; B=row, C=col, D=type
;   type: 0=EMPTY (quitar), 1=CAT (colocar/quitar gato), 2=MARK (X descartada)
;   Si type=CAT y coincide con gato no encontrado -> found=1, found_cnt++
;   Z=1 si colocado gato válido de la solución, Z=0 si no

; board_check_win()            ; A = 1 si found_cnt == num_cats
;   Compara gatos puestos contra lista solución (no guarda solución aparte)

; board_get_hint()             ; HL = puntero a (row, col) primer gato no encontrado
;   A = 0 si no quedan (ya ganó)
```

### 9. Paleta Fija (common.inc + main.s)
- Una paleta de 16 colores hardware, declarada una sola vez en `main.s`
- `cpct_setPalette_asm` con los valores del generador_catdoku.py
- Nunca cambia durante la partida
- Usada tanto para renderizar celdas/sprites como para el HUD

### 10. Pipeline de Generación (build time - scripts/)
- `scripts/gen_catdoku_levels.py`:
  1. Llama a `catdoku/generador_catdoku.py` 200 veces (semillas distintas)
  2. Convierte cada JSON al formato binario (header + grid + cats)
  3. Comprime cada nivel con ZX7B (herramienta CPCTelera)
  4. Genera `generated/catdoku_levels.s` con:
     - Tabla de 200 entradas: (offset_packed, size_packed, size_unpacked)
     - Datos comprimidos concatenados (.db ...)
     - `CATDOKU_NUM_LEVELS .equ 200`
     - `CATDOKU_DECOMP_BUFFER_SIZE .equ 128`
  5. Genera `generated/catdoku_music.s` y `generated/catdoku_sfx.s` a partir de los archivos AKG

### 11. Manifest Corregido (glasnost.manifest.json)
```json
{
  "modules": [
    "core/system.s",
    "core/input.s",
    "video/video.s",
    "video/sprite.s",
    "video/transparency.s",
    "ui/text.s",
    "ui/window.s",
    "resources/zx7b.s",
    "resources/disk.s",
    "audio/akg.s",
    "game/board.s",
    "game/save.s",
    "generated/catdoku_levels.s",
    "generated/catdoku_music.s",
    "generated/catdoku_sfx.s"
  ],
  "game_sources": [
    "main.s", "menu.s", "game.s", "common.inc", "generated/project.inc"
  ]
}
```
(Nada de ECS, nada de extensiones physics/tilemap)

### 12. Qué NO se incluye (excluido deliberadamente)
- Módulo ECS completo (ecs_manager, ecs_behavior, etc.) - añade ~3-4 KB sin beneficio
- Extensiones physics_8_8, physics_platform, tilemap, tilemap_render
- Audio AKG alternativo o compresión propia (usamos el incluido)
- Conversión binaria→ASCII para el timer (usamos fwk_text_draw_small_u8/digit)

### 13. Próximos Pasos (cuando cambie de agente)
1. Generar los 200 niveles con `scripts/gen_catdoku_levels.py`
2. Crear los 4 PNGs de sprites (cat, mark, cell, cursor) + assets.json
3. Escribir `common.inc` con constantes, paleta, bindings
4. Escribir `board.s` con la API completa
5. Escribir `save.s` con lectura/escritura AMSDOS
6. Escribir `menu.s` con selección de nivel por dificultad
7. Escribir `game.s` con bucle, timer, render, victoria
8. Probar carga de niveles, save/load, audio, victoria
