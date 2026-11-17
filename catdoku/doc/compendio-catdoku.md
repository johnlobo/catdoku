# Catdoku

## Compendio de reglas y algoritmo de generación con cinco niveles de dificultad

**Versión 1.0** · documento técnico + implementación de referencia (`generador_catdoku.py`)

---

## Resumen

Catdoku es un puzle de lógica de la familia *Star Battle* / *Queens*: un tablero
cuadrado dividido en regiones de color en el que hay que colocar exactamente un
gato por región, por fila y por columna, sin que dos gatos se toquen (ni en
diagonal). No hay pistas numéricas: toda la información está en la forma de las
regiones.

Este documento tiene cuatro partes:

1. **Compendio de reglas** (secciones 1–7): qué es el juego, las cuatro reglas
   básicas, sus consecuencias, los casos límite que suelen generar dudas y las
   técnicas de deducción que usa un jugador humano.
2. **Modelo formal** (secciones 8–10): definiciones, equivalencia con
   permutaciones «sin reyes» y relación entre unicidad y deducibilidad.
3. **Algoritmo de generación** (secciones 11–21): cadena completa (solución →
   partición → oráculo de unicidad → motor de deducción humana → pulido →
   puntuación → selección), definición operativa de los cinco niveles de
   dificultad, complejidad y rendimiento.
4. **Validación** (secciones 22–24): autotest, banco de pruebas, limitaciones
   conocidas y extensiones.

El apéndice incluye tableros reales generados por la implementación para cada
nivel, el formato JSON y la tabla de conteo de configuraciones.

---

# Parte I — Compendio de reglas

## 1. Qué es Catdoku

Catdoku es un puzle de colocación con temática felina. El tablero es una
cuadrícula de `n × n` casillas, dividida en `n` regiones conexas coloreadas
(habitualmente con una letra o un color cada una). Cada región tiene `n`
casillas de media, pero los tamaños pueden variar mucho.

El objetivo es colocar `n` gatos, uno por región, uno por fila y uno por
columna, de modo que ningún par de gatos se toque.

El juego pertenece a la misma familia que:

- ***Star Battle*** (dos estrellas por fila, columna y región; también existe la
  variante de una estrella),
- ***Queens*** / *LinkedIn Queens* (una reina por fila, columna y región, sin
  reinas que se ataquen),
- ***Meowdoku***, ***Pawdoku***, ***WangDoKu*** y otras variantes temáticas.

La diferencia entre «reinas» y «gatos» es sólo de fraseo: en la variante de una
sola pieza por unidad, dos reinas se atacan si comparten fila, columna o
diagonal; dos gatos se «tocan» si comparten fila, columna o diagonal **de una
casilla contigua**. La restricción es la misma: nada de piezas en las ocho
casillas vecinas.

## 2. Las cuatro reglas

Un tablero de Catdoku de tamaño `n` se resuelve cuando se cumplen
simultáneamente:

| # | Regla | Formulación precisa |
|---|-------|---------------------|
| **R1** | Un gato por región | Para cada región `R`, exactamente una casilla de `R` contiene gato. |
| **R2** | Un gato por fila | Para cada fila `f`, exactamente una casilla de `f` contiene gato. |
| **R3** | Un gato por columna | Para cada columna `c`, exactamente una casilla de `c` contiene gato. |
| **R4** | Sin contacto | Si dos casillas con gato son distintas, no pueden ser vecinas: `máx(|Δfila|, |Δcol|) ≥ 2`. |

Como el tablero tiene `n` filas, `n` columnas y `n` regiones, cada una de R1,
R2 y R3 fija por sí sola el número total de gatos en `n`; R4 no cuenta piezas,
sólo prohíbe vecindades. Las cuatro son necesarias como restricciones: R1–R3
reparten los gatos y R4 los separa.

**Condición de victoria.** El tablero está resuelto cuando las `n` casillas
marcadas cumplen R1–R4. En la mayoría de implementaciones no se exige acertar la
solución concreta: cualquier configuración que cumpla las cuatro reglas se acepta.
Por eso un buen puzle debe tener **solución única** (sección 10).

## 3. Reglas derivadas y consecuencias

Las siguientes afirmaciones se deducen de R1–R4 y son las que un jugador usa
constantemente. No son reglas nuevas: son atajos válidos.

- **D1 — Conteo.** Hay exactamente `n` gatos en un tablero `n × n`.
- **D2 — Exclusión por adyacencia.** Si hay un gato en `(f, c)`, las ocho
  casillas vecinas (incluidas las cuatro diagonales) quedan descartadas.
- **D3 — Exclusión por unidad.** Si hay un gato en `(f, c)`, ninguna otra casilla
  de la fila `f`, de la columna `c` ni de la región de `(f, c)` puede tener gato.
- **D4 — Cuadre de filas y regiones.** Si `k` regiones sólo tienen casillas
  posibles en `k` filas, entonces esas `k` filas están «ocupadas» por esas `k`
  regiones: ninguna otra región puede poner gato en ellas.
- **D5 — Simetría del cuadre.** Lo mismo con columnas: `k` regiones confinadas a
  `k` columnas agotan esas columnas.
- **D6 — Cuadre inverso.** Si `k` filas sólo tienen casillas posibles en `k`
  regiones, esas `k` regiones quedan agotadas por esas filas.
- **D7 — Conteo de casillas.** Una región con una sola casilla posible fija su
  gato; una fila con una sola casilla posible fija el suyo; etc. (caso particular
  de D3–D6 con `k = 1`).

D2–D3 son «propagación inmediata». D4–D6 son «intersecciones» y «palomar».

## 4. Notación y convenios

- Filas y columnas se numeran **desde 1**, de arriba abajo y de izquierda a
  derecha.
