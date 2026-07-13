# Spy Hunter (C64) — Reverse-Engineering Analysis

**Cartridge:** `Spy Hunter 1983 U.S. Gold.crt` — actually a **raw 16 KB cartridge ROM** (not a `.crt` container).
**Build stamp in the header:** `09/14/84, VER-1.1, (C)1983 BALLY`
**ROM footprint:** `$8000–$BFFF` (16384 bytes), MD5 `ee7fe8c9a5179aa8b23d8f1e49cf113c`.

This document explains what the code does, how the game is structured, and how the accompanying
disk-loadable `spyhunter.prg` was produced and validated.

---

## 1. Cartridge format and autostart

The first bytes are the standard C64 autostart signature, not a `.crt` header:

```
8000: 27 80        cold-start vector  -> $8027
8002: 27 80        warm-start vector  -> $8027
8004: C3 C2 CD 38 30   "CBM80"  (autostart magic)
8009: "9/14/84,VER-1.1,(C)1983 BALLY"   (ASCII build stamp)
8027: 78           SEI   <-- code entry
```

On real hardware the KERNAL sees `CBM80` at `$8004` during reset and jumps through the
`$8000` cold-start vector to `$8027`. The cartridge is a **16 KB game config** (ROML `$8000–$9FFF`
+ ROMH `$A000–$BFFF`).

## 2. Reset / cold-start ($8027)

```
SEI ; CLD
LDA #$7F : STA $DD0D / STA $DC0D   ; disable all CIA1/CIA2 interrupts
LDA $DD0D / LDA $DC0D              ; acknowledge
LDX #$FF : TXS                     ; reset stack
JSR sub_80E5                       ; system + VIC + charset + memory init
JSR sub_8261 ... (a 13-call init chain) ...
```

After init it drops into a polling **main loop** (`$8061+`) that reads the joystick
(`$DC00`/`$DC01`) and game-state variables in RAM to decide between attract/demo mode and
starting a game.

## 3. Memory configuration — the key to running it from disk

The game touches the `$01` processor port exactly **three** times:

| Site   | Value | Meaning on the cartridge | Meaning on a plain C64 (no cart) |
|--------|-------|--------------------------|----------------------------------|
| `$80EF`| `$05` | LORAM=1,HIRAM=0,CHAREN=1 | **RAM @ $A000, I/O @ $D000, RAM @ $E000** ✅ |
| `$811F`| `$03` | cart ROMH + char ROM     | **BASIC ROM @ $A000** ❌ (would hide game code) |
| `$817D`| `$05` | back to normal run config | back to normal ✅ |

The crucial discovery: on a C64 **with no cartridge**, `$01 = $05` (config 5) already gives
RAM at `$A000` and `$E000` with I/O at `$D000` — exactly the map the game runs in. So the game's
normal running config is *native* on a plain machine. The game is also fully **self-contained**:
it makes **no KERNAL or BASIC calls at all**, and installs its own CPU vectors at `$FFFA–$FFFF`
(NMI/RESET → `$8027`, IRQ → `$8402`) because it runs with `$E000–$FFFF` as RAM.

The only incompatibility is the brief `$03` window: it copies the C64 **character ROM** out of
`$D000` while calling helper routines at `$A122/$A146/$A130…`. Under config 3 on a real C64 those
`$A0xx` addresses are BASIC ROM, so the calls would crash. Config **`$02`** fixes it: RAM stays at
`$A000` (game code intact) *and* the character ROM is still visible at `$D000`. So the loader
applies a single-byte patch `$811E: $03 → $02`.

### Memory map (runtime)

| Range | Contents |
|-------|----------|
| `$0000–$00FF` | Zero page: pointers (`$12–$17`), IRQ/raster state (`$34–$41`), sound state (`$52–$5E`) |
| `$0100–$01FF` | CPU stack |
| `$2800–$2FFF` | Speed-critical routine copied into RAM (called from the IRQ as `JSR $2802`) |
| `$4000–$7FFF` | **VIC bank 1** graphics (selected via `$DD00=$02`) |
| `$4D00–…`     | Game-state variables (score, lives, enemy/object tables) |
| `$6400 / $7800 / $7C00` | Screen buffers (title / play / high-score) |
| `$6800 / $7000` | Two character sets (playfield graphics + text) |
| `$8000–$BFFF` | Game code + data (the cartridge image) |
| `$BD00±`      | Music / sound-effect data tables |
| `$D800–$DBFF` | Colour RAM |
| `$E000–$FFFF` | RAM; CPU vectors live at `$FFFA–$FFFF` |

## 4. Display engine

Registers observed at runtime: `$DD00=$02` (VIC bank 1 = `$4000–$7FFF`), `$D016=$18`
(**multicolour character mode**, 40 cols), `$D011=$1B` (25 rows, display on, text mode — *not*
bitmap), `$D018` cycling through `$9A/$EC/$FC`. Decoding `$D018` within bank 1:

* `$9A` → screen `$6400`, charset `$6800`
* `$EC` → screen `$7800`, charset `$7000`
* `$FC` → screen `$7C00`, charset `$7000`

