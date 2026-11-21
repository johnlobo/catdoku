"""Reference model of hint.s: the hint for a board state, rule for rule.

State: n, grid (n*n region ids), cats (solution (row, col) pairs in the
order of catdoku_cats), marks (n*n: 0 empty, 1 cat, 2 X).

A cell is a candidate when it is empty and no placed cat shares its row,
column or region or touches it. Units: rows 0..n-1, columns 0..n-1, regions
0..n-1, in that order. The hint is the first that applies of:

  ERR    an X on a solution cell (first in cats order)
  RULED  empty cells that are not candidates (a placed cat rules them out)
  ONE    a unit without a cat with a single candidate
  FIT    k units of family A (k = 1, 2, 3) without cats whose candidates lie
         in k units of family B, when that rules out a candidate outside them.
         Pairs, in order: regions->rows, regions->columns, rows->regions,
         columns->regions. Subsets in increasing bit-mask order.
  TRIAL  the first non-solution candidate where a cat leads, by placing the
         single candidates one after another, to a unit with no candidate;
         else the first non-solution candidate.
"""

NONE, ERR, RULED, ONE, FIT, TRIAL = range(6)
PAIRS = ((2, 0), (2, 1), (0, 2), (1, 2))


def family(n, grid, i, f):
    return (i // n, i % n, grid[i])[f]


def compute(n, grid, marks, cats):
    has = [[False] * n for _ in range(3)]
    for i in range(n * n):
        if cats[i]:
            for f in range(3):
                has[f][family(n, grid, i, f)] = True
    cand = [False] * (n * n)
    count = [[0] * n for _ in range(3)]
    last = [[0] * n for _ in range(3)]
    for i in range(n * n):
        if marks[i] or cats[i] or any(has[f][family(n, grid, i, f)] for f in range(3)):
            continue
        r, c = divmod(i, n)
        if any(cats[rr * n + cc] for rr in (r - 1, r, r + 1) for cc in (c - 1, c, c + 1)
               if 0 <= rr < n and 0 <= cc < n and (rr, cc) != (r, c)):
            continue
        cand[i] = True
        for f in range(3):
            u = family(n, grid, i, f)
            count[f][u] += 1
            last[f][u] = i
    return cand, has, count, last


def single(n, has, count, last):
    for f in range(3):
        for u in range(n):
            if not has[f][u] and count[f][u] == 1:
                return f, u, last[f][u]
    return None


def contradiction(n, has, count):
    return any(not has[f][u] and count[f][u] == 0 for f in range(3) for u in range(n))


def hint(n, grid, cats, marks):
    """Returns (kind, target cell, blinking cells, extra): extra is the family
    for ONE and (k, family A, family B) for FIT."""
    solution = [r * n + c for r, c in cats]
    missing = next((i for i in solution if marks[i] != 1), None)
    for i in solution:
        if marks[i] == 2:
            return ERR, i, {i}, None
    placed = [m == 1 for m in marks]
    cand, has, count, last = compute(n, grid, marks, placed)
    ruled = {i for i in range(n * n) if marks[i] == 0 and not cand[i]}
    if ruled:
        return RULED, missing, ruled, None
    found = single(n, has, count, last)
    if found:
        f, u, i = found
        return ONE, i, {j for j in range(n * n) if family(n, grid, j, f) == u}, f
    for k in (1, 2, 3):
        for fa, fb in PAIRS:
            mask = [0] * n
            for i in range(n * n):
                if cand[i]:
                    mask[family(n, grid, i, fa)] |= 1 << family(n, grid, i, fb)
            valid = sum(1 << a for a in range(n) if not has[fa][a] and mask[a])
            for s in range(1, 1 << n):
                if s & ~valid or bin(s).count("1") != k:
                    continue
                union = 0
                for a in range(n):
                    if s >> a & 1:
                        union |= mask[a]
                if bin(union).count("1") != k:
                    continue
                if any(cand[i] and union >> family(n, grid, i, fb) & 1 and not s >> family(n, grid, i, fa) & 1
                       for i in range(n * n)):
                    blink = {i for i in range(n * n) if s >> family(n, grid, i, fa) & 1}
                    return FIT, missing, blink, (k, fa, fb)
    first = None
    for i in range(n * n):
        if not cand[i] or i in solution:
            continue
        if first is None:
            first = i
        trial = placed[:]
        trial[i] = True
        while True:
            _, t_has, t_count, t_last = compute(n, grid, marks, trial)
            if contradiction(n, t_has, t_count):
                return TRIAL, i, {i}, None
            step = single(n, t_has, t_count, t_last)
            if not step:
                break
            trial[step[2]] = True
    if first is not None:
        return TRIAL, first, {first}, None
    return NONE, None, set(), None


def apply(n, grid, marks, found):
    """Plays a hint as a player who understood it: RULED and FIT put their X,
    ONE puts the cat, TRIAL puts the X on the tried cell. Changes marks."""
    kind, target, blink, extra = found
    if kind == RULED:
        for i in blink:
            marks[i] = 2
    elif kind == ONE:
        marks[target] = 1
    elif kind == TRIAL:
        marks[target] = 2
    elif kind == FIT:
        _, fa, fb = extra
        cand = compute(n, grid, marks, [m == 1 for m in marks])[0]
        chosen = {family(n, grid, i, fa) for i in blink}
        inside = {family(n, grid, i, fb) for i in range(n * n) if cand[i] and family(n, grid, i, fa) in chosen}
        for i in range(n * n):
            if cand[i] and family(n, grid, i, fb) in inside and family(n, grid, i, fa) not in chosen:
                marks[i] = 2
