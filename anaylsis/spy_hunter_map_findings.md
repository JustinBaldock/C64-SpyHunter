; =============================================================================
; SPY HUNTER - ROAD / LEVEL MAP FINDINGS  (supplement to spyhunter.asm)
; =============================================================================
;
; Companion notes for spyhunter.asm, derived by correlating live VICE .vsf
; snapshots (start / level-1 fork LEFT / level-1 fork RIGHT) with the ROM tables.
; This file is COMMENTS ONLY - it changes no assembled bytes and is safe to
; .include from spyhunter.asm (or keep as a reference beside it).
;
; All snapshot addresses below use the corrected RAM extraction: the C64MEM
; snapshot module has 4 leading bytes (pport.data, pport.dir, exrom, game)
; before the 65536-byte RAM image (tools/vsf_extract.py reads at payload+4).
; Verified via the invariant SPRITE_PTRS ($4D2B) == SPRPTR_7800 ($7BF8), which
; COPY_SPRITE_REGS writes every frame. With this fix, all live values match the
; existing spyhunter.asm labels exactly - no label corrections are required.
;
; -----------------------------------------------------------------------------
; 1. SNAPSHOT-VERIFIED VALUES  (confirm existing labels)
; -----------------------------------------------------------------------------
;   SCORE   $E0/$E1/$E2  3-byte little-endian BCD   125 / 1200 / 1950  (verified)
;   HISCORE $02/$03/$04  3-byte little-endian BCD   (tracks score while setting
;                                                    the session record)
;   TIMER   $4D01/$4D02  GAME_TIME_LO/HI, BCD, -1 every 4th frame
;                        (WAIT_FRAME_TIMER)          970 / 888 / 746   (verified)
;   WEAPON  $4D1E        WEAPON_STATE = $01 = machine guns (default)  (verified)
;   ammo    $F6/$F7/$F9  GUN_HEAT / MISSILE_CNT / SMOKE_CNT (all 0 = guns only)
;
; The status panel (PANEL_SCR0 $6798 / PANEL_SCR1 $67C0) renders each digit as a
; double-height 2x2 block: digit N -> screen codes $60+2N / $61+2N, blank $40/$41.
; Score drawn at panel column 0 (bottom-left), timer at X=$14 (centre), weapon /
; fuel icons on the right (DRAW_STATUS_PANEL / PANEL_ICON_TBL).
;
; -----------------------------------------------------------------------------
; 2. ROAD / LEVEL MAP ENGINE  (IRQ_BOTTOM_SCROLL, label L853F)
; -----------------------------------------------------------------------------
; The level is a linked graph of road segments, walked one segment at a time.
; When a segment's rows are exhausted (ROW_REPEAT->0, SEG_REPEAT->0, then
; ROAD_SEG_LEN->0), the next segment is chosen:
;
;     lda ROAD_SEG_IDX          ; $42, current segment
;     asl a : tay
;     lda SCENE_IDX : cmp #$13 : bcc + : iny   ; SCENE_IDX>=$13 -> BRANCH (odd)
;   + lda ROAD_SEG_TBL,y        ; -> next segment id
;     ...
;     lda ROAD_PTR_LO_TBL,y / ROAD_PTR_HI_TBL,y -> ROAD_PTR (row/feature list)
;     lda ROAD_LEN_TBL,y                         -> ROAD_SEG_LEN (row count)
;
; Per row: lda (ROAD_PTR),y -> ROAD_FEATURE ($44); the feature indexes the row
; graphics via OBJ_ADDR_LO/HI ($AD63/$AD7D), OBJ_ROWREP_TBL ($AD97),
; OBJ_SEGREP_TBL ($ADB1); palette via ROAD_COLIDX/BORDER/MC1/MC2.
;
; FORK MECHANISM:
;   ROAD_SEG_TBL holds TWO next-segment ids per entry:
;       ROAD_SEG_TBL[2*idx]   = MAIN   (taken when SCENE_IDX <  $13)
;       ROAD_SEG_TBL[2*idx+1] = BRANCH (taken when SCENE_IDX >= $13)
;   Snapshots confirm this maps to the physical fork the player steers into:
;       left  fork (score 1200): SCENE_IDX = $0C (< $13)  -> MAIN path
;       right fork (score 1950): SCENE_IDX = $1B (>= $13)  -> BRANCH path
;   i.e. steer LEFT = main/even next-segment, steer RIGHT = branch/odd.
;
;   Start: RESET_ROAD_INDEX sets ROAD_SEG_IDX=$1F (a start sentinel; valid
;   segment ids are $00-$1E). $1F bootstraps into segment $01.
;
; -----------------------------------------------------------------------------
; 3. DECODED SEGMENT GRAPH  (from ROAD_SEG_TBL @ $AC17, 32 x [main,branch])
; -----------------------------------------------------------------------------
;   seg  main branch  fork   segPtr  rows      (segPtr = ROAD_PTR_*_TBL[seg])
;   $01  $02   $03    FORK   $ACEF    3
;   $02  $08   $05    FORK   $ACF2   15
;   $03  $06   $04    FORK   $AD01   16
;   $04  $07   $07           $AD11    5
;   $05  $07   $07           $AD16    5
;   $06  $07   $07           $AD1B    2
;   $07  $10   $10           $AD1D    3
;   $08  $09   $0E    FORK   $AD20    9
;   $09  $0A   $0A           $AD29    2
;   $0A  $0B   $0B           $AD2B    1
;   $0B  $0C   $0C           $AD2C    3
;   $0C  $0D   $0D           $AD2F    1
;   $0D  $0F   $0F           $AD30    6
;   $0E  $0F   $0F           $AD36    3
;   $0F  $11   $11           $AD39    3
;   $10  $12   $0B    FORK   $AD3C    1
;   $11  $12   $0B    FORK   $AD3D    3
;   $12  $13   $13           $AD40    2
;   $13  $12   $14    FORK   $AD42    2
;   $14  $15   $17    FORK   $AD44   16
;   $15  $16   $16           $AD54    1
;   $16  $1A   $1A           $AD55    1
;   $17  $18   $18           $AD56    2
;   $18  $19   $19           $AD58    1
;   $19  $1A   $1A           $AD59    1
;   $1A  $1B   $1B           $AD5A    5
;   $1B  $1C   $1C           $AD5F    1
;   $1C  $01   $01           $AD60    2
;   $1D  $01   $1E    FORK   $AD62    1
;   $1E  $01   $01           $AD62    1
;   ($1F start -> $01 main / $1D branch)
;
;   Main-path walk from start:
;     $1F->$01->$02->$08->$09->$0A->$0B->$0C->$0D->$0F->$11->$12->$13->$12...
;   Segment $12<->$13 is the repeating road loop between scripted events;
;   $1C/$1D/$1E all loop back to $01 to close the level. The 10 fork points are
;   segments $01,$02,$03,$08,$10,$11,$13,$14,$1D plus the start $1F. The FIRST
;   fork the player meets is at segment $01 (branch $02 vs $03) - matches the
;   level-1 fork snapshots (ROAD_SEG_IDX = $01 then $02).
;
; -----------------------------------------------------------------------------
; 4. OPEN ITEMS
; -----------------------------------------------------------------------------
;   * Per-segment feature lists at $ACEE-$AD62 not yet expanded row-by-row.
;   * ROAD_FEATURE codes seen: $11,$0C,$12 (row-graphics indices). Special codes
;     referenced in code ($0F,$13,$14,$15) still to be labelled - snapshot at a
;     bridge / the water-boat section / the weapons van to pin each one.
; =============================================================================
