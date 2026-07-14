# Spy Hunter - per-object DRAW handlers ($9368-$99DE)

Full conversion of the largest remaining raw-data block in `spyhunter.asm`
(1655 bytes, previously flagged "left unexpanded for a future focused
session" right after `MUSIC_START_THEME`) to labelled, real 6502
instructions. This was task #26 in the session task list.

## The mechanism: two-stage draw dispatch

`OBJINIT_PARAM_TBL` (Stage 5, `$8B3F`) holds a 4-byte move+draw vector pair
per `OBJ_TYPE` (`$00`-`$1B`, 28 entries). The *draw* half of each entry does
**not** point at code directly - it points at a small per-animation-frame
address table, itself indexed by `OBJ_ANIM*2` through the `ZVEC_DRAW`
indirection already documented at `PROCESS_OBJECTS`:

```
lda OBJ_ANIM,x
asl a
tay
lda (ZVEC_DRAW),y    ; ZVEC_DRAW points at one of the DRAW_TBL_T* tables below
pha
iny
lda (ZVEC_DRAW),y
sta ZVEC_DRAW_HI
pla
sta ZVEC_DRAW
...
jsr OBJ_VEC2_DISPATCH   ; jmp (ZVEC_DRAW) -> the real per-frame draw routine
```

Reading the raw `OBJINIT_PARAM_TBL` bytes directly out of the ROM (rather
than trusting a shallow heuristic scan) gave the authoritative TYPE-to-table
map:

| OBJ_TYPE | Draw table | Frames |
|---|---|---|
| `$06` | `DRAW_TBL_T06` | 3 |
| `$09` | `DRAW_TBL_T09` | 3 |
| `$0A` | `DRAW_TBL_T0A` | 3 |
| `$0B` | `DRAW_TBL_T0B` | 4 |
| `$0C`/`$0D` | `DRAW_TBL_T0C` | 1 (shared) |
| `$0E`/`$0F`/`$10` | `DRAW_TBL_T0E` | 3 (shared) |
| `$11` | `DRAW_TBL_T11` | 2 |
| `$12`/`$13` | `DRAW_TBL_T12` | 2 (shared) - **confirmed boat/water enemy pair** |
| `$14`/`$17` | `DRAW_TBL_T14` | 3 (shared) |
| `$15` | `DRAW_TBL_T15` | 6 |
| `$16` | `DRAW_TBL_T16` | 4 |
| `$18` | `DRAW_TBL_T18` | 3 |
| `$19` | `DRAW_TBL_T19` | 2 |
| `$1A` | `DRAW_TBL_T1A` | 2 |
| `$1B` | `DRAW_TBL_T1B` | 2 (nested inside `DRAW_TBL_T0B`'s bytes) - **confirmed live-bullet type** |

`$12`/`$13` and `$1B` cross-check exactly against prior findings
(`claude/Collision_Detection_Notes.md`, `claude/Controls_And_Difficulty_Notes.md`):
`$13` was already confirmed as the boat/water enemy type, and `$1B` as the
"live bullet" `OBJ_TYPE` a successful machine-gun shot commits to. Both draw
tables turned out to live in this exact block.

## How the conversion was actually done

Given the size (1655 bytes, ~40 frame routines across 15 tables), hand
transcription was not attempted directly. Instead:

1. Read `OBJINIT_PARAM_TBL`'s raw bytes to get the authoritative TYPE->table
   map above (rather than trusting an earlier shallow "does this decode
   cleanly" scan, which under-counted several tables' entries).
2. Wrote a recursive-descent 6502 walker (Python) seeded from all 15 tables'
   entries plus `$9368` itself, `$9965` (found to be called from Stage 5/6
   code elsewhere in the ROM via `JSR $9965`), and three targets (`$99CB`,
   `$99D8`, `$99DB`) branched to from a small dispatch fragment at `$99E3`
   (immediately after this block, already-converted collision-detection
   code).
3. **Critical fix during this pass**: an initial "stop the walk on an
   illegal opcode" heuristic silently mis-decoded through at least one
   table (`$9624`'s 3-entry table happened to decode as *valid-looking but
   wrong* instructions all the way through, desyncing everything after it).
   Fixed by explicitly carving out all 15 address tables (plus two small
   byte-indexed tables at `$939A` and `$95AD`, read via `LDA $939A,y` /
   `LDA $95AD,y` from two of the draw routines) as hard-excluded regions
   *before* walking, rather than discovering them reactively.
4. Verified full byte coverage: all 1655 bytes accounted for with zero
   gaps and zero ambiguity once the data regions were excluded (1557 code
   bytes + 98 data bytes).
5. Found and fixed 3 genuine overlapping-instruction sites via a systematic
   byte-range-collision check (not just "does it decode cleanly") - the
   same "BIT-absolute as a 2-byte skip" idiom already established elsewhere
   in this file (`SPEED_STEP_DOWN/UP`, `MOVE_BOAT_SEQ_LO/ARM`):
   ```
       lda #$02
       .byte $2C        ; falls through with A=$02 ...
   L950D:
       .byte $A9,$FE    ; ... or entered via a BMI directly, re-reading these
                        ;   same 2 bytes as "lda #$FE" instead
       sta $B1
   ```
   at `$950C`/`$975C`/`$99D2`.
6. Generated ca65 source programmatically (address-ordered emission,
   resolving operands against the existing equates table), assembled a
   scratch copy, and confirmed byte-for-byte identical output
   (`cmp`/`md5`) against `spyhunter.bin` *before* touching the real file.

## New equates

Nine new `STATE_4Dxx`/`STATE_4D0x` zero-page-adjacent placeholders
(`STATE_4D0A`, `STATE_4D0E`, `STATE_4D34`, `STATE_4D39`, `STATE_4D5C`,
`STATE_4D61`, `STATE_4D81`, `STATE_4DAE`, `STATE_4DC9`) - all unconfirmed
purpose, following the file's existing "flag/state, not yet interpreted"
convention.

## What's still open

* **`DRAW_STATE_4D89_PREP`** (`$9368`, the block's very first bytes) is not
  reached via `OBJINIT_PARAM_TBL`/`ZVEC_DRAW` at all - no `JSR`/`JMP $9368`
  exists anywhere in the ROM. It reads `SPEED_SUM`/`STEER_ACCUM`
  (`SPEEDCODE_IMAGE`'s own zero-page vars) and increments `STATE_4D89` (the
  boat's "already crashed" flag) before falling through into
  `DRAW_T0A_F0`. Candidate: a panel/HUD speed or boat-wake indicator called
  through some vector this session didn't trace - not confirmed.
* Individual TYPE semantics (which enemy/effect each of the ~14
  non-boat/non-bullet tables draws) are **not** interpreted here - this was
  a mechanical data-to-code conversion pass, not a semantic one. Now that
  the code is readable, task #33 ("pin down remaining enemy OBJ_TYPE
  values" - Road Lord, Switch Blade, The Enforcer) has real disassembly to
  work from instead of raw bytes.
* Most internal branch targets within each per-frame draw routine kept
  positional `L####` labels rather than descriptive names, consistent with
  the file's existing fallback convention for not-yet-semantically-confirmed
  code - a good target for a future descriptive-naming pass once specific
  TYPEs are identified.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` - the whole conversion is data->code only,
no assembled bytes changed.

## Part 2: the companion block ($8E74-$9355, after `INIT_OBJECT_SLOT`)

Same conversion, same day, immediately following on from the block above
(this was task #25). 1250 bytes, covering the remaining `OBJINIT_PARAM_TBL`
draw entries not in the first block: `OBJ_TYPE` `$00`-`$03` (the hero -
shares one table, `DRAW_TBL_T00`), `$04`, `$05`, `$07`, `$08`.

### The COMMIT_TYPE tables live here

The first 196 bytes of this block ($8E74-$8F37) are **not** draw code at
all - they're the 7 per-`OBJ_TYPE` initialisation tables (28 bytes each,
one byte per `OBJ_TYPE` `$00`-`$1B`) that `COMMIT_TYPE` (in the already-
converted hero/object move-handler block) reads when a slot's type is first
set:

| Table | Feeds | 
|---|---|
| `TYPE_TBL_VEL` (`$8F1C`) | `OBJ_TBL43`/`OBJ_TBL3B`/`OBJ_TBL4B`/`OBJ_TBL53` (nibble-packed X/Y velocity) |
| `TYPE_TBL_93` (`$8EAC`) | `OBJ_TBL93` |
| `TYPE_TBL_SPRPTR` (`$8EE4`) | `SPRITE_PTRS`/`OBJ_TBL23` (initial sprite shape) |
| `TYPE_TBL_ANIM` (`$8F00`) | `OBJ_ANIM` (initial animation frame) |
| `TYPE_TBL_HITGRP` (`$8E90`) | `HIT_GROUP0`/`HIT_GROUP2` (per-bit, via `BIT_MASK`) |
| `TYPE_TBL_SPRATTR` (`$8EC8`) | `VIC_SPR_COLOR`/`VIC_SPR_MCM`/`VIC_SPR_XEXP`/`VIC_SPR_YEXP` |
| `TYPE_TBL_A3` (`$8E74`) | `OBJ_TBLA3` - read from a short tail *after* `COMMIT_TYPE` itself, not `COMMIT_TYPE` proper |

`COMMIT_TYPE`'s own code (already converted in a prior session) previously
referenced these 6-of-7 tables by raw hex address; updated in this pass to
use the names above (a pure label/comment change, re-verified byte-identical
same as everything else).

### The hero's draw table has by far the most frames

`DRAW_TBL_T00` (`$90AA`, shared by `OBJ_TYPE` `$00`-`$03`) has **10** frame
entries - more than double any table in the first block. Consistent with
the hero/player car being the most animated object (turning, crashing,
weapon-firing poses, etc.) Two more small byte-indexed tables
(`DRAW_T07_TAIL_TBL` at `$8F40`, `DRAW_T00_F3_TBL` at `$9093`) are read via
`LDA tbl,y` / `ADC tbl,x` from inside their neighbouring routines - the same
"small inline lookup table, not address pairs" idiom as `SPEED_ACCUM`-style
tables in `SPEEDCODE_IMAGE` and the two byte tables in Part 1 above.

### New equates

`STATE_4D44`, `STATE_4D54`, `STATE_4D5C`, `STATE_4D61`, `STATE_4D64`,
`STATE_4D6C`, `STATE_4D74`, `STATE_4D7C` - all unconfirmed-purpose
placeholders, same convention as Part 1.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db`.

## Part 3: attract/road-reset helper ($A298-$A322, task #28)

Small (139-byte) standalone routine, not part of the `OBJINIT_PARAM_TBL`
dispatch system at all - called directly (`JSR`/`JMP`) from two sites inside
the hero/object move-handler block, previously left as raw hex (`$A29D`,
now `ATTRACT_HELPER`). Structure: a short countdown
(`OBJ_TBL5B,x`/`FLAG_FF`) that, once expired (`BLIT_ROWS` reaches 0), points
`STREAM_PTR` at a small 5-byte value table (`ATTRACT_HELPER_TBL`, consumed
indirectly elsewhere - same "point a zero-page pointer at a small table for
someone else to read" idiom seen throughout this file), computes a staged
screen row/column from `OBJ_TBLB3`/`OBJ_TBLBB`, and writes a fixed set of 9
`$5Axx` screen-row addresses (candidate: attract-mode text row pointers -
not confirmed). One more of the file's "BIT-absolute as a 2-byte skip"
overlap tricks.

## Part 4: effect spawn/param helper ($A7A1-$A840, task #29)

Small (160-byte) routine, `SEGMENT_FX_HELPER` (previously raw hex `$A7C1`,
called twice from `MOVE_BOAT_MAIN`'s hazard-check chain in the
collision-detection block). Looks up a `ROAD_FEATURE`/`PREV_FEATURE` code in
a 12-byte table (`SEGMENT_FX_FEATURE_TBL`) to get a column offset, then
points `STREAM_PTR` at one of two 10-byte parameter tables
(`SEGMENT_FX_TBL_A`/`_B`, selected by odd/even feature index) - the same
indirect-pointer idiom as Part 3. The block's last 6 bytes turned out to be
the *start* of `TALLY_CHAR_TBL`, an address already named as an equate
elsewhere in the file (from `TALLY_SCORE_EVENTS`) - no new label needed,
just confirms the boundary was exactly right.

## Combined result

All four blocks done (tasks #25/#26/#28/#29) - this file's "raw data that's
actually code" backlog, tracked since early in the project, is now fully
cleared. Verified by re-scanning `spyhunter.asm` for every "not yet
disassembled"/"left for a future session"/"stored as data" comment: the one
remaining hit is stale phrasing inside an already-converted `SPEED_STEP`
comment describing *past* state, not a live TODO (fixed in passing).

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` across all four conversions.