- La casilla de la fila `f` y la columna `c` se escribe `(f, c)`.
- Las regiones se etiquetan con letras: `A`, `B`, `C`, … La región `k`-ésima
  (0-indexada internamente) se muestra como la letra `LETRAS[k]`.
- En los tableros de este documento, `@` marca un gato en la solución y cada
  letra marca la región de esa casilla.
- `n` es siempre el lado del tablero; hay `n` regiones y `n` gatos.

Ejemplo de lectura (nivel 1, `n = 5`):

```
    1 2 3 4 5
 1  D D D @ D
 2  @ C D D D
 3  A C @ D D
 4  A C C E @
 5  B @ C C C
```

La región `D` contiene las celdas `(1,1)`, `(1,2)`, `(1,3)`, `(1,4)`, `(1,5)`,
`(2,3)`, `(2,4)`, `(2,5)`, `(3,4)` y `(3,5)`: 10 casillas, y su gato es el de
`(1,4)`. La región `A` es una tira vertical de tres casillas en la primera
columna —`(2,1)`, `(3,1)`, `(4,1)`— y su gato es el de `(2,1)`; la región `B`
es una tira horizontal de dos casillas, `(5,1)` y `(5,2)`, con gato en `(5,2)`.
Las regiones alargadas de una sola fila o columna son las que hacen visibles las
intersecciones de T2 (sección 6).

## 5. Casos límite y aclaraciones

Las discusiones sobre reglas en esta familia de juegos giran casi siempre en
torno a los mismos puntos. Aquí están resueltos de forma explícita.

1. **«Tocarse» incluye las diagonales.** Dos gatos en `(2,2)` y `(3,3)` se
   tocan. Dos gatos en `(2,2)` y `(4,4)` **no** se tocan: la diagonal larga está
   permitida; lo prohibido es compartir una casilla vecina.
2. **«Vecino» significa las ocho casillas del entorno de Moore**, no las cuatro
   ortogonales. R4 usa `máx(|Δfila|, |Δcol|) ≥ 2`.
3. **Una fila vacía es un error, no una variante.** Cada fila debe tener
   exactamente un gato. «Al menos uno» no basta (sería imposible: hay `n` gatos).
4. **Las regiones son conexas por aristas** (no por vértices). Una región en
   forma de dos bloques unidos sólo por una esquina no es válida en la
   implementación de referencia: la conectividad se comprueba con BFS de 4
   vecinos.
5. **Las regiones pueden ser de tamaños muy distintos**, pero no de tamaño cero.
   Un tamaño 1 es legal (y equivale a regalar ese gato); la implementación lo
   prohíbe por calidad (sección 16).
6. **El borde del tablero no es un vecino.** Un gato en la esquina sólo elimina
   tres casillas del tablero.
7. **No hay pistas numéricas, casillas bloqueadas ni «muros».** Toda la
   restricción viene de la partición en regiones y de R1–R4.
8. **Los gatos no se mueven ni se pueden repetir.** Son `n` piezas idénticas;
   la solución es un conjunto de `n` casillas.
9. **La solución no tiene por qué ser simétrica** ni estar en la diagonal
   principal.
10. **Un tablero con solución única pero no deducible es legal, pero injusto.**
    Se puede resolver por prueba y error, y el jugador lo percibe como roto. Por
    eso el generador exige además que exista una cadena de deducción humana
    (secciones 6 y 10).
11. **Simetría de la partición.** La partición no necesita ser simétrica. De
    hecho, las particiones muy regulares suelen tener muchas soluciones
    (sección 21).
12. **Empates y marcas.** Marcar una casilla como «descartada» (una `X`) no es
    parte de la solución, pero es la técnica de trabajo estándar: reduce el
    espacio de búsqueda del jugador sin comprometerse con un gato.

## 6. Técnicas humanas: los cuatro niveles de razonamiento

El generador mide la dificultad con un **modelo explícito de razonamiento
humano**. Las técnicas están ordenadas de menos a más costosas. Un tablero es de
nivel `t` si el motor lo resuelve usando como máximo las técnicas `T1…Tt`.

### T1 — Candidato único

Si en una fila, columna o región sólo queda **una** casilla compatible con todo
lo colocado, ahí va el gato.

> Ejemplo: en el tablero anterior, la región `B` está formada por `(5,1)` y
> `(5,2)`. En cuanto la columna 1 recibe su gato en `(2,1)`, la casilla `(5,1)`
> queda descartada y `B` se resuelve: su gato sólo puede estar en `(5,2)`.

Esta técnica incluye la «eliminación por adyacencia» D2: al colocar un gato se
marcan sus ocho vecinos.

### T2 — Intersección región ↔ línea (*pointing*)

Si todas las casillas posibles de una región están en una misma fila (o
columna), el gato de esa región está en esa fila; por tanto el gato de esa fila
está en esa región. Se eliminan las demás casillas de esa fila (o columna).

### T3 — Palomar de orden 2 y 3

Si `k` regiones (con `k = 2` o `k = 3`) sólo tienen casillas posibles en `k`
filas, esas filas quedan agotadas por esas regiones. Se eliminan las casillas de
esas filas que pertenecen a otras regiones. Y simétricamente con columnas y con
el cuadre inverso (D6).

> Esta es la técnica que separa los puzles «fáciles» de los «medios»: requiere
> mirar dos o tres unidades a la vez.

### T4 — Reducción al absurdo de un paso

Se elige una casilla candidata `x`, se **supone** que tiene gato y se propaga
T1–T3. Si aparece una contradicción (una fila/columna/región sin casilla
posible, o dos gatos en la misma unidad), `x` no puede tener gato: se descarta.
Si la suposición no contradice nada, se prueba la hipótesis complementaria («`x`
está vacía») y, si esa también contradice, se coloca el gato.

