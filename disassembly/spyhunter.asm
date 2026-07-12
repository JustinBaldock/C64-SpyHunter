; =============================================================================
; SPY HUNTER  (C) 1983 Bally / U.S. Gold 1984  --  Commodore 64 16K cartridge
; =============================================================================
;   ROM $8000-$BFFF (16384 bytes), autostart, RESET = $8027.
;   Build stamp in header: 09/14/84, VER-1.1, (C)1983 BALLY.
;   MD5 of assembled binary: ee7fe8c9a5179aa8b23d8f1e49cf113c (byte-identical).
;
;   Build:
;     ca65 spyhunter.asm -o spyhunter.o
;     ld65 -C spyhunter.cfg spyhunter.o -o spyhunter.bin
;
; -----------------------------------------------------------------------------
; ANNOTATION NOTE
;   Labels, variable names and comments below are a best-effort reverse-
;   engineering pass. Confident names are plain; guesses are marked "(???)".
;   None of the renaming changes a single assembled byte.
;
; -----------------------------------------------------------------------------
; SNAPSHOT-VERIFIED FINDINGS  (from live VICE .vsf snapshots)
;   Live state read from snapshots and cross-checked with the labels below.
;   VICE C64MEM module stores 4 bytes (pport.data,dir,exrom,game) before the
;   65536-byte RAM image; read at payload+4 (verified by SPRITE_PTRS $4D2B ==
;   SPRPTR_7800 $7BF8, copied every frame in COPY_SPRITE_REGS).
;
;   SCORE   $E0/$E1/$E2   3-byte LE BCD   (125/1200/1950/6000/6050 observed)
;   HISCORE $02/$03/$04   3-byte LE BCD   (tracks score while setting the record)
;   TIMER   $4D01/$4D02   GAME_TIME_LO/HI BCD, -1 every 4th frame
;   WEAPON  $4D1E=$01 = machine guns (default); special-weapon charge lives in
;           the ammo counters $F6-$F9 (picking up smoke in the van set $F7=$FF).
;
;   ROAD MAP (full graph in disassembly/spyhunter_map_findings.asm):
;     Level = linked graph of road segments walked by IRQ_BOTTOM_SCROLL.
;     ROAD_SEG_TBL ($AC17) = 32 x (main,branch) next-segment ids; the branch
;     (odd) entry is taken when SCENE_IDX >= $13.  Snapshots: LEFT fork ->
;     SCENE_IDX < $13 (main/even), RIGHT fork -> SCENE_IDX >= $13 (branch/odd).
;     Start sentinel ROAD_SEG_IDX=$1F -> segment $01 (first fork $02 vs $03).
;
;   WEAPONS VAN: player = object slot 1; HERO_STATE $A3 $FF->$03 when in van;
;     hero sub-state $A0=$04; SCENE_ID $A8->$FF.  Sequence freezes the world:
;     SCROLL_SPEED $34->$00, TIMER_ENABLE $E3->$00.  Van = hardware sprite 1,
;     pointer $5E -> graphics $5780; new weapon granted on exit, not inside.
;
;   SMOKE WEAPON (snapshot "smoke dropped"):
;     1. Smoke is drawn as MAP CHARACTER TILES, not sprites - UPDATE_WEAPONS
;        calls DRAW_OBJECT_TILES (the shared road/van blitter) to stamp tiles
;        straight into the $7800 play buffer (SCREEN_PTR=$7Axx).
;     2. Smoke tiles: core $10, sides $AD/$AE (mirror), edge variants $B0-$B6;
;        source = ROM tile-triple table ~$A538-$A567 (STREAM_PTR=$A550), colour
;        OBJ_COLOR=$09 (brown).
;     3. Expanding plume: DRAW_OBJECT_TILES spread logic (BLIT_FLAGS) widens the
;        cloud 3->5->7->9 tiles per row; position BLIT_COL<-STATE_4DB9 ($4DB9),
;        BLIT_ROW<-STATE_4DC1+2 ($4DC1) = just behind the car.
;     4. It scrolls with NO code of its own: being in the $7800 road buffer, it
;        rides the road's vertical scroll (VSCROLL_POS/D011 fine-scroll +
;        SCROLL_SPEED + the IRQ per-row copy). New tiles stamped each frame.
;     5. Transient: DRAW_OBJECT_TILES writes only the screen buffer + colour RAM,
;        never the ROM level/segment tables or road template, so smoke scrolls
;        off the top and is recycled - it does NOT alter the permanent map.
;     6. Special-weapon charge = $F7: $FF full on pickup, decrements as used
;        (seen $FF->$EC).  (This is the "smoke" the player picks; refines the
;        MISSILE_CNT/SMOKE_CNT (???) guesses on $F6-$F9.)
;     7. WEAPON_STATE $4D1E stays $01 (machine guns) throughout - the special
;        weapon is independent of $4D1E, tracked by the ammo counter + fired
;        via UPDATE_WEAPONS.
;
;   WATER / BRIDGE (snapshot "bridge start", still car scene SCENE_ID=$05):
;     1. Water is MAP CHARACTER TILES in the $7800 road buffer, drawn like the
;        road - not a sprite, not a separate layer. It just replaces the grass
;        road margins with water tiles.
;     2. Water tiles: texture $08-$13, solid water $06, shore/near water $07.
;        Bridge: rails $30-$3F, upper deck $01, lower deck $02; the two
;        carriageways are split by a blank ($00) gap.
;     3. It IS part of the map: the water tiles come from the road-segment
;        template that the road IRQ copies row-by-row (SCROLL_SRC -> SCROLL_DST),
;        so water is permanent segment graphics that scroll with the road.
;        (Contrast: the smoke weapon is transiently blitted and scrolls off.)
;     4. Water "animation" is free: the texture repeats every ~5 rows; as the
;        map scrolls the patterned tiles cycle (same trick as lane markers).
;     5. In-water bridge support/pylon = map tiles $4E/$4F/$50/$51/$52/$53 (2x3),
;        also drawn as tiles (not a sprite).
;     6. Water colours are the per-segment split colours (ROAD_BORDER/MC1/MC2):
;        border/bg $36=$0B, mc1 $37=$0F, mc2 $38=$01 (grey/white, moonlit water).
;
;   RIVER ENTRANCE / TIMER EXPIRY (snapshot "river entrance, timer gone"):
;     1. ROAD_FEATURE $44=$13 is the river-entrance transition feature (segment
;        $0F, PREV_FEATURE=$11, SCENE_IDX=$13).  Still the car scene (SCENE_ID=
;        $05), drawn as $7800 map tiles: the road divides into a two-lane
;        highway with a central median (tile $2F) + roadside scenery, narrowing
;        toward the water. (No water tiles on screen yet - this is the approach.)
;     2. "Timer gone" mechanism: when GAME_TIME reaches 0, WAIT_FRAME_TIMER sets
;        EXTRA_LIFE_AVAIL ($4D12) = $FF; DRAW_STATUS_PANEL then draws the LIVES
;        markers in the timer slot INSTEAD of the countdown, so the timer
;        disappears.  So $4D12 is really a timer-expired flag: $00 = running/
;        shown, $FF = expired/hidden (and it also sets FLAG_FC on the car scene).
;     3. TIMER_ENABLE $E3 stays $02 after expiry, so GAME_TIME keeps wrapping
;        past 0 (seen $9761) but is no longer drawn.
;
; RUNTIME MEMORY MAP
;   $00-$01 6510 I/O port ($01=$05 run) ; $02-$04 high score BCD
;   $12-$2F working pointers            ; $34-$41 IRQ/raster split state
;   $52-$6D SID per-voice state         ; $CA-$DA sprite coord shadow ->$D000
;   $E0-$E2 current score BCD           ; $2800-$2FFF speed routine (JSR $2802)
;   $4000-$7FFF VIC bank 1 graphics     ; $4D00-$4DFF game-state variables
;   $6400/$7800/$7C00 screen buffers    ; $6800/$7000 two charsets
;   $8000-$BFFF this ROM                ; $D800-$DBFF colour RAM
;   $E000-$FFFF RAM (CPU vectors $FFFA-$FFFF)
; =============================================================================
.setcpu "6502"
; =============================================================================
; SYMBOL EQUATES  (zero page, $4Dxx game state, hardware registers)
; =============================================================================
COLOR_RAM = $D800    ; colour RAM base
ZP_00 = $00    ; 6510 data-direction reg ($2F)
CPU_PORT = $01    ; 6510 port: RAM/ROM banking ($01)
HISCORE_LO = $02    ; high score, 3-byte BCD (lo)
HISCORE_MID = $03    ; high score BCD (mid)
HISCORE_HI = $04    ; high score BCD (hi)
BIT_MASK = $05    ; current object sprite bit
OBJ_IDX = $06    ; current object slot 0..7
OBJ_IDX2 = $07    ; object slot * 2
ZTMP_08 = $08
ZTMP_09 = $09
ZTMP_0A = $0A
ZTMP_0B = $0B
ZTMP_0C = $0C
ZTMP_0D = $0D
ZTMP_0F = $0F
BIT_MASK_INV = $10    ; complement of BIT_MASK (EOR mask)
SRC_PTR = $12    ; general source pointer
SRC_PTR_HI = $13
DST_PTR = $14    ; general dest pointer
DST_PTR_HI = $15
DST2_PTR = $16    ; 2nd dest pointer
DST2_PTR_HI = $17
MAP_SRC = $18    ; map decode: source
MAP_SRC_HI = $19
MAP_DST = $1A    ; map decode: dest
MAP_DST_HI = $1B
MAP_PREV = $1C    ; map decode: prev row
MAP_PREV_HI = $1D
MAP_ROW = $1E    ; map decode: row
MAP_ROW_HI = $1F
SCREEN_PTR = $22    ; blitter: screen dest
SCREEN_PTR_HI = $23
STREAM_PTR = $24    ; byte-stream read pointer
STREAM_PTR_HI = $25
STREAM_PTR2 = $26    ; 2nd stream pointer
STREAM_PTR2_HI = $27
SCROLL_SRC = $28    ; IRQ block-copy source
SCROLL_SRC_HI = $29
SCROLL_DST = $2A    ; IRQ block-copy dest
SCROLL_DST_HI = $2B
ROAD_PTR = $2C    ; current road-segment data
ROAD_PTR_HI = $2D
SCROLL_SRC_SAVE = $2E    ; saved scroll source
SCROLL_SRC_SAVE_HI = $2F
ZTMP_30 = $30
BLIT_WIDTH = $31    ; blit block width
BLIT_COUNT = $32    ; blit block count
FRAME_CTR = $33    ; frame counter (+1/frame)
SCROLL_SPEED = $34    ; vertical road scroll speed
ROAD_X_REF = $35    ; road centre x reference (???)
BORDER_COL_SPLIT = $36    ; border colour below split
MC_COL1_SPLIT = $37    ; multicolour 1 below split
MC_COL2_SPLIT = $38    ; multicolour 2 below split
BORDER_COL_TOP = $39    ; border colour, panel
MC_COL1_TOP = $3A    ; multicolour 1, panel
MC_COL2_TOP = $3B    ; multicolour 2, panel
SPLIT_RASTER = $3C    ; next raster-compare line
D011_SHADOW = $3D    ; shadow of VIC_CR1
VSCROLL_POS = $3E    ; vertical scroll accumulator
D018_SHADOW = $3F    ; shadow of VIC_MEMPTR
D018_ALT = $40    ; alternate VIC_MEMPTR
COPY_BLOCK_FLAG = $41    ; IRQ: do block-copy this frame
ROAD_SEG_IDX = $42    ; road segment index (start sentinel $1F)
ROAD_SEG_LEN = $43    ; road segment length
ROAD_FEATURE = $44    ; current road feature code
PREV_FEATURE = $45    ; previous road feature
SEG_REPEAT = $46    ; segment repeat count
SEG_REPEAT_INIT = $47
ROW_REPEAT = $48    ; row repeat count
SEQ_STATE = $49    ; sequence/animation state (0..6)
SCENE_IDX = $4A    ; scene/level index; >=$13 selects road branch (right fork)
SND_VOICE = $4B    ; music: current voice
SND_REGOFS = $4C    ; music: SID register offset
SND_PTR_LO = $4D    ; music: work ptr lo
SND_PTR_HI = $4E    ; music: work ptr hi
SND_TMP = $4F
SND_SEQ_PTR = $50    ; music: sequence pointer
SND_SEQ_PTR_HI = $51
SND_PTR0_LO = $52    ; voice ptr lo (base)
SND_SEQ = $55    ; voice active / seq id (base)
SND_SEQ_V1 = $56
SND_SEQ_V2 = $57
SND_DUR = $58    ; voice note duration
SND_POS = $5B    ; voice sequence position
SND_SLIDE_HI = $5E    ; voice portamento hi
SND_FREQ_LO = $61    ; voice frequency lo
SND_TGT_LO = $64    ; voice slide target lo
SND_TGT_HI = $67    ; voice slide target hi
SND_RATE = $6A    ; voice slide rate
SND_SLIDE_LO = $6D    ; voice portamento lo
ZVEC_MOVE = $71    ; indirect object-move vector
ZVEC_DRAW = $73    ; indirect object-draw vector
ZVEC_DRAW_HI = $74
SPRMUX_CNT = $75    ; sprite-multiplex line counters
SPRMUX_CNT1 = $76
SPRMUX_CNT2 = $77
SPRMUX_CNT3 = $78
COLOR_PTR = $95    ; blitter colour-RAM dest
COLOR_PTR_HI = $96
OBJ_COLOR = $97    ; blit colour value
BLIT_COL = $98    ; object screen column
BLIT_ROW = $99    ; object screen row
OBJ_ANIM = $9A    ; per-object animation frame
FLAG_A1 = $A1    ; flag (???)
OBJ_TYPE = $A2    ; per-object type ($FF=empty); slot1=hero, =$03 in weapons van
HERO_STATE = $A3    ; hero state = OBJ_TYPE[1]; $FF normal, $03 in weapons van
SCENE_ID = $A8    ; high-level scene id (car/boat/...); $FF during van sequence
ANIM_STATE = $A9    ; sub-state / animation selector (???)
SPR_STAGE = $BA    ; staged hardware sprite coords
SPR_X_SHADOW = $CA    ; sprite X shadow (->$D000)
SPR_Y_SHADOW = $CB    ; sprite Y shadow
SPAWN_Y = $CD    ; object spawn y (= sprite1 Y shadow; van vertical pos)
SPR_XMSB = $DA    ; sprite X bit-8 shadow (->$D010)
RNG_SEED = $DB    ; PRNG seed
SCORE_OVFL = $DC    ; score overflow / millions (???)
FLAG_DD = $DD    ; flag (???)
HIT_MASK_A = $DE    ; collision result A
HIT_MASK_B = $DF    ; collision result B
SCORE_LO = $E0    ; score BCD (lo)
SCORE_MID = $E1    ; score BCD (mid)
SCORE_HI = $E2    ; score BCD (hi)
TIMER_ENABLE = $E3    ; game-timer enable ($00 freezes it, e.g. in the van)
FX_TIMER0 = $E4    ; hazard/effect timer 0
FX_TIMER1 = $E5    ; effect timer 1
FX_TIMER2 = $E6    ; effect timer 2
FX_TIMER3 = $E7    ; effect timer 3
BLIT_ROWS = $E8    ; blitter row counter
FX_SRC = $E9    ; effect data pointer
FX_SRC_HI = $EA
FX_COUNT = $EB    ; effect step count
FX_LEN = $EC    ; effect length
KEY_TOGGLE = $ED    ; pause/mute toggles
KEY_DEBOUNCE = $F0    ; key debounce timers
DEMO_TIMER = $EE    ; attract/demo countdown (???)
START_HELD = $EF    ; start-button held counter (???)
KEY_LAST = $F3    ; last key seen
GUN_HEAT = $F6    ; weapon/ammo counter (???)
MISSILE_CNT = $F7    ; active special-weapon charge: $FF full on pickup, dec per
                     ;   use ($FF->$EC seen dropping "smoke"). (???: name may be smoke)
PANEL_X = $F8    ; panel draw column (???)
SMOKE_CNT = $F9    ; smoke count (???)
ROAD_PHASE = $FA    ; road lane phase
FLAG_FB = $FB    ; flag (???)
FLAG_FC = $FC    ; flag (???)
BLIT_FLAGS = $FD    ; blit mode flags
FLAG_FF = $FF    ; flag (???)
SPEEDCODE = $2802    ; RAM speed routine entry ($2802)
VEC_OBJMOVE = $2893    ; self-mod object-move vector
VEC_OBJMOVE_HI = $2894
VEC_STATE = $2895    ; main state dispatch vector
VEC_STATE_HI = $2896
VEC_SCROLL = $2897    ; road-scroll dispatch vector
VEC_SCROLL_HI = $2898
ROWADDR_LO = $2899    ; screen row-address table lo
ROWADDR_HI = $289A    ; screen row-address table hi
FRAME_FLAG = $4D00    ; IRQ frame counter (waited on)
GAME_TIME_LO = $4D01    ; game timer BCD lo (on-screen timer)
GAME_TIME_HI = $4D02    ; game timer BCD hi
IRQ_TOGGLE = $4D03    ; IRQ scroll toggle
STATE_4D05 = $4D05
NEXT_LIFE_SCORE = $4D06    ; next extra-life threshold
STATE_4D07 = $4D07
STATE_4D08 = $4D08
JOY_STATE = $4D09    ; decoded joystick state
STATE_4D0C = $4D0C
IRQ_HALF = $4D0D    ; IRQ top/bottom toggle
FRAME_SUBCTR = $4D0F    ; frame sub-counter
STATE_4D10 = $4D10
NUM_PLAYERS = $4D11    ; 1 or 2 players
EXTRA_LIFE_AVAIL = $4D12    ; timer-expired flag: $00 running(timer shown),
                            ;   $FF expired (DRAW_STATUS_PANEL shows lives, hides timer)
GAME_STATE = $4D13    ; game state machine
TWO_PLAYER = $4D14    ; 2-player flag
LIVES = $4D15    ; player lives
STATE_4D16 = $4D16
STATE_4D17 = $4D17
STATE_4D18 = $4D18
MUX_SLOT_IDX = $4D19    ; sprite-mux slot index
MUX_SLOT0 = $4D1A    ; active mux slot 0
MUX_SLOT1 = $4D1B    ; active mux slot 1
MUX_SLOT2 = $4D1C    ; active mux slot 2
STATE_4D1D = $4D1D
WEAPON_STATE = $4D1E    ; weapon state ($01=machine guns; special = ammo $F6-$F9)
HIT_GROUP0 = $4D1F    ; collision group mask 0
HIT_GROUP1 = $4D20    ; collision group mask 1
HIT_GROUP2 = $4D21    ; collision group mask 2
HIT_ACCUM = $4D22    ; collision accumulator
SPRITE_PTRS = $4D2B    ; sprite pointer shadow (copied to $7BF8 each frame)
OBJ_TBL63 = $4D63
OBJ_TBL69 = $4D69
OBJ_TBL6B = $4D6B
OBJ_TBL71 = $4D71
OBJ_TBL73 = $4D73
OBJ_TBL79 = $4D79
OBJ_TBLAB = $4DAB
STATE_4DAC = $4DAC
OBJ_TBLB3 = $4DB3
STATE_4DB9 = $4DB9
OBJ_TBLBB = $4DBB
STATE_4DC1 = $4DC1
SCORE_EVENT = $4DC3    ; queued score events
STAT_CTR = $4DC4    ; statistic counters
STATE_4DCB = $4DCB
VIC_SPR0X = $D000    ; sprite 0 X (VIC reg base)
VIC_CR1 = $D011    ; control reg 1 (Y-scroll/rows/RSEL)
VIC_RASTER = $D012    ; raster line / compare
VIC_SPR_ENA = $D015    ; sprite enable
VIC_CR2 = $D016    ; control reg 2 (X-scroll/MCM/40col)
VIC_MEMPTR = $D018    ; screen+charset pointers
VIC_IRR = $D019    ; interrupt request reg
VIC_IMR = $D01A    ; interrupt mask reg
VIC_SPR_BGPRI = $D01B    ; sprite-bg priority
VIC_BORDER = $D020    ; border colour
VIC_BG0 = $D021    ; background colour 0
VIC_BG1 = $D022    ; background colour 1
VIC_BG2 = $D023    ; background colour 2
VIC_SPRMC0 = $D025    ; sprite multicolour 0
VIC_SPRMC1 = $D026    ; sprite multicolour 1
SID_V1_FLO = $D400    ; voice1 freq lo
SID_V1_FHI = $D401    ; voice1 freq hi
SID_V1_CTRL = $D404    ; voice1 control
SID_V1_AD = $D405    ; voice1 attack/decay
SID_V1_SR = $D406    ; voice1 sustain/release
SID_V2_CTRL = $D40B    ; voice2 control
SID_V3_CTRL = $D412    ; voice3 control
SID_VOL = $D418    ; master volume/filter
CIA1_PRA = $DC00    ; CIA1 port A (keyboard cols/joy2)
CIA1_PRB = $DC01    ; CIA1 port B (keyboard rows/joy1)
CIA1_DDRA = $DC02    ; CIA1 data-dir A
CIA1_ICR = $DC0D    ; CIA1 interrupt ctrl
CIA2_PRA = $DD00    ; CIA2 port A (VIC bank select)
CIA2_DDRA = $DD02    ; CIA2 data-dir A
CIA2_ICR = $DD0D    ; CIA2 interrupt ctrl
VEC_NMI = $FFFA    ; CPU NMI vector
VEC_NMI_HI = $FFFB
VEC_RESET = $FFFC    ; CPU RESET vector
VEC_RESET_HI = $FFFD
VEC_IRQ = $FFFE    ; CPU IRQ vector
VEC_IRQ_HI = $FFFF

; =============================================================================
; DATA / TABLE ADDRESSES  (ROM tables + RAM screen/charset buffers)
; =============================================================================
PANEL_SCR0 = $6798
PANEL_SCR1 = $67C0
SPRPTR_6400 = $67F8
CHARSET_A_10 = $6810
CHARSET_A_E0 = $68E0
CHARSET_B_660 = $7660
CHARSET_B_730 = $7730
SCR_PLAY_0D = $7A0D
SCR_PLAY_35 = $7A35
SCR_PLAY_5D = $7A5D
SPRPTR_7800 = $7BF8
SCR_HISC_0D = $7E0D
SCR_HISC_35 = $7E35
SCR_HISC_5D = $7E5D
SPRPTR_7C00 = $7FF8
PANEL_LABELS_TBL = $824D
MENU_MSG_TBL = $8283
MENU_MSG_TBL_B = $8293
SCROLL_VEC_TBL = $8621
SCROLL_VEC_TBL_B = $8622
SCROLL_VEC_TBL_C = $8623
SCROLL_VEC_TBL_D = $8624
OBJ_DIST_TBL = $897B
OBJMOVE_VEC_LO = $8B2F
OBJMOVE_VEC_HI = $8B30
OBJINIT_PARAM_TBL = $8B3F
SPR_MATCH_A = $A568
SPR_MATCH_B = $A578
SPR_MATCH_C = $A588
FX_PARAM_E9 = $A75E
FX_PARAM_EA = $A764
FX_PARAM_30 = $A76A
FX_PARAM_EB = $A770
FX_PARAM_EC = $A776
TALLY_CHAR_TBL = $A83B
POINTS_TBL_LO = $A89D
POINTS_TBL_HI = $A89E
PANEL_ICON_TBL = $A963
KEYCODE_TBL = $AA17
KEYIDX_TBL = $AA1D
KEYVAL_TBL = $AA23
PAUSEKEY_TBL = $AA60
SNDCMD_VEC_LO = $AB24
SNDCMD_VEC_HI = $AB25
ROAD_SEG_TBL = $AC17
ROAD_PTR_LO_TBL = $AC57
ROAD_PTR_HI_TBL = $AC76
ROAD_LEN_TBL = $AC95
ROAD_COLIDX_TBL = $ACB4
ROAD_BORDER_TBL = $ACD3
ROAD_MC1_TBL = $ACDC
ROAD_MC2_TBL = $ACE5
OBJ_ADDR_LO = $AD63
OBJ_ADDR_LO2 = $AD64
OBJ_ADDR_HI = $AD7D
OBJ_ADDR_HI2 = $AD7E
OBJ_ROWREP_TBL = $AD97
OBJ_SEGREP_TBL = $ADB1
INIT_CHARS_TBL = $BC6C
SND_FREQ_LO_TBL = $BCBB
SND_FREQ_HI_TBL = $BCBC
SND_DUR_TBL = $BD13
SND_SEQPTR_LO = $BD17
SND_SEQPTR_HI = $BD18
.segment "CODE"
.org $8000

; -----------------------------------------------------------------------
; Cartridge autostart header: cold/warm vectors -> RESET ($8027), the
; "CBM80" magic the KERNAL looks for, and the ASCII build stamp.
    .byte $27,$80,$27,$80,$C3,$C2,$CD,$38,$30,$30,$39,$2F,$31,$34,$2F,$38
    .byte $34,$2C,$56,$45,$52,$2D,$31,$2E,$31,$2C,$28,$43,$29,$31,$39,$38
    .byte $33,$20,$42,$41,$4C,$4C,$59

; -----------------------------------------------------------------------
; RESET / cold + warm entry ($8027).
RESET:
    sei
    cld
    lda #$7F
    sta CIA2_ICR
    sta CIA1_ICR
    lda CIA2_ICR
    lda CIA1_ICR
    ldx #$FF
    txs
    jsr INIT_SYSTEM

; -----------------------------------------------------------------------
; Top-level game state loop.
MAIN_RUN_ATTRACT:
    jsr ATTRACT_TITLE

MAIN_RUN_MENU:
    jsr ATTRACT_MENU

MAIN_RUN_PLAY:
    jsr INIT_PLAY_STATE
    jsr MUSIC_START_THEME

; -----------------------------------------------------------------------
; Per-frame master loop.
GAME_LOOP:
    jsr WAIT_FRAME_TIMER
    jsr PROCESS_OBJECTS
    jsr UPDATE_SCENE_SELECT
    jsr UPDATE_WEAPONS
    jsr DRAW_STATUS_PANEL
    jsr TALLY_SCORE_EVENTS
    jsr HANDLE_PAUSE_KEYS
    jsr GAME_DISPATCH
    lda GAME_STATE
    bne L808C
    lda GAME_TIME_HI
    cmp #$08
    bcc L80AA
    lda #$FF
    cmp CIA1_PRB
    bne L807D
    cmp CIA1_PRA
    bne L807D
    lda START_HELD
    beq L808C

L807D:
    inc START_HELD
    lda NUM_PLAYERS
    beq L80D5
    lda TWO_PLAYER
    beq L80D5
    sta GAME_STATE

L808C:
    lda DEMO_TIMER
    bne L80D5
    lda START_HELD
    bne L80CF
    lda LIVES
    bpl L80A7
    lda ANIM_STATE
    cmp #$15
    bcc L80A7
    cmp #$18
    bcs L80A7
    lda FLAG_A1
    beq L80AA

L80A7:
    jmp GAME_LOOP

L80AA:
    jsr CLEAR_PANEL
    ldy #$00
    jsr ADD_SCORE
    inc FX_TIMER0
    jsr DELAY_FRAMES
    lda #$06
    sta ZTMP_08

L80BB:
    jsr POLL_INPUT_FRAME
    bne L80CF
    dec ZTMP_08
    bne L80BB
    sta GAME_STATE
    jsr RESET_ROAD_INDEX
    inc SCENE_IDX
    jmp MAIN_RUN_ATTRACT

L80CF:
    jsr RESET_ROAD_INDEX
    jmp MAIN_RUN_PLAY

L80D5:
    lda #$01
    sta GAME_STATE
    jsr RESET_ROAD_INDEX_ALT
    inc SCENE_IDX
    jmp MAIN_RUN_MENU

; -----------------------------------------------------------------------
; Enter the current game-state handler via VEC_STATE ($2895).
GAME_DISPATCH:
    jmp (VEC_STATE)

; -----------------------------------------------------------------------
; One-time system init.
INIT_SYSTEM:
    lda #$80
    tay
    ldx #$40
    jsr COPY_PAGES
    lda #$05
    sta CPU_PORT
    lda #$2F
    sta ZP_00
    ldx #$00
    txa
    stx VIC_CR1
    stx VIC_IMR
    stx VIC_SPR_ENA
    stx VIC_SPR_BGPRI
    dex
    stx VIC_IRR
    dex

L8109:
    sta CPU_PORT,x
    dex
    bne L8109
    jsr DRAW_PLAYFIELD_FRAME
    jsr UNPACK_MAP_DATA
    lda #$00
    ldy #$4D
    ldx #$33
    jsr FILL_PAGES
    lda #$03
    sta CPU_PORT
    lda #$00
    sta SRC_PTR
    lda #$D0
    sta SRC_PTR_HI
    lda #$01
    sta DST_PTR
    lda #$68
    sta DST_PTR_HI
    lda #$09
    sta DST2_PTR
    lda #$68
    sta DST2_PTR_HI
    lda #$40
    sta ZTMP_0A

L813D:
    lda #$08
    sta ZTMP_0B

L8141:
    ldx #$00
    lda (SRC_PTR,x)
    jsr PACK_2BITS
    ldy ZTMP_09
    jsr PACK_2BITS
    ldx #$00
    tya
    sta (DST_PTR,x)
    lda ZTMP_09
    sta (DST2_PTR,x)
    jsr PTR_SRC_INC
    jsr PTR_DST_INC
    jsr PTR_AUX_INC
    dec ZTMP_0B
    bne L8141
    lda #$08
    jsr PTR_DST_ADD
    lda #$08
    jsr PTR_AUX_ADD
    dec ZTMP_0A
    bne L813D
    ldy #$4E

L8173:
    lda INIT_CHARS_TBL,y
    sta (DST_PTR),y
    dey
    bpl L8173
    lda #$05
    sta CPU_PORT
    lda #$00
    sta DST_PTR
    lda #$70
    sta DST_PTR_HI
    lda #$0C
    sta ZTMP_0C
    jsr BUILD_CHAR_PAIR
    lda #$1C
    sta ZTMP_0C
    lda #$00
    jsr BUILD_CHAR_PAIR
    lda #$3B
    sta ZTMP_0C

L819B:
    ldy #$00

L819D:
    jsr STREAM_NEXT_BYTE
    sta (DST_PTR),y
    iny
    cpy #$08
    bne L819D
    lda #$08
    jsr PTR_DST_ADD
    dec ZTMP_0C
    bne L819B
    lda #$0E
    sta ZTMP_0C
    lda #$00
    jsr BUILD_CHAR_PAIR
    ldx #$00

L81BB:
    lda CHARSET_A_10,x
    asl a
    sta CHARSET_B_660,x
    lda CHARSET_A_E0,x
    asl a
    sta CHARSET_B_730,x
    inx
    cpx #$D0
    bne L81BB
    lda #$00
    sta SRC_PTR
    lda #$78
    sta SRC_PTR_HI
    ldx #$00

L81D8:
    lda SRC_PTR
    sta ROWADDR_LO,x
    inx
    lda SRC_PTR_HI
    sta ROWADDR_LO,x
    inx
    lda #$28
    jsr PTR_SRC_ADD
    cpx #$32
    bne L81D8
    jsr UNPACK_CHARSET
    ldx #$00
    stx BLIT_ROWS
    inx
    stx VIC_IRR
    stx VIC_IMR
    stx WEAPON_STATE
    inx
    stx CIA2_PRA
    inx
    stx CIA2_DDRA
    stx STATE_4D1D
    stx STATE_4D16
    lda #$18
    sta VIC_CR2
    lda #$27
    sta VEC_NMI
    lda #$80
    sta VEC_NMI_HI
    lda #$27
    sta VEC_RESET
    lda #$80
    sta VEC_RESET_HI
    lda #$02
    sta VEC_IRQ
    lda #$84
    sta VEC_IRQ_HI
    lda #$EA
    sta SPLIT_RASTER
    lda #$17
    sta VSCROLL_POS
    lda #$1B
    sta D011_SHADOW
    lda #$9A
    sta D018_SHADOW
    lda #$FC
    sta D018_ALT
    lda #$F1
    sta VIC_RASTER
    jsr RESET_SCROLL_VARS
    cli
    rts
; -----------------------------------------------------------------------
; PANEL_LABELS_TBL: 20 screen char-codes drawn to the status panel by ATTRACT_TITLE.
    .byte $32,$02,$2E,$08,$12,$1A,$40,$32,$18,$18,$02,$04,$40,$66,$70,$72
    .byte $62,$52,$06,$50

; -----------------------------------------------------------------------
; Draw the attract/title status line and poll for input.
ATTRACT_TITLE:
    jsr RESET_SCREEN_STATE
    jsr DELAY_FRAMES_ALT
    ldx #$00
    ldy #$13

L826B:
    lda PANEL_LABELS_TBL,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl L826B
    lda #$12
    sta SCENE_IDX
    jsr POLL_INPUT_FRAME
    beq L827F
    inc SCENE_IDX

L827F:
    sta GAME_STATE
    rts
; -----------------------------------------------------------------------
; MENU_MSG_TBL / MENU_MSG_TBL_B: char-codes for the player-select / demo screen.
    .byte $28,$24,$0A,$20,$30,$0A,$40,$24,$1E,$40,$0A,$06,$12,$2C,$1E,$1C
    .byte $0A,$24,$1E,$06,$26,$40,$10,$0E,$12,$10

; -----------------------------------------------------------------------
; Player-select / demo screen.
ATTRACT_MENU:
    jsr RESET_SCREEN_STATE
    lda GAME_STATE
    beq L8318
    jsr DELAY_FRAMES_ALT
    ldx #$14
    ldy #$09

L82AC:
    lda MENU_MSG_TBL_B,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl L82AC
    jsr DRAW_SCORE

L82B8:
    jsr POLL_INPUT_FRAME
    beq L8318
    ldx #$01
    ldy #$11
    cmp #$1D
    beq L82CC
    inx
    ldy #$1D
    cmp #$1A
    bne L82B8

L82CC:
    stx NUM_PLAYERS
    ldx #$12
    lda #$00

L82D3:
    sta SCR_PLAY_0D,y
    sta SCR_PLAY_35,y
    sta SCR_PLAY_5D,y
    sta SCR_HISC_0D,y
    sta SCR_HISC_35,y
    sta SCR_HISC_5D,y
    dey
    dex
    bne L82D3
    jsr CLEAR_PANEL
    ldx #$04
    ldy #$0F

L82F0:
    lda MENU_MSG_TBL,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl L82F0

L82F9:
    jsr POLL_INPUT_FRAME
    beq L8318
    ldy #$01
    cmp #$18
    beq L8309
    cmp #$31
    bne L82F9
    iny

L8309:
    sty GAME_STATE
    sty TWO_PLAYER
    dey
    beq L8315
    jmp LA274

L8315:
    jmp CLEAR_PANEL_ALT

L8318:
    lda #$00
    sta GAME_STATE
    rts

; -----------------------------------------------------------------------
; Set up a fresh play state.
INIT_PLAY_STATE:
    jsr CLEAR_RAM_AND_SPRITES
    jsr DELAY_FRAMES_ALT
    ldx GAME_STATE
    beq L8333
    ldx TWO_PLAYER
    cpx #$01
    beq L8333
    ldy #$FF
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
L8333:
    ldy #$05
    sty MUX_SLOT2
    dey
    sty MUX_SLOT1
    dey
    sty MUX_SLOT0
    lda #$01
    sta LIVES
    sta EXTRA_LIFE_AVAIL
    dec EXTRA_LIFE_AVAIL
    lda #$99
    sta GAME_TIME_LO
    lda #$09
    sta GAME_TIME_HI
    ldx #$FF
    stx STATE_4D17
    stx VIC_SPR_ENA
    inx
    inx
    stx PREV_FEATURE
    stx SEQ_STATE
    stx STATE_4D05
    stx STATE_4DCB
    inx
    stx NEXT_LIFE_SCORE
    stx MUX_SLOT_IDX
    lda #$0E
    sta VIC_SPRMC0
    lda #$01
    sta VIC_SPRMC1
    lda #$89
    ldy #$A1
    ldx GAME_STATE
    beq L8393
    ldx NUM_PLAYERS
    dex
    beq L838F
    lda #$F6
    ldy #$A9
    bne L8393

L838F:
    lda #$52
    ldy #$A1

L8393:
    sta VEC_STATE
    sty VEC_STATE_HI

; -----------------------------------------------------------------------
; Clear per-scene state then fall into CLEAR_RAM_AND_SPRITES.
RESET_SCREEN_STATE:
    jsr CLEAR_PANEL

; -----------------------------------------------------------------------
; Fill colour RAM, init SID, zero ZP $DC-$FF, clear object slots, push sprites.
CLEAR_RAM_AND_SPRITES:
    jsr CLEAR_COLOR_RAM
    jsr SID_INIT
    ldx #$DC
    ldy #$00
    tya

L83A7:
    sta ZP_00,x
    inx
    bne L83A7
    lda #$FE
    sta BIT_MASK_INV

L83B0:
    jsr INIT_OBJECT_SLOT
    lda #$95
    sta SPRPTR_6400,x
    inx
    iny
    iny
    sec
    rol BIT_MASK_INV
    bcs L83B0
    jmp LA361

; -----------------------------------------------------------------------
; Raster IRQ, top of frame ($83C3, vectored from IRQ_MAIN).
IRQ_TOP_PANEL:
    pha
    txa
    pha
    ldx #$04

L83C8:
    dex
    bne L83C8
    lda BORDER_COL_TOP
    sta VIC_BORDER
    sta VIC_BG0
    lda MC_COL1_TOP
    sta VIC_BG1
    lda MC_COL2_TOP
    sta VIC_BG2
    ldx #$F1
    lda VIC_CR1
    and #$07
    cmp #$02
    beq L83E9
    inx

L83E9:
    stx VIC_RASTER
    lda #$02
    sta VEC_IRQ
    lda #$84
    sta VEC_IRQ_HI
    lda #$01
    sta VIC_IRR
    pla
    tax
    pla
    rti

; -----------------------------------------------------------------------
; Jump through VEC_SCROLL ($2897) into the current road-scroll chunk.
SCROLL_DISPATCH:
    jmp (VEC_SCROLL)

; -----------------------------------------------------------------------
; Main raster IRQ ($8402).
IRQ_MAIN:
    cld
    pha
    txa
    pha
    tya
    pha
    ldx #$03

L840A:
    dex
    bne L840A
    lda D011_SHADOW
    sta VIC_CR1
    lda D018_SHADOW
    sta VIC_MEMPTR
    ldy IRQ_HALF
    bne L841F
    jmp IRQ_BOTTOM_SCROLL

L841F:
    lda BORDER_COL_SPLIT
    sta VIC_BORDER
    sta VIC_BG0
    lda MC_COL1_SPLIT
    sta VIC_BG1
    lda MC_COL2_SPLIT
    sta VIC_BG2
    lda SPLIT_RASTER
    cmp #$EE
    bcc L8445
    lda BORDER_COL_SPLIT
    sta BORDER_COL_TOP
    lda MC_COL1_SPLIT
    sta MC_COL1_TOP
    lda MC_COL2_SPLIT
    sta MC_COL2_TOP
    lda #$2F

L8445:
    sta VIC_RASTER
    sta SPLIT_RASTER
    lda #$C3
    sta VEC_IRQ
    lda #$83
    sta VEC_IRQ_HI
    lda #$01
    sta VIC_IRR
    cli
    lda #$1B
    sta D011_SHADOW
    lda #$9A
    sta D018_SHADOW
    lda COPY_BLOCK_FLAG
    beq L84D2
    ldy #$1F

L8468:
    lda (SCROLL_SRC),y
    sta (SCROLL_DST),y
    dey
    bpl L8468
    iny
    sty COPY_BLOCK_FLAG
    ldy #$1F

L8474:
    lda a:SPRMUX_CNT,y
    beq L8485
    jsr SPEEDCODE
    lda #$0E
    sta COLOR_RAM+HISCORE_HI,y
    tya
    tax
    dec SPRMUX_CNT,x

L8485:
    dey
    bpl L8474
    lda ROW_REPEAT
    ldy #$14
    cmp #$01
    bne L849E
    lda ROAD_FEATURE
    cmp #$15
    beq L84AA
    cmp #$13
    bne L84C9
    ldy #$04
    bne L84AA

L849E:
    ldy STATE_4D18
    beq L84C9
    lda #$00
    sta STATE_4D18
    beq L84AD

L84AA:
    sty STATE_4D18

L84AD:
    lda #$0A
    sta COLOR_RAM+HISCORE_HI,y
    sta COLOR_RAM+BIT_MASK,y
    sta COLOR_RAM+OBJ_IDX,y
    sta COLOR_RAM+OBJ_IDX2,y
    lda #$19
    sta a:SPRMUX_CNT,y
    sta a:SPRMUX_CNT1,y
    sta a:SPRMUX_CNT2,y
    sta a:SPRMUX_CNT3,y

L84C9:
    jsr SCROLL_DISPATCH
    jsr UPDATE_HAZARDS
    inc FRAME_SUBCTR

L84D2:
    jmp IRQ_EXIT

; -----------------------------------------------------------------------
; Bottom-of-frame path of the IRQ: advance scroll, step road-segment tables.
; The per-segment template row (SCROLL_SRC, from OBJ_ADDR at L85B7) defines the
; whole road row incl. its MARGIN tiles - grass on land, water tiles ($06-$13)
; on the bridge/water segments - so water is part of the scrolling road map.
IRQ_BOTTOM_SCROLL:
    lda #$00
    sta VIC_BORDER
    sta VIC_BG0
    lda #$01
    sta VIC_BG1
    lda #$08
    sta VIC_BG2
    inc FRAME_FLAG
    lda SPLIT_RASTER
    clc
    adc SCROLL_SPEED
    sta SPLIT_RASTER
    lda D018_ALT
    sta D018_SHADOW
    lda FLAG_FB
    beq L8500
    lda SPAWN_Y
    clc
    adc SCROLL_SPEED
    sta SPAWN_Y

L8500:
    lda VSCROLL_POS
    and #$07
    clc
    adc SCROLL_SPEED
    cmp #$08
    php
    and #$07
    ora #$10
    sta VSCROLL_POS
    sta D011_SHADOW
    plp
    bcs L8518
    jmp L8606

L8518:
    dec ROW_REPEAT
    beq L852A
    lda SCROLL_SRC
    clc
    adc #$20
    sta SCROLL_SRC
    bcc L8527
    inc SCROLL_SRC_HI

L8527:
    jmp L85DD

L852A:
    dec SEG_REPEAT
    beq L853F
    lda SEG_REPEAT_INIT
    sta ROW_REPEAT
    lda SCROLL_SRC_SAVE
    sta SCROLL_SRC
    lda SCROLL_SRC_SAVE_HI
    sta SCROLL_SRC_HI
    beq L853F
    jmp L85DD

L853F:
    lda #$17
    sta STATE_4D10
    dec ROAD_SEG_LEN
    bne L85B7
    lda ROAD_SEG_IDX
    asl a
    tay
    lda SCENE_IDX
    cmp #$13
    bcc L8553
    iny

L8553:
    lda ROAD_SEG_TBL,y
    sta ROAD_SEG_IDX
    tay
    lda ROAD_PTR_LO_TBL,y
    sta ROAD_PTR
    lda ROAD_PTR_HI_TBL,y
    sta ROAD_PTR_HI
    lda ROAD_LEN_TBL,y
    sta ROAD_SEG_LEN
    cpy #$1C
    bne L857C
    inc ROAD_PHASE
    ldx MUX_SLOT_IDX
    bmi L857C
    sec
    ror MUX_SLOT0,x
    dec MUX_SLOT_IDX
    inc FLAG_DD

L857C:
    lda ROAD_PHASE
    and #$03
    sta ROAD_PHASE
    cpy #$0F
    bne L8588
    inc FX_TIMER1

L8588:
    cpy #$1B
    bne L859B
    cmp #$01
    bne L859B
    ldx SCENE_IDX
    cpx #$13
    bcs L8599
    inc FX_TIMER2
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
L8599:
    inc FX_TIMER3

L859B:
    clc
    adc ROAD_COLIDX_TBL,y
    tay
    lda ROAD_BORDER_TBL,y
    sta BORDER_COL_SPLIT
    lda ROAD_MC1_TBL,y
    sta MC_COL1_SPLIT
    lda ROAD_MC2_TBL,y
    sta MC_COL2_SPLIT
    lda SCROLL_SPEED
    lsr a
    clc
    adc #$2F
    sta SPLIT_RASTER

L85B7:
    ldy ROAD_SEG_LEN
    dey
    lda ROAD_FEATURE
    sta PREV_FEATURE
    lda (ROAD_PTR),y
    sta ROAD_FEATURE
    tay
    lda OBJ_ADDR_LO,y
    sta SCROLL_SRC
    sta SCROLL_SRC_SAVE
    lda OBJ_ADDR_HI,y
    sta SCROLL_SRC_HI
    sta SCROLL_SRC_SAVE_HI
    lda OBJ_ROWREP_TBL,y
    sta ROW_REPEAT
    sta SEG_REPEAT_INIT
    lda OBJ_SEGREP_TBL,y
    sta SEG_REPEAT

L85DD:
    inc COPY_BLOCK_FLAG
    lda D018_ALT
    eor #$10
    sta D018_ALT
    sta D018_SHADOW
    lda IRQ_TOGGLE
    eor #$04
    sta IRQ_TOGGLE
    tay
    lda SCROLL_VEC_TBL,y
    sta SCROLL_DST
    lda SCROLL_VEC_TBL_B,y
    sta SCROLL_DST_HI
    lda SCROLL_VEC_TBL_C,y
    sta VEC_SCROLL
    lda SCROLL_VEC_TBL_D,y
    sta VEC_SCROLL_HI

L8606:
    lda #$06
    sta VIC_RASTER
    lda #$01
    sta VIC_IRR
    jsr MUSIC_DRIVER

; -----------------------------------------------------------------------
; Flip the IRQ_HALF top/bottom toggle and restore registers / RTI.
IRQ_EXIT:
    lda IRQ_HALF
    eor #$FF
    sta IRQ_HALF
    pla
    tay
    pla
    tax
    pla
    rti
; -----------------------------------------------------------------------
; SCROLL_VEC_TBL: scroll-dispatch bytes selected by the IRQ_TOGGLE bit.
    .byte $04,$78,$01,$16,$04,$7C,$00,$04

; -----------------------------------------------------------------------
; Draw the playfield border/frame characters into the screen buffers.
DRAW_PLAYFIELD_FRAME:
    lda #$20
    sta ZTMP_09
    lda #$08
    sta ZTMP_0A
    lda #$18
    sta ZTMP_0B
    lda #$AD
    sta ZTMP_0C
    lda #$8D
    sta ZTMP_0D
    lda #$BB
    sta SRC_PTR
    lda #$7B
    sta SRC_PTR_HI
    lda #$E3
    sta DST_PTR
    lda #$7F
    sta DST_PTR_HI
    lda #$00
    sta DST2_PTR
    lda #$04
    sta DST2_PTR_HI
    jsr DRAW_BOX_ROWS
    lda #$BB
    sta SRC_PTR
    lda #$7F
    sta SRC_PTR_HI
    lda #$E3
    sta DST_PTR
    lda #$7B
    sta DST_PTR_HI
    jsr DRAW_BOX_ROWS
    lda #$01
    sta ZTMP_09
    lda #$27
    sta ZTMP_0A
    lda #$B9
    sta ZTMP_0C
    lda #$99
    sta ZTMP_0D
    lda #$9C
    sta SRC_PTR
    lda #$DB
    sta SRC_PTR_HI
    lda #$C4
    sta DST_PTR
    lda #$DB
    sta DST_PTR_HI

; -----------------------------------------------------------------------
; Helper for DRAW_PLAYFIELD_FRAME: stamp a rectangular run of border cells.
DRAW_BOX_ROWS:
    lda ZTMP_0B
    sta ZTMP_08

L868F:
    ldx ZTMP_09

L8691:
    ldy #$00
    lda ZTMP_0C
    sta (DST2_PTR),y
    iny
    lda SRC_PTR
    sta (DST2_PTR),y
    iny
    lda SRC_PTR_HI
    sta (DST2_PTR),y
    iny
    lda ZTMP_0D
    sta (DST2_PTR),y
    iny
    lda DST_PTR
    sta (DST2_PTR),y
    iny
    lda DST_PTR_HI
    sta (DST2_PTR),y
    lda #$06
    jsr PTR_AUX_ADD
    sec
    lda DST_PTR
    sbc #$01
    sta DST_PTR
    bcs L86C0
    dec DST_PTR_HI

L86C0:
    sec
    lda SRC_PTR
    sbc #$01
    sta SRC_PTR
    bcs L86CB
    dec SRC_PTR_HI

L86CB:
    dex
    bne L8691
    sec
    lda DST_PTR
    sbc ZTMP_0A
    sta DST_PTR
    bcs L86D9
    dec DST_PTR_HI

L86D9:
    sec
    lda SRC_PTR
    sbc ZTMP_0A
    sta SRC_PTR
    bcs L86E4
    dec SRC_PTR_HI

L86E4:
    dec ZTMP_08
    bne L868F
    ldy #$00
    lda #$60
    sta (DST2_PTR),y
    jsr PTR_AUX_INC
    rts
; -----------------------------------------------------------------------
; SPEEDCODE_IMAGE: a small 6502 routine kept here as data; run from $2800 RAM.
    .byte $04,$03,$02,$01,$00,$A5,$33,$4A,$90,$07,$A4,$A8,$C0,$05,$F0,$01
    .byte $4A,$A5,$B8,$90,$03,$ED,$09,$4D,$30,$02,$A9,$00,$C9,$F8,$10,$02
    .byte $A9,$F8,$85,$B8,$18,$65,$35,$18,$65,$D7,$85,$D7,$4A,$4A,$4A,$4A
    .byte $38,$E9,$08,$AA,$30,$0A,$E0,$05,$B0,$06,$BD,$F2,$86,$20,$06,$A1
    .byte $C0,$06,$F0,$06,$A5,$FA,$C9,$02,$D0,$05,$A5,$33,$4A,$90,$2B,$A6
    .byte $35,$F0,$25,$AC,$0A,$4D,$98,$18,$65,$B0,$AA,$30,$0E,$F0,$19,$C0
    .byte $00,$F0,$14,$C5,$35,$90,$11,$F0,$0F,$B0,$0C,$C0,$00,$F0,$06,$65
    .byte $35,$F0,$02,$10,$03,$E8,$E8,$CA,$86,$B0,$A5,$B0,$08,$18,$65,$D6
    .byte $85,$D6,$B0,$05,$28,$30,$05,$10,$09,$28,$30,$06,$A5,$DA,$49,$40
    .byte $85,$DA,$60