So the vertically-scrolling road is built from **custom multicolour characters**, with several
screen buffers swapped for different game states and smooth updates. Shared multicolour colours
are `$D022=$01` (white) and `$D023=$08` (orange).

### Raster-interrupt chain (the split screen + sprite multiplexing)

The IRQ handler at `$8402` is a **chained raster interrupt**:

1. Saves registers, does a short stabilisation delay.
2. Writes `$D011`/`$D018` (from `$3D`/`$3F`) and border/background colours (from `$36–$38`) —
   changing the screen buffer, charset and palette **at the split line**.
3. Programs the next raster compare to line `$2F` and re-points the IRQ vector to `$83C3`
   (`STA $FFFE/$FFFF`), then `CLI`.
4. Optionally copies a 32-byte block (`($28)→($2A)`) and updates colour RAM, then `JSR $2802`.

The captured raster-compare targets — a dense run of lines `$2F…$44` plus `$06`, `$EA`, `$F1` —
are the signature of a **status-panel/playfield split at the top** and **sprite multiplexing**
(sprites are repositioned at successive raster lines to display more than the VIC's 8 hardware
sprites — necessary for the many enemy vehicles). The bottom IRQ at line `$F1` handles per-frame
game logic and music; the top chain (`$83C3` at line `$2F`) paints the score/status panel.

## 5. Sound engine (SID) — the "Peter Gunn" theme

* `sub_AA63` — SID init: clears all 25 SID registers `$D400–$D418`, sets master volume `$0F`.
* `sub_AAA8` — gate-off / silence all three voices (`$D404/$D40B/$D412 = 0`).
* `sub_AA76 / sub_AAC1` — note/effect trigger: read note+control data from tables at `$BD17/$BD18`
  (cart data around `$BD00`), and store per-voice state into zero page `$52–$5E`.

All three SID voices are driven (frequency, pulse width, ADSR, filter), consistent with Spy
Hunter's continuous music (Henry Mancini's *Peter Gunn* theme) plus engine/weapon sound effects.

## 6. Core utility primitives

* `sub_A213` — **page copy (memcpy)**: copies X×256 bytes from `($12/$13)` to `($14/$15)`.
* `sub_A22C / sub_A232` — **page fill (memset)**: fills X×256 bytes at `($12/$13)` with A
  (used to clear `$4D00–$7FFF` and colour RAM at startup).
* `sub_A116 / sub_A122 / sub_A130 / sub_A13A / sub_A146` — small pointer/byte helpers used by the
  character-set builder in the `$8118–$817D` init block.

## 7. Init chain (called from `$8027`)

`sub_80E5` (system/VIC/vectors/charset/clear) → `sub_8261` → `sub_829D` → `sub_831E` →
`sub_9356` → `sub_A323` → `sub_8A82` → `sub_9DBA` → `sub_A477` → `sub_A967` → `sub_A841` →
`sub_AA29` (sound) → `sub_80E2` (`JMP ($2895)` — indirect dispatch into the game state machine).

The game is a **state machine**: a game-mode variable (checked at `$4D0D`, `$4D13`, etc.) selects
attract/demo, gameplay, and high-score states, dispatched through pointer tables (e.g.
`JMP ($2895)`), which is why parts of the ROM are only reached once the corresponding state runs.

## 8. Coverage of this analysis

Reachable code was mapped two ways and merged: a static recursive-descent trace, plus a custom
6502 emulator that actually executed the loader + game through 3M+ instructions across several
input scenarios (following the jump tables and IRQ handlers that static tracing can't).

* **~5.2 KB (32%)** identified as executable code across **68 subroutines**; the remaining ~68%
  is data — character/sprite graphics, screen/level tables and music data, as expected for an
  arcade port.
* The uncovered code paths are additional in-game states (crash/repair sequences, the weapons
  van, boat section, scoring screens) that require reaching those game states interactively.

See `spyhunter.asm` for the full annotated listing.

## 9. The disk loader (`spyhunter.prg`)

A single self-contained PRG (loads at `$0801`):

```
10 SYS2061          ; BASIC bootstrap
$080D: relocator    ; SEI; $01=$05; copy 16 KB payload up to $8000-$BFFF; JMP $8027
$0900: payload      ; the 16 KB cart image, with the $811E $03->$02 patch
```

The stub selects config `$05` **before** jumping, because the very first init routine calls
`$A213` *before* it sets `$01` itself — so `$A000` must already be RAM at entry.

### Validation

Executed under the custom 6502 + C64 emulator (models `$01` banking, raster, CIA, SID). Across
all input scenarios: **no illegal opcodes, no BRK, and zero execution in banked-out BASIC/KERNAL
ROM.** The program reaches config `$05`, runs the patched charset copy as RAM (not BASIC ROM),
sets up the full VIC display and all three SID voices, and runs its IRQ-driven main loop cleanly.

> Note: pixel-accurate confirmation needs a full emulator with the copyrighted C64 KERNAL/BASIC/
> CHARGEN ROMs (stripped from the packaged VICE build here). The logic/banking are proven; drop
> the PRG onto a `.d64` and run it in VICE/on real hardware to confirm graphics and audio.
