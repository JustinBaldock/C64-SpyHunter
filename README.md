# C64 Spy Hunter — Reverse Engineering

An in-progress reverse-engineering of the 1984 Commodore 64 cartridge port of
**Spy Hunter** (Bally/U.S. Gold/Sega). The goal is a fully annotated,
byte-identical-reassembling disassembly — real 6502 mnemonics with meaningful
labels and comments, not just raw opcodes — plus a written-up understanding of
how the game actually works internally.

> This is a personal research project for learning/preservation purposes. It
> requires the original cartridge ROM (not included) to build and run.

## What's in this repo

| Path | Contents |
|---|---|
| [`disassembly/`](disassembly/) | The annotated source (`spyhunter.asm`), linker config, `Makefile`, and build docs. |
| [`claude/`](claude/) | Write-ups of specific findings — enemies, scoring, the road/level graph, the boat crossing, the weapons van, collision handling, etc. |
| [`tools/`](tools/) | Small Python utilities built along the way (see [Tools](#tools) below). |
| [`original_files/`](original_files/) | The source cartridge dump and the scanned/OCR'd game manual. |
| [`references/`](references/) | 6502/cc65 reference material used while annotating. |

## The process

The disassembly started from a straight-line disassembly of the 16 KB
cartridge ROM (`$8000`–`$BFFF`) and has been built up in passes:

1. **Get a byte-identical baseline.** Every single edit — renaming a label,
   adding a comment, converting a data blob to real instructions — is
   verified by reassembling and comparing the MD5 of the output against the
   original ROM. Comments and labels can never change what actually gets
   assembled; this is treated as a hard invariant throughout.
2. **Annotate in stages**, working through the ROM one functional area at a
   time: boot/init, the raster-IRQ system (split-screen + sprite
   multiplexing), the playfield/charset drawing code, the moving-object
   system, the road/segment engine, the road/graphics data tables, the
   status panel and input handling, and the sound engine. Each stage adds
   real names for routines and variables and prose comments explaining what
   a novice 6502 reader would need to know.
3. **Cross-check against live gameplay.** Many routines are only reachable
   through runtime dispatch tables (per-object "move" and "draw" vectors), so
   a static pass alone can't identify what a lot of the ROM does. To get
   past that, dozens of **VICE emulator snapshots** (`.vsf` files) were
   captured at specific in-game moments — crashing into the boat hazard, the
   broken bridge, entering/exiting the weapons van, encountering different
   enemy types, the icy road, lap completion — and a small extraction tool
   (`vsf_extract.py`) pulls out RAM state and the CPU program counter at the
   moment of capture. Cross-referencing a captured PC against the dispatch
   tables tells you exactly which handler was executing, which is how the
   largest remaining "reached only indirectly" blocks have been getting
   peeled off.
4. **Cross-check against the original manual.** The scanned game manual
   (`original_files/Spy_Hunter_1984_Sega_text.pdf`) documents the six enemy
   agents, their weapons, and the exact scoring table. This turned out to
   match a data table in the ROM byte-for-byte (see
   [Scoring](#scoring) below) — strong independent confirmation that the
   reverse-engineering is on the right track, and a way to resolve
   ambiguities (e.g. why one enemy never registers a hit) from primary
   design intent rather than guesswork alone.
5. **Verify dense/overlapping code mechanically, not by eye.** Some blocks
   use classic size-optimization tricks — a `BIT $abs` instruction used
   purely to skip the next two bytes, or the same bytes decoding into
   different instructions depending on which address you jump to. Hand-
   transcribing this kind of code is error-prone (this project has hit real
   bugs doing it by hand); the more reliable approach used for the densest
   blocks was to generate the annotated instruction stream programmatically
   from a verified disassembly and diff the reassembled bytes against the
   ROM before ever touching the real source file.

### Current status

- **479 labels**, of which all but a handful now have descriptive names
  (rather than auto-generated addresses like `L9E50`).
- Roughly **three-quarters of the ROM's bytes** are now real, annotated 6502
  instructions (the rest is either legitimate graphics/table data, which is
  already identified and documented, or a handful of remaining "reached only
  via a runtime dispatch vector" code blocks — the largest around ~1.6 KB —
  flagged in the source for a future pass).
- The `claude/*.md` files capture everything that's been resolved via
  snapshot analysis or the manual, including a few open questions that are
  still just educated guesses (flagged `(???)` throughout `spyhunter.asm`).

## Spy Hunter — game design summary

*(Assembled from the official manual and confirmed against the ROM; see
[`claude/Enemy_Agents_Manual_Reference.md`](claude/Enemy_Agents_Manual_Reference.md)
for full detail and citations.)*

You drive the **Spy Car** (an armed, gadget-equipped vehicle) along a
continuous, scrolling course: **road → boathouse (car becomes an amphibious
boat) → water → more road**, including a bridge stretch and an icy road
stretch where the car is harder to control. Weapons and special equipment are
granted by docking with the **Weapons Van**, which briefly freezes the road
and timer while you're inside it.

### Enemy Agents

Six named enemies oppose you, each (except the Road Lord) with its own
weapon:

| Enemy | Weapon / behaviour | Points |
|---|---|---|
| **The Road Lord** | Bulletproof — can only be defeated by ramming it off the road | 150 |
| **Switch Blade** | Extends buzz-saw hubcaps to slash your car | 150 |
| **The Enforcer** | Fires a shotgun | 500 |
| **The Copter** ("Mad Bomber") | Drops bombs onto the Spy Car | 700 |
| **Barrel Dumper** | A boat — dumps barrels in the water ahead of you | 150 |
| **Doctor Torpedo** | A boat — fires torpedoes at you | 500 |

The Road Lord being *deliberately* bulletproof — not a bug — resolved an
early mystery in this project where shooting an enemy on the bridge appeared
to do nothing.

### Scoring

Driving itself scores points, at a higher rate on the road than on water,
plus one-off bonuses for destroying enemies and for crossing the
land/water boundary:

| Source | Points |
|---|---|
| Travelling on the road | 25 / quarter-screen |
| Travelling on the water | 15 / quarter-screen |
| Destroying Road Lord / Switch Blade / Barrel Dumper | 150 |
| Destroying The Enforcer / Doctor Torpedo | 500 |
| Destroying The Copter | 700 |
| Entering or exiting the boathouse | 1500 |

This entire table was found **byte-for-byte** in the ROM's scoring lookup
table — a rare case of the disassembly directly confirming a primary source
with nothing left unexplained.

### Difficulty

Two modes: **Novice** (a countdown timer, unlimited cars until it runs out,
then a set number of extra lives) and **Expert** (same timer, tougher
enemies, fewer starting lives, less frequent extra-life bonuses).

## Building the `.prg`

The build reassembles the 16 KB cartridge ROM from source and wraps it in a
disk-loadable, self-relocating `.prg` (the original is a cartridge, so a
plain disk image can't reproduce it directly — see
[`disassembly/BUILD.md`](disassembly/BUILD.md) for exactly why, and how the
loader stub works around it).

### Tools needed

- **[cc65](https://cc65.github.io/)** — provides `ca65` (assembler) and
  `ld65` (linker).
  - macOS: `brew install cc65`
  - Debian/Ubuntu: `sudo apt-get install cc65`
- **Python 3** — used by the `.prg` builder script (and by the analysis
  tools in `tools/`).
- Optional: **[VICE](https://vice-emu.sourceforge.io/)** (`x64sc`) to run
  the result, and `md5`/`md5sum` to verify the rebuilt ROM.

### Build

```sh
cd disassembly
make            # -> spyhunter.bin (raw ROM) and spyhunter.prg (disk-loadable)
make verify     # rebuild and check the ROM's MD5 against the known-good hash
make clean
```

Or run the two steps by hand:

```sh
cd disassembly
ca65 -t c64 spyhunter.asm -o spyhunter.o
ld65 -C spyhunter.cfg spyhunter.o -o spyhunter.bin   # raw 16 KB ROM, $8000-$BFFF
cp spyhunter.bin spyhunter.rom
python3 build_prg.py                                  # -> spyhunter.prg
```

Run it with `x64sc spyhunter.prg`, or write `spyhunter.prg` to a `.d64` and
`LOAD"*",8,1 : RUN`. The raw `spyhunter.bin` can also be run directly as a
16 KB cartridge image in an emulator that supports one.

> **Note on the starting-lives cheat:** `spyhunter.asm` currently ships with
> `LIVES` set to `#$7F` (127) instead of the original game's `#$01`, to make
> manual exploration easier — clearly marked with an `<<< EDIT HERE` comment
> at the assignment site. This means the rebuilt ROM's MD5
> (`5af76758a98f7fc30dda87e48f94f5db`) differs from the untouched original
> dump's MD5 (`ee7fe8c9a5179aa8b23d8f1e49cf113c`); everything else in the
> file reassembles byte-for-byte identical to the original cartridge. Set it
> back to `#$01` for a bit-for-bit rebuild of the original ROM.

## Tools

Small utilities built while working through the ROM, in [`tools/`](tools/):

| Tool | Purpose |
|---|---|
| `vsf_extract.py` | Pulls RAM contents, game-state variables, and the CPU program counter out of a VICE `.vsf` snapshot — the key tool for cross-referencing a captured moment in gameplay against the disassembly. |
| `disasm6502.py` | A minimal standalone 6502 disassembler (official opcodes only), used to independently verify hand-analysis of dense/overlapping code before it's committed to `spyhunter.asm`. |
| `emu6502.py` | A cycle-inexact 6502 + C64 emulator (memory banking, raster, CIA, SID) used early on to trace which code paths are actually reachable and validate the disk-loader stub. |
| `build_prg.py` | Wraps the assembled ROM image in a self-relocating, disk-loadable `.prg`. |

## Further reading

The [`claude/`](claude/) directory has a write-up per topic — the road/level
graph, the boat crossing and its collision handling, the broken bridge, the
weapons van, the "GAME OVER" text rendering, and more — each citing the
specific ROM addresses and (where used) the snapshot evidence behind the
finding. `claude/Spy_Hunter_Analysis.md` has the original high-level pass
(memory map, display engine, sound engine, init chain); the rest were added
incrementally as specific questions got resolved.
