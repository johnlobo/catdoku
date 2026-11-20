"""Catdoku tests.

Host checks run anywhere. The emulator checks build the game with GlasnostFWK and play it
in BluePixel headless; they are skipped when the emulator is not found.

    python3 -m unittest discover -s tests -v

Locations (environment variables, all optional):
    GLASNOST_ROOT        GlasnostFWK checkout (default: two folders above this project)
    BLUEPIXEL_HEADLESS   bluepixel-headless binary (default: <GlasnostFWK>/../BluePixel/build/)
    BLUEPIXEL_ROMS       ROM folder (default: <GlasnostFWK>/../BluePixel/web/roms)
    CATDOKU_SLOW=1       also regenerate the 200 levels and compare (about 1.5 minutes)
"""
from __future__ import annotations

import base64
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
GLASNOST = Path(os.environ.get("GLASNOST_ROOT", PROJECT.parents[1])).resolve()
BLUEPIXEL = GLASNOST.parent / "BluePixel"
HEADLESS = Path(os.environ.get("BLUEPIXEL_HEADLESS", BLUEPIXEL / "build" / "bluepixel-headless"))
ROMS = Path(os.environ.get("BLUEPIXEL_ROMS", BLUEPIXEL / "web" / "roms"))
DSK = PROJECT / "build" / "catdoku.dsk"
NOI = PROJECT / "build" / "obj" / "catdoku.noi"

# Keyboard matrix (row, mask with the key's bit at 0), as the BluePixel adapter expects.
KEYS = {"up": (0, 0xFE), "right": (0, 0xFD), "down": (0, 0xFB), "left": (1, 0xFE),
        "return": (2, 0xFB), "space": (5, 0x7F), "esc": (8, 0xFB)}

STATE_MENU, STATE_LEVEL_SELECT, STATE_RULES, STATE_CONFIRM_NEW = 0, 1, 7, 8
MENU_CONTINUE, MENU_RULES, MENU_AUTO_MARK = 1, 2, 3
SAVE_FLAG_AUTO_MARK = 0x80


def common_constant(name: str) -> int:
    match = re.search(rf"^{name}\s*=\s*(\S+)", (PROJECT / "common.inc").read_text(), re.M)
    return int(match.group(1), 0)


