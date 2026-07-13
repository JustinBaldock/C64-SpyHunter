# Spy Hunter - Collision detection (partial manual disassembly)

Starting point: two VICE snapshots' captured program counter (see the discussion in this
session) landed inside the previously-undissected "per-object-type move/draw handler" and
"weapon/collision handler" blocks flagged in `spyhunter.asm`'s Stage 5/9 annotation passes:
`become-boat.vsf` at `$992C`, `weapon-oil-used.vsf` at `$9820`. Both addresses were disassembled
by hand using a small purpose-built disassembler (`tools/disasm6502.py`, verified against the
already-annotated `WAIT_FRAME_TIMER` before trusting it on new code).

## Method: cross-referencing `OBJINIT_PARAM_TBL`

Before disassembling blind, the full `OBJINIT_PARAM_TBL` move/draw vector table (`$8B3F`,
4 bytes/entry) was extracted for every type index `$00-$1F`:

```
type  move   draw          type  move   draw          type  move   draw
$00  $9A8E  $90AA         $0B  $9B88  $94FB         $16  $8B2E  $96EC
$01  $9A8E  $90AA         $0C  $9AC5  $9549         $17  $8B2E  $9624
$02  $9A8E  $90AA         $0D  $9AB3  $9549         $18  $9AA1  $971E
$03  $9A8E  $90AA         $0E  $9AA8  $956D         $19  $8B2E  $976B
$04  $8B2E  $924D         $0F  $9AA8  $956D         $1A  $9B2F  $97A8
$05  $99F1  $92AA         $10  $9AA8  $956D         $1B  $9B62  $94FF
$06  $99F1  $93A2         $11  $9B02  $95BE
$07  $9A80  $8F38         $12  $9AB6  $95EB
$08  $8B2E  $9027         $13  $9AB9  $95EB
$09  $9AB0  $9448         $14  $8B2E  $9624
$0A  $9B34  $9478         $15  $8B2E  $966F
```
(entries stop being plausible past `$1B` - the table is 28 entries, `$00-$1B`.)

`$992C` falls between the `$99F1` (types 5/6 move) and `$9A80` (type 7 move) vectors - i.e.
inside **type 5/6's shared MOVE routine**. This lines up perfectly: types `$05`/`$06` are exactly
the two "boat-mode" types already confirmed in `claude/Boat_River_Notes.md`, and `become-boat.vsf`
had a live boat object in slot 6 (`TYPE=$06`) at the moment of capture.

## Type 5/6 move handler (`$99F1`-`$9A8D`): the boat, including crash handling

```
$99F1  lda STATE_4D05        ; a per-boat "special sequence in progress" flag
       beq +continue
       lda STATE_4DB9        ; blit-column-ish state var (also used by UPDATE_WEAPONS)
       cmp #$04 : bcc +skip  ; only proceed if STATE_4DB9 is in [$04,$22] - an
       cmp #$23 : bcs +skip  ;   on-screen column range
       lda #$00 : sta STATE_4D89 : rts   ; still mid-sequence and on-screen -> wait
+skip: rts
+continue:
       lda #$00 : sta STATE_4DCB : sta STATE_4D05   ; reset both flags
       lda OBJ_TBL79                  ; NOTE: read directly, not ,x-indexed
       bmi ->crash_handler
       cmp #$09 : beq ->rts
       lda STATE_4D89 : bne ->crash_handler
       jsr HAZARD_CHECK_0A  : beq ->crash_handler
       jsr HAZARD_CHECK_0C  : beq ->continue2
       jsr HAZARD_CHECK_0B  : beq ->continue2
       jsr HAZARD_CHECK_CHAIN : beq ->crash_handler
       jsr HAZARD_CHECK_07  : bne ->continue2
       jsr $A7C1
->continue2:
       jmp $9C5A
->crash_handler:
       ldx #$00
       stx GUN_HEAT : stx MISSILE_CNT : stx SMOKE_CNT   ; clear all ammo
       ldx EXTRA_LIFE_AVAIL
       beq +life_ok
       dec LIVES                      ; <-- CONFIRMED: crashing costs a life
+life_ok:
       inc STATE_4DCB
       lda #$02 : sta STATE_4D05      ; arm the "crash sequence" flag
       ... (SEQ_STATE bookkeeping, then jsr SOUND_SILENCE : jmp $AA8A)
$9A80  lda STATE_4D83,x
       beq $9A8D
       jsr SOUND_SILENCE
       ldx #$05 : jmp $9BC0
$9A8D  rts
```

**This directly and definitively answers the open question from `claude/Boat_River_Notes.md`:
crashing into a water hazard DOES cost a life** (`dec LIVES`, gated only on whether the timer has
already expired via `EXTRA_LIFE_AVAIL`/`$4D12`) - confirmed by reading the actual code, not
inferred from snapshot correlation.

## The hazard-check primitive (`$9D60`-`$9DB9`)

A shared comparison routine, entered at several different offsets that each preload a different
target byte into A before falling into the common tail - the same "multiple entry points into
overlapping code" trick already seen elsewhere in this file (e.g. `DEC_TIMER1`/`2`/`3` in
`UPDATE_HAZARDS`), and confirmed by disassembling from each JSR target independently:

```
HAZARD_CHECK_0C: lda #$0C  \
HAZARD_CHECK_0B: lda #$0B   } all fall into the shared check below
HAZARD_CHECK_0A: lda #$0A  /
HAZARD_CHECK_COMMON:
    cmp OBJ_TBL63,x : beq ->hit
    cmp OBJ_TBL6B,x : beq ->hit
    cmp OBJ_TBL73,x           ; Z flag from THIS compare is the real return value
->hit: rts                    ; Z=1 if A matched any of the three, Z=0 otherwise

HAZARD_CHECK_07: lda #$07 : cmp OBJ_TBL73,x : rts   ; simpler single-slot variant

HAZARD_CHECK_CHAIN:
    lda OBJ_TBL7B,x : jsr HAZARD_CHECK_COMMON : beq ->miss
    cmp #$00 : bne +next
    lda #$04 : jsr HAZARD_CHECK_COMMON : beq ->miss
+next:
    lda #$06 : jsr HAZARD_CHECK_COMMON : beq ->miss
    lda #$07 : jsr HAZARD_CHECK_COMMON : beq ->miss
    lda #$03 : jsr HAZARD_CHECK_COMMON : beq ->no_match
    lda #$05 : jsr HAZARD_CHECK_COMMON : beq ->miss
    lda #$02 : jsr HAZARD_CHECK_COMMON : beq ->miss
->no_match: lda #$00 : rts
->miss:     lda #$01 : rts
```

`OBJ_TBL63/6B/73,x` here are read as plain per-slot bytes - the same three arrays
`OBJ_CALC_SCREEN_POS` (Stage 5) populates with a **tile-distance-bucket classification** of
whatever's underneath/near the object each frame. So this whole primitive is: "is one of the
nearby classified tiles one of these specific hazard codes (`$02,$03,$05,$06,$07,$0A,$0B,$0C`,
plus a per-slot value from `OBJ_TBL7B`)?" - i.e. **environmental hazard detection via tile
classification**, distinct from the sprite-based collision mechanism below. Not confirmed:
exactly which physical hazard (barrel? rock? shoreline?) each numeric code represents - that
would need a snapshot with a specific hazard tile visible near the boat at the moment of a
captured crash.

## A second, separate collision mechanism: sprite-proximity checking (`~$97F3`+)

The `weapon-oil-used.vsf` PC (`$9820`) landed in a different area entirely - a routine (starting
cleanly around `$97F3`, right after an `RTS`) that reads `SPR_STAGE,y` (the clamped X/Y delta
array `OBJ_CALC_SPRITE_DELTA`, Stage 5, computes between this object and every hardware sprite)
and compares the rotated/shifted values against thresholds (`$15`, `$23`) reminiscent of
`OBJ_CALC_SPRITE_DELTA`'s clamp ranges. This looks like **sprite-to-sprite proximity/collision
checking** - a second, complementary mechanism to the tile-hazard check above, likely used for
object-vs-object hits (weapon-vs-enemy, car-vs-enemy) rather than object-vs-terrain. Not fully
traced - this is a genuinely large routine and only the entry/threshold-check portion was read in
this pass.

## Full decode of the `$99E3`-`$9DB9` block (session 2)

