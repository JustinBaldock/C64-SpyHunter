# Spy Hunter - Exiting the water: dock, building, and the truck

From `spyhunter-exit-water-dock-building-and-truck.vsf` (score 16130, timer 9304, seg_idx `$14`,
`ROAD_SEG_LEN=$10`, feature `$0F`, prev `$15`). Extracted with `tools/vsf_extract.py`. User-visible
context: a dock/building scene with a truck present.

## Segment chain: the water loop exits onto segment $14, not straight back to $12

`PREV_FEATURE=$15` (the water-exit trigger documented in `claude/Boat_River_Notes.md`) and
`ROAD_SEG_IDX=$14` together confirm which of segment `$13`'s two exits was taken. Segment `$13`
(`main=$12, branch=$14`, row stream `$14 -> $15`) has two ways out of the repeating water loop:
`main` loops back into `$12` for another lap, `branch` exits to segment `$14`. This snapshot is
sitting in segment `$14` at its very first row (`ROAD_SEG_LEN=$10` = the segment's full 16-row
length) with feature `$0F` — so the **branch exit was taken**, landing on segment `$14`, whose
full row stream (from `claude/Road_Map_Decode.md`'s ROM dump) is:

```
seg $14: main=$15 branch=$17   0F 10 08 11 0B 05 06 05 06 04 07 04 07 08 09 12
```

`$0F` opening this segment is the same feature code already identified as "broken-bridge skip /
return to road" (`claude/Broken_Bridge_Notes.md`, previously pinned via segment `$0B`). Seeing it
again here, as the very first row after exiting the water loop via `$14`, means **`$0F` is a
general "you're back on solid road" scene marker reused at more than one water-exit point**, not
a one-off tied only to segment `$0B` — both the boat segment's branch (`$11`->`$0B`) and this
repeating-loop branch (`$13`->`$14`) open with it. `$0F`'s graphics-table entry
(`SCROLL_SRC=$4A40, ROW_REPEAT=$16=22`, from the ROM table dump) is a notably tall 22-row block —
plausibly big enough to carry the dock/building scenery the user is describing, though that's a
size argument, not a visual confirmation.

## HERO_STATE $02 (new value) and a distinct object slot pattern

`HERO_STATE` (`OBJ_TYPE[1]`, `$A3`) = **`$02`**, `OBJ_ANIM[1]` (`$9B`) = **`$08`** — both values
not seen in any prior snapshot (previously: `$FF` normal, `$03` van, `$00`/`$11` on the bridge).
Checking `OBJINIT_PARAM_TBL` (`$8B3F`, indexed by `TYPE*4`, feeds the per-object move/draw
dispatch vectors `ZVEC_MOVE`/`ZVEC_DRAW` copied at `disassembly/spyhunter.asm:1976-1982`) directly
from the ROM:

```
type $00: move=$9A8E draw=$90AA
type $01: move=$9A8E draw=$90AA
type $02: move=$9A8E draw=$90AA   <- same handler as $00/$01/$03
type $03: move=$9A8E draw=$90AA
```

So `HERO_STATE=$02` dispatches through the **same generic move/draw handler** as `$00`, `$01`
and `$03` (the van) — meaning these low hero-state values are likely a small state machine (idle
/ transitioning / in van / ...) whose actual differing behaviour comes from checks elsewhere
against `HERO_STATE` directly (as seen in `UPDATE_SCENE_SELECT`,
`disassembly/spyhunter.asm:2361-2374`), not from separate per-state move code. `$02` is a
plausible "boat-to-car transition at the dock" cutscene state, consistent with the user's
description, but not confirmed beyond this correlation.

Object slot 2 (`TYPE=$14`) shows a state pattern **not seen before**:
`OBJ_TBL63=$01, OBJ_TBL6B=$03, OBJ_TBL73=$01` — distinct from both the ordinary-enemy pattern
(`$00/$00/$00`) and the boat-mode pattern (`$02/$02/$02` documented in
`claude/Boat_River_Notes.md`). This is a candidate for the "truck"/dock-building object the user
describes, but with only one snapshot there's no way to separate "this slot is the truck" from
"this slot is mid-transition between boat and road modes" — flagged as open, same standard as
`claude/Enemy_Invincibility_Notes.md`. Slot 6 (`TYPE=$06`) still carries the boat-mode `02/02/02`
pattern, i.e. a boat-flagged object is still present on screen as the dock scene begins.

## New information (list)

1. Segment `$14` (opening feature `$0F`) is the water loop's **branch exit** (`$13`'s branch,
   taken after the `$15` water-exit trigger) — a second on-ramp back to normal road alongside the
   boat segment's branch (`$11`->`$0B`, also opening on `$0F`).
2. `$0F` is confirmed as a **reused, general "return to road" marker**, not segment-`$0B`-specific.
3. `HERO_STATE=$02` (new value, `ANIM=$08`) shares its move/draw dispatch entry with `$00`/`$01`/
   `$03` — supports "these are all hero sub-states sharing generic object code" rather than each
   having bespoke movement logic.
4. Object slot 2's `TBL63/6B/73=01/03/01` pattern is new and unidentified — candidate for the
   dock building or the truck the user observed, not confirmed.
5. A boat-mode-flagged object (slot 6) is still present as the dock scene opens.
