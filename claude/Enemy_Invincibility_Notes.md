# Spy Hunter - "enemy unshootable" (inconclusive, needs follow-up)

From `spyhunter-enemy-unshootable.vsf` (score 10000, seg_idx `$0C` — the bridge segment, feature
`$01`, prev `$06`). Extracted with the moving-object-table extension added to
`tools/vsf_extract.py` this session (dumps `OBJ_TYPE`/`OBJ_ANIM`/`OBJ_TBL63`/`OBJ_TBL6B`/
`OBJ_TBL73`/`OBJ_TBLB3`/`OBJ_TBLBB` for object slots 0-7).

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

## What's NOT confirmed

- Which enemy (if any specific one) was the unshootable one — no per-slot "invincible" bit was
  found; the only anomaly found is the *hero's* own state byte, not an enemy's.
- Whether `HERO_STATE=$11` is the cause, a symptom, or unrelated coincidence. One hypothesis: a
  transitional/grace-period hero state (distinct from both normal driving and the bridge's own
  `$00` sub-state) that also suppresses hit-detection that frame — but this is speculation from a
  single snapshot, not evidence.

## Follow-up needed

A same-session **paired capture** — one snapshot the instant an enemy fails to register a hit,
and a second a frame or two before/after — would let a diff isolate what actually changes. A
single isolated snapshot can only establish correlation candidates (as above), not causation;
recorded here rather than guessed at further, per this project's own standard for open items
(see the "open discrepancy" section previously resolved in `claude/Snapshot_Analysis.md`).
