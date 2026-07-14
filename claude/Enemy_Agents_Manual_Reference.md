# Spy Hunter - Enemy Agents & scoring (from the official manual)

Source: `original_files/Spy_Hunter_1984_Sega_text.pdf` (extracted via `pypdf`; OCR is imperfect in
places, cleaned up below). This is primary-source game-design documentation, not derived from the
disassembly - useful as ground truth to check ROM findings against.

## The six Enemy Agents

> The Spy Car faces various Enemy Agents along the course. Each Enemy Agent, except the Road
> Lord, has its own unique weaponry.

| Enemy | Weapon / behaviour | Points |
|---|---|---|
| **The Road Lord** | **Bulletproof.** Must be rammed off the road by the Spy Car - it has no weapon of its own. | 150 |
| **Switch Blade** | Extends buzz-saw hubcaps to slash cars | 150 |
| **The Enforcer** | Fires a shotgun | 500 |
| **The Copter** (Mad Bomber) | Drops bombs onto the Spy Car | 700 |
| **Barrel Dumper** | A boat - dumps barrels in the water ahead of the Spy Boat | 150 |
| **Doctor Torpedo** | A boat - fires torpedoes at the Spy Boat | 500 |

Two of the six (Barrel Dumper, Doctor Torpedo) are explicitly boats, only encountered on the
water section - consistent with the boat-mode object flag documented in
`claude/Boat_River_Notes.md` (`OBJ_TBL63/6B/73 = $02` on NPC slots during the water/boat scenes).

General rules from the manual: "You can also use your Spy Car to destroy some enemy agents by
ramming them off the road for points" (implying ramming works on more than just the Road Lord,
just that it's the ONLY option for the Road Lord specifically, since it has no weapon to disable
and can't be shot). Running off the road or into a screen boundary costs a Spy Car, same as
colliding with an enemy.

## This resolves (or strongly reframes) the open enemy-unshootable question

`claude/Enemy_Invincibility_Notes.md` documented an inconclusive finding from a single snapshot
(`enemy-unshootable.vsf`, captured on the bridge): an enemy failed to register a hit, and the only
byte-level anomaly found was the hero's own `HERO_STATE=$11` (unique among all captured
snapshots). The manual now gives a much simpler, high-confidence explanation: **the Road Lord is
bulletproof by design** - shooting it is *supposed* to do nothing, every time, regardless of any
hero state. It isn't a bug, a transient condition, or something tied to the bridge specifically.

This also suggests a revised reading of `HERO_STATE=$11`: rather than being *the cause* of the
missed hit, it may be a side effect of the player repeatedly attempting to **ram** the Road Lord
(the only way to defeat it) - i.e. a collision/ramming sub-state, captured mid-attempt in that
snapshot, rather than anything shooting-related. Still not proven from one snapshot, but far more
plausible than the earlier guesses.

## `OBJ_TYPE` byte mapping - partial progress

A later batch of user-named snapshots (`helicopter-enemy.vsf`, `text-bridgeout.vsf`,
`respawn-boat.vsf`, `level-ice.vsf`, `water-ice-area.vsf`, etc.) made real progress here, mainly
by spotting a **locomotion-class flag** distinct from the boat-mode flag already documented
(`OBJ_TBL63/6B/73` all `$02`): a slot with all three of `OBJ_TBL63/6B/73 = $FF` (not `$00`, not
`$02`) shows up specifically paired with `OBJ_TYPE=$08`:

| `OBJ_TYPE` | Evidence | Candidate |
|---|---|---|
| **`$08`** | `TBL63/6B/73 = $FF/$FF/$FF` (an "airborne" locomotion flag, distinct from both ordinary `$00/$00/$00` and boat `$02/$02/$02`) in BOTH `helicopter-enemy.vsf` and `text-bridgeout.vsf` - two independent snapshots, same unusual signature | **The Copter (Mad Bomber)** - the only aerial enemy, so a dedicated locomotion-class flag distinguishing it from ground/water traffic makes sense |
| **`$07`** | In `helicopter-enemy.vsf`, slot 1 sits immediately next to the `$08`/airborne slot 0 (screen position one row apart, same column) | Candidate: a bomb the Copter just dropped, given the manual's "drops bombs onto the Spy Car" - not confirmed, could instead be an ordinary nearby vehicle |
| **`$13`** | Appears **three times simultaneously** in `water-ice-area.vsf` (slots 2/4/5, all boat-flagged) plus repeatedly elsewhere (`water-enemyboat`, `exit-water`/dock) | A boat enemy type that can spawn multiple instances at once - candidate Barrel Dumper or Doctor Torpedo (not yet distinguished from each other) |
| **`$18`, `$19`** | New, adjacent, both boat-flagged, only in `respawn-boat.vsf` (slots 0/1, right next to each other on screen) | Candidate: a two-part hero-boat respawn animation (splash + boat), by analogy with the weapons van's dedicated `$03` state - since the filename implies this is the PLAYER's boat reappearing, not a new enemy |
| `$05, $06, $0C, $0D, $0E, $14, $16` | Seen across many otherwise-unremarkable driving snapshots | Still most consistent with ordinary background traffic rather than named agents - `$05` especially, given how often it recurs |

None of this is definitive - it's correlation across a handful of snapshots, not a traced
collision-handler read.

