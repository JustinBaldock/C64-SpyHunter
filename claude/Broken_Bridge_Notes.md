# Spy Hunter - Broken bridge / return to road (ROAD_FEATURE $0F)

From `spyhunter-skip-broken-bridge-return-to-road.vsf` (score 9850, timer 080, seg_idx `$0B`,
feature `$0F`, prev `$02`). Extracted with `tools/vsf_extract.py`.

## ROAD_FEATURE $0F = broken-bridge skip / return to normal road

The snapshot lands in **segment `$0B`** (`ROAD_PTR=$AD2C`, 3 rows). Reading the raw row bytes
from the ROM (segment `$0B`'s feature stream) gives `06 05 0F`; played in the tool's documented
reverse order (`disassembly/spyhunter.asm:1250-1255`), the actual sequence is
**`$0F` (broken-bridge/return) -> `$05` -> `$06`** (both plain-road features, `rowrep=$1C=28` each
— long, ordinary road blocks).

`PREV_FEATURE=$02` in the snapshot (boat/water, see `claude/Boat_River_Notes.md`) matches this
exactly: segment `$0B` is the **branch target of the boat segment `$11`**
(`ROAD_SEG_TBL[$11] = (main=$12, branch=$0B)`), and `$11`'s own last-played row is feature `$02`
again (its row stream `02 03 02` ends on `$02`). So the full scripted chain now reads:

```
river-entrance ($0F, feature $13) -> boat ($11, feature $02 -> $03 -> $02) -> [branch] ->
segment $0B (feature $0F "broken bridge, return to road" -> $05 -> $06, plain road)
```

i.e. "broken bridge" isn't a hazard the player reacts to in the moment — it's a **scripted
segment transition** that ends the water section and puts the player back on ordinary road,
matching the snapshot's own filename/description.

## Graphics-table evidence

`OBJ_ADDR_LO/HI` + `OBJ_ROWREP_TBL`/`OBJ_SEGREP_TBL` at index `$0F` (read from the assembled ROM):

```
feature $0F -> SCROLL_SRC = $4A40, ROW_REPEAT = $16 ($22), SEG_REPEAT = $01
```

`$4A40` is the **last** entry in the ordinary `$00-$0F` graphics-pointer table — the table's
address range runs `$2980` (`$00`) up to `$4A40+`(`$0F`)'s block, ending right at the documented
`$4D00` game-state-variable boundary. So `$0F` is the final "ordinary" feature code; everything
from `$10` up lands outside this table's clean address progression (see
`claude/Road_Map_Decode.md` for the full table dump) and behaves differently — several of those
higher codes (`$11`, `$13`, `$14`, `$15`) are separately checked by explicit `CMP #imm` branches
in `UPDATE_SCENE_SELECT` (`disassembly/spyhunter.asm:2361-2374`) and elsewhere, i.e. they double
as scene-transition triggers, not just tile-graphics indices.

## New information (list)

1. `ROAD_FEATURE $0F` = the broken-bridge skip that returns the player to normal road, confirmed
   via segment `$0B`'s ROM feature stream (`0F 05 06`, played in that order) matching the boat
   segment's branch target and the snapshot's own `PREV_FEATURE=$02`.
2. It is a scripted **segment-graph transition** (boat segment `$11`'s branch entry), not an
   in-the-moment player hazard.
3. `$0F` is the last entry in the "ordinary" 16-entry `OBJ_ADDR_LO/HI` graphics table
   (`$00-$0F`, spanning ROM/RAM `$2980-$4CFF`); feature codes `$10` and above fall outside this
   table's address progression and are handled separately (see `Road_Map_Decode.md`).
