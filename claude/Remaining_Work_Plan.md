# Spy Hunter - Remaining work plan

Snapshot of outstanding work as of this session. Cross-checked directly
against `spyhunter.asm`'s current state (not just the session's task
tracker) - see the verification note at the bottom.

## Current status

- **479+ labels**, effectively all real names now (only a handful of
  auto-generated `LXXXX:` addresses remain).
- **~3.2 KB of the 16 KB ROM (~20%)** is still raw `.byte` data flagged
  "reached only indirectly via a runtime dispatch vector" - down from
  ~4.3 KB two sessions ago. Everything else is either real, annotated
  6502 instructions or legitimate, identified graphics/table data.

## Phase 1 - Remaining code-to-instructions conversions (4 blocks, ~3.2 KB)

The last of the "raw data that's actually code" blocks. Same process each
time: verified straight-line disassembly, label/equate map, multi-entry
"BIT-as-skip" overlaps handled as raw bytes with labels, mechanically
generated where the block is large/dense, byte-diffed against the ROM
before ever touching the real file.

| # | Block | Size | Location | Why it matters |
|---|---|---|---|---|
| 25 | Per-object handler | ~1.25 KB | after `INIT_OBJECT_SLOT` | Likely per-enemy-type behavior/weapons |
| 26 | Largest per-object handler | ~1.65 KB | after `MUSIC_START_THEME` | Best remaining candidate for the Road Lord's "can't be shot" logic and the enemy-destroyed -> `SCORE_EVENT` tier mapping; also very likely holds the six data tables `COMMIT_TYPE` (in the hero/object move-handler block, already converted) reads from |
| 28 | Attract/road-reset helper | ~139 B | after `RESET_SCROLL_VARS` | |
| 29 | Effect spawn/param helper + FX tables | ~160 B | after `SEGMENT_FX_FIRE` | |

Recommended order: **26 then 25** - block 26 is the highest-value target
(scoring/Road Lord), and finishing both closes out essentially all of
Phase 2 below as a side effect (the OBJ_TYPE-to-enemy and kill-tier
questions almost certainly resolve once these are readable). 28 and 29 are
small, low-risk, do whenever.

## Phase 2 - Open research questions (investigation, not conversion)

Likely to resolve naturally once Phase 1 is done, since they're contained
in the blocks being converted - but worth explicitly re-checking rather
than assuming:

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
tracker alone - two matches turned out to be stale phrasing inside
already-converted code (the `SPEED_STEP` overlap bytes, and a descriptive
aside inside the already-confirmed `POINTS_TBL` comment) and were excluded.
The four blocks in Phase 1 are the complete, current list of genuine
undissected code.
