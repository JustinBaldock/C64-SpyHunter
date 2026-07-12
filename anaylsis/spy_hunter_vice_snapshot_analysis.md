# Spy Hunter — VICE Snapshot Analysis (state identification)
 
Working notes for correlating live game state in VICE `.vsf` snapshots to memory
addresses, to confirm/refine the labels in `disassembly/spyhunter.asm`.
 
Tooling: `tools/vsf_extract.py <snap.vsf>` parses the snapshot, extracts the 64 KB
RAM image (from the `C64MEM` module), and prints the score/timer/weapon state plus
the rendered status panel. RAM extraction is validated by the CPU port bytes it
recovers (`$01=$05`, `$00=$2F` — exactly the game's runtime banking config).
 
## How the status panel is drawn (from the disassembly)
 
* Panel lives in two adjacent screen rows: `PANEL_SCR0 = $6798`, `PANEL_SCR1 = $67C0`
  (rows 23–24 of the `$6400` buffer). Each digit is a **double-height 2×2 block**:
  `PANEL_PUT_DIGIT` computes char code `$60 + 2·N` (and `+1` for the right half) and
  writes the same pair to *both* rows. So digit N → screen codes `$60+2N`/`$61+2N`
  (0→`$60/$61`, 1→`$62/$63`, … 9→`$72/$73`). Blank cell = `$40/$41`.
* `DRAW_SCORE` renders 3 BCD bytes (6 digits, leading zeros suppressed) starting at
  panel column 0 (**bottom-left**).
* Timer is drawn by the `LA955` entry from `$4D01/$4D02` at panel X=`$14` (col 20,
  **centre**).
* `DRAW_STATUS_PANEL` draws the weapon/fuel indicator icons on the **right** from
  `PANEL_ICON_TBL = $80,$82,$84,$86`, gated on the ammo counters `GUN_HEAT $F6`,
  `MISSILE_CNT $F7`, `SMOKE_CNT $F9`.
## Candidate state addresses (labels from disassembly)
 
| Meaning | Address | Encoding |
|---|---|---|
| Score | `$E0`/`$E1`/`$E2` (+ovfl `$DC`) | BCD, lo→hi |
| Alt score buffer (direct `DRAW_SCORE`) | `$02`/`$03`/`$04` | BCD |
| Game timer | `$4D01`/`$4D02` (enable `$E3`) | BCD |
| Weapon state | `$4D1E` | enum |
| Ammo: guns / missiles / smoke | `$F6` / `$F7` / `$F9` | count |
| Lives | `$4D15` | — |
| Game state | `$4D13` | — |
| Sprite-ptr shadow | `$4D2B` | 8 bytes |
 
## Snapshot 1 — `spyhunterstartlevel.vsf` (shortly after start)
 
User-reported on screen: **score 175** (bottom-left), a timer (centre), weapon =
**machine guns** (bottom-right icon).
 
Extracted values:
 
* Rendered panel `$6798/$67C0`: left group **`125`**, centre group **`970`**, weapon
  icon chars `$84/$85` on the right.
* `$E0–$E2` (labelled SCORE) = `25 40 40` → **254040** — does **not** match panel.
* `$02–$04` = `25 43 37` → 254337 — no match either.
* `$4D01/$4D02` (labelled TIMER) = `01 04` → **0104** — does **not** match centre `970`.
* `$4D1E` (WEAPON) = `05`; ammo `$F6=$F7=$F9=00` → consistent with **default machine
  guns, no special-weapon ammo**. ✅ (highest-confidence identification)
* `$4D15` LIVES = `01`; `$4D13` GAME_STATE = `02`.
* Active play screen = `$7800` (scrolling road). Player car = hardware sprite #4,
  data at `$5E00` (play sprite pointers `$7BF8`: `00 00 95 95 78 95 95 95`).
### Open discrepancy (needs a 2nd snapshot to resolve)
 
The **rendered panel** (`125`/`970`) and the **labelled score/timer variables**
(`254040`/`0104`) disagree, and neither equals the reported `175`. Likely one of:
(a) the `$6400` panel buffer is stale/attract content and the live gameplay panel is
sourced elsewhere at the raster split; or (b) `$E0–$E2` is actually the *high* score
and the current score sits in a different buffer. A diff of two snapshots taken at
different scores/timers will pin the exact live bytes unambiguously.
 
## Next-snapshot recipe (to lock addresses by diffing)
 
1. **Score**: let it tick up, then snapshot — the score bytes are guaranteed to differ.
2. **Weapon**: drive over a weapons van and pick up a different weapon (oil slick /
   smoke / missiles), then snapshot — diff reveals the weapon + ammo bytes.
3. **Timer**: snapshot a few seconds apart — the BCD timer bytes will have counted.
Keep other conditions as similar as possible between paired snapshots so the diff is
clean. `vsf_extract.py` writes `ram.bin`; diff two with `cmp -l a.bin b.bin`.