# Spy Hunter - Boat / river crossing (ROAD_FEATURE $02)

From `spyhunter-become-boat.vsf` (score 13625, seg_idx `$11`, feature `$02`, prev `$13`) and
`spyhunter-crash-into-water-score9850-timer143.vsf` (score 9850, seg_idx `$11`, feature `$02`,
prev `$13`). Both extracted with `tools/vsf_extract.py`.

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