**Update - resolved via the collision-handler code directly (`claude/Enemy_Scoring_Notes.md`):**
`SCORE_EVENT`'s queue-write site has now been located and fully traced (tasks #32/#33). Each
enemy `OBJ_TYPE`'s own `MOVE_TYPE_*` handler hardcodes which `POINTS_TBL` kill tier it awards,
giving a much stronger, code-level identification:

| `OBJ_TYPE` | Kill tier | Identity | Confidence |
|---|---|---|---|
| `$07` | 700 (tier 5, alone) | **The Copter (Mad Bomber)** | High |
| `$13` | 150 (tier 3) + confirmed boat | **Barrel Dumper** | High |
| `$0C` | 150 (tier 3), multi-frame scoring | **The Road Lord** | Moderate |
| `$0D` | 150 (tier 3), single-hit scoring | **Switch Blade** | Moderate |
| `$09` | 500 (tier 4) | **The Enforcer** (possibly shared with Doctor Torpedo) | Moderate |
| `$11` | n/a - excluded from bullet hits | Not an enemy - the hero's own default `HERO_STATE` | Moderate |
| `$08` | not traced to a score tier | Still just the airborne-locomotion correlation below - not confirmed against the scoring path | Low (superseded lead: see `$07` above for the Copter) |

Full reasoning, including why `$0C`/`$0D` split the way they do and the open Doctor Torpedo
question, is in `claude/Enemy_Scoring_Notes.md`. This mostly supersedes the locomotion-flag
correlation below, EXCEPT that it re-opens what `$08` actually is, since `$07` (not `$08`) is now
the code-confirmed Copter - `$08`'s "airborne" flag evidence still stands on its own (see next
section) and the two may simply be closely-related (e.g. the Copter's body vs. a paired
hit-registration sub-object), not necessarily the same identification.

## Scoring (complete, from the manual)

| Source | Points |
|---|---|
| Travelling on the road | 25 points per 1/4 screen of distance |
| Travelling on the water | 15 points per 1/4 screen of distance |
| Destroy: Road Lord | 150 |
| Destroy: Switch Blade | 150 |
| Destroy: Barrel Dumper | 150 |
| Destroy: The Enforcer | 500 |
| Destroy: Doctor Torpedo | 500 |
| Destroy: The Copter (Mad Bomber) | 700 |
| Enter or exit the boathouse (land<->water transition, either direction) | 1500 |

So scoring isn't just kills - simply driving accrues points continuously, at a HIGHER rate on
the road (25/quarter-screen) than on water (15/quarter-screen).

**Confirmed directly in the ROM.** `POINTS_TBL_LO`/`POINTS_TBL_HI` (`$A89D`/`$A89E`, an
interleaved lo/hi BCD-pair array read by `ADD_SCORE`, `disassembly/spyhunter.asm`) decodes to
**exactly** the manual's numbers, with nothing left over to explain:

| index (`y=2*n`) | BCD value | Matches |
|---|---|---|
| 0 | 0 | (unused/no-op entry) |
| 1 | **15** | water travel rate |
| 2 | **25** | road travel rate |
| 3 | **150** | Road Lord / Switch Blade / Barrel Dumper (all 150 pts) |
| 4 | **500** | The Enforcer / Doctor Torpedo (both 500 pts) |
| 5 | **700** | The Copter (Mad Bomber) |
| 6 | **1500** | boathouse land<->water transition |

(index 7 onward reads into unrelated adjacent code/data - the table is 7 entries, indices 0-6.)

Every one of the manual's numbers is accounted for by exactly one table entry - a full, confirmed
match, not just a plausible guess. This also reveals the table's real structure: it's **3 kill
tiers** (150/500/700), not 6 individual per-enemy entries - Road Lord/Switch Blade/Barrel Dumper
share entry 3, and Enforcer/Doctor Torpedo share entry 4.

**Update - the `OBJ_TYPE`-to-tier mapping is now traced (`claude/Enemy_Scoring_Notes.md`).**
`SCORE_EVENT`'s write site is `ARM_SCORE_EVENT`/`ARM_SCORE_EVENT_X8` in the collision-detection
block; there's no lookup table - each enemy `OBJ_TYPE`'s own `MOVE_TYPE_*` handler hardcodes its
tier index as a literal constant before calling it. See the table above and
`claude/Enemy_Scoring_Notes.md` for the full per-type breakdown.

## Other manual details worth keeping

* Terrain sequence: road -> boathouse (car becomes amphibious) -> water -> more road, with a
  bridge stretch and an "Icy Road" stretch elsewhere ("the surface is slippery and your car is
  harder to control") - matches `ICY` appearing in `ONROAD_MSG_TBL` (`claude/Game_Over_Text_Notes.md`
  / the `spyhunter.asm` header's on-road-text notes).
* Weapons are granted by "docking" with the Weapons Van (matches `claude/Weapons_Truck_Notes.md`).
* Two difficulty modes: Novice (999-unit counter, unlimited Spy Cars during it, then 1 extra life
  at completion, +1 every 10,000 points after an initial 20,000) vs Expert (same 999 counter,
  harder/more aggressive enemies, 1 Spy Car after the counter runs down, +1 every 20,000 points).
  This may explain some of the still-unidentified difficulty/scene-select state variables
  (`SEQ_STATE`, `SCENE_IDX` thresholds) noted elsewhere in the disassembly.
