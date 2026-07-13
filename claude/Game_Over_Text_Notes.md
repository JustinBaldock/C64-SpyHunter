# Spy Hunter - "GAME OVER" text on the road

Snapshot `spyhunterlevel1gameover.vsf` (game over; GAME_STATE=$01, LIVES=$FF,
SCROLL_SPEED=$34=$00 so the road is frozen). Score 9050.

## How the on-road text is displayed

The "GAME OVER" text is drawn by **DRAW_OBJECT_TILES** - the SAME character blitter the
game uses for the weapons van, the smoke plume and road hazards. It is NOT sprites and NOT
the status panel. The text is a blitted **map object**: font-character tiles written into
the `$7800` play screen buffer (and `$7C00`) over the halted road.

Evidence: the exact glyph sequence for "GAME" (`D8 D9 CC CD E4 E5 D4 D5`) exists in three
places - `$79A0` (play buffer $7800, row 10), `$7D78` ($7C00 buffer) and **`$A700` (ROM)** -
and the ROM copy sits inside the "effect graphics/params" data block right after a
`jsr DRAW_OBJECT_TILES : rts`, i.e. the same tile-pair library DRAW_OBJECT_TILES reads.

## The letters

Each letter is a **2-cell-wide pair of custom multicolour font glyphs** from the play charset
(`$7000`), rendered single height. Two lines are stacked: **GAME** on screen row 10, **OVER**
on row 11 (cols 16-23), over the road tiles.

Letter -> glyph-pair (charset $7000 codes):
`G=$D8/$D9  A=$CC/$CD  M=$E4/$E5  E=$D4/$D5  O=$E8/$E9  V=$F6/$F7  R=$EE/$EF`

The full font maps alphabetically: letter L -> ($CC+2L, $CD+2L), so A=$CC/$CD ... Z=$FE/$FF.

## Message table

The messages are stored in ROM as glyph-pair strings with `$00` word separators, at
`ONROAD_MSG_TBL = $A6E6` (in the effects/object tile region, same block as the smoke/hazard
tile sources). Decoded contents: `KEY / OR / JOY / OVER / GAME / ON / LEFT / DETOUR / OUT /
BRIDGE / AHEAD / ROADS / ICY`. "GAME" ($A700) is drawn on screen row 10 over "OVER" ($A6F8)
on row 11.

## Why it sits "on the road"

`SCROLL_SPEED=$00` freezes the road scroll on game over, so the blitted letters overwrite the
road character cells at rows 10-11 and stay put (they don't scroll away like smoke would while
driving). The text is written into both play buffers ($7800 and $7C00) so it survives the
raster-split buffer flip.

## New information (list)

1. On-road "GAME OVER" is drawn by DRAW_OBJECT_TILES - the shared van/smoke/hazard blitter -
   as a map object, not sprites and not the panel.
2. Letters are 2-cell multicolour font-glyph pairs from charset $7000, mapped alphabetically
   (A=$CC/$CD ... G=$D8/$D9 ... O=$E8/$E9 ... R=$EE/$EF ... Z=$FE/$FF).
3. Text is two stacked lines (GAME row 10, OVER row 11) blitted into $7800 and $7C00.
4. Messages live in a ROM glyph-pair table (ONROAD_MSG_TBL $A6E6, in the effects/object tile
   region), `$00`-separated: KEY/OR/JOY/OVER/GAME/ON/LEFT/DETOUR/OUT/BRIDGE/AHEAD/ROADS/ICY.
5. The road is frozen (SCROLL_SPEED=$00) so the text overlays the road and stays put.
6. This unifies the engine's on-playfield graphics: ONE blitter (DRAW_OBJECT_TILES) draws the
   van, smoke, hazards AND text messages.
7. Game-over state: GAME_STATE=$01, LIVES=$FF, timer already expired (EXTRA_LIFE_AVAIL=$FF).
