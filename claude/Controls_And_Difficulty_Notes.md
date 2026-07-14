# Spy Hunter - Controls and difficulty (bug fix: this is NOT a 2-player game)

User-reported bug: `spyhunter.asm` had a zero-page variable named `TWO_PLAYER` and
commented as a "2-player flag". **This was wrong.** Spy Hunter on the C64 is
single-player only. The user also noted that the game reads the *second*
joystick port, using its fire button for weapons - this turned out to be the
actual source of the old mislabelling, and is now confirmed and documented in
`spyhunter.asm` directly.

## What was actually wrong

Two separate, sequential menu prompts on the attract/menu screen were conflated
into one "how many players" story:

1. **First prompt** (`$1D`/`$1A` keys) - writes into what was called `NUM_PLAYERS`
   (`$4D11`). Tracing where this value is *used* (`INIT_PLAY_STATE`, Stage 2)
   shows it selects between two completely different **input decoders**:
   - value `1` -> `READ_DUAL_JOYSTICK_INPUT` (`$A152`) - reads joystick port 1
     for steering, and joystick **port 2** for weapon fire.
   - value `2` -> `CONTROL_KEYBOARD_ENTRY` (`$A9F6`) - the keyboard-matrix
     scanner (`SCAN_JOY_KEYS`/`DECODE_JOY_LOOP`, Stage 8).

   This is a **control-method** choice (dual joystick vs. keyboard), not a
   player count. Renamed to `CONTROL_SCHEME`.

2. **Second prompt** (`$18`/`$31` keys) - writes into what was called
   `TWO_PLAYER` (`$4D14`), and also directly into `GAME_STATE`. Tracing where
   *this* value is used (`ADD_SCORE`, near `NEXT_LIFE_SCORE`) shows it's added
   directly to the BCD ten-thousands digit of the extra-life score threshold:
   value `1` advances the threshold by 10,000 points, value `2` by 20,000.
   This is an **exact match** to the manual's documented difficulty figures
   (`claude/Enemy_Agents_Manual_Reference.md`): Novice awards an extra life
   every 10,000 points (after an initial 20,000), Expert every 20,000. Renamed
   to `DIFFICULTY_MODE` (1=Novice, 2=Expert) - confirmed, not a guess.

## The joystick-2-for-weapons finding

`READ_DUAL_JOYSTICK_INPUT` (`$A152`-`$A188`, previously left as raw
undissected `.byte` data under the "player-count" framing) was fully traced
this session:

```
lda CIA1_PRB       ; joystick port 1 (steering)
eor #$FF
...                ; decode up/down -> JOY_STATE (+1/-1), left/right -> JOY_STATE+1
...                ; joystick 1's own fire button -> JOY1_FIRE_BTN ($4D0B)
lda CIA1_PRA       ; joystick port 2
eor #$FF
and #$10           ; keep ONLY the fire-button bit
sta WEAPON_FIRE_INPUT   ; ($4D0C) - checked by UPDATE_WEAPONS to fire
```

`UPDATE_WEAPONS` (Stage 6) checks `WEAPON_FIRE_INPUT` (formerly the unnamed
`STATE_4D0C`) to decide whether to fire the currently-selected SPECIAL
weapon (smoke or missile, limited ammo). **Confirmed: this is a
single-player game that reads a second joystick port purely for its fire
button, to trigger the special weapon - independent of joystick 1's own
fire button, which is decoded separately into `JOY1_FIRE_BTN`.**

Cross-checked against the newly-added `references/Commodore_64_memory_map.rtf`:
it documents exactly this hardware layout - `$DC00` (`CIA1_PRA`) bit 4 = port 2
fire, `$DC01` (`CIA1_PRB`) bit 4 = port 1 fire - matching `READ_DUAL_JOYSTICK_INPUT`
byte-for-byte (`CIA1_PRA`/`CIA1_PRB` equate comments updated with the full
bit layout accordingly).

## The joystick-1-fire / machine-gun finding (follow-up)

