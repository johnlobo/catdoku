#!/usr/bin/env python3
"""Generate 200 Catdoku levels (40 per difficulty) as ZX7B-compressed .s file.

The puzzles come from catdoku/doc/generador_catdoku.py (the reference
implementation of catdoku/doc/compendio-catdoku.md) with fixed seeds, so the
output is reproducible.

    python3 scripts/gen_catdoku_levels.py           # rewrite generated/catdoku_levels.s
    python3 scripts/gen_catdoku_levels.py --check   # exit 1 if it would change (about 3 min)

zx7b comes from $ZX7B, else the CPCtelera of $CPCT_PATH, else the one
`glasnost path` reports (GlasnostFWK checkout two levels up).
"""

import argparse
import json
import subprocess
import os
import shutil
import sys
import tempfile

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

def generate_level(difficulty, n, seed):
    """Generate a single level using the Python generator."""
    cmd = [
        sys.executable, GENERATOR,
        "--nivel", str(difficulty),
        "--n", str(n),
        "--semilla", str(seed),
        "--json"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error generating level: {result.stderr}", file=sys.stderr)
        return None
    return json.loads(result.stdout)

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
    
    level_id = 0
    entries = []
    packed_data = bytearray()
    
    for difficulty, n, count in DIFFICULTIES:
        print(f"Generating difficulty {difficulty} (n={n}, {count} levels)...")
        for i in range(count):
            seed = level_id * 1000 + difficulty * 100 + i
            level_data = generate_level(difficulty, n, seed)
            if level_data is None:
                sys.exit(f"Failed to generate level {level_id}: the table would shift")
            
            raw = level_to_binary(level_data, level_id)
            compressed = compress_level(raw, level_id)
            
            offset = len(packed_data)
            packed_size = len(compressed)
            unpacked_size = len(raw)
            
            entries.append((offset, packed_size, unpacked_size))
            packed_data.extend(compressed)
            
            level_id += 1
            if level_id % 10 == 0:
                print(f"  Generated {level_id} levels...")
    
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