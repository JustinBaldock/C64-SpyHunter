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
`STATE_4D0C`) to decide whether to fire the currently-selected weapon
(smoke or missile). **Confirmed: this is a single-player game that reads a
second joystick port purely for its fire button, to trigger weapons -
independent of joystick 1's own fire button, which is decoded separately
into `JOY1_FIRE_BTN` and doesn't appear to be read anywhere else in the
annotated code yet.**

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

## Still open

* Whether joystick 1's own fire button (`JOY1_FIRE_BTN`, `$4D0B`) is read
  anywhere - it's written but no read site has been found yet in the
  annotated code (may be in one of the remaining undissected blocks, or
  genuinely unused).
* The exact demo-AI logic in `ATTRACT_AUTODRIVE` (what `OBJ_TBL69`/`OBJ_TBL71`
  and `SCROLL_SPEED` mean in that specific context).
