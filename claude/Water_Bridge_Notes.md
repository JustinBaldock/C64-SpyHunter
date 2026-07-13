# Spy Hunter - Water / bridge handling

From snapshot `spyhunterlevel1bridgestart.vsf` (car on the bridge over water). Score 7075,
timer 050. Still the CAR scene (`SCENE_ID $A8=$05`), `ROAD_SEG_IDX=$0C`, `ROAD_FEATURE=$01`.

## How the water is handled

The water is rendered as **map character tiles in the `$7800` play buffer** - the exact same
layer and mechanism as the road. It is NOT a sprite and NOT a separate graphics layer. It
simply replaces the grass margins of the road with water tiles.

Play-buffer layout on the bridge:
```
wwwwwww|||======      |||wwwwwww     (upper section, rows 0-18)
~~~~~~~~rr############rr::::::::     (lower section, rows 19-24)
```
* `w` water texture  = char codes **$08-$13** (a 12-tile patterned water surface)
* `~` solid water    = **$06** ; `:` shore/near water = **$07**
* `|` bridge rails    = **$30-$3F** ; `=` upper bridge deck = **$01** ; `#` lower deck = **$02**
* blank gap (cols 20-25) between the two carriageways = the bridge split

## Is the water part of the map?

**Yes.** The water tiles come from the road-segment template that the road IRQ copies into
the buffer each row (`SCROLL_SRC` -> `SCROLL_DST`, same as the road). So water is baked into
the level/segment graphics and scrolls with the road via the normal vertical scroll. This is
the opposite of the smoke weapon: smoke is *transiently* blitted into the buffer and scrolls
off; water is a *permanent* part of the segment map data.

## New information worked out

1. Water = MAP CHARACTER TILES in the `$7800` road buffer, drawn like the road (not a sprite,
   not a separate layer).
2. Water tile set: texture `$08-$13`, solid water `$06`, shore/near water `$07`.
3. Bridge structure tiles: rails `$30-$3F`, upper deck `$01`, lower deck `$02`; the two
   carriageways are separated by a blank gap (the bridge split you can fall through).
4. Water is PART OF THE MAP: sourced from the road-segment template (`SCROLL_SRC`), scrolls
   with the road, and is permanent segment data - contrast with transient smoke.
5. Water "animation": the texture repeats every ~5 rows (rows 0-4 = 5-9 = 10-14 = 15-18); as
   the map scrolls those patterned tiles cycle, giving the rippling-water effect for free
   (same trick as the road lane markers).
6. In-water structure tiles `$4E/$4F/$50/$51/$52/$53` (a 2x3 block, rows 22-24) = a bridge
   support / pylon rising from the water, also drawn as map tiles (not a sprite).
7. Per-segment split colours give the water its look: border/bg `$36=$0B`, mc1 `$37=$0F`,
   mc2 `$38=$01` (grey/white, moonlit water); set from the ROAD_BORDER/MC1/MC2 tables.
8. It is still the CAR scene on the bridge (`SCENE_ID=$05`), not a separate boat scene - the
   bridge-over-water is part of the level-1 road, selected by the road segment.