Es el razonamiento de «si pusiera aquí un gato, esta región se quedaría sin
sitio; luego aquí no va». No requiere adivinar: cada hipótesis se refuta
formalmente.

### Lo que queda fuera del modelo

Un jugador experto también usa técnicas de orden superior (palomar de orden 4+,
cadenas de contradicciones de dos niveles, patrones de «par de casillas»). El
motor se detiene en T4 a propósito: un tablero que necesite más que T4 se
considera «demasiado» para los cinco niveles de este documento.

## 7. Variantes

| Variante | Cambio | Efecto |
|----------|--------|--------|
| **Dos estrellas** (*Star Battle* clásico) | 2 piezas por fila, columna y región | Cambia por completo el espacio de soluciones; este documento no la cubre. |
| **Tamaños** | `n = 4 … 13` | `n = 4` es trivial (2 soluciones posibles sin regiones); a partir de `n = 9` la generación se vuelve cara (sección 21). |
| **Regiones con nombre/color** | etiquetas en vez de letras | Sólo presentación. |
| **Modo diario** | semilla = fecha | La semilla hace el tablero reproducible (ver CLI). |
| **Pistas opcionales** | revelar un gato | Rompe la elegancia pero ayuda a principiantes; no forma parte de las reglas. |

---

# Parte II — Modelo formal

## 8. Definiciones

Sea `n ≥ 4` el lado del tablero.

- **Celda**: par `(f, c)` con `1 ≤ f, c ≤ n`. Hay `n²` celdas.
- **Partición**: función `reg : {1..n}² → {0..n−1}` tal que cada nivel
  `k` tiene al menos una celda, la preimagen `reg⁻¹(k)` es **conexa por aristas**
  y hay exactamente `n` niveles no vacíos.
- **Configuración**: conjunto `S` de `n` celdas.
- **Configuración válida** para `reg`: cumple R1–R4.
- **Solución**: configuración válida. **Solución única**: existe exactamente una.

Una configuración `S` se representa por una permutación `π` de `{1..n}`:
`π[c] = f` significa que el gato de la columna `c` está en la fila `f`.

## 9. Equivalencia con permutaciones «sin reyes»

**Proposición.** `S` cumple R2–R4 si y sólo si su permutación asociada `π`
satisface `|π[c] − π[c+1]| ≥ 2` para todo `c`.

*Demostración.* R2 y R3 dicen que `π` es una permutación (una fila por columna,
sin repetir fila). Para R4: dos gatos en columnas `c < c'` se tocan si
`|c − c'| = 1` y `|π[c] − π[c']| ≤ 1`. Si `|c − c'| ≥ 2` no pueden ser vecinos.
Por tanto basta comprobar los pares de columnas consecutivas. ∎

R1 (una por región) es la única restricción que depende de `reg`; sin ella, el
problema es puramente «permutaciones con diferencia ≥ 2 entre términos
consecutivos».

### 9.1 Cuántas configuraciones válidas hay sin regiones

Sin la restricción de regiones, el número de configuraciones válidas es el de
permutaciones de `n` con `|π[c] − π[c+1]| ≥ 2`. Se calcula exactamente por
programación dinámica sobre el conjunto de filas usadas:

```
f(mask, última) = Σ_{v ∉ mask, |v − última| ≥ 2} f(mask ∪ {v}, v)
```

| `n` | Configuraciones válidas |
|----:|------------------------:|
| 4 | 2 |
| 5 | 14 |
| 6 | 90 |
| 7 | 646 |
| 8 | 5 242 |
| 9 | 47 622 |
| 10 | 479 306 |
| 11 | 5 296 790 |
| 12 | 63 779 034 |
| 13 | 831 283 558 |

Esta tabla es la razón por la que la partición en regiones es imprescindible:
con `n = 10` hay casi medio millón de configuraciones legales y hay que dejar
una sola.

## 10. Unicidad y deducibilidad

**Definición (unicidad).** `reg` es *única* si `|{S : S válida para reg}| = 1`.

**Definición (deducibilidad).** `reg` es *deducible a techo `t`* si el motor de
la sección 17 resuelve el tablero usando sólo T1…Tt.

**Teorema (solidez).** Si el motor resuelve un tablero, el tablero tiene solución
única.

*Idea.* Todas las reglas de T1–T4 son **sólidas**: eliminan casillas que no
pueden contener gato en *ninguna* solución, o colocan gatos que están en *todas*
las soluciones. Por inducción, el conjunto de soluciones no cambia tras cada
paso. Si el motor termina con una configuración completa y consistente, el
conjunto de soluciones es exactamente esa configuración: cardinal 1. ∎

El recíproco **es falso**: hay tableros con solución única que ningún humano
resuelve sin probar hipótesis largas. Esa brecha —«única pero injusta»— es el
motivo de que el generador no se conforme con la unicidad.

Corolario práctico: si el motor resuelve, no hace falta llamar al oráculo de
unicidad. La implementación llama a ambos porque el oráculo es la referencia
independiente y sirve de test cruzado.

---

# Parte III — Algoritmo de generación

## 11. Visión general

La generación es un **muestreo con rechazo** sobre particiones. Cada iteración
produce un candidato completo y lo somete a una cadena de filtros; sólo los que
pasan todos se aceptan.