class HostChecks(unittest.TestCase):
    def test_states_and_save_layout_match_common_inc(self):
        for name, value in (("STATE_MENU", STATE_MENU), ("STATE_LEVEL_SELECT", STATE_LEVEL_SELECT),
                            ("STATE_RULES", STATE_RULES), ("STATE_CONFIRM_NEW", STATE_CONFIRM_NEW)):
            self.assertEqual(common_constant(name), value, name)
        save = (PROJECT / "save.s").read_text()
        self.assertRegex(save, r"SAVE_FLAG_AUTO_MARK = 0x80")

    def test_level_table_is_consistent(self):
        text = (PROJECT / "generated" / "catdoku_levels.s").read_text()
        entries = [tuple(map(int, m)) for m in re.findall(r"^\s+\.dw (\d+), (\d+), (\d+)$", text, re.M)]
        self.assertEqual(len(entries), 200)
        offset = 0
        for index, (start, packed, unpacked) in enumerate(entries):
            self.assertEqual(start, offset, f"level {index} does not follow the previous one")
            n = 5 + index // 40
            self.assertEqual(unpacked, 6 + n * n + 2 * n, f"level {index}: header + grid + cats")
            offset += packed
        packed_bytes = sum(len(re.findall(r"0x[0-9A-F]{2}", line))
                           for line in text.split("catdoku_levels_packed::", 1)[1].splitlines()
                           if line.strip().startswith(".db"))
        self.assertEqual(packed_bytes, offset)

    @unittest.skipUnless(os.environ.get("CATDOKU_SLOW") == "1", "set CATDOKU_SLOW=1 (about 1.5 minutes)")
    def test_the_generator_reproduces_the_levels(self):
        result = subprocess.run([sys.executable, str(PROJECT / "scripts" / "gen_catdoku_levels.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


def emulator_available() -> bool:
    return HEADLESS.exists() and ROMS.is_dir() and (GLASNOST / "bin" / "glasnost").exists()


@unittest.skipUnless(emulator_available(), f"BluePixel headless not found at {HEADLESS}")
class Emulator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(GLASNOST / "tools" / "glasnost"))
        global BluePixel
        from bluepixel_adapter import BluePixel  # noqa: PLW0603 (imported only when present)
        build = subprocess.run([str(GLASNOST / "bin" / "glasnost"), "build", "--project", str(PROJECT)],
                               capture_output=True, text=True)
        if build.returncode != 0:
            raise RuntimeError("glasnost build failed:\n" + build.stdout[-2000:] + build.stderr[-2000:])

    # -- helpers ------------------------------------------------------------------
    def boot(self, disk: Path = DSK):
        emu = BluePixel(HEADLESS, ROMS)
        self.addCleanup(emu.close)
        emu.load(disk, NOI)
        emu.boot('run"catdoku', "catdoku_save_loaded", 1)
        emu.run(300)                       # menu drawn
        return emu

    @staticmethod
    def tap(emu, key: str, frames: int = 12):
        row, mask = KEYS[key]
        emu.key(row, mask, True)
        emu.run(4)
        emu.key(row, mask, False)
        emu.run(frames)

    @staticmethod
    def byte(emu, symbol: str) -> int:
        return emu.read(symbol)[0]

    def open_level(self, emu, difficulty: int = 0):
        self.tap(emu, "return", 30)        # NEW GAME (no progress: no question)
        for _ in range(difficulty):
            self.tap(emu, "space", 40)
        self.tap(emu, "return", 150)
        self.assertEqual(self.byte(emu, "game_state"), 2)

    @staticmethod
    def screen(emu, x: int, y: int, length: int) -> bytes:
        return emu.read(0xC000 + 80 * (y // 8) + 2048 * (y & 7) + x, length)

    def export(self, emu) -> Path:
        image = base64.b64decode(emu.call("disc.export", {"drive": 0})["data_base64"])
        path = Path(tempfile.mkdtemp(prefix="catdoku-")) / "catdoku.dsk"
        path.write_bytes(image)
        return path

    def toggle_auto_mark(self, emu):
        for _ in range(3):
            self.tap(emu, "down")
        self.assertEqual(self.byte(emu, "menu_selection"), MENU_AUTO_MARK)
        self.tap(emu, "return", 200)       # flips it and writes CATDOKU.SAV

    # -- tests --------------------------------------------------------------------
    def test_auto_mark_marks_row_column_region_and_neighbours(self):
        for enabled in (False, True):
            with self.subTest(auto_mark=enabled):
                emu = self.boot()
                if enabled:
                    self.toggle_auto_mark(emu)
                    for _ in range(3):
                        self.tap(emu, "up")
                self.open_level(emu)
                n = self.byte(emu, "catdoku_n")
                grid = list(emu.read("catdoku_grid", n * n))
                row, col = emu.read("catdoku_cats", 2)
                for _ in range(row):
                    self.tap(emu, "down")
                for _ in range(col):
                    self.tap(emu, "right")
                self.tap(emu, "return", 40)
                marks = list(emu.read("catdoku_marks", n * n))
                expected = []
                for r in range(n):
                    for c in range(n):
                        if (r, c) == (row, col):
                            expected.append(1)
                        elif enabled and (r == row or c == col or (abs(r - row) <= 1 and abs(c - col) <= 1)
                                          or grid[r * n + c] == grid[row * n + col]):
                            expected.append(2)
                        else:
                            expected.append(0)
                self.assertEqual(marks, expected)

    def test_auto_mark_option_survives_a_reboot(self):
        emu = self.boot()
        self.toggle_auto_mark(emu)
        self.assertTrue(emu.read("catdoku_save_buffer", 8)[7] & SAVE_FLAG_AUTO_MARK)
        disk = self.export(emu)
        again = self.boot(disk)
        self.assertTrue(again.read("catdoku_save_buffer", 8)[7] & SAVE_FLAG_AUTO_MARK)

    def test_rules_screen_and_cursor_leave_the_board_intact(self):
        emu = self.boot()
        self.tap(emu, "down")              # CONTINUE is disabled: down goes to RULES
        self.assertEqual(self.byte(emu, "menu_selection"), MENU_RULES)
        self.tap(emu, "return", 30)
        self.assertEqual(self.byte(emu, "game_state"), STATE_RULES)
        self.tap(emu, "return", 30)
        self.assertEqual(self.byte(emu, "game_state"), STATE_MENU)
        self.tap(emu, "up")
        self.open_level(emu)
        n, bx, by = self.byte(emu, "catdoku_n"), self.byte(emu, "board_x"), self.byte(emu, "board_y")

        def board():
            return b"".join(self.screen(emu, bx - 1, y, 8 * n + 2) for y in range(by - 1, by + 16 * n + 1))

        before = board()
        for key in ["right", "down", "right", "down", "left", "up", "left", "up"]:
            self.tap(emu, key)
        for key in ("right", "down", "left", "up"):
            for _ in range(n - 1):
                self.tap(emu, key)
        self.assertEqual(board(), before, "moving the cursor around changed the board")

    def test_held_cursor_repeats_after_15_frames_then_every_4(self):
        emu = self.boot()
        self.open_level(emu)
        self.tap(emu, "right", 40)
        self.assertEqual(self.byte(emu, "cursor_col"), 1, "a tap moves one cell")
        self.tap(emu, "left", 40)
        emu.key(*KEYS["right"], True)
        trace = []
        for _ in range(30):
            emu.run(1)
            trace.append(self.byte(emu, "cursor_col"))
        emu.key(*KEYS["right"], False)
        steps = [i for i in range(1, 30) if trace[i] != trace[i - 1]]
        self.assertEqual([b - a for a, b in zip(steps, steps[1:])], [15, 4, 4], trace)

    def test_menu_indicator_is_the_small_cat(self):
        # The indicator is the 8x8 icon (bytes 22..25), not a slice of the 16x16 board cat.
        emu = self.boot()
        rows = [self.screen(emu, 22, y, 5) for y in range(100, 200)]   # byte 27 on: AUTO MARK
        self.assertTrue(any(any(row[:4]) for row in rows), "no indicator")
        self.assertFalse(any(any(row[4:]) for row in rows), "indicator wider than 4 bytes")
        drawn = [row[:4] for row in rows if any(row[:4])]
        self.assertEqual(len(drawn), 5, "the icon has 5 lines of pixels")

    def test_every_board_size_is_centred(self):
        for difficulty in range(5):
            with self.subTest(n=5 + difficulty):
                emu = self.boot()
                self.open_level(emu, difficulty)
                columns, lines = set(), set()
                for y in range(18, 189):        # between the time (8..16) and the help (190..)
                    row = self.screen(emu, 0, y, 80)
                    for x, value in enumerate(row):
                        if value:
                            columns.add(x)
                            lines.add(y)
                left, right = min(columns), max(columns)
                self.assertLessEqual(abs(left - (79 - right)), 1, (left, right))
                self.assertLessEqual(abs((min(lines) + max(lines)) / 2 - 100), 2)

    def test_new_game_asks_before_erasing_and_continue_needs_progress(self):
        emu = self.boot()
        self.assertEqual(self.byte(emu, "catdoku_save_count"), 0)
        self.tap(emu, "down")
        self.assertEqual(self.byte(emu, "menu_selection"), MENU_RULES, "disabled CONTINUE is skipped")
        self.tap(emu, "up")
        self.assertEqual(self.byte(emu, "menu_selection"), 0)
        # One completed level (id 3, 77 s), then redraw the menu.
        for offset, value in enumerate((3, 77, 0, 0, 0)):
            emu.write(f"catdoku_save_buffer + {8 + offset}", value)
        emu.write("catdoku_save_count", 1)
        emu.write("menu_dirty", 1)
        emu.run(30)
        self.tap(emu, "down")
        self.assertEqual(self.byte(emu, "menu_selection"), MENU_CONTINUE)
        self.tap(emu, "up")
        self.tap(emu, "return", 60)
        self.assertEqual(self.byte(emu, "game_state"), STATE_CONFIRM_NEW)
        self.tap(emu, "esc", 60)
        self.assertEqual((self.byte(emu, "game_state"), self.byte(emu, "catdoku_save_count")), (STATE_MENU, 1))
        self.tap(emu, "return", 60)
        self.tap(emu, "return", 300)
        self.assertEqual((self.byte(emu, "game_state"), self.byte(emu, "catdoku_save_count")),
                         (STATE_LEVEL_SELECT, 0))
        again = self.boot(self.export(emu))
        self.assertEqual(self.byte(again, "catdoku_save_count"), 0)
        self.assertEqual(again.read("catdoku_save_buffer", 7), b"CATDOKU")

    def test_the_time_is_centred_as_it_grows(self):
        emu = self.boot()
        self.open_level(emu)
        for seconds in (2, 12):
            emu.run(50 * seconds)
            with self.subTest(seconds=self.byte(emu, "game_timer_seconds")):
                columns = {x for y in range(8, 17) for x, value in enumerate(self.screen(emu, 0, y, 80)) if value}
                self.assertTrue(columns, "the time is not drawn")
                self.assertLessEqual(abs(min(columns) - (79 - max(columns))), 1, sorted(columns))

    def test_a_version_1_save_forgets_progress_and_keeps_auto_mark(self):
        emu = self.boot()
        # A version-1 file with AUTO MARK off and one completed level: the toggle
        # below sets AUTO MARK and writes these bytes to the disc as they are.
        emu.write("catdoku_save_buffer + 7", 0x01)
        for offset, value in enumerate((3, 77, 0, 0, 0)):
            emu.write(f"catdoku_save_buffer + {8 + offset}", value)
        emu.write("catdoku_save_count", 1)
        self.toggle_auto_mark(emu)
        self.assertEqual(emu.read("catdoku_save_buffer", 9)[7:], bytes((0x81, 3)))
        again = self.boot(self.export(emu))
        self.assertEqual(self.byte(again, "catdoku_save_count"), 0)
        self.assertEqual(again.read("catdoku_save_buffer", 9)[7:], bytes((0x82, 0xFF)),
                         "version 2 with AUTO MARK kept, no level")


if __name__ == "__main__":
    unittest.main()
