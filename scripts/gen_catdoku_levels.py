#!/usr/bin/env python3
"""Generate 200 Catdoku levels (40 per difficulty) as ZX7B-compressed .s file.

The puzzles come from catdoku/doc/generador_catdoku.py (the reference
implementation of catdoku/doc/compendio-catdoku.md), imported as a module, with
fixed seeds, so the output is reproducible. Catdoku accepts a board with its own
bands (BANDS below) instead of the reference ones: the hardest technique a board
needs, and how many times it needs T4 ("probar y descartar"). Each difficulty is
then ordered from easiest to hardest.

    python3 scripts/gen_catdoku_levels.py           # rewrite generated/catdoku_levels.s
    python3 scripts/gen_catdoku_levels.py --check   # exit 1 if it would change

zx7b comes from $ZX7B, else the CPCtelera of $CPCT_PATH, else the one
`glasnost path` reports (GlasnostFWK checkout two levels up).
"""

import argparse
import importlib.util
import json
import subprocess
import os
import random
import shutil
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR = os.path.join(HERE, "..", "catdoku", "doc", "generador_catdoku.py")
OUTPUT_DIR = os.path.join(HERE, "..", "generated")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "catdoku_levels.s")
TEMP_DIR = None   # set in main()


def find_zx7b():
    """zx7b executable: $ZX7B, $CPCT_PATH, then `glasnost path`."""
    if os.environ.get("ZX7B"):
        return os.environ["ZX7B"]
    roots = []
    if os.environ.get("CPCT_PATH"):
        roots.append(os.environ["CPCT_PATH"])
    glasnost = os.path.join(HERE, "..", "..", "..", "bin", "glasnost")
    if os.path.exists(glasnost):
        found = subprocess.run([glasnost, "path"], capture_output=True, text=True)
        if found.returncode == 0 and found.stdout.strip():
            roots.append(found.stdout.strip())
    for root in roots:
        candidate = os.path.join(root, "tools", "zx7b", "bin", "zx7b")
        if os.path.exists(candidate):
            return candidate
    found = shutil.which("zx7b")
    if found:
        return found
    sys.exit("zx7b not found: set ZX7B or CPCT_PATH")

# 40 levels per difficulty, n=5..9
DIFFICULTIES = [
    (1, 5, 40),   # Iniciación
    (2, 6, 40),   # Fácil
    (3, 7, 40),   # Medio
    (4, 8, 40),   # Difícil
    (5, 9, 40),   # Experto
]

# Catdoku difficulty curve. tier = (lowest, highest) technique the board needs at
# least (tier_min of the reference: T1 forced cells, T2 one-unit pigeonhole,
# T3 two/three-unit pigeonhole, T4 trial and contradiction); t4 = how many steps
# need T4. pasos = deduction steps / n^2, as in the reference NIVELES.
BANDS = {
    1: dict(tier=(1, 2), t4=(0, 0),   pasos=(0.00, 1.00)),   # Iniciación 5x5
    2: dict(tier=(2, 3), t4=(0, 0),   pasos=(0.00, 1.00)),   # Fácil 6x6
    3: dict(tier=(3, 3), t4=(0, 0),   pasos=(0.00, 1.00)),   # Medio 7x7: no trial
    4: dict(tier=(4, 4), t4=(1, 10),  pasos=(0.30, 1.00)),   # Difícil 8x8
    5: dict(tier=(4, 4), t4=(11, 99), pasos=(0.50, 1.00)),   # Experto 9x9
}
RETRIES = 20                     # seeds tried per level before giving up


def load_generator():
    spec = importlib.util.spec_from_file_location("generador_catdoku", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module          # dataclasses look their module up here
    spec.loader.exec_module(module)
    return module


def fits(m, nivel, n):
    band = BANDS[nivel]
    return (m.n == n
            and band["tier"][0] <= m.tier_min <= band["tier"][1]
            and band["t4"][0] <= m.t4 <= band["t4"][1]
            and band["pasos"][0] <= m.pasos / (m.n * m.n) <= band["pasos"][1])


def generate_level(job):
    """One board for (difficulty, n, seed); other seeds derived from it if that one fails."""
    difficulty, n, seed = job
    gen = load_generator()
    gen.encaja = lambda m, nivel: fits(m, nivel, n)   # catdoku bands, same search
    for retry in range(RETRIES):
        try:
            return gen.generar_tablero(difficulty, random.Random(seed + retry * 1_000_003), n=n,
                                       max_intentos=5000)
        except RuntimeError:
            continue
    raise RuntimeError(f"no board for difficulty {difficulty} (n={n}) from seed {seed}")


def difficulty_key(level):
    """Order inside a difficulty: fewer T4 steps, then lower technique, then fewer steps."""
    m = level["metricas"]
    return (m["t4"], m["tier_min"], m["pasos"], level["id"])

def level_to_binary(level_data, level_id):
    """Convert level JSON to binary format."""
    n = level_data["n"]
    regiones = level_data["regiones"]
    solucion = level_data["solucion"]
    
    # Count unique colours
    colours = set()
    for row in regiones:
        for c in row:
            colours.add(c)
    num_colours = len(colours)
    num_cats = len(solucion)
    
    # Header (6 bytes)
    header = bytes([
        level_id & 0xFF,
        level_data["nivel"] & 0xFF,
        n & 0xFF,
        num_colours & 0xFF,
        num_cats & 0xFF,
        0  # checksum (placeholder)
    ])
    
    # Grid (n*n bytes)
    grid = bytes([regiones[r][c] for r in range(n) for c in range(n)])
    
    # Cats (num_cats * 2 bytes)
    cats = bytes([solucion[i][0] for i in range(num_cats) for _ in [0]] +
                  [solucion[i][1] for i in range(num_cats) for _ in [0]])
    # Actually: interleave row, col
    cats = []
    for s in solucion:
        cats.append(s[0])
        cats.append(s[1])
    cats = bytes(cats)
    
    return header + grid + cats

def compress_level(raw_data, level_id):
    """Compress raw level data with ZX7B."""
    os.makedirs(TEMP_DIR, exist_ok=True)
    input_path = os.path.join(TEMP_DIR, f"level_{level_id}.bin")
    output_path = os.path.join(TEMP_DIR, f"level_{level_id}.zx7")
    with open(input_path, "wb") as f:
        f.write(raw_data)
    subprocess.run([ZX7B, input_path, output_path], check=True, capture_output=True)
    with open(output_path, "rb") as f:
        return f.read()

def bytes_to_db(data):
    """Convert bytes to .db assembly lines."""
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_vals = ", ".join(f"0x{b:02X}" for b in chunk)
        lines.append(f"    .db {hex_vals}")
    return "\n".join(lines)

def main():
    global TEMP_DIR, ZX7B
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="compare with generated/catdoku_levels.s instead of writing it")
    args = parser.parse_args()
    ZX7B = find_zx7b()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    TEMP_DIR = tempfile.mkdtemp(prefix="catdoku_gen_")
    
    jobs = []
    for difficulty, n, count in DIFFICULTIES:
        base = len(jobs)
        jobs += [(difficulty, n, (base + i) * 1000 + difficulty * 100 + i) for i in range(count)]
    print(f"Generating {len(jobs)} levels...")
    try:
        with ProcessPoolExecutor() as pool:
            boards = list(pool.map(generate_level, jobs))
    except RuntimeError as error:
        sys.exit(f"Failed: {error}")

    ordered = []
    for difficulty, _, _ in DIFFICULTIES:
        group = sorted((b for b in boards if b["nivel"] == difficulty), key=difficulty_key)
        ordered += group
        t4 = [b["metricas"]["t4"] for b in group]
        tiers = sorted({b["metricas"]["tier_min"] for b in group})
        print(f"  difficulty {difficulty}: techniques {tiers}, T4 steps {t4[0]}..{t4[-1]}")

    level_id = 0
    entries = []
    packed_data = bytearray()

    for level_data in ordered:
        raw = level_to_binary(level_data, level_id)
        compressed = compress_level(raw, level_id)
        entries.append((len(packed_data), len(compressed), len(raw)))
        packed_data.extend(compressed)
        level_id += 1

    # Generate .s file
    output_path = os.path.join(TEMP_DIR, "catdoku_levels.s")
    with open(output_path, "w") as f:
        f.write(";; generated/catdoku_levels.s - 200 Catdoku levels (ZX7B compressed)\n")
        f.write(";; Generated by scripts/gen_catdoku_levels.py\n")
        f.write(";; Do not edit manually.\n\n")
        f.write(".module catdoku_levels\n\n")
        f.write(".area _DATA\n")
        f.write("catdoku_decomp_buffer:: .ds 128    ;; decompression buffer\n\n")
        f.write(".area _CODE\n\n")
        f.write(".globl catdoku_decomp_buffer, catdoku_level_table, catdoku_levels_packed\n\n")
        f.write(";; Level table: 200 entries x 6 bytes (offset, packed_size, unpacked_size)\n")
        f.write("catdoku_level_table::\n")
        for offset, packed_size, unpacked_size in entries:
            f.write(f"    .dw {offset}, {packed_size}, {unpacked_size}\n")
        f.write("\n")
        f.write(";; Compressed level data\n")
        f.write("catdoku_levels_packed::\n")
        f.write(bytes_to_db(bytes(packed_data)))
        f.write("\n\n")
        f.write(f"CATDOKU_NUM_LEVELS .equ {len(entries)}\n")
        f.write("CATDOKU_DECOMP_BUFFER_SIZE .equ 128\n")
    
    with open(output_path) as f:
        text = f.read()
    shutil.rmtree(TEMP_DIR, ignore_errors=True)
    print(f"Generated {len(entries)} levels, {len(packed_data)} bytes compressed.")
    if args.check:
        with open(OUTPUT_PATH) as f:
            same = f.read() == text
        print("generated/catdoku_levels.s is up to date" if same
              else "generated/catdoku_levels.s differs from the generator output")
        return 0 if same else 1
    with open(OUTPUT_PATH, "w") as f:
        f.write(text)
    print(f"Output: {OUTPUT_PATH}")
    return 0

if __name__ == "__main__":
    sys.exit(main())