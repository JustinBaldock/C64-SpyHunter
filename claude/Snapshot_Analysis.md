# Spy Hunter - VICE Snapshot Analysis (state identification)

Correlating live game state in VICE `.vsf` snapshots to memory, to confirm the labels in
`disassembly/spyhunter.asm`.

Tooling: `tools/vsf_extract.py <snap.vsf>` parses the snapshot, extracts the 64 KB RAM
image (from the `C64MEM` module) and prints score/timer/weapon/road state + the panel.

## IMPORTANT - extraction offset

The `C64MEM` module stores **4** leading bytes (`pport.data`, `pport.dir`, `exrom`, `game`)
before the 65536-byte RAM image, so RAM starts at `payload+4`. The first version of the
extractor skipped only 2 bytes, shifting every address up by 2. That produced spurious
"corrections" (score seemingly at `$04/$05`, timer at `$4D03/$4D04`). Those were wrong.
The offset is fixed and verified by the invariant `SPRITE_PTRS ($4D2B) == SPRPTR_7800
($7BF8)` (copied every frame in `COPY_SPRITE_REGS`), which only holds at `payload+4`.

## CONFIRMED addresses (disassembly labels were correct)

Verified across three snapshots with known on-screen values (score 125 / 1200 / 1950,
timer 970 / 888 / 746):

| State | Address | Encoding | Evidence |
|---|---|---|---|
| **Score** | `$E0`=lo, `$E1`=mid, `$E2`=hi | 3-byte little-endian BCD | 125=`25 01 00`, 1200=`00 12 00`, 1950=`50 19 00` |
| **High score** | `$02`=lo, `$03`=mid, `$04`=hi | BCD (mirrors score while setting session record) | same values |
| **Timer** | `$4D01`=lo, `$4D02`=hi | BCD, counts down | `09 70`, `08 88`, `07 46` |
| **Weapon** | `$4D1E` | enum (`$01` = machine guns) | `$01` in all three |
| Ammo guns/miss/smoke | `$F6`/`$F7`/`$F9` | count (all `00` = default guns) | - |

## Road / fork state (per snapshot)

| Snapshot | ROAD_SEG_IDX `$42` | SCENE_IDX `$4A` | ROAD_FEATURE `$44` | fork taken |
|---|---|---|---|---|
| start (125/970)  | `$01` | `$15` | `$11` | - |
| fork L (1200/888)| `$02` | `$0C` (< $13 -> main/even)  | `$0C` | left  |
| fork R (1950/746)| `$02` | `$1B` (>= $13 -> branch/odd) | `$12` | right |

**Fork selection:** `IRQ_BOTTOM_SCROLL` takes the branch (odd) next-segment when
`SCENE_IDX >= $13`. Snapshots confirm: left fork -> `SCENE_IDX < $13` (main path),
right fork -> `SCENE_IDX >= $13` (branch path). Full map graph in `Road_Map_Decode.md`.

## Snapshots on file

* Snap 1 `spyhunterstartlevel.vsf` - level 1 start, straight road. Score 125 (the chunky
  double-height `2` glyph reads like `7`, hence the initial "175" reading), timer 970.
* Snap 2 `spyhunterlevel1forkscore1200timer888.vsf` - level 1 fork, **left** branch.
* Snap 3 `spyhunterlevel1forkscore1950timer746.vsf` - level 1 fork, **right** branch.

## Panel rendering (reference)

Panel = two rows `PANEL_SCR0=$6798` / `PANEL_SCR1=$67C0`. Each digit is a double-height 2x2
block: digit N -> screen codes `$60+2N`/`$61+2N`; blank = `$40/$41`. Score at column 0
(bottom-left), timer at panel X=`$14` (centre), weapon/fuel icons on the right.
