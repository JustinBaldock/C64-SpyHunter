# Spy Hunter - Weapons Truck (van) state + sprite

From snapshot `spyhunterlevel1score6000timer336inweapontruck.vsf` (player inside the
weapons van), diffed against normal driving. Score 6000 (`$E0-$E2`), timer 336
(`$4D01/$4D02`) - both confirmed. Addresses per `spyhunter.asm`.

## The van is object slot 1 (the "hero" slot)

The player/hero is moving-object **slot 1**. Its type byte doubles as `HERO_STATE`:

| Var | Addr | Normal | In-truck | Meaning |
|---|---|---|---|---|
| `HERO_STATE` (OBJ_TYPE[1]) | `$A3` | `$FF` | **`$03`** | hero object type = weapons-van state |
| hero sub-state | `$A0` | `$00` | `$04` | van-sequence step/counter |
| `SCENE_ID` (OBJ_TYPE[6]) | `$A8` | `$05` | `$FF` | scene-object slot cleared during van |
| `OBJ_ANIM[1]` | `$9B` | `$00` | `$03` | van animation frame |
| `OBJ_TBLB3[1]` | `$4DB4` | `$16` | `$1D` | van screen column |
| `OBJ_TBLBB[1]` | `$4DBC` | `$00` | `$05` | van screen row |
| `OBJ_TBL63[1]` | `$4D64` | `$00` | `$04` | per-slot state |
| `OBJ_TBL6B[1]` | `$4D6C` | `$00` | `$08` | per-slot state |
| `OBJ_TBL73[1]` | `$4D74` | `$00` | `$03` | per-slot state |

## The sequence freezes the road + timer

| Var | Addr | Normal | In-truck | Effect |
|---|---|---|---|---|
| `SCROLL_SPEED` | `$34` | `$03` | **`$00`** | road scroll stopped |
| `TIMER_ENABLE` | `$E3` | `$02` | **`$00`** | game timer frozen (336 held) |

So while you're in the van the playfield stops scrolling and the countdown pauses.
`WEAPON_STATE $4D1E` is still `$01` (machine guns) here - the new weapon is granted on
*exit*, not while inside.

## Sprite details

The van is drawn as **hardware sprite 1** (multicolour):

* Sprite pointer (shadow `SPRITE_PTRS $4D2B+1`, copied to `$7BF9`): **`$5E`** ->
  graphics at **`$4000 + $5E*64 = $5780`**.
* Position (shadow, copied to `$D000-$D010`): sprite 1 X = `$CC` = **`$FC` (252)**,
  Y = `$CD` = **`$56` (86)** (`$CD` is also `SPAWN_Y`); MSB `$DA` = 0. All other sprites
  point to the blank cell `$95` ($6540) and sit at 0,0.
* Shared sprite multicolours (from `INIT_PLAY_STATE`): `VIC_SPRMC0 $D025 = $0E`,
  `VIC_SPRMC1 $D026 = $01`.
* Staged multiplex coords for slot 1 sit in the `SPR_STAGE $BA` / `$CA-$D9` shadow.

Decoded `$5780` sprite (12px multicolour x ~16 rows) is the van seen from above -
a cab block up top and a rectangular cargo body with side detailing:

```
 +oooo+        cab / windscreen
 oooooo
 o++++o
 +oooo+
 +o++o+
########       body roof
oooooooo
o#oooo#o
o######o
o##++##o       cargo detailing
o#+##+#o
o#++++#o
o##++##o
o######o
o#oooo#o
oooooooo
```

## Handler entry points (ROM, for follow-up)

Hero/van object type `$03` dispatches through `OBJMOVE_VEC_LO/HI` (`$8B2F`) entry [3]
and `OBJINIT_PARAM_TBL` (`$8B3F`) entry [3]; the van graphics/transition also run through
`UPDATE_WEAPONS` / `DRAW_OBJECT_TILES`. Not yet fully traced.
