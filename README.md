# CATDOKU

Juego de puzles de lógica (familia Star Battle/Queens) para Amstrad CPC.

## Descripción
Catdoku es un juego de colocación de gatos en un tablero n×n dividido en regiones de color.
El objetivo: colocar n gatos, uno por región, fila y columna, sin que dos se toquen (ni en diagonal).

## Controles
- **Cursores**: mover el selector de casilla. Mantenido, repite a los 15 frames y luego cada 4.
- **RETURN**: poner un gato. Un gato no se puede quitar.
- **ESPACIO**: poner o quitar una X (casilla descartada).
- **H**: pista. Lleva el selector a la casilla de uno de los gatos que faltan, sin colocarlo.
- **ESC**: volver a la selección de nivel. La partida en curso se pierde.

## Fin de partida
- **Victoria**: con los n gatos colocados aparece "LEVEL COMPLETE!". El nivel queda completado y, si el tiempo es mejor, se guarda en `CATDOKU.SAV`.
- **Gato equivocado**: un gato en una casilla que no es de la solución termina la partida ("NO CAT THERE", "GAME OVER").
- **Tiempo**: a los 1000 segundos la partida termina ("TIME UP").

Cada nivel tiene una única solución que se obtiene por deducción, sin adivinar (ver `catdoku/doc/compendio-catdoku.md`).

## Menú
NEW GAME, CONTINUE, RULES (pantalla de reglas) y AUTO MARK.

- **NEW GAME**: si hay niveles completados, pide confirmación ("ERASE ALL PROGRESS?", RETURN sí, ESC no) y borra de `CATDOKU.SAV` los niveles completados y los mejores tiempos (AUTO MARK se conserva). Después abre la selección en el primer nivel. Sin progreso no pregunta.
- **CONTINUE**: abre la selección en el primer nivel no completado. Sale en gris y el cursor la salta mientras no haya ningún nivel completado.

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
glasnost test      # integridad del proyecto y compilación
```

## Pruebas
`tests/test_catdoku.py` contiene comprobaciones en el host (tabla de niveles, constantes) y partidas automáticas en BluePixel headless: AUTO MARK, guardado tras reiniciar, reglas, repetición de cursor, centrado de los cinco tamaños y NEW GAME/CONTINUE.

```sh
python3 -m unittest discover -s tests -v
```

Las pruebas con emulador se saltan si no encuentran BluePixel. Por defecto lo buscan junto a GlasnostFWK (`../BluePixel`); también aceptan `GLASNOST_ROOT`, `BLUEPIXEL_HEADLESS` y `BLUEPIXEL_ROMS`. El proyecto debe estar en una carpeta llamada `catdoku`, porque `glasnost build` lo exige. Con `CATDOKU_SLOW=1` también se regeneran los 200 niveles y se comparan con los del repositorio (unos 3 minutos).

## Niveles
200 niveles pregenerados: 40 por dificultad (Iniciación 5x5, Fácil 6x6, Medio 7x7, Difícil 8x8, Experto 9x9).
El progreso se guarda en `CATDOKU.SAV` en el DSK.

`generated/catdoku_levels.s` se genera con `scripts/gen_catdoku_levels.py`. Ese script llama a `catdoku/doc/generador_catdoku.py`, la implementación de referencia del compendio, con semillas fijas, y comprime cada nivel con `zx7b`. El resultado es reproducible:

```sh
python3 scripts/gen_catdoku_levels.py           # reescribe generated/catdoku_levels.s
python3 scripts/gen_catdoku_levels.py --check   # falla si cambiaría (unos 3 minutos)
```

`zx7b` se toma de `ZX7B`, de `CPCT_PATH` o de `glasnost path`.