; -----------------------------------------------------------------------
; Decompress a custom multicolour character set from a byte-stream.
UNPACK_CHARSET:
    lda #$00
    sta DST_PTR
    lda #$54
    sta DST_PTR_HI

L878D:
    lda DST_PTR
    sta SRC_PTR
    sta DST2_PTR
    lda DST_PTR_HI
    sta SRC_PTR_HI
    sta DST2_PTR_HI
    lda #$00
    sta ZTMP_09
    jsr STREAM_NEXT_BYTE
    bmi L87A7
    bne L87BC
    jmp L888E

L87A7:
    ldy #$00

L87A9:
    jsr STREAM_NEXT_BYTE
    sta (SRC_PTR),y
    iny
    jsr MIRROR_BYTE
    sta (SRC_PTR),y
    iny
    iny
    cpy #$3F
    bne L87A9
    beq L87DC

L87BC:
    sta ZTMP_30
    jsr STREAM_NEXT_BYTE
    sta BLIT_COUNT

L87C3:
    lda BLIT_COUNT
    sta BLIT_ROWS
    ldy #$00

L87C9:
    jsr STREAM_NEXT_BYTE
    sta (SRC_PTR),y
    iny
    iny
    iny
    dec BLIT_ROWS
    bne L87C9
    jsr PTR_SRC_INC
    dec ZTMP_30
    bne L87C3

L87DC:
    jsr STREAM_NEXT_BYTE
    bmi L8847
    bne L87EB
    lda #$40
    jsr PTR_DST_ADD
    jmp L878D

L87EB:
    lda #$40
    sta ZTMP_08

L87EF:
    ldy #$00
    lda (DST_PTR),y
    ldy #$40
    sta (DST_PTR),y
    cpx #$02
    beq L8801
    bcc L8805
    ldy #$C0
    sta (DST_PTR),y

L8801:
    ldy #$80
    sta (DST_PTR),y

L8805:
    jsr PTR_DST_INC
    dec ZTMP_08
    bne L87EF
    stx ZTMP_09

L880E:
    jsr STREAM_NEXT_BYTE
    beq L881C
    tay
    jsr STREAM_NEXT_BYTE
    sta (DST_PTR),y
    jmp L880E

L881C:
    jsr STREAM_NEXT_BYTE
    bne L8835
    ldx ZTMP_09

L8823:
    lda #$40
    jsr PTR_AUX_ADD
    dex
    beq L87DC
    bmi L87DC
    lda #$40
    jsr PTR_DST_ADD
    jmp L8823

L8835:
    tay

L8836:
    jsr STREAM_NEXT_BYTE
    beq L881C
    sta (DST2_PTR),y
    iny
    jsr MIRROR_BYTE
    sta (DST2_PTR),y
    iny
    iny
    bne L8836

L8847:
    ldy #$00

L8849:
    lda (DST_PTR),y
    pha
    iny
    lda (DST_PTR),y
    pha
    iny
    lda (DST_PTR),y
    pha
    tya
    clc
    adc #$3E
    tay
    pla
    jsr MIRROR_BYTE
    sta (DST_PTR),y
    iny
    pla
    jsr MIRROR_BYTE
    sta (DST_PTR),y
    iny
    pla
    jsr MIRROR_BYTE
    sta (DST_PTR),y
    tya
    sec
    sbc #$3F
    tay
    cpy #$3F
    bne L8849
    ldy #$00
    pha

L8879:
    lda (DST_PTR),y
    pha
    iny
    bpl L8879
    pla

L8880:
    pla
    jsr MIRROR_BYTE
    sta (DST_PTR),y
    iny
    bne L8880
    inc DST_PTR_HI
    jmp L878D

L888E:
    jsr STREAM_NEXT_BYTE
    bne L8894
    rts

L8894:
    sta ZTMP_0B
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0C

L889B:
    lda #$C0
    sta SRC_PTR
    lda #$53
    sta SRC_PTR_HI
    ldx ZTMP_0B
    inc ZTMP_0B
    cpx ZTMP_0C
    beq L888E

L88AB:
    lda #$40
    jsr PTR_SRC_ADD
    dex
    bne L88AB
    ldy #$00

L88B5:
    stx ZTMP_09
    stx ZTMP_0A
    lda (SRC_PTR),y
    ldx #$04

L88BD:
    lsr a
    ror ZTMP_09
    dex
    bne L88BD
    sta (SRC_PTR),y
    iny
    lda (SRC_PTR),y
    ldx #$04

L88CA:
    lsr a
    ror ZTMP_0A
    dex
    bne L88CA
    ora ZTMP_09
    sta (SRC_PTR),y
    iny
    lda ZTMP_0A
    sta (SRC_PTR),y
    iny
    cpy #$3F
    bne L88B5
    beq L889B

; -----------------------------------------------------------------------
; Convert a moving object's world position to a screen cell and stage its sprite.
OBJ_CALC_SCREEN_POS:
    ldx OBJ_IDX
    clc
    lda BIT_MASK
    and SPR_XMSB
    beq L88EA
    sec

L88EA:
    php
    ldy OBJ_IDX2
    lda a:SPR_X_SHADOW,y
    plp
    ror a
    lsr a
    sec
    sbc #$05
    lsr a
    cmp #$04
    bcc L88FF
    cmp #$24
    bcc L8904

L88FF:
    lda #$FF
    jmp L8971

L8904:
    pha
    sta OBJ_TBLB3,x
    lda a:SPR_Y_SHADOW,y
    sec
    sbc #$28
    bcs L8919
    lda BIT_MASK_INV
    and HIT_ACCUM
    ldy #$00
    beq L8930

L8919:
    cmp #$C1
    bcc L8926
    lda BIT_MASK_INV
    and HIT_ACCUM
    ldy #$2C
    bne L8930

L8926:
    lsr a
    lsr a
    and #$FE
    tay
    lda BIT_MASK
    ora HIT_ACCUM

L8930:
    sta HIT_ACCUM
    lda ROWADDR_LO,y
    sta SRC_PTR
    lda ROWADDR_HI,y
    sta SRC_PTR_HI
    tya
    lsr a
    sta OBJ_TBLBB,x
    pla
    tay
    lda (SRC_PTR),y
    pha
    iny
    lda (SRC_PTR),y
    pha
    iny
    lda (SRC_PTR),y
    ldy #$02
    sty ZTMP_08

L8952:
    ldy #$00

L8954:
    cmp OBJ_DIST_TBL,y
    bcc L8960
    iny
    cpy #$0D
    bcc L8954
    ldy #$00

L8960:
    tya
    dec ZTMP_08
    bmi L8977
    beq L896A
    sta OBJ_TBL6B,x

L896A:
    sta OBJ_TBL73,x
    pla
    jmp L8952

L8971:
    sta OBJ_TBL6B,x
    sta OBJ_TBL73,x

L8977:
    sta OBJ_TBL63,x
    rts
; -----------------------------------------------------------------------
; OBJ_DIST_TBL: object distance thresholds, followed by aux data (computed jumps).
    .byte $04,$08,$14,$1C,$24,$30,$38,$40,$72,$7A,$A7,$AD,$B7,$A9,$00,$85
    .byte $12,$A9,$78,$85,$13,$A9,$0F,$D0,$0A,$A9,$C0,$85,$12,$A9,$7B,$85
    .byte $13,$A9,$F3,$99,$CB,$00,$A9,$00,$A0,$04,$06,$08,$90,$04,$A9,$08
    .byte $A0,$14,$85,$08,$84,$09,$4A,$4A,$9D,$7B,$4D,$E0,$06,$F0,$1D,$B5
    .byte $A2,$F0,$10,$C9,$18,$F0,$17,$18,$AD,$04,$4D,$69,$03,$C9,$1E,$90
    .byte $0D,$B0,$09,$A5,$4A,$C9,$13,$90,$03,$A9,$12,$2C,$A9,$03,$8D,$04
    .byte $4D,$A8,$C8,$C0,$23,$B0,$28,$B1,$12,$C5,$08,$90,$F5,$C5,$09,$B0
    .byte $F1,$8C,$04,$4D,$98,$A4,$07,$0A,$18,$69,$06,$0A,$0A,$99,$CA,$00
    .byte $A5,$05,$90,$04,$05,$DA,$D0,$04,$49,$FF,$25,$DA,$85,$DA,$18,$60

; -----------------------------------------------------------------------
; Compute the object's on-screen sprite offset and stage the hardware sprite.
OBJ_CALC_SPRITE_DELTA:
    ldy OBJ_IDX2
    ldx #$00
    lda #$01
    sta ZTMP_0A
    lda BIT_MASK
    and SPR_XMSB
    clc
    beq L8A1B
    sec

L8A1B:
    lda a:SPR_X_SHADOW,y
    ror a
    sta ZTMP_0C
    lda a:SPR_Y_SHADOW,y
    sta ZTMP_0D
    ldy #$00

L8A28:
    lda ZTMP_0A
    and SPR_XMSB
    clc
    beq L8A30
    sec

L8A30:
    lda SPR_X_SHADOW,x
    ror a
    sec
    sbc ZTMP_0C
    bpl L8A47
    eor #$FF
    clc
    adc #$01
    cmp #$40
    bcc L8A43
    lda #$3F

L8A43:
    ora #$40
    bne L8A4D

L8A47:
    cmp #$40
    bcc L8A4D
    lda #$3F

L8A4D:
    asl a
    sta a:SPR_STAGE,y
    iny
    sec
    lda SPR_Y_SHADOW,x
    sbc ZTMP_0D
    bpl L8A68
    eor #$FF
    clc
    adc #$01
    cmp #$80
    bcc L8A64
    lda #$7F

L8A64:
    ora #$80
    bne L8A6E

L8A68:
    cmp #$80
    bcc L8A6E
    lda #$7F

L8A6E:
    sta a:SPR_STAGE,y
    iny
    inx
    inx
    asl ZTMP_0A
    bcc L8A28
    rts

; -----------------------------------------------------------------------
; Trampoline: JMP (VEC_OBJMOVE) into the current object-type move handler.
OBJ_MOVE_DISPATCH:
    jmp (VEC_OBJMOVE)

; -----------------------------------------------------------------------
; Trampoline: JMP (ZVEC_MOVE) into a per-object-type routine.
OBJ_VEC1_DISPATCH:
    jmp ($0071)

; -----------------------------------------------------------------------
; Trampoline: JMP (ZVEC_DRAW) into a per-object-type routine.
OBJ_VEC2_DISPATCH:
    jmp ($0073)

; -----------------------------------------------------------------------
; Moving-object engine (per frame).
PROCESS_OBJECTS:
    ldx #$07
    lda #$80
    sta BIT_MASK
    eor #$FF
    sta BIT_MASK_INV

L8A8C:
    stx OBJ_IDX
    txa
    asl a
    tay
    sty OBJ_IDX2
    lda #$00
    sta STATE_4D07
    sta STATE_4D08
    lda OBJMOVE_VEC_LO,y
    sta VEC_OBJMOVE
    lda OBJMOVE_VEC_HI,y
    sta VEC_OBJMOVE_HI
    lda OBJ_TYPE,x
    bpl L8AB0
    jsr OBJ_MOVE_DISPATCH
    bcc L8AFF

L8AB0:
    lda OBJ_TYPE,x
    sta ZTMP_0F
    asl a
    asl a
    tay
    ldx #$00

L8AB9:
    lda OBJINIT_PARAM_TBL,y
    sta ZVEC_MOVE,x
    iny
    inx
    cpx #$04
    bne L8AB9
    jsr OBJ_CALC_SCREEN_POS
    jsr OBJ_CALC_SPRITE_DELTA
    ldy OBJ_IDX2
    ldx OBJ_IDX
    jsr OBJ_VEC1_DISPATCH
    ldx OBJ_IDX
    lda OBJ_ANIM,x
    asl a
    tay
    lda (ZVEC_DRAW),y
    pha
    iny
    lda (ZVEC_DRAW),y
    sta ZVEC_DRAW_HI
    pla
    sta ZVEC_DRAW
    ldy OBJ_IDX2
    jsr OBJ_VEC2_DISPATCH
    ldy OBJ_IDX2
    lda HIT_ACCUM
    ldx SPR_Y_SHADOW,y
    cpx #$37
    bcc L8AFA
    cpx #$F0
    bcs L8AFA
    ora BIT_MASK
    bne L8AFC

L8AFA:
    and BIT_MASK_INV

L8AFC:
    sta HIT_ACCUM

L8AFF:
    ldx OBJ_IDX

L8B01:
    lsr BIT_MASK
    sec
    ror BIT_MASK_INV
    dex
    bmi L8B1B
    cpx MUX_SLOT0
    beq L8B01
    cpx MUX_SLOT1
    beq L8B01
    cpx MUX_SLOT2
    beq L8B01
    jmp L8A8C

L8B1B:
    lda HIT_GROUP0
    and HIT_ACCUM
    and HIT_GROUP1
    sta HIT_MASK_A
    lda HIT_GROUP2
    and HIT_ACCUM
    sta HIT_MASK_B
    rts
; -----------------------------------------------------------------------
; OBJMOVE_VEC_LO/HI + OBJINIT_PARAM_TBL, then object / hero state-machine
; handlers stored as data (reached through VEC_OBJMOVE / VEC_STATE).
    .byte $AF,$8B,$D4,$8B,$5B,$8C,$5E,$8C,$5B,$8C,$5E,$8C,$90,$8C,$C2,$8C
    .byte $8E,$9A,$AA,$90,$8E,$9A,$AA,$90,$8E,$9A,$AA,$90,$8E,$9A,$AA,$90
    .byte $2E,$8B,$4D,$92,$F1,$99,$AA,$92,$F1,$99,$A2,$93,$80,$9A,$38,$8F
    .byte $2E,$8B,$27,$90,$B0,$9A,$48,$94,$34,$9B,$78,$94,$88,$9B,$FB,$94
    .byte $C5,$9A,$49,$95,$B3,$9A,$49,$95,$A8,$9A,$6D,$95,$A8,$9A,$6D,$95
    .byte $A8,$9A,$6D,$95,$02,$9B,$BE,$95,$B6,$9A,$EB,$95,$B9,$9A,$EB,$95
    .byte $2E,$8B,$24,$96,$2E,$8B,$6F,$96,$2E,$8B,$EC,$96,$2E,$8B,$24,$96
    .byte $A1,$9A,$1E,$97,$2E,$8B,$6B,$97,$2F,$9B,$A8,$97,$62,$9B,$FF,$94
    .byte $A5,$A3,$C9,$07,$F0,$1A,$C9,$09,$F0,$13,$C9,$18,$F0,$0C,$A5,$A5
    .byte $C9,$12,$F0,$03,$4C,$32,$8E,$A9,$1A,$2C,$A9,$19,$2C,$A9,$0A,$2C
    .byte $A9,$08,$4C,$2D,$8D,$A5,$A2,$85,$08,$38,$66,$A2,$A9,$00,$85,$FB
    .byte $A4,$49,$88,$F0,$17,$88,$F0,$54,$88,$88,$F0,$50,$88,$D0,$06,$A5
    .byte $44,$C9,$14,$F0,$53,$A5,$08,$85,$A2,$4C,$32,$8E,$A5,$44,$C9,$13
    .byte $F0,$06,$A5,$42,$C9,$11,$D0,$0A,$A9,$02,$20,$06,$A1,$A9,$64,$8D
    .byte $10,$4D,$CE,$10,$4D,$D0,$DE,$EE,$10,$4D,$D0,$2F,$A5,$44,$C9,$0F
    .byte $F0,$0C,$C9,$13,$B0,$CF,$A4,$FC,$F0,$04,$C6,$FC,$F0,$26,$C9,$02
    .byte $90,$1F,$C9,$0E,$B0,$BF,$A5,$DD,$D0,$14,$F0,$B9,$AD,$17,$4D,$F0
    .byte $DB,$30,$D9,$38,$6E,$17,$4D,$2C,$A9,$18,$2C,$A9,$00,$2C,$A9,$07
    .byte $2C,$A9,$11,$2C,$A9,$09,$8D,$04,$4D,$4C,$2D,$8D,$A9,$0C,$2C,$A9
    .byte $0D,$85,$08,$A5,$A8,$30,$27,$A0,$0E,$A5,$44,$C9,$0E,$F0,$0E,$C9
    .byte $14,$F0,$0A,$20,$0E,$A1,$29,$03,$18,$65,$08,$D0,$0B,$A0,$0B,$E0
    .byte $03,$F0,$03,$A9,$13,$2C,$A9,$12,$8C,$25,$D0,$4C,$2D,$8D,$4C,$32
    .byte $8E,$A5,$49,$C9,$01,$F0,$15,$C9,$03,$F0,$20,$C9,$05,$D0,$0A,$A5
    .byte $A3,$C9,$18,$D0,$04,$A5,$9B,$D0,$12,$4C,$32,$8E,$A5,$A3,$C9,$04
    .byte $B0,$F7,$A5,$9B,$C9,$02,$D0,$F1,$A9,$05,$2C,$A9,$06,$8D,$05,$4D
    .byte $4C,$2D,$8D,$A5,$49,$F0,$46,$C9,$05,$F0,$3F,$C9,$06,$F0,$41,$B0
    .byte $42,$A5,$A3,$C9,$04,$B0,$0A,$A5,$9B,$C9,$02,$F0,$4C,$C9,$05,$F0
    .byte $48,$AD,$0B,$4D,$F0,$24,$A5,$49,$C9,$02,$90,$1E,$C9,$05,$B0,$1A
    .byte $A5,$A3,$C9,$07,$D0,$30,$A5,$F6,$F0,$2C,$A5,$C7,$30,$28,$A5,$C6
    .byte $29,$7F,$C9,$46,$B0,$20,$C6,$F6,$90,$19,$4C,$32,$8E,$A9,$15,$2C
    .byte $A9,$17,$2C,$A9,$16,$48,$A5,$49,$29,$04,$09,$01,$85,$49,$38,$66
    .byte $A8,$68,$2C,$A9,$1B,$2C,$A9,$0B,$2C,$A9,$04,$2C,$A9,$14,$95,$A2
    .byte $A8,$B9,$1C,$8F,$48,$29,$03,$0A,$9D,$43,$4D,$49,$FF,$18,$69,$02
    .byte $9D,$3B,$4D,$68,$4A,$4A,$48,$F0,$02,$09,$FC,$9D,$4B,$4D,$68,$4A
    .byte $4A,$F0,$02,$09,$F0,$9D,$53,$4D,$B9,$AC,$8E,$9D,$93,$4D,$B9,$E4
    .byte $8E,$9D,$2B,$4D,$9D,$23,$4D,$B9,$00,$8F,$95,$9A,$B9,$90,$8E,$85
    .byte $08,$29,$3F,$9D,$9B,$4D,$A5,$05,$06,$08,$90,$05,$0D,$1F,$4D,$D0
    .byte $05,$49,$FF,$2D,$1F,$4D,$8D,$1F,$4D,$A5,$05,$06,$08,$90,$05,$0D
    .byte $21,$4D,$D0,$05,$49,$FF,$2D,$21,$4D,$8D,$21,$4D,$B9,$C8,$8E,$85
    .byte $08,$29,$0F,$9D,$27,$D0,$A5,$05,$06,$08,$B0,$05,$0D,$1C,$D0,$D0
    .byte $05,$49,$FF,$2D,$1C,$D0,$8D,$1C,$D0,$A5,$05,$06,$08,$90,$05,$0D
    .byte $1D,$D0,$D0,$05,$49,$FF,$2D,$1D,$D0,$8D,$1D,$D0,$A5,$05,$06,$08
    .byte $90,$05,$0D,$17,$D0,$D0,$05,$49,$FF,$2D,$17,$D0,$8D,$17,$D0,$B9
    .byte $74,$8E,$85,$08,$29,$0F,$9D,$A3,$4D,$A4,$07,$06,$08,$90,$0C,$06
    .byte $08,$06,$08,$A5,$34,$C9,$03,$90,$0C,$B0,$13,$06,$08,$A9,$00,$90
    .byte $13,$06,$08,$B0,$09,$20,$94,$89,$BD,$53,$4D,$4C,$13,$8E,$20,$88
    .byte $89,$BD,$4B,$4D,$B0,$1D,$95,$B2,$A9,$00,$95,$AA,$9D,$33,$4D,$9D
    .byte $5B,$4D,$9D,$8B,$4D,$9D,$83,$4D,$9D,$AB,$4D,$20,$DB,$99,$20,$5E
    .byte $8E,$38,$60,$A4,$07

; -----------------------------------------------------------------------
; Clear moving-object slot X.
INIT_OBJECT_SLOT:
    lda BIT_MASK_INV
    and SPR_XMSB
    sta SPR_XMSB
    lda #$00
    sta a:SPR_X_SHADOW,y
    sta a:SPR_Y_SHADOW,y
    sta OBJ_TBLAB,x
    lda #$FF
    sta OBJ_TYPE,x
    lda #$95
    jsr SET_SPRITE_PTR
    lda BIT_MASK_INV
    and HIT_GROUP0
    sta HIT_GROUP0
    lda BIT_MASK_INV
    and HIT_GROUP2
    sta HIT_GROUP2
    lda BIT_MASK_INV
    and HIT_MASK_A
    sta HIT_MASK_A
    lda BIT_MASK_INV
    and HIT_MASK_B
    sta HIT_MASK_B
    lda BIT_MASK_INV
    and HIT_ACCUM
    sta HIT_ACCUM
    clc
    rts
; -----------------------------------------------------------------------
; State-machine handler code and jump tables (object / hero behaviour), as data.
    .byte $44,$04,$04,$04,$04,$66,$04,$04,$00,$86,$04,$06,$86,$82,$86,$86
    .byte $86,$64,$94,$94,$00,$04,$04,$04,$52,$00,$04,$04,$D0,$D0,$D0,$D0
    .byte $10,$CC,$CE,$58,$58,$CC,$48,$4C,$CC,$D2,$CC,$CC,$CA,$5A,$D0,$D0
    .byte $18,$0C,$10,$18,$D4,$08,$02,$46,$20,$20,$20,$20,$07,$15,$16,$1E
    .byte $20,$1C,$01,$0E,$15,$14,$11,$14,$11,$0A,$1C,$16,$15,$10,$11,$15
    .byte $20,$06,$10,$0B,$2A,$2A,$2A,$2A,$00,$04,$2A,$0A,$81,$2A,$0E,$28
    .byte $0A,$0A,$03,$0A,$08,$C3,$2F,$2A,$08,$08,$06,$08,$2A,$81,$20,$0A
    .byte $5F,$5C,$5D,$5E,$8C,$50,$83,$68,$6D,$72,$8D,$90,$71,$78,$74,$73
    .byte $7B,$93,$80,$86,$64,$64,$8F,$64,$75,$77,$91,$92,$04,$09,$09,$09
    .byte $03,$03,$01,$03,$03,$02,$02,$01,$00,$00,$00,$00,$00,$01,$00,$01
    .byte $01,$05,$03,$02,$02,$00,$01,$01,$D6,$DA,$DA,$DA,$00,$00,$00,$FC
    .byte $00,$73,$00,$00,$AB,$CA,$CA,$BF,$DD,$00,$CD,$B9,$00,$00,$00,$00
    .byte $C6,$00,$00,$00,$58,$8F,$84,$8F,$04,$90,$0D,$90,$00,$04,$01,$38
    .byte $66,$A3,$A9,$00,$85,$FF,$60,$20,$0E,$A1,$29,$3F,$8D,$5C,$4D,$A9
    .byte $01,$85,$FF,$60,$A0,$1C,$20,$7A,$AA,$A5,$CD,$C9,$09,$90,$E0,$4C
    .byte $E9,$8F,$C6,$9B,$A9,$00,$85,$AB,$A9,$02,$8D,$54,$4D,$A5,$FF,$48
    .byte $A9,$FF,$85,$FF,$68,$10,$08,$A9,$01,$8D,$5C,$4D,$20,$9D,$A2,$60
    .byte $AD,$AC,$4D,$D0,$DD,$A5,$FF,$10,$03,$4C,$FD,$8F,$D0,$03,$20,$4B
    .byte $8F,$A5,$C6,$0A,$08,$C9,$02,$90,$1D,$28,$90,$0C,$AD,$44,$4D,$F0
    .byte $03,$CE,$44,$4D,$A9,$FF,$D0,$11,$AD,$44,$4D,$C9,$02,$B0,$03,$EE
    .byte $44,$4D,$A9,$01,$D0,$03,$28,$A9,$00,$85,$AB,$A5,$D7,$38,$E9,$3C
    .byte $E5,$CD,$F0,$31,$B0,$03,$A9,$FF,$2C,$A9,$01,$8D,$54,$4D,$AC,$44
    .byte $4D,$B9,$40,$8F,$8D,$34,$4D,$AD,$17,$D0,$88,$D0,$03,$05,$05,$2C
    .byte $25,$10,$8D,$17,$D0,$AD,$54,$4D,$48,$20,$D8,$99,$68,$20,$FB,$98
    .byte $A6,$06,$4C,$9D,$A2,$A9,$00,$F0,$D2,$A9,$00,$85,$AB,$4C,$EC,$8F
    .byte $A5,$C7,$30,$E1,$C6,$9B,$4C,$4B,$8F,$C6,$9B,$C6,$AB,$A9,$FA,$85
    .byte $CD,$A5,$05,$05,$DA,$85,$DA,$A9,$20,$85,$CC,$20,$A8,$AA,$A0,$1A
    .byte $4C,$7A,$AA,$2F,$90,$40,$90,$4B,$90,$58,$90,$A9,$04,$85,$9A,$A9
    .byte $01,$20,$76,$90,$E9,$0C,$20,$96,$90,$4C,$64,$90,$A9,$00,$20,$76
    .byte $90,$20,$96,$90,$4C,$64,$90,$A9,$02,$20,$76,$90,$20,$96,$90,$E9
    .byte $15,$4C,$64,$90,$A9,$03,$20,$76,$90,$E9,$0C,$20,$96,$90,$E9,$15
    .byte $85,$CB,$A6,$06,$C6,$9A,$20,$D8,$99,$AD,$15,$D0,$09,$01,$8D,$15
    .byte $D0,$60,$8D,$33,$4D,$AD,$15,$D0,$29,$FE,$8D,$15,$D0,$A5,$DA,$4A
    .byte $4A,$A5,$CC,$6A,$26,$08,$AE,$44,$4D,$18,$7D,$93,$90,$38,$60,$03
    .byte $05,$08,$66,$08,$2A,$08,$85,$CA,$A5,$DA,$4A,$28,$2A,$85,$DA,$A9
    .byte $07,$18,$65,$CD,$38,$60,$BE,$90,$C9,$90,$DD,$90,$E3,$90,$21,$91
    .byte $64,$91,$AB,$91,$E2,$91,$04,$92,$38,$92,$8E,$AC,$4D,$4C,$DC,$91
    .byte $C6,$9B,$4C,$65,$99,$A2,$FF,$86,$B3,$AD,$74,$4D,$D0,$06,$C6,$9B
    .byte $EE,$54,$4D,$E8,$86,$AB,$4C,$19,$91,$A5,$A1,$D0,$E5,$F0,$E1,$A9
    .byte $00,$CD,$64,$4D,$D0,$0A,$CD,$74,$4D,$D0,$05,$CD,$6C,$4D,$F0,$2D
    .byte $20,$06,$A1,$A9,$01,$85,$B3,$A5,$CD,$C9,$A0,$F0,$C3,$A2,$00,$AD
    .byte $64,$4D,$F0,$0E,$C9,$03,$F0,$0B,$C9,$04,$F0,$07,$C9,$05,$F0,$03
    .byte $CA,$CA,$E8,$86,$AB,$A6,$06,$20,$65,$99,$4C,$00,$99,$A5,$34,$F0
    .byte $18,$C9,$01,$F0,$19,$CE,$08,$4D,$A0,$0F,$20,$EE,$A0,$A9,$00,$38
    .byte $E5,$35,$85,$B3,$C6,$B3,$4C,$DC,$91,$A9,$01,$20,$06,$A1,$A9,$FD
    .byte $85,$B3,$A9,$01,$85,$AB,$AE,$64,$4D,$F0,$CA,$AE,$74,$4D,$F0,$C5
    .byte $A9,$00,$85,$AB,$A6,$CD,$E0,$90,$B0,$BB,$85,$B3,$C6,$9B,$10,$B5
    .byte $A5,$10,$8D,$20,$4D,$A5,$B8,$8D,$54,$4D,$A5,$C7,$30,$10,$C9,$32
    .byte $B0,$0C,$C9,$1E,$90,$0C,$A5,$C6,$29,$7F,$C9,$01,$90,$10,$E6,$9B
    .byte $D0,$09,$C6,$9B,$A9,$04,$85,$A0,$8D,$05,$4D,$EE,$07,$4D,$CE,$08
    .byte $4D,$A5,$CD,$C9,$65,$B0,$0D,$38,$A9,$00,$E5,$35,$10,$06,$C9,$F8
    .byte $F0,$02,$85,$B3,$4C,$DC,$91,$A5,$C7,$30,$1C,$C9,$31,$B0,$DC,$C9
    .byte $27,$90,$1D,$A5,$C6,$29,$7F,$C9,$01,$B0,$D0,$38,$66,$A9,$EE,$54
    .byte $4D,$E6,$B3,$C6,$9B,$D0,$C4,$29,$7F,$C9,$35,$90,$03,$EE,$07,$4D
    .byte $A6,$B8,$CA,$8E,$54,$4D,$A6,$06,$20,$65,$99,$4C,$F3,$97,$A9,$58
    .byte $85,$FB,$85,$CC,$A9,$FD,$25,$DA,$85,$DA,$A5,$CD,$C9,$F0,$A9,$00
    .byte $90,$04,$C6,$9B,$85,$FB,$CE,$5C,$4D,$D0,$02,$85,$9B,$4C,$65,$99
    .byte $A9,$DC,$85,$FB,$85,$CC,$A9,$FD,$25,$DA,$85,$DA,$A5,$CD,$C9,$10
    .byte $B0,$05,$18,$69,$0C,$85,$CD,$A5,$49,$C9,$03,$D0,$0D,$A9,$04,$85
    .byte $9B,$A2,$00,$86,$FB,$A6,$06,$4C,$65,$99,$AD,$03,$D0,$C9,$F0,$90
    .byte $F4,$66,$A3,$60,$A9,$15,$C5,$45,$F0,$02,$D6,$9A,$D6,$9A,$A9,$00
    .byte $85,$CD,$8D,$7C,$4D,$8D,$AC,$4D,$60,$55,$92,$60,$92,$76,$92,$A4
    .byte $92,$C6,$B9,$A5,$B9,$C9,$0A,$D0,$23,$66,$A9,$60,$A5,$A0,$C9,$01
    .byte $F0,$0A,$C9,$04,$F0,$06,$A5,$9B,$C9,$06,$90,$02,$C6,$A1,$A5,$B9
    .byte $10,$0A,$E6,$B9,$A5,$B9,$C9,$14,$D0,$02,$C6,$A1,$18,$65,$CD,$85
    .byte $D9,$A5,$CC,$85,$D8,$A5,$DA,$29,$02,$F0,$06,$A9,$80,$05,$DA,$D0
    .byte $04,$A9,$7F,$25,$DA,$85,$DA,$A5,$A3,$C9,$04,$90,$02,$66,$A9,$60
    .byte $A9,$0A,$85,$B9,$D0,$D4,$B6,$92,$D5,$92,$EE,$92,$12,$93,$3E,$93
    .byte $68,$93,$AD,$79,$4D,$D0,$03,$8D,$05,$4D,$C9,$09,$D0,$0D,$8D,$05
    .byte $4D,$66,$A8,$EE,$C9,$4D,$A9,$03,$85,$49,$60,$20,$79,$99,$4C,$F7
    .byte $86,$A5,$A9,$10,$14,$A9,$00,$8D,$89,$4D,$8D,$0E,$4D,$85,$B0,$85
    .byte $B8,$C6,$A0,$A9,$02,$85,$E3,$85,$49,$60,$E6,$D7,$A5,$D7,$C9,$D1
    .byte $90,$1B,$C6,$A0,$A9,$FF,$A6,$A3,$F0,$13,$CA,$F0,$09,$CA,$F0,$03
    .byte $85,$F7,$60,$85,$F9,$60,$18,$A5,$F6,$69,$03,$85,$F6,$60,$A5,$A9
    .byte $C9,$04,$D0,$08,$A5,$A1,$C9,$01,$D0,$02,$C6,$A0,$A9,$0A,$18,$65
    .byte $CD,$85,$D7,$A5,$CC,$85,$D6,$A5,$DA,$29,$02,$F0,$06,$A9,$40,$05
    .byte $DA,$D0,$04,$A9,$BF,$25,$DA,$85,$DA,$60,$A5,$D7,$E9,$0A,$C5,$CD
    .byte $90,$06,$C6,$D7,$C6,$D7,$B0,$DB,$A2,$00,$86,$E3,$E8,$86,$49,$38
    .byte $66,$A8

; -----------------------------------------------------------------------
; Start the 3-voice "Peter Gunn" theme.
MUSIC_START_THEME:
    jsr SOUND_SILENCE
    ldy #$02
    jsr SOUND_REQ_V1
    ldy #$04
    jsr SOUND_REQ_V0B
    ldy #$06
    jmp SOUND_REQ_V2
; -----------------------------------------------------------------------
; More state handlers and jump tables (UPDATE_SCENE_SELECT family), as data.
    .byte $A5,$D7,$C9,$23,$90,$04,$C9,$DC,$90,$03,$EE,$89,$4D,$A5,$33,$4A
    .byte $90,$1D,$A9,$07,$CE,$0E,$4D,$10,$03,$8D,$0E,$4D,$A4,$B0,$10,$04
    .byte $AD,$0E,$4D,$0A,$38,$ED,$0E,$4D,$A8,$B9,$9A,$93,$20,$DB,$99,$4C
    .byte $00,$99,$00,$09,$05,$0B,$02,$0A,$04,$08,$A8,$93,$08,$94,$43,$94
    .byte $AD,$79,$4D,$C9,$09,$D0,$0D,$E6,$A0,$EE,$C9,$4D,$8D,$05,$4D,$A9
    .byte $03,$85,$49,$60,$A9,$15,$C5,$44,$F0,$0A,$C5,$45,$D0,$3C,$A5,$44
    .byte $C9,$0F,$D0,$36,$AD,$B9,$4D,$C9,$13,$90,$2F,$8D,$05,$4D,$A0,$00
    .byte $8C,$61,$4D,$C9,$19,$F0,$05,$90,$02,$88,$88,$C8,$8C,$0A,$4D,$A4
    .byte $A3,$C9,$07,$D0,$05,$8C,$AC,$4D,$E6,$CD,$A0,$00,$A5,$34,$C9,$02
    .byte $F0,$05,$90,$02,$88,$88,$C8,$8C,$09,$4D,$20,$8F,$99,$4C,$F7,$86
    .byte $A5,$49,$C9,$05,$F0,$33,$A5,$35,$49,$FF,$18,$69,$01,$85,$B8,$AD
    .byte $79,$4D,$D0,$0A,$38,$66,$A8,$A9,$01,$85,$49,$4C,$02,$94,$C9,$02
    .byte $D0,$D8,$C6,$A0,$A9,$04,$85,$49,$4A,$8D,$81,$4D,$A9,$00,$8D,$CB
    .byte $4D,$8D,$89,$4D,$8D,$05,$4D,$F0,$C1,$E6,$A0,$A9,$22,$4C,$22,$93
    .byte $4E,$94,$56,$94,$71,$94,$A9,$01,$8D,$AC,$4D,$4C,$F3,$97,$EE,$08
    .byte $4D,$A5,$C7,$30,$11,$C9,$04,$B0,$0D,$A9,$00,$38,$E5,$35,$95,$B2
    .byte $CE,$08,$4D,$CE,$08,$4D,$4C,$F3,$97,$C6,$9B,$A2,$01,$86,$B3,$60
    .byte $00,$99,$82,$94,$7E,$94,$C6,$9A,$D0,$11,$20,$B1,$94,$A5,$B3,$85
    .byte $B2,$A5,$C7,$10,$06,$29,$7F,$C9,$28,$90,$26,$A9,$06,$8D,$27,$D0
    .byte $A5,$DA,$4A,$4A,$08,$2A,$28,$2A,$85,$DA,$A5,$CC,$18,$69,$04,$85
    .byte $CA,$90,$06,$A5,$05,$05,$DA,$85,$DA,$A5,$CD,$18,$69,$0F,$85,$CB
    .byte $60,$C9,$14,$B0,$0D,$A0,$0C,$20,$82,$AA,$C6,$9A,$A5,$A8,$10,$02
    .byte $C6,$9B,$A9,$0A,$8D,$27,$D0,$A5,$C6,$10,$14,$A9,$F6,$85,$AA,$A5
    .byte $CC,$38,$E9,$02,$85,$CA,$B0,$1A,$A5,$DA,$4A,$0A,$85,$DA,$60,$A9
    .byte $0A,$85,$AA,$A5,$CC,$18,$69,$0A,$85,$CA,$90,$06,$A5,$DA,$05,$05
    .byte $85,$DA,$60,$15,$95,$24,$95,$03,$95,$24,$95,$A9,$FB,$48,$A5,$BC
    .byte $30,$03,$A9,$02,$2C,$A9,$FE,$85,$B1,$A9,$78,$D0,$05,$A9,$ED,$48
    .byte $A9,$50,$C5,$D9,$90,$02,$66,$A9,$68,$4C,$FB,$98,$C6,$A1,$A5,$B0
    .byte $85,$B1,$A5,$DA,$0A,$0A,$08,$6A,$28,$6A,$85,$DA,$A5,$D6,$85,$D8
    .byte $A5,$D7,$85,$D9,$A0,$10,$A5,$A9,$C9,$0B,$F0,$02,$A0,$22,$4C,$8A
    .byte $AA,$4B,$95,$A5,$C7,$30,$12,$C9,$0F,$B0,$0B,$FE,$AB,$4D,$AD,$05
    .byte $4D,$D0,$03,$EE,$07,$4D,$EE,$08,$4D,$B5,$A2,$C9,$0D,$D0,$03,$20
    .byte $B6,$99,$4C,$F3,$97,$73,$95,$83,$95,$B5,$95,$A5,$C7,$29,$7F,$C9
    .byte $14,$B0,$05,$A9,$01,$9D,$AB,$4D,$4C,$F3,$97,$DE,$5B,$4D,$D0,$03
    .byte $FE,$83,$4D,$A5,$33,$4A,$4A,$29,$03,$A8,$B9,$AD,$95,$DD,$33,$4D
    .byte $F0,$0F,$20,$D5,$99,$B9,$B1,$95,$A4,$07,$18,$79,$CA,$00,$99,$CA
    .byte $00,$A4,$07,$10,$C6,$01,$00,$02,$00,$F8,$08,$06,$FA,$D6,$9A,$A9
    .byte $3C,$9D,$5B,$4D,$D0,$C5,$C2,$95,$D3,$95,$AD,$21,$4D,$25,$10,$8D
    .byte $21,$4D,$A9,$00,$CE,$5C,$4D,$D0,$17,$F0,$12,$A5,$FC,$D0,$0E,$A9
    .byte $0F,$8D,$5C,$4D,$A5,$CD,$C9,$F3,$8A,$85,$FB,$90,$03,$38,$66,$A3
    .byte $4C,$DB,$99,$EF,$95,$FC,$95,$A5,$C7,$30,$03,$EE,$07,$4D,$20,$E3
    .byte $99,$4C,$FB,$97,$AD,$05,$4D,$D0,$EE,$BD,$5B,$4D,$30,$05,$FE,$5B
    .byte $4D,$10,$E4,$A5,$C7,$30,$E7,$A5,$C6,$29,$7F,$C9,$0F,$B0,$D8,$20
    .byte $C6,$A2,$A9,$26,$9D,$5B,$4D,$9D,$AB,$4D,$10,$CB,$2A,$96,$48,$96
    .byte $51,$96,$DE,$5B,$4D,$D0,$03,$38,$76,$A2,$A5,$33,$29,$03,$48,$20
    .byte $DB,$99,$68,$D0,$08,$F6,$B2,$30,$04,$F0,$02,$D6,$B2,$4C,$00,$99
    .byte $A9,$1E,$9D,$5B,$4D,$D6,$9A,$10,$E1,$A9,$01,$20,$06,$A1,$A9,$FE
    .byte $95,$B2,$A5,$D7,$85,$D9,$A5,$D6,$85,$D8,$A5,$DA,$0A,$38,$30,$01
    .byte $18,$6A,$85,$DA,$D6,$9A,$60,$7B,$96,$83,$96,$9E,$96,$B5,$96,$D9
    .byte $96,$5A,$96,$A9,$01,$9D,$AB,$4D,$4C,$00,$99,$DE,$5B,$4D,$BD,$5B
    .byte $4D,$29,$07,$F0,$01,$60,$D6,$9A,$B9,$CB,$00,$18,$69,$05,$99,$CB
    .byte $00,$A9,$8B,$4C,$DF,$99,$DE,$5B,$4D,$BD,$5B,$4D,$29,$07,$F0,$01
    .byte $60,$D6,$9A,$A9,$04,$9D,$27,$D0,$A9,$8A,$4C,$DF,$99,$DE,$5B,$4D
    .byte $BD,$5B,$4D,$29,$07,$D0,$0C,$A9,$01,$20,$06,$A1,$D6,$9A,$A9,$89
    .byte $4C,$DF,$99,$29,$03,$D0,$07,$A0,$07,$20,$EE,$A0,$A9,$00,$4C,$DB
    .byte $99,$20,$A8,$AA,$A0,$1E,$20,$8A,$AA,$A4,$07,$A9,$2F,$9D,$5B,$4D
    .byte $D6,$9A,$10,$E3,$F4,$96,$FE,$96,$15,$97,$5A,$96,$DE,$5B,$4D,$D0
    .byte $14,$38,$76,$A2,$D0,$14,$DE,$5B,$4D,$D0,$0A,$A9,$1E,$9D,$5B,$4D
    .byte $D6,$9A,$DE,$2B,$4D,$A9,$01,$20,$06,$A1,$4C,$00,$99,$A9,$1E,$9D
    .byte $5B,$4D,$D6,$9A,$10,$E0,$24,$97,$4E,$97,$38,$97,$A5,$44,$C9,$15
    .byte $D0,$07,$CE,$08,$4D,$A9,$01,$85,$B3,$A9,$01,$8D,$AC,$4D,$D0,$29
    .byte $A9,$F4,$85,$D7,$A9,$01,$20,$06,$A1,$EE,$5C,$4D,$30,$01,$60,$A0
    .byte $20,$20,$7A,$AA,$C6,$9B,$A5,$CD,$C9,$A0,$B0,$09,$C6,$9B,$A9,$04
    .byte $85,$49,$A9,$01,$2C,$A9,$02,$85,$A0,$20,$EB,$99,$A9,$00,$85,$AB
    .byte $4C,$FB,$97,$6F,$97,$8E,$97,$A5,$DA,$4A,$48,$4A,$A5,$CC,$6A,$08
    .byte $18,$69,$04,$28,$2A,$85,$CA,$68,$2A,$85,$DA,$E6,$9A,$A9,$06,$85
    .byte $B2,$A9,$14,$8D,$5B,$4D,$E6,$B2,$CE,$5B,$4D,$D0,$02,$C6,$9A,$18
    .byte $A5,$CD,$65,$B2,$85,$CB,$A5,$A3,$C9,$18,$F0,$03,$38,$66,$A2,$60
    .byte $AC,$97,$BF,$97,$AD,$21,$4D,$09,$01,$8D,$21,$4D,$A9,$01,$8D,$AB
    .byte $4D,$8D,$AE,$4D,$4C,$00,$99,$A5,$DA,$29,$08,$18,$F0,$01,$38,$08
    .byte $A5,$DA,$4A,$28,$2A,$A5,$D0,$18,$69,$08,$85,$CA,$A5,$D1,$18,$69
    .byte $05,$85,$CB,$A5,$C7,$10,$13,$A9,$FA,$85,$B2,$A5,$C6,$29,$7F,$C9
    .byte $04,$B0,$07,$C6,$9A,$A0,$2A,$20,$82,$AA,$60,$A5,$44,$C9,$03,$D0
    .byte $02,$F6,$B2,$A0,$0C,$B5,$A2,$C9,$04,$B0,$02,$A0,$0E,$84,$09,$A0
    .byte $00,$84,$08,$84,$0B,$C8,$D0,$01,$28,$C8,$C4,$09,$F0,$26,$C4,$07
    .byte $D0,$03,$C8,$D0,$F4,$B9,$BA,$00,$C8,$0A,$08,$4A,$C9,$15,$B0,$E8
    .byte $46,$0B,$28,$26,$0B,$B9,$BA,$00,$0A,$08,$4A,$C9,$23,$B0,$D9,$28
    .byte $90,$D7,$26,$08,$A4,$07,$AD,$07,$4D,$D0,$08,$A5,$33,$4A,$90,$03
    .byte $4C,$00,$99,$BD,$8B,$4D,$F0,$09,$B5,$AA,$D0,$02,$F6,$AA,$4C,$00
    .byte $99,$A5,$08,$F0,$43,$A5,$0B,$F0,$18,$BD,$6B,$4D,$DD,$7B,$4D,$D0
    .byte $26,$B5,$AA,$30,$07,$DD,$43,$4D,$F0,$04,$B0,$16,$F6,$AA,$4C,$00
    .byte $99,$BD,$63,$4D,$DD,$7B,$4D,$D0,$0E,$B5,$AA,$DD,$3B,$4D,$F0,$04
    .byte $30,$EA,$D6,$AA,$4C,$00,$99,$B5,$B2,$DD,$4B,$4D,$10,$02,$F6,$B2
    .byte $B5,$AA,$F0,$64,$30,$D6,$10,$EA,$AD,$08,$4D,$30,$1A,$18,$F0,$01
    .byte $38,$A5,$33,$29,$07,$D0,$10,$B0,$2B,$B5,$B2,$DD,$53,$4D,$30,$05
    .byte $D6,$B2,$4C,$BF,$98,$F6,$B2,$BD,$63,$4D,$DD,$7B,$4D,$D0,$A2,$BD
    .byte $6B,$4D,$DD,$7B,$4D,$D0,$B2,$AD,$07,$4D,$F0,$C4,$A5,$C6,$F0,$C0
    .byte $10,$8F,$30,$A5,$A5,$C7,$F0,$DF,$30,$CF,$C9,$05,$90,$D9,$A9,$00
    .byte $38,$E5,$35,$D5,$B2,$30,$D0,$B5,$B2,$DD,$4B,$4D,$10,$C9,$F6,$B2
    .byte $4C,$BF,$98,$38,$E5,$35,$95,$B2,$A6,$06,$A4,$07,$B5,$AA,$08,$18
    .byte $79,$CA,$00,$99,$CA,$00,$B0,$05,$28,$30,$05,$10,$09,$28,$30,$06
    .byte $A5,$05,$45,$DA,$85,$DA,$BD,$73,$4D,$10,$03,$38,$76,$A2,$B5,$B2
    .byte $48,$B9,$CB,$00,$AA,$68,$18,$79,$CB,$00,$18,$65,$35,$E0,$0C,$90
    .byte $0D,$E0,$F3,$90,$10,$C9,$E9,$20,$51,$99,$90,$0C,$B0,$07,$C9,$16
    .byte $20,$51,$99,$B0,$03,$99,$CB,$00,$60,$08,$48,$A6,$06,$BD,$AB,$4D
    .byte $F0,$08,$A9,$00,$9D,$AB,$4D,$38,$76,$A2,$68,$28,$60,$A5,$33,$29
    .byte $03,$F0,$01,$60,$A5,$9B,$C9,$02,$A9,$04,$90,$18,$4D,$34,$4D,$10
    .byte $13,$A5,$34,$F0,$0F,$AD,$79,$4D,$F0,$0A,$A0,$0E,$20,$86,$AA,$AD
    .byte $39,$4D,$49,$01,$4C,$D5,$99,$A5,$A0,$F0,$04,$A9,$95,$D0,$48,$38
    .byte $A9,$04,$E5,$34,$A8,$A9,$00,$88,$30,$04,$38,$2A,$D0,$F9,$25,$33
    .byte $D0,$2E,$CE,$39,$4D,$10,$29,$A9,$02,$8D,$39,$4D,$10,$22,$A4,$07
    .byte $A5,$49,$C9,$02,$90,$15,$A5,$C7,$29,$7F,$C9,$1E,$B0,$0D,$A0,$18
    .byte $20,$76,$AA,$DE,$33,$4D,$10,$08,$A9,$02,$2C,$A9,$00,$9D,$33,$4D
    .byte $BD,$33,$4D,$18,$7D,$23,$4D

; -----------------------------------------------------------------------
; Store A as the sprite pointer for slot X (SPRITE_PTRS,x).
SET_SPRITE_PTR:
    sta SPRITE_PTRS,x
    rts
