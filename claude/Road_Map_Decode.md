# Spy Hunter - Road / Level Map Decode

The scrolling level is a **linked graph of road segments** in ROM, walked one segment at
a time by the bottom-of-frame IRQ (`IRQ_BOTTOM_SCROLL`, label `L853F`). This doc decodes
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
`disassembly/spyhunter.asm:1250-1267`) to pick the row's `SCROLL_SRC` graphics pointer. Reading
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
in a second region, `$C000`-`$D000+`, not the smooth `$2980-$4CFF` run) and several of them
(`$11`, `$13`, `$14`, `$15`) are separately checked by explicit `CMP #imm` branches elsewhere —
`UPDATE_SCENE_SELECT` (`disassembly/spyhunter.asm:2361-2374`) checks `$11`, panel/colour-cycle
code near `L8474` checks `$13`/`$15`, effects code near `LA60E` checks `$14`. So `$10`+ double as
scene-transition triggers, not just tile indices; `$13` = the river-entrance transition
(documented in the `spyhunter.asm` header). `$10` itself (seen live in segment `$08`, snapshot
`level1-score4550-timer559`, the road just before the river/boat/bridge arc begins) isn't
directly `CMP`'d anywhere found so far — recorded as still open below.

Per-segment feature streams (ROM bytes, read in the code's actual **reverse** play order) for the
segments pinned by snapshots this session:

```
seg $0C (bridge):        $01                        (single row)
seg $0B (return-to-road): $0F -> $05 -> $06          (broken-bridge skip, then plain road)
seg $11 (boat):           $02 -> $03 -> $02           (boat, unidentified $03 row, boat)
seg $08 (pre-river road): $0C -> $10 -> $08 -> $09 -> $12 -> $0A -> $11 -> $09 -> $12
```

confirming the scripted chain: `... segment $08/$09/$0A/$0B/$0C/$0D/$0F (river-entrance,
feature $13) -> segment $11 (boat, feature $02) -> [branch] -> segment $0B (feature $0F,
broken-bridge return) -> plain road ...`

## Next steps

* Feature `$10`'s exact meaning (segment `$08`) — no direct `CMP` site found yet.
* Feature `$03` (the row between the two boat rows in segment `$11`) — likely a water
  current/wake variant, not yet visually confirmed.
* What makes an enemy briefly unshootable near the bridge — see
  `claude/Enemy_Invincibility_Notes.md` (inconclusive from a single snapshot; needs a paired
  before/after capture).
* Full row-by-row expansion of the remaining un-snapshotted segments (`$02`-`$07`, `$0D`-`$0E`,
  `$12`-`$1E`).
