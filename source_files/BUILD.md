# Building Spy Hunter (C64)

This project reassembles the original 16 KB Spy Hunter cartridge ROM from
`spyhunter.asm` and wraps it in a disk-loadable `.prg`.

## Prerequisites

- **cc65** (provides `ca65` and `ld65`) — https://cc65.github.io/
  - Debian/Ubuntu: `sudo apt-get install cc65`
  - macOS: `brew install cc65`
- **Python 3** (for the PRG builder)
- Optional: `md5sum` (to verify the ROM) and **VICE** (`x64sc`) to run it.

## Files

| File             | Purpose                                                     |
|------------------|-------------------------------------------------------------|
| `spyhunter.asm`  | The annotated, reassemblable source.                        |
| `spyhunter.cfg`  | ld65 linker config — lays the code out as a flat 16 KB image at `$8000`. |
| `build_prg.py`   | Wraps the ROM image in a self-relocating `.prg`.            |
| `Makefile`       | One-command build.                                          |

## Quick start (Makefile)

```sh
make          # -> spyhunter.bin (ROM) and spyhunter.prg
make verify   # check the ROM matches the original (MD5)
make clean
```

## Manual build (two steps + PRG)

### 1. Assemble and link the ROM image

```sh
ca65 -t c64 spyhunter.asm -o spyhunter.o
ld65 -C spyhunter.cfg spyhunter.o -o spyhunter.bin
```

`spyhunter.bin` is the raw 16 KB cartridge ROM (`$8000-$BFFF`).
It should be exactly 16384 bytes with MD5 `ee7fe8c9a5179aa8b23d8f1e49cf113c`
(identical to the original dump):

```sh
md5sum spyhunter.bin
```

### 2. Build the disk-loadable PRG

```sh
cp spyhunter.bin spyhunter.rom
python3 build_prg.py          # -> spyhunter.prg
```

## The linker config (`spyhunter.cfg`)

```
# ld65 config: raw 16K binary loaded at $8000
MEMORY {
    ROM: start = $8000, size = $4000, fill = yes, fillval = $00, file = %O;
}
SEGMENTS {
    CODE: load = ROM, type = ro, start = $8000;
}
```

- `MEMORY` declares one region, `ROM`, 16 KB (`$4000`) starting at `$8000`,
  zero-filled to the full size, written to the output file (`file = %O`).
- `SEGMENTS` maps the single `CODE` segment (declared in the `.asm` with
  `.segment "CODE"` / `.org $8000`) into that region as read-only.

The result is a headerless, absolutely-located binary — the cartridge image.

## What the PRG builder does

The original is a cartridge, so a plain disk load can't reproduce it directly.
`build_prg.py` produces a `.prg` that loads at `$0801` and contains:

1. A BASIC line: `10 SYS2061`.
2. A 42-byte machine-language relocator stub at `$080D`:
   - selects memory config `$05` (RAM at `$A000`/`$E000`, I/O at `$D000`),
   - copies the 16 KB payload up to `$8000-$BFFF`,
   - `JMP $8027` (the game's cold-start entry).
3. The 16 KB payload (the ROM), page-aligned at `$0900`.

It also applies one byte patch — `$811E: $03 -> $02` — so the character-ROM
copy done during init uses config 2 (RAM at `$A000` **and** char ROM visible at
`$D000`) instead of config 3, which on a real C64 would page in BASIC ROM over
the game's own `$A0xx` routines and crash. See `Spy_Hunter_Analysis.md` §3.

## Running it

```sh
x64sc spyhunter.prg          # VICE: loads and autostarts via the SYS line
```

Or write `spyhunter.prg` to a `.d64` and `LOAD"*",8,1 : RUN`.

> Note: the `spyhunter.bin` ROM image can also be run directly as a cartridge
> in an emulator that accepts a raw 16 KB `$8000` image (16K game config).
