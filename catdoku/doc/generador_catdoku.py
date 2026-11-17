#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Catdoku — generador de tableros con cinco niveles de dificultad.

El módulo implementa la cadena descrita en ``compendio-catdoku.md``:

    1. Solución    : permutación sin gatos que se ataquen (reyes).
    2. Partición   : bosque aleatorio (Kruskal restringido) con una semilla
                     por región; regiones conexas y de tamaño acotado.
    3. Oráculo     : enumeración exacta para exigir solución única.
    4. Motor       : perfil de deducción humana (forzados, intersecciones,
                     palomar, reducción al absurdo) → techo lógico mínimo.
    5. Medición    : vector de dificultad (tamaño, techo, pasos, geometría).
    6. Selección   : rechazo hasta caer en la banda del nivel pedido.
    7. Empaquetado : texto ASCII y JSON.

Uso:
    python3 generador_catdoku.py --nivel 3 --semilla 1234
    python3 generador_catdoku.py --nivel 5 --n 11 --json
    python3 generador_catdoku.py --bench --muestras 12
    python3 generador_catdoku.py --autotest --muestras 20
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import random
import sys
import time
from collections import deque
from dataclasses import asdict, dataclass

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

UNK, STAR, EMPTY = 0, 1, -1
LETRAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
CAT, VACIO = "@", "."
TOPE_REGION = 2.5   # tamaño máximo de una región, en múltiplos de n


# ---------------------------------------------------------------------------
# 1. Solución
# ---------------------------------------------------------------------------

def generar_solucion(n: int, rng: random.Random) -> list[int]:
    """sol[c] = fila del gato de la columna c.

    Es una permutación (una fila y una columna por gato) con
    |sol[c] - sol[c+1]| >= 2 (sin contacto, ni diagonal).
    """
    sol: list[int] = []
    usadas = [False] * n

    def retroceder() -> bool:
        if len(sol) == n:
            return True
        valores = list(range(n))
        rng.shuffle(valores)
        for v in valores:
            if usadas[v] or (sol and abs(v - sol[-1]) < 2):
                continue
            usadas[v] = True
            sol.append(v)
            if retroceder():
                return True
            sol.pop()
            usadas[v] = False
        return False

    if not retroceder():
        raise RuntimeError(f"n={n} no admite solución")
    return sol


def contar_permutaciones_validas(n: int) -> int:
    """Número de soluciones si no hubiera regiones (tabla del documento)."""
    from functools import lru_cache

    @lru_cache(maxsize=None)
    def f(mask: int, ultimo: int) -> int:
        if mask == (1 << n) - 1:
            return 1
        return sum(f(mask | (1 << v), v) for v in range(n)
                   if not (mask >> v & 1) and (ultimo >= n or abs(v - ultimo) >= 2))

    return f(0, n)


# ---------------------------------------------------------------------------
# 2. Partición en regiones
# ---------------------------------------------------------------------------

def vecinos4(r: int, c: int, n: int):
    if r > 0:
        yield r - 1, c
    if r + 1 < n:
        yield r + 1, c
    if c > 0:
        yield r, c - 1
    if c + 1 < n:
        yield r, c + 1


def conectada(celdas: set[tuple[int, int]], n: int) -> bool:
    if not celdas:
        return False
    ini = next(iter(celdas))
    visto = {ini}
    cola = deque([ini])
    while cola:
        r, c = cola.popleft()
        for rr, cc in vecinos4(r, c, n):
            if (rr, cc) in celdas and (rr, cc) not in visto:
                visto.add((rr, cc))
                cola.append((rr, cc))
    return len(visto) == len(celdas)


