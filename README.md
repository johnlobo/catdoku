# CATDOKU

Juego de puzles de lógica (familia Star Battle/Queens) para Amstrad CPC.

## Descripción
Catdoku es un juego de colocación de gatos en un tablero n×n dividido en regiones de color.
El objetivo: colocar n gatos, uno por región, fila y columna, sin que dos se toquen (ni en diagonal).

## Controles
- **Cursor**: moverseleccionador
- **ENTER**: colocar/quitar gato
- **ESPACIO**: marcar celda como descartada (X)
- **H**: pista (muestra un gato no encontrado)
- **ESC**: volver al menú

## Menú
NEW GAME, CONTINUE, RULES (pantalla de reglas) y AUTO MARK.

## Tablero
Las casillas vecinas de una misma región se dibujan unidas: cada región es una sola forma y las líneas negras marcan sus fronteras.

## AUTO MARK
Opción del menú principal (RETURN la activa o desactiva; se guarda en `CATDOKU.SAV`). Al poner un gato correcto, marca con X las casillas vacías de su fila, su columna, su región y sus 8 vecinas.

## Estructura del proyecto
- `main.s` - Punto de entrada y máquina de estados
- `menu.s` - Menú principal y selección de nivel
- `game.s` - Bucle de juego, temporizador, render
- `board.s` - Lógica del tablero
- `save.s` - Guardado/carga de progreso
- `common.inc` - Constantes y definiciones compartidas
- `assets/` - Sprites (PNG) y paleta
- `generated/` - Niveles comprimidos, música y efectos

## Compilación
```sh
glasnost build
glasnost run
glasnost test
```

## Niveles
200 niveles pregenerados (40 por dificultad: Iniciación, Fácil, Medio, Difícil, Experto).
El progreso se guarda en `CATDOKU.SAV` en el DSK.