# Spy Hunter - Icy Road, lap/phase completion, and boat respawn

From the new snapshot batch: `level-ice.vsf`, `water-ice-area.vsf`, `yellow-area-maybe-level2.vsf`,
`respawn-boat.vsf`. Extracted with `tools/vsf_extract.py`.

## HERO_STATE $01 - a new value, first seen on the Icy Road

`level-ice.vsf` (score 42590, seg_idx `$01`, feature `$11`, prev `$0A`) shows `HERO_STATE`
(`OBJ_TYPE[1]`, `$A3`) = **`$01`** - a value not seen live in any prior snapshot. Per the
`OBJINIT_PARAM_TBL` dispatch-table check already done this session (`claude/Dock_Exit_Notes.md`),
`$01` was already known to share the same generic move/draw handler as `$00`/`$02`/`$03` (all
`move=$9A8E draw=$90AA`) - i.e. it was always architecturally grouped with the other "normal"
hero sub-states, just never confirmed live until now.

Seeing it specifically on the manual's documented Icy Road ("the surface is slippery and your car
is harder to control") is a strong contextual match: `$01` is a good candidate for a **"car
sliding/reduced-control" sub-state**, distinct from ordinary driving (`$FF`). Not proven from one
snapshot, but the timing lines up well. Also notable: `level-ice.vsf`'s hero-adjacent slot (slot 0)
shows `OBJ_TBL63/6B/73 = $FF/$FF/$FF` - the same "airborne" locomotion flag documented in
`claude/Enemy_Agents_Manual_Reference.md` for the Copter - worth a follow-up snapshot to check
whether the Copter specifically patrols the icy stretch, or this is coincidental.

## Segment `$1C` confirmed as the lap/phase-completion point

`yellow-area-maybe-level2.vsf` (score 17480, seg_idx `$1C`, feature `$12`, prev `$00`) lands
exactly on **segment `$1C`** - the segment `claude/Road_Map_Decode.md`'s decoded graph already
flagged as special: `LOAD_NEXT_SEGMENT` (`disassembly/spyhunter.asm`, Stage 6 annotation)
increments `ROAD_PHASE` and touches `MUX_SLOT0` specifically when the new segment is `$1C`,
treating it as "completed a lap" per that comment. The user's own observation - a **visible
palette/terrain colour change** ("yellow area") right around here - is exactly the kind of
player-visible effect `ROAD_PHASE`/the per-segment `ROAD_COLIDX_TBL` palette lookup
(`APPLY_SEGMENT_PALETTE`, Stage 6) would produce. This is a good independent confirmation of a
hypothesis that was previously only inferred from reading the code, not observed live - segment
`$1C` really does mark a new lap/phase, not just a code-level curiosity.

Not confirmed: whether this is literally "Level 2" in the way separate arcade levels usually work,
or just a colour/phase variation within one continuous course (the manual doesn't describe
discrete numbered levels - it describes one continuous terrain sequence: road -> boathouse ->
water -> more road, with bridge and icy stretches "in other screens"). `ROAD_PHASE` wrapping via
`AND #$03` (four phases, Stage 6) fits a repeating palette cycle better than a small number of
discrete "levels."

## Candidate boat-respawn sequence: `OBJ_TYPE $18`/`$19`

`respawn-boat.vsf` (score 8445, seg_idx `$12`, feature `$14`) shows two brand-new, adjacent,
boat-flagged (`$02/$02/$02`) object types - `$18` (slot 0) and `$19` (slot 1) - sitting right next
to each other on screen (columns `$19`/`$1A`, rows `$0E`/`$0F`). Given the filename indicates this
is the moment the player's own boat reappears after a crash, the leading candidate is a two-part
respawn animation (e.g. a splash effect plus the boat itself), by analogy with the weapons van
using its own dedicated `OBJ_TYPE $03` for a scripted sequence (`claude/Weapons_Truck_Notes.md`).
Not confirmed - could instead be a pair of ordinary enemy boats that happened to be adjacent.

## Open follow-ups

* Which of `$18`/`$19` (if either) is actually the hero vs. a visual effect - would need a
  snapshot a frame or two before/after to see which one tracks with subsequent player input.
* Whether `$07` (seen adjacent to the candidate Copter `$08` in `helicopter-enemy.vsf`) really is
  a dropped bomb - a snapshot right as a bomb visibly falls would confirm this.
* The Road Lord, Switch Blade, and Enforcer still have no candidate `OBJ_TYPE` at all.
