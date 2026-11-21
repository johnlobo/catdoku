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
Cada casilla mide 16x16 píxeles: 15x15 del color de su región y 1 de separación. Entre casillas de la misma región la separación toma el color de la región con una raya de 2 píxeles en el centro (blanca en las regiones oscuras, negra en las claras); entre regiones distintas es negra. El cursor son cuatro esquinas blancas dentro de la casilla. Un marco naranja rodea el tablero.

## Gráficos
Las pantallas siguen `docs/maqueta.png` (menú, selección de nivel y partida), que está dibujada a doble tamaño sobre la rejilla del CPC: cada pantalla son 156x196 píxeles de modo 0 y 13 colores del CPC. La única diferencia buscada es ":" donde la maqueta escribe "=". Reglas, confirmación de NEW GAME, nivel completado, tiempo agotado, partida perdida y guardado usan el mismo marco, las mismas cajas y la misma franja de ayuda.

- `assets/src/ui_menu.png`, `ui_levels.png`, `ui_game.png`, `ui_plain.png`: fondos de 160x200 sacados de la maqueta, sin lo que dibuja el código (cajas de opciones, dificultad, BEST, textos con ":", tablero). Se guardan como volcados de pantalla comprimidos con ZX7B (1,3 KB los cuatro) y se descomprimen directamente en la memoria de vídeo.
- `assets/src/font.png`: la fuente de la maqueta, 3x6 píxeles por carácter (ASCII 32..95). V, ":", "!" y "?" no salen en la maqueta y están dibujados en el mismo estilo.
- `assets/src/sprites.png`: gato y X de 16x16.
- `assets/palette.json`: la paleta, copiada también en `main.s` (colores hardware) y en `save.s` (colores firmware mientras AMSDOS escribe); una prueba comprueba que coinciden.
- `ui.s`: fondos, rectángulos y cajas con precisión de píxel, texto con la fuente 3x6 y la franja de ayuda.

`generated/catdoku_ui.s` se genera con `scripts/gen_ui.py` (`--check` falla si cambiaría).

## AUTO MARK
Opción del menú principal (RETURN la activa o desactiva; se guarda en `CATDOKU.SAV`). Al poner un gato correcto, marca con X las casillas vacías de su fila, su columna, su región y sus 8 vecinas.

## Estructura del proyecto
- `main.s` - Punto de entrada y máquina de estados
- `menu.s` - Menú principal y selección de nivel
- `game.s` - Bucle de juego, temporizador, render
- `board.s` - Lógica del tablero
- `save.s` - Guardado/carga de progreso
- `ui.s` - Fondos, cajas y texto con la fuente de la maqueta
- `common.inc` - Constantes y definiciones compartidas
- `assets/` - Sprites, fondos, fuente (PNG) y paleta
- `generated/` - Niveles y fondos comprimidos, fuente, música y efectos
- `docs/maqueta.png` - Diseño de referencia de las pantallas

## Compilación
```sh
glasnost build
glasnost run
glasnost test      # integridad del proyecto y compilación
```

## Pruebas
`tests/test_catdoku.py` contiene comprobaciones en el host (tabla de niveles, constantes, las tres copias de la paleta, `generated/catdoku_ui.s` al día) y partidas automáticas en BluePixel headless: menú y selección de nivel iguales píxel a píxel a la maqueta (salvo los ":"), la huella que sigue a la selección, niveles completados en verde solo en su dificultad, AUTO MARK, guardado tras reiniciar, reglas, repetición de cursor, centrado de los cinco tamaños y del tiempo, NEW GAME/CONTINUE y la migración de un `CATDOKU.SAV` de versión 1.

```sh
python3 -m unittest discover -s tests -v
```

Las pruebas con emulador se saltan si no encuentran BluePixel. Por defecto lo buscan junto a GlasnostFWK (`../BluePixel`); también aceptan `GLASNOST_ROOT`, `BLUEPIXEL_HEADLESS` y `BLUEPIXEL_ROMS`. El proyecto debe estar en una carpeta llamada `catdoku`, porque `glasnost build` lo exige. Con `CATDOKU_SLOW=1` también se regeneran los 200 niveles y se comparan con los del repositorio (algo más de un minuto).

## Niveles
200 niveles pregenerados: 40 por dificultad (Iniciación 5x5, Fácil 6x6, Medio 7x7, Difícil 8x8, Experto 9x9).
El progreso se guarda en `CATDOKU.SAV` en el DSK. Un fichero de la versión 1 (los niveles anteriores a esta curva) pierde al cargarse los niveles completados y los tiempos, porque se refieren a otros tableros, y conserva AUTO MARK.

Técnica más difícil que necesita cada nivel (T1 casillas forzadas, T2 y T3 palomar con una o con dos o tres unidades, T4 probar y descartar):

| Dificultad | Tablero | Técnica | Usos de T4 |
|---|---|---|---|
| Iniciación | 5x5 | T1-T2 | 0 |
| Fácil | 6x6 | T2-T3 | 0 |
| Medio | 7x7 | T3 | 0 |
| Difícil | 8x8 | T4 | 1-10 |
| Experto | 9x9 | T4 | 11 o más |

Dentro de cada dificultad, los 40 niveles van de más fácil a más difícil: primero por usos de T4, luego por técnica y luego por número de pasos.

`generated/catdoku_levels.s` se genera con `scripts/gen_catdoku_levels.py`. Ese script importa `catdoku/doc/generador_catdoku.py`, la implementación de referencia del compendio, acepta cada tablero con las bandas de la tabla (`BANDS`) en lugar de las del compendio, usa semillas fijas y comprime cada nivel con `zx7b`. El resultado es reproducible (algo más de un minuto):

```sh
python3 scripts/gen_catdoku_levels.py           # reescribe generated/catdoku_levels.s
python3 scripts/gen_catdoku_levels.py --check   # falla si cambiaría
```

`zx7b` se toma de `ZX7B`, de `CPCT_PATH` o de `glasnost path`.
