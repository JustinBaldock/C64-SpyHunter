# Spy Hunter - "enemy unshootable" (very likely explained: the Road Lord)

From `spyhunter-enemy-unshootable.vsf` (score 10000, seg_idx `$0C` — the bridge segment, feature
`$01`, prev `$06`). Extracted with the moving-object-table extension added to
`tools/vsf_extract.py` this session (dumps `OBJ_TYPE`/`OBJ_ANIM`/`OBJ_TBL63`/`OBJ_TBL6B`/
`OBJ_TBL73`/`OBJ_TBLB3`/`OBJ_TBLBB` for object slots 0-7).

## Update: the official manual explains this

`claude/Enemy_Agents_Manual_Reference.md` (extracted from `original_files/Spy_Hunter_1984_Sega_text.pdf`)
documents six Enemy Agents, one of which - **the Road Lord** - is explicitly **bulletproof by
design**: "Must be rammed off road by Spy Car," the manual's only enemy with no weapon of its own
and no way to be shot down. That almost certainly *is* what this snapshot caught: not a bug, a
transient hero state, or anything bridge-specific, just the intended behaviour of that one enemy
type. The byte-level analysis below stands as evidence of what was captured, but the original
"why is this happening" framing is superseded - see the reframed hypothesis at the end.

## What's confirmed

`HERO_STATE` (`OBJ_TYPE[1]`, `$A3`) = **`$11`** in this snapshot. Checked against every other
snapshot on file, this value is unique — it doesn't match any previously-seen `HERO_STATE`:

| Snapshot | HERO_STATE `$A3` | Context |
|---|---|---|
| `enemy-unshootable` | **`$11`** | bridge, feature `$01` |
| `level1-bridge-start` | `$00` | **also** bridge, feature `$01` |
| `level1-fork-score1200` (and other normal-driving snapshots) | `$FF` | normal driving |
| `level1-score6000...in-weapon-truck` | `$03` | weapons van (documented, `claude/Weapons_Truck_Notes.md`) |

Because `level1-bridge-start` is *also* on the bridge (same `ROAD_FEATURE=$01`) but has
`HERO_STATE=$00`, not `$11`, being on the bridge alone doesn't explain the value — something
else specific to the moment `enemy-unshootable` was captured produced state `$11`.

The non-hero object slots present (`slot 2 TYPE=$0C`, `slot 6 TYPE=$05`) are ordinary enemy-type
codes that also appear unremarkably in other snapshots (e.g. `score4550` also has `slot2=$0C`,
`slot6=$05`) — nothing in the `OBJ_TBL63/6B/73` per-slot state bytes (all `$00` for these slots,
consistent with plain driving) marks any *specific* enemy slot as flagged invincible. `TBLB3`/
`TBLBB` are just screen column/row (per `claude/Weapons_Truck_Notes.md`) and vary only with
on-screen position.

**Dispatch-table corroboration:** `HERO_STATE` feeds `OBJINIT_PARAM_TBL` (`$8B3F`, indexed by
`TYPE*4`) to pick the object's move/draw vectors. Reading that table from the ROM directly:

```
type $00: move=$9A8E draw=$90AA
type $01: move=$9A8E draw=$90AA
type $02: move=$9A8E draw=$90AA
type $03: move=$9A8E draw=$90AA   (weapons van)
type $11: move=$9B02 draw=$95BE   <- different handler entirely
```

`$00`/`$01`/`$02`/`$03` (all previously-seen hero states — `$02` newly confirmed in
`claude/Dock_Exit_Notes.md`) share one move/draw handler, but `$11` dispatches to a **distinct**
one. That's supporting evidence — not proof — that `$11` is a genuinely different hero sub-state
with its own behaviour, not just a coincidental byte value. Still doesn't explain *why* an enemy
went unshootable, since the dispatch table only governs the hero object's own move/draw code, not
hit-detection against other slots.

## What's NOT confirmed

- Which of the two non-hero slots (`slot 2 TYPE=$0C`, `slot 6 TYPE=$05`) was the Road Lord, or
  whether either was — no per-slot "invincible" bit exists in the disassembly (consistent with the
  manual: it's not a flag, it's just that the Road Lord's code path never registers a hit,
  presumably because collision/weapon-hit handling checks its `OBJ_TYPE` specifically and skips
  it — not yet traced to the actual comparison in code).

  **Update (`claude/Enemy_Scoring_Notes.md`):** `TYPE=$0C` is now the leading candidate for the
  Road Lord on independent code-level evidence (its `MOVE_TYPE_0C` handler awards the 150-point
  tier via a distinctive multi-frame decrementing score, unlike the other 150-tier types' one-shot
  award) - this snapshot's `slot 2 TYPE=$0C` sighting, captured before that tracing was done,
  lines up with the later finding rather than contradicting it. `$05` is not one of the tier-3/4/5
  scoring types traced there, so it's likely ordinary boat/traffic, not the Road Lord. No hard
  "bulletproof, excluded from all bullet hits" flag was found for `$0C` though - see that doc's
  open questions.
- **Revised hypothesis for `HERO_STATE=$11`:** given the manual says the Road Lord can *only* be
  defeated by ramming, `$11` may be a ramming/collision sub-state rather than anything related to
  the miss itself — i.e. this snapshot may have caught the moment the player rammed the Road Lord
  (successfully or not), not a moment where a shot was fired and ignored. Still unconfirmed from a
  single snapshot.

## Follow-up needed

- A same-session **paired capture** — one snapshot the instant an enemy fails to register a hit,
  and a second a frame or two before/after — would let a diff isolate what actually changes.
- Ideally, a snapshot with the Road Lord clearly visible/identifiable on screen at the moment of
  interaction, to pin down which `OBJ_TYPE` value it actually is (see the "not yet mapped" section
  in `claude/Enemy_Agents_Manual_Reference.md` for the broader enemy-type identification problem).
- Locating the actual weapon-vs-enemy hit-detection code (not yet traced in this session) and
  checking whether it special-cases the Road Lord's `OBJ_TYPE` would settle this definitively
  without needing more snapshots.