```
            ┌─────────────────┐
            │ 1. solución S    │  permutación con |Δ| ≥ 2
            └────────┬────────┘
                     ▼
            ┌─────────────────┐
            │ 2. partición reg │  bosque aleatorio con 1 semilla por región
            └────────┬────────┘
                     ▼
            ┌─────────────────┐
            │ 3. estructura    │  n regiones conexas, 1 gato por región
            └────────┬────────┘
                     ▼
            ┌─────────────────┐
            │ 4. oráculo       │  ¿exactamente 1 solución?
            └────────┬────────┘     no → descartar
                     ▼ sí
            ┌─────────────────┐
            │ 5. pulido        │  fuera regiones de tamaño 1
            └────────┬────────┘
                     ▼
            ┌─────────────────┐
            │ 6. motor T1–T4   │  techo mínimo, pasos, perfil
            └────────┬────────┘
                     ▼
            ┌─────────────────┐
            │ 7. banda nivel   │  ¿cumple (n, techo, pasos)?
            └────────┬────────┘     no → descartar
                     ▼ sí
                 aceptar
```

La clave del diseño es que **la unicidad se comprueba, no se construye**: en
lugar de intentar esculpir una partición única (difícil y frágil), se generan
particiones baratas y se descartan las ambiguas. El coste lo determina la
probabilidad de que una partición aleatoria sea única, que se mide en la
sección 21.

## 12. Paso 1 — Generar la solución

Se construye una permutación aleatoria con `|π[c] − π[c+1]| ≥ 2` por
backtracking con orden aleatorio de filas candidatas:

```
función solución(n, rng):
    π ← []
    usado ← [falso]·n
    función extender():
        si |π| = n: devolver cierto
        para v en barajar(0..n−1):
            si usado[v] o (π ≠ [] y |v − π[último]| < 2): continuar
            usado[v] ← cierto; π.append(v)
            si extender(): devolver cierto
            π.pop(); usado[v] ← falso
        devolver falso
    extender()
    devolver π
```

Como existen configuraciones válidas para todo `n ≥ 4` (tabla de 9.1), el
backtracking nunca falla en la práctica; el orden aleatorio evita el sesgo hacia
las soluciones «en zigzag» que produce un orden ascendente.

## 13. Paso 2 — Partición en regiones: bosque aleatorio restringido

Se parte de `n²` celdas aisladas, cada una su propia componente. Las `n` celdas
de la solución son **semillas**: cada componente puede contener como mucho una
semilla. Se van fusionando componentes por aristas del retículo hasta quedarse
con exactamente `n` componentes, una por semilla.

Es un **Kruskal aleatorio con una restricción de color**:

```
función partición(n, π, rng):
    padre ← identidad sobre n² celdas        # union-find
    tamaño ← [1]·n²
    semillas ← [0]·n²
    para c en 0..n−1: semillas[π[c]·n + c] ← 1

    unir(a, b):
        ra, rb ← hallar(a), hallar(b)
        si ra = rb o semillas[ra] + semillas[rb] > 1: devolver falso
        unir por tamaño; devolver cierto

    aristas ← [(celda, vecina derecha/abajo)]
    necesarias ← n² − n
    mientras fusiones < necesarias:
        barajar(aristas)
        para (a, b) en aristas:
            si unir(a, b): fusiones += 1
            si fusiones = necesarias: romper
        si no hubo ninguna fusión: romper          # no debería ocurrir

    reg ← etiqueta de la componente de cada celda
    reetiquetar para que la región de la semilla de la columna c sea c
    devolver reg
```

**Por qué funciona.** Un bosque con `n²` vértices y `n` componentes tiene
`n² − n` aristas. La restricción «como mucho una semilla por componente»
garantiza que las `n` componentes finales contienen exactamente una semilla cada
una, es decir, R1 se cumple por construcción y la solución `π` **es** una
solución del tablero. La conectividad también es automática: cada componente es
un árbol.

**Por qué se reetiqueta.** El etiquetado interno de union-find es arbitrario; se
renombra para que la región `k` sea la de la semilla de la columna `k`. Esto
hace que el tablero sea comparable entre ejecuciones y que la solución sea
legible en orden de columnas.

**Sesgo conocido.** La coalescencia aleatoria produce tamaños muy desiguales:
una componente tiende a «tragarse» el tablero. Esto es a la vez un problema de
estética y la fuente de la unicidad (las regiones pequeñas son restricciones
fuertes). El filtro de tamaño máximo `TOPE_REGION = 2.5` lo acota; la sección 23
lo discute.

## 14. Paso 3 — Validación estructural

Antes de gastar tiempo en el oráculo se comprueba, en `O(n²)`:

1. todas las celdas tienen región;
2. aparecen exactamente las `n` regiones;
3. cada región es conexa (BFS de 4 vecinos);
4. cada región contiene exactamente una celda de `π` (R1);
5. `π` cumple R4 (`|π[c] − π[c+1]| ≥ 2`).

Los puntos 1–4 son invariantes del paso 2, pero la comprobación es barata y
protege contra errores de implementación.

## 15. Paso 4 — Oráculo de unicidad

Se enumeran las soluciones por backtracking **por filas** con dos máscaras de
bits (columnas usadas y regiones usadas). Para la fila `f`:

- se elige una columna `c` no usada,
- `|c − c_anterior| ≥ 2` (R4 con la fila anterior),
- la región `reg[f][c]` no está usada (R1).

```
función enumerar(reg, límite):
    soluciones ← []
    función buscar(f, cols, regs, c_ant):
        si |soluciones| ≥ límite: volver
        si f = n: soluciones.append(copiar(actual)); volver
        para c en 0..n−1:
            si cols tiene c, o |c − c_ant| < 2: continuar
            si regs tiene reg[f][c]: continuar
            actual.append((f, c))
            buscar(f+1, cols ∪ {c}, regs ∪ {reg[f][c]}, c)
            actual.pop()
    buscar(0, ∅, ∅, −1)
    devolver soluciones
```

