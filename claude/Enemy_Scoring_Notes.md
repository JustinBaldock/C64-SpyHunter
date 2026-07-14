# Spy Hunter - enemy identification & scoring tiers (tasks #32/#33/#34)

Full trace of `SCORE_EVENT`'s queue-write site (the missing piece
`claude/Enemy_Agents_Manual_Reference.md` flagged as "not yet located"),
which turned out to directly answer both the scoring-tier question (#32)
and most of the remaining `OBJ_TYPE` identification question (#33). Traced
entirely from the collision-detection block (`$99E3-$9DB9`,
`claude/Collision_Detection_Notes.md`) and the panel/scoring code
(`TALLY_SCORE_EVENTS`/`ADD_SCORE`), both already fully converted to real
instructions - no new disassembly needed this pass, just reading.

## #32: how `OBJ_TYPE` maps down to a `POINTS_TBL` kill tier

**There is no lookup table.** Each enemy `OBJ_TYPE`'s own `MOVE_TYPE_*`
handler (in the collision block) has its kill tier **hardcoded as a literal
constant** in its own code:

```
ARM_SCORE_EVENT_X8:
    ldx ZTMP_08
ARM_SCORE_EVENT:
    inc SCORE_EVENT,x        ; queue one event in tier-slot x
```

`SCORE_EVENT` (`$4DC3`) is an 8-byte array - but it's indexed by **tier
number**, not by which object slot held the enemy: each `MOVE_TYPE_*`
handler loads `ZTMP_08` (or, for type `$07`, `X` directly) with a **fixed
tier index** before calling `ARM_SCORE_EVENT_X8`/`ARM_SCORE_EVENT`:

| `OBJ_TYPE` | Tier index (`X`) | `POINTS_TBL[X]` | Trigger |
|---|---|---|---|
| `$07` | `5` (hardcoded `ldx #$05`) | **700** | `STATE_4D83,x` nonzero |
| `$09` | `4` (`ZTMP_08=$04`) | **500** | `STATE_4D83,x` nonzero |
| `$0C` | `3` (`ZTMP_08=$03`) | **150** | `STATE_4D83,x` nonzero, **decrementing multi-frame** (see below) |
| `$0D` | `3` (`ZTMP_08=$03`) | **150** | `STATE_4D83,x` nonzero, single check |
| `$12` | `6` (`ZTMP_08=$06`) | **1500** | `STATE_4D83,x` nonzero |
| `$13` | `3` (`ZTMP_08=$03`) | **150** | `STATE_4D83,x` nonzero |

Later, `TALLY_SCORE_EVENTS`/`TALLY_ONE_EVENT` drains this array (indices 7
downto 0) and calls `ADD_SCORE` with `y = index*2`, directly indexing
`POINTS_TBL` - i.e. **tier index IS the `POINTS_TBL` entry number**, exactly
matching `claude/Enemy_Agents_Manual_Reference.md`'s decoded table (entry
3=150, 4=500, 5=700, 6=1500). Entries 0/1/2 (0/15/25) are never reached via
this path - no code was found calling `ADD_SCORE` with `y=0/2/4` (only
`y=0` at two other unrelated call sites, and this tier-index path), so the
water/road per-distance scoring (15/25 pts) documented in the manual must
be added some other, not-yet-traced way (still open - see below).

`STATE_4D83,x` is the shared "hit pending" flag: mainly armed by the
bullet's own hit-resolution (`MOVE_TYPE_1B_B`, below), but also directly by
at least one DRAW routine (`DRAW_T0E_F1`, task #26's block - an
animation-driven countdown `OBJ_TBL5B,x` that arms `STATE_4D83,x` once it
expires, for types `$0E`/`$0F`/`$10` - see the Switch Blade discussion
below).

**`$12`'s tier (1500 = the boathouse land/water transition value) is not a
kill tier at all** - `$12` is very likely not an enemy, despite sharing the
same low-level dispatch chain as `$09`/`$0D`/`$13` (see `claude/Draw_Handler_Notes.md`:
`$12`/`$13` share a draw table, and `$13` is the confirmed boat). Candidate:
`$12` represents the hero's own boat-transition event reusing the object-type
machinery, not a distinct agent.

## #33: `OBJ_TYPE` -> enemy identity

Combining the tier table above with `claude/Enemy_Agents_Manual_Reference.md`'s
already-decoded `POINTS_TBL` (tier 3=150 shared by Road Lord/Switch
Blade/Barrel Dumper, tier 4=500 shared by Enforcer/Doctor Torpedo, tier
5=700=The Copter alone) and the already-confirmed boat/locomotion evidence:

| `OBJ_TYPE` | Tier | Confidence | Identity |
|---|---|---|---|
| **`$07`** | 5 (700) | **High** - only type reaching tier 5, matches the Copter's unique point value exactly | **The Copter (Mad Bomber)** |
| **`$13`** | 3 (150) | **High** - tier 3 AND independently confirmed as a boat (spawns 3x simultaneously, `claude/Enemy_Agents_Manual_Reference.md`) | **Barrel Dumper** (the boat 150-pointer) |
| **`$0C`** | 3 (150) | Moderate | **The Road Lord** (see reasoning below) |
| **`$0D`** | 3 (150) | Moderate | **Switch Blade** (by elimination against `$0C`) |
| **`$09`** | 4 (500) | Moderate | **The Enforcer** (no boat evidence found; candidate also covers Doctor Torpedo - see below) |
| `$12` | 6 (1500, not a kill) | - | Not an enemy - see #32 above |
| `$11` | n/a | Moderate | **Not an enemy - the hero's own "normal driving" `HERO_STATE`** (see below) |

### Road Lord vs. Switch Blade (`$0C` vs `$0D`)

Both reach tier 3 (150 pts), but their `MOVE_TYPE_*` handlers differ in one
structurally important way:

```
MOVE_TYPE_0D/09/13 (shared chain):        MOVE_TYPE_0C:
    lda STATE_4D83,x                          lda STATE_4D83,x
    beq MOVE_HAZARD_TAIL                      beq MOVE_HAZARD_TAIL
    jmp ARM_SCORE_EVENT_X8   ; once            dec STATE_4D83,x        ; multi-frame
                             ; and done         bne MOVE_TYPE_0C_RETRY  ; countdown -
                                                jmp ARM_SCORE_EVENT_X8  ; scores again
                                                                        ; EVERY frame
                                                                        ; while nonzero
```

`$0D` (and `$09`/`$13`) score **once**, immediately, on the first frame
`STATE_4D83,x` is seen nonzero. `$0C` instead **decrements** `STATE_4D83,x`
every frame and re-queues a score event each time it's still nonzero after
decrementing - i.e. **sustained contact keeps awarding points, frame after
frame, until the counter runs out.** This is a distinctive "must stay in
contact" mechanic that fits the Road Lord's unique trait far better than a
one-shot kill: the manual says it "must be rammed off the road" (implied
sustained pushing, not a single tap), matching a multi-frame ram/decrement
pattern much more naturally than Switch Blade's straightforward "shoot it
once" kill. This is inference from behavioural asymmetry, not a smoking-gun
"bulletproof" flag (no `OBJ_TYPE` exclusion for `$0C` was found anywhere in
the bullet's own hit-resolution code - see the open question below) - flagged
as moderate, not high, confidence.

### The Enforcer / Doctor Torpedo (`$09`)

Only **one** `OBJ_TYPE` (`$09`) was found reaching tier 4 (500 pts), but the
manual lists two agents at that tier - one road (Enforcer), one boat
(Doctor Torpedo). No boat-locomotion evidence (`OBJ_TBL63/6B/73`) has been
tied to `$09` in any snapshot so far, and its draw table (`$9448`, task
#26) is not shared with the confirmed-boat types (`$12`/`$13`'s `$95EB`).
Working hypothesis: **`$09` is reused for both** - the same type code,
with the boat/road distinction coming from which terrain it's spawned on
(`SCENE_ID`/water-mode flags), not from a separate `OBJ_TYPE` value - the
same "one type, context determines flavour" pattern already established for
other shared-table types in `claude/Draw_Handler_Notes.md`. Not confirmed;
a snapshot with a torpedo-firing boat enemy captured mid-encounter would
settle this.

### `$11` is very likely the hero's own state, not an enemy

The file's own header notes (`spyhunter.asm`, the `HERO_STATE=$11`
bridge/enemy-unshootable snapshot discussion) already observed that
`HERO_STATE=$11` dispatches through this exact `OBJINIT_PARAM_TBL` entry
(`move=$9B02 draw=$95BE`) - i.e. `$11` shows up as the **hero's own** type
value in a captured snapshot, not an NPC's. This session found independent
supporting evidence: `MOVE_TYPE_1B_B` (the bullet's generic hit-resolution
pass) explicitly **excludes** `OBJ_TYPE=$11` from ever registering a hit:

```
    lda OBJ_TYPE,y
    cmp #$11
    beq MOVE_TYPE_1B_B_NOHIT    ; type $11 can never be "hit" by the bullet
    cmp #$07
    beq MOVE_TYPE_1B_B_NOHIT    ; type $07 excluded here too (handled by a
                                 ;   separate, earlier pass - see #34 below)
```

Since the bullet's hit-scan walks every object slot including the hero's
own (slot 1), and nothing else in this pass excludes slot 1 by slot number,
excluding it by **type** value `$11` is exactly what you'd need to stop the
hero from ever "shooting itself" while in that state. Read together with
the header's existing snapshot evidence, `$11` is best explained as a
normal hero substate (candidate: the bridge/narrow-section driving state),
not a Road Lord/Switch Blade/Enforcer candidate - removed from consideration
for #33.

### Still open

* Whether `$09` really is shared between Enforcer/Doctor Torpedo, or
  whether Doctor Torpedo has a separate, not-yet-found type.
* No structural "bulletproof" flag was found for `$0C` (Road Lord candidate)
  - its 150-tier score can still be reached via the same generic bullet-hit
  path as everything else that isn't `$07`/`$11`. The Road Lord/Switch Blade
  split above rests on the multi-frame-scoring asymmetry, not a hard
  exclusion - worth a live snapshot check (does shooting the Road Lord
  candidate ever visibly register, contra the manual's "bulletproof" claim?).
* The 15/25-point road/water per-distance scoring (`POINTS_TBL` entries 1/2)
  was not traced to a call site this session - `ADD_SCORE` is only called
  with `y=0` (twice, bookkeeping-only) and `y=tier*2` (the kill-tier path
  above). Distance scoring must be added some other way, not yet found.

## #34: `HERO_STATE=$07` and the `$C6`/`$C7` machine-gun proximity check

Full context, `GUN_CHECK_FIRE` (inside `MOVE_GUN_SLOT`, slot 7's own move
handler, hero/object move-handler block):

```
GUN_CHECK_FIRE:
    lda JOY1_FIRE_BTN
    beq SLOT7_BAIL              ; fire button not pressed
    lda SEQ_STATE
    cmp #$02 : bcc SLOT7_BAIL   ; only while SEQ_STATE in [2,4]
    cmp #$05 : bcs SLOT7_BAIL
    lda HERO_STATE
    cmp #$07 : bne TYPE_GUN_NOFIRE   ; must be EXACTLY HERO_STATE=$07
    lda GUN_HEAT
    beq TYPE_GUN_NOFIRE          ; no heat left
    lda $C7
    bmi TYPE_GUN_NOFIRE          ; $C7 must be non-negative
    lda $C6
    and #$7F
    cmp #$46 : bcs TYPE_GUN_NOFIRE   ; ($C6 & $7F) must be < $46 (70)
    dec GUN_HEAT
    ; ... TYPE_GUN_FIRED: commits OBJ_TYPE=$1B (the bullet)
```

**`HERO_STATE=$07` confirmed as the exact, single required value** for the
machine gun to be fireable - not a range, an exact match. Given
`HERO_STATE` **is** `OBJ_TYPE[1]` (the hero's own slot's type byte - same
memory, just a friendlier alias), this is numerically the same value as the
enemy Copter's `OBJ_TYPE` (`$07`, see #33 above) - a namespace coincidence,
not a conflict: in `PROCESS_OBJECTS`, a positive `OBJ_TYPE` dispatches
through `TYPE_DISPATCH` regardless of which slot holds it, so if the hero's
own slot briefly has `OBJ_TYPE=$07`, it would technically run
`MOVE_TYPE_07`'s code (the Copter's own handler) that frame instead of
`MOVE_HERO`. This is **harmless in practice**: `MOVE_TYPE_07` only does
anything if `STATE_4D83,x` (that slot's own "hit pending" flag) is nonzero,
which is essentially never true for the hero's own slot - so it reduces to
a silent no-op (`beq MOVE_TYPE_07_DONE : rts`) on every frame the hero
happens to be in this state. Best read as "normal driving, combat-ready"
- the hero's default/idle drivable substate, reusing the Copter's numeric
type value purely by coincidence of a shared, tightly-packed `OBJ_TYPE`
space.

**`$C6`/`$C7` identified: `SPR_STAGE+12`/`+13`, i.e. `SPR_STAGE` (`$BA`)
entry 6 of 8** - `SPR_STAGE` is the per-hardware-sprite clamped X/Y delta
array populated by `OBJ_CALC_SPRITE_DELTA` (Stage 5): for whichever object
is currently being processed in `PROCESS_OBJECTS`, it computes that
object's signed, clamped delta to *every* hardware sprite 0-7 and stores
each pair at `SPR_STAGE[n*2]`/`[n*2+1]`. `$C6`/`$C7` = `n=6`'s pair, i.e.
**hardware sprite 6's clamped X/Y delta from whichever object most recently
ran `OBJ_CALC_SPRITE_DELTA`.**

Their gating logic is fully confirmed: `$C7` (Y delta) must be
non-negative (sign test), and `$C6` (X delta)'s low 7 bits must be under
`$46` (70 decimal, out of a 0-63 clamped range per `OBJ_CALC_SPRITE_DELTA`'s
own comments) - i.e. two threshold checks, consistent with a
**proximity/clearance check** against hardware sprite 6 specifically,
matching the earlier tentative read in `claude/Controls_And_Difficulty_Notes.md`.

**Not fully resolved:** slot 7 (the gun, `MOVE_GUN_SLOT`) is dispatched via
the *slot*-indexed path (`OBJ_MOVE_DISPATCH`/`OBJMOVE_VEC_LO/HI`, taken
because its `OBJ_TYPE` has bit 7 set), which does **not** itself call
`OBJ_CALC_SPRITE_DELTA` first (unlike the ordinary `TYPE_DISPATCH` path).
So by the time `GUN_CHECK_FIRE` reads `$C6`/`$C7`, the value is a
**leftover** from whichever positive-`OBJ_TYPE` object was processed last
before slot 7 in `PROCESS_OBJECTS`'s per-frame sweep (slots run 7 downto 0,
so this would be slot 0's turn from the *previous* frame, since slot 7 -
the gun itself - never populates it, and slots 1-6 run after slot 7 within
the *same* frame). Which object's delta this actually amounts to at fire
time, and why hardware sprite index 6 specifically was chosen as the
gating reference, needs either a live snapshot pair (gun fires vs. blocked,
comparing `$C6`/`$C7` against on-screen sprite positions) or full
per-frame execution-order tracing - neither done this session.