; -----------------------------------------------------------------------
; Weapon / collision handler routines and their dispatch tables, as data.
    .byte $A5,$33,$29,$03,$D0,$EF,$F0,$E0,$A5,$33,$29,$01,$10,$EA,$AD,$05
    .byte $4D,$F0,$11,$AD,$B9,$4D,$C9,$04,$90,$0A,$C9,$23,$B0,$06,$A9,$00
    .byte $8D,$89,$4D,$60,$A9,$00,$8D,$CB,$4D,$8D,$05,$4D,$AD,$79,$4D,$30
    .byte $28,$C9,$09,$F0,$EE,$AD,$89,$4D,$D0,$1F,$20,$66,$9D,$F0,$1A,$20
    .byte $60,$9D,$F0,$12,$20,$63,$9D,$F0,$0D,$20,$7C,$9D,$F0,$0B,$20,$76
    .byte $9D,$D0,$03,$20,$C1,$A7,$4C,$5A,$9C,$A2,$00,$86,$F6,$86,$F7,$86
    .byte $F9,$AE,$12,$4D,$F0,$03,$CE,$15,$4D,$EE,$CB,$4D,$A9,$02,$8D,$05
    .byte $4D,$CD,$69,$4D,$D0,$03,$CD,$71,$4D,$08,$A5,$49,$C9,$03,$B0,$09
    .byte $A9,$08,$28,$F0,$0E,$A9,$00,$F0,$07,$A9,$07,$28,$F0,$05,$A9,$06
    .byte $A0,$1E,$2C,$A0,$24,$85,$49,$20,$A8,$AA,$4C,$8A,$AA,$BD,$83,$4D
    .byte $F0,$08,$20,$A8,$AA,$A2,$05,$4C,$C0,$9B,$60,$A9,$FF,$8D,$20,$4D
    .byte $A5,$9B,$F0,$0A,$C9,$06,$F0,$06,$A9,$00,$8D,$84,$4D,$60,$A5,$44
    .byte $C9,$15,$D0,$01,$60,$BD,$83,$4D,$F0,$2B,$4C,$B7,$9B,$A9,$04,$2C
    .byte $A9,$03,$2C,$A9,$06,$2C,$A9,$03,$85,$08,$BD,$83,$4D,$F0,$16,$4C
    .byte $BE,$9B,$A9,$03,$85,$08,$BD,$83,$4D,$F0,$0A,$DE,$83,$4D,$D0,$EF
    .byte $A0,$28,$20,$7E,$AA,$20,$76,$9D,$D0,$06,$20,$C1,$A7,$FE,$8B,$4D
    .byte $20,$60,$9D,$D0,$02,$76,$A2,$BD,$8B,$4D,$D0,$08,$20,$63,$9D,$D0
    .byte $03,$FE,$8B,$4D,$20,$7C,$9D,$D0,$03,$4C,$C3,$9B,$4C,$5A,$9C,$A5
    .byte $DF,$20,$DE,$9B,$C0,$08,$F0,$23,$C0,$00,$F0,$04,$C0,$07,$D0,$06
    .byte $A5,$0C,$05,$05,$D0,$EB,$AD,$1D,$4D,$49,$FE,$8D,$1D,$4D,$79,$AA
    .byte $00,$99,$AA,$00,$C6,$9B,$A0,$16,$20,$86,$AA,$60,$A0,$02,$A9,$12
    .byte $2C,$A9,$09,$C8,$D9,$A2,$00,$F0,$04,$38,$66,$A2,$60,$A5,$DF,$20
    .byte $DE,$9B,$C0,$08,$F0,$14,$C0,$06,$F0,$06,$A5,$0C,$05,$05,$D0,$EF
    .byte $EE,$89,$4D,$A9,$00,$8D,$05,$4D,$66,$A2,$A5,$0C,$85,$DF,$60,$A5
    .byte $DF,$20,$DE,$9B,$C0,$08,$F0,$12,$B9,$A2,$00,$C9,$08,$F0,$04,$C9
    .byte $07,$D0,$0C,$EE,$84,$4D,$66,$A9,$66,$A2,$A5,$0C,$85,$DF,$60,$A5
    .byte $0C,$05,$05,$D0,$DC,$A5,$DF,$05,$05,$20,$DE,$9B,$C0,$08,$F0,$1B
    .byte $C0,$00,$F0,$1C,$C0,$06,$F0,$18,$B9,$A2,$00,$C9,$11,$F0,$11,$C9
    .byte $07,$F0,$0D,$A9,$01,$99,$83,$4D,$38,$66,$A9,$A5,$0C,$85,$DF,$60
    .byte $A5,$0C,$B0,$D3,$A9,$3C,$8D,$CA,$4D,$D0,$05,$A6,$08,$FE,$C3,$4D
    .byte $A6,$06,$B5,$AA,$48,$B5,$B2,$48,$20,$2B,$8D,$68,$95,$B2,$68,$95
    .byte $AA,$A0,$1E,$20,$86,$AA,$68,$68,$4C,$B0,$8A,$A0,$00,$84,$0D,$A0
    .byte $08,$85,$0C,$25,$05,$F0,$6F,$45,$0C,$85,$0C,$F0,$69,$BD,$93,$4D
    .byte $85,$08,$A0,$FF,$38,$24,$18,$26,$0D,$C8,$B0,$5A,$A9,$00,$85,$0E
    .byte $A5,$0C,$25,$0D,$F0,$F0,$A6,$06,$B9,$93,$4D,$85,$09,$18,$B9,$A3
    .byte $4D,$79,$9B,$4D,$38,$FD,$A3,$4D,$85,$0A,$18,$BD,$A3,$4D,$7D,$9B
    .byte $4D,$38,$F9,$A3,$4D,$85,$0B,$98,$0A,$AA,$B5,$BB,$30,$06,$C5,$08
    .byte $B0,$C4,$90,$06,$29,$7F,$C5,$09,$B0,$BC,$C9,$0E,$90,$02,$E6,$0E
    .byte $B5,$BA,$30,$06,$C5,$0B,$B0,$AE,$90,$06,$29,$7F,$C5,$0A,$B0,$A6
    .byte $A5,$0C,$45,$0D,$85,$0C,$60,$A5,$DE,$20,$DE,$9B,$A5,$0C,$85,$DE
    .byte $C0,$08,$D0,$01,$60,$A6,$06,$E0,$06,$F0,$04,$C0,$06,$D0,$68,$A9
    .byte $10,$D5,$A2,$D0,$06,$A9,$02,$95,$9A,$D0,$0A,$D9,$A2,$00,$D0,$0A
    .byte $A9,$02,$99,$9A,$00,$A9,$3C,$8D,$CA,$4D,$A9,$0D,$D5,$A2,$F0,$05
    .byte $D9,$A2,$00,$D0,$1C,$A5,$0E,$D0,$18,$AD,$05,$4D,$D0,$39,$A5,$A8
    .byte $C9,$05,$D0,$33,$85,$A0,$98,$48,$A0,$26,$20,$82,$AA,$68,$A8,$D0
    .byte $26,$A9,$0C,$D5,$A2,$F0,$20,$D9,$A2,$00,$F0,$1B,$38,$B5,$B2,$F9
    .byte $B2,$00,$C9,$07,$10,$0A,$38,$B9,$B2,$00,$F5,$B2,$C9,$07,$30,$07
    .byte $8A,$9D,$83,$4D,$99,$83,$4D,$B9,$AA,$00,$48,$B5,$AA,$99,$AA,$00
    .byte $68,$95,$AA,$84,$08,$B5,$AA,$D9,$AA,$00,$10,$06,$8A,$48,$98,$AA
    .byte $68,$A8,$F6,$AA,$F6,$AA,$8A,$0A,$AA,$18,$B5,$CA,$69,$02,$95,$CA
    .byte $90,$06,$A5,$05,$05,$DA,$85,$DA,$98,$AA,$D6,$AA,$D6,$AA,$0A,$AA
    .byte $38,$B5,$CA,$E9,$02,$95,$CA,$B0,$08,$A5,$0D,$49,$FF,$25,$DA,$85
    .byte $DA,$A4,$08,$A6,$06,$B9,$B2,$00,$48,$B5,$B2,$99,$B2,$00,$68,$95
    .byte $B2,$D9,$B2,$00,$10,$06,$98,$48,$8A,$A8,$68,$AA,$F6,$B2,$8A,$0A
    .byte $AA,$F6,$CB,$F6,$CB,$98,$AA,$D6,$B2,$0A,$AA,$D6,$CB,$D6,$CB,$A6
    .byte $06,$A0,$2C,$20,$86,$AA,$A5,$05,$05,$0C,$4C,$5C,$9C,$A9,$0C,$2C
    .byte $A9,$0B,$2C,$A9,$0A,$DD,$63,$4D,$F0,$08,$DD,$6B,$4D,$F0,$03,$DD
    .byte $73,$4D,$60,$A9,$07,$DD,$73,$4D,$60,$BD,$7B,$4D,$20,$68,$9D,$F0
    .byte $33,$C9,$00,$D0,$17,$A9,$04,$20,$68,$9D,$F0,$28,$A9,$06,$20,$68
    .byte $9D,$F0,$21,$A9,$07,$20,$68,$9D,$F0,$1A,$D0,$15,$A9,$03,$20,$68
    .byte $9D,$F0,$0E,$A9,$05,$20,$68,$9D,$F0,$0A,$A9,$02,$20,$68,$9D,$F0
    .byte $03,$A9,$00,$60,$A9,$01,$60

; -----------------------------------------------------------------------
; Pick the current road section / difficulty (SCENE_IDX) from game state.
UPDATE_SCENE_SELECT:
    lda SEQ_STATE
    beq L9DEF
    cmp #$06
    bcs L9DEF
    lda ROAD_SEG_IDX
    cmp #$0F
    beq L9DF6
    lda ROAD_FEATURE
    cmp #$11
    beq L9DDB
    lda PREV_FEATURE
    cmp #$15
    beq L9DDB
    lda #$00
    sta STATE_4D17
    beq L9DF6

L9DDB:
    lda STATE_4D17
    bne L9DF6
    ldy STATE_4D16
    tya
    dey
    bne L9DE9
    ldy #$03

L9DE9:
    sty STATE_4D16
    sta STATE_4D17

L9DEF:
    ldx HERO_STATE
    bmi L9DF6
    stx STATE_4DAC

L9DF6:
    lda FRAME_SUBCTR
    cmp #$06
    bcc L9E10
    ldx #$00
    stx FRAME_SUBCTR
    lda #$14
    cmp ROAD_FEATURE
    beq L9E0D
    cmp PREV_FEATURE
    beq L9E0D
    inx

L9E0D:
    inc STAT_CTR,x

L9E10:
    lda STATE_4DB9
    ldy #$12
    ldx ROAD_SEG_IDX
    cpx #$07
    beq L9E23
    cpx #$0F
    bcc L9E2F
    cpx #$12
    bcs L9E2F

L9E23:
    ldx SCENE_ID
    cpx #$06
    beq L9E2E
    cpx #$05
    bne L9E31
    iny

L9E2E:
    tya

L9E2F:
    sta SCENE_IDX

L9E31:
    rts

; -----------------------------------------------------------------------
; Decode the road/scene layout stream into RAM (runs + mirrored rows).
UNPACK_MAP_DATA:
    lda #$60
    sta MAP_SRC
    lda #$29
    sta MAP_SRC_HI
    lda #$80
    sta MAP_DST
    sta MAP_ROW
    lda #$29
    sta MAP_DST_HI
    sta MAP_ROW_HI
    lda #$CB
    sta STREAM_PTR
    lda #$AD
    sta STREAM_PTR_HI
    ldy #$00

L9E50:
    jsr STREAM_NEXT_BYTE
    bne L9E59
    beq L9E70

L9E57:
    ldy #$00

L9E59:
    ldx #$01
    cmp #$14
    bcc L9E63
    cmp #$40
    bcc L9E68

L9E63:
    pha
    jsr STREAM_NEXT_BYTE
    pla

L9E68:
    sta (MAP_DST),y
    iny
    dex
    bne L9E68
    beq L9E50

L9E70:
    jsr STREAM_NEXT_BYTE
    bpl L9E90
    and #$1F
    tax
    lda #$0F
    sta ZTMP_09
    lda #$10
    sta ZTMP_0A

L9E80:
    ldy ZTMP_09
    lda (MAP_DST),y
    eor #$01
    ldy ZTMP_0A
    sta (MAP_DST),y
    inc ZTMP_0A
    dec ZTMP_09
    bpl L9E80

L9E90:
    clc
    lda MAP_SRC
    adc #$20
    sta MAP_SRC
    bcc L9E9B
    inc MAP_SRC_HI

L9E9B:
    clc
    lda MAP_DST
    adc #$20
    sta MAP_DST
    bcc L9EA6
    inc MAP_DST_HI

L9EA6:
    dex
    bmi L9EB4
    ldy #$1F

L9EAB:
    lda (MAP_SRC),y
    sta (MAP_DST),y
    dey
    bpl L9EAB
    bmi L9E90

L9EB4:
    jsr STREAM_NEXT_BYTE
    bne L9E57
    lda MAP_ROW
    sta MAP_PREV
    sta DST2_PTR
    lda MAP_ROW_HI
    sta MAP_PREV_HI
    sta DST2_PTR_HI
    lda MAP_DST
    sta MAP_ROW
    sta SRC_PTR
    sec
    sbc #$01
    sta DST_PTR
    lda MAP_DST_HI
    sta MAP_ROW_HI
    sta SRC_PTR_HI
    sbc #$00
    sta DST_PTR_HI
    jsr STREAM_NEXT_BYTE
    beq L9EF5
    bpl L9EE7
    jsr DRAW_FLIP_ROWS
    jmp L9EF5

L9EE7:
    jsr DRAW_MIRROR_ROWS
    jsr STREAM_NEXT_BYTE
    beq L9EF5
    jsr DRAW_FLIP_ROWS
    jsr DRAW_MIRROR_ROWS

L9EF5:
    jsr STREAM_NEXT_BYTE
    beq L9EFD
    jmp L9E57

L9EFD:
    jsr STREAM_NEXT_BYTE
    beq L9F35
    sta ZTMP_30
    jsr STREAM_NEXT_BYTE
    sta BLIT_COUNT
    jsr STREAM_NEXT_BYTE
    sta SCREEN_PTR_HI
    jsr STREAM_NEXT_BYTE
    sta SCREEN_PTR
    jsr STREAM_NEXT_BYTE
    beq L9F25
    sta SRC_PTR_HI
    jsr STREAM_NEXT_BYTE
    sta SRC_PTR
    jsr MAP_COPY_BLOCK
    jmp L9EFD

L9F25:
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0B
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0C
    jsr MAP_EXPAND_RUN
    jmp L9EFD

L9F35:
    lda #$80
    sta SRC_PTR
    lda #$29
    sta SRC_PTR_HI
    ldx #$00

L9F3F:
    lda (SRC_PTR,x)
    cmp #$08
    bcc L9F58
    cmp #$14
    bcs L9F58

L9F49:
    jsr RNG_NEXT
    and #$0F
    sec
    sbc #$04
    bmi L9F49
    clc
    adc #$08
    bne L9F79

L9F58:
    pha
    cmp #$14
    bcc L9F7E
    cmp #$2C
    bcs L9F7E
    inc ZTMP_09
    lda ZTMP_09
    and #$08
    bne L9F7E
    pla
    pha
    and #$04
    bne L9F75
    pla
    sec
    sbc #$04
    bne L9F79

L9F75:
    pla
    clc
    adc #$04

L9F79:
    sta (SRC_PTR,x)
    jmp L9F7F

L9F7E:
    pla

L9F7F:
    jsr PTR_SRC_INC
    lda SRC_PTR_HI
    cmp #$5D
    bcc L9F3F
    lda #$4D
    ldy #$C0
    ldx #$10
    jmp COPY_PAGES

DRAW_MIRROR_ROWS:
    ldx #$00

L9F93:
    ldy #$1F

L9F95:
    lda (DST2_PTR,x)
    eor #$01
    sta (SRC_PTR),y
    jsr PTR_AUX_INC
    lda DST2_PTR_HI
    cmp MAP_ROW_HI
    bne L9FAA
    lda DST2_PTR
    cmp MAP_ROW
    beq L9FFB

L9FAA:
    dey
    bpl L9F95
    lda #$20
    jsr PTR_SRC_ADD
    jmp L9F93

DRAW_FLIP_ROWS:
    ldx #$00

L9FB7:
    ldy #$1F

L9FB9:
    lda (DST_PTR,x)
    cmp #$14
    bcc L9FD3
    cmp #$2C
    bcs L9FD3
    pha
    and #$04
    bne L9FCF
    pla
    sec
    sbc #$04
    jmp L9FD3

L9FCF:
    pla
    clc
    adc #$04

L9FD3:
    eor #$02
    sta (SRC_PTR),y
    sec
    lda DST_PTR
    sbc #$01
    sta DST_PTR
    bcs L9FE2
    dec DST_PTR_HI

L9FE2:
    lda DST_PTR_HI
    cmp MAP_PREV_HI
    bcc L9FFB
    beq L9FF5

L9FEA:
    dey
    bpl L9FB9
    lda #$20
    jsr PTR_SRC_ADD
    jmp L9FB7

L9FF5:
    lda DST_PTR
    cmp MAP_PREV
    bcs L9FEA

L9FFB:
    lda MAP_ROW
    sta MAP_PREV
    sta DST2_PTR
    lda MAP_ROW_HI
    sta MAP_PREV_HI
    sta DST2_PTR_HI
    lda SRC_PTR
    sta MAP_SRC
    sta DST_PTR
    lda SRC_PTR_HI
    sta MAP_SRC_HI
    sta DST_PTR_HI
    lda #$1F
    jsr PTR_DST_ADD
    lda #$20
    jsr PTR_SRC_ADD
    lda SRC_PTR
    sta MAP_ROW
    sta MAP_DST
    lda SRC_PTR_HI
    sta MAP_ROW_HI
    sta MAP_DST_HI
    rts

MAP_EXPAND_RUN:
    ldx ZTMP_0B
    cpx ZTMP_0C
    bne LA033
    jmp LA0C2

LA033:
    inc ZTMP_0B
    lda OBJ_ADDR_LO,x
    sta SRC_PTR
    lda OBJ_ADDR_HI,x
    sta SRC_PTR_HI
    lda OBJ_ADDR_LO2,x
    sta DST_PTR
    lda OBJ_ADDR_HI2,x
    sta DST_PTR_HI
    cpx #$0F
    beq LA056
    bcc LA05D
    sec
    lda SRC_PTR_HI
    sbc #$73
    sta SRC_PTR_HI

LA056:
    sec
    lda DST_PTR_HI
    sbc #$73
    sta DST_PTR_HI

LA05D:
    lda #$00
    sta ZTMP_0A

LA061:
    ldy #$00

LA063:
    lda (SRC_PTR),y
    iny
    cmp #$04
    bcc LA06E
    cmp #$08
    bcc LA072

LA06E:
    tya
    jmp LA09C

LA072:
    cpy ZTMP_30
    bne LA063
    inc ZTMP_0A
    lda BLIT_COUNT
    cmp ZTMP_0A
    bne LA0AE
    sec
    sbc #$01
    asl a
    asl a
    asl a
    asl a
    asl a
    bcc LA08A
    dec SRC_PTR_HI

LA08A:
    sta BIT_MASK
    sec
    lda SRC_PTR
    sbc BIT_MASK
    sta SRC_PTR
    bcs LA097
    dec SRC_PTR_HI

LA097:
    jsr MAP_COPY_BLOCK
    lda #$03

LA09C:
    jsr PTR_SRC_ADD
    lda SRC_PTR_HI
    cmp DST_PTR_HI
    bcc LA05D
    lda SRC_PTR
    cmp DST_PTR
    bcc LA05D
    jmp MAP_EXPAND_RUN

LA0AE:
    lda #$20
    jsr PTR_SRC_ADD
    lda SRC_PTR_HI
    cmp DST_PTR_HI
    bcc LA061
    lda SRC_PTR
    cmp DST_PTR
    bcc LA061
    jmp MAP_EXPAND_RUN

LA0C2:
    rts

MAP_COPY_BLOCK:
    lda BLIT_COUNT
    sta BLIT_ROWS
    ldy #$00
    ldx #$00

LA0CB:
    lda ZTMP_30
    sta BLIT_WIDTH

LA0CF:
    lda (SCREEN_PTR),y
    sta (SRC_PTR,x)
    iny
    dec BLIT_WIDTH
    beq LA0DE
    jsr PTR_SRC_INC
    jmp LA0CF

LA0DE:
    dec BLIT_ROWS
    beq LA0ED
    lda #$21
    sec
    sbc ZTMP_30
    jsr PTR_SRC_ADD
    jmp LA0CB

LA0ED:
    rts
; -----------------------------------------------------------------------
; Small mirror/fill helper fragment stored as data.
    .byte $A9,$FF,$2C,$A9,$01,$84,$08,$18,$65,$34,$30,$13,$C9,$05,$B0,$0F
    .byte $48,$A5,$33,$25,$08,$D0,$07,$68,$85,$34,$0A,$85,$35,$24,$68,$60

; -----------------------------------------------------------------------
; Pseudo-random step: RNG_SEED = RNG_SEED + A, then EOR VIC_RASTER.
RNG_NEXT:
    adc RNG_SEED
    eor VIC_RASTER
    sta RNG_SEED
    rts

; -----------------------------------------------------------------------
; Fetch the next byte from STREAM_PTR and post-increment.
STREAM_NEXT_BYTE:
    ldx #$00
    lda (STREAM_PTR,x)
    inc STREAM_PTR
    bne LA120
    inc STREAM_PTR_HI

LA120:
    tax
    rts

; -----------------------------------------------------------------------
; Advance SRC_PTR by 1 (PTR_SRC_INC) or by A (PTR_SRC_ADD).
PTR_SRC_INC:
    lda #$01

PTR_SRC_ADD:
    clc
    adc SRC_PTR
    sta SRC_PTR
    bcc LA12D
    inc SRC_PTR_HI

LA12D:
    rts

; -----------------------------------------------------------------------
; Advance DST_PTR by 1 or by A.
PTR_DST_INC:
    lda #$01

PTR_DST_ADD:
    clc
    adc DST_PTR
    sta DST_PTR
    bcc LA139
    inc DST_PTR_HI

LA139:
    rts

; -----------------------------------------------------------------------
; Advance DST2_PTR by 1 or by A.
PTR_AUX_INC:
    lda #$01

PTR_AUX_ADD:
    clc
    adc DST2_PTR
    sta DST2_PTR
    bcc LA145
    inc DST2_PTR_HI

LA145:
    rts

; -----------------------------------------------------------------------
; Charset builder helper: roll 2 bits of A into ZTMP_09.
PACK_2BITS:
    ldx #$04

LA148:
    clc
    rol ZTMP_09
    asl a
    rol ZTMP_09
    dex
    bne LA148
    rts
; -----------------------------------------------------------------------
; Joystick / keyboard decode helper code and tables (feeds JOY_STATE), as data.
    .byte $AD,$01,$DC,$49,$FF,$AA,$A0,$00,$29,$03,$F0,$06,$4A,$90,$02,$C8
    .byte $24,$88,$8C,$09,$4D,$8A,$29,$10,$8D,$0B,$4D,$8A,$A0,$00,$29,$0C
    .byte $F0,$07,$C9,$08,$F0,$02,$88,$24,$C8,$8C,$0A,$4D,$AD,$00,$DC,$49
    .byte $FF,$29,$10,$8D,$0C,$4D,$60,$20,$0E,$A1,$29,$03,$8D,$0B,$4D,$A9
    .byte $00,$A8,$AA,$CD,$71,$4D,$D0,$0C,$CD,$69,$4D,$D0,$05,$20,$0E,$A1
    .byte $10,$02,$C8,$C8,$88,$8C,$0A,$4D,$C5,$34,$F0,$07,$20,$0E,$A1,$30
    .byte $02,$CA,$CA,$E8,$8E,$09,$4D,$60

; -----------------------------------------------------------------------
; Charset builder: emit a character and its mirrored twin into DST_PTR.
BUILD_CHAR_PAIR:
    sta ZTMP_0D

LA1BC:
    lda #$08
    sta ZTMP_0B

LA1C0:
    ldy #$00
    jsr STREAM_NEXT_BYTE
    sta (DST_PTR),y
    pha
    jsr MIRROR_BYTE
    pha
    ldy #$08
    sta (DST_PTR),y
    jsr PTR_DST_INC
    lda ZTMP_0D
    bne LA1D9
    pla
    pla

LA1D9:
    dec ZTMP_0B
    bne LA1C0
    lda #$08
    sta ZTMP_0B
    jsr PTR_DST_ADD
    lda ZTMP_0D
    beq LA1FE

LA1E8:
    ldy #$08
    pla
    sta (DST_PTR),y
    ldy #$00
    pla
    sta (DST_PTR),y
    jsr PTR_DST_INC
    dec ZTMP_0B
    bne LA1E8
    lda #$08
    jsr PTR_DST_ADD

LA1FE:
    dec ZTMP_0C
    bne LA1BC
    rts

; -----------------------------------------------------------------------
; Horizontally mirror a multicolour byte (swap the four 2-bit pixels).
MIRROR_BYTE:
    ldx #$04

LA205:
    asl a
    php
    asl a
    ror ZTMP_0A
    plp
    ror ZTMP_0A
    dex
    bne LA205
    lda ZTMP_0A
    rts

; -----------------------------------------------------------------------
; memcpy: copy X*256 bytes from SRC_PTR to DST_PTR (page-aligned).
COPY_PAGES:
    sta SRC_PTR_HI
    sty DST_PTR_HI
    ldy #$00
    sty SRC_PTR
    sty DST_PTR

LA21D:
    lda (SRC_PTR),y
    sta (DST_PTR),y
    iny
    bne LA21D
    inc SRC_PTR_HI
    inc DST_PTR_HI
    dex
    bne LA21D
    rts

; -----------------------------------------------------------------------
; memset colour RAM: fill 4 pages at $D800 with $0E. Falls into FILL_PAGES.
CLEAR_COLOR_RAM:
    lda #$0E
    ldy #$D8
    ldx #$04

; -----------------------------------------------------------------------
; memset: fill X*256 bytes at SRC_PTR with the value in A.
FILL_PAGES:
    sty SRC_PTR_HI
    ldy #$00
    sty SRC_PTR

LA238:
    sta (SRC_PTR),y
    iny
    bne LA238
    inc SRC_PTR_HI
    dex
    bne LA238
    rts

; -----------------------------------------------------------------------
; Busy-wait some frames using the IRQ COPY_BLOCK_FLAG / FRAME_SUBCTR.
DELAY_FRAMES:
    lda SCROLL_SPEED
    bne LA249
    inc SCROLL_SPEED

LA249:
    lda COPY_BLOCK_FLAG
    beq LA249
    lda #$0C
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
DELAY_FRAMES_ALT:
    lda #$1A
    ldx #$01
    stx SCROLL_SPEED
    dex
    stx FRAME_SUBCTR

LA25A:
    cmp FRAME_SUBCTR
    bne LA25A
    stx SCROLL_SPEED
    rts

; -----------------------------------------------------------------------
; Scan the joystick/keys once per frame; return the first code seen.
POLL_INPUT_FRAME:
    ldy FRAME_FLAG
    dey

LA266:
    jsr SCAN_JOY_KEYS
    bne LA270
    cpy FRAME_FLAG
    bne LA266