Se corta en `límite = 2`: basta saber si hay una o más de una. La poda por
región es lo que hace que la enumeración sea barata pese a que el espacio sin
regiones sea enorme (tabla 9.1). En la práctica tarda microsegundos para
`n ≤ 10`.

**Complejidad.** En el peor caso `O(n!)`, pero con la doble poda el árbol tiene
profundidad `n` y un factor de ramificación efectivo pequeño. En la práctica el
oráculo tarda microsegundos para `n ≤ 10`; el coste real del generador está en
el número de particiones que hay que muestrear (sección 21), no en enumerar.

## 16. Paso 5 — Pulido de regiones

Dos defectos de legibilidad se corrigen aquí:

1. **Regiones de una sola celda.** Serían un gato regalado (T1 trivial). Se
   eliminan cediendo a la región una celda adyacente de una región mayor, con
   dos condiciones: la donante sigue conexa y el tablero sigue siendo único. Si
   el movimiento rompe la unicidad se prueba otra celda; si no hay ninguna, se
   descarta el tablero.
2. **Regiones desproporcionadas.** Se descarta el tablero si alguna región
   supera `TOPE_REGION × n = 2.5n` celdas.

```
función pulir(reg, π):
    repetir hasta 40 veces:
        si no hay regiones de tamaño 1: romper
        k ← una región de tamaño 1
        opciones ← celdas vecinas a k en regiones de tamaño ≥ 3
                   cuya donante siga conexa al quitarlas
        si opciones = ∅: romper
        para (celda, donante) en barajar(opciones):
            mover celda a k
            si enumerar(reg, 2) = 1: aceptar y romper
            deshacer
    devolver reg
```

El pulido **sólo se acepta si preserva la unicidad**, así que no puede empeorar
la corrección; sólo puede fallar y dejar la región de tamaño 1 (en cuyo caso el
tablero se descarta por el filtro de tamaño mínimo).

## 17. Paso 6 — Motor de deducción humana

El motor replica a un jugador. Mantiene un tablero de tres estados por celda:
`DESCONOCIDO`, `GATO`, `VACÍA`. En cada iteración aplica la técnica más barata
disponible y, cuando ninguna aplica, se detiene y devuelve la ambigüedad
restante.

### 17.1 Estado derivado: casillas posibles

```
posibles(tablero):
    gatos ← celdas con GATO
    filas ← filas de gatos;  cols ← columnas de gatos;  regs ← regiones de gatos
    devolver { (f,c) : tablero[f][c] = DESCONOCIDO,
                        f ∉ filas, c ∉ cols, reg[f][c] ∉ regs,
                        ∀ g ∈ gatos: máx(|f−g.f|, |c−g.c|) ≥ 2 }
```

Esta función ya incorpora D2 y D3: es la propagación de adyacencia y de unidad.

### 17.2 T1 — Forzados

```
para cada unidad U en {filas pendientes} ∪ {columnas pendientes} ∪ {regiones pendientes}:
    si U ∩ posibles = ∅: CONTRADICCIÓN
    si |U ∩ posibles| = 1: colocar gato en esa celda
```

«Pendiente» significa que la unidad aún no tiene gato. Las unidades ya
satisfechas se omiten: incluirlas haría que una unidad satisfecha con cero
casillas posibles se interpretara como contradicción.

### 17.3 T2 — Intersección (k = 1)

```
para cada región R pendiente:
    si todas las posibles de R están en una fila f:
        eliminar de la fila f las posibles que no son de R
    si todas están en una columna c: análogamente
para cada fila f pendiente / columna c pendiente:
    si todas las posibles están en una sola región R:
        eliminar de R las posibles que no están en esa fila/columna
```

### 17.4 T3 — Palomar (k = 2, 3)

```
para k en {2, 3}:
    para cada combinación Z de k regiones pendientes:
        celdas ← posibles de Z
        si celdas se reparten en exactamente k filas F:
            para f en F: eliminar posibles de f que no son de Z    # D4
        si se reparten en exactamente k columnas C:
            para c en C: eliminar posibles de c que no son de Z    # D5
    para cada combinación de k filas pendientes:
        si sus posibles se reparten en exactamente k regiones Z:
            para R en Z: eliminar posibles de R fuera de esas filas  # D6
    (simétrico con columnas)
```

**Detalle crítico.** Sólo se consideran combinaciones formadas **íntegramente**
por unidades pendientes (`all(...)`, no `any(...)`). Si se mezclara una unidad
ya satisfecha con otras, la regla del palomar se aplicaría a un conjunto que ya
no necesita gatos y produciría eliminaciones falsas. Este fue un error real
detectado durante el desarrollo: convertía tableros ambiguos en «resueltos» con
solución distinta a la verdadera.

### 17.5 T4 — Reducción al absurdo de un paso

```
posibles ← posibles(tablero)
para x en posibles (como máximo 40 por ronda):
    copia ← clonar(tablero); poner GATO en x; saturar(copia, T1–T3)
    si copia contradice: marcar x como VACÍA; continuar
    copia2 ← clonar(tablero); poner VACÍA en x; saturar(copia2, T1–T3)
    si copia2 contradice: poner GATO en x
```

`saturar` aplica T1–T3 hasta punto fijo y devuelve «contradicción» si alguna
unidad pendiente se queda sin casillas posibles. Es la parte más cara del motor,
por eso el número de hipótesis por ronda está acotado (40).

### 17.6 El motor completo

```
función motor(reg, techo):
    tablero ← todo DESCONOCIDO
    pasos ← 0; perfil ← {1:0, 2:0, 3:0, 4:0}
    mientras pasos < tope:
        si resuelto(tablero): romper
        si T1 coloca gatos: contar(1); continuar
        si techo ≥ 2 y T2 elimina algo: contar(2); continuar
        si techo ≥ 3 y T3 elimina algo: contar(3); continuar
        si techo ≥ 4 y T4 elimina/coloca algo: contar(4); continuar
        romper
    devolver {resuelto, perfil, pasos, ambigüedad = |posibles|, primer_gato}
```

