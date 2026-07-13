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

## Not yet mapped: which `OBJ_TYPE` byte is which enemy

Across all snapshots analysed this session, these `OBJ_TYPE` values have been seen on non-hero,
non-empty object slots: `$05, $06, $0C, $0D, $0E, $13, $14, $16` - more distinct values than the
6 named enemies, so some are likely ordinary background traffic rather than one of the named
agents (the manual doesn't name a "generic car" but real Spy Hunter has ordinary non-hostile
traffic too). `$05` in particular appears very consistently across many otherwise-unremarkable
driving snapshots, which fits it being ordinary traffic rather than a named threat.

No snapshot has yet been captured at the exact moment of a confirmed miss against a *specific,
visually-identified* enemy, so none of these byte values can be confidently assigned to Road Lord/
Switch Blade/etc. yet. If a future snapshot is captured with the enemy on-screen clearly
identified (by appearance) at the moment of an interaction, that would pin one value definitively
and likely unlock the rest via elimination (weapon type, boat-vs-road behaviour, scoring on
destruction via `TALLY_SCORE_EVENTS`/`POINTS_TBL_LO`/`POINTS_TBL_HI` could also help - the 150/
500/500/700-point tiers are distinct enough to potentially cross-reference against
`disassembly/spyhunter.asm`'s scoring tables in a later session).

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
share entry 3, and Enforcer/Doctor Torpedo share entry 4. So whatever selects an index into this
table on enemy destruction must first map `OBJ_TYPE` (or similar) down to a tier (0-2), which is a
promising lead for the "which `OBJ_TYPE` is which enemy" problem above - `SCORE_EVENT` (`$4DC3`,
queued events consumed by `TALLY_SCORE_EVENTS`) is written somewhere outside
`TALLY_SCORE_EVENTS` itself (not yet located - likely in the collision/hit-detection code, not
yet annotated as of this session's Stage 4) with the OBJ_TYPE-to-tier mapping happening at that
write site.

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
