# Spy Hunter - Boat / river crossing (ROAD_FEATURE $02)

From `spyhunter-become-boat.vsf` (score 13625, seg_idx `$11`, feature `$02`, prev `$13`),
`spyhunter-crash-into-water-score9850-timer143.vsf` (score 9850, seg_idx `$11`, feature `$02`,
prev `$13`), `spyhunter-water-enemyboat-score14505.vsf` (score 14505, seg_idx `$12`, feature
`$14`, prev `$0E`), and `spyhunter-exit-water.vsf` (score 16050, seg_idx `$13`, feature `$15`,
prev `$14`). All extracted with `tools/vsf_extract.py`.

## ROAD_FEATURE $02 = boat/water crossing

Both snapshots land in **segment `$11`** (`ROAD_PTR=$AD3D`, 3 rows) with `ROAD_FEATURE=$02` and
`PREV_FEATURE=$13` (the already-documented river-entrance transition feature). Reading segment
`$11`'s raw row bytes straight from the assembled ROM (`ROAD_PTR_LO/HI_TBL` + `ROAD_LEN_TBL` at
segment index `$11`) gives `02 03 02`. The per-row reader walks this **backwards**
(`ldy ROAD_SEG_LEN : dey : lda (ROAD_PTR),y`, `disassembly/spyhunter.asm:1250-1255`), so the
actual play order is **`$02` (boat) -> `$03` -> `$02` (boat)** — the boat state opens and closes
the segment, with one row of a different feature (`$03`) in between (likely a wake/current
variant of the water tile, not yet visually confirmed).

Segment `$11` is reached from the river-entrance segment `$0F` (`main=$11`, `disassembly/spyhunter.asm`
segment graph) whose own feature stream ends in `$13` — i.e. the scripted sequence is
`... -> $0F (feature $13, river-entrance) -> $11 (feature $02, boat) -> ...`, matching both
snapshots' `PREV_FEATURE=$13`.

## Graphics-table evidence

`ROAD_FEATURE` indexes `OBJ_ADDR_LO/HI` (`$AD63`/`$AD7D`) + `OBJ_ROWREP_TBL`/`OBJ_SEGREP_TBL`
(`$AD97`/`$ADB1`) directly (`tay` right after the feature is loaded — `disassembly/spyhunter.asm:1255-1267`).
Reading those tables from the assembled ROM at index `$02`:

```
feature $02 -> SCROLL_SRC = $2AC0, ROW_REPEAT = $05, SEG_REPEAT = $0A
```

`$2AC0` sits inside the same `$2980-$4CFF` RAM graphics bank used by every other "ordinary" road
feature (`$00-$0F`) — the table is a clean, regularly-structured list of pointers into this bank,
ending exactly where `$4D00` (the documented game-state variable region) begins. So the boat is
drawn through the **same generic per-row tile blitter** as plain road/bridge rows, just with its
own graphics block — consistent with `claude/Water_Bridge_Notes.md`'s finding that water/bridge
tiles are ordinary map tiles, not sprites or a separate rendering layer.

## The "boat mode" object flag ($02 in OBJ_TBL63/6B/73)

Across all three water snapshots on file (`become-boat`, `crash-into-water`,
`water-enemyboat-score14505`), every object slot that's visibly a boat has
`OBJ_TBL63 = OBJ_TBL6B = OBJ_TBL73 = $02` (all three of the parallel per-slot state arrays at
`$4D63`/`$4D6B`/`$4D73` set to the same value) — e.g. `become-boat` slot 2 (`TYPE=$14`) and slot 6
(`TYPE=$06`) both show `02 02 02`; `water-enemyboat-score14505` slot 2 (`TYPE=$13`) and slot 6
(`TYPE=$06`) do too. In every plain-road snapshot these three bytes are `$00` for ordinary enemy
slots. That's consistent with `$02` being a shared **locomotion/terrain-mode flag** (car vs. boat)
rather than something specific to any one object type — the same three-array triplet flags the
hero's own boat state too (`become-boat`/`crash-into-water` have it on slot 1's peers turning
boat-shaped, though the hero's own `HERO_STATE`/`OBJ_TYPE[1]` stays `$FF` in both, so the "am I a
boat" state for the player must live elsewhere - possibly `SCENE_ID` transitions handle the
player case specifically while `OBJ_TBL63/6B/73` handles NPCs).

## Enemy boat spawn: ROAD_FEATURE $14 (segment $12/$13 repeating loop)

`spyhunter-water-enemyboat-score14505.vsf` (score 14505, seg_idx `$12`, feature `$14`, prev
`$0E`) pins down one of the previously-unresolved "scripted trigger" feature codes. Segment `$12`'s
ROM row stream is `$0E -> $14` (2 rows, `ROAD_PTR=$AD40`); segment `$13`'s is `$14 -> $15`
(`ROAD_PTR=$AD42`, `main=$12`, `branch=$14`) — `$12` and `$13` are the documented **repeating
road loop** between scripted events, and `$14` appears in both, i.e. every lap of the loop passes
through a `$14` row.

`ROAD_FEATURE=$14` is directly checked in the disassembly at `LA60E`
(`disassembly/spyhunter.asm:3619-3663`):

```
lda ROAD_FEATURE
cmp #$14
beq LA62D          ; -> random spawn roll
...
LA62D:
    jsr RNG_NEXT
    cmp #$FA
    bcc LA62C       ; ~97.7% of the time: nothing (RNG_NEXT < $FA -> rts)
    jsr RNG_NEXT     ; ~2.3% chance: pick a spawn table + params
    pha
    cmp #$7F
    lda #$09 : ldx #$A5 : ldy #$BB
    bcc LA648
    lda #$07 : ldx #$A5 : ldy #$98
LA648:
    sta FX_COUNT : stx FX_SRC_HI : sty FX_SRC   ; FX_SRC/HI -> $A5BB or $A598
    ...                                          ; FX_LEN from further RNG
```

`FX_SRC`/`FX_SRC_HI` then feed `STREAM_PTR`, and the routine sets `BLIT_COL/BLIT_ROW/BLIT_WIDTH/
BLIT_ROWS/OBJ_COLOR` — the same blit-parameter set used by `DRAW_OBJECT_TILES` (the shared
van/smoke/hazard/text blitter, see the `spyhunter.asm` header). The two candidate source tables
are small tile-code streams (`$A598`: `10 2B 2A 10 10 27 2C 28 ...`; `$A5BB`: `10 27 2A 10 10 10
2B 2C 26 ...`, values in the `$10-$2C` tile-code range) — a compact shape blitted as map tiles,
consistent with a small object graphic rather than a full sprite.

So: **each pass through the `$12`/`$13` repeating water loop rolls a ~1-in-43 (`$FA`/`$100`≈2.3%)
chance to spawn a random object** (one of two variants) via the standard tile blitter — matching
`water-enemyboat-score14505`'s randomly-appeared enemy boat (`slot 2`, `TYPE=$13`, boat-mode flag
`02 02 02` per above).

## Water exit: ROAD_FEATURE $15 (mirrors $13's entry trigger)

`spyhunter-exit-water.vsf` (score 16050, seg_idx `$13`, feature `$15`, prev `$14`) pins the last
member of the `$11/$13/$14/$15` "scripted trigger" family. Segment `$13`'s ROM row stream is
`$14 -> $15` (play order) — so `$15` is literally the row right after the random-spawn row
`$14`, i.e. the last row before the loop exits back onto normal road via segment `$13`'s branch
(`main=$12` continues the loop, `branch=$14` exits it).

`$15` is checked in the same raster-IRQ code block as `$13` (`disassembly/spyhunter.asm:1099-1132`,
part of `IRQ_MAIN`'s bottom-half handler, right after the per-frame sprite-multiplex decrement
loop at `L8474`):

```
lda ROW_REPEAT
ldy #$14
cmp #$01                ; only on the LAST row of the current row-repeat cycle
bne L849E
lda ROAD_FEATURE
cmp #$15
beq L84AA               ; feature $15 -> Y stays $14
cmp #$13
bne L84C9
ldy #$04                ; feature $13 -> Y becomes $04
L84AA:
    sty STATE_4D18       ; remember which row-band was (re)armed
L84AD:
    lda #$0A
    sta COLOR_RAM+HISCORE_HI,y   ; paint a 4-cell colour block: COLOR_RAM+Y+4..+7
    sta COLOR_RAM+BIT_MASK,y
    sta COLOR_RAM+OBJ_IDX,y
    sta COLOR_RAM+OBJ_IDX2,y
    lda #$19
    sta SPRMUX_CNT,y             ; re-arm 4 parallel sprite-multiplex counters
    sta SPRMUX_CNT1,y            ; for 25 ($19) rows starting at row Y
    sta SPRMUX_CNT2,y
    sta SPRMUX_CNT3,y
```

So `$13` (entering the water) and `$15` (exiting it) are a matched pair that **re-arm the
sprite multiplexer** — reload all four `SPRMUX_CNT*` countdown arrays for 25 rows starting at a
computed row (`Y=$04` on entry, `Y=$14` on exit) and paint a matching 4-cell colour-RAM block —
each at the last row of their respective feature's row-repeat cycle. `STATE_4D18` carries the
armed row index forward so the `L849E` path (taken every other frame, when `ROAD_FEATURE` isn't
`$13`/`$15` or `ROW_REPEAT>1`) can consume/clear it via the same paint-and-arm code at `L84AD`.
This is most likely what schedules the extra multiplexed hazard/enemy-boat sprites specifically
at the river's entry and exit bands, rather than a purely visual flash.

## Open item: does crashing into water cost a life?

`become-boat` has `LIVES $4D15=$00`, `crash-into-water` has `LIVES $4D15=$01` — but the two
snapshots are **not a matched before/after pair**: `become-boat`'s score (13625) is higher than
`crash-into-water`'s (9850), so they come from different attempts/points, not a single continuous
sequence. Can't conclude a life was lost from these two alone. Needs a same-session snapshot pair
(boat entry, then crash) to confirm.

## New information (list)

1. `ROAD_FEATURE $02` = boat/water-crossing row, confirmed via segment `$11`'s ROM feature stream
   (`02 03 02`, played in that order) and both live snapshots.
2. It uses the same generic `OBJ_ADDR_LO/HI`-indexed graphics table as every other ordinary road
   feature (`SCROLL_SRC=$2AC0`) — no special-case blitter.
3. Segment `$11` (the boat) is reached from segment `$0F` (feature `$13`, river-entrance) —
   confirms the scripted sequence river-entrance -> boat documented piecemeal across snapshots.
4. Row feature `$03` (between the two boat rows in segment `$11`) is not yet identified —
   candidate: a water-current/wake variant.
5. Whether crashing into the water costs a life is unconfirmed (see above) — needs a paired
   snapshot capture in one continuous session.
6. `OBJ_TBL63/6B/73` (all three set to `$02` together) is a shared boat/terrain-mode flag for NPC
   object slots, confirmed across all three water snapshots.
7. `ROAD_FEATURE $14` (in the repeating `$12`/`$13` water loop) is a ~2.3%-per-pass random spawn
   trigger, traced directly in ROM at `LA60E`/`LA62D` — picks one of two small tile-blit shapes
   (`$A598`/`$A5BB`) via `DRAW_OBJECT_TILES`'s blit parameters. This explains the randomly
   encountered enemy boat in `water-enemyboat-score14505.vsf`.
8. `ROAD_FEATURE $15` = the water-exit trigger, matched with `$13`'s water-entry trigger — both
   traced in `IRQ_MAIN`'s bottom-half handler (`disassembly/spyhunter.asm:1099-1132`) re-arming
   all four `SPRMUX_CNT*` sprite-multiplex counters for 25 rows at a computed row band (`$04` on
   entry, `$14` on exit) plus a matching 4-cell colour-RAM block, confirmed by
   `spyhunter-exit-water.vsf` (seg `$13`, feature `$15`, prev `$14`). This closes out the last of
   the four `$11/$13/$14/$15` "scripted trigger" feature codes flagged in `Road_Map_Decode.md`.