`resuelto` comprueba **las tres** dimensiones: una por fila, una por columna y
una por región. Comprobar sólo las filas es un error tentador: un tablero con dos
gatos en la misma columna puede tener una fila por gato y declararse «resuelto».

**Techo mínimo.** Se define `techo_min(reg)` como el menor `t ∈ {1,2,3,4}` tal que
`motor(reg, t)` resuelve. Si ningún `t` lo consigue, vale 5 («sólo por búsqueda»).

## 18. Paso 7 — Vector de dificultad y puntuación

Se miden seis cantidades:

| Métrica | Símbolo | Significado |
|---------|---------|-------------|
| Tamaño | `n` | Lado del tablero. |
| Techo lógico | `T` | `techo_min`; la técnica más cara que hace falta. |
| Pasos | `p` | Acciones elementales del motor hasta resolver. |
| Primer gato | `g₁` | Pasos antes de poder colocar el primer gato. |
| Entrelazado | `ι` | `1 − perímetro/(2n(n−1))`; mide cuánto se enredan las fronteras. |
| Dispersión de tamaños | `σ` | Desviación típica de los tamaños de región. |

La **puntuación compuesta** (0–100) que se usa para ordenar tableros es:

```
score = 30 · mín(1, (n − 5)/6)                 # tamaño
      + 40 · mín(1, (T − 1)/3)                 # profundidad lógica
      + 20 · mín(1, p / n²)                    # densidad de pasos
      +  5 · mín(1, ι / 0.55)                  # entrelazado
      +  5 · mín(1, σ / (0.6 · media_tamaños)) # variedad de tamaños
```

El primer gato `g₁` se mide y se reporta como diagnóstico (indica cuánto tarda
el tablero en «arrancar»), pero no entra en la puntuación.

Los pesos reflejan la experiencia de juego: el tamaño aporta hasta 30 puntos
(hay más que mirar), el techo lógico hasta 40 (es lo que separa a un jugador
principiante de uno avanzado), la cantidad de pasos hasta 20 (un tablero que se
resuelve en tres golpes se siente fácil aunque sea grande) y la geometría 10
(las regiones retorcidas son más difíciles de visualizar). El score **no** se usa
para aceptar o rechazar: la aceptación usa la banda explícita del nivel
(sección 19), que es más interpretable. El score sirve para ordenar, comparar y
depurar.

## 19. Selección: los cinco niveles

Un tablero candidato se acepta para el nivel `L` si cumple simultáneamente:

1. `n` dentro del rango del nivel;
2. `T` dentro de la banda de techo del nivel;
3. `p / n²` dentro de la banda de densidad de pasos;
4. unicidad (oráculo = 1);
5. ninguna región de tamaño 1 y ninguna mayor que `2.5n`.

| Nivel | Nombre | `n` | Techo `T` | Pasos `p/n²` | Score típico | Tiempo medio |
|:-----:|--------|:---:|:---------:|:------------:|:------------:|:------------:|
| 1 | Iniciación | 5 | 1–2 | 0.00–1.00 | 33–38 | < 0.05 s |
| 2 | Fácil | 6 | 2–3 | 0.00–1.00 | 41–56 | < 0.5 s |
| 3 | Medio | 7 | 3–4 | 0.00–0.75 | 58–72 | 0.1–4 s |
| 4 | Difícil | 8–9 | 4 | 0.30–1.00 | 78–87 | 0.3–5 s |
| 5 | Experto | 9–10 | 4 | 0.50–1.00 | 84–92 | 2–20 s |

**Por qué la banda de techo no es un «tier mínimo» puro.** El techo 3 (palomar
de orden 2 y 3) sólo es *necesario* en una minoría de tableros: casi siempre que
hace falta algo más que T2, T4 también funciona y el motor cae en 4. Por eso el
nivel 3 admite techo 3 **o** 4 y se distingue del 4 por el tamaño y la densidad
de pasos. Fijar `T = 3` exacto haría la generación inviable sin aportar nada al
jugador.

**Progresión real.** La dificultad no depende de una sola variable:

- niveles 1–2: tableros pequeños, resueltos casi de golpe con T1–T3;
- nivel 3: primer tablero que exige mirar varias unidades a la vez;
- niveles 4–5: exigen reducción al absurdo (T4) y muchos pasos, con tableros
  grandes donde la geometría pesa.

## 20. Pseudocódigo completo

```
función generar(nivel, rng, intentos_máx):
    cfg ← NIVELES[nivel]
    repetir intentos_máx veces:
        n ← sorteo(cfg.n)                      # por intento, no por tablero
        π ← solución(n, rng)
        reg ← partición(n, π, rng)
        si no válida_estructuralmente(reg, π): continuar
        si enumerar(reg, 2) ≠ 1: continuar
        reg ← pulir(reg, π)
        si no válida_estructuralmente(reg, π): continuar
        si enumerar(reg, 2) ≠ 1: continuar
        si mín(tamaños) < 2 o máx(tamaños) > 2.5n: continuar
        m ← medir(reg, π)
        si no encaja(m, nivel): continuar
        devolver empaquetar(reg, π, m)
    error «sin tablero»
```

Sorteo del tamaño **por intento** (y no una vez por tablero) para que un tamaño
grande poco probable no bloquee la generación: si el nivel admite `n = 9` y
`n = 10` y el 10 es cien veces más raro, los intentos con 9 siguen avanzando.

## 21. Complejidad y rendimiento