def particion_bosque(n: int, sol: list[int], rng: random.Random) -> list[list[int]]:
    """Kruskal aleatorio restringido: n árboles conexos, uno por semilla.

    Se barajan las aristas del retículo y se fusionan componentes siempre que
    la unión no contenga dos semillas.  Con n^2 celdas y n semillas quedan
    exactamente n componentes, cada uno con un gato.
    """
    padre = list(range(n * n))
    tam = [1] * (n * n)
    semillas = [0] * (n * n)
    for c in range(n):
        semillas[sol[c] * n + c] = 1

    def hallar(x: int) -> int:
        while padre[x] != x:
            padre[x] = padre[padre[x]]
            x = padre[x]
        return x

    def unir(a: int, b: int) -> bool:
        ra, rb = hallar(a), hallar(b)
        if ra == rb or semillas[ra] + semillas[rb] > 1:
            return False
        if tam[ra] < tam[rb]:
            ra, rb = rb, ra
        padre[rb] = ra
        tam[ra] += tam[rb]
        semillas[ra] += semillas[rb]
        return True

    aristas = []
    for r in range(n):
        for c in range(n):
            if r + 1 < n:
                aristas.append((r * n + c, (r + 1) * n + c))
            if c + 1 < n:
                aristas.append((r * n + c, r * n + c + 1))

    necesarias = n * n - n
    hechas = 0
    while hechas < necesarias:
        rng.shuffle(aristas)
        progreso = False
        for a, b in aristas:
            if unir(a, b):
                hechas += 1
                progreso = True
                if hechas == necesarias:
                    break
        if not progreso:
            break

    comp: dict[int, int] = {}
    reg = [[0] * n for _ in range(n)]
    for i in range(n * n):
        raiz = hallar(i)
        if raiz not in comp:
            comp[raiz] = len(comp)
        reg[i // n][i % n] = comp[raiz]

    # Reetiquetar: la región de la semilla de la columna c se llama c.
    mapa = {comp[hallar(sol[c] * n + c)]: c for c in range(n)}
    return [[mapa[x] for x in fila] for fila in reg]


def perimetro(reg: list[list[int]], n: int) -> int:
    p = 0
    for r in range(n):
        for c in range(n):
            if r + 1 < n and reg[r][c] != reg[r + 1][c]:
                p += 1
            if c + 1 < n and reg[r][c] != reg[r][c + 1]:
                p += 1
    return p


# ---------------------------------------------------------------------------
# 3. Motor de deducción humana
# ---------------------------------------------------------------------------

def posibles(grid: list[list[int]], n: int, reg: list[list[int]]) -> set[tuple[int, int]]:
    """Celdas vacías que aún podrían alojar un gato."""
    gatos = [(r, c) for r in range(n) for c in range(n) if grid[r][c] == STAR]
    filas = {r for r, _ in gatos}
    cols = {c for _, c in gatos}
    zonas = {reg[r][c] for r, c in gatos}
    salida = set()
    for r in range(n):
        for c in range(n):
            if grid[r][c] != UNK:
                continue
            if r in filas or c in cols or reg[r][c] in zonas:
                continue
            if any(abs(r - rr) <= 1 and abs(c - cc) <= 1 for rr, cc in gatos):
                continue
            salida.add((r, c))
    return salida


def unidades_pendientes(n: int, reg: list[list[int]], poss: set[tuple[int, int]],
                        grid: list[list[int]]):
    """Unidades (fila/columna/región) que todavía no tienen gato."""
    for r in range(n):
        if not any(grid[r][c] == STAR for c in range(n)):
            yield {(r, c) for c in range(n)} & poss
    for c in range(n):
        if not any(grid[r][c] == STAR for r in range(n)):
            yield {(r, c) for r in range(n)} & poss
    for z in range(n):
        celdas = {(r, c) for r in range(n) for c in range(n) if reg[r][c] == z}
        if not any(grid[r][c] == STAR for r, c in celdas):
            yield celdas & poss


def _colocar(grid, n, reg, r, c) -> None:
    grid[r][c] = STAR


def tier_forzados(grid, n, reg) -> tuple[bool, int]:
    """T1: candidato único en una unidad. (ok, colocados)"""
    p = posibles(grid, n, reg)
    forzadas: set[tuple[int, int]] = set()
    for u in unidades_pendientes(n, reg, p, grid):
        if not u:
            return False, 0
        if len(u) == 1:
            forzadas.add(next(iter(u)))
    colocados = 0
    for r, c in forzadas:
        if grid[r][c] == UNK:
            _colocar(grid, n, reg, r, c)
            colocados += 1
    return True, colocados


def tier_palomar(grid, n, reg, kmin: int = 1, kmax: int = 3) -> tuple[bool, int]:
    """T2/T3: intersecciones y palomar (k zonas confinadas a k líneas)."""
    p = posibles(grid, n, reg)
    cambio = 0
    zonas = [[(r, c) for r in range(n) for c in range(n) if reg[r][c] == z] for z in range(n)]
    zc = [set(z) & p for z in zonas]
    filas_ok = [not any(grid[r][c] == STAR for c in range(n)) for r in range(n)]
    cols_ok = [not any(grid[r][c] == STAR for r in range(n)) for c in range(n)]
    zonas_ok = [not any(grid[r][c] == STAR for r, c in zonas[z]) for z in range(n)]

    for k in range(kmin, kmax + 1):
        if k > n - 1:
            break
        for combo in itertools.combinations(range(n), k):
            if not all(zonas_ok[z] for z in combo):
                continue
            celdas = set().union(*(zc[z] for z in combo))
            if not celdas:
                continue
            filas = {r for r, _ in celdas}
            cols = {c for _, c in celdas}
            if len(filas) == k:
                for r in filas:
                    for c in range(n):
                        if (r, c) in p and reg[r][c] not in combo:
                            grid[r][c] = EMPTY
                            p.discard((r, c))
                            cambio += 1
            if len(cols) == k:
                for c in cols:
                    for r in range(n):
                        if (r, c) in p and reg[r][c] not in combo:
                            grid[r][c] = EMPTY
                            p.discard((r, c))
                            cambio += 1

    for k in range(kmin, kmax + 1):
        if k > n - 1:
            break
        for combo in itertools.combinations(range(n), k):
            if not all(filas_ok[r] for r in combo):
                continue
            celdas = {(r, c) for r in combo for c in range(n) if (r, c) in p}
            if not celdas:
                continue
            zs = {reg[r][c] for r, c in celdas}
            if len(zs) == k:
                for z in zs:
                    for r, c in zc[z]:
                        if r not in combo and grid[r][c] == UNK:
                            grid[r][c] = EMPTY
                            cambio += 1
        for combo in itertools.combinations(range(n), k):
            if not all(cols_ok[c] for c in combo):
                continue
            celdas = {(r, c) for c in combo for r in range(n) if (r, c) in p}
            if not celdas:
                continue
            zs = {reg[r][c] for r, c in celdas}
            if len(zs) == k:
                for z in zs:
                    for r, c in zc[z]:
                        if c not in combo and grid[r][c] == UNK:
                            grid[r][c] = EMPTY
                            cambio += 1
    return True, cambio


def tier_absurdo(grid, n, reg) -> tuple[bool, int]:
    """T4: reducción al absurdo a un nivel."""
    base = posibles(grid, n, reg)
    cambio = 0
    probadas = 0
    for r, c in base:
        probadas += 1
        if probadas > 40:
            break
        # hipótesis gato -> ¿contradicción?
        g2 = [f[:] for f in grid]
        g2[r][c] = STAR
        ok = _saturar(g2, n, reg, 3)
        if not ok:
            grid[r][c] = EMPTY
            cambio += 1
            continue
        # hipótesis vacío -> ¿contradicción?
        g3 = [f[:] for f in grid]
        g3[r][c] = EMPTY
        ok2 = _saturar(g3, n, reg, 3)
        if not ok2:
            grid[r][c] = STAR
            cambio += 1
    return True, cambio


def _saturar(grid, n, reg, max_tier: int = 3, tope: int = 300) -> bool:
    """Aplica T1..max_tier hasta punto fijo. Devuelve False si contradice."""
    for _ in range(tope):
        ok, colocados = tier_forzados(grid, n, reg)
        if not ok:
            return False
        if colocados:
            continue
        if max_tier >= 2:
            ok, c2 = tier_palomar(grid, n, reg, 1, 1)
            if not ok:
                return False
            if c2:
                continue
        if max_tier >= 3:
            ok, c3 = tier_palomar(grid, n, reg, 2, 3)
            if not ok:
                return False
            if c3:
                continue
        return True
    return True


def resuelto(grid, n, reg: list[list[int]] | None = None) -> bool:
    """¿Hay exactamente un gato por fila, columna y (si se da) región?"""
    if not all(sum(1 for c in range(n) if grid[r][c] == STAR) == 1 for r in range(n)):
        return False
    if not all(sum(1 for r in range(n) if grid[r][c] == STAR) == 1 for c in range(n)):
        return False
    if reg is not None:
        for z in range(n):
            if sum(1 for r in range(n) for c in range(n)
                   if reg[r][c] == z and grid[r][c] == STAR) != 1:
                return False
    return True


def motor(n: int, reg: list[list[int]], max_tier: int = 4,
          tope: int = 3000) -> dict:
    """Resuelve por deducción.  Devuelve estado final y contadores por nivel."""
    grid = [[UNK] * n for _ in range(n)]
    stats = {1: 0, 2: 0, 3: 0, 4: 0}
    pasos = 0
    tier_max = 0
    primer_gato = None

    while pasos < tope:
        if resuelto(grid, n, reg):
            break
        ok, colocados = tier_forzados(grid, n, reg)
        if not ok:
            return dict(ok=False, solved=False, grid=grid, stats=stats,
                        ambig=0, pasos=pasos, tier_max=tier_max)
        if colocados:
            if primer_gato is None:
                primer_gato = pasos
            stats[1] += colocados
            pasos += colocados
            tier_max = max(tier_max, 1)
            continue
        if max_tier >= 2:
            ok, c = tier_palomar(grid, n, reg, 1, 1)
            if not ok:
                return dict(ok=False, solved=False, grid=grid, stats=stats,
                            ambig=0, pasos=pasos, tier_max=tier_max)
            if c:
                stats[2] += c
                pasos += c
                tier_max = max(tier_max, 2)
                continue
        if max_tier >= 3:
            ok, c = tier_palomar(grid, n, reg, 2, 2)
            if not ok:
                return dict(ok=False, solved=False, grid=grid, stats=stats,
                            ambig=0, pasos=pasos, tier_max=tier_max)
            if not c:
                ok, c = tier_palomar(grid, n, reg, 3, 3)
                if not ok:
                    return dict(ok=False, solved=False, grid=grid, stats=stats,
                                ambig=0, pasos=pasos, tier_max=tier_max)
            if c:
                stats[3] += c
                pasos += c
                tier_max = max(tier_max, 3)
                continue
        if max_tier >= 4:
            ok, c = tier_absurdo(grid, n, reg)
            if not ok:
                return dict(ok=False, solved=False, grid=grid, stats=stats,
                            ambig=0, pasos=pasos, tier_max=tier_max)
            if c:
                stats[4] += c
                pasos += c
                tier_max = max(tier_max, 4)
                continue
        break

    p = posibles(grid, n, reg)
    return dict(ok=True, solved=resuelto(grid, n, reg), grid=grid, stats=stats,
                ambig=len(p), pasos=pasos, tier_max=tier_max,
                primer_gato=pasos if primer_gato is None else primer_gato)


def enumerar_soluciones(n: int, reg: list[list[int]], limite: int = 2) -> list[tuple[tuple[int, int], ...]]:
    """Enumera hasta ``limite`` soluciones completas.

    Backtracking por filas con máscaras de columnas y regiones: cada fila
    necesita exactamente un gato, así que basta recorrer filas y elegir la
    columna.  Es el oráculo independiente del motor heurístico.
    """
    sols: list[tuple[tuple[int, int], ...]] = []
    acc: list[tuple[int, int]] = []

    def rec(fila: int, cols: int, zonas: int, prev: int) -> None:
        if len(sols) >= limite:
            return
        if fila == n:
            sols.append(tuple(acc))
            return
        for c in range(n):
            if cols >> c & 1:
                continue
            if prev >= 0 and abs(c - prev) < 2:
                continue
            z = reg[fila][c]
            if zonas >> z & 1:
                continue
            acc.append((fila, c))
            rec(fila + 1, cols | (1 << c), zonas | (1 << z), c)
            acc.pop()
            if len(sols) >= limite:
                return

    rec(0, 0, 0, -1)
    return sols


def contar_soluciones(n: int, reg: list[list[int]], limite: int = 2) -> int:
    """Número de soluciones hasta ``limite`` (validador de unicidad)."""
    return len(enumerar_soluciones(n, reg, limite))


# ---------------------------------------------------------------------------
# 4. Utilidades de regiones
# ---------------------------------------------------------------------------

def _celdas_de(n: int, reg: list[list[int]], k: int) -> set[tuple[int, int]]:
    return {(r, c) for r in range(n) for c in range(n) if reg[r][c] == k}


def pulir(n: int, reg: list[list[int]], sol: list[int], rng: random.Random,
          max_iter: int = 40) -> list[list[int]]:
    """Elimina regiones de una sola celda (serían un gato regalado).

    Para cada región de tamaño 1 se le cede una celda adyacente de una región
    mayor, comprobando que la donante sigue conexa y que el tablero sigue
    teniendo solución única.  Si el movimiento rompe la unicidad se deshace.
    """
    reg = [fila[:] for fila in reg]
    for _ in range(max_iter):
        tam = [len(_celdas_de(n, reg, k)) for k in range(n)]
        singles = [k for k in range(n) if tam[k] == 1]
        if not singles:
            break
        k = rng.choice(singles)
        (sr, sc) = next(iter(_celdas_de(n, reg, k)))
        opciones = []
        for r, c in vecinos4(sr, sc, n):
            a = reg[r][c]
            if a == k or tam[a] <= 2:
                continue
            if conectada(_celdas_de(n, reg, a) - {(r, c)}, n):
                opciones.append((r, c, a))
        if not opciones:
            break
        rng.shuffle(opciones)
        for r, c, a in opciones:
            reg[r][c] = k
            if contar_soluciones(n, reg, limite=2) == 1:
                break
            reg[r][c] = a
        else:
            break
    return reg


# ---------------------------------------------------------------------------
# 5. Métricas
# ---------------------------------------------------------------------------

@dataclass
class Metricas:
    n: int
    nivel: int = 0
    tier_max: int = 0
    pasos: int = 0
    t1: int = 0
    t2: int = 0
    t3: int = 0
    t4: int = 0
    tier_min: int = 0              # techo mínimo con el que se resuelve
    primer_gato: int = 0           # pasos antes del primer gato
    tam_min: int = 0
    tam_max: int = 0
    tam_media: float = 0.0
    tam_desv: float = 0.0
    interbloqueo: float = 0.0
    puntuacion: float = 0.0

    def como_dict(self) -> dict:
        return asdict(self)


def tier_minimo(n: int, reg: list[list[int]]) -> int:
    """Menor techo de deducción (1..4) con el que el motor resuelve.

    5 significa que ni siquiera T4 basta (no debería ocurrir con los
    tableros aceptados, que se validan antes con el oráculo).
    """
    for t in (1, 2, 3, 4):
        if motor(n, reg, max_tier=t)["solved"]:
            return t
    return 5


def medir(n: int, reg: list[list[int]], sol: list[int], nivel: int = 0) -> Metricas:
    m = Metricas(n=n, nivel=nivel)

    m.tier_min = tier_minimo(n, reg)
    res = motor(n, reg, max_tier=4)
    m.tier_max = res["tier_max"]
    m.pasos = res["pasos"]
    m.t1 = res["stats"][1]
    m.t2 = res["stats"][2]
    m.t3 = res["stats"][3]
    m.t4 = res["stats"][4]
    m.primer_gato = res["primer_gato"]

    tam = [0] * n
    for r in range(n):
        for c in range(n):
            tam[reg[r][c]] += 1
    m.tam_min, m.tam_max = min(tam), max(tam)
    m.tam_media = sum(tam) / n
    m.tam_desv = (sum((t - m.tam_media) ** 2 for t in tam) / n) ** 0.5
    total_aristas = 2 * n * (n - 1)
    m.interbloqueo = 1.0 - perimetro(reg, n) / total_aristas

    m.puntuacion = calcular_puntuacion(m)
    return m


def calcular_puntuacion(m: Metricas) -> float:
    """Escala 0-100.

    Tamaño 30 %, techo lógico mínimo 40 %, densidad de pasos 20 %,
    geometría (entrelazado y variedad de tamaños) 10 %.
    """
    s = 30.0 * min(1.0, max(0.0, (m.n - 5) / 6))
    s += 40.0 * min(1.0, (max(0, m.tier_min) - 1) / 3)
    s += 20.0 * min(1.0, m.pasos / (m.n * m.n))
    s += 5.0 * min(1.0, m.interbloqueo / 0.55)
    s += 5.0 * min(1.0, m.tam_desv / max(1.0, m.tam_media * 0.6))
    return round(s, 2)


# ---------------------------------------------------------------------------
# 6. Niveles
# ---------------------------------------------------------------------------

NIVELES = {
    1: dict(nombre="Iniciación", n=(5, 5),  tier=(1, 2), pasos=(0.00, 1.00)),
    2: dict(nombre="Fácil",      n=(6, 6),  tier=(2, 3), pasos=(0.00, 1.00)),
    3: dict(nombre="Medio",      n=(7, 7),  tier=(3, 4), pasos=(0.00, 0.75)),
    4: dict(nombre="Difícil",    n=(8, 9),  tier=(4, 4), pasos=(0.30, 1.00)),
    5: dict(nombre="Experto",    n=(9, 10), tier=(4, 4), pasos=(0.50, 1.00)),
}


def encaja(m: Metricas, nivel: int) -> bool:
    cfg = NIVELES[nivel]
    if not (cfg["n"][0] <= m.n <= cfg["n"][1]):
        return False
    if not (cfg["tier"][0] <= m.tier_min <= cfg["tier"][1]):
        return False
    ratio = m.pasos / (m.n * m.n)
    if not (cfg["pasos"][0] <= ratio <= cfg["pasos"][1]):
        return False
    return True


def generar_tablero(nivel: int, rng: random.Random, n: int | None = None,
                    max_intentos: int = 20000, verbose: bool = False) -> dict:
    """Genera un tablero del nivel pedido por muestreo con rechazo.

    Cada intento: solución → partición en árbol → validación estructural →
    oráculo de unicidad → perfil de deducción.  Sólo se acepta si cumple la
    banda del nivel (tamaño, techo lógico mínimo, densidad de pasos).
    """
    cfg = NIVELES[nivel]

    for intento in range(1, max_intentos + 1):
        # el tamaño se sortea en cada intento: si el tamaño grande es muy
        # improbable, los intentos pequeños siguen avanzando (sin bloqueo)
        nn = n if n is not None else rng.randint(*cfg["n"])
        sol = generar_solucion(nn, rng)
        reg = particion_bosque(nn, sol, rng)

        if not _validar_estructura(nn, reg, sol):
            continue
        # oráculo exacto: descarta particiones con más de una solución
        if contar_soluciones(nn, reg, limite=2) != 1:
            continue
        # legibilidad: ninguna región debe ser una sola celda («gato regalado»)
        reg = pulir(nn, reg, sol, rng)
        if not _validar_estructura(nn, reg, sol):
            continue
        if contar_soluciones(nn, reg, limite=2) != 1:
            continue
        if min(len(_celdas_de(nn, reg, k)) for k in range(nn)) < 2:
            continue
        # ni regiones desproporcionadas (ilegibles): tope 2.5n
        if max(len(_celdas_de(nn, reg, k)) for k in range(nn)) > TOPE_REGION * nn:
            continue
        m = medir(nn, reg, sol, nivel)
        if not encaja(m, nivel):
            if verbose and intento % 200 == 0:
                print(f"  intento {intento}: n={nn} tier_min={m.tier_min} "
                      f"pasos={m.pasos}", file=sys.stderr)
            continue
        return empaquetar(nn, reg, sol, nivel, m, intento)
    raise RuntimeError(f"Sin tablero para nivel {nivel} (n={n}) tras {max_intentos} intentos")


def _validar_estructura(n: int, reg: list[list[int]], sol: list[int]) -> bool:
    if any(reg[r][c] < 0 for r in range(n) for c in range(n)):
        return False
    if sorted({reg[r][c] for r in range(n) for c in range(n)}) != list(range(n)):
        return False
    for k in range(n):
        celdas = _celdas_de(n, reg, k)
        if not celdas or not conectada(celdas, n):
            return False
        if sum(1 for c in range(n) if reg[sol[c]][c] == k) != 1:
            return False
    return all(abs(sol[c] - sol[c + 1]) >= 2 for c in range(n - 1))


def empaquetar(n: int, reg: list[list[int]], sol: list[int], nivel: int,
               m: Metricas, intento: int) -> dict:
    firma = hashlib.sha1((str(n) + str(reg) + str(sol) + str(nivel)).encode()).hexdigest()[:10]
    return {
        "id": f"catdoku-L{nivel}-n{n}-{firma}",
        "nivel": nivel,
        "nombre_nivel": NIVELES[nivel]["nombre"],
        "n": n,
        "regiones": reg,
        "solucion": [[sol[c], c] for c in range(n)],
        "metricas": m.como_dict(),
        "intentos": intento,
    }


# ---------------------------------------------------------------------------
# 7. Render y CLI
# ---------------------------------------------------------------------------

def render(tablero: dict, mostrar_solucion: bool = False) -> str:
    n = tablero["n"]
    reg = tablero["regiones"]
    gatos = {(r, c) for r, c in tablero["solucion"]} if mostrar_solucion else set()
    lineas = ["    " + " ".join(str(c + 1) for c in range(n))]
    for r in range(n):
        fila = [CAT if (r, c) in gatos else LETRAS[reg[r][c]] for c in range(n)]
        lineas.append(f"{r + 1:>2}  " + " ".join(fila))
    lineas.append("")
    lineas.append("Regiones: " + "  ".join(f"{LETRAS[k]}=R{k + 1}" for k in range(n)))
    if mostrar_solucion:
        lineas.append("Gatos: " + ", ".join(f"({r + 1},{c + 1})" for r, c in tablero["solucion"]))
    return "\n".join(lineas)


def bench(muestras: int, rng: random.Random) -> None:
    """Tabla de calibración: qué produce realmente cada nivel."""
    print(f"{'nivel':>5} {'n':>4} {'tier':>5} {'pasos/n²':>9} {'score':>6} "
          f"{'intentos':>9} {'t(s)':>6}")
    for nivel in range(1, 6):
        t0 = time.time()
        ns, tiers, ratios, scores, intentos = [], [], [], [], []
        for _ in range(muestras):
            t = generar_tablero(nivel, rng)
            m = t["metricas"]
            ns.append(t["n"])
            tiers.append(m["tier_min"])
            ratios.append(m["pasos"] / (t["n"] ** 2))
            scores.append(m["puntuacion"])
            intentos.append(t["intentos"])
        k = max(1, len(ns))
        print(f"{nivel:>5} {sum(ns)/k:>4.1f} {sum(tiers)/k:>5.2f} "
              f"{sum(ratios)/k:>9.2f} {sum(scores)/k:>6.1f} "
              f"{sum(intentos)/k:>9.0f} {time.time()-t0:>6.1f}")


def autotest(muestras: int, rng: random.Random) -> None:
    fallos = 0
    for nivel in range(1, 6):
        fallos_nivel = 0
        for _ in range(muestras):
            t = generar_tablero(nivel, rng)
            n, reg = t["n"], t["regiones"]
            sol = [r for r, _ in t["solucion"]]
            problemas = []
            if not _validar_estructura(n, reg, sol):
                problemas.append("estructura")
            res = motor(n, reg, max_tier=4)
            if not res["solved"]:
                problemas.append("no resuelto por deducción")
            if contar_soluciones(n, reg, limite=2) != 1:
                problemas.append("no único")
            if problemas:
                fallos_nivel += 1
                print("FALLO", t["id"], problemas)
        fallos += fallos_nivel
        print(f"nivel {nivel}: {'OK' if not fallos_nivel else 'con fallos'}")
    print("AUTOTEST", "OK" if fallos == 0 else "CON FALLOS")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Generador de tableros Catdoku")
    p.add_argument("--nivel", type=int, choices=range(1, 6), default=1)
    p.add_argument("--n", type=int, default=None)
    p.add_argument("--semilla", type=int, default=None)
    p.add_argument("--json", action="store_true")
    p.add_argument("--solucion", action="store_true")
    p.add_argument("--bench", action="store_true")
    p.add_argument("--autotest", action="store_true")
    p.add_argument("--muestras", type=int, default=8)
    p.add_argument("--guardar", metavar="DIR", default=None,
                   help="guarda el tablero como JSON y TXT en DIR")
    a = p.parse_args(argv)

    rng = random.Random(a.semilla)
    if a.bench:
        bench(a.muestras, rng)
        return 0
    if a.autotest:
        autotest(a.muestras, rng)
        return 0

    t0 = time.time()
    tab = generar_tablero(a.nivel, rng, n=a.n)
    if a.guardar:
        from pathlib import Path
        d = Path(a.guardar)
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{tab['id']}.json").write_text(
            json.dumps(tab, ensure_ascii=False, indent=2), encoding="utf-8")
        (d / f"{tab['id']}.txt").write_text(
            render(tab, mostrar_solucion=True), encoding="utf-8")
        print(f"guardado en {d}/{tab['id']}.json")
    if a.json:
        print(json.dumps(tab, ensure_ascii=False))
    else:
        print(render(tab, mostrar_solucion=a.solucion))
        m = tab["metricas"]
        print()
        print(f"{tab['id']}  nivel {tab['nivel']} ({tab['nombre_nivel']})")
        print(f"puntuación {m['puntuacion']}  tier mínimo {m['tier_min']}  "
              f"pasos {m['pasos']}  primer gato tras {m['primer_gato']} pasos  "
              f"interbloqueo {m['interbloqueo']:.2f}")
        print(f"generado en {time.time() - t0:.2f}s, {tab['intentos']} intentos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