The entire "weapon/collision handler" block flagged after `SET_SPRITE_PTR` has now been converted
from raw `.byte` data to fully labelled, real 6502 instructions in `spyhunter.asm` (mechanically
generated from a verified straight-line disassembly of the ROM, then byte-diffed against the
original ROM bytes before being applied - see the tooling note below). It turned out to contain
MOVE handlers for **every remaining unassigned `OBJINIT_PARAM_TBL` type** (`$09`, `$0A`, `$0B`,
`$0C`, `$0D`, `$12`, `$13`, `$18`, `$1A`, `$1B`, plus types `$00`-`$03`'s shared handler), not just
the boat (`$05`/`$06`) and type `$07` traced in session 1. Key findings:

* **`CONSUME_HIT_MASK_BIT`/`CONSUME_HIT_MASK_A`/`HIT_RESOLVE_*` (`$9BDE`-`$9D5F`) is the
  sprite-to-sprite proximity/collision check** that consumes `HIT_MASK_A`/`HIT_MASK_B` (built by
  `PROCESS_OBJECTS`, Stage 5): for a slot paired against every other slot, it compares the clamped
  sprite-distance values (`SPR_STAGE`/`SPR_STAGE+1,x`, from `OBJ_CALC_SPRITE_DELTA`) against
  per-slot thresholds and folds a hit bit into the mask. On an actual hit it arms
  `STATE_4DCA` (a short effect countdown) for specific type pairs (`$10`, `$0D`, `$0C`), pairs up
  the two slots' `STATE_4D83`, and swaps/nudges their `OBJ_POS_X`/`OBJ_POS_Y` and
  `SPR_X_SHADOW`/`SPR_Y_SHADOW`-family counters. This is very likely the actual weapon-vs-enemy
  and car-vs-enemy hit resolution, though which specific effect corresponds to "enemy destroyed"
  vs. "just bumped" is still not nailed down.
* **This is a *different* mechanism from the tile-hazard chain** (`HAZARD_CHECK_*`) used by the
  boat and several other MOVE handlers - confirming the "two distinct collision subsystems" finding
  below still holds, and both are now fully readable code rather than partly-guessed.
* Many of the new handlers converge on `ARM_SCORE_EVENT`/`ARM_SCORE_EVENT_X8` (`$9BC0`/`$9BBE`),
  confirming `SCORE_EVENT` (`$4DC3`) is queued from multiple different type-specific code paths,
  not just one.
* Several more multi-entry-point overlaps (the same "BIT-absolute as skip" trick as
  `HAZARD_CHECK_0C/0B/0A`) were found and kept as raw bytes with labels at each entry: one shared
  between the boat's post-crash sequence-arming code, one shared between types `$0D`/`$12`/`$13`,
  one shared between types `$0A`/`$1A`, and one inside `CONSUME_HIT_MASK_BIT` itself (a
  carry-select trick, not a real `BIT` test).
* Tooling note: given how dense and overlap-heavy this block is, the final instruction stream was
  generated mechanically from a verified straight-line disassembly (address -> mnemonic/operand,
  with a small hand-maintained label/equate lookup table) rather than transcribed by hand, and the
  assembled output was byte-diffed against the original ROM bytes before being applied to
  `spyhunter.asm` - catching several transcription mistakes an earlier hand-written draft had
  introduced (e.g. `HIT_MASK_A` vs. `HIT_MASK_B`, and which exact jump targets several `jmp`/`jsr`
  instructions used).

## What this does and doesn't resolve

* **Resolved:** crashing into a water hazard costs a life (direct code confirmation).
* **Resolved:** there are (at least) two distinct collision subsystems - tile-classification-based
  (environmental hazards, `HAZARD_CHECK_*`) and sprite-delta-based (object-vs-object,
  `CONSUME_HIT_MASK_*`/`HIT_RESOLVE_*`) - rather than one unified check. Both are now fully decoded
  as real instructions in `spyhunter.asm`.
* **Resolved:** `SCORE_EVENT` is queued from `ARM_SCORE_EVENT`/`ARM_SCORE_EVENT_X8`, reached from
  multiple type-specific MOVE handlers on a hazard miss/hit.
* **Still open:** which specific `OBJ_TYPE` is the Road Lord, and the precise mapping from a
  `HIT_RESOLVE_*` effect to a `POINTS_TBL` tier (`claude/Enemy_Agents_Manual_Reference.md`). The
  sprite-proximity routine at `~$97F3`+ (in the separate, still-undissected DRAW-dispatch data
  before `SET_SPRITE_PTR`) remains the most promising remaining place to look for object-vs-object
  hit detection that feeds scoring specifically.
* Several zero-page/state bytes used heavily in this block are still only tentatively named
  (`OBJ_POS_X`/`OBJ_POS_Y` at `$AA`/`$B2`, `STATE_9B`, `STATE_4D83`/`STATE_4D84`) - flagged with
  "(???)" in `spyhunter.asm` pending further snapshot correlation.