| Etapa | Coste por intento | Comentario |
|-------|-------------------|------------|
| Solución | `O(n!)` peor caso, `O(n²)` típico | backtracking con orden aleatorio |
| Partición | `O(n² · α(n²))` | Kruskal con union-find |
| Validación | `O(n²)` | BFS por región |
| Oráculo | `O(nodos)` | doble poda (columna y región) |
| Pulido | `O(n²)` por movimiento, ≤ 40 | sólo si hay regiones de tamaño 1 |
| Motor | `O(n²)` por ronda; T4 `O(40 · n²)` | acotado por `tope` |
| Medición | hasta 4 motores + 1 oráculo | por candidato único |

El coste dominante es el **número de intentos**, que depende de la probabilidad
de que una partición aleatoria pase los filtros. Tasas medidas con semilla 99
(4 000 particiones para `n = 5–6`, 8 000 para el resto):

| `n` | Particiones únicas | Únicas y legibles | Intentos (1/p) |
|----:|-------------------:|------------------:|---------------:|
| 5 | ~46 % | ~31 % | ~3 |
| 6 | ~18 % | ~8 % | ~13 |
| 7 | ~6.8 % | ~1.6 % | ~60 |
| 8 | ~2.8 % | ~0.23 % | ~450 |
| 9 | ~0.9 % | ~0.03 % | ~4 000 |
| 10 | ~0.4 % | ~0.013 % | ~8 000 |

«Únicas y legibles» añade los dos filtros de forma: ninguna región de tamaño 1
tras el pulido y ninguna mayor que `2.5n`. Las tasas varían ±30–50 % entre
semillas y caen con `n`, pero la tendencia es estable. La banda de nivel recorta
aún más: por eso el banco de pruebas necesita ~240 intentos en el nivel 3
(media de `n = 7`) y ~4 300 en el 5 (mezcla de `n = 9` y `n = 10`).

Estas tasas explican por qué el nivel 5 tarda segundos y el 1 es instantáneo.
Mejorarlas requiere construir particiones sesgadas hacia la unicidad (sección
23), no optimizar el código.

---

# Parte IV — Validación

## 22. Autotest y banco de pruebas

La implementación incluye dos comprobaciones ejecutables:

```
python3 generador_catdoku.py --autotest --muestras 4
python3 generador_catdoku.py --bench    --muestras 5
```

El **autotest** genera tableros de los cinco niveles y verifica, para cada uno:

1. estructura (regiones conexas, una semilla por región, R4);
2. resolución por el motor con techo 4;
3. **unicidad con el oráculo independiente** (`enumerar(reg, 2) = 1`).

Resultado de la última ejecución:

```
nivel 1: OK
nivel 2: OK
nivel 3: OK
nivel 4: OK
nivel 5: OK
AUTOTEST OK
```

El **banco** mide lo que produce cada nivel:

```
nivel    n  tier  pasos/n²  score  intentos   t(s)
    1  5.0  2.00      0.63   35.6         3    0.0
    2  6.0  2.20      0.63   43.5        31    0.2
    3  7.0  4.00      0.58   71.7       239    0.7
    4  8.0  4.00      0.80   80.9       962    4.9
    5  9.2  4.00      0.79   86.8      4320   40.0
```

(5 muestras por nivel, semilla 22; el tiempo es el total de las 5 muestras y
varía con la máquina.)

El score medio es estrictamente creciente con el nivel, que es la propiedad que
se quería garantizar.

## 23. Limitaciones conocidas

1. **Regiones desiguales.** La coalescencia aleatoria del paso 2 produce una
   distribución de tamaños muy sesgada. El tope `2.5n` y el pulido la acotan,
   pero un tablero de nivel 5 puede tener una región de 25 celdas y varias de 2.
   Los puzles comerciales son más equilibrados. Arreglarlo requiere un
   generador de particiones sesgado (crecimiento dirigido, optimización de
   fronteras), no un filtro.
2. **Rendimiento en `n = 10–11`.** La tasa de unicidad cae por debajo del 0.5 %.
   El nivel 5 se limita a `n ≤ 10` por eso; `n = 11` es posible pero lento
   (decenas de segundos por tablero).
3. **Modelo humano acotado a T4.** Tableros que requieren palomar de orden 4 o
   cadenas de contradicción de dos niveles se rechazan aunque sean únicos. Es
   deliberado: el objetivo son cinco niveles «de revista», no el límite teórico.
4. **El score no es una medida psicométrica.** Es una combinación calibrada a
   ojo con datos del propio motor. Sirve para ordenar y comparar, no para
   predecir tiempos de resolución de personas reales.
5. **Sin garantía de diversidad.** Dos ejecuciones con semillas distintas pueden
   producir tableros isomorfos (misma partición salvo simetría). No hay
   deduplicación por clase de isomorfía.

## 24. Extensiones naturales

- **Particiones dirigidas.** Generar la partición maximizando directamente la
  probabilidad de unicidad (por ejemplo, con crecimiento multi-fuente y
  recocido sobre las fronteras, evaluando con el oráculo). Es el siguiente paso
  lógico para equilibrar tamaños sin perder unicidad.
- **Dificultad psicométrica.** Ajustar los pesos del score con tiempos de
  resolución humanos.
- **Variante de dos estrellas.** Cambia el oráculo (dos por unidad) y el motor
  (reglas de par de estrellas); la arquitectura se mantiene.
- **Pistas progresivas.** Revelar gatos o descartes para un modo «aprender».

---

# Apéndices

## A. Glosario

