# Spy Hunter - Hero/object move-handler block ($8B2F-$8E33)

Full decode of the block flagged since Stage 5 as "the single largest remaining
undisassembled chunk of real game logic" - now converted to labelled 6502
instructions in `spyhunter.asm`. Method: same as the collision-detection block
(`claude/Collision_Detection_Notes.md`) - a verified straight-line disassembly,
a hand-built label/equate map, multi-entry "BIT-as-2-byte-skip" overlaps handled
as raw bytes with labels at each entry point, generated mechanically and
byte-diffed against the ROM before being applied to the real file.

## Structure

```
$8B2F-$8B3E  OBJMOVE_VEC_LO/HI   16 bytes, 8 (lo,hi) address pairs, one per SLOT
$8B3F-$8BAE  OBJINIT_PARAM_TBL   112 bytes, 28 (move,draw) vector pairs, one per TYPE
$8BAF-$8E33  five MOVE handlers, one per SLOT with OBJ_TYPE bit 7 set (the
             "direct dispatch" path in PROCESS_OBJECTS - separate from, and
             not overlapping with, OBJINIT_PARAM_TBL's own move vectors,
             which all point elsewhere)
```

`OBJMOVE_VEC_LO/HI` decodes to: slot0=`$8BAF`, slot1=`$8BD4`, slot2=`$8C5B`,
slot3=`$8C5E`, slot4=`$8C5B` (shared with slot2), slot5=`$8C5E` (shared with
slot3), slot6=`$8C90`, slot7=`$8CC2`. Slot3/5's entry (`$8C5E`) turned out to
be a mid-instruction overlap into slot2/4's own routine (see below) - not a
separate routine at all, just a different immediate value.

## Slot 0 - `SLOT0_HERO_WATCH` ($8BAF)

