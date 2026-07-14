# Spy Hunter - Remaining work plan

Snapshot of outstanding work as of this session. Cross-checked directly
against `spyhunter.asm`'s current state (not just the session's task
tracker) - see the verification note at the bottom.

## Current status

- **540+ labels**, effectively all real names now (only a handful of
  auto-generated `LXXXX:` addresses remain, mostly internal branch targets
  inside the four blocks converted this session - see below).
- **Phase 1 is complete.** All four remaining "raw data that's actually
  code" blocks (~3.2 KB total) have been converted to labelled instructions
  and verified byte-identical against `spyhunter.bin`. This file no longer
  has any undissected code - what remains as raw `.byte` is legitimate,
  identified graphics/table data.

## Phase 1 - Code-to-instructions conversions (COMPLETE)

| # | Block | Size | Location | Result |
|---|---|---|---|---|
| 25 | Per-object handler | 1250 B | after `INIT_OBJECT_SLOT` | **Done** - the counterpart to #26: draw routines for `OBJ_TYPE` `$00`-`$05`/`$07`/`$08` (the hero's own type shares one 10-frame table, by far the largest), plus the 7 `TYPE_TBL_*` init tables `COMMIT_TYPE` reads from |
| 26 | Largest per-object handler | 1655 B | after `MUSIC_START_THEME` | **Done** - the per-object-type DRAW dispatch: 15 per-animation-frame address tables + ~40 draw routines, reached via `OBJINIT_PARAM_TBL`'s draw-vector column through a two-stage `ZVEC_DRAW` indirection. Confirmed the `$12`/`$13` boat and `$1B` bullet draw tables live here |
| 28 | Attract/road-reset helper | 139 B | after `RESET_SCROLL_VARS` | **Done** - `ATTRACT_HELPER`, a countdown-driven effect trigger called from the hero/object move-handler block |
| 29 | Effect spawn/param helper + FX tables | 160 B | after `SEGMENT_FX_FIRE` | **Done** - `SEGMENT_FX_HELPER`, a `ROAD_FEATURE`-indexed parameter lookup called from `MOVE_BOAT_MAIN`'s hazard chain |

Full writeup: `claude/Draw_Handler_Notes.md` (all four blocks). None of the
four turned out to hold the Road Lord/scoring logic that was the original
motivation for prioritising #26 - see Phase 2 below, still open.

## Phase 2 - Open research questions (investigation, not conversion)

Now that all code is converted and readable, these are pure semantic-
identification questions rather than "find the code" questions:

- **#32** - Where does `OBJ_TYPE` map down to a `POINTS_TBL` kill tier
  (0/500/700) when an enemy is destroyed? `SCORE_EVENT`'s queue-write site
  hasn't been located yet.
- **#33** - Which `OBJ_TYPE` values are the Road Lord, Switch Blade, and
  The Enforcer? (The Copter at `$08` and the boat enemies at `$13` are
  already confirmed; these three aren't.)
- **#34** - What does `HERO_STATE=$07` mean (the gate on machine-gun fire),
  and what do `$C6`/`$C7` represent (the proximity/cooldown check)?
- **#37** - `MOVE_HERO`'s full `SEQ_STATE`/`ROAD_FEATURE` state-machine -
  structurally traced and converted to real instructions already, but not
  yet mapped to specific gameplay moments (candidate: boathouse/bridge
  scripted sequences).

These genuinely need **live gameplay evidence** (a VICE snapshot pair, not
just static reading), separate from Phase 1's code conversion:

- **#36** - Does pressing "up" actually make `SCROLL_SPEED` faster or
  slower? (`SpeedCode_Notes.md` traced the full accumulate/divide/
  re-centre/reverse-table chain but the net sign isn't obvious from static
  analysis alone.) Also: what does the steering half's `SPR_XMSB` bit-6
  toggle actually do on screen?

## Phase 3 - Documentation housekeeping

- **#35** - `Boat_River_Notes.md` still has an "open item: does crashing
  cost a life?" section marked unconfirmed, even though this was directly
  settled by code-reading in `Collision_Detection_Notes.md`. Just needs the
  cross-reference added.

## How this list was verified

Re-scanned `spyhunter.asm` directly for every comment matching "as data" /
"not yet disassembled" / "left for a future session" / "stored as data" /
"kept as data" / "left unexpanded", rather than trusting the session task
tracker alone. As of this update, the only remaining hit is stale phrasing
inside the already-converted `SPEED_STEP` comment describing *past* state
(fixed in passing) - there is no other genuine undissected code left in the
file.