| Término | Definición |
|---------|-----------|
| Región | Subconjunto conexo de celdas; hay `n` y cada una lleva un gato. |
| Unidad | Fila, columna o región. Hay `3n` unidades. |
| Unidad pendiente | Unidad que todavía no tiene gato. |
| Posible | Celda desconocida compatible con todos los gatos colocados. |
| Techo | Conjunto máximo de técnicas que el motor puede usar (1–4). |
| Techo mínimo | Menor techo con el que el motor resuelve. |
| Único | Con exactamente una solución. |
| Deducible | Resoluble por el motor sin ramificar. |
| Ambigüedad | Número de celdas posibles cuando el motor se atasca. |
| Semilla | Celda de la solución; ancla de cada región en la partición. |

## B. Formato de salida

`--json` produce un objeto con esta forma:

```json
{
  "id": "catdoku-L3-n7-858a19f460",
  "nivel": 3,
  "nombre_nivel": "Medio",
  "n": 7,
  "regiones": [[...], ...],
  "solucion": [[fila, columna], ...],
  "metricas": {
    "n": 7, "nivel": 3,
    "tier_min": 3, "tier_max": 3, "pasos": 30,
    "t1": 7, "t2": 20, "t3": 3, "t4": 0,
    "primer_gato": 23,
    "tam_min": 2, "tam_max": 16, "tam_media": 7.0, "tam_desv": 5.35,
    "interbloqueo": 0.65, "puntuacion": 58.91
  },
  "intentos": 206
}
```

`regiones[f][c]` es el índice de región (0-based) de la celda `(f+1, c+1)`.
`solucion` lista `[fila, columna]` con índices 0-based.

## C. Tableros de ejemplo

### Nivel 1 — Iniciación (`n = 5`, score 37.73, T = 2)

```
    1 2 3 4 5
 1  D D D @ D
 2  @ C D D D
 3  A C @ D D
 4  A C C E @
 5  B @ C C C

Regiones: A=R1  B=R2  C=R3  D=R4  E=R5
Gatos: (2,1), (5,2), (3,3), (1,4), (4,5)
```

Resolución: el motor coloca 5 gatos por candidato único (T1) y hace 13
deducciones de intersección (T2); no necesita nada más. Las regiones `A`
(columna 1), `B` (fila 5) y `E` (fila 4) son tiras de una sola fila o columna:
en cuanto una línea se ocupa, la tira se reduce a una casilla.

### Nivel 3 — Medio (`n = 7`, score 58.91, T = 3)

```
    1 2 3 4 5 6 7
 1  B B B D D G @
 2  B B D D @ E G
 3  B @ D D F F F
 4  D D D F F @ F
 5  A A D @ F F F
 6  @ A D D F F F
 7  A C @ D F F F

Regiones: A=R1  B=R2  C=R3  D=R4  E=R5  F=R6  G=R7
Gatos: (6,1), (3,2), (7,3), (5,4), (2,5), (4,6), (1,7)
```

Aquí T1 y T2 no bastan: el motor hace 7 colocaciones por candidato único, 20
deducciones de intersección y 3 de palomar (T3). Es el palomar el que rompe el
bloqueo: sin él el tablero no cae.

### Nivel 5 — Experto (`n = 10`, score 91.80, T = 4)

```
    1 2 3 4 5 6 7 8 9 10
 1  A A G G G J J J @ I
 2  @ A G G G G G J J I
 3  D G G G G G @ J J J
 4  D D G G G G J J J @
 5  D D D G G G H @ H H
 6  D D D D @ G H H H H
 7  D @ D D E H H H H H
 8  B B D @ F F H H H H
 9  B B B F F @ H H H H
10  B C @ F F F H H H H

Regiones: A=R1  B=R2  C=R3  D=R4  E=R5  F=R6  G=R7  H=R8  I=R9  J=R10
Gatos: (2,1), (7,2), (10,3), (8,4), (6,5), (9,6), (3,7), (5,8), (1,9), (4,10)
```

Requiere reducción al absurdo: el motor hace sólo 5 colocaciones directas, 16
intersecciones, 48 palomares (T3) y 15 reducciones al absurdo (T4). Las regiones
grandes (`G` con 22 casillas, `H` con 25) apenas restringen al principio; son el
palomar y las hipótesis los que las van cerrando.

## D. Interfaz de línea de comandos

```
python3 generador_catdoku.py --nivel 3 --semilla 1234 --solucion
python3 generador_catdoku.py --nivel 5 --json
python3 generador_catdoku.py --nivel 4 --guardar ejemplos/
python3 generador_catdoku.py --autotest --muestras 4
python3 generador_catdoku.py --bench --muestras 5
```

| Opción | Efecto |
|--------|--------|
| `--nivel 1..5` | Nivel de dificultad. |
| `--n N` | Fuerza el tamaño (anula el rango del nivel). |
| `--semilla S` | Reproducibilidad. |
| `--solucion` | Dibuja los gatos `@`. |
| `--json` | Salida máquina-legible. |
| `--guardar DIR` | Escribe `id.json` e `id.txt`. |
| `--autotest` | Valida estructura, deducibilidad y unicidad. |
| `--bench` | Tabla de calibración por nivel. |

## E. Referencias del género

- *Star Battle* / *Queens*: reglas y variantes (una o dos piezas por unidad).
- Generadores abiertos de la familia (`queens-generator`, `starbattle`,
  `meowdoku-solver`, `wangdoku`): confirman que la unicidad se comprueba con un
  solver y que la «justicia» exige además un modelo de deducción humana.
- Aplicaciones comerciales (*Catdoku!*, *Meowdoku*, *Pawdoku*, *WangDoKu*):
  confirman las cuatro reglas y la ausencia de pistas numéricas.

---

*Documento e implementación generados en el espacio de trabajo
`catdoku/`. La implementación es la referencia ejecutable de todo lo aquí
descrito; si hay discrepancia entre el texto y el código, manda el código.*