Watches `HERO_STATE` (slot 1, the hero's own type) and transitions **its
own** `OBJ_TYPE` to `$08`, `$0A`, `$19`, or `$1A` when `HERO_STATE` is
`$07`/`$09`/`$18`, or (via a separate check) `OBJ_TYPE+3` (slot 3) is `$12`.
Reads as a hero-state-reactive "companion/effect" object - candidate:
splash/dock/scripted-sequence visuals tied to the hero's own state
transitions, but not confirmed which. All four target types have their own
`draw` vectors in `OBJINIT_PARAM_TBL` (`$9448`/`$9478`/`$971E`/`$97A8`),
none decoded yet.

## Slot 1 - `MOVE_HERO` ($8BD4) - full state-machine now interpreted (task #37)

The hero/player car's own movement/state-machine logic - the most complex
routine in the block. It saves and clears the current `OBJ_TYPE`, branches
on `SEQ_STATE` (0-6), and - depending on which branch and a handful of
other flags - either restores the saved `OBJ_TYPE` unchanged
(`HERO_RESTORE_TYPE`, i.e. no state change this frame) or commits a new
`HERO_STATE` value via the shared `COMMIT_TYPE` tail. Cross-referencing
every value against `claude/Road_Map_Decode.md`'s already-decoded
`ROAD_FEATURE` codes and the collision/scoring findings in
`claude/Enemy_Scoring_Notes.md` resolves what each branch represents:

### `SEQ_STATE` dispatch

| `SEQ_STATE` | Path | What it does |
|---|---|---|
| 0, 3, 6+ | `HERO_RESTORE_TYPE` | No-op - `MOVE_HERO` does nothing these frames |
| **1** | `HERO_CHECK_ROAD_13` | **Boathouse-entry slowdown** (see below) |
| **2 or 4** | `HERO_CHECK_4D17` | Road-sign-cycle passthrough, or ordinary driving sub-state (see below) |
| **5** | inline check | `ROAD_FEATURE==$14` -> commit `$18`; otherwise no-op |

### `SEQ_STATE==1`: the boathouse-entry slowdown

```
HERO_CHECK_ROAD_13:
    lda ROAD_FEATURE
    cmp #$13
    beq HERO_ARM_TIMER
    lda ROAD_SEG_IDX
    cmp #$11
    bne HERO_COUNTDOWN
HERO_ARM_TIMER:
    lda #$02
    jsr SPEED_SET          ; force SCROLL_SPEED = SPEEDCODE_TBL[2] = 2 (slow)
    lda #$64
    sta STATE_4D10          ; arm a 100-frame countdown
HERO_COUNTDOWN:
    dec STATE_4D10
    bne HERO_RESTORE_TYPE    ; still counting down -> no state change
    inc STATE_4D10
    bne SLOT1_SET_00          ; countdown just hit 0 -> commit HERO_STATE=$00
```

Triggered by `ROAD_FEATURE==$13` (already confirmed the river-entrance
transition feature, `claude/Boat_River_Notes.md`) or `ROAD_SEG_IDX==$11`
(the boat segment itself, reached from segment `$0F`/feature `$13` per the
same doc). While active, it **forcibly holds `SCROLL_SPEED` at a fixed slow
value for ~100 frames**, then releases the hero back to `HERO_STATE=$00`
(ordinary driving). This is almost certainly the scripted "car slows down
as it transitions into/through the boathouse" sequence - matches the
manual's "road -> boathouse (car becomes amphibious) -> water" terrain
description (`claude/Enemy_Agents_Manual_Reference.md`) about as directly
as static reading can confirm without a live capture.

### `SEQ_STATE` 2 or 4: sign-cycle passthrough vs. ordinary sub-states

```
HERO_CHECK_4D17:
    lda STATE_4D17
    beq HERO_CHECK_ROAD_0F
    bmi HERO_CHECK_ROAD_0F
    sec
    ror STATE_4D17          ; STATE_4D17 positive & nonzero: halve it (mark
    ...                     ;   consumed) but leave A - and hence the
                             ;   *original* STATE_4D17 value - untouched;
                             ;   a chain of BIT-skip no-ops then commits
                             ;   THAT value as the new HERO_STATE
```

`STATE_4D17` is the "sign-cycle armed" flag from `UPDATE_SCENE_SELECT`
(already documented there): it gets armed to a 3/2/1 round-robin value
(`STATE_4D16`) specifically when `ROAD_FEATURE==$11` or
`PREV_FEATURE==$15` - i.e. right at a river-entrance or just after leaving
the water, timed to cycle which road-sign message
(`ONROAD_MSG_TBL`/DETOUR/BRIDGE OUT/ICY ROADS) shows next. When this fires,
`MOVE_HERO` copies that same 1/2/3 value straight into `HERO_STATE` via an
elaborate chained BIT-skip (five consecutive 3-byte no-ops overlapping
`SLOT1_SET_18`/`_00`/`_07`/`_11`/`_09`'s own bytes) rather than loading a
fresh constant - `HERO_STATE` briefly becomes the sign-cycle counter's raw
value. Since `HERO_STATE` `$00`-`$03` all share one `OBJINIT_PARAM_TBL`
entry (identical move/draw vectors), this has no visible effect on the
hero's own appearance - it reads as reusing the hero's own type field as
convenient scratch storage for the sign-cycle counter, not a real hero
state.

When `STATE_4D17` is zero/negative (the normal case, away from a sign-cycle
moment), falls to `HERO_CHECK_ROAD_0F`:

```
HERO_CHECK_ROAD_0F:
    lda ROAD_FEATURE
    cmp #$0F : beq HERO_CHECK_RANGE      ; back on solid road -> check range
    cmp #$13 : bcs HERO_RESTORE_TYPE     ; >= water-crossing features -> no-op
    ldy FLAG_FC
    beq HERO_CHECK_RANGE
    dec FLAG_FC
    beq SLOT1_SET_09                      ; FLAG_FC just reached 0 -> HERO_STATE=$09
HERO_CHECK_RANGE:
    cmp #$02 : bcc SLOT1_SET_11            ; ROAD_FEATURE < 2 -> HERO_STATE=$11
    cmp #$0E : bcs HERO_RESTORE_TYPE       ; ROAD_FEATURE >= $0E -> no-op
    lda FLAG_DD
    bne SLOT1_SET_07                        ; FLAG_DD nonzero -> HERO_STATE=$07
    beq HERO_RESTORE_TYPE                    ; FLAG_DD zero -> no-op
```

Three more `HERO_STATE` values fall out of this:

* **`HERO_STATE=$11` when `ROAD_FEATURE < 2`** (i.e. `$00` or `$01`).
  `$01` is the already-confirmed **bridge** feature code
  (`claude/Road_Map_Decode.md`). This directly confirms the file header's
  existing speculation: the `enemy-unshootable.vsf`/bridge snapshot's
  `HERO_STATE=$11` is exactly this - a normal "on the bridge/narrow
  section" substate, not anything shooting-related, and (independently,
  `claude/Enemy_Scoring_Notes.md`) also explains why `$11` is excluded from
  the bullet's own hit-resolution: it's a hero state, not an enemy type.
* **`HERO_STATE=$07` when `ROAD_FEATURE` is in `[2,$0E)` and `FLAG_DD` is
  nonzero.** `FLAG_DD` is set exactly once, in `LOAD_NEXT_SEGMENT`, when
  the road graph loops back to segment `$1C` ("where the main path loops
  back to the start...treat reaching it as 'completed a lap'" - existing
  comment in `spyhunter.asm`) - and nothing resets it afterward. So this is
  a **one-time, permanent latch**: the machine gun (which requires exactly
  `HERO_STATE=$07`, `claude/Enemy_Scoring_Notes.md`) only becomes usable
  after the road graph has cycled back to segment `$1C` once. Whether that
  happens seconds into a run or after a full lap depends on the segment
  graph's actual layout/timing (`claude/Road_Map_Decode.md`) - not itself
  re-confirmed here, but the gating mechanism is exact and unambiguous.
* **`HERO_STATE=$09` when `ROAD_FEATURE==$0F` (or `<$13`) and a `FLAG_FC`
  countdown reaches exactly 0.** `FLAG_FC` is the same flag
  `WAIT_FRAME_TIMER` increments when the game timer expires
  (`EXTRA_LIFE_AVAIL` becomes `$FF`) on the car scene - so this specific
  branch only fires as part of that sequence, decrementing back to 0
  exactly as the hero returns to solid road (`$0F`, the confirmed general
  "back on solid road" marker reused at water-exit points,
  `claude/Dock_Exit_Notes.md`). Reads as a brief, one-shot post-timer-expiry
  transition state, not a repeating gameplay state.

### `SEQ_STATE==5`: `HERO_STATE=$18`

```
    lda ROAD_FEATURE
    cmp #$14
    beq SLOT1_SET_18
```

`ROAD_FEATURE==$14` is the confirmed random enemy-boat spawn trigger inside
the repeating water loop (`claude/Boat_River_Notes.md`). `HERO_STATE=$18`
being tied to this exact feature, during a specific `SEQ_STATE`, is
consistent with `SLOT0_HERO_WATCH`'s already-documented reaction to
`HERO_STATE=$18` (transitions its own type to `$1A`) and with the earlier
"two-part hero-boat respawn animation" candidate in
`claude/Enemy_Agents_Manual_Reference.md` for `$18`/`$19` - likely the
splash/respawn visual cue tied to the water-loop's spawn cadence, though
the exact visual isn't confirmed from static reading alone.

### Cross-check: `SLOT0_HERO_WATCH`

Slot 0's own handler (above) reacts to `HERO_STATE` `$07`/`$09`/`$18`
(exactly three of the five values `MOVE_HERO` can commit to) by changing
**its own** type - i.e. slot 0 is a dedicated "reacts to the hero's state"
companion object, and now that all three trigger values are pinned to
specific `SEQ_STATE`/`ROAD_FEATURE` contexts above, slot 0's own
transitions (to `$08`/`$0A`/`$1A`) inherit the same context: `$08` fires
alongside the lap-completion gun-ready state, `$0A` alongside the
post-timer-expiry blip, `$1A` alongside the water-loop spawn cue.

## Slots 2 & 4 - `SLOT_2_4_ENTRY` ($8C5B) / slot 3&5 overlap (`$8C5E`)

Checks `SCENE_ID` (bails if negative, i.e. during the weapons-van sequence),
then `ROAD_FEATURE` for `$0E`/`$14`; if neither, calls `RNG_NEXT` to
randomize. Writes the result to `VIC_SPRMC0` (the shared sprite-multicolour
register - affects **all** sprites, not just this slot) before falling into
`COMMIT_TYPE`. Reads as an environment-reactive global sprite recolour -
candidate: the icy-road/night palette effect noted in
`claude/Ice_Road_And_Lap_Notes.md`, though not confirmed. Slot 3/5 enters at
the exact same code via a BIT-skip overlap, just with a different immediate
value (`$0D` vs `$0C`) staged into `ZTMP_08` first - the two pairs of slots
share every byte of logic.

One internal branch (`SLOT24_APPLY`'s `cpx #$03 : beq SLOT24_TYPE_12`) can
never be taken as currently reached (`x` is always `OBJ_IDX`, which is 2 or
4 for this routine, never 3) - flagged `(???)` in the source rather than
asserted as dead code, since the routine might be reachable some other way
not yet found.

## Slot 6 - `MOVE_BOAT_SLOT` ($8C90) - CONFIRMED as the boat

Checks `SEQ_STATE` (1/3/5) combined with `HERO_STATE`/`ANIM_STATE`
(`STATE_9B`), and sets `STATE_4D05` to **5** (one path) or **6** (a second,
overlap-entered path) before falling into `COMMIT_TYPE`. `STATE_4D05` is the
exact "per-boat crash/special-sequence in progress" flag already traced from
the *other* side in `MOVE_TYPE_05_06` (`claude/Collision_Detection_Notes.md`)
- this is where that flag actually gets armed. Strong, direct confirmation
that slot 6 is the boat object, consistent with slot 6 being singled out by
index in several places elsewhere in the collision code.

## Slot 7 - `MOVE_GUN_SLOT` ($8CC2) - CONFIRMED as the machine-gun/bullet

**Correction to `claude/Controls_And_Difficulty_Notes.md`**: the confirmed
`JOY1_FIRE_BTN`/`GUN_HEAT` machine-gun-fire check (`GUN_CHECK_FIRE`, `$8CE0`)
is slot **7**'s routine, not slot 6 as earlier speculated (slot 6 is the
boat - see above).

Full gate for firing: `SEQ_STATE` in `[2,4]`, `HERO_STATE=$07`, `GUN_HEAT`
nonzero, and a proximity check against `$C6`/`$C7` (bit-7-masked comparisons
against `$46` and a sign check) - candidates for a `SPR_STAGE`-family
clamped-delta pair, but not confirmed which slot/meaning. On success,
`GUN_HEAT` is decremented and this slot's `OBJ_TYPE` commits to **`$1B`** -
directly explaining `MOVE_TYPE_1B` (`claude/Collision_Detection_Notes.md`),
previously just a decoded-but-unexplained hit-mask consumer. `$1B` is the
"live bullet" object type. On a failed fire attempt or various early-bail
conditions, the type instead becomes `$0B` (reuses `MOVE_TYPE_0B`'s logic)
or `$04`; when the routine isn't even trying to fire (`SEQ_STATE` 0/6/7+) it
cycles through `$15`/`$16`/`$17` (idle/reload states, not decoded).

## The shared `COMMIT_TYPE` tail ($8D2D)

All five routines' "success" paths converge here. Commits the new value in
`A` to `OBJ_TYPE,x`, then reinitialises the slot from six data tables -
`$8EAC` (-> `OBJ_TBL93`), `$8EE4` (-> `SPRITE_PTRS`/`OBJ_TBL23`), `$8F00`
(-> `OBJ_ANIM`), `$8E90` (-> `OBJ_TBL9B` + `HIT_GROUP0`/`HIT_GROUP2` bits),
`$8EC8` (-> `VIC_SPR_COLOR` + `VIC_SPR_MCM`/`VIC_SPR_XEXP`/`VIC_SPR_YEXP`
bits), `$8E74` (-> `OBJ_TBLA3` + an initial X-velocity direction/magnitude
via `OBJ_TBL53`/`OBJ_TBL4B` and calls to `$8994`/`$8988`) - then zeroes the
position/hit-pairing state (`OBJ_POS_Y`/`OBJ_POS_X`/`OBJ_TBL33`/`OBJ_TBL5B`/
`OBJ_TBL8B`/`STATE_4D83`/`OBJ_TBLAB`) and calls `$99DB`/`$8E5E` before
returning. All six source tables and both called subroutines live in the
**next** undissected block (after `INIT_OBJECT_SLOT`) and aren't decoded yet
- likely the per-`TYPE` "spawn parameters" (sprite shape, starting
velocity/hit-group, colour) referenced by index `y` = the newly-committed
`OBJ_TYPE`.

## New/updated equates

`STATE_4D04`, `OBJ_TBL23/33/3B/43/4B/53/5B` (per-slot arrays),
`VIC_SPR_YEXP`/`VIC_SPR_MCM`/`VIC_SPR_XEXP`/`VIC_SPR_COLOR` (VIC-II sprite
registers $D017/$D01C/$D01D/$D027).

## Still open

* `HERO_STATE=$07` and `$C6`/`$C7` are now resolved - see
  `claude/Enemy_Scoring_Notes.md`.
* The six data tables and two subroutines the `COMMIT_TYPE` tail reads/calls
  are now converted - see `claude/Draw_Handler_Notes.md`.
* Slot 1's (`MOVE_HERO`'s) full semantics are now interpreted - see the
  "full state-machine now interpreted" section above (task #37). What's
  left is confirming the exact visual/gameplay feel of each transition
  against live play (e.g. does the boathouse-entry slowdown visibly feel
  like "becoming amphibious"; what `HERO_STATE=$18`/slot 0's `$1A` reaction
  actually looks like on screen) - static reading has gone as far as it can
  without a live capture.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` - the entire conversion is
comment/label/data-to-code only, no assembled bytes changed.
