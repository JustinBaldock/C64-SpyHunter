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

## Slot 1 - `MOVE_HERO` ($8BD4)

The hero/player car's own movement/state-machine logic - the most complex
routine in the block. Broad shape: saves and clears the current `OBJ_TYPE`,
then branches on `SEQ_STATE` (0-6) into several sub-checks involving
`ROAD_FEATURE` (`$0F`/`$13`/`$14`), `ROAD_SEG_IDX`, a countdown
(`STATE_4D10`, armed to `$64`=100), `FLAG_FC`, `FLAG_DD`, and `STATE_4D17`.
Most paths either restore the saved `OBJ_TYPE` unchanged (`HERO_RESTORE_TYPE`)
or commit one of several sub-state values (`$00`/`$07`/`$09`/`$11`/`$18`) via
the shared `COMMIT_TYPE` tail. Not fully interpreted - candidate territory
for boathouse/bridge/scripted-sequence transitions, given the `ROAD_FEATURE`
values checked line up with features already documented elsewhere
(`$13`=river-entrance, `$0F`=broken-bridge/return - see
`claude/Boat_River_Notes.md`/`claude/Broken_Bridge_Notes.md`).

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
* Slot 1's (`MOVE_HERO`'s) full semantics - only the control-flow shape is
  traced, not what each `SEQ_STATE`/sub-state transition represents in
  gameplay terms.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` - the entire conversion is
comment/label/data-to-code only, no assembled bytes changed.