LA270:
    rts

; -----------------------------------------------------------------------
; Blank the status panel (11 cells of blanks via PANEL_PUT_CHAR_PAIR).
CLEAR_PANEL:
    jsr CLEAR_PANEL_ALT

LA274:
    ldx #$00
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
CLEAR_PANEL_ALT:
    ldx #$12
    ldy #$0B

LA27B:
    lda #$40
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bne LA27B
    rts

; -----------------------------------------------------------------------
; Reset the road-segment index (ROAD_SEG_IDX=$1F).
RESET_ROAD_INDEX:
    lda #$1F
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
RESET_ROAD_INDEX_ALT:
    lda #$1D
    sta ROAD_SEG_IDX

; -----------------------------------------------------------------------
; Reset scroll/segment counters and SCENE_IDX for a new scene.
RESET_SCROLL_VARS:
    lda #$01
    sta ROW_REPEAT
    sta SEG_REPEAT
    sta ROAD_SEG_LEN
    lda #$12
    sta SCENE_IDX
    rts
; -----------------------------------------------------------------------
; Attract / road-reset helper code plus a $5Axx screen row-address table, as data.
    .byte $9E,$9F,$A0,$A1,$A2,$DE,$5B,$4D,$D0,$09,$A5,$FF,$30,$17,$D0,$04
    .byte $FE,$5B,$4D,$60,$A9,$FF,$85,$FF,$A9,$2D,$9D,$5B,$4D,$A0,$0A,$20
    .byte $82,$AA,$4C,$FE,$A2,$A9,$00,$85,$FF,$A0,$1E,$20,$82,$AA,$A5,$E8
    .byte $D0,$DE,$A9,$98,$85,$24,$A9,$A2,$85,$25,$A0,$01,$BD,$73,$4D,$C9
    .byte $02,$F0,$07,$C8,$E6,$24,$D0,$02,$E6,$25,$18,$BD,$B3,$4D,$69,$01
    .byte $85,$98,$BD,$BB,$4D,$69,$01,$85,$99,$C9,$14,$A9,$00,$B0,$06,$85
    .byte $97,$84,$31,$84,$E8,$2C,$A9,$A0,$A0,$03,$20,$07,$A3,$A0,$00,$99
    .byte $2D,$5A,$99,$33,$5A,$99,$6F,$5A,$99,$75,$5A,$99,$86,$5A,$99,$8C
    .byte $5A,$99,$C8,$5A,$99,$CE,$5A,$99,$1E,$5B,$60

; -----------------------------------------------------------------------
; Wait for the IRQ frame flag; every 4th frame decrement the BCD game timer.
; When GAME_TIME reaches 0 it sets EXTRA_LIFE_AVAIL=$FF (the timer-expired flag
; that hides the panel timer) and, on the car scene (SCENE_ID=$05), inc FLAG_FC.
WAIT_FRAME_TIMER:
    lda FRAME_FLAG
    cmp #$02
    bcc WAIT_FRAME_TIMER
    lda #$00
    sta FRAME_FLAG
    inc FRAME_CTR
    lda TIMER_ENABLE
    beq LA361
    lda FRAME_CTR
    and #$03
    bne LA361
    sed
    sec
    lda GAME_TIME_LO
    sbc #$01
    sta GAME_TIME_LO
    tax
    lda GAME_TIME_HI
    sbc #$00
    sta GAME_TIME_HI
    cld
    bne LA361
    txa
    bne LA361
    lda #$FF
    sta EXTRA_LIFE_AVAIL
    lda SCENE_ID
    cmp #$05
    bne LA361
    inc FLAG_FC

; -----------------------------------------------------------------------
; COPY_SPRITE_REGS: push staged sprite coords to $D000-$D010 and pointers to screens.
LA361:
    ldy #$10

LA363:
    lda a:SPR_X_SHADOW,y
    sta VIC_SPR0X,y
    dey
    bpl LA363
    ldx #$07

LA36E:
    lda SPRITE_PTRS,x
    sta SPRPTR_7800,x
    sta SPRPTR_7C00,x
    dex
    bpl LA36E
    rts

; -----------------------------------------------------------------------
; Blit a multi-character object (car / weapons van / boat / smoke plume) into
; the scrolling $7800 screen buffer + colour RAM (never the ROM/road template),
; so blitted content becomes transient MAP tiles that scroll with the road.
; The BLIT_FLAGS high-bit path (LA408+) widens the shape row-by-row = smoke plume.
DRAW_OBJECT_TILES:
    ldx BLIT_ROWS
    bne LA380
    rts

LA380:
    lda BLIT_ROW
    asl a
    tay
    sec
    lda ROWADDR_HI,y
    sbc #$78
    clc
    adc #$D8
    sta COLOR_PTR_HI
    sec
    lda ROWADDR_LO,y
    sbc #$28
    php
    bcs LA39A
    dec COLOR_PTR_HI

LA39A:
    clc
    adc BLIT_COL
    php
    bcc LA3A2
    inc COLOR_PTR_HI

LA3A2:
    sta COLOR_PTR
    clc
    adc #$24
    php
    clc
    adc SCROLL_DST
    sta SCREEN_PTR
    lda ROWADDR_HI,y
    adc SCROLL_DST_HI
    plp
    adc #$00
    plp
    adc #$00
    plp
    sbc #$78
    sta SCREEN_PTR_HI
    lda #$1B
    sta BLIT_ROW
    ldx BLIT_COL

LA3C3:
    ldy BLIT_WIDTH
    dey

LA3C6:
    lda (STREAM_PTR),y
    sta (SCREEN_PTR),y
    lda OBJ_COLOR
    beq LA3D8
    sta (COLOR_PTR),y
    cpx #$00
    beq LA3D8
    lda BLIT_ROW
    sta ZVEC_MOVE,x

LA3D8:
    inx
    dey
    bpl LA3C6
    dec BLIT_ROWS
    beq LA403
    ldx #$00
    lda SCREEN_PTR
    clc
    adc #$28
    bcc LA3ED
    inc SCREEN_PTR_HI
    inc COLOR_PTR_HI

LA3ED:
    sta SCREEN_PTR
    lda COLOR_PTR
    clc
    adc #$28
    sta COLOR_PTR
    lda STREAM_PTR
    clc
    adc BLIT_WIDTH
    bcc LA3FF
    inc STREAM_PTR_HI

LA3FF:
    sta STREAM_PTR
    bne LA3C3

LA403:
    lda BLIT_FLAGS
    bmi LA408

LA407:
    rts

LA408:
    and #$07
    sta BLIT_FLAGS
    sta BLIT_ROWS
    clc
    lda STREAM_PTR
    adc #$02
    sta STREAM_PTR2
    lda STREAM_PTR_HI
    adc #$00
    sta STREAM_PTR2_HI
    lda #$02
    sta BLIT_WIDTH

LA41F:
    dec BLIT_ROWS
    beq LA407
    clc
    lda SCREEN_PTR
    adc #$27
    sta SCREEN_PTR
    bcc LA42E
    inc SCREEN_PTR_HI

LA42E:
    clc
    lda COLOR_PTR
    adc #$27
    sta COLOR_PTR
    bcc LA439
    inc COLOR_PTR_HI

LA439:
    dec BLIT_ROW
    lda BLIT_ROW
    cmp #$02
    bcs LA447

LA441:
    lda #$00
    sta BLIT_ROWS
    beq LA407

LA447:
    dec BLIT_COL
    inc BLIT_WIDTH
    inc BLIT_WIDTH
    ldx #$00
    ldy #$00
    beq LA457

LA453:
    ldx #$02
    ldy BLIT_WIDTH

LA457:
    lda (STREAM_PTR,x)
    sta (SCREEN_PTR),y
    lda OBJ_COLOR
    beq LA472
    sta (COLOR_PTR),y
    tya
    clc
    adc BLIT_COL
    tax
    lda BLIT_ROW
    sta ZVEC_MOVE,x
    cpx #$23
    bcs LA441
    cpx #$05
    bcc LA441

LA472:
    dey
    bpl LA41F
    bmi LA453

; -----------------------------------------------------------------------
; Per-frame weapon / special-vehicle update (weapons van, smoke/missile fx).
; Smoke: decrements the $F7 charge and blits the plume tiles ($AD/$10/$AE, edge
; variants $B0-$B6) from ROM ~$A538-$A567 (STREAM_PTR) into the $7800 road buffer
; via DRAW_OBJECT_TILES, colour $09; blit col/row from STATE_4DB9 / STATE_4DC1.
UPDATE_WEAPONS:
    lda BLIT_ROWS
    bne LA493
    lda STATE_4D0C
    bne LA494
    sta BLIT_FLAGS
    lda WEAPON_STATE
    and #$10
    beq LA493
    lda WEAPON_STATE
    and #$0F
    eor #$03
    sta WEAPON_STATE

LA493:
    rts

LA494:
    lda WEAPON_STATE

LA497:
    cmp #$11
    beq LA4AF
    bcs LA4C4
    lda MISSILE_CNT
    beq LA4AF
    lda SMOKE_CNT
    beq LA4C4
    lda WEAPON_STATE
    ora #$10
    sta WEAPON_STATE
    bne LA497

LA4AF:
    lda SMOKE_CNT
    beq LA493
    ldy #$12
    jsr SOUND_REQ_V0
    dec SMOKE_CNT
    lda #$08
    sta BLIT_FLAGS
    ldx #$FD
    ldy #$00
    beq LA4E3

LA4C4:
    lda MISSILE_CNT
    beq LA493
    ldy #$14
    jsr SOUND_REQ_V0
    dec MISSILE_CNT
    inc BLIT_FLAGS
    lda BLIT_FLAGS
    cmp #$05
    bcc LA4D9
    lda #$04

LA4D9:
    ora #$80
    sta BLIT_FLAGS
    lda #$09
    ldx #$15
    ldy #$08

LA4E3:
    sta OBJ_COLOR
    stx ZTMP_08
    ldx #$08

LA4E9:
    clc
    lda ZTMP_08
    adc #$03
    sta ZTMP_08
    lda SPR_MATCH_A,y
    cmp OBJ_TBL69
    bne LA508
    lda SPR_MATCH_B,y
    cmp OBJ_TBL79
    bne LA508
    lda SPR_MATCH_C,y
    cmp OBJ_TBL71
    beq LA50D

LA508:
    iny
    dex
    bne LA4E9
    rts

LA50D:
    cpx #$04
    bcs LA515
    lda #$0E
    sta OBJ_COLOR

LA515:
    clc
    lda #$38
    adc ZTMP_08
    sta STREAM_PTR
    lda #$A5
    adc #$00
    sta STREAM_PTR_HI
    lda STATE_4DB9
    sta BLIT_COL
    lda STATE_4DC1
    clc
    adc #$02
    sta BLIT_ROW
    lda #$03
    sta BLIT_WIDTH
    lda #$01
    sta BLIT_ROWS
    rts
; -----------------------------------------------------------------------
; SPR_MATCH_A/B/C: sprite-graphic match tables used when drawing weapon icons.
    .byte $A7,$10,$A8,$A7,$10,$AA,$A7,$10,$AC,$A9,$10,$A8,$AB,$10,$A8,$A3
    .byte $9D,$A4,$A3,$9D,$A6,$A5,$9D,$A4,$AD,$10,$AE,$AD,$10,$B0,$AD,$10
    .byte $B2,$AF,$10,$AE,$B1,$10,$AE,$B3,$01,$B4,$B3,$01,$B6,$B5,$01,$B4
    .byte $00,$00,$00,$04,$06,$02,$02,$05,$00,$00,$00,$04,$06,$02,$02,$05
    .byte $00,$00,$00,$00,$00,$02,$02,$02,$00,$00,$00,$00,$00,$02,$02,$02
    .byte $00,$04,$06,$00,$00,$02,$05,$02,$00,$04,$06,$00,$00,$02,$05,$02
    .byte $10,$2B,$2A,$10,$10,$27,$2C,$28,$10,$10,$2B,$2C,$2A,$10,$10,$2C
    .byte $2C,$2C,$26,$10,$29,$2C,$2C,$2A,$10,$25,$2C,$2C,$28,$10,$10,$29
    .byte $2C,$24,$10,$10,$27,$2A,$10,$10,$10,$2B,$2C,$26,$10,$27,$17,$16
    .byte $2A,$10,$2B,$15,$1A,$2C,$26,$29,$17,$04,$1A,$2A,$25,$15,$04,$18
    .byte $2C,$27,$2C,$19,$14,$24,$25,$2C,$2C,$28,$10,$10,$25,$2C,$24,$10

; -----------------------------------------------------------------------
; Advance and draw the road weapon/hazard effects using the FX_* state.
UPDATE_HAZARDS:
    jsr DRAW_OBJECT_TILES
    ldx #$05
    lda FX_TIMER3
    bne LA609
    dex
    lda FX_TIMER2
    bne LA606
    dex
    lda FX_TIMER1
    bne LA603
    dex
    lda FX_TIMER0
    beq LA60E
    dec FX_TIMER0
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
LA603:
    dec FX_TIMER1
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
LA606:
    dec FX_TIMER2
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
LA609:
    dec FX_TIMER3
    jmp LA785

LA60E:
    lda FX_COUNT
    bne LA659
    lda ROAD_FEATURE
    cmp #$14
    beq LA62D
    lda SEG_REPEAT
    dex
    ldy ROAD_SEG_IDX
    cpy #$1D
    bne LA624
    jmp LA77C

LA624:
    dex
    cpy #$1E
    bne LA62C
    jmp LA781

LA62C:
    rts

LA62D:
    jsr RNG_NEXT
    cmp #$FA
    bcc LA62C
    jsr RNG_NEXT
    pha
    cmp #$7F
    lda #$09
    ldx #$A5
    ldy #$BB
    bcc LA648
    lda #$07
    ldx #$A5
    ldy #$98

LA648:
    sta FX_COUNT
    stx FX_SRC_HI
    sty FX_SRC
    pla
    and #$0E
    adc #$0A
    sta FX_LEN
    lda #$05
    sta ZTMP_30

LA659:
    dec FX_COUNT
    lda FX_LEN
    sta BLIT_COL
    lda #$00
    sta BLIT_ROW
    lda ZTMP_30
    sta BLIT_WIDTH
    lda #$01
    sta BLIT_ROWS
    lda #$00
    sta OBJ_COLOR
    lda FX_SRC
    sta STREAM_PTR
    lda FX_SRC_HI
    sta STREAM_PTR_HI
    lda FX_SRC
    clc
    adc ZTMP_30
    bcc LA680
    inc FX_SRC_HI

LA680:
    sta FX_SRC
    jsr DRAW_OBJECT_TILES
    rts
; -----------------------------------------------------------------------
; FX_PARAM_* tables and effect graphics/params for UPDATE_HAZARDS.
    .byte $95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95,$95
    .byte $95,$95,$95,$95,$95,$95,$95,$95,$96,$97,$98,$98,$99,$9A,$9B,$9C
    .byte $8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E
    .byte $8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8F,$90,$91,$92,$93,$94,$00,$00
    .byte $00,$7A,$7B,$7C,$7D,$7E,$7F,$00,$80,$81,$82,$83,$84,$85,$86,$87
    .byte $88,$89,$8A,$8B,$8C,$8D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $E0,$E1,$D4,$D5,$FC,$FD,$00,$E8,$E9,$EE,$EF,$00,$DE,$DF,$E8,$E9
    .byte $FC,$FD,$E8,$E9,$F6,$F7,$D4,$D5,$EE,$EF,$D8,$D9,$CC,$CD,$E4,$E5
    .byte $D4,$D5,$E8,$E9,$E6,$E7,$00,$00,$E2,$E3,$D4,$D5,$D6,$D7,$F2,$F3
    .byte $00,$D2,$D3,$D4,$D5,$F2,$F3,$E8,$E9,$F4,$F5,$EE,$EF,$00,$00,$00
    .byte $00,$00,$E8,$E9,$F4,$F5,$F2,$F3,$00,$00,$00,$00,$00,$CE,$CF,$EE
    .byte $EF,$DC,$DD,$D2,$D3,$D8,$D9,$D4,$D5,$00,$CC,$CD,$DA,$DB,$D4,$D5
    .byte $CC,$CD,$D2,$D3,$EE,$EF,$E8,$E9,$CC,$CD,$D2,$D3,$F0,$F1,$00,$00
    .byte $DC,$DD,$D0,$D1,$FC,$FD,$00,$00,$E6,$86,$F8,$08,$40,$40,$A6,$A6
    .byte $A6,$A7,$A7,$A7,$12,$20,$08,$0E,$0A,$0A,$01,$03,$02,$04,$03,$03
    .byte $0B,$04,$10,$0D,$07,$17

LA77C:
    cmp #$0D
    beq LA785

LA780:
    rts

LA781:
    cmp #$0F
    bne LA780

LA785:
    lda FX_PARAM_E9,x
    sta FX_SRC
    lda FX_PARAM_EA,x
    sta FX_SRC_HI
    lda FX_PARAM_30,x
    sta ZTMP_30
    lda FX_PARAM_EC,x
    sta FX_LEN
    lda FX_PARAM_EB,x
    sta FX_COUNT
    jmp LA659
; -----------------------------------------------------------------------
; Effect spawn/param helper code plus FX parameter tables, as data.
    .byte $10,$10,$B7,$10,$B9,$BB,$10,$BD,$10,$10,$10,$10,$10,$B8,$BC,$BA
    .byte $BE,$10,$10,$10,$17,$10,$15,$11,$0C,$1B,$0A,$1C,$12,$21,$10,$22
    .byte $A5,$E8,$D0,$73,$A9,$04,$C5,$44,$B0,$08,$C5,$45,$90,$69,$A5,$45
    .byte $10,$02,$A5,$44,$0A,$0A,$A8,$D0,$07,$BD,$B3,$4D,$C9,$14,$90,$1B
    .byte $BD,$B3,$4D,$C9,$0A,$90,$50,$C9,$23,$B0,$4C,$38,$F9,$B5,$A7,$18
    .byte $69,$04,$30,$04,$C9,$08,$90,$11,$BD,$B3,$4D,$C8,$38,$F9,$B5,$A7
    .byte $18,$69,$04,$30,$32,$C9,$08,$B0,$2E,$C8,$C8,$B9,$B5,$A7,$85,$98
    .byte $98,$4A,$90,$06,$A9,$AB,$A0,$A7,$D0,$04,$A9,$A1,$A0,$A7,$85,$24
    .byte $84,$25,$A9,$02,$85,$31,$A9,$00,$85,$97,$BD,$BB,$4D,$85,$99,$C9
    .byte $14,$B0,$04,$A9,$05,$85,$E8,$A4,$07,$60,$1C,$1E,$40,$20,$28,$26

; -----------------------------------------------------------------------
; Award any queued scoring events (SCORE_EVENT[]).
TALLY_SCORE_EVENTS:
    ldx #$07
    lda STATE_4DCB
    beq TALLY_ONE_EVENT
    lda SCORE_EVENT,x
    beq LA87E
    lda #$01
    sta SCORE_EVENT,x
    lda #$00
    jsr TALLY_ONE_EVENT
    ldy #$00
    jsr ADD_SCORE
    ldx #$07
    jmp LA87E

TALLY_ONE_EVENT:
    dec SCORE_EVENT,x
    bmi LA887
    php
    tax
    tay

LA869:
    plp
    php
    beq LA871
    lda TALLY_CHAR_TBL,y
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
LA871:
    lda #$40
    jsr PANEL_PUT_CHAR_PAIR
    iny
    cpy #$06
    bcc LA869
    plp
    ldx #$06

LA87E:
    lda #$00

LA880:
    sta SCORE_EVENT,x
    dex
    bpl LA880

LA886:
    rts

LA887:
    inc SCORE_EVENT,x
    dex
    bmi LA886

LA88D:
    dec SCORE_EVENT,x
    bmi LA887
    txa
    pha
    asl a
    tay
    jsr ADD_SCORE
    pla
    tax
    bpl LA88D
    brk
; -----------------------------------------------------------------------
; POINTS_TBL_HI plus the score-event delta table.
    .byte $00,$15,$00,$25,$00,$50,$01,$00,$05,$00,$07,$00,$15

; -----------------------------------------------------------------------
; Add POINTS_TBL[Y] to the BCD score, update high score / extra life, redraw.
ADD_SCORE:
    sed
    clc
    lda POINTS_TBL_LO,y
    adc SCORE_LO
    sta SCORE_LO
    tax
    lda POINTS_TBL_HI,y
    adc SCORE_MID
    sta SCORE_MID
    tay
    lda #$00
    adc SCORE_HI
    sta SCORE_HI
    bcc LA8C7
    inc SCORE_OVFL

LA8C7:
    cmp HISCORE_HI
    bcc LA8DD
    bne LA8D7
    cpy HISCORE_MID
    bcc LA8DD
    bne LA8D7
    cpx HISCORE_LO
    bcc LA8DD

LA8D7:
    sta HISCORE_HI
    sty HISCORE_MID
    stx HISCORE_LO

LA8DD:
    cmp NEXT_LIFE_SCORE
    bcc LA8FB
    clc
    lda NEXT_LIFE_SCORE
    adc TWO_PLAYER
    sta NEXT_LIFE_SCORE
    ldx LIVES
    cpx #$06
    bcs LA8FB
    inc LIVES
    ldy #$08
    jsr SOUND_REQ_V1

LA8FB:
    cld
    ldx #$E0
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
; -----------------------------------------------------------------------
; Render the BCD score digits into the status-panel screen rows.
DRAW_SCORE:
    ldx #$02
    stx SRC_PTR
    ldx #$00
    stx SRC_PTR_HI
    lda #$F0
    sta ZTMP_08
    ldy #$02
    lda SCORE_OVFL
    bne LA927
    iny

LA912:
    dey

LA913:
    lda (SRC_PTR),y
    and ZTMP_08
    bne LA927
    inx
    inx
    lda ZTMP_08
    eor #$FF
    sta ZTMP_08
    bmi LA912
    cpy #$00
    bne LA913

LA927:
    lsr ZTMP_08
    bcs LA934

LA92B:
    lda (SRC_PTR),y
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PANEL_PUT_DIGIT

LA934:
    lda (SRC_PTR),y
    and #$0F
    jsr PANEL_PUT_DIGIT
    dey
    bpl LA92B
    rts

; -----------------------------------------------------------------------
; PANEL_PUT_DIGIT/PANEL_PUT_CHAR_PAIR: write a 2-char cell pair into the panel.
PANEL_PUT_DIGIT:
    asl a
    clc
    adc #$60

PANEL_PUT_CHAR_PAIR:
    sta PANEL_SCR0,x
    sta PANEL_SCR1,x
    inx
    clc
    adc #$01
    sta PANEL_SCR0,x
    sta PANEL_SCR1,x
    inx
    rts

LA955:
    ldy #$01
    sty SRC_PTR
    ldy #$4D
    sty SRC_PTR_HI
    ldy #$01
    ldx #$14
    bne LA934
; -----------------------------------------------------------------------
; PANEL_ICON_TBL: status-panel indicator icon char-codes.
    .byte $80,$82,$84,$86

; -----------------------------------------------------------------------
; Draw the panel indicators: weapon/fuel icons, then EITHER the game timer
; (LA955, when EXTRA_LIFE_AVAIL=$00) OR the lives markers (when EXTRA_LIFE_AVAIL
; =$FF, i.e. the timer has expired) - which is why the timer vanishes at 0.
DRAW_STATUS_PANEL:
    ldx #$1C
    stx PANEL_X
    ldy #$00

LA96D:
    lda a:GUN_HEAT,y
    beq LA977
    lda PANEL_ICON_TBL,y
    bne LA979

LA977:
    lda #$40

LA979:
    jsr PANEL_PUT_CHAR_PAIR
    inx
    iny
    cpy #$04
    bne LA96D
    lda EXTRA_LIFE_AVAIL
    beq LA955
    ldx #$0E
    lda #$06
    sta ZTMP_08
    ldy LIVES
    bmi LA9A0

LA992:
    lda #$88
    dey
    bpl LA999
    lda #$40

LA999:
    jsr PANEL_PUT_CHAR_PAIR
    dec ZTMP_08
    bne LA992

LA9A0:
    rts

; -----------------------------------------------------------------------
; Scan the CIA1 keyboard/joystick matrix and return a key/joystick code.
SCAN_JOY_KEYS:
    lda #$FF
    sta CIA1_DDRA
    lda #$FE
    sta CIA1_PRA
    lda #$3F
    sec

LA9AE:
    sbc #$08
    tax
    lda CIA1_PRB
    rol CIA1_PRA
    eor #$FF
    bne LA9C0

LA9BB:
    txa
    bcs LA9AE
    bcc LA9F2

LA9C0:
    php
    pha
    txa
    pha
    lda CIA1_PRA
    pha
    lda #$FF
    sta CIA1_PRA
    lda CIA1_PRB
    eor #$FF
    beq LA9DF
    pla
    sta CIA1_PRA
    pla
    tax
    pla
    plp
    jmp LA9BB

LA9DF:
    pla
    sta CIA1_PRA
    pla
    tax
    pla
    plp

LA9E7:
    inx
    rol a
    bcc LA9E7

LA9EB:
    lda #$00
    sta CIA1_DDRA
    txa
    rts

LA9F2:
    ldx #$00
    beq LA9EB
    lda #$00
    ldx #$03

LA9FA:
    sta JOY_STATE,x
    dex
    bpl LA9FA
    jsr SCAN_JOY_KEYS
    ldx #$06

