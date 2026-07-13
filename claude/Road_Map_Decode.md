# Spy Hunter - Road / Level Map Decode

The scrolling level is a **linked graph of road segments** in ROM, walked one segment at
a time by the bottom-of-frame IRQ (`IRQ_BOTTOM_SCROLL`, specifically the segment-advance step
now labelled `ADVANCE_ROAD_SEGMENT` at `$853F`). This doc decodes
that structure. All snapshot values below use the corrected RAM extraction (see note at end).

## The engine (how a segment advances)

Each frame the road scrolls up. When the current segment's rows are exhausted
(`ROW_REPEAT`->0, `SEG_REPEAT`->0, then `ROAD_SEG_LEN`->0), the code advances:

```
lda ROAD_SEG_IDX      ; current segment ($42)
asl a : tay
lda SCENE_IDX : cmp #$13 : bcc + : iny   ; SCENE_IDX >= $13 -> take BRANCH (odd) entry
+ lda ROAD_SEG_TBL,y  ; next segment id
  sta ROAD_SEG_IDX
  tay
  lda ROAD_PTR_LO_TBL,y / ROAD_PTR_HI_TBL,y -> ROAD_PTR (this segment's row/feature list)
  lda ROAD_LEN_TBL,y                         -> ROAD_SEG_LEN (row count)
```

Then per row: `lda (ROAD_PTR),y -> ROAD_FEATURE ($44)`, and the feature indexes the
row-graphics tables `OBJ_ADDR_LO/HI` (`$AD63/$AD7D`), `OBJ_ROWREP_TBL` (`$AD97`),
`OBJ_SEGREP_TBL` (`$ADB1`), plus the palette via `ROAD_COLIDX/BORDER/MC1/MC2`.

**Fork mechanism:** `ROAD_SEG_TBL` stores **two** next-segment ids per entry
(`[2*idx]` = main, `[2*idx+1]` = branch). The branch is taken when `SCENE_IDX >= $13`.
Snapshots confirm the mapping to the physical fork the player takes:

* left fork  (score 1200): `SCENE_IDX = $0C` (< $13) -> **main / even** next-segment
* right fork (score 1950): `SCENE_IDX = $1B` (>= $13) -> **branch / odd** next-segment

So steering LEFT keeps the main path, steering RIGHT takes the branch path.

## Table addresses (ROM)

| Table | Addr | Purpose |
|---|---|---|
| `ROAD_SEG_TBL` | `$AC17` | 32 x (main, branch) next-segment ids |
| `ROAD_PTR_LO/HI_TBL` | `$AC57` / `$AC76` | per-segment -> row/feature-list pointer |
| `ROAD_LEN_TBL` | `$AC95` | per-segment row count |
| `ROAD_COLIDX/BORDER/MC1/MC2` | `$ACB4`/`$ACD3`/`$ACDC`/`$ACE5` | per-segment palette |
| feature-list bytes | `$ACEE-$AD62` | the `(ROAD_PTR),y` feature streams |
| `OBJ_ADDR_LO/HI`,`OBJ_ROWREP`,`OBJ_SEGREP` | `$AD63...$ADB1` | feature -> row graphics + repeats |

Start sentinel: `RESET_ROAD_INDEX` sets `ROAD_SEG_IDX = $1F` (valid segment ids are
`$00-$1E`; `$1F` just bootstraps into segment `$01`).

## Decoded segment graph

```
seg  main branch  fork   segPtr  rows
$01  $02   $03    FORK   $ACEF    3
$02  $08   $05    FORK   $ACF2   15
$03  $06   $04    FORK   $AD01   16
$04  $07   $07           $AD11    5
$05  $07   $07           $AD16    5
$06  $07   $07           $AD1B    2
$07  $10   $10           $AD1D    3
$08  $09   $0E    FORK   $AD20    9
$09  $0A   $0A           $AD29    2
$0A  $0B   $0B           $AD2B    1
$0B  $0C   $0C           $AD2C    3
$0C  $0D   $0D           $AD2F    1
$0D  $0F   $0F           $AD30    6
$0E  $0F   $0F           $AD36    3
$0F  $11   $11           $AD39    3
$10  $12   $0B    FORK   $AD3C    1
$11  $12   $0B    FORK   $AD3D    3
$12  $13   $13           $AD40    2
$13  $12   $14    FORK   $AD42    2
$14  $15   $17    FORK   $AD44   16
$15  $16   $16           $AD54    1
$16  $1A   $1A           $AD55    1
$17  $18   $18           $AD56    2
$18  $19   $19           $AD58    1
$19  $1A   $1A           $AD59    1
$1A  $1B   $1B           $AD5A    5
$1B  $1C   $1C           $AD5F    1
$1C  $01   $01           $AD60    2
$1D  $01   $1E    FORK   $AD62    1
$1E  $01   $01           $AD62    1
($1F start -> $01 main / $1D branch)
```