`JOY1_FIRE_BTN` (`$4D0B`) - joystick 1's OWN fire button, on the same port as
steering - turned out **not** to be dead: it's read at `$8CE0`
(`LDA $4D0B`), inside the large still-undissected hero/object move-handler
block right after `OBJINIT_PARAM_TBL` (Stage 5, the ~1650-byte block flagged
"left for a future session"). Traced (not yet converted to labelled
instructions - see that block's header comment):

```
lda JOY1_FIRE_BTN
beq +skip                  ; not pressed -> skip
lda SEQ_STATE
cmp #$02 : bcc +skip       ; only while SEQ_STATE is in [2,4]
cmp #$05 : bcs +skip
lda HERO_STATE
cmp #$07 : bne +other      ; only in HERO_STATE $07
lda GUN_HEAT
beq +other                 ; no heat left -> can't fire
... (a couple of position/proximity checks against $C6/$C7, unnamed -
     possibly a dedicated "bullet" object slot's clamped sprite-delta) ...
dec GUN_HEAT                ; consumes one "shot" of heat
```

This is almost certainly the **machine-gun fire trigger**. `GUN_HEAT`
(`$F6`, previously "weapon/ammo counter (???)") is renamed/re-commented as a
heat/cooldown gauge rather than literal ammo - consistent with the machine
gun being the always-available primary weapon, and with `MOVE_BOAT_CRASH`
resetting it to 0 alongside `MISSILE_CNT`/`SMOKE_CNT` on a water-hazard
crash (a crash disarms all three weapon systems, not just the special one).

So the full picture: **joystick 1 steers and fires the machine gun;
joystick 2's fire button (and only its fire button) fires the special
weapon.** `HERO_STATE=$07`'s exact meaning and the `$C6`/`$C7` proximity
check aren't confirmed yet - candidates noted in `spyhunter.asm` as `(???)`.

## Bonus: the attract-mode auto-drive routine

The same raw-data block also contained a second routine (`$A189`-`$A1B9`),
now labelled `ATTRACT_AUTODRIVE`: it generates pseudo-random steering/speed
deltas (via `RNG_NEXT`) into the same `JOY_STATE` slots the real input
routines use, driving the demo car shown on the title/menu screens. Not
central to this bug fix, but sat in the same block and was traced along with
it. A couple of its decision inputs (`OBJ_TBL69`/`OBJ_TBL71` read bare/
unindexed, and `SCROLL_SPEED`) are still marked `(???)` - plausible as
"is there a hazard/obstacle nearby" and a pacing check respectively, but not
confirmed.

## Renames in `spyhunter.asm`

| Old name | New name | Notes |
|---|---|---|
| `NUM_PLAYERS` | `CONTROL_SCHEME` | 1=dual joystick, 2=keyboard |
| `TWO_PLAYER` | `DIFFICULTY_MODE` | 1=Novice, 2=Expert - confirmed via `ADD_SCORE` |
| `STATE_4D0C` | `WEAPON_FIRE_INPUT` | joystick 2's fire button |
| (unnamed `$4D0B`) | `JOY1_FIRE_BTN` | joystick 1's own fire button |
| `GOTO_PLAYER_SELECT` | `GOTO_MENU_SELECT` | |
| `ONE_PLAYER_VEC` | `JOYSTICK_CONTROL_VEC` | |
| `STATE_2P_ENTRY` | `CONTROL_KEYBOARD_ENTRY` | |
| `POLL_PLAYERS_CHOICE`/`PLAYERS_CHOSEN`/`DRAW_PLAYERS_PROMPT_LOOP` | `POLL_CONTROL_CHOICE`/`CONTROL_SCHEME_CHOSEN`/`DRAW_CONTROL_PROMPT_LOOP` | |
| `DRAW_GAME_PROMPT_LOOP`/`POLL_GAME_CHOICE`/`GAME_CHOICE_MADE`/`MENU_DONE_1P` | `DRAW_DIFFICULTY_PROMPT_LOOP`/`POLL_DIFFICULTY_CHOICE`/`DIFFICULTY_CHOSEN`/`MENU_DONE_NOVICE` | |
| (raw `.byte` block, "Joystick / keyboard decode helper... as data") | `READ_DUAL_JOYSTICK_INPUT` + `ATTRACT_AUTODRIVE` (real instructions) | |

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` (the session's `LIVES=$7F` cheat baseline) -
all renames and the data->code conversion are comment/label-only, no
assembled bytes changed.

## Update (follow-up session): the machine-gun trigger is slot 7, not slot 6

The `$8CE0`/`GUN_CHECK_FIRE` fragment mentioned above has now been fully
traced as part of converting the whole hero/object move-handler block
(`$8B2F`-`$8E33`) to real instructions - see
`claude/Hero_Object_Move_Handler_Notes.md` for the complete writeup. The
short version, correcting this doc's earlier speculation:

* The `JOY1_FIRE_BTN` check is **slot 7**'s own MOVE routine
  (`MOVE_GUN_SLOT`, `$8CC2`), not slot 6 as guessed above - slot 6 turned
  out to be the **boat** object instead (`MOVE_BOAT_SLOT`, `$8C90` - it sets
  `STATE_4D05`, the exact per-boat crash-sequence flag from
  `claude/Collision_Detection_Notes.md`'s `MOVE_TYPE_05_06`).
* `$C6`/`$C7` (the proximity/cooldown check gating a shot) are confirmed as
  `SPR_STAGE`-family bytes for a slot index, but not yet pinned to a
  specific slot's meaning - still open.
* A successful shot commits slot 7's own `OBJ_TYPE` to `$1B` - directly
  explaining `MOVE_TYPE_1B` from the collision-detection session, which was
  previously unexplained ("(???)" in that doc). `$1B` is the "live bullet"
  object type.

## Update (second follow-up session): where JOY_STATE actually drives car physics

User hypothesis: `SPEED_STEP_UP/DOWN` (a small routine found and converted
while looking for `SCROLL_SPEED`-adjusting code - see its comment header in
`disassembly/spyhunter.asm`) responds directly to joystick up/down.
Investigated by searching every reference to `$DC00`/`$DC01` and to
`JOY_STATE` in the assembled ROM:

* **No other raw `$DC00`/`$DC01` read exists anywhere** - only inside the
  already-converted `READ_DUAL_JOYSTICK_INPUT` and `SCAN_JOY_KEYS` (the
  latter is also how keyboard "I"/"K" would come in, via `KEYCODE_TBL` -
  both control schemes feed the same `JOY_STATE` array).
* **`JOY_STATE` (byte 0, speed) is read in exactly one place in the whole
  ROM**: `SPEEDCODE_IMAGE` (`$86F2`-`$8784`, now fully converted - see
  `claude/SpeedCode_Notes.md`). This is THE player-input-to-car-physics
  routine, not `SPEED_STEP_UP/DOWN` - it feeds a low-pass-filtered
  accumulator that eventually calls a third, previously-missed entry point
  into `SPEED_STEP` (`SPEED_SET`, at `$A106`) to snap `SCROLL_SPEED` to a
  target value once the accumulator crosses a threshold.
* `SPEED_STEP_UP` turned out to be called from `SPEEDCODE_IMAGE` too (not
  found last session's search); `SPEED_STEP_DOWN`'s other two callers
  (inside the still-undissected block after `INIT_OBJECT_SLOT`, task #25)
  remain more likely automatic/terrain-triggered deceleration than direct
  input.
* Whether pressing "up" nets out to actually mean faster or slower isn't
  settled by static analysis alone (the accumulator math is a few
  indirection steps removed from a direct mapping) - would need a live
  snapshot pair to confirm.

## Still open

* The exact demo-AI logic in `ATTRACT_AUTODRIVE` (what `OBJ_TBL69`/`OBJ_TBL71`
  and `SCROLL_SPEED` mean in that specific context).
* `HERO_STATE=$07`'s meaning (the gate on machine-gun fire), and exactly
  what `$C6`/`$C7` represent (see `claude/Hero_Object_Move_Handler_Notes.md`).
* The full per-object handler blocks after `INIT_OBJECT_SLOT` and
  `MUSIC_START_THEME` remain separate future tasks.
