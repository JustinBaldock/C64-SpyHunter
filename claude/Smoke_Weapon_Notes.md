# Spy Hunter - Smoke weapon handling

From snapshot `spyhunterlevel1score6575timer260smokedropped.vsf` (actively dropping smoke),
diffed against the smoke-equipped-but-unfired snapshot. Score 6575 / timer 260 confirmed.

## Key finding: smoke is drawn into the road MAP buffer, not as a sprite

When smoke is dropped, `UPDATE_WEAPONS` calls `DRAW_OBJECT_TILES` (the same character
blitter used for the road objects and the weapons van) to stamp smoke **character tiles
directly into the `$7800` play-screen buffer** (`SCREEN_PTR = $7Axx`). It is NOT a hardware
sprite. This is why smoke can be an arbitrary expanding cloud (sprites are limited to 8).

* Smoke tile codes: `$AD` (left), `$10` (core), `$AE` (right, mirror of `$AD`), with edge
  variants `$B0/$B2/$AF/$B1/$B3/$B4/$B5/$B6`.
* Tile source: a triple-table in ROM at `~$A538-$A567` (`STREAM_PTR = $A550` in this frame):
  `AD 10 AE / AD 10 B0 / AD 10 B2 / AF 10 AE / B1 10 AE / B3 01 B4 ...`.
* Colour: `OBJ_COLOR = $09` (brown), written to colour RAM at the smoke cells.
* Blit position: `BLIT_COL` from `STATE_4DB9` ($4DB9), `BLIT_ROW` from `STATE_4DC1`+2
  ($4DC1) - i.e. just behind the car. `BLIT_WIDTH=$08`.

## The expanding plume

`DRAW_OBJECT_TILES`' spread logic (driven by `BLIT_FLAGS`) widens the cloud each row:
observed 3 -> 5 -> 7 -> 9 tiles wide over successive rows (rows 18-24 in the buffer),
producing the triangular smoke plume trailing the car.

## How it scrolls

The smoke has **no scroll code of its own**. Because it is written into the `$7800`
scrolling road buffer, it is carried upward by the same vertical scroll as the road: the
VIC fine-scroll (`VSCROLL_POS $3E` -> D011 Y-scroll, `SCROLL_SPEED $34=$04`) plus the IRQ's
per-row block copy. New smoke tiles are stamped at the car's rear each frame; older rows
scroll up and off the top.

## Does it become part of the map?

Partly. It becomes part of the **live on-screen character map** (the scrolling play buffer),
so it moves with the road and can be driven over. But `DRAW_OBJECT_TILES` writes only to the
screen buffer (`SCREEN_PTR`) + colour RAM - **not** to the ROM level/segment tables or the
road template (`SCROLL_SRC` source). So the smoke is transient: it scrolls off the top and is
overwritten as the buffer recycles; it never alters the permanent level definition.

## Weapon charge byte

The active dropped-weapon charge is `$F7`: `$FF` (full, on pickup) -> `$EC` here, i.e. it
**decrements as the smoke is used**. This refines the disassembly's `(???)` guesses for the
`$F6-$F9` ammo counters: the weapon the player calls "smoke" is tracked by `$F7`.
`WEAPON_STATE $4D1E` stays `$01` (machine guns) throughout - the special weapon is
independent of `$4D1E`, tracked by the ammo counter and fired via `UPDATE_WEAPONS`.