Main-path walk from start: `$1F->$01->$02->$08->$09->$0A->$0B->$0C->$0D->$0F->$11->$12->$13->$12...`
- segment `$12<->$13` is the **repeating road loop** between scripted events; `$1C->$01` and
`$1D/$1E->$01` close the level back to the top. The **10 fork points** are segments
`$01, $02, $03, $08, $10, $11, $13, $14, $1D`, plus the start `$1F`. The first fork the
player meets is at segment `$01` (branch to `$02` vs `$03`), matching the level-1 fork in
the snapshots (where `ROAD_SEG_IDX` = `$01` then `$02`).

## Snapshot-verified live values (corrected extraction)

| Snapshot | SCORE $E0-$E2 | TIMER $4D01/2 | ROAD_SEG_IDX $42 | SCENE_IDX $4A | fork |
|---|---|---|---|---|---|
| start  | 125  | 970 | $01 | $15 | - |
| fork L | 1200 | 888 | $02 | $0C (main path)   | left  |
| fork R | 1950 | 746 | $02 | $1B (branch path) | right |

WEAPON `$4D1E` = `$01` (machine guns) in all three. `ROAD_FEATURE $44` per-row codes
observed: `$11`, `$0C`, `$12` (indices into the row-graphics tables, vary per row).

## Extraction offset note (important)

The C64MEM snapshot module stores **4** leading bytes (`pport.data`, `pport.dir`, `exrom`,
`game`) before the 65536-byte RAM image. An earlier version of `tools/vsf_extract.py`
skipped only 2, shifting every address up by 2 and producing bogus "corrected" score/timer
addresses. The fix (`ram = payload+4`) is verified by the invariant
`SPRITE_PTRS ($4D2B) == SPRPTR_7800 ($7BF8)` (the game copies these each frame). With the
fix, all live values match the `spyhunter.asm` labels exactly - the disassembly's
`SCORE=$E0-$E2`, `HISCORE=$02-$04`, `GAME_TIME=$4D01/$4D02`, `WEAPON_STATE=$4D1E` were all
correct.

## ROAD_FEATURE code table (resolved)

`ROAD_FEATURE` (`$44`) indexes `OBJ_ADDR_LO/HI` (`$AD63`/`$AD7D`) and `OBJ_ROWREP_TBL`/
`OBJ_SEGREP_TBL` (`$AD97`/`$ADB1`) directly (`tay` right after the feature byte is loaded,
`READ_ROAD_ROW`, `disassembly/spyhunter.asm`) to pick the row's `SCROLL_SRC` graphics pointer. Reading
those tables straight from the assembled ROM gives a clean **16-entry table for codes `$00-$0F`**
— pointers into a `$2980-$4CFF` RAM graphics bank, ending exactly at the documented `$4D00`
game-state-variable boundary:

| feature | SCROLL_SRC | ROW_REPEAT | SEG_REPEAT | meaning |
|---|---|---|---|---|
| `$00` | `$2980` | `$05` | `$14` | plain road (opening) |
| `$01` | `$2A20` | `$05` | `$0F` | **bridge** (`claude/Water_Bridge_Notes.md`) |
| `$02` | `$2AC0` | `$05` | `$0A` | **boat / water crossing** (`claude/Boat_River_Notes.md`) |
| `$03` | `$2B60` | `$03` | `$04` | water-crossing variant (between two `$02` rows in segment `$11`) |
| `$04`-`$0E` | `$2BC0`-`$4780` | varies | `$01` | plain road variants |
| `$0F` | `$4A40` | `$16` | `$01` | **broken-bridge skip / return to road** (`claude/Broken_Bridge_Notes.md`) |

Feature codes `$10` and above fall **outside** this table's clean address progression (they land
in a second region, `$C000`-`$D000+`, not the smooth `$2980-$4CFF` run) and several of them are
separately checked by explicit `CMP #imm` branches elsewhere — all four confirmed:

| feature | checked at | effect |
|---|---|---|
| `$11` | `UPDATE_SCENE_SELECT`, `disassembly/spyhunter.asm` | scene/difficulty select |
| `$13` | `IRQ_MAIN` bottom-half (`CONSUME_ARMED_ROW`/`STORE_ARMED_ROW`/`PAINT_AND_ARM_MUX`), `disassembly/spyhunter.asm` | **water-entry**: on the last row of its row-repeat cycle, re-arms all four `SPRMUX_CNT*` sprite-multiplex counters for 25 rows starting at row `$04`, plus a matching 4-cell colour-RAM block; river-entrance transition (`spyhunter.asm` header) |
| `$14` | `SPAWN_CHECK_ENTRY`/`RANDOM_SPAWN_ROLL` (`UPDATE_HAZARDS`), `disassembly/spyhunter.asm` | **random object spawn**: ~2.3% chance per pass through the repeating water loop (segments `$12`/`$13`) to blit one of two small tile shapes (`$A598`/`$A5BB`) via the shared `DRAW_OBJECT_TILES` blit parameters — confirmed by `water-enemyboat-score14505.vsf`; see `claude/Boat_River_Notes.md` |
| `$15` | same `IRQ_MAIN` code as `$13` | **water-exit**: mirrors `$13`, re-arms the same sprite-mux counters for 25 rows starting at row `$14` instead — confirmed by `exit-water.vsf`; see `claude/Boat_River_Notes.md` |