LAA05:
    dex
    bmi LAA16
    cmp KEYCODE_TBL,x
    bne LAA05
    lda KEYVAL_TBL,x
    ldy KEYIDX_TBL,x
    sta JOY_STATE,y

LAA16:
    rts
; -----------------------------------------------------------------------
; KEYCODE_TBL / KEYIDX_TBL / KEYVAL_TBL: console-key scan decode tables.
    .byte $1E,$1A,$15,$1D,$35,$33,$00,$00,$01,$01,$02,$03,$01,$FF,$01,$FF
    .byte $FF,$FF

; -----------------------------------------------------------------------
; Read the pause/mute console keys, debounce, toggle freeze/mute.
HANDLE_PAUSE_KEYS:
    lda SCROLL_SPEED
    pha

LAA2C:
    jsr SCAN_JOY_KEYS
    ldx #$02

LAA31:
    tay
    cmp PAUSEKEY_TBL,x
    bne LAA45
    cmp KEY_LAST,x
    beq LAA47
    dec KEY_DEBOUNCE,x
    bne LAA4B
    lda KEY_TOGGLE,x
    eor #$FF
    sta KEY_TOGGLE,x

LAA45:
    sty KEY_LAST,x

LAA47:
    ldy #$0A
    sty KEY_DEBOUNCE,x

LAA4B:
    dex
    bpl LAA31
    lda KEY_TOGGLE
    beq LAA5C
    lda #$00
    sta SCROLL_SPEED
    jsr SOUND_SILENCE
    jmp LAA2C

LAA5C:
    pla
    sta SCROLL_SPEED
    rts
; -----------------------------------------------------------------------
; PAUSEKEY_TBL: the three key scan codes HANDLE_PAUSE_KEYS watches.
    .byte $3C,$3A,$3B

; -----------------------------------------------------------------------
; Clear all 25 SID registers and set master volume $0F.
SID_INIT:
    jsr SOUND_SILENCE
    lda #$00
    ldx #$18

LAA6A:
    sta SID_V1_FLO,x
    dex
    bpl LAA6A
    lda #$0F
    sta SID_VOL
    rts

; -----------------------------------------------------------------------
; Request sound sequence Y on a SID voice.
SOUND_REQ_V0:
    lda SND_SEQ
    bne LAAA7

SOUND_REQ_V0B:
    lda #$00
    beq LAA8C
    lda SND_SEQ_V1
    bne LAAA7

SOUND_REQ_V1:
    lda #$01
    bne LAA8C
    lda SND_SEQ_V2
    bne LAAA7

SOUND_REQ_V2:
    lda #$02

LAA8C:
    stx ZTMP_08
    tax
    lda #$00
    sta SND_SEQ,x
    sta SND_POS,x
    sta SND_SLIDE_HI,x
    lda #$01
    sta SND_DUR,x
    lda SND_SEQPTR_LO,y
    sta SND_PTR0_LO,x
    lda SND_SEQPTR_HI,y
    sta SND_SEQ,x
    ldx ZTMP_08

LAAA7:
    rts

; -----------------------------------------------------------------------
; Gate off all three SID voices.
SOUND_SILENCE:
    txa
    pha
    lda #$00
    sta SID_V1_CTRL
    sta SID_V2_CTRL
    sta SID_V3_CTRL
    lda #$00
    ldx #$02

LAAB9:
    sta SND_SEQ,x
    dex
    bpl LAAB9
    pla
    tax
    rts

; -----------------------------------------------------------------------
; Per-frame SID player (called from the IRQ).
MUSIC_DRIVER:
    lda #$0E
    sta SND_REGOFS
    ldx #$02

LAAC7:
    stx SND_VOICE
    ldy SND_POS,x
    lda SND_SEQ,x
    beq LAAF6
    sta SND_SEQ_PTR_HI
    lda SND_PTR0_LO,x
    sta SND_SEQ_PTR
    cpy #$00
    bne LAAF2
    lda (SND_SEQ_PTR),y
    pha
    iny
    lda (SND_SEQ_PTR),y
    pha
    iny
    lda (SND_SEQ_PTR),y
    ldy SND_REGOFS
    sta SID_V1_SR,y
    pla
    sta SID_V1_AD,y
    pla
    sta SID_V1_CTRL,y
    ldy #$03

LAAF2:
    dec SND_DUR,x
    beq LAB03

LAAF6:
    sty SND_POS,x
    lda SND_REGOFS
    sec
    sbc #$07
    sta SND_REGOFS
    dex
    bpl LAAC7
    rts

LAB03:
    lda SND_SLIDE_HI,x
    beq LAB0A
    jmp LABBC

LAB0A:
    lda (SND_SEQ_PTR),y
    iny
    cmp #$00
    beq LAB14
    jmp LAB90

LAB14:
    lda (SND_SEQ_PTR),y
    iny
    asl a
    tax
    lda SNDCMD_VEC_HI,x
    pha
    lda SNDCMD_VEC_LO,x
    pha
    ldx SND_VOICE
    rts
; -----------------------------------------------------------------------
; SNDCMD_VEC_LO/HI plus the music command-handler code, as data.
    .byte $29,$AB,$38,$AB,$7A,$AB,$A9,$00,$95,$55,$A8,$A6,$4C,$9D,$04,$D4
    .byte $A6,$4B,$4C,$F6,$AA,$B1,$50,$C8,$29,$1F,$0A,$AA,$BD,$BB,$BC,$85
    .byte $4D,$BD,$BC,$BC,$85,$4E,$20,$04,$AC,$A5,$4D,$95,$61,$A5,$4E,$95
    .byte $5E,$B1,$50,$C8,$29,$1F,$0A,$AA,$BD,$BB,$BC,$85,$4D,$BD,$BC,$BC
    .byte $A6,$4B,$95,$64,$A5,$4D,$95,$67,$B1,$50,$C8,$95,$6D,$B1,$50,$C8
    .byte $95,$6A,$95,$58,$4C,$F6,$AA,$B1,$50,$C8,$95,$52,$48,$B1,$50,$C8
    .byte $95,$55,$85,$51,$68,$85,$50,$A0,$00,$4C,$03,$AB

LAB90:
    and #$3F
    asl a
    tax
    lda SND_FREQ_LO_TBL,x
    sta SND_PTR_LO
    lda SND_FREQ_HI_TBL,x
    sta SND_PTR_HI
    jsr SID_WRITE_FREQ
    dey
    lda (SND_SEQ_PTR),y
    iny
    rol a
    rol a
    rol a
    and #$03
    tax
    lda SND_DUR_TBL,x
    cpx #$00
    bne LABB5
    lda (SND_SEQ_PTR),y
    iny

LABB5:
    ldx SND_VOICE
    sta SND_DUR,x
    jmp LAAF6

LABBC:
    clc
    lda SND_SLIDE_LO,x
    bmi LABE3
    adc SND_FREQ_LO,x
    sta SND_FREQ_LO,x
    sta SND_PTR_LO
    bcc LABCB
    inc SND_SLIDE_HI,x

LABCB:
    lda SND_SLIDE_HI,x
    sta SND_PTR_HI
    cmp SND_TGT_LO,x
    bcc LABD9
    lda SND_FREQ_LO,x
    cmp SND_TGT_HI,x
    bcs LABFD

LABD9:
    jsr SID_WRITE_FREQ
    lda SND_RATE,x
    sta SND_DUR,x
    jmp LAAF6

LABE3:
    adc SND_FREQ_LO,x
    sta SND_FREQ_LO,x
    sta SND_PTR_LO
    bcs LABED
    dec SND_SLIDE_HI,x

LABED:
    lda SND_SLIDE_HI,x
    sta SND_PTR_HI
    lda SND_TGT_LO,x
    cmp SND_SLIDE_HI,x
    bcc LABD9
    lda SND_TGT_HI,x
    cmp SND_FREQ_LO,x
    bcc LABD9

LABFD:
    lda #$00
    sta SND_SLIDE_HI,x
    jmp LAB0A

; -----------------------------------------------------------------------
; Write a 16-bit frequency to the SID voice selected by SND_VOICE / SND_REGOFS.
SID_WRITE_FREQ:
    sty SND_TMP
    ldy SND_REGOFS
    ldx SND_VOICE
    lda SND_PTR_LO
    sta SID_V1_FLO,y
    lda SND_PTR_HI
    sta SID_V1_FHI,y
    ldy SND_TMP
    rts
