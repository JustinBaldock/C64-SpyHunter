# Spy Hunter - SPEEDCODE_IMAGE: the player-input-to-physics routine ($86F2-$8784)

Full decode of the block flagged as "a small 6502 routine kept here as data;
run from `$2800` RAM" - now converted to labelled instructions in
`spyhunter.asm`. Found while investigating a user hypothesis that
`SPEED_STEP_UP/DOWN` (`claude/Controls_And_Difficulty_Notes.md`) responds
directly to joystick up/down - it doesn't; this routine does.

## Why "run from $2800" doesn't complicate the disassembly

The ROM holds the master copy of this routine at a fixed cartridge address
(`$86F2`); at runtime it gets copied to RAM at `$2800` and executed from
there (for consistent cycle timing - the old `claude/Spy_Hunter_Analysis.md`
memory map already noted "`$2800-$2FFF` speed-critical routine copied into
RAM"). This doesn't affect annotating the ROM copy: 6502 absolute addressing
encodes a fixed 16-bit address regardless of where the executing code's PC
currently is, so the routine's own internal references (`SPEEDCODE_TBL`,
the call into `SPEED_SET`) still correctly point at their ROM addresses
whether the code is running from `$8000`-space or from `$2800`.

## The key finding: this is where JOY_STATE actually gets consumed

An exhaustive search of every absolute reference to `JOY_STATE` (`$4D09`) in
the assembled ROM found exactly one **read** (as opposed to the many
writes, from `READ_DUAL_JOYSTICK_INPUT` and `ATTRACT_AUTODRIVE`): here, at
`$8707`. `JOY_STATE+1` (steering) is read the same way further down. This
is the actual player-input-to-car-physics routine - not
`SPEED_STEP_UP/DOWN`, which is a shared low-level "step/snap `SCROLL_SPEED`"
primitive that this routine (among others) calls into.

## Speed half

```
lda FRAME_CTR
lsr                    ; carry = FRAME_CTR bit 0
bcc SPEED_ACCUM_ADJUST  ; even frame -> always skip the SBC below
ldy SCENE_ID
cpy #$05
beq SPEED_ACCUM_ADJUST  ; SCENE_ID=5 -> always take the SBC below
lsr                     ; odd frame, other scene -> throttle on FRAME_CTR bit 1
SPEED_ACCUM_ADJUST:
lda SPEED_ACCUM
bcc SPEED_ACCUM_CLAMP    ; (throttled out this frame)
sbc JOY_STATE            ; up (+1) decreases SPEED_ACCUM; down (-1) increases it
SPEED_ACCUM_CLAMP:
bmi SPEED_ACCUM_CLAMP2   ; negative -> keep as-is
lda #$00                 ; non-negative -> reset to exactly 0
SPEED_ACCUM_CLAMP2:
cmp #$F8
bpl SPEED_ACCUM_DONE
lda #$F8                 ; floor at -8
SPEED_ACCUM_DONE:
sta SPEED_ACCUM
clc
adc ROAD_X_REF
clc
adc SPEED_SUM
sta SPEED_SUM             ; running sum accumulates SPEED_ACCUM+ROAD_X_REF
lsr : lsr : lsr : lsr     ; /16
sec
sbc #$08                  ; re-centre
tax
bmi SPEED_SNAP_CHECK       ; out of [0,4] -> no snap this frame
cpx #$05
bcs SPEED_SNAP_CHECK
lda SPEEDCODE_TBL,x        ; {4,3,2,1,0} - REVERSED index
jsr SPEED_SET               ; snap SCROLL_SPEED/ROAD_X_REF directly
```

`SPEED_ACCUM` is a small accumulator that only ever holds 0 or a negative
value (0 to -8) - pressing "up" (`JOY_STATE`=+1) decreases it via `SBC`,
pressing "down" (`JOY_STATE`=-1=`$FF`) increases it back toward/through 0
(where it clamps). It feeds into `SPEED_SUM`, a longer-running accumulator
combined with `ROAD_X_REF`; once `SPEED_SUM` (divided by 16, re-centred)
falls in `[0,4]`, that's used as an index into a small **reversed** table
(`4,3,2,1,0`) to snap `SCROLL_SPEED` straight to a target value via the
newly-labelled third entry point into `SPEED_STEP`, `SPEED_SET` (`$A106`,
inside `disassembly/spyhunter.asm`'s existing `SPEED_STEP_DOWN`/`_UP`
routine - it skips the throttle/clamp logic and just stores directly).

This is a **low-pass-filtered "ease toward a target" mechanism**, not a
direct 1:1 joystick-to-speed mapping - confirming the user's instinct that
up/down drives speed, but the actual wiring is more indirect than a simple
"pressed up -> `INC SCROLL_SPEED`". Whether "up" nets out to *faster* or
*slower* isn't settled by this static trace alone (the accumulate/divide/
re-centre/reverse-table chain makes the net sign non-obvious) - would need
a live snapshot pair (`SCROLL_SPEED` immediately before/after a confirmed
up-press) to pin down.

## Steering half (mirror structure)

`STEER_GATE` onward repeats the same shape using `JOY_STATE+1` (steering
delta), `STEER_ACCUM`/`STEER_SUM` in place of `SPEED_ACCUM`/`SPEED_SUM` -
but instead of a table-snap, it toggles bit 6 of `SPR_XMSB` (the sprite-X
MSB shadow) when `STEER_SUM` overflows or goes negative. Reads as some kind
of scroll-direction or screen-half flip rather than literal sprite
repositioning, but not fully interpreted - flagged `(???)` in the source.

## New equates

`SPEED_ACCUM`/`SPEED_SUM` (`$B8`/`$D7`), `STEER_ACCUM`/`STEER_SUM`
(`$B0`/`$D6`), `SPEEDCODE_TBL` (`$86F2`), `SPEED_SET` (`$A106`, the new
third entry point added to the existing `SPEED_STEP` routine).

## Still open

* The precise game-feel meaning of "up"/"down" on final `SCROLL_SPEED` -
  needs live snapshot confirmation.
* The steering half's `SPR_XMSB` bit-6 toggle - what it actually controls.
* The exact throttling rule at the top (frame-parity + `SCENE_ID`/
  `ROAD_PHASE` gating) - structurally traced, not semantically confirmed.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` - the whole conversion (plus adding the
`SPEED_SET` label to the existing `SPEED_STEP` routine) is comment/label/
data-to-code only, no assembled bytes changed.