All four `$11/$13/$14/$15` "scripted trigger" feature codes are now traced. `$10` itself (seen
live in segment `$08`, snapshot `level1-score4550-timer559`, the road just before the
river/boat/bridge arc begins) isn't directly `CMP`'d anywhere found so far — still open.

## Full segment row-by-row table (ROM bytes, code's actual reverse play order)

Extracted directly from the assembled ROM (`ROAD_PTR_LO/HI_TBL` + `ROAD_LEN_TBL`, walked the same
`dey`-first order the game itself uses — `READ_ROAD_ROW`, `disassembly/spyhunter.asm`). This resolves the
"decode the per-segment feature-list bytes" open item in full, not just the snapshotted segments:

```
seg $00: main=$1D branch=$1D  11
seg $01: main=$02 branch=$03  11 09 12
seg $02: main=$08 branch=$05  0C 10 08 09 12 0A 0B 10 05 06 04 07 08 09 12
seg $03: main=$06 branch=$04  0D 10 05 06 04 07 08 11 0B 05 06 04 07 08 09 12
seg $04: main=$07 branch=$07  0D 05 06 04 07
seg $05: main=$07 branch=$07  0D 05 06 04 07
seg $06: main=$07 branch=$07  0C 10
seg $07: main=$10 branch=$10  08 11 13
seg $08: main=$09 branch=$0E  0C 10 08 09 12 0A 11 09 12
seg $09: main=$0A branch=$0A  0C 04
seg $0A: main=$0B branch=$0B  02
seg $0B: main=$0C branch=$0C  0F 05 06
seg $0C: main=$0D branch=$0D  01                          (bridge)
seg $0D: main=$0F branch=$0F  05 06 05 06 04 07
seg $0E: main=$0F branch=$0F  0D 05 06
seg $0F: main=$11 branch=$11  08 11 13                    (river-entrance, ends on $13)
seg $10: main=$12 branch=$0B  02                           (boat)
seg $11: main=$12 branch=$0B  02 03 02                     (boat)
seg $12: main=$13 branch=$13  0E 14                        (repeating loop)
seg $13: main=$12 branch=$14  14 15                        (repeating loop, FORK)
seg $14: main=$15 branch=$17  0F 10 08 11 0B 05 06 05 06 04 07 04 07 08 09 12
seg $15: main=$16 branch=$16  0C
seg $16: main=$1A branch=$1A  01
seg $17: main=$18 branch=$18  0D 04
seg $18: main=$19 branch=$19  02
seg $19: main=$1A branch=$1A  07
seg $1A: main=$1B branch=$1B  10 08 11 09 12
seg $1B: main=$1C branch=$1C  00
seg $1C: main=$01 branch=$01  12 0A
seg $1D: main=$01 branch=$1E  19
seg $1E: main=$01 branch=$01  19
```

This confirms the full scripted chain end-to-end: `... $08/$09/$0A/$0B/$0C(bridge)/$0D/$0F
(river-entrance, feature $13) -> $11 (boat, feature $02, random enemy-boat spawns via feature
$14 further round the $12/$13 loop) -> [branch] -> $0B (feature $0F, broken-bridge return) ->
plain road ...`

Segment `$13` (the repeating water-loop's fork point) has **two** exits, both confirmed by
snapshots: `main` loops back to `$12` for another lap; `branch` exits to segment `$14`
(`spyhunter-exit-water-dock-building-and-truck.vsf`, seg `$14`, feature `$0F`, prev `$15`) — a
second "return to road" on-ramp, opening (like segment `$0B`) on feature `$0F`. See
`claude/Dock_Exit_Notes.md`.

## Next steps

* Feature `$10`'s exact meaning (segment `$08`) — no direct `CMP` site found yet.
* Feature `$03` (the row between the two boat rows in segment `$11`) — likely a water
  current/wake variant, not yet visually confirmed.
* Which `OBJ_TYPE` byte value is the Road Lord (the official manual explains WHY an enemy near
  the bridge was unshootable — the Road Lord is bulletproof by design, see
  `claude/Enemy_Agents_Manual_Reference.md` — but not yet WHICH byte value it is) — see
  `claude/Enemy_Invincibility_Notes.md`.