; -----------------------------------------------------------------------
; ROAD_SEG_TBL and its road palette / pointer sub-tables (ROAD_PTR_*/ROAD_*),
; then the bulk graphics and audio data through $BFFF (charsets, sprite shapes,
; screen layouts, SID music tables) - emitted verbatim from the ROM below.
    .byte $1D,$1D,$02,$03,$08,$05,$06,$04,$07,$07,$07,$07,$07,$07,$10,$10
    .byte $09,$0E,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$0D,$0F,$0F,$0F,$0F,$11,$11
    .byte $12,$0B,$12,$0B,$13,$13,$12,$14,$15,$17,$16,$16,$1A,$1A,$18,$18
    .byte $19,$19,$1A,$1A,$1B,$1B,$1C,$1C,$01,$01,$01,$1E,$01,$01,$01,$1D
    .byte $EE,$EF,$F2,$01,$11,$16,$1B,$1D,$20,$29,$2B,$2C,$2F,$30,$36,$39
    .byte $3C,$3D,$40,$42,$44,$54,$55,$56,$58,$59,$5A,$5F,$60,$62,$62,$AC
    .byte $AC,$AC,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD
    .byte $AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$01,$03
    .byte $0F,$10,$05,$05,$02,$03,$09,$02,$01,$03,$01,$06,$03,$03,$01,$03
    .byte $02,$02,$10,$01,$01,$02,$01,$01,$05,$01,$02,$01,$01,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$04,$00,$04,$00,$00,$00,$04,$04,$00
    .byte $00,$00,$00,$04,$00,$04,$00,$00,$04,$00,$08,$08,$0B,$0B,$0C,$0B
    .byte $0B,$0B,$0C,$0B,$00,$05,$07,$0F,$07,$0F,$0F,$0F,$0F,$08,$07,$08
    .byte $01,$08,$01,$01,$01,$01,$01,$11,$12,$09,$11,$12,$09,$08,$07,$04
    .byte $06,$05,$10,$0B,$0A,$12,$09,$08,$10,$0C,$12,$09,$08,$07,$04,$06
    .byte $05,$0B,$11,$08,$07,$04,$06,$05,$10,$0D,$07,$04,$06,$05,$0D,$07
    .byte $04,$06,$05,$0D,$10,$0C,$13,$11,$08,$12,$09,$11,$0A,$12,$09,$08
    .byte $10,$0C,$04,$0C,$02,$06,$05,$0F,$01,$07,$04,$06,$05,$06,$05,$06
    .byte $05,$0D,$13,$11,$08,$02,$02,$03,$02,$14,$0E,$15,$14,$12,$09,$08
    .byte $07,$04,$07,$04,$06,$05,$06,$05,$0B,$11,$08,$10,$0F,$0C,$01,$04
    .byte $0D,$02,$07,$12,$09,$11,$08,$10,$00,$0A,$12,$19,$80,$20,$C0,$60
    .byte $C0,$40,$C0,$40,$C0,$40,$C0,$40,$C0,$A0,$80,$40,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$70,$29,$2A,$2A,$2B,$2B,$2F,$32,$36,$39,$3B
    .byte $3D,$40,$41,$44,$47,$4A,$C0,$C2,$C3,$C4,$C8,$CC,$D0,$00,$00,$67
    .byte $05,$05,$05,$03,$1C,$1C,$1C,$1C,$0C,$14,$14,$0C,$17,$17,$16,$16
    .byte $10,$08,$08,$20,$20,$20,$01,$01,$01,$01,$14,$0F,$0A,$04,$01,$01
    .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$0A,$1E,$0A,$01,$0A,$01
    .byte $01,$01,$01,$1A,$36,$36,$01,$09,$37,$37,$39,$10,$02,$00,$80,$36
    .byte $36,$01,$09,$37,$37,$39,$10,$02,$00,$80,$30,$36,$01,$09,$37,$31
    .byte $3B,$10,$02,$00,$80,$32,$33,$01,$09,$32,$33,$3D,$10,$02,$00,$80
    .byte $34,$36,$01,$09,$37,$35,$3F,$10,$02,$00,$80,$00,$00,$10,$07,$38
    .byte $36,$36,$01,$06,$00,$80,$10,$07,$38,$36,$36,$01,$06,$00,$80,$10
    .byte $07,$3A,$30,$36,$01,$06,$00,$80,$10,$07,$3C,$32,$33,$01,$06,$00
    .byte $80,$10,$07,$3E,$34,$36,$01,$06,$00,$80,$00,$00,$10,$0D,$38,$36
    .byte $36,$01,$0C,$37,$37,$39,$10,$01,$00,$00,$10,$0D,$38,$36,$36,$01
    .byte $0C,$37,$37,$39,$10,$01,$00,$00,$10,$0D,$3A,$30,$36,$01,$0C,$37
    .byte $31,$3B,$10,$01,$00,$00,$10,$0D,$3C,$32,$33,$01,$0C,$32,$33,$3D
    .byte $10,$01,$00,$00,$10,$0D,$3E,$34,$36,$01,$0C,$37,$35,$3F,$10,$01
    .byte $00,$00,$00,$00,$10,$28,$00,$02,$00,$00,$04,$08,$16,$1E,$01,$0C
    .byte $21,$19,$05,$08,$00,$01,$04,$09,$16,$1E,$01,$0C,$21,$19,$05,$07
    .byte $00,$03,$04,$0A,$16,$1E,$01,$0C,$21,$19,$05,$06,$00,$03,$04,$0B
    .byte $16,$1E,$01,$0C,$21,$19,$05,$05,$00,$03,$04,$0C,$16,$1E,$01,$0C
    .byte $21,$19,$05,$04,$00,$03,$04,$0D,$16,$1E,$01,$0C,$21,$19,$05,$03
    .byte $00,$03,$04,$0E,$16,$1E,$01,$0C,$21,$19,$05,$02,$00,$03,$04,$0F
    .byte $16,$1E,$01,$0C,$21,$19,$05,$01,$00,$01,$00,$01,$01,$04,$07,$14
    .byte $1C,$01,$07,$00,$83,$04,$06,$14,$1C,$01,$08,$00,$83,$04,$05,$14
    .byte $1C,$01,$09,$00,$83,$04,$04,$14,$1C,$01,$0A,$00,$83,$04,$03,$14
    .byte $1C,$01,$0B,$00,$83,$04,$02,$14,$1C,$01,$0C,$00,$83,$04,$01,$14
    .byte $1C,$01,$0D,$00,$83,$14,$1C,$01,$0D,$21,$00,$81,$14,$1C,$01,$0C
    .byte $1D,$2C,$00,$81,$00,$80,$04,$01,$1A,$22,$01,$0B,$1D,$15,$04,$02
    .byte $1A,$22,$01,$0B,$1D,$00,$01,$04,$01,$16,$1E,$01,$0B,$21,$19,$04
    .byte $03,$1A,$22,$01,$0B,$00,$01,$04,$02,$16,$1E,$01,$0B,$21,$19,$04
    .byte $03,$16,$1E,$01,$0A,$00,$00,$04,$02,$16,$1E,$01,$0B,$1D,$15,$04
    .byte $04,$1A,$22,$01,$09,$00,$01,$04,$03,$16,$1E,$01,$0B,$21,$19,$04
    .byte $04,$1A,$22,$01,$08,$00,$00,$04,$03,$1A,$22,$01,$0B,$1D,$15,$04
    .byte $05,$1A,$22,$01,$07,$00,$01,$04,$04,$16,$1E,$01,$0B,$1D,$15,$04
    .byte $05,$16,$1E,$01,$06,$00,$00,$04,$04,$16,$1E,$01,$0B,$21,$19,$04
    .byte $06,$16,$1E,$01,$05,$00,$00,$04,$05,$16,$1E,$01,$0B,$21,$19,$04
    .byte $06,$16,$1E,$01,$04,$00,$01,$04,$05,$16,$1E,$01,$0B,$1D,$15,$04
    .byte $07,$16,$1E,$01,$03,$00,$00,$04,$06,$16,$1E,$01,$0B,$21,$19,$04
    .byte $07,$1A,$22,$01,$02,$00,$01,$04,$06,$1A,$22,$01,$0C,$21,$19,$04
    .byte $07,$16,$1E,$01,$01,$00,$01,$04,$07,$1A,$22,$01,$0C,$1D,$15,$04
    .byte $07,$1A,$22,$00,$01,$04,$07,$16,$1E,$01,$0D,$21,$19,$04,$07,$16
    .byte $00,$01,$00,$01,$00,$26,$10,$0C,$29,$2D,$22,$01,$0C,$1D,$15,$04
    .byte $02,$00,$01,$26,$10,$0D,$25,$2D,$22,$01,$0C,$1D,$15,$04,$01,$00
    .byte $01,$26,$10,$0E,$29,$2D,$1C,$01,$0C,$21,$19,$00,$01,$2E,$2A,$10
    .byte $0E,$25,$2D,$1E,$01,$0C,$21,$00,$00,$2E,$26,$10,$0F,$29,$2D,$1E
    .byte $01,$0C,$00,$00,$2E,$2A,$10,$0F,$29,$2D,$2D,$1E,$01,$0B,$00,$00
    .byte $1A,$2E,$26,$10,$0F,$29,$2D,$2D,$1E,$01,$0A,$00,$00,$16,$2E,$2A
    .byte $10,$10,$25,$2D,$2D,$1E,$01,$09,$00,$00,$16,$2E,$26,$10,$10,$25
    .byte $2D,$19,$16,$1E,$01,$08,$00,$00,$04,$01,$16,$2E,$26,$10,$10,$25
    .byte $2D,$19,$16,$1E,$01,$07,$00,$00,$04,$01,$16,$2E,$26,$10,$10,$25
    .byte $2D,$19,$04,$01,$16,$1E,$01,$06,$00,$00,$04,$01,$16,$2E,$26,$10
    .byte $11,$25,$2D,$19,$04,$01,$16,$1E,$01,$05,$00,$00,$04,$02,$16,$2E
    .byte $26,$10,$11,$25,$2D,$19,$04,$01,$16,$1E,$01,$04,$00,$00,$04,$02
    .byte $16,$2E,$26,$10,$11,$25,$2D,$19,$04,$02,$16,$1E,$01,$03,$00,$00
    .byte $04,$03,$16,$2E,$2A,$10,$11,$25,$2D,$19,$04,$02,$16,$1E,$01,$02
    .byte $00,$00,$04,$03,$16,$2E,$26,$10,$11,$25,$2D,$19,$04,$03,$16,$1E
    .byte $01,$01,$00,$00,$04,$03,$16,$2E,$26,$10,$12,$29,$2D,$15,$04,$03
    .byte $16,$1E,$00,$00,$04,$03,$1A,$2E,$26,$10,$12,$29,$2D,$15,$04,$04
    .byte $16,$00,$00,$04,$04,$1A,$2E,$26,$10,$09,$00,$80,$00,$00,$10,$0C
    .byte $2B,$2F,$2F,$1C,$01,$0B,$23,$17,$04,$03,$00,$01,$10,$0B,$2B,$2F
    .byte $2F,$1C,$01,$0C,$23,$1B,$04,$03,$00,$00,$10,$0A,$2B,$2F,$2F,$1C
    .byte $01,$0C,$23,$17,$04,$04,$00,$01,$10,$09,$27,$2F,$17,$14,$1C,$01
    .byte $0C,$23,$1B,$04,$04,$00,$00,$10,$08,$2B,$2F,$17,$14,$1C,$01,$0C
    .byte $23,$1B,$04,$05,$00,$01,$10,$07,$2B,$2F,$17,$04,$01,$14,$1C,$01
    .byte $0C,$23,$1B,$04,$05,$00,$00,$10,$06,$2B,$2F,$1B,$04,$01,$14,$1C
    .byte $01,$0C,$23,$17,$04,$06,$00,$01,$10,$05,$2B,$2F,$17,$04,$02,$14
    .byte $1C,$01,$0C,$23,$17,$04,$06,$00,$00,$10,$04,$27,$2F,$1B,$04,$02
    .byte $14,$1C,$01,$0C,$23,$17,$04,$07,$00,$01,$10,$03,$27,$2F,$17,$04
    .byte $03,$14,$1C,$01,$0C,$1F,$17,$04,$07,$00,$00,$10,$02,$27,$2F,$1B
    .byte $04,$03,$14,$1C,$01,$0C,$23,$17,$04,$08,$00,$01,$10,$01,$2B,$2F
    .byte $17,$04,$04,$14,$1C,$01,$0C,$1F,$17,$04,$08,$00,$00,$27,$2F,$17
    .byte $04,$05,$14,$1C,$01,$0C,$1F,$17,$04,$08,$00,$01,$2F,$17,$04,$06
    .byte $14,$1C,$01,$0C,$1F,$17,$04,$08,$00,$00,$17,$04,$07,$14,$1C,$01
    .byte $0C,$1F,$17,$04,$08,$00,$00,$00,$00,$04,$08,$14,$1C,$01,$06,$00
    .byte $87,$00,$80,$04,$05,$14,$1C,$01,$09,$00,$83,$00,$80,$18,$20,$01
    .byte $0B,$21,$19,$04,$01,$00,$83,$00,$80,$04,$04,$14,$1C,$01,$05,$23
    .byte $1E,$01,$0D,$1D,$15,$04,$04,$00,$05,$04,$04,$14,$1C,$01,$04,$1F
    .byte $2F,$1E,$01,$0E,$1D,$15,$04,$03,$00,$05,$04,$04,$18,$20,$01,$04
    .byte $1F,$17,$16,$1E,$01,$0D,$1D,$15,$04,$03,$00,$04,$04,$03,$18,$20
    .byte $01,$04,$1F,$17,$04,$01,$16,$1E,$01,$0D,$1D,$15,$04,$03,$00,$04
    .byte $04,$03,$18,$20,$01,$04,$1F,$17,$04,$02,$16,$1E,$01,$0C,$1D,$15
    .byte $04,$03,$00,$04,$04,$02,$18,$20,$01,$04,$1F,$17,$04,$03,$16,$1E
    .byte $01,$0C,$1D,$15,$04,$03,$00,$04,$00,$00,$04,$04,$16,$2E,$26,$10
    .byte $09,$00,$8F,$00,$80,$04,$03,$14,$2C,$24,$10,$0B,$27,$26,$10,$06
    .byte $25,$2D,$15,$04,$04,$00,$04,$04,$02,$14,$2C,$24,$10,$0C,$27,$2D
    .byte $26,$10,$05,$25,$2D,$15,$04,$04,$00,$04,$04,$01,$14,$2C,$24,$10
    .byte $0C,$27,$2D,$2D,$26,$10,$05,$25,$2D,$15,$04,$04,$00,$04,$14,$2C
    .byte $24,$10,$0C,$27,$2D,$2D,$2D,$26,$10,$05,$25,$2D,$15,$04,$04,$00
    .byte $04,$2C,$24,$10,$0C,$27,$2C,$15,$14,$2D,$26,$10,$05,$25,$2D,$15
    .byte $04,$04,$00,$05,$24,$10,$0C,$27,$2C,$2C,$2C,$2C,$2C,$26,$10,$04
    .byte $25,$2D,$2D,$2D,$15,$04,$03,$00,$05,$00,$00,$00,$04,$02,$BC,$64
    .byte $54,$C4,$04,$02,$BC,$64,$5C,$D4,$04,$04,$BC,$44,$00,$08,$14,$04
    .byte $04,$BC,$54,$00,$04,$08,$02,$03,$BC,$1E,$00,$04,$08,$08,$0C,$BB
    .byte $9B,$00,$14,$16,$07,$05,$BB,$FB,$00,$14,$16,$02,$04,$BC,$24,$00
    .byte $08,$16,$02,$04,$BC,$2C,$00,$08,$16,$02,$04,$BC,$34,$00,$08,$16
    .byte $02,$04,$BC,$3C,$00,$08,$16,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $55,$55,$55,$55,$55,$55,$55,$55,$FF,$FF,$FF,$FF,$F7,$FF,$FF,$FF
    .byte $FF,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    .byte $48,$62,$48,$62,$98,$62,$88,$66,$98,$62,$98,$62,$59,$66,$58,$56
    .byte $80,$20,$00,$00,$88,$20,$00,$20,$88,$00,$82,$20,$88,$22,$88,$20
    .byte $2F,$BB,$EE,$BB,$2E,$BB,$EF,$BB,$2F,$BB,$EE,$BF,$2F,$BB,$2F,$BF
    .byte $22,$88,$22,$88,$22,$88,$22,$88,$55,$55,$55,$65,$55,$55,$A5,$A5
    .byte $55,$59,$55,$55,$40,$40,$55,$55,$55,$55,$A5,$A5,$55,$65,$55,$55
    .byte $55,$55,$59,$55,$55,$55,$55,$55,$AF,$AF,$AF,$AF,$AF,$AF,$AF,$AF
    .byte $AF,$AF,$AF,$AF,$AF,$AF,$AA,$AA,$AF,$AF,$AF,$AF,$FF,$FF,$AF,$AF
    .byte $AF,$AF,$AA,$AA,$AF,$AF,$AF,$AF,$56,$55,$57,$5A,$55,$6A,$59,$66
    .byte $ED,$6A,$79,$66,$9E,$49,$50,$54,$55,$55,$55,$55,$5A,$56,$A9,$BA
    .byte $9A,$66,$AA,$D6,$9A,$E6,$AA,$A6,$9A,$6A,$AA,$E6,$B9,$A6,$22,$98
    .byte $55,$55,$55,$55,$55,$56,$5B,$56,$55,$5D,$57,$59,$56,$5E,$57,$55
    .byte $56,$56,$56,$5A,$5E,$5A,$76,$59,$6A,$BA,$66,$DA,$9E,$A6,$BA,$AA
    .byte $BA,$66,$6A,$AA,$6E,$BA,$66,$26,$02,$40,$54,$54,$40,$55,$55,$55
    .byte $6A,$6A,$66,$D9,$76,$4D,$52,$56,$5A,$5A,$55,$51,$53,$54,$56,$55
    .byte $5A,$6A,$19,$26,$09,$72,$40,$43,$55,$95,$A5,$A5,$55,$A5,$A9,$A5
    .byte $A9,$69,$A9,$69,$59,$35,$15,$55,$55,$95,$A5,$A5,$A5,$95,$D5,$55
    .byte $65,$A9,$69,$AA,$6A,$9A,$6A,$EA,$5A,$79,$69,$7A,$EA,$6A,$E5,$4D
    .byte $E1,$A9,$A9,$6A,$9A,$D6,$2E,$41,$0A,$40,$50,$50,$52,$52,$42,$02
    .byte $A0,$01,$15,$95,$95,$95,$95,$85,$5B,$56,$5E,$56,$5D,$76,$59,$77
    .byte $6E,$77,$42,$50,$54,$55,$55,$55,$55,$55,$95,$A5,$A5,$E5,$A9,$A9
    .byte $A9,$A5,$A9,$A5,$9A,$6A,$AA,$65,$AA,$AD,$28,$51,$05,$25,$25,$25
    .byte $A9,$AA,$AA,$6A,$AA,$AA,$AA,$AA,$AA,$AA,$6A,$AA,$AA,$A6,$AA,$AA
    .byte $55,$55,$55,$55,$55,$55,$55,$55,$00,$00,$3F,$FE,$EA,$E2,$EA,$E2
    .byte $03,$FF,$FF,$AF,$2F,$2F,$AF,$2F,$C0,$33,$CC,$33,$CC,$33,$CC,$33
    .byte $00,$00,$CC,$33,$AC,$A3,$CC,$33,$E2,$EA,$FF,$C0,$2A,$AA,$2A,$0A
    .byte $AF,$FC,$02,$AA,$AA,$00,$00,$00,$CC,$33,$80,$AA,$AA,$00,$00,$00
    .byte $CC,$33,$CC,$03,$A8,$AA,$A8,$A0,$3F,$0F,$3F,$3F,$03,$F0,$FF,$3F
    .byte $FC,$FF,$0F,$C0,$FC,$FC,$F3,$F3,$FF,$3F,$3C,$FF,$FF,$F0,$F0,$C0
    .byte $F3,$FC,$3C,$FC,$F0,$00,$03,$03,$F0,$F3,$FF,$FF,$FC,$FC,$F0,$F0
    .byte $F0,$F0,$C0,$00,$00,$00,$00,$00,$3F,$0F,$3F,$3F,$3F,$FC,$F3,$F3
    .byte $CF,$CF,$3F,$FC,$FC,$FC,$F0,$F0,$FF,$0F,$3F,$3F,$FC,$FC,$FF,$3F
    .byte $CF,$CF,$3F,$3F,$FC,$FC,$F0,$F0,$FF,$CF,$0F,$3F,$3F,$FC,$FC,$FC
    .byte $C3,$CF,$CF,$CF,$FF,$FF,$FC,$FC,$FF,$CF,$C0,$03,$03,$0F,$0F,$0F
    .byte $FF,$FF,$FC,$FC,$F0,$F0,$C0,$C0,$FF,$CF,$3F,$3F,$3F,$FC,$FF,$FF
    .byte $FF,$FF,$00,$F0,$C0,$03,$F3,$F3,$FF,$3F,$FC,$FF,$FF,$F3,$F3,$C3
    .byte $F0,$FC,$3C,$FC,$F0,$C0,$F0,$F0,$FC,$33,$33,$33,$00,$00,$00,$00
    .byte $00,$CF,$33,$33,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$55,$00,$55
    .byte $00,$00,$00,$03,$FA,$5A,$AA,$55,$00,$00,$3A,$AA,$A8,$A3,$A8,$55
    .byte $00,$00,$AA,$BE,$FA,$E8,$28,$55,$00,$00,$AB,$AA,$3F,$FF,$00,$55
    .byte $00,$00,$00,$B0,$AC,$EB,$0A,$56,$00,$00,$00,$00,$00,$C0,$BC,$AB
    .byte $AA,$55,$55,$00,$00,$FF,$FF,$FF,$AA,$AA,$5F,$3F,$EC,$FE,$FF,$FF
    .byte $AA,$AA,$F5,$FC,$3E,$3C,$FC,$F0,$AA,$AA,$55,$00,$AA,$AA,$00,$00
    .byte $A9,$AA,$5F,$3F,$BC,$3E,$EF,$0F,$5A,$A5,$FA,$FE,$3E,$3C,$FC,$F0
    .byte $B0,$AB,$56,$A9,$AB,$AB,$00,$00,$00,$00,$B0,$AC,$F0,$F0,$00,$00
    .byte $AA,$28,$AA,$AA,$AA,$28,$BE,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
    .byte $0C,$00,$0C,$DF,$34,$30,$D0,$F0,$70,$C0,$30,$1C,$88,$30,$0C,$00
    .byte $3C,$31,$07,$33,$00,$00,$00,$00,$10,$0C,$80,$30,$00,$C0,$00,$00
    .byte $FF,$FE,$C8,$EA,$A2,$EA,$FB,$FF,$BB,$7E,$88,$EA,$A2,$EA,$7B,$EE
    .byte $03,$0F,$3C,$33,$0F,$3C,$0F,$03,$4B,$2F,$BC,$33,$8F,$BC,$4F,$23
    .byte $57,$5F,$7C,$73,$5F,$7C,$5F,$57,$0B,$2F,$2B,$BE,$3F,$BF,$BB,$2A
    .byte $0B,$6F,$2B,$BE,$7F,$BF,$BB,$2A,$5B,$6F,$6B,$BE,$7F,$BF,$BB,$6A
    .byte $F0,$C0,$C0,$00,$C0,$00,$00,$C0,$B0,$C0,$80,$C0,$00,$00,$C0,$80
    .byte $AF,$AF,$AE,$AA,$EA,$EB,$EB,$EB,$FA,$FA,$FE,$FE,$FE,$FF,$FF,$FF
    .byte $FF,$BF,$BF,$BF,$AF,$AF,$AF,$AE,$EA,$EA,$EB,$FB,$FA,$FA,$FE,$FF
    .byte $FF,$0F,$3D,$3B,$3B,$3B,$39,$35,$37,$3F,$2F,$2F,$2F,$2F,$2F,$3B
    .byte $3D,$3D,$2F,$0F,$0B,$02,$FF,$03,$0F,$00,$00,$00,$00,$00,$00,$3F
    .byte $BF,$F9,$DD,$DD,$DD,$F9,$BF,$3F,$00,$00,$00,$00,$00,$00,$AA,$EA
    .byte $7F,$FF,$FF,$FF,$7F,$EA,$AA,$00,$00,$00,$00,$00,$00,$E0,$F8,$7E
    .byte $DF,$DF,$DF,$7E,$F8,$E0,$FF,$03,$0F,$0F,$3F,$36,$F7,$DF,$EF,$FB
    .byte $3D,$3D,$0F,$02,$00,$00,$00,$00,$00,$C0,$F0,$B8,$DE,$5E,$7F,$FF
    .byte $FF,$7F,$FF,$BD,$2F,$0B,$02,$00,$00,$00,$00,$00,$80,$E0,$F8,$78
    .byte $7E,$7E,$FA,$F8,$E0,$A0,$FF,$FF,$3A,$2A,$2F,$3A,$3B,$55,$AA,$AA
    .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$00,$00,$00,$00,$00,$03,$00,$15
    .byte $AB,$AA,$AB,$AB,$AB,$AB,$AB,$AD,$00,$58,$9A,$95,$95,$9A,$95,$95
    .byte $9A,$00,$95,$9A,$95,$97,$9D,$9F,$97,$95,$9A,$00,$00,$01,$0C,$3A
    .byte $0D,$AC,$00,$00,$03,$00,$15,$AB,$AA,$AB,$AB,$AB,$AB,$AB,$AD,$00
    .byte $58,$9A,$95,$95,$9A,$95,$95,$9A,$00,$95,$9A,$95,$97,$9D,$9F,$97
    .byte $95,$9A,$00,$00,$00,$03,$15,$00,$00,$08,$0A,$0A,$02,$8A,$AA,$AA
    .byte $AE,$AB,$2B,$0A,$2B,$2B,$AA,$8A,$0A,$08,$08,$00,$20,$A0,$A0,$A8
    .byte $A8,$A8,$BA,$BA,$BE,$FE,$FA,$FA,$FA,$FA,$AE,$AA,$AA,$0A,$02,$02
    .byte $00,$00,$00,$00,$80,$80,$A0,$80,$80,$80,$00,$00,$00,$80,$A0,$80
    .byte $00,$00,$80,$80,$80,$80,$FF,$03,$15,$55,$41,$40,$4B,$4F,$4F,$7F
    .byte $43,$13,$20,$20,$08,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40
    .byte $50,$24,$28,$08,$C2,$F3,$FF,$FD,$FD,$FD,$D5,$57,$01,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$40,$40
    .byte $50,$D0,$54,$54,$15,$15,$07,$33,$FF,$FF,$01,$05,$14,$13,$1F,$23
    .byte $23,$1F,$07,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
    .byte $02,$0C,$00,$00,$50,$08,$12,$00,$09,$02,$04,$01,$0A,$A0,$01,$00
    .byte $01,$48,$92,$04,$48,$10,$A0,$00,$00,$00,$FF,$FF,$0F,$37,$15,$1D
    .byte $15,$1E,$1E,$1C,$20,$20,$2D,$2D,$2D,$25,$1D,$1D,$1D,$15,$15,$15
    .byte $05,$00,$FF,$0F,$37,$16,$16,$16,$1F,$15,$1D,$15,$1D,$15,$1F,$17
    .byte $05,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$35,$1A,$2A,$2A,$2A,$2A
    .byte $2A,$2A,$20,$00,$0A,$2A,$2A,$2A,$2A,$2A,$20,$20,$2A,$0A,$00,$00
    .byte $FF,$0C,$3B,$3B,$2F,$2F,$2E,$29,$25,$27,$2F,$2F,$2F,$2B,$26,$19
    .byte $0A,$02,$00,$00,$00,$00,$00,$03,$15,$00,$00,$03,$0E,$39,$39,$39
    .byte $39,$39,$39,$39,$39,$39,$0E,$03,$30,$0C,$C0,$33,$00,$C0,$3C,$EB
    .byte $96,$69,$55,$BE,$D7,$BE,$55,$AA,$AA,$FF,$AA,$55,$FF,$00,$CC,$00
    .byte $00,$00,$00,$00,$00,$C0,$B0,$6C,$6C,$6C,$6C,$6C,$6C,$6C,$6C,$6C
    .byte $B0,$C0,$0C,$30,$03,$CC,$00,$03,$01,$2D,$C0,$2F,$03,$30,$30,$31
    .byte $00,$32,$0C,$33,$0C,$34,$33,$35,$30,$36,$C3,$38,$C3,$39,$30,$3B
    .byte $0C,$3C,$0C,$3E,$30,$00,$00,$00,$01,$06,$3C,$FF,$FF,$FF,$FF,$3C
    .byte $00,$02,$14,$00,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .byte $02,$02,$02,$02,$02,$02,$03,$FC,$57,$A9,$A9,$A9,$01,$01,$55,$55
    .byte $55,$55,$55,$01,$56,$FE,$FE,$56,$46,$CE,$03,$02,$0F,$3D,$11,$F0
    .byte $2A,$3E,$2C,$F0,$4C,$31,$4E,$30,$4F,$0D,$51,$C0,$52,$31,$54,$30
    .byte $67,$32,$69,$30,$6A,$0E,$6C,$C0,$6D,$32,$6F,$30,$00,$00,$00,$02
    .byte $11,$00,$00,$00,$02,$03,$03,$00,$00,$01,$01,$00,$00,$00,$00,$00
    .byte $00,$00,$20,$20,$20,$CE,$03,$23,$AB,$EC,$FC,$FD,$75,$54,$54,$20
    .byte $20,$20,$20,$00,$03,$0C,$82,$A3,$2A,$20,$30,$AF,$03,$00,$00,$00
    .byte $00,$00,$00,$00,$F0,$A0,$AC,$AD,$FD,$FD,$15,$05,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$80,$A0,$20,$FF,$02,$0E,$02,$0A,$2A
    .byte $2A,$A0,$A5,$9F,$9F,$AA,$90,$90,$8A,$8A,$8A,$80,$50,$54,$54,$55
    .byte $55,$F5,$F5,$95,$15,$15,$85,$85,$85,$02,$00,$6D,$30,$C0,$30,$C0
    .byte $00,$C0,$00,$AA,$C0,$0C,$C0,$30,$C0,$00,$C0,$00,$00,$00,$02,$0B
    .byte $0B,$3B,$B8,$B8,$BB,$8B,$0B,$38,$3B,$38,$30,$80,$B0,$B8,$B8,$B8
    .byte $88,$80,$B0,$B0,$B0,$30,$02,$00,$64,$0C,$30,$C0,$30,$C0,$00,$A4
    .byte $30,$0C,$C0,$30,$C0,$0C,$C0,$00,$00,$00,$FF,$01,$06,$19,$67,$5D
    .byte $75,$75,$15,$16,$15,$14,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $02,$00,$64,$0C,$30,$C0,$30,$C0,$00,$A4,$30,$0C,$C0,$30,$C0,$0C
    .byte $C0,$00,$00,$00,$03,$14,$00,$07,$3F,$77,$DF,$37,$05,$02,$22,$AE
    .byte $A9,$29,$0A,$29,$29,$0A,$0A,$02,$00,$00,$F0,$FF,$FF,$FF,$FF,$7F
    .byte $FD,$7F,$BD,$7E,$FA,$7A,$7A,$6A,$AA,$AA,$A2,$82,$80,$80,$00,$40
    .byte $C0,$F0,$FC,$F4,$D0,$40,$80,$A0,$A0,$A0,$80,$80,$80,$80,$A0,$A0
    .byte $00,$00,$00,$02,$15,$00,$03,$3F,$7F,$EF,$3B,$0B,$00,$3C,$1F,$1B
    .byte $37,$0F,$07,$1E,$05,$27,$16,$2F,$2E,$28,$F8,$FE,$FF,$FF,$FD,$BC
    .byte $F8,$F0,$80,$18,$B4,$74,$F8,$F4,$E8,$7C,$E8,$F4,$BC,$AC,$18,$00
    .byte $02,$10,$10,$F4,$BE,$FF,$7F,$76,$DD,$3F,$1F,$7B,$15,$9F,$5B,$BE
    .byte $BA,$A0,$00,$30,$E0,$F0,$60,$D0,$D0,$E0,$D0,$A0,$F0,$A0,$D0,$F0
    .byte $B0,$60,$00,$FF,$54,$44,$44,$54,$44,$44,$54,$44,$44,$54,$44,$44
    .byte $54,$44,$44,$54,$44,$44,$54,$44,$44,$00,$01,$02,$00,$AA,$03,$00
    .byte $43,$03,$AA,$30,$AA,$03,$AA,$AA,$C0,$03,$03,$03,$C0,$AA,$AA,$03
    .byte $AA,$C0,$AA,$03,$00,$83,$03,$AA,$33,$0C,$C0,$33,$0F,$3F,$CF,$3F
    .byte $03,$C0,$0C,$03,$30,$AA,$03,$00,$C3,$0C,$08,$08,$08,$08,$08,$08
    .byte $00,$00,$00,$01,$08,$40,$40,$40,$40,$40,$40,$40,$40,$00,$01,$0B
    .byte $30,$64,$64,$64,$64,$64,$64,$20,$20,$98,$88,$00,$02,$08,$70,$88
    .byte $64,$10,$B8,$0C,$4C,$04,$0E,$11,$26,$08,$1D,$30,$32,$20,$00,$02
    .byte $0A,$07,$0F,$3F,$7F,$FF,$FF,$FF,$7F,$3F,$07,$80,$E0,$F0,$F8,$F8
    .byte $F0,$E0,$E0,$C0,$00,$00,$00,$01,$02,$03,$04,$0D,$15,$1D,$26,$31
    .byte $3A,$3B,$46,$00,$71,$71,$71,$71,$71,$71,$71,$71,$6B,$5A,$43,$6B
    .byte $42,$5A,$43,$4D,$4C,$52,$47,$48,$66,$52,$57,$4B,$5A,$52,$70,$6F
    .byte $50,$47,$52,$60,$4C,$5A,$52,$6F,$70,$6D,$43,$4D,$6B,$50,$70,$6F
    .byte $6F,$70,$57,$45,$56,$52,$6F,$70,$70,$6F,$51,$4D,$4A,$4E,$70,$6F
    .byte $70,$70,$48,$43,$42,$50,$49,$70,$6F,$51,$51,$41,$6A,$52,$48,$51
    .byte $52,$57,$4E,$4F,$4A,$45,$4A,$6C,$40,$4F,$4A,$4B,$71,$71,$71,$71
    .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$6B,$5A,$42,$66,$53
    .byte $66,$4D,$52,$48,$52,$70,$48,$51,$60,$5A,$52,$50,$6F,$53,$48,$57
    .byte $4A,$45,$4E,$4F,$6C,$44,$4B,$6B,$6E,$6A,$6D,$71,$6C,$71,$71,$5A
    .byte $60,$58,$5E,$56,$5C,$61,$5B,$5F,$59,$5D,$57,$71,$71,$71,$71,$66
    .byte $71,$64,$71,$62,$71,$67,$71,$65,$71,$63,$71,$71,$71,$71,$68,$69
    .byte $71,$42,$48,$49,$43,$40,$46,$47,$41,$71,$44,$45,$71,$71,$54,$55
    .byte $71,$4C,$52,$53,$4D,$4A,$50,$51,$4B,$71,$4E,$4F,$71,$76,$77,$78
    .byte $79,$72,$73,$74,$75,$20,$98,$9A,$55,$9A,$98,$20,$00,$00,$00,$A8
    .byte $55,$A8,$00,$00,$00,$09,$99,$95,$A5,$29,$2A,$00,$00,$40,$58,$56
    .byte $56,$56,$68,$A0,$00,$00,$00,$2A,$6A,$20,$80,$00,$00,$00,$00,$AA
    .byte $00,$00,$00,$00,$00,$FF,$FF,$57,$77,$57,$FF,$FF,$00,$FF,$FF,$77
    .byte $77,$75,$FF,$FF,$00,$10,$2A,$45,$45,$45,$2A,$10,$00,$40,$A0,$A4
    .byte $44,$A4,$A0,$40,$EF,$0E,$DF,$1D,$0C,$07,$18,$0E,$31,$1C,$63,$38
    .byte $C7,$70,$D2,$0F,$A5,$1F,$4B,$3F,$97,$7E,$C3,$11,$86,$23,$0C,$47
    .byte $61,$08,$87,$21,$DF,$27,$68,$09,$D1,$12,$A2,$25,$47,$05,$8F,$0A
    .byte $1F,$15,$3E,$2A,$7D,$54,$ED,$05,$B5,$17,$30,$0B,$60,$16,$C1,$2C
    .byte $83,$59,$A7,$06,$4E,$0D,$9C,$1A,$39,$35,$47,$06,$8F,$0C,$1E,$19
    .byte $3C,$32,$BE,$3B,$6B,$2F,$BF,$4F,$0F,$43,$00,$00,$00,$03,$06,$0C
    .byte $45,$BD,$45,$BD,$5B,$BD,$70,$BE,$8F,$BE,$9D,$BE,$A8,$BE,$B1,$BE
    .byte $BA,$BE,$C3,$BE,$CC,$BE,$DF,$BE,$E6,$BE,$05,$BF,$30,$BF,$43,$BF
    .byte $4A,$BF,$55,$BF,$5F,$BF,$67,$BF,$8A,$BF,$9B,$BF,$A2,$BF,$11,$00
    .byte $F1,$94,$AB,$94,$AB,$99,$AB,$94,$AB,$A3,$9F,$94,$AB,$C2,$9F,$AB
    .byte $00,$02,$48,$BD,$11,$00,$E1,$2B,$C0,$2B,$60,$13,$54,$08,$60,$EB
    .byte $13,$60,$C8,$1D,$18,$97,$90,$93,$8C,$8F,$88,$81,$84,$A1,$A5,$EB
    .byte $C7,$D2,$D6,$DC,$2B,$04,$DC,$2B,$04,$DC,$2B,$04,$1C,$10,$16,$10
    .byte $12,$10,$07,$10,$03,$10,$07,$10,$E4,$20,$30,$20,$18,$E0,$2B,$10
    .byte $D7,$2B,$04,$D7,$2B,$04,$D7,$2B,$04,$D7,$2B,$04,$D7,$2B,$04,$2B
    .byte $60,$2B,$30,$10,$04,$D7,$10,$04,$17,$08,$2B,$04,$17,$10,$17,$60
    .byte $93,$97,$93,$88,$D3,$D7,$17,$30,$2B,$30,$10,$04,$D7,$10,$04,$17
    .byte $08,$2B,$04,$17,$08,$17,$08,$17,$60,$93,$97,$93,$88,$93,$97,$93
    .byte $88,$A5,$9A,$96,$8B,$87,$8B,$96,$9A,$A5,$A1,$A5,$A1,$A5,$A1,$A5
    .byte $A1,$A5,$A1,$A5,$A1,$A5,$A1,$A5,$A1,$A5,$A1,$A5,$A1,$A5,$A1,$A5
    .byte $A1,$A5,$A1,$A5,$A1,$A5,$A1,$EB,$2B,$30,$10,$04,$D7,$10,$04,$17
    .byte $08,$2B,$04,$17,$08,$17,$08,$17,$60,$00,$02,$14,$BE,$93,$97,$93
    .byte $88,$93,$97,$93,$88,$A5,$9A,$96,$8B,$88,$84,$A5,$96,$92,$8B,$87
    .byte $A0,$87,$92,$A0,$97,$93,$88,$84,$A1,$96,$92,$87,$A0,$95,$91,$97
    .byte $93,$88,$84,$A1,$96,$57,$53,$48,$61,$49,$45,$62,$57,$62,$57,$53
    .byte $49,$57,$53,$48,$61,$57,$48,$44,$61,$58,$49,$45,$62,$49,$62,$57
    .byte $53,$49,$62,$57,$53,$62,$57,$53,$48,$57,$48,$44,$61,$48,$61,$56
    .byte $52,$56,$52,$47,$60,$15,$60,$00,$00,$11,$00,$E1,$2B,$60,$2B,$60
    .byte $2B,$60,$21,$60,$21,$54,$EB,$21,$60,$C8,$13,$18,$8C,$8F,$88,$81
    .byte $84,$A1,$A5,$9A,$9C,$96,$00,$00,$11,$00,$F1,$26,$08,$6B,$26,$08
    .byte $6B,$26,$08,$6B,$00,$00,$11,$00,$F1,$00,$01,$0D,$13,$DD,$01,$00
    .byte $00,$81,$09,$00,$4E,$D7,$93,$53,$00,$00,$81,$00,$84,$64,$6B,$64
    .byte $6B,$00,$00,$81,$00,$C0,$61,$6B,$65,$6B,$00,$00,$81,$08,$86,$45
    .byte $46,$45,$6B,$00,$00,$81,$00,$56,$00,$01,$07,$09,$7F,$01,$06,$30
    .byte $00,$01,$09,$07,$81,$01,$00,$00,$81,$00,$60,$64,$6B,$00,$00,$11
    .byte $00,$61,$4E,$51,$4E,$55,$4E,$5B,$4E,$64,$66,$4B,$66,$4B,$66,$4B
    .byte $66,$4B,$66,$4B,$66,$4B,$66,$4B,$66,$4B,$66,$4B,$00,$00,$21,$C0
    .byte $F0,$0E,$01,$2B,$02,$0E,$01,$2B,$02,$0E,$01,$2B,$02,$0E,$01,$2B
    .byte $02,$0E,$01,$2B,$02,$0E,$01,$2B,$02,$0E,$01,$2B,$02,$0E,$01,$2B
    .byte $02,$0E,$01,$2B,$02,$00,$02,$08,$BF,$21,$0D,$00,$0E,$01,$2B,$02
    .byte $0E,$01,$2B,$02,$0E,$01,$2B,$02,$00,$02,$33,$BF,$81,$0B,$00,$0E
    .byte $90,$00,$00,$11,$0B,$04,$C3,$AB,$03,$30,$03,$18,$00,$00,$81,$06
    .byte $89,$0F,$18,$0A,$18,$5E,$00,$00,$81,$00,$AA,$06,$18,$69,$00,$00
    .byte $11,$00,$81,$00,$01,$0D,$27,$81,$01,$00,$01,$2A,$05,$81,$01,$00
    .byte $01,$09,$22,$81,$01,$00,$01,$27,$26,$81,$01,$00,$01,$05,$28,$81
    .byte $01,$00,$00,$11,$00,$80,$0D,$01,$2B,$02,$0A,$01,$00,$01,$10,$0F
    .byte $81,$01,$00,$00,$81,$C8,$00,$06,$78,$00,$00,$81,$08,$00,$0E,$18
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$00,$00
