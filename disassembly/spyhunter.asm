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
; 6502 PRIMER  (for readers who know programming but not assembly)
;   This whole program is machine code for the 6502 CPU. There's no compiler:
;   every line below is either one CPU instruction or one byte of raw data.
;   If you already know 6502, skip this section - everything past here assumes
;   it. Otherwise, keep this as your cheat sheet; later comments lean on it
;   instead of re-explaining these terms every time.
;
;   REGISTERS - the CPU has just a handful of tiny (8-bit, 0-255) storage
;   slots built into the chip itself (nothing like a modern CPU's dozens):
;     A (accumulator) - the main "working" value; almost every calculation
;                        goes through A (think of it as the one variable
;                        every arithmetic/logic op implicitly uses).
;     X, Y             - general-purpose "index" registers. Mainly used to
;                         walk through arrays: e.g. "LDA TABLE,X" loads
;                         TABLE[X]. Also used as small loop counters.
;     S (stack ptr)    - tracks the top of the hardware stack (see JSR/RTS
;                         below). Rarely touched directly.
;     P (status/flags) - one bit per condition, set automatically by most
;                         instructions. The ones you'll see checked constantly:
;                           Z (zero)     - set when a result was 0
;                           C (carry)    - set on unsigned overflow/borrow,
;                                          and doubles as the "extra bit" for
;                                          shifts and multi-byte add/subtract
;                           N (negative) - set when bit 7 of the result is 1
;                     There is no separate program-counter register comment
;                     needed here - just know it's what advances through the
;                     code automatically; JMP/JSR/branches change it directly.
;
;   MEMORY & ADDRESSING - a 6502 only ever reads/writes 8 bits (1 byte) at a
;   time, and addresses are 16-bit (0000-$FFFF, i.e. 0-65535), so a 16-bit
;   address is always stored/loaded as TWO bytes: a low byte and a high byte
;   (hence all the "_LO"/"_HI" equate pairs below - together they form one
;   address, e.g. SCROLL_SRC/SCROLL_SRC_HI). You'll see several ADDRESSING
;   MODES, distinguished by syntax:
;     lda #$05        - IMMEDIATE: load the literal number 5 into A.
;     lda $44          - ABSOLUTE/ZERO PAGE: load the BYTE STORED AT address
;                        $44 into A (i.e. treat $44 as a variable, not a value).
;     lda TABLE,x      - ABSOLUTE,X / ZERO PAGE,X: load TABLE[x] - X is added
;                        to the address first. (,y works the same way.)
;     lda (PTR),y      - INDIRECT INDEXED: PTR is a zero-page variable that
;                        holds a 16-bit address (2 bytes: PTR/PTR+1); read
;                        the address it points to, add y, and load THAT byte.
;                        This is the 6502's version of a pointer/array access
;                        and shows up constantly for walking ROM data tables.
;     jmp (VEC)        - similar, but jumps through a stored address - the
;                        6502's version of a function pointer/vtable.
;   ZERO PAGE ($0000-$00FF) is just the first 256 bytes of RAM, but
;   instructions that address it are shorter and faster than normal absolute
;   addressing - so this program (like most 6502 code) keeps its most
;   frequently-used variables and pointers there. When you see a short
;   zero-page equate (e.g. ROAD_FEATURE = $44) being read/written constantly,
;   that's why: it's being used as a fast global variable.
;
;   THE STACK & SUBROUTINES - JSR (jump to subroutine) pushes the return
;   address onto the hardware stack (which lives at $0100-$01FF) and jumps;
;   RTS pops that address back off and returns - this program's version of a
;   function call/return. PHA/PLA push and pop A onto/off the same stack (a
;   scratch save-and-restore, since there are no other spare registers).
;
;   COMMON INSTRUCTIONS you'll see everywhere (full mnemonic = operation):
;     LDA/LDX/LDY  load A/X/Y            STA/STX/STY  store A/X/Y to memory
;     TAX/TXA/TAY/TYA  copy between A and X/Y (transfer)
;     INC/DEC  add/subtract 1 from a memory byte;  INX/DEX/INY/DEY  same for X/Y
;     CMP/CPX/CPY  compare (subtract without storing the result, just set flags)
;     AND/ORA/EOR  bitwise AND / OR / XOR;  ASL/LSR  shift left/right (x2, /2)
;     BIT  test bits against a memory value without changing A (flags only)
;     SEI/CLI  disable/enable interrupts;  SEC/CLC  set/clear the carry flag
;   BRANCHES test one flag and jump only if it matches, otherwise fall through
;   to the next line (this is how every if/while loop in this file is built):
;     BEQ/BNE  branch if Z set/clear (i.e. "if equal" / "if not equal", after
;              a CMP)                BCS/BCC  branch if carry set/clear
;     BPL/BMI  branch if N clear/set (i.e. "if positive" / "if negative" -
;              often used as a cheap "is bit 7 set?" test on a byte, since N
;              just mirrors bit 7 of the last loaded/computed value)
;
;   HEX & BCD - a leading "$" means hexadecimal (base 16), e.g. $44 = 68
;   decimal. Scores/timers in this game are BCD (binary-coded decimal): each
;   byte holds two decimal digits, one per nibble (so BCD byte $19 means the
;   decimal number "19", not 25) - that's why score/timer math in this file
;   uses SED (decimal mode) instead of plain binary ADC/SBC.
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
;   ON-ROAD TEXT / "GAME OVER" (snapshot "game over"):
;     1. On-road text ("GAME OVER", plus road signs) is drawn by DRAW_OBJECT_TILES
;        - the SAME blitter as the van/smoke/hazards - as playfield MAP TILES,
;        not sprites and not the status panel.
;     2. Letters are 2-cell multicolour font-glyph pairs from charset $7000,
;        mapped alphabetically: letter L -> ($CC+2L,$CD+2L) (A=$CC/$CD ... G=
;        $D8/$D9 ... O=$E8/$E9 ... R=$EE/$EF ... Z=$FE/$FF).
;     3. Message strings live in ROM at ONROAD_MSG_TBL ($A6E6), $00-separated:
;        KEY/OR/JOY/OVER/GAME/ON/LEFT/DETOUR/OUT/BRIDGE/AHEAD/ROADS/ICY.  "GAME
;        OVER" = GAME ($A700) drawn on screen row 10 over OVER ($A6F8) on row 11.
;     4. Blitted into BOTH play buffers ($7800 and $7C00) so it survives the
;        raster buffer-flip; the road scroll is frozen (SCROLL_SPEED=$00) on game
;        over so the text overlays the road and stays put.
;
;   BOAT / BROKEN BRIDGE (snapshots "become boat", "crash into water", "skip broken
;   bridge return to road"):
;     1. ROAD_FEATURE $44=$02 is the boat/water-crossing row (segment $11, rows
;        $02/$03/$02 played in that order - boat, an unidentified $03 row, boat
;        again). Reached from the river-entrance segment $0F (feature $13).
;     2. ROAD_FEATURE $44=$0F is a scripted "broken bridge, return to road" segment
;        transition (segment $0B, the boat segment's branch target: rows $0F/$05/$06
;        played in that order) - not an in-the-moment player hazard.
;     3. Both index the SAME generic OBJ_ADDR_LO/HI graphics table as ordinary road
;        rows ($02->SCROLL_SRC=$2AC0, $0F->$4A40) - no special-case blitter. That
;        table is exactly 16 entries ($00-$0F), spanning RAM $2980-$4CFF and ending
;        right at the $4D00 game-state boundary; feature codes $10+ fall outside its
;        clean address progression and several ($11/$13/$14/$15) are separately
;        checked by CMP #imm branches (UPDATE_SCENE_SELECT and others) as
;        scene-transition triggers rather than plain tile indices.
;     4. "Enemy unshootable" (near the bridge) is VERY LIKELY just the Road Lord:
;        the official manual (claude/Enemy_Agents_Manual_Reference.md, extracted
;        from original_files/Spy_Hunter_1984_Sega_text.pdf) documents 6 Enemy
;        Agents, one of which - the Road Lord - is explicitly bulletproof by
;        design (must be rammed, not shot). Not a bug/hero-state fluke. The one
;        byte anomaly found (hero's own HERO_STATE=$11, unique among all
;        captured snapshots) may instead be a ramming/collision sub-state,
;        caught mid-attempt against the Road Lord - unconfirmed, see
;        claude/Enemy_Invincibility_Notes.md. Which OBJ_TYPE value IS the Road
;        Lord (vs. the other 5 named agents vs. ordinary traffic) is still open.
;     5. NPC boat state = OBJ_TBL63/6B/73 ($4D63/$4D6B/$4D73) all set to $02 for that
;        slot (vs. $00 for ordinary road enemies) - a shared car/boat locomotion flag.
;     6. ROAD_FEATURE $44=$14 (in the repeating segment $12/$13 water loop) is a
;        traced RNG-gated random spawn: SPAWN_CHECK_ENTRY/RANDOM_SPAWN_ROLL
;        (UPDATE_HAZARDS, Stage 6) roll ~2.3% (RNG>=$FA) per pass to
;        blit one of two small tile shapes ($A598/$A5BB) via DRAW_OBJECT_TILES's
;        blit params - confirmed by a randomly-encountered enemy boat (snapshot
;        "water enemyboat"). Full 31-segment row-by-row graph now in
;        claude/Road_Map_Decode.md.
;     7. ROAD_FEATURE $44=$15 is the water-EXIT counterpart to $13's water-entry
;        trigger (confirmed by snapshot "exit water", seg $13, prev $14). Both are
;        checked in IRQ_MAIN's bottom-half handler ($8474-$84C9): on the last row of
;        their row-repeat cycle they re-arm all four SPRMUX_CNT* sprite-multiplex
;        counters for 25 rows starting at a computed row ($04 on entry, $14 on exit)
;        plus a matching 4-cell colour-RAM block - most likely what schedules the
;        extra multiplexed hazard/enemy-boat sprites at the river's boundaries. This
;        resolves the last of the four $11/$13/$14/$15 scripted-trigger codes.
;     8. DOCK / EXIT SCENE (snapshot "exit water, dock building and truck"): segment
;        $13's BRANCH exit (taken after the $15 trigger) lands on segment $14, which
;        also opens on feature $0F - confirming $0F is a general "back on solid road"
;        marker reused at more than one water-exit point, not unique to segment $0B.
;        HERO_STATE=$02 (new value, ANIM=$08) shares its OBJINIT_PARAM_TBL move/draw
;        dispatch entry with states $00/$01/$03 (all move=$9A8E draw=$90AA) - these
;        low hero-state values look like one small state machine sharing generic
;        object code, with actual behaviour driven by direct HERO_STATE checks
;        elsewhere (as in UPDATE_SCENE_SELECT). By contrast HERO_STATE=$11 (the
;        bridge/enemy-unshootable snapshot) dispatches to a DIFFERENT entry
;        (move=$9B02 draw=$95BE) - supporting evidence (not proof) that $11 is a
;        distinct sub-state, relevant to the still-open enemy-unshootable question.
;        See claude/Dock_Exit_Notes.md and claude/Enemy_Invincibility_Notes.md.
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
;   "EQUATES" just means named constants (like #define in C) - "NAME = $XX"
;   gives a number a readable name everywhere below; it doesn't reserve or
;   allocate anything by itself. Grouped here by what part of the machine
;   they refer to; see the "6502 PRIMER" above for what zero page/BCD/etc mean.
; =============================================================================
COLOR_RAM = $D800    ; colour RAM base (a hardware address, used as a base for
                     ;   indexed writes like "COLOR_RAM+n,y" further down)
; --- Zero page ($00-$FF): the program's fast "global variables" and pointers.
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
; --- RAM code/dispatch area ($2800+): a small routine + several "vectors"
; (RAM words holding a target address) that the game overwrites at runtime
; and then jumps through indirectly, e.g. "jmp (VEC_STATE)" - the 6502
; equivalent of a function pointer, used here to switch behaviour (which
; state-handler/move-routine/scroll-routine runs) without a big branch table.
SPEEDCODE = $2802    ; RAM speed routine entry ($2802)
VEC_OBJMOVE = $2893    ; self-mod object-move vector
VEC_OBJMOVE_HI = $2894
VEC_STATE = $2895    ; main state dispatch vector
VEC_STATE_HI = $2896
VEC_SCROLL = $2897    ; road-scroll dispatch vector
VEC_SCROLL_HI = $2898
ROWADDR_LO = $2899    ; screen row-address table lo
ROWADDR_HI = $289A    ; screen row-address table hi
; --- $4Dxx game-state variables: ordinary RAM (not zero page - these are
; addressed the normal, slightly slower way), used for less time-critical
; state: score/lives/timer, the moving-object tables, sprite multiplexing.
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
; --- VIC-II (video chip) hardware registers, memory-mapped at $D000-$D02E.
; Writing these directly controls the screen: sprite positions/colours,
; scroll position, screen/charset memory pointers, border/background colour,
; and the raster-line interrupt used throughout the IRQ code below.
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
; --- SID (sound chip) hardware registers, $D400+: 3 independent voices, each
; with frequency, waveform/gate control, and an ADSR (attack/decay/sustain/
; release) envelope, plus one shared filter/volume register.
SID_V1_FLO = $D400    ; voice1 freq lo
SID_V1_FHI = $D401    ; voice1 freq hi
SID_V1_CTRL = $D404    ; voice1 control
SID_V1_AD = $D405    ; voice1 attack/decay
SID_V1_SR = $D406    ; voice1 sustain/release
SID_V2_CTRL = $D40B    ; voice2 control
SID_V3_CTRL = $D412    ; voice3 control
SID_VOL = $D418    ; master volume/filter
; --- CIA hardware registers, $DC00+/$DD00+: two "Complex Interface Adapter"
; chips handle the keyboard matrix, both joystick ports, and (via CIA2 port A)
; which 16 KB "bank" of RAM the VIC chip reads its screen/sprite data from.
CIA1_PRA = $DC00    ; CIA1 port A (keyboard cols/joy2)
CIA1_PRB = $DC01    ; CIA1 port B (keyboard rows/joy1)
CIA1_DDRA = $DC02    ; CIA1 data-dir A
CIA1_ICR = $DC0D    ; CIA1 interrupt ctrl
CIA2_PRA = $DD00    ; CIA2 port A (VIC bank select)
CIA2_DDRA = $DD02    ; CIA2 data-dir A
CIA2_ICR = $DD0D    ; CIA2 interrupt ctrl
; --- CPU vectors, $FFFA-$FFFF: fixed hardware addresses the 6502 always
; reads on reset/IRQ/NMI to find out where to jump. This program overwrites
; them (they sit in RAM here, not ROM) to point NMI/RESET at $8027 and IRQ at
; $8402, effectively replacing the machine's normal KERNAL startup entirely.
VEC_NMI = $FFFA    ; CPU NMI vector
VEC_NMI_HI = $FFFB
VEC_RESET = $FFFC    ; CPU RESET vector
VEC_RESET_HI = $FFFD
VEC_IRQ = $FFFE    ; CPU IRQ vector
VEC_IRQ_HI = $FFFF

; =============================================================================
; DATA / TABLE ADDRESSES  (ROM tables + RAM screen/charset buffers)
;   These aren't CPU/hardware registers - just named addresses of data
;   structures inside this ROM image (screen buffers, tile-graphics tables,
;   the road/level tables, sound data), given names so the code below reads
;   as "look up ROAD_SEG_TBL" instead of "look up $AC17".
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
; ROAD_SEG_TBL, ROAD_PTR_LO/HI_TBL, ROAD_LEN_TBL, ROAD_COLIDX/BORDER/MC1/
; MC2_TBL, and OBJ_ADDR_LO/HI + OBJ_ROWREP_TBL/OBJ_SEGREP_TBL are all real
; labels now (Stage 7 annotation pass), defined right at their ROM data -
; see the road-tables block below, and claude/Road_Map_Decode.md for the
; full decode. No equates needed for them here any more.
OBJ_ADDR_LO2 = $AD64
OBJ_ADDR_HI2 = $AD7E
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
; RESET / cold + warm entry ($8027). This is where the CPU starts (see the
; autostart header above) - the 6502 equivalent of main().
RESET:
    sei                 ; disable IRQs while we set things up
    cld                 ; make sure we start in normal (not BCD) arithmetic mode
    lda #$7F
    sta CIA2_ICR        ; mask (disable) all CIA2 interrupt sources...
    sta CIA1_ICR        ; ...and all CIA1 interrupt sources
    lda CIA2_ICR        ; reading each ICR acknowledges/clears any pending IRQ
    lda CIA1_ICR        ; (standard C64 startup: guarantees a clean interrupt state)
    ldx #$FF
    txs                 ; reset the stack pointer to the top of the stack page
    jsr INIT_SYSTEM     ; set up VIC/charset/RAM (see below), then fall through

; -----------------------------------------------------------------------
; Top-level game-state loop: title screen -> menu -> play -> (loop). Each of
; these is only ever reached via a `jmp`, never falls through from above, so
; think of them as the three "screens" the game cycles between.
MAIN_RUN_ATTRACT:
    jsr ATTRACT_TITLE   ; show the title screen until a key/coin advances it

MAIN_RUN_MENU:
    jsr ATTRACT_MENU    ; show the menu (player count etc.) until START is hit

MAIN_RUN_PLAY:
    jsr INIT_PLAY_STATE     ; reset score/lives/road/etc. for a fresh game
    jsr MUSIC_START_THEME

; -----------------------------------------------------------------------
; Per-frame master loop: everything the game does once per video frame while
; actually playing. GAME_DISPATCH below then hands off to whatever the
; current GAME_STATE's handler is (attract/play/etc.), and the rest of this
; loop is really the "what happens after that dispatch" bookkeeping: deciding
; whether to return to attract mode, restart the menu, or start a new game.
GAME_LOOP:
    jsr WAIT_FRAME_TIMER    ; block until the IRQ signals a new frame started
    jsr PROCESS_OBJECTS     ; move every car/enemy/hazard object one step
    jsr UPDATE_SCENE_SELECT ; pick road difficulty/section for this frame
    jsr UPDATE_WEAPONS      ; fire/animate the player's current weapon
    jsr DRAW_STATUS_PANEL   ; redraw score/timer/lives/weapon icons
    jsr TALLY_SCORE_EVENTS  ; apply any points queued up this frame
    jsr HANDLE_PAUSE_KEYS   ; check for the pause/mute keys
    jsr GAME_DISPATCH       ; run the current game-state's own handler
    lda GAME_STATE
    bne ATTRACT_LOOP_CHECK  ; GAME_STATE=0 means "not actively playing yet" -
                            ; only then do we look for a coin/start press below
    lda GAME_TIME_HI
    cmp #$08
    bcc GAMEOVER_WAIT_INPUT ; timer already low -> skip straight to the
                            ; "game over, wait for input" handling further down
    lda #$FF
    cmp CIA1_PRB            ; CIA ports read $FF when nothing is pressed
    bne START_OR_SELECT_PRESSED   ; (joystick/keys pull individual bits LOW)
    cmp CIA1_PRA
    bne START_OR_SELECT_PRESSED
    lda START_HELD
    beq ATTRACT_LOOP_CHECK  ; nothing pressed and nothing held -> just loop

; A key/joystick input was seen (or START_HELD was already counting) - track
; how long it's been held, and once a player count is chosen, start playing.
START_OR_SELECT_PRESSED:
    inc START_HELD
    lda NUM_PLAYERS
    beq GOTO_PLAYER_SELECT  ; no player count chosen yet -> go pick one
    lda TWO_PLAYER
    beq GOTO_PLAYER_SELECT  ; (???) same check again on the 2-player flag
    sta GAME_STATE          ; otherwise commit to playing (A = TWO_PLAYER here)

; Reached every frame once GAME_STATE is nonzero (i.e. once actually playing).
; Its job is to notice "game over" and, after a short wait, either restart
; the game (if the player presses something) or fall back to attract mode.
ATTRACT_LOOP_CHECK:
    lda DEMO_TIMER
    bne GOTO_PLAYER_SELECT  ; demo/attract countdown still running
    lda START_HELD
    bne BEGIN_PLAY          ; START is being held down -> (re)start immediately
    lda LIVES
    bpl LOOP_TO_GAME        ; LIVES has its top bit set only at $FF ("game
                            ; over" sentinel, per the header notes) - if it's
                            ; not $FF, there's nothing special to do this frame
    lda ANIM_STATE
    cmp #$15
    bcc LOOP_TO_GAME        ; only continue while ANIM_STATE is in the small
    cmp #$18                ; window $15-$17 - the game-over animation is
    bcs LOOP_TO_GAME        ; presumably playing during that window
    lda FLAG_A1
    beq GAMEOVER_WAIT_INPUT ; (???) some extra one-shot guard flag

LOOP_TO_GAME:
    jmp GAME_LOOP

; Game over animation has finished: clear the score panel, award any final
; points, then give the player a short window (POLL_INPUT_FRAME, looped 6
; times) to press something before falling back to the attract/title screen.
GAMEOVER_WAIT_INPUT:
    jsr CLEAR_PANEL
    ldy #$00
    jsr ADD_SCORE            ; (Y=0: no extra points, just runs the score-tally
                              ;  side effects, e.g. updating the high score)
    inc FX_TIMER0
    jsr DELAY_FRAMES
    lda #$06
    sta ZTMP_08              ; loop counter: wait up to 6 polls for input

GAMEOVER_WAIT_LOOP:
    jsr POLL_INPUT_FRAME
    bne BEGIN_PLAY            ; input seen -> go straight back into play
    dec ZTMP_08
    bne GAMEOVER_WAIT_LOOP
    sta GAME_STATE             ; no input within the wait: A is 0 here (from
                                ; POLL_INPUT_FRAME), so this resets GAME_STATE
    jsr RESET_ROAD_INDEX
    inc SCENE_IDX
    jmp MAIN_RUN_ATTRACT        ; ...and drop back to the attract/title screen

BEGIN_PLAY:
    jsr RESET_ROAD_INDEX
    jmp MAIN_RUN_PLAY            ; start (or restart) a game from the top

GOTO_PLAYER_SELECT:
    lda #$01
    sta GAME_STATE
    jsr RESET_ROAD_INDEX_ALT
    inc SCENE_IDX
    jmp MAIN_RUN_MENU             ; go show the player-count menu

; -----------------------------------------------------------------------
; Enter the current game-state handler via VEC_STATE ($2895). VEC_STATE is
; one of the "RAM vector" function pointers from the equates section - some
; other routine has already written the target address into it, and this
; just jumps through it. So GAME_DISPATCH itself never changes; only where
; it sends control does.
GAME_DISPATCH:
    jmp (VEC_STATE)

; -----------------------------------------------------------------------
; One-time system init, called once from RESET: sets memory banking, clears
; RAM, builds the game's custom character sets from ROM font data, sets up
; the VIC display and the CPU's interrupt vectors, then returns with
; interrupts re-enabled (CLI) so the IRQ-driven game loop can start.
INIT_SYSTEM:
    lda #$80
    tay
    ldx #$40
    jsr COPY_PAGES      ; copy $40 (64) pages - i.e. 16 KB
    lda #$05
    sta CPU_PORT        ; memory config $05: RAM at $A000/$E000, I/O at $D000
                        ;   (see the header's "memory configuration" notes)
    lda #$2F
    sta ZP_00           ; data-direction register: which CPU_PORT bits are outputs
    ldx #$00
    txa
    stx VIC_CR1         ; screen off while we set everything up
    stx VIC_IMR         ; disable all VIC interrupt sources
    stx VIC_SPR_ENA     ; no hardware sprites visible yet
    stx VIC_SPR_BGPRI
    dex                 ; x = $FF
    stx VIC_IRR         ; writing $FF acknowledges/clears any pending VIC IRQs
    dex                 ; x = $FE

; Zero out zero page RAM (addresses CPU_PORT+1 .. CPU_PORT+$FE, i.e. $02-$FF -
; A is still 0 from the "txa" above). $00/$01 are left alone since they're
; the CPU's own port registers, just configured above.
CLEAR_ZEROPAGE_LOOP:
    sta CPU_PORT,x
    dex
    bne CLEAR_ZEROPAGE_LOOP
    jsr DRAW_PLAYFIELD_FRAME
    jsr UNPACK_MAP_DATA
    lda #$00
    ldy #$4D
    ldx #$33
    jsr FILL_PAGES      ; zero-fill $33 pages starting at $4D00 (game-state
                        ;   vars, object tables, sprite/colour buffers)
    lda #$03
    sta CPU_PORT        ; briefly switch to config $03 (character ROM visible)
                        ;   to read the real C64 font as source data below
    lda #$00
    sta SRC_PTR
    lda #$D0
    sta SRC_PTR_HI      ; SRC_PTR = $D000: the character ROM (visible now)
    lda #$01
    sta DST_PTR
    lda #$68
    sta DST_PTR_HI      ; DST_PTR  = $6801
    lda #$09
    sta DST2_PTR
    lda #$68
    sta DST2_PTR_HI     ; DST2_PTR = $6809
    lda #$40
    sta ZTMP_0A         ; outer loop count = $40 (64)

; Build two custom character sets (at DST_PTR/DST2_PTR) out of the stock
; character ROM, 8 bytes (one character) at a time: PACK_2BITS presumably
; repacks each 1-bit-per-pixel ROM glyph row into this game's 2-bit-per-pixel
; multicolour format (exact bit trick not traced - see PACK_2BITS). (???)
BUILD_CHARSET_OUTER:
    lda #$08
    sta ZTMP_0B         ; inner loop count = 8 (one character = 8 rows)

BUILD_CHARSET_INNER:
    ldx #$00
    lda (SRC_PTR,x)     ; note: this is (zp,x)-indexed with x=0, i.e. just a
    jsr PACK_2BITS       ;   plain "load through the pointer" - x is 0 here,
    ldy ZTMP_09          ;   not walking an array
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
    bne BUILD_CHARSET_INNER
    lda #$08
    jsr PTR_DST_ADD     ; advance DST_PTR/DST2_PTR to the next character
    lda #$08
    jsr PTR_AUX_ADD
    dec ZTMP_0A
    bne BUILD_CHARSET_OUTER
    ldy #$4E

; Copy INIT_CHARS_TBL (a small ROM table of extra ready-made characters)
; straight into the tail end of the character set just built.
COPY_INIT_CHARS_LOOP:
    lda INIT_CHARS_TBL,y
    sta (DST_PTR),y
    dey
    bpl COPY_INIT_CHARS_LOOP
    lda #$05
    sta CPU_PORT        ; back to normal config $05 (character ROM hidden again)
    lda #$00
    sta DST_PTR
    lda #$70
    sta DST_PTR_HI      ; DST_PTR = $7000: the second (playfield) character set
    lda #$0C
    sta ZTMP_0C
    jsr BUILD_CHAR_PAIR ; build $0C character-pairs of one kind (???: exact
                        ;   source/shape not traced)
    lda #$1C
    sta ZTMP_0C
    lda #$00
    jsr BUILD_CHAR_PAIR ; then $1C more of another kind
    lda #$3B
    sta ZTMP_0C

; Stream $3B (59) more characters (8 bytes each) straight out of a ROM byte
; stream via STREAM_NEXT_BYTE - i.e. these characters are stored pre-built in
; ROM rather than generated, unlike the ones above.
STREAM_CHARS_OUTER:
    ldy #$00

STREAM_CHARS_INNER:
    jsr STREAM_NEXT_BYTE
    sta (DST_PTR),y
    iny
    cpy #$08
    bne STREAM_CHARS_INNER
    lda #$08
    jsr PTR_DST_ADD
    dec ZTMP_0C
    bne STREAM_CHARS_OUTER
    lda #$0E
    sta ZTMP_0C
    lda #$00
    jsr BUILD_CHAR_PAIR
    ldx #$00

; Build a third, brighter variant of two of the charsets by shifting every
; byte left one bit (ASL): CHARSET_A_10/CHARSET_A_E0 -> CHARSET_B_660/
; CHARSET_B_730. (Multicolour chars use 2 bits/pixel; shifting left changes
; which colour-pair each pixel selects - a cheap way to get an "alternate
; palette" copy of the same shapes without hand-drawing new ones.) (???)
DOUBLE_CHARSET_LOOP:
    lda CHARSET_A_10,x
    asl a
    sta CHARSET_B_660,x
    lda CHARSET_A_E0,x
    asl a
    sta CHARSET_B_730,x
    inx
    cpx #$D0
    bne DOUBLE_CHARSET_LOOP
    lda #$00
    sta SRC_PTR
    lda #$78
    sta SRC_PTR_HI      ; SRC_PTR = $7800: the main scrolling play screen
    ldx #$00

; Build ROWADDR_LO/HI: a lookup table of the screen address of each text row
; ($28 = 40 bytes apart, i.e. one 40-column row), so other code can jump
; straight to "the address of row N" instead of recalculating it each time.
BUILD_ROWADDR_LOOP:
    lda SRC_PTR
    sta ROWADDR_LO,x
    inx
    lda SRC_PTR_HI
    sta ROWADDR_LO,x    ; (note: this stores into the same ROWADDR_LO array,
    inx                 ;  not ROWADDR_HI - the two interleave lo/hi/lo/hi as
                        ;  one table, walked by a single incrementing index)
    lda #$28
    jsr PTR_SRC_ADD
    cpx #$32
    bne BUILD_ROWADDR_LOOP
    jsr UNPACK_CHARSET
    ldx #$00
    stx BLIT_ROWS
    inx
    stx VIC_IRR         ; x=1: acknowledge/enable-mask tidy-up
    stx VIC_IMR
    stx WEAPON_STATE    ; start the player with weapon state 1 (machine guns)
    inx
    stx CIA2_PRA        ; x=2: CIA2 port A bit 1 -> selects VIC bank 1 ($4000+)
    inx
    stx CIA2_DDRA       ; x=3: CIA2 port A data-direction
    stx STATE_4D1D
    stx STATE_4D16
    lda #$18
    sta VIC_CR2         ; multicolour character mode, 40-column display
    lda #$27
    sta VEC_NMI         ; install our own NMI/RESET/IRQ vectors, replacing
    lda #$80            ;   the KERNAL's - from here on this program owns the
    sta VEC_NMI_HI      ;   whole machine (NMI/RESET both -> $8027 = RESET,
    lda #$27            ;   IRQ -> $8402 = IRQ_MAIN)
    sta VEC_RESET
    lda #$80
    sta VEC_RESET_HI
    lda #$02
    sta VEC_IRQ
    lda #$84
    sta VEC_IRQ_HI
    lda #$EA
    sta SPLIT_RASTER    ; first raster-interrupt compare line
    lda #$17
    sta VSCROLL_POS
    lda #$1B
    sta D011_SHADOW     ; screen on, 25 rows, no Y-scroll offset yet
    lda #$9A
    sta D018_SHADOW     ; initial screen/charset pointer (title screen buffer)
    lda #$FC
    sta D018_ALT
    lda #$F1
    sta VIC_RASTER      ; arm the raster compare for line $F1 - the IRQ fires
                        ;   here first (see IRQ_MAIN/IRQ_BOTTOM_SCROLL below)
    jsr RESET_SCROLL_VARS
    cli                 ; interrupts back on - the IRQ-driven game can now run
    rts
; -----------------------------------------------------------------------
; PANEL_LABELS_TBL: 20 screen char-codes drawn to the status panel by ATTRACT_TITLE.
    .byte $32,$02,$2E,$08,$12,$1A,$40,$32,$18,$18,$02,$04,$40,$66,$70,$72
    .byte $62,$52,$06,$50

; -----------------------------------------------------------------------
; Draw the attract/title status line and poll for input once. This runs
; exactly once per pass through the boot-order chain (RESET falls into
; MAIN_RUN_ATTRACT -> here -> MAIN_RUN_MENU -> ATTRACT_MENU -> MAIN_RUN_PLAY,
; all called in a straight line, see the top-level game-state loop above) -
; it does NOT itself sit in a loop waiting for a keypress. The actual
; per-frame "wait on the title screen" behaviour comes from GAME_LOOP calling
; GAME_DISPATCH (through VEC_STATE) every frame once play is running; this
; routine only sets the initial GAME_STATE/SCENE_IDX for that to act on.
ATTRACT_TITLE:
    jsr RESET_SCREEN_STATE
    jsr DELAY_FRAMES_ALT
    ldx #$00
    ldy #$13            ; 20 entries in PANEL_LABELS_TBL, indices 19 downto 0

DRAW_TITLE_LABELS_LOOP:
    lda PANEL_LABELS_TBL,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl DRAW_TITLE_LABELS_LOOP
    lda #$12
    sta SCENE_IDX
    jsr POLL_INPUT_FRAME    ; sample this frame's input once (A = 0 if none)
    beq TITLE_SET_GAME_STATE
    inc SCENE_IDX            ; input seen this frame -> bump the scene index

TITLE_SET_GAME_STATE:
    sta GAME_STATE           ; GAME_STATE = whatever POLL_INPUT_FRAME returned
    rts
; -----------------------------------------------------------------------
; MENU_MSG_TBL / MENU_MSG_TBL_B: char-codes for the player-select / demo screen.
    .byte $28,$24,$0A,$20,$30,$0A,$40,$24,$1E,$40,$0A,$06,$12,$2C,$1E,$1C
    .byte $0A,$24,$1E,$06,$26,$40,$10,$0E,$12,$10

; -----------------------------------------------------------------------
; Player-select / demo screen: like ATTRACT_TITLE, this runs once per pass
; through the boot-order chain, not in an internal wait-loop (see the note
; above ATTRACT_TITLE). Two sequential single-poll prompts: first "how many
; players", then a second "which game/start option" choice. The exact key
; codes compared against ($1D/$1A/$18/$31) are POLL_INPUT_FRAME's raw
; decoded-input values - see SCAN_JOY_KEYS/KEYCODE_TBL in a later section for
; how those are produced; not cross-checked here. (???)
ATTRACT_MENU:
    jsr RESET_SCREEN_STATE
    lda GAME_STATE
    beq MENU_ABORT      ; GAME_STATE=0 (attract mode) -> nothing to do, bail
    jsr DELAY_FRAMES_ALT
    ldx #$14
    ldy #$09            ; 10 entries in MENU_MSG_TBL_B

DRAW_PLAYERS_PROMPT_LOOP:
    lda MENU_MSG_TBL_B,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl DRAW_PLAYERS_PROMPT_LOOP
    jsr DRAW_SCORE

POLL_PLAYERS_CHOICE:
    jsr POLL_INPUT_FRAME
    beq MENU_ABORT       ; no input this frame -> bail
    ldx #$01
    ldy #$11
    cmp #$1D
    beq PLAYERS_CHOSEN   ; input $1D -> 1 player (X stays 1)
    inx                  ; X=2
    ldy #$1D
    cmp #$1A
    bne POLL_PLAYERS_CHOICE  ; not $1A either -> keep polling next frame

PLAYERS_CHOSEN:
    stx NUM_PLAYERS      ; NUM_PLAYERS = 1 or 2
    ldx #$12
    lda #$00

; Clear a block of rows across all 6 play/high-score screen-buffer areas
; (play buffer x3 + high-score buffer x3, see the SCR_PLAY_*/SCR_HISC_*
; equates) to erase the "how many players" prompt before the next one.
CLEAR_MENU_ROWS_LOOP:
    sta SCR_PLAY_0D,y
    sta SCR_PLAY_35,y
    sta SCR_PLAY_5D,y
    sta SCR_HISC_0D,y
    sta SCR_HISC_35,y
    sta SCR_HISC_5D,y
    dey
    dex
    bne CLEAR_MENU_ROWS_LOOP
    jsr CLEAR_PANEL
    ldx #$04
    ldy #$0F            ; 16 entries in MENU_MSG_TBL

DRAW_GAME_PROMPT_LOOP:
    lda MENU_MSG_TBL,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl DRAW_GAME_PROMPT_LOOP

POLL_GAME_CHOICE:
    jsr POLL_INPUT_FRAME
    beq MENU_ABORT
    ldy #$01
    cmp #$18
    beq GAME_CHOICE_MADE  ; input $18 -> choice 1 (Y stays 1)
    cmp #$31
    bne POLL_GAME_CHOICE   ; not $31 either -> keep polling
    iny                     ; input $31 -> choice 2 (Y=2)

GAME_CHOICE_MADE:
    sty GAME_STATE
    sty TWO_PLAYER          ; (???) both set to the same 1/2 choice value
    dey
    beq MENU_DONE_1P        ; choice was 1 -> clear the panel's right half
    jmp CLEAR_PANEL_FULL     ; choice was 2 -> clear its left half instead
                              ;   (CLEAR_PANEL_FULL's second entry point,
                              ;   see the CLEAR_PANEL/CLEAR_PANEL_ALT note
                              ;   near WAIT_FRAME_TIMER)

MENU_DONE_1P:
    jmp CLEAR_PANEL_ALT

MENU_ABORT:
    lda #$00
    sta GAME_STATE
    rts

; -----------------------------------------------------------------------
; Set up a fresh play state: score/lives/road/timer all reset to their
; starting values, called once from MAIN_RUN_PLAY before the per-frame
; GAME_LOOP begins.
INIT_PLAY_STATE:
    jsr CLEAR_RAM_AND_SPRITES
    jsr DELAY_FRAMES_ALT
    ldx GAME_STATE
    beq INIT_PLAY_MUX
    ldx TWO_PLAYER
    cpx #$01
    beq INIT_PLAY_MUX
    ldy #$FF
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
INIT_PLAY_MUX:
    ldy #$05
    sty MUX_SLOT2       ; sprite-multiplex slot base indices: 5, 4, 3
    dey
    sty MUX_SLOT1
    dey
    sty MUX_SLOT0
    ; <<< EDIT HERE for more starting lives (e.g. for exploring/mapping the
    ; game): change the #$7F below to any value from #$00 to #$7F (127).
    ; DO NOT use #$FF (255) or anything >= #$80 - LIVES doubles as a "game
    ; over" sentinel elsewhere (GAME_LOOP and DRAW_STATUS_PANEL both treat
    ; any value with bit 7 set as "out of lives"), so a value that high would
    ; make the game think it's over before it even starts. #$7F is plenty -
    ; the status panel only ever draws up to 6 life icons regardless, and the
    ; extra-life award code (further down) stops adding more once LIVES>=6.
    ; (currently set to #$7F = 127, in place of the original game's #$01)
    lda #$7F
    sta LIVES
    sta EXTRA_LIFE_AVAIL
    dec EXTRA_LIFE_AVAIL   ; ...then immediately drop it to 0 = "timer
                            ;   running/shown" (see the header's timer notes -
                            ;   $FF would mean "expired")
    lda #$99
    sta GAME_TIME_LO    ; game timer = BCD 0999 (the starting countdown value)
    lda #$09
    sta GAME_TIME_HI
    ldx #$FF
    stx STATE_4D17
    stx VIC_SPR_ENA     ; enable all 8 hardware sprites
    inx
    inx                 ; x = $01
    stx PREV_FEATURE
    stx SEQ_STATE
    stx STATE_4D05
    stx STATE_4DCB
    inx                 ; x = $02
    stx NEXT_LIFE_SCORE ; (???) likely an index into a score-threshold table
                        ;   rather than a raw score value
    stx MUX_SLOT_IDX
    lda #$0E
    sta VIC_SPRMC0      ; shared sprite colour 1: light blue
    lda #$01
    sta VIC_SPRMC1      ; shared sprite colour 2: white

; Pick which game-state handler VEC_STATE should dispatch to (via
; GAME_DISPATCH, every frame) for the game that's about to start - one of
; three addresses depending on GAME_STATE/NUM_PLAYERS. $A189/$A152 aren't
; covered by this annotation pass; $A9F6 is STATE_2P_ENTRY (Stage 8, near
; SCAN_JOY_KEYS) - a 2-player-specific input-decode entry point. (???: the
; other two handlers' roles)
    lda #$89
    ldy #$A1
    ldx GAME_STATE
    beq SET_STATE_VEC        ; GAME_STATE=0 (attract) -> $A189
    ldx NUM_PLAYERS
    dex
    beq ONE_PLAYER_VEC       ; NUM_PLAYERS=1 -> $A152
    lda #$F6
    ldy #$A9
    bne SET_STATE_VEC         ; NUM_PLAYERS=2 -> $A9F6 (STATE_2P_ENTRY)

ONE_PLAYER_VEC:
    lda #$52
    ldy #$A1

SET_STATE_VEC:
    sta VEC_STATE
    sty VEC_STATE_HI

; -----------------------------------------------------------------------
; Clear per-scene state then fall into CLEAR_RAM_AND_SPRITES.
RESET_SCREEN_STATE:
    jsr CLEAR_PANEL

; -----------------------------------------------------------------------
; Fill colour RAM, init SID, zero ZP $DC-$FF (score/flags/effect-timer zero
; page variables - see the equates section), clear all 8 object slots, and
; push their sprites off-screen.
CLEAR_RAM_AND_SPRITES:
    jsr CLEAR_COLOR_RAM
    jsr SID_INIT
    ldx #$DC
    ldy #$00
    tya

ZERO_ZP_TAIL_LOOP:
    sta ZP_00,x
    inx
    bne ZERO_ZP_TAIL_LOOP    ; x wraps $FF->$00 and bne stops - covers $DC-$FF
    lda #$FE
    sta BIT_MASK_INV

; Loop exactly 8 times, once per object slot: BIT_MASK_INV starts as
; %11111110. Each pass, "sec" forces a 1 into the bottom bit and "rol" shifts
; everything left one place, moving the top bit out into the carry flag;
; "bcs" (branch if carry set) loops again as long as that bit was a 1. Since
; only ONE bit of the starting value was 0, this walks that single 0 bit
; through all 8 positions and stops right after it shifts out - a common
; 6502 idiom for "repeat exactly N times" when you don't want to spend a
; separate counter byte.
INIT_ALL_OBJECT_SLOTS_LOOP:
    jsr INIT_OBJECT_SLOT
    lda #$95
    sta SPRPTR_6400,x   ; point this slot's sprite at the blank/empty shape
    inx
    iny
    iny
    sec
    rol BIT_MASK_INV
    bcs INIT_ALL_OBJECT_SLOTS_LOOP
    jmp COPY_SPRITE_REGS ; tail-jump into the sprite-register push routine
                        ;   (see the note above COPY_SPRITE_REGS, Stage 6) -
                        ;   that routine's own RTS returns to our caller

; -----------------------------------------------------------------------
; Raster IRQ, top of frame ($83C3, vectored from IRQ_MAIN below). This is the
; SECOND half of the "chained raster interrupt" described in the header: the
; game alternates between two IRQ handlers across a frame, re-pointing
; VEC_IRQ/VIC_RASTER to each other so raster line X triggers IRQ_TOP_PANEL,
; which then arms the NEXT compare (around line $F1, IRQ_MAIN territory) and
; points the vector back - the pair keep re-triggering each other all the
; way down the screen. This half repaints the border/background colours to
; the status-PANEL palette (as opposed to the play-area "split" palette) and
; hands back off to IRQ_MAIN's raster range.
;
; An interrupt can fire in the middle of ANY instruction, so the very first
; thing any IRQ handler must do is save every register it's about to use
; (here: A and X, via PHA/PHA - note Y isn't touched, so it doesn't need
; saving) and the very last thing is restore them in reverse order before
; RTI (ReTurn from Interrupt - like RTS, but also restores the flags the
; interrupted code had, from the extra byte the CPU auto-pushed on entry).
IRQ_TOP_PANEL:
    pha                 ; save A
    txa
    pha                 ; save X (via A, since there's no direct "push X")
    ldx #$04

; A tiny busy-wait: do nothing $04 times. Real raster IRQs need pixel-exact
; timing, and the number of CPU cycles taken to get here varies slightly
; frame to frame - a short fixed delay like this "eats" that jitter so
; everything after it lands on a consistent cycle, keeping the screen split
; stable instead of wobbling by a pixel.
IRQ_TOP_STABILISE_DELAY:
    dex
    bne IRQ_TOP_STABILISE_DELAY
    lda BORDER_COL_TOP
    sta VIC_BORDER
    sta VIC_BG0
    lda MC_COL1_TOP
    sta VIC_BG1
    lda MC_COL2_TOP
    sta VIC_BG2
    ldx #$F1            ; default: next raster split at line $F1...
    lda VIC_CR1
    and #$07            ; ...but VIC_CR1's low 3 bits are the fine Y-scroll,
    cmp #$02             ;   which shifts the whole picture down by a pixel -
    beq IRQ_TOP_SET_RASTER  ; so when it's not the expected value, bump the
    inx                      ;   target line by one to compensate (X = $F2)

IRQ_TOP_SET_RASTER:
    stx VIC_RASTER      ; arm the next raster-compare line
    lda #$02
    sta VEC_IRQ         ; re-point the IRQ vector to $8402 = IRQ_MAIN...
    lda #$84
    sta VEC_IRQ_HI      ; ...so THAT handler runs when this new line is hit
    lda #$01
    sta VIC_IRR         ; acknowledge this raster interrupt
    pla
    tax                 ; restore X
    pla                 ; restore A
    rti                 ; back to whatever the CPU was doing, flags restored

; -----------------------------------------------------------------------
; Jump through VEC_SCROLL ($2897) into the current road-scroll chunk - the
; same "RAM vector"/function-pointer trick as GAME_DISPATCH/VEC_STATE above,
; here used to switch which scrolling routine runs depending on game state.
SCROLL_DISPATCH:
    jmp (VEC_SCROLL)

; -----------------------------------------------------------------------
; Main raster IRQ ($8402) - the OTHER half of the chained top/bottom raster
; pair described above IRQ_TOP_PANEL. IRQ_HALF flips between the two halves
; each time this fires: IRQ_HALF=0 means "we're at the bottom split" (the
; scrolling road/game-logic half, IRQ_BOTTOM_SCROLL below); IRQ_HALF!=0 means
; "we're partway back up, arm the top/panel split" (this routine, inline).
IRQ_MAIN:
    cld                 ; belt-and-braces: make sure decimal mode is off
    pha
    txa
    pha
    tya
    pha                 ; save A, X, Y - see the note above IRQ_TOP_PANEL
    ldx #$03

IRQ_MAIN_STABILISE_DELAY:
    dex
    bne IRQ_MAIN_STABILISE_DELAY  ; same cycle-jitter trick as IRQ_TOP_PANEL
    lda D011_SHADOW
    sta VIC_CR1         ; apply this frame's screen-control settings...
    lda D018_SHADOW
    sta VIC_MEMPTR      ; ...and screen/charset pointer (which buffer's shown)
    ldy IRQ_HALF
    bne ARM_SPLIT_TO_PANEL
    jmp IRQ_BOTTOM_SCROLL   ; IRQ_HALF=0 -> do the bottom-half road/game work

; Arm the switch BACK to the top/panel half: set the panel's border/
; background colours, then figure out where the split line should be.
ARM_SPLIT_TO_PANEL:
    lda BORDER_COL_SPLIT
    sta VIC_BORDER
    sta VIC_BG0
    lda MC_COL1_SPLIT
    sta VIC_BG1
    lda MC_COL2_SPLIT
    sta VIC_BG2
    lda SPLIT_RASTER
    cmp #$EE
    bcc ARM_RASTER_SPLIT    ; normally just reuse SPLIT_RASTER as-is...
    lda BORDER_COL_SPLIT     ; ...but if it's drifted near the bottom of the
    sta BORDER_COL_TOP        ; screen ($EE+), that's this frame's LAST split -
    lda MC_COL1_SPLIT          ; copy the play-area colours to the "top"
    sta MC_COL1_TOP              ; variables too (so the panel redraw next
    lda MC_COL2_SPLIT             ; frame starts from the right colours) and
    sta MC_COL2_TOP                ; reset the split line back to near the top
    lda #$2F                        ; ($2F) for the next frame's first split.

ARM_RASTER_SPLIT:
    sta VIC_RASTER
    sta SPLIT_RASTER
    lda #$C3
    sta VEC_IRQ         ; re-point the IRQ vector to $83C3 = IRQ_TOP_PANEL...
    lda #$83
    sta VEC_IRQ_HI      ; ...so THAT handler runs at the next split
    lda #$01
    sta VIC_IRR         ; acknowledge this raster interrupt
    cli                 ; interrupts back on early - the rest of this handler
                        ;   can safely be pre-empted by the next raster split
    lda #$1B
    sta D011_SHADOW     ; screen back on/25 rows for the next frame's redraw
    lda #$9A
    sta D018_SHADOW     ; back to the title/panel screen+charset pointer
    lda COPY_BLOCK_FLAG
    beq IRQ_MAIN_DONE
    ldy #$1F            ; COPY_BLOCK_FLAG set -> one 32-byte block to copy

; Copy 32 bytes from SCROLL_SRC to SCROLL_DST - a small, fast, once-per-IRQ
; chunk of the road-scrolling copy (the full row copy happens across several
; IRQs, not all at once, to keep each individual IRQ short).
BLOCK_COPY_LOOP:
    lda (SCROLL_SRC),y
    sta (SCROLL_DST),y
    dey
    bpl BLOCK_COPY_LOOP
    iny
    sty COPY_BLOCK_FLAG
    ldy #$1F

; Sprite multiplexing: the VIC chip only has 8 hardware sprites, but this
; game shows far more moving objects than that by repositioning sprites
; partway down the screen (once one enemy has scrolled past, its sprite can
; be re-used lower down for another). SPRMUX_CNT (and its 3 sister arrays,
; SPRMUX_CNT1-3) hold a per-row-band countdown; this loop walks all 32 bands
; (y = $1F downto 0) and, for any band still counting down, calls SPEEDCODE
; (the fast RAM routine that actually repositions the sprite for this band)
; and paints a status-colour cell, then ticks the countdown down by one.
SPRITE_MUX_ROW_LOOP:
    lda a:SPRMUX_CNT,y
    beq SPRITE_MUX_ROW_NEXT
    jsr SPEEDCODE
    lda #$0E
    sta COLOR_RAM+HISCORE_HI,y
    tya
    tax
    dec SPRMUX_CNT,x

SPRITE_MUX_ROW_NEXT:
    dey
    bpl SPRITE_MUX_ROW_LOOP
    lda ROW_REPEAT
    ldy #$14
    cmp #$01
    bne CONSUME_ARMED_ROW   ; only act below on the LAST row of a row-repeat
    lda ROAD_FEATURE         ;   cycle (see claude/Boat_River_Notes.md for the
    cmp #$15                  ;   full write-up of what this does)
    beq STORE_ARMED_ROW        ; feature $15 (water-exit trigger): Y stays $14
    cmp #$13
    bne IRQ_MAIN_TAIL
    ldy #$04                    ; feature $13 (water-entry trigger): Y = $04
    bne STORE_ARMED_ROW

; Neither trigger fired this pass - instead, pick up whatever row band was
; armed by a PREVIOUS pass (STATE_4D18) and finish arming it now, one frame
; later, then clear the "pending" flag so this only fires once.
CONSUME_ARMED_ROW:
    ldy STATE_4D18
    beq IRQ_MAIN_TAIL
    lda #$00
    sta STATE_4D18
    beq PAINT_AND_ARM_MUX

STORE_ARMED_ROW:
    sty STATE_4D18      ; remember which row band to finish arming next pass

; Paint a 4-cell colour-RAM block and re-arm all four SPRMUX_CNT* arrays for
; 25 ($19) rows starting at row Y - see claude/Boat_River_Notes.md: this is
; what schedules the extra multiplexed sprites right at the river's entry
; and exit points (e.g. the random enemy-boat spawn).
PAINT_AND_ARM_MUX:
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

IRQ_MAIN_TAIL:
    jsr SCROLL_DISPATCH ; run this frame's road-scroll routine (via VEC_SCROLL)
    jsr UPDATE_HAZARDS
    inc FRAME_SUBCTR

IRQ_MAIN_DONE:
    jmp IRQ_EXIT

; -----------------------------------------------------------------------
; Bottom-of-frame path of the IRQ: advance the road's vertical scroll one
; step, and - once it's scrolled a full character row - step the road-segment
; engine on to the next row (or the next SEGMENT, when the current one runs
; out). This is the routine documented in depth in claude/Road_Map_Decode.md:
; a level is a linked graph of "segments" (ROAD_SEG_TBL), each a short list
; of per-row "feature" codes (ROAD_FEATURE) that select that row's graphics.
; The per-segment template row (SCROLL_SRC, set below at READ_ROAD_ROW) covers
; the WHOLE row including its margins - grass on land, water tiles ($06-$13)
; on the bridge/water segments - so water is just ordinary map data, not a
; special layer (see claude/Water_Bridge_Notes.md / Boat_River_Notes.md).
IRQ_BOTTOM_SCROLL:
    lda #$00
    sta VIC_BORDER      ; play-area colours while the road/game logic runs
    sta VIC_BG0
    lda #$01
    sta VIC_BG1
    lda #$08
    sta VIC_BG2
    inc FRAME_FLAG      ; signal "a new frame happened" - GAME_LOOP's
                        ;   WAIT_FRAME_TIMER polls this to pace the game loop
    lda SPLIT_RASTER
    clc
    adc SCROLL_SPEED    ; the screen split drifts down with the scroll speed
    sta SPLIT_RASTER    ;   too, so the panel/play boundary tracks smoothly
    lda D018_ALT
    sta D018_SHADOW
    lda FLAG_FB
    beq ADVANCE_VSCROLL
    lda SPAWN_Y         ; (???) if FLAG_FB is set, some spawn point also
    clc                  ;   drifts down at the same rate as the road
    adc SCROLL_SPEED
    sta SPAWN_Y

; Add SCROLL_SPEED to the fine (pixel-level, 0-7) scroll offset. If that
; pushes it past 7 (a whole character cell), the carry comes out set - that's
; the signal to step the road forward a full row below; otherwise this frame
; only needed the smooth pixel-scroll, so skip straight to the tail.
ADVANCE_VSCROLL:
    lda VSCROLL_POS
    and #$07
    clc
    adc SCROLL_SPEED
    cmp #$08
    php                 ; stash the carry (crossed a row?) - AND/ORA below
                        ;   would otherwise clobber the flag before it's used
    and #$07            ; keep only the fine-scroll bits (wrap 0-7)
    ora #$10            ; combine with the fixed screen-control bits
    sta VSCROLL_POS
    sta D011_SHADOW
    plp                 ; get the "crossed a row" carry back
    bcs ADVANCE_ROW
    jmp IRQ_BOTTOM_TAIL  ; pixel-scroll only this frame - nothing else to do

; A full row has scrolled past: count down ROW_REPEAT (how many more times
; this same template row repeats) and, if it's not done yet, just advance
; the read pointer to the next 32-byte row within the same template.
ADVANCE_ROW:
    dec ROW_REPEAT
    beq ROW_REPEAT_DONE
    lda SCROLL_SRC
    clc
    adc #$20            ; +32 bytes = next row of this feature's template
    sta SCROLL_SRC
    bcc FINISH_ROW_STEP
    inc SCROLL_SRC_HI

FINISH_ROW_STEP:
    jmp FINISH_ROW_AND_TOGGLE_BUFFER

; This row-repeat cycle is used up: count down SEG_REPEAT (how many more
; times to repeat the WHOLE row-repeat cycle). If more remain, reset
; ROW_REPEAT and rewind SCROLL_SRC back to the saved start of this template -
; i.e. loop the same short template again (this is how a long straight
; stretch of road is built from one small graphic, repeated many times).
ROW_REPEAT_DONE:
    dec SEG_REPEAT
    beq ADVANCE_ROAD_SEGMENT
    lda SEG_REPEAT_INIT
    sta ROW_REPEAT
    lda SCROLL_SRC_SAVE
    sta SCROLL_SRC
    lda SCROLL_SRC_SAVE_HI
    sta SCROLL_SRC_HI
    beq ADVANCE_ROAD_SEGMENT
    jmp FINISH_ROW_AND_TOGGLE_BUFFER

; Both repeat counts are exhausted: move on to the next ROW within the
; current road segment (ROAD_SEG_LEN), or - once the whole segment's rows
; are used up - walk the segment graph to pick the NEXT segment. This is the
; fork mechanism from claude/Road_Map_Decode.md: ROAD_SEG_TBL stores TWO
; next-segment ids per entry (main/branch); SCENE_IDX >= $13 selects the
; branch (steering right), otherwise the main path (steering left).
ADVANCE_ROAD_SEGMENT:
    lda #$17
    sta STATE_4D10
    dec ROAD_SEG_LEN
    bne READ_ROAD_ROW   ; more rows left in this segment -> just read the next one
    lda ROAD_SEG_IDX
    asl a               ; x2: each segment has a (main, branch) PAIR of entries
    tay
    lda SCENE_IDX
    cmp #$13
    bcc LOAD_NEXT_SEGMENT   ; SCENE_IDX < $13 -> keep the even (main) entry
    iny                      ; SCENE_IDX >= $13 -> odd (branch) entry instead

; Load the chosen next segment's row-pointer and length, then a few one-off
; side effects keyed to specific segment ids reached (lap/loop bookkeeping,
; and what look like scripted road-sign timers - see the header's ROAD MAP
; notes and claude/Road_Map_Decode.md for the fully-traced feature codes).
LOAD_NEXT_SEGMENT:
    lda ROAD_SEG_TBL,y
    sta ROAD_SEG_IDX
    tay
    lda ROAD_PTR_LO_TBL,y
    sta ROAD_PTR
    lda ROAD_PTR_HI_TBL,y
    sta ROAD_PTR_HI
    lda ROAD_LEN_TBL,y
    sta ROAD_SEG_LEN
    cpy #$1C            ; segment $1C is where the main path loops back to
    bne APPLY_ROAD_PHASE    ; the start (per the decoded segment graph) -
    inc ROAD_PHASE           ; treat reaching it as "completed a lap"
    ldx MUX_SLOT_IDX
    bmi APPLY_ROAD_PHASE
    sec
    ror MUX_SLOT0,x     ; (???) some per-lap sprite-multiplex bookkeeping
    dec MUX_SLOT_IDX
    inc FLAG_DD

APPLY_ROAD_PHASE:
    lda ROAD_PHASE
    and #$03            ; wrap to a 0-3 "phase" counter
    sta ROAD_PHASE
    cpy #$0F            ; segment $0F = the river-entrance segment
    bne CHECK_SIGN_TIMER_SEG
    inc FX_TIMER1        ; (???) likely arms a scripted road-sign/effect

; (???) Segment $1B, only when ROAD_PHASE==1: pick FX_TIMER2 or FX_TIMER3
; depending on which fork (SCENE_IDX) got here - candidate for arming one of
; the road-sign messages in ONROAD_MSG_TBL (DETOUR/BRIDGE OUT/ICY ROADS
; etc., see the header's ON-ROAD TEXT notes), not confirmed.
CHECK_SIGN_TIMER_SEG:
    cpy #$1B
    bne APPLY_SEGMENT_PALETTE
    cmp #$01            ; (A still holds ROAD_PHASE&3 from above)
    bne APPLY_SEGMENT_PALETTE
    ldx SCENE_IDX
    cpx #$13
    bcs SIGN_TIMER_B
    inc FX_TIMER2
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
SIGN_TIMER_B:
    inc FX_TIMER3

; Combine ROAD_PHASE with this segment's ROAD_COLIDX_TBL entry to pick the
; row's palette variant, then apply the split-screen border/multicolours -
; this is what gives different stretches of road (and the bridge/water
; sections) their distinct look (see claude/Water_Bridge_Notes.md).
APPLY_SEGMENT_PALETTE:
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
    lsr a               ; half the scroll speed...
    clc
    adc #$2F            ; ...offset from the panel/play split baseline
    sta SPLIT_RASTER

; Read this row's feature code and look up its graphics: the exact mechanism
; fully documented in claude/Road_Map_Decode.md and claude/Boat_River_Notes.md
; - the row list is walked BACKWARDS (dey first), each ROAD_FEATURE byte
; indexes the 16-entry OBJ_ADDR_LO/HI/OBJ_ROWREP_TBL/OBJ_SEGREP_TBL tables
; (codes $00-$0F; $10+ are special scripted trigger codes handled elsewhere,
; e.g. UPDATE_SCENE_SELECT) to pick this row's SCROLL_SRC template pointer
; and repeat counts.
READ_ROAD_ROW:
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

; Arm the 32-byte-per-IRQ block copy (consumed back in IRQ_MAIN's
; BLOCK_COPY_LOOP) and flip between the two screen buffers/scroll routines
; every other IRQ - a form of double buffering so the row currently being
; copied in isn't the same one currently on screen.
FINISH_ROW_AND_TOGGLE_BUFFER:
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

IRQ_BOTTOM_TAIL:
    lda #$06
    sta VIC_RASTER      ; arm the very next raster line - keeps this IRQ
                        ;   pair firing tightly near the top of the frame
    lda #$01
    sta VIC_IRR
    jsr MUSIC_DRIVER    ; advance the music/sound-effect player one tick

; -----------------------------------------------------------------------
; Flip the IRQ_HALF top/bottom toggle (EOR #$FF just inverts every bit - a
; common way to toggle a flag between $00 and $FF) so next time IRQ_MAIN
; fires, it takes the OTHER path (top-panel-arm vs. bottom-scroll) - this is
; what keeps the pair of raster IRQs alternating all the way down the
; screen. Then restore Y/X/A (reverse order from how they were pushed - the
; stack is LIFO) and RTI back to normal execution.
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
; Draw the playfield border/frame by GENERATING a small machine-code routine
; into RAM at $0400 and presumably running it elsewhere (not yet traced where
; it's called from). This is a neat, slightly advanced 6502 trick worth
; calling out: $AD is the opcode byte for "LDA absolute" and $8D is "STA
; absolute" (each a 3-byte instruction: opcode + 2-byte address) - so each
; 6-byte record DRAW_BOX_ROWS writes below is literally the bytes for
; "LDA $srcaddr" followed by "STA $dstaddr", i.e. one COMPILED copy
; instruction pair per character cell, and the whole generated routine is
; terminated with a plain RTS ($60). Writing out the actual instructions like
; this - instead of a generic loop that reads addresses from a table - trades
; RAM for speed, since the CPU doesn't have to compute each address at
; runtime. (ZTMP_0C/ZTMP_0D hold $AD/$8D - the two opcode bytes - across all
; three calls below.)
DRAW_PLAYFIELD_FRAME:
    lda #$20
    sta ZTMP_09         ; cells per row (inner loop count)
    lda #$08
    sta ZTMP_0A         ; per-row address stride
    lda #$18
    sta ZTMP_0B         ; row count (outer loop count)
    lda #$AD
    sta ZTMP_0C         ; opcode byte: LDA absolute
    lda #$8D
    sta ZTMP_0D         ; opcode byte: STA absolute
    lda #$BB
    sta SRC_PTR
    lda #$7B
    sta SRC_PTR_HI      ; SRC_PTR = $7BBB (source screen cells)
    lda #$E3
    sta DST_PTR
    lda #$7F
    sta DST_PTR_HI      ; DST_PTR = $7FE3 (destination screen cells)
    lda #$00
    sta DST2_PTR
    lda #$04
    sta DST2_PTR_HI     ; DST2_PTR = $0400: where the generated code goes
                        ;   (borrowed scratch RAM - this game's own screen
                        ;   buffers live at $6400/$7800/$7C00, not $0400)
    jsr DRAW_BOX_ROWS   ; generate the first box's copy instructions...
    lda #$BB
    sta SRC_PTR
    lda #$7F
    sta SRC_PTR_HI      ; ...then swap source/dest ($7FBB <-> $7BE3)...
    lda #$E3
    sta DST_PTR
    lda #$7B
    sta DST_PTR_HI
    jsr DRAW_BOX_ROWS   ; ...to generate a mirrored second box, appended
                        ;   right after the first (DST2_PTR carries over)
    lda #$01
    sta ZTMP_09         ; third box: just 1 cell per row...
    lda #$27
    sta ZTMP_0A
    lda #$B9
    sta ZTMP_0C         ; ...and different opcode/marker bytes ($B9/$99 -
    lda #$99            ;   still valid 6502 opcodes: LDA abs,Y / STA abs,Y -
    sta ZTMP_0D          ;   so this third box copies via a different
    lda #$9C              ;   addressing mode)
    sta SRC_PTR
    lda #$DB
    sta SRC_PTR_HI      ; SRC_PTR = $DB9C, DST_PTR = $DBC4 (colour RAM area)
    lda #$C4
    sta DST_PTR
    lda #$DB
    sta DST_PTR_HI
    ; falls straight into DRAW_BOX_ROWS - no jsr/rts between them, so this
    ; third box reuses ZTMP_0B (row count) still set from the very first call

; -----------------------------------------------------------------------
; Helper for DRAW_PLAYFIELD_FRAME: emit ZTMP_0B rows x ZTMP_09 columns of
; compiled "LDA src / STA dst" instruction pairs into (DST2_PTR), stepping
; SRC_PTR/DST_PTR back by 1 each column and by ZTMP_0A each row (so the
; generated routine, once run, will copy a rectangular block of border
; characters from one screen area to another).
DRAW_BOX_ROWS:
    lda ZTMP_0B
    sta ZTMP_08         ; row counter = ZTMP_0B (outer loop)

DRAW_BOX_ROW_LOOP:
    ldx ZTMP_09         ; column counter = ZTMP_09 (inner loop)

DRAW_BOX_CELL_LOOP:
    ldy #$00
    lda ZTMP_0C
    sta (DST2_PTR),y    ; emit the LDA-opcode byte
    iny
    lda SRC_PTR
    sta (DST2_PTR),y    ; emit its address operand, low byte...
    iny
    lda SRC_PTR_HI
    sta (DST2_PTR),y    ; ...and high byte
    iny
    lda ZTMP_0D
    sta (DST2_PTR),y    ; emit the STA-opcode byte
    iny
    lda DST_PTR
    sta (DST2_PTR),y    ; emit its address operand, low byte...
    iny
    lda DST_PTR_HI
    sta (DST2_PTR),y    ; ...and high byte (6 bytes written this pass)
    lda #$06
    jsr PTR_AUX_ADD     ; advance DST2_PTR past the instruction pair just written
    sec
    lda DST_PTR
    sbc #$01
    sta DST_PTR         ; step DST_PTR back one cell...
    bcs DST_BORROW_DONE
    dec DST_PTR_HI      ; ...borrowing into the high byte if needed

DST_BORROW_DONE:
    sec
    lda SRC_PTR
    sbc #$01
    sta SRC_PTR         ; ...and SRC_PTR back one cell too
    bcs SRC_BORROW_DONE
    dec SRC_PTR_HI

SRC_BORROW_DONE:
    dex
    bne DRAW_BOX_CELL_LOOP
    sec
    lda DST_PTR
    sbc ZTMP_0A
    sta DST_PTR         ; end of a row: jump DST_PTR to the next row start...
    bcs DST_ROW_BORROW_DONE
    dec DST_PTR_HI

DST_ROW_BORROW_DONE:
    sec
    lda SRC_PTR
    sbc ZTMP_0A
    sta SRC_PTR         ; ...and SRC_PTR likewise
    bcs SRC_ROW_BORROW_DONE
    dec SRC_PTR_HI

SRC_ROW_BORROW_DONE:
    dec ZTMP_08
    bne DRAW_BOX_ROW_LOOP
    ldy #$00
    lda #$60
    sta (DST2_PTR),y    ; append RTS ($60) - terminates the generated routine
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
; Decompress a custom multicolour character set from a compressed byte-
; stream (read via STREAM_NEXT_BYTE) into RAM at $5400+. This is a small
; bytecode interpreter: it repeatedly reads one CONTROL byte and, depending
; on whether it's negative/zero/positive, switches between several different
; unpacking "modes" below (mirrored-pair writes, run-length block copies,
; sparse byte patches, and a set of clever bit-shuffling tricks to build
; extra characters cheaply). The exact meaning of some of the more intricate
; bit-shift sequences isn't fully re-derived here - see the "(???)" notes -
; but the overall mode structure and data flow is.
UNPACK_CHARSET:
    lda #$00
    sta DST_PTR
    lda #$54
    sta DST_PTR_HI      ; DST_PTR = $5400: base of the unpacked character set

; Top of the per-character-block loop: read one control byte and dispatch.
UNPACK_BLOCK_LOOP:
    lda DST_PTR
    sta SRC_PTR
    sta DST2_PTR
    lda DST_PTR_HI
    sta SRC_PTR_HI
    sta DST2_PTR_HI     ; SRC_PTR/DST2_PTR both start pointing at DST_PTR
    lda #$00
    sta ZTMP_09
    jsr STREAM_NEXT_BYTE
    bmi MODE_MIRROR_PAIRS   ; control byte negative -> mode A
    bne MODE_RUN_BLOCKS      ; positive, nonzero -> mode B
    jmp ROTATE_CHARSET_ENTRY  ; zero -> the nibble-rotate mode further down

; Mode A: read 21 bytes from the stream, writing each one PLUS its bit-
; mirrored twin (via MIRROR_BYTE - reverses the bit pairs, since multicolour
; pixels are 2 bits each) into every third byte-pair of this character block
; (offsets 0/1, 3/4, 6/7, ... up to $3E). (???: exact reason for the 1-byte
; gap between each written pair not confirmed - possibly interleaving with
; data written by a different pass.)
MODE_MIRROR_PAIRS:
    ldy #$00

MIRROR_PAIR_LOOP:
    jsr STREAM_NEXT_BYTE
    sta (SRC_PTR),y
    iny
    jsr MIRROR_BYTE
    sta (SRC_PTR),y
    iny
    iny
    cpy #$3F
    bne MIRROR_PAIR_LOOP
    beq MODE_MIRROR_MORE     ; (unconditional - cpy just left Z set)

; Mode B: the control byte is a repeat count (ZTMP_30); for each repeat,
; read BLIT_COUNT (a fresh row count each pass) more bytes from the stream,
; writing one every 3rd byte, then advance SRC_PTR to the next character.
MODE_RUN_BLOCKS:
    sta ZTMP_30
    jsr STREAM_NEXT_BYTE
    sta BLIT_COUNT

RUN_BLOCK_OUTER:
    lda BLIT_COUNT
    sta BLIT_ROWS
    ldy #$00

RUN_BLOCK_INNER:
    jsr STREAM_NEXT_BYTE
    sta (SRC_PTR),y
    iny
    iny
    iny
    dec BLIT_ROWS
    bne RUN_BLOCK_INNER
    jsr PTR_SRC_INC
    dec ZTMP_30
    bne RUN_BLOCK_OUTER

; Common continuation after modes A and B: read the NEXT control byte to
; decide what happens to this finished character block - move on to the next
; one (mode 0), duplicate it into other character-set quadrants (negative),
; or patch in a few extra bytes by hand (positive).
MODE_MIRROR_MORE:
    jsr STREAM_NEXT_BYTE
    bmi DUPLICATE_QUADRANTS
    bne SPARSE_PATCH_SETUP
    lda #$40
    jsr PTR_DST_ADD     ; advance to the next character slot ($40 bytes on)
    jmp UNPACK_BLOCK_LOOP

; Duplicate this character's first byte into the other three "quadrants"
; of a related character-set region (offsets DST_PTR, DST_PTR+$40,
; DST_PTR+$80, and - depending on X - DST_PTR+$C0). (???: which caller sets
; X, and exactly what these four quadrants represent, not traced here.)
SPARSE_PATCH_SETUP:
    lda #$40
    sta ZTMP_08

DUPLICATE_QUADRANT_LOOP:
    ldy #$00
    lda (DST_PTR),y
    ldy #$40
    sta (DST_PTR),y
    cpx #$02
    beq DUP_QUADRANT_80
    bcc DUP_QUADRANT_NEXT
    ldy #$C0
    sta (DST_PTR),y

DUP_QUADRANT_80:
    ldy #$80
    sta (DST_PTR),y

DUP_QUADRANT_NEXT:
    jsr PTR_DST_INC
    dec ZTMP_08
    bne DUPLICATE_QUADRANT_LOOP
    stx ZTMP_09

; Sparse patch mode: repeatedly read an (offset, value) pair from the
; stream and poke VALUE directly at DST_PTR+offset, until a 0 offset byte
; ends the list - a compact way to fix up a handful of individual bytes
; without re-sending a whole character.
SPARSE_PATCH_LOOP:
    jsr STREAM_NEXT_BYTE
    beq SPARSE_PATCH_DONE
    tay
    jsr STREAM_NEXT_BYTE
    sta (DST_PTR),y
    jmp SPARSE_PATCH_LOOP

SPARSE_PATCH_DONE:
    jsr STREAM_NEXT_BYTE
    bne MODE_MIRROR_MORE2
    ldx ZTMP_09

; Skip forward ZTMP_09 more character slots without unpacking anything into
; them (presumably already filled by an earlier DUPLICATE_QUADRANT_LOOP
; pass) - both the "source" (ZTMP_09-via-PTR_AUX_ADD) and destination
; pointers step forward together.
SKIP_CHARS_LOOP:
    lda #$40
    jsr PTR_AUX_ADD
    dex
    beq MODE_MIRROR_MORE     ; done skipping -> back to the main dispatch
    bmi MODE_MIRROR_MORE
    lda #$40
    jsr PTR_DST_ADD
    jmp SKIP_CHARS_LOOP

MODE_MIRROR_MORE2:
    tay

; Like MODE_MIRROR_PAIRS above, but writing into DST2_PTR (this block's own
; start) rather than SRC_PTR, and running until a zero stream byte ends it
; instead of a fixed count.
MIRROR_PAIRS_UNTIL_ZERO:
    jsr STREAM_NEXT_BYTE
    beq SPARSE_PATCH_DONE
    sta (DST2_PTR),y
    iny
    jsr MIRROR_BYTE
    sta (DST2_PTR),y
    iny
    iny
    bne MIRROR_PAIRS_UNTIL_ZERO

; Build a byte-order-REVERSED, bit-mirrored copy of a 128-byte block into the
; 128 bytes right after it (offsets $00-$7F copied+flipped to $80-$FF): the
; first loop reads 3 source bytes at a time and writes their mirror images
; far ahead (roughly +64 offset, converging on a 128-byte spacing overall);
; the second pushes the first 128 bytes onto the stack then pops them back
; off (LIFO - Last In, First Out, so popping reverses the order they went in)
; mirroring each as it's stored into the second half. Net effect: a
; horizontally + bit-flipped twin of the first half of this character block -
; plausibly a mirror-image variant (e.g. facing the opposite direction) built
; from one set of source graphics rather than storing both by hand. (???:
; the precise offset arithmetic isn't independently re-derived step by step.)
DUPLICATE_QUADRANTS:
    ldy #$00

DUP_MIRROR_FORWARD_LOOP:
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
    bne DUP_MIRROR_FORWARD_LOOP
    ldy #$00
    pha                 ; stash A as a spare stack entry - see the note below

PUSH_HALF_BLOCK_LOOP:
    lda (DST_PTR),y
    pha
    iny
    bpl PUSH_HALF_BLOCK_LOOP  ; pushes all 128 bytes ($00-$7F) onto the stack
    pla                        ; discard the top one (the last byte pushed)

POP_MIRROR_REVERSE_LOOP:
    pla                 ; pop the NEXT one down - LIFO means this walks back
    jsr MIRROR_BYTE      ;   through the source bytes in REVERSE order
    sta (DST_PTR),y
    iny
    bne POP_MIRROR_REVERSE_LOOP  ; y: $80 up to $FF, wrapping to 0 to stop
    inc DST_PTR_HI
    jmp UNPACK_BLOCK_LOOP

; A second, separate transformation pass: read a (start, end) character-index
; range from the stream, then for each character in that range, 4-bit-rotate
; every byte and recombine adjacent bytes' rotated nibbles - the same
; "rotate a byte by N bits using N x LSR/ROR" trick as elsewhere in this file,
; applied here to build some derived/shifted variant of an existing
; character block at $53C0+ (see ROTATE_CHARSET_INNER below). (???: exact
; purpose of the resulting shifted characters not confirmed.)
ROTATE_CHARSET_ENTRY:
    jsr STREAM_NEXT_BYTE
    bne ROTATE_CHARSET_RANGE_SETUP
    rts                  ; control byte 0 -> nothing more to unpack, done

ROTATE_CHARSET_RANGE_SETUP:
    sta ZTMP_0B         ; range start index
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0C         ; range end index

ROTATE_CHARSET_OUTER:
    lda #$C0
    sta SRC_PTR
    lda #$53
    sta SRC_PTR_HI      ; SRC_PTR = $53C0: base of the block being rotated
    ldx ZTMP_0B
    inc ZTMP_0B
    cpx ZTMP_0C
    beq ROTATE_CHARSET_ENTRY  ; reached the end of the range -> read the next
                              ;   control byte (loops the whole routine)

; Walk SRC_PTR forward $40 (64) bytes per index in X - a "multiply by
; repeated addition" (X iterations of +$40) rather than a real multiply,
; since the 6502 has no MUL instruction.
ROTATE_CHARSET_CALC_SRC:
    lda #$40
    jsr PTR_SRC_ADD
    dex
    bne ROTATE_CHARSET_CALC_SRC
    ldy #$00

; For each pair of bytes in this character (63 bytes total), rotate the
; first byte right by 4 bits (into ZTMP_09), rotate the second right by 4
; bits (into ZTMP_0A), then combine: store (rotated byte1 | rotated byte0)
; at the first position and the plain rotated byte1 at the next - shuffling
; the two bytes' nibbles together.
ROTATE_CHARSET_INNER:
    stx ZTMP_09
    stx ZTMP_0A
    lda (SRC_PTR),y
    ldx #$04

ROTATE_NIBBLE_A:
    lsr a
    ror ZTMP_09
    dex
    bne ROTATE_NIBBLE_A
    sta (SRC_PTR),y
    iny
    lda (SRC_PTR),y
    ldx #$04

ROTATE_NIBBLE_B:
    lsr a
    ror ZTMP_0A
    dex
    bne ROTATE_NIBBLE_B
    ora ZTMP_09
    sta (SRC_PTR),y
    iny
    lda ZTMP_0A
    sta (SRC_PTR),y
    iny
    cpy #$3F
    bne ROTATE_CHARSET_INNER
    beq ROTATE_CHARSET_OUTER

; -----------------------------------------------------------------------
; Convert a moving object's world sprite position (SPR_X_SHADOW/SPR_Y_SHADOW,
; the 9-bit hardware-sprite coordinates - X needs 9 bits since the VIC
; screen is wider than 255 pixels, hence the SPR_XMSB high-bit table) into a
; screen column/row (OBJ_TBLB3/OBJ_TBLBB, matching the labels already
; confirmed in claude/Weapons_Truck_Notes.md), tracks whether the object is
; currently within the visible vertical range (via HIT_ACCUM - see below),
; and classifies the road tile(s) under the object into a "distance" bucket
; via OBJ_DIST_TBL - almost certainly driving Spy Hunter's pseudo-3D
; perspective effect (things further up the screen = further away = drawn
; smaller/differently), though the exact use of the resulting bucket value
; isn't traced past where it's stored. (???)
OBJ_CALC_SCREEN_POS:
    ldx OBJ_IDX
    clc
    lda BIT_MASK
    and SPR_XMSB        ; this object's high (9th) X bit
    beq COMBINE_X_MSB
    sec

; Combine the 9th X bit (in carry) with the 8-bit shadow X into one value via
; ROR, then divide down to a character column: two more LSRs (a slightly
; different scale than the straight /8 you'd expect - this game's road
; margins/off-screen area account for the extra "-5" offset below).
COMBINE_X_MSB:
    php                 ; stash the carry (9th X bit) - AND/LSR below would clobber it
    ldy OBJ_IDX2
    lda a:SPR_X_SHADOW,y
    plp                 ; get the 9th X bit back into carry
    ror a
    lsr a
    sec
    sbc #$05
    lsr a
    cmp #$04
    bcc OBJ_OFFSCREEN   ; column < 4 -> off-screen (left)
    cmp #$24
    bcc OBJ_ONSCREEN_X  ; column < $24 (36) -> valid on-screen column

OBJ_OFFSCREEN:
    lda #$FF            ; off-screen sentinel column
    jmp OBJ_OFFSCREEN_ROW

; On-screen horizontally: store the column, then work out the row from Y,
; and along the way update HIT_ACCUM - this object's bit is SET while it's
; within the valid vertical range, CLEARED if it's scrolled off the top or
; bottom. HIT_ACCUM's per-object bits are presumably consulted by whatever
; (not yet traced) does pairwise collision/weapon-hit checks, so this is
; effectively "is this object even eligible to be hit/collide right now".
OBJ_ONSCREEN_X:
    pha                 ; save the column
    sta OBJ_TBLB3,x
    lda a:SPR_Y_SHADOW,y
    sec
    sbc #$28
    bcs OBJ_Y_IN_RANGE
    lda BIT_MASK_INV
    and HIT_ACCUM       ; too close to the top -> clear this object's bit
    ldy #$00
    beq OBJ_STORE_HIT_ACCUM  ; (unconditional - the AND above left Z set)

OBJ_Y_IN_RANGE:
    cmp #$C1
    bcc OBJ_CALC_ROW
    lda BIT_MASK_INV
    and HIT_ACCUM       ; too close to the bottom -> clear this object's bit
    ldy #$2C
    bne OBJ_STORE_HIT_ACCUM   ; (unconditional - Y is nonzero)

OBJ_CALC_ROW:
    lsr a
    lsr a
    and #$FE
    tay                 ; Y = row-table index
    lda BIT_MASK
    ora HIT_ACCUM       ; in valid range -> SET this object's bit

OBJ_STORE_HIT_ACCUM:
    sta HIT_ACCUM
    lda ROWADDR_LO,y    ; look up this row's screen address (the table built
    sta SRC_PTR          ;   in BUILD_ROWADDR_LOOP, Stage 2)
    lda ROWADDR_HI,y
    sta SRC_PTR_HI
    tya
    lsr a
    sta OBJ_TBLBB,x     ; store the screen row
    pla
    tay                 ; column back into Y
    lda (SRC_PTR),y     ; read the 3 screen-tile bytes at/around the object's
    pha                  ;   position (whatever's already drawn there - road,
    iny                   ;   water, another blitted object, ...)
    lda (SRC_PTR),y
    pha
    iny
    lda (SRC_PTR),y
    ldy #$02
    sty ZTMP_08         ; process 3 bytes total (loop counter)

; For each of the 3 tile bytes read above, find its "distance bucket" by
; scanning OBJ_DIST_TBL's 13 ascending thresholds (first one the byte is
; LESS than wins; falls back to bucket 0 if none match) and store the bucket
; index into OBJ_TBL6B/OBJ_TBL73 (the first and third bytes; the middle one
; only feeds the next iteration's comparison, per OBJ_BUCKET_NEXT below).
OBJ_CLASSIFY_TILE_LOOP:
    ldy #$00

OBJ_DIST_SCAN:
    cmp OBJ_DIST_TBL,y
    bcc OBJ_BUCKET_FOUND
    iny
    cpy #$0D
    bcc OBJ_DIST_SCAN
    ldy #$00            ; no threshold matched -> bucket 0

OBJ_BUCKET_FOUND:
    tya
    dec ZTMP_08
    bmi OBJ_TILE_CLASSIFY_DONE
    beq OBJ_BUCKET_NEXT
    sta OBJ_TBL6B,x

OBJ_BUCKET_NEXT:
    sta OBJ_TBL73,x
    pla
    jmp OBJ_CLASSIFY_TILE_LOOP

OBJ_OFFSCREEN_ROW:
    sta OBJ_TBL6B,x
    sta OBJ_TBL73,x

OBJ_TILE_CLASSIFY_DONE:
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
; For the CURRENT object (OBJ_IDX2), compute its X/Y DELTA to each of the 8
; hardware sprites in turn, clamp each delta to a signed 7-bit range, and
; pack it (sign bit + magnitude) into SPR_STAGE. This looks like prep work
; for the sprite-multiplexing system (SPR_STAGE is consumed elsewhere as
; "staged hardware sprite coords") - likely used to decide proximity/
; ordering when deciding which hardware sprite to reassign to which object,
; though the exact downstream use isn't traced from here. (???)
;
; The outer/inner-loop split (ZTMP_0A starting at 1, doubled via ASL each
; pass, looping while carry stays clear) is the same "repeat exactly 8
; times without a separate counter byte" idiom seen in
; INIT_ALL_OBJECT_SLOTS_LOOP (Stage 2) - it walks the single 1-bit through
; all 8 positions.
OBJ_CALC_SPRITE_DELTA:
    ldy OBJ_IDX2
    ldx #$00
    lda #$01
    sta ZTMP_0A
    lda BIT_MASK
    and SPR_XMSB
    clc
    beq OBJ_DELTA_GET_XY
    sec

; Combine this object's 9th X bit with its 8-bit X (same ROR trick as
; OBJ_CALC_SCREEN_POS) into ZTMP_0C; save its Y into ZTMP_0D. These become
; the "origin" every hardware sprite's delta is measured from.
OBJ_DELTA_GET_XY:
    lda a:SPR_X_SHADOW,y
    ror a
    sta ZTMP_0C
    lda a:SPR_Y_SHADOW,y
    sta ZTMP_0D
    ldy #$00

OBJ_DELTA_LOOP:
    lda ZTMP_0A
    and SPR_XMSB
    clc
    beq OBJ_DELTA_X
    sec

; X delta: subtract this object's X from hardware sprite X's (9-bit-combined
; via the same ROR trick). If negative, take the absolute value and clamp
; to 63 (with the sign bit re-added via ORA #$40 - not two's complement, a
; sign+magnitude encoding); if positive, just clamp to 63. Either way,
; double it (ASL) before storing - SPR_STAGE presumably reserves the low bit
; for something else, or this doubling matches a table stride elsewhere.
OBJ_DELTA_X:
    lda SPR_X_SHADOW,x
    ror a
    sec
    sbc ZTMP_0C
    bpl OBJ_DELTA_X_POS
    eor #$FF            ; negate (with the +1 below, this is -value via
    clc                  ;   two's-complement negation)
    adc #$01
    cmp #$40
    bcc OBJ_DELTA_X_NEG_CLAMP
    lda #$3F

OBJ_DELTA_X_NEG_CLAMP:
    ora #$40            ; set the sign bit on the (now-positive) magnitude
    bne OBJ_DELTA_X_STORE   ; (unconditional - ORA #$40 is never zero)

OBJ_DELTA_X_POS:
    cmp #$40
    bcc OBJ_DELTA_X_STORE
    lda #$3F

OBJ_DELTA_X_STORE:
    asl a
    sta a:SPR_STAGE,y
    iny
    sec
    ; same clamp-and-sign pattern again, this time for Y (range 0-127
    ; instead of 0-63, since Y doesn't get doubled/shared the same way)
    lda SPR_Y_SHADOW,x
    sbc ZTMP_0D
    bpl OBJ_DELTA_Y_POS
    eor #$FF
    clc
    adc #$01
    cmp #$80
    bcc OBJ_DELTA_Y_NEG_CLAMP
    lda #$7F

OBJ_DELTA_Y_NEG_CLAMP:
    ora #$80
    bne OBJ_DELTA_Y_STORE    ; (unconditional)

OBJ_DELTA_Y_POS:
    cmp #$80
    bcc OBJ_DELTA_Y_STORE
    lda #$7F

OBJ_DELTA_Y_STORE:
    sta a:SPR_STAGE,y
    iny
    inx
    inx
    asl ZTMP_0A
    bcc OBJ_DELTA_LOOP
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
; Moving-object engine (per frame) - walks all 8 object slots (7 downto 0),
; runs each one's type-specific move and draw handlers (reached indirectly
; through OBJ_VEC1_DISPATCH/OBJ_VEC2_DISPATCH - see ZVEC_MOVE/ZVEC_DRAW in
; the equates), and builds two "collision mask" bytes (HIT_MASK_A/B) at the
; end from whichever objects are currently on-screen (HIT_ACCUM, built up
; per-slot by OBJ_CALC_SCREEN_POS) AND flagged as belonging to certain
; "hit groups" (HIT_GROUP0/1/2 - presumably "hero", "enemy", "hazard" or
; similar categories, not confirmed). This is very likely the entry point
; into collision handling, though the actual pairwise hit-test and the
; enemy-destroyed -> SCORE_EVENT logic live inside the per-type handlers
; dispatched below (see the note on the following data block - those
; handlers are stored as raw, not-yet-disassembled bytes).
PROCESS_OBJECTS:
    ldx #$07
    lda #$80
    sta BIT_MASK        ; BIT_MASK starts as %10000000 (slot 7's bit)...
    eor #$FF
    sta BIT_MASK_INV    ; ...and BIT_MASK_INV its complement

; Per-slot setup: point VEC_OBJMOVE at this slot's move routine (from the
; per-SLOT OBJMOVE_VEC_LO/HI table), then either dispatch through it
; directly (if OBJ_TYPE's top bit is set - the hero/empty-slot convention
; from claude/Dock_Exit_Notes.md) or, for ordinary positive OBJ_TYPE values,
; copy this TYPE's 4-byte move+draw vector pair out of OBJINIT_PARAM_TBL
; into ZVEC_MOVE/ZVEC_DRAW and run the full move -> position -> draw chain.
OBJECT_LOOP:
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
    bpl TYPE_DISPATCH
    jsr OBJ_MOVE_DISPATCH   ; type has bit 7 set -> hero/empty-slot handler
    bcc OBJECT_LOOP_NEXT

TYPE_DISPATCH:
    lda OBJ_TYPE,x
    sta ZTMP_0F
    asl a
    asl a               ; TYPE * 4 = byte offset into OBJINIT_PARAM_TBL
    tay
    ldx #$00

COPY_TYPE_VECTORS:
    lda OBJINIT_PARAM_TBL,y
    sta ZVEC_MOVE,x     ; copies 4 bytes: move-vec lo/hi, draw-vec lo/hi
    iny
    inx
    cpx #$04
    bne COPY_TYPE_VECTORS
    jsr OBJ_CALC_SCREEN_POS
    jsr OBJ_CALC_SPRITE_DELTA
    ldy OBJ_IDX2
    ldx OBJ_IDX
    jsr OBJ_VEC1_DISPATCH   ; run this type's MOVE handler
    ldx OBJ_IDX
    lda OBJ_ANIM,x
    asl a
    tay
    lda (ZVEC_DRAW),y   ; the draw vector is itself a small per-ANIM-frame
    pha                  ;   table - so each object type can have a
    iny                   ;   different draw routine per animation frame
    lda (ZVEC_DRAW),y
    sta ZVEC_DRAW_HI
    pla
    sta ZVEC_DRAW
    ldy OBJ_IDX2
    jsr OBJ_VEC2_DISPATCH   ; run this frame's DRAW handler

; After moving/drawing, update this slot's bit in HIT_ACCUM based on its
; screen Y: only objects roughly within rows $37-$EF count as "on-screen for
; collision purposes" (a tighter vertical band than OBJ_CALC_SCREEN_POS's
; own on/off-screen test).
    ldy OBJ_IDX2
    lda HIT_ACCUM
    ldx SPR_Y_SHADOW,y
    cpx #$37
    bcc CLEAR_HIT_BIT
    cpx #$F0
    bcs CLEAR_HIT_BIT
    ora BIT_MASK
    bne STORE_HIT_BIT   ; (unconditional - ORA of a nonzero bit is nonzero)

CLEAR_HIT_BIT:
    and BIT_MASK_INV

STORE_HIT_BIT:
    sta HIT_ACCUM

OBJECT_LOOP_NEXT:
    ldx OBJ_IDX

; Advance to the next slot: BIT_MASK/BIT_MASK_INV shift down together (same
; single-bit-walk idiom as before, here counting DOWN through slots 7-0
; instead of up), skipping any slot currently reserved by the sprite
; multiplexer (MUX_SLOT0/1/2 - those get processed separately, not as
; ordinary objects here).
NEXT_SLOT:
    lsr BIT_MASK
    sec
    ror BIT_MASK_INV
    dex
    bmi ALL_SLOTS_DONE
    cpx MUX_SLOT0
    beq NEXT_SLOT
    cpx MUX_SLOT1
    beq NEXT_SLOT
    cpx MUX_SLOT2
    beq NEXT_SLOT
    jmp OBJECT_LOOP

; All 8 slots processed: combine HIT_ACCUM (which slots are on-screen) with
; the HIT_GROUP0/1/2 masks (which slots belong to which collision category)
; into two final masks other code checks for actual collisions.
ALL_SLOTS_DONE:
    lda HIT_GROUP0
    and HIT_ACCUM
    and HIT_GROUP1
    sta HIT_MASK_A
    lda HIT_GROUP2
    and HIT_ACCUM
    sta HIT_MASK_B
    rts
; -----------------------------------------------------------------------
; OBJMOVE_VEC_LO/HI (8 addresses, one per SLOT) + OBJINIT_PARAM_TBL (4-byte
; move/draw vector entries, one per object TYPE - the first 4 entries here
; are TYPE $00-$03, all identical: move=$9A8E draw=$90AA, matching the hero
; sub-state finding in claude/Dock_Exit_Notes.md / Enemy_Invincibility_Notes.md).
;
; After the vector tables, this data block continues into the ACTUAL MACHINE
; CODE for the per-object-type move/draw handlers themselves (e.g. the
; hero's own move logic starting around $8EA5 - readable opcode-by-opcode if
; you want to trace it: A5 A3 = LDA HERO_STATE, C9 07 = CMP #$07, and so on).
; These handlers are only ever reached INDIRECTLY, through OBJ_VEC1_DISPATCH/
; OBJ_VEC2_DISPATCH's runtime pointer lookup (PROCESS_OBJECTS above) - a
; disassembler walking the file top-to-bottom in a straight line has no way
; to know code lives here, so it's left as raw .byte data rather than
; expanded into labelled instructions. This is genuinely the single largest
; remaining undisassembled chunk of real game logic in this file - it's
; extremely likely where per-enemy-type behaviour (the Road Lord's "can't be
; shot", the different weapons, etc. - see claude/Enemy_Agents_Manual_Reference.md)
; and the enemy-destroyed -> SCORE_EVENT scoring-tier logic actually live.
; Turning this into real, commented 6502 (rather than one big data blob) is
; a substantial task of its own, left for a future session.
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
; Clear moving-object slot X (Y = X*2, i.e. caller passes OBJ_IDX/OBJ_IDX2
; already set up, same convention as PROCESS_OBJECTS): zero its sprite
; position, mark it OBJ_TYPE=$FF (empty), point its hardware sprite at the
; blank shape, and clear its bit out of every hit-related mask - a freshly
; emptied slot can't be on-screen or collidable.
INIT_OBJECT_SLOT:
    lda BIT_MASK_INV
    and SPR_XMSB
    sta SPR_XMSB
    lda #$00
    sta a:SPR_X_SHADOW,y
    sta a:SPR_Y_SHADOW,y
    sta OBJ_TBLAB,x
    lda #$FF
    sta OBJ_TYPE,x      ; $FF = empty (per the hero/type convention already
                        ;   documented in claude/Dock_Exit_Notes.md)
    lda #$95
    jsr SET_SPRITE_PTR  ; $95 = the blank/empty sprite shape
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
; More per-object-type/hero state-machine handler CODE stored as raw data,
; same situation as the block right after PROCESS_OBJECTS above (only
; reachable indirectly via the ZVEC_MOVE/ZVEC_DRAW/VEC_STATE dispatch
; vectors, so never picked up as code by a straight-line disassembly pass).
; This is a substantial chunk (~80 lines) - almost certainly containing the
; individual behaviour of each enemy type (weapons, movement patterns) and
; the hero's own crash/collision handling. Left as a labelled-but-unexpanded
; data block for a future session rather than hand-disassembled here; see
; the equivalent note after PROCESS_OBJECTS for how to start tracing it
; (each 3-byte "opcode + address" or 2-byte "opcode + value" group can be
; decoded by hand against a 6502 opcode table).
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
; Start the 3-voice "Peter Gunn" theme: silence everything, then request
; sound-effect index $02 on voice 1, $04 on the "voice 0B" queue, and $06 on
; voice 2 - three simultaneous SOUND_REQ_* calls kick off the three SID
; voices' independent note sequences (see MUSIC_DRIVER further down for how
; a queued request turns into actual SID register writes).
MUSIC_START_THEME:
    jsr SOUND_SILENCE
    ldy #$02
    jsr SOUND_REQ_V1
    ldy #$04
    jsr SOUND_REQ_V0B
    ldy #$06
    jmp SOUND_REQ_V2
; -----------------------------------------------------------------------
; More per-object-type/hero state-machine handler CODE stored as raw data -
; the same situation as the two blocks noted in Stage 5 (PROCESS_OBJECTS/
; INIT_OBJECT_SLOT): only reachable indirectly via the ZVEC_MOVE/ZVEC_DRAW/
; VEC_STATE dispatch vectors, so a straight-line disassembly never picks it
; up as code. This is the largest such block in the file (~1650 bytes) -
; left unexpanded for a future focused session, same as its counterparts.
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
; Weapon / collision handler routines and their dispatch tables, as data -
; the same situation as the two data blocks in Stage 5 above (real 6502
; code, only reached indirectly via a runtime vector, so left undisassembled
; by a straight-line pass). This is the LARGEST such block in the file
; (~1000 bytes) and, per its existing label, is specifically about weapons
; and collisions - meaning this very likely contains the actual pairwise
; hit-test against HIT_MASK_A/B (built in PROCESS_OBJECTS above) and the
; code that queues SCORE_EVENT on an enemy kill (see
; claude/Enemy_Agents_Manual_Reference.md's confirmed POINTS_TBL - 150/500/
; 700-point tiers - for what a full decode here would likely explain: which
; OBJ_TYPE maps to which enemy, and why the Road Lord specifically never
; registers a hit). A strong candidate for a focused future session rather
; than folded into this general annotation pass.
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
; Already partly documented from the road/river investigation (see the
; spyhunter.asm header's ROAD MAP notes and claude/Road_Map_Decode.md) -
; this is where ROAD_FEATURE $11/$13/$14/$15 get checked as scripted
; triggers. Reading the full routine now (previously only its trigger
; checks were traced): it does three unrelated things in sequence.
UPDATE_SCENE_SELECT:
    lda SEQ_STATE
    beq HERO_STATE_TRACK    ; SEQ_STATE 0 or >=6 -> skip the sign-cycle
    cmp #$06                ;   logic below entirely, go straight to
    bcs HERO_STATE_TRACK     ;   tracking the hero's state
    lda ROAD_SEG_IDX
    cmp #$0F            ; segment $0F = the river-entrance segment
    beq FRAME_SUBCTR_CHECK  ; -> skip the sign cycling here too
    lda ROAD_FEATURE
    cmp #$11
    beq SIGN_CYCLE_ARM   ; feature $11 -> arm/advance the sign cycle
    lda PREV_FEATURE
    cmp #$15
    beq SIGN_CYCLE_ARM   ; just left the water (feature $15) -> same
    lda #$00
    sta STATE_4D17       ; otherwise, not near a trigger point: reset
    beq FRAME_SUBCTR_CHECK   ; the "already armed this pass" flag

; A 3-value round-robin counter (STATE_4D16: 3,2,1,3,2,1,...) that only
; advances once per arming (guarded by STATE_4D17, so repeated frames at the
; same trigger point don't re-advance it). Candidate: cycling through the
; road-sign messages in ONROAD_MSG_TBL (DETOUR/BRIDGE OUT/ICY ROADS etc, see
; the header's ON-ROAD TEXT notes) so consecutive river-entrance/exit
; crossings show different signs. (???: not confirmed which sign maps to
; which counter value.)
SIGN_CYCLE_ARM:
    lda STATE_4D17
    bne FRAME_SUBCTR_CHECK   ; already armed this pass -> don't re-advance
    ldy STATE_4D16
    tya
    dey
    bne SIGN_CYCLE_STORE
    ldy #$03            ; wrapped past 1 -> back to 3

SIGN_CYCLE_STORE:
    sty STATE_4D16
    sta STATE_4D17      ; mark "armed" (nonzero) until reset above

; Track the hero's own state into STATE_4DAC, but only while it's a "normal"
; (bit 7 clear) value - the $80-$FF range is reserved for the hero/empty-slot
; sentinel convention (claude/Dock_Exit_Notes.md), so this deliberately
; skips recording those.
HERO_STATE_TRACK:
    ldx HERO_STATE
    bmi FRAME_SUBCTR_CHECK
    stx STATE_4DAC

; Every 6th frame, bump one of two STAT_CTR counters depending on whether
; ROAD_FEATURE or PREV_FEATURE is currently $14 (the water-loop random-spawn
; trigger, claude/Boat_River_Notes.md) - i.e. tallying frames spent in that
; specific water-loop state vs. not. Purpose of the tally not confirmed
; (possibly difficulty pacing or spawn-rate tuning). (???)
FRAME_SUBCTR_CHECK:
    lda FRAME_SUBCTR
    cmp #$06
    bcc SCENE_IDX_UPDATE
    ldx #$00
    stx FRAME_SUBCTR
    lda #$14
    cmp ROAD_FEATURE
    beq STAT_CTR_BUMP
    cmp PREV_FEATURE
    beq STAT_CTR_BUMP
    inx

STAT_CTR_BUMP:
    inc STAT_CTR,x

; Recompute SCENE_IDX (the fork-selector variable that steers left/right at
; road forks, per claude/Road_Map_Decode.md) from STATE_4DB9, but only near
; specific segments (exactly $07, or $0F-$11) and only adjusted by whether
; SCENE_ID is 5 or 6 (candidates: car vs. boat scene, given SCENE_ID is
; documented elsewhere as "car/boat/..." - see the equates). Everywhere
; else, SCENE_IDX is simply left as STATE_4DB9 unchanged.
SCENE_IDX_UPDATE:
    lda STATE_4DB9
    ldy #$12
    ldx ROAD_SEG_IDX
    cpx #$07
    beq SCENE_ID_CHECK
    cpx #$0F
    bcc SCENE_IDX_STORE     ; segment < $0F -> just store STATE_4DB9 as-is
    cpx #$12
    bcs SCENE_IDX_STORE     ; segment >= $12 -> same

SCENE_ID_CHECK:
    ldx SCENE_ID
    cpx #$06
    beq SCENE_IDX_FROM_Y
    cpx #$05
    bne SCENE_IDX_DONE   ; SCENE_ID isn't 5 or 6 -> leave SCENE_IDX untouched
    iny                   ; SCENE_ID==5 -> Y=$13 instead of $12

SCENE_IDX_FROM_Y:
    tya

SCENE_IDX_STORE:
    sta SCENE_IDX

SCENE_IDX_DONE:
    rts

; -----------------------------------------------------------------------
; Decode the road/scene layout stream (another compressed byte-stream
; interpreter, same overall style as UNPACK_CHARSET) into the road template
; RAM at $2980+ - the exact area later read as SCROLL_SRC by the road-scroll
; IRQ (READ_ROAD_ROW, claude/Road_Map_Decode.md) and referenced as the
; OBJ_ADDR_LO/HI table target. In short: this BUILDS the per-feature road
; row graphics that the scrolling engine later just points at; the game
; doesn't ship every road row as a full bitmap, it ships this much smaller
; compressed description and expands it once at startup.
;
; Top-level modes (each driven by a control byte from STREAM_NEXT_BYTE):
;  - literal/run bytes into the current 32-byte destination row
;  - mirrored duplication of part of a row (EOR #$01 - toggles between a
;    tile and its horizontal-mirror pair, same trick as MIRROR_BYTE)
;  - repeat the previous 32-byte row range N times (a cheap way to draw a
;    long straight stretch without repeating the same block many times)
;  - row mirroring/flipping against the previous row (DRAW_MIRROR_ROWS /
;    DRAW_FLIP_ROWS below) - building the OTHER side of a symmetric road
;    from one side's data
;  - a final "expand object templates" pass (MAP_EXPAND_RUN/MAP_COPY_BLOCK)
;    that blits smaller per-object graphics (OBJ_ADDR_LO/HI - the exact
;    16-entry table decoded in claude/Road_Map_Decode.md) into place
;  - a random "texture jitter" pass (RNG_NEXT-driven) that perturbs certain
;    tile codes in a range, giving the water/road texture some organic
;    variation instead of looking perfectly uniform
UNPACK_MAP_DATA:
    lda #$60
    sta MAP_SRC
    lda #$29
    sta MAP_SRC_HI      ; MAP_SRC = $2960 (previous-row scratch)
    lda #$80
    sta MAP_DST
    sta MAP_ROW
    lda #$29
    sta MAP_DST_HI      ; MAP_DST = MAP_ROW = $2980 (destination, matches
    sta MAP_ROW_HI       ;   OBJ_ADDR_LO/HI's base address exactly)
    lda #$CB
    sta STREAM_PTR
    lda #$AD
    sta STREAM_PTR_HI   ; compressed source stream starts at $ADCB (ROM)
    ldy #$00

; Literal-row mode: fill 32 bytes at MAP_DST. Each source byte is either
; used directly (values $40+) or triggers reading ONE MORE stream byte to
; use instead (values $00-$13, i.e. treated as a 1-byte "repeat count" of 1 -
; effectively a small escape range reserved for values that would otherwise
; be ambiguous with control bytes elsewhere in this format).
ROW_FILL_ENTRY:
    jsr STREAM_NEXT_BYTE
    bne ROW_FILL_START
    beq ROW_BLOCK_REPEAT   ; (unconditional - control byte was 0)

ROW_FILL_RESTART:
    ldy #$00

ROW_FILL_START:
    ldx #$01
    cmp #$14
    bcc ROW_FILL_ESCAPE
    cmp #$40
    bcc ROW_FILL_STORE

ROW_FILL_ESCAPE:
    pha
    jsr STREAM_NEXT_BYTE
    pla

ROW_FILL_STORE:
    sta (MAP_DST),y
    iny
    dex
    bne ROW_FILL_STORE  ; (dex from ldx#$01 -> this only ever runs once per
                        ;   byte - X isn't a real "fill count" here)
    beq ROW_FILL_ENTRY

; Mirror mode: read a control byte; if its top bit is clear, skip straight
; to the block-repeat step below. Otherwise, take the low 5 bits as a
; repeat count and mirror-duplicate part of the just-written row (toggling
; each tile's mirror-pair bit via EOR #$01) into the following bytes.
ROW_BLOCK_REPEAT:
    jsr STREAM_NEXT_BYTE
    bpl COPY_PREV_ROWS
    and #$1F
    tax
    lda #$0F
    sta ZTMP_09
    lda #$10
    sta ZTMP_0A

MIRROR_ROW_LOOP:
    ldy ZTMP_09
    lda (MAP_DST),y
    eor #$01
    ldy ZTMP_0A
    sta (MAP_DST),y
    inc ZTMP_0A
    dec ZTMP_09
    bpl MIRROR_ROW_LOOP

; Block-repeat: copy the 32-byte row at MAP_SRC to MAP_DST, X times (X was
; set above, either from the mirror step's repeat count or falls through as
; 0/unset if that step was skipped) - the "repeat a straight stretch of
; road" mechanism.
COPY_PREV_ROWS:
    clc
    lda MAP_SRC
    adc #$20
    sta MAP_SRC
    bcc ROW_ADVANCE_DST
    inc MAP_SRC_HI

ROW_ADVANCE_DST:
    clc
    lda MAP_DST
    adc #$20
    sta MAP_DST
    bcc ROW_REPEAT_CHECK
    inc MAP_DST_HI

ROW_REPEAT_CHECK:
    dex
    bmi MAP_BLOCK_DONE
    ldy #$1F

ROW_REPEAT_COPY:
    lda (MAP_SRC),y
    sta (MAP_DST),y
    dey
    bpl ROW_REPEAT_COPY
    bmi COPY_PREV_ROWS  ; (unconditional - dey went negative to exit above)

; A whole "block" of rows is finished: shuffle MAP_ROW/MAP_PREV bookkeeping
; forward, then check the next control byte to decide whether to mirror
; and/or flip this block against the previous one (building the opposite
; side of a symmetric road segment), before looping back for the next block.
MAP_BLOCK_DONE:
    jsr STREAM_NEXT_BYTE
    bne ROW_FILL_RESTART
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
    beq BLOCK_NEXT
    bpl MIRROR_THEN_CHECK
    jsr DRAW_FLIP_ROWS
    jmp BLOCK_NEXT

MIRROR_THEN_CHECK:
    jsr DRAW_MIRROR_ROWS
    jsr STREAM_NEXT_BYTE
    beq BLOCK_NEXT
    jsr DRAW_FLIP_ROWS
    jsr DRAW_MIRROR_ROWS

BLOCK_NEXT:
    jsr STREAM_NEXT_BYTE
    beq OBJECT_EXPAND_ENTRY
    jmp ROW_FILL_RESTART

; Object-template expansion: read a chain of (width, height, dest, [src])
; records; a zero src signals "run-length expand instead of copy" (handled
; by MAP_EXPAND_RUN, which reads directly from OBJ_ADDR_LO/HI by feature
; index rather than an explicit address). A zero width/count byte ends the
; chain and falls into the road-texture randomiser below.
OBJECT_EXPAND_ENTRY:
    jsr STREAM_NEXT_BYTE
    beq TEXTURE_JITTER_ENTRY
    sta ZTMP_30
    jsr STREAM_NEXT_BYTE
    sta BLIT_COUNT
    jsr STREAM_NEXT_BYTE
    sta SCREEN_PTR_HI
    jsr STREAM_NEXT_BYTE
    sta SCREEN_PTR
    jsr STREAM_NEXT_BYTE
    beq RUN_EXPAND_ENTRY
    sta SRC_PTR_HI
    jsr STREAM_NEXT_BYTE
    sta SRC_PTR
    jsr MAP_COPY_BLOCK
    jmp OBJECT_EXPAND_ENTRY

RUN_EXPAND_ENTRY:
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0B
    jsr STREAM_NEXT_BYTE
    sta ZTMP_0C
    jsr MAP_EXPAND_RUN
    jmp OBJECT_EXPAND_ENTRY

; Road-texture randomiser: walk every byte in $2980-$5CFF and, for tile
; codes in range $08-$13 (the water texture range, per
; claude/Water_Bridge_Notes.md), replace with a fresh random pick from that
; same range via RNG_NEXT - so the water's "rippling" texture isn't
; perfectly uniform even though it's built from a repeating template. Once
; done, COPY_PAGES duplicates the finished $4D00 pages to $C000 (matching
; the "second graphics bank" address range identified for scripted-feature
; rows $10+ in claude/Broken_Bridge_Notes.md / Road_Map_Decode.md).
TEXTURE_JITTER_ENTRY:
    lda #$80
    sta SRC_PTR
    lda #$29
    sta SRC_PTR_HI
    ldx #$00

TEXTURE_JITTER_LOOP:
    lda (SRC_PTR,x)
    cmp #$08
    bcc TEXTURE_SPECIAL_RANGE
    cmp #$14
    bcs TEXTURE_SPECIAL_RANGE

TEXTURE_RANDOM_PICK:
    jsr RNG_NEXT
    and #$0F
    sec
    sbc #$04
    bmi TEXTURE_RANDOM_PICK   ; reject/retry until the result is in range
    clc
    adc #$08            ; -> a fresh random value in $08-$13
    bne TEXTURE_JITTER_STORE   ; (unconditional - adding #$08 to 0-11 is never 0)

; A second, narrower tile range ($14-$2B) gets a different, less-random
; nudge (+-4) roughly every 8th byte (via a running counter's bit 3) -
; likely a subtler variation for a different texture family (e.g. road
; surface rather than water).
TEXTURE_SPECIAL_RANGE:
    pha
    cmp #$14
    bcc TEXTURE_JITTER_SKIP
    cmp #$2C
    bcs TEXTURE_JITTER_SKIP
    inc ZTMP_09
    lda ZTMP_09
    and #$08
    bne TEXTURE_JITTER_SKIP
    pla
    pha
    and #$04
    bne TEXTURE_NUDGE_UP
    pla
    sec
    sbc #$04
    bne TEXTURE_JITTER_STORE

TEXTURE_NUDGE_UP:
    pla
    clc
    adc #$04

TEXTURE_JITTER_STORE:
    sta (SRC_PTR,x)
    jmp TEXTURE_JITTER_NEXT

TEXTURE_JITTER_SKIP:
    pla

TEXTURE_JITTER_NEXT:
    jsr PTR_SRC_INC
    lda SRC_PTR_HI
    cmp #$5D
    bcc TEXTURE_JITTER_LOOP
    lda #$4D
    ldy #$C0
    ldx #$10
    jmp COPY_PAGES

; Helper for the block-mirror step above: mirror-duplicate ($EOR #$01) each
; byte of the block starting at DST2_PTR into SRC_PTR, row by row, until
; DST2_PTR reaches MAP_ROW (the top of the block being mirrored).
DRAW_MIRROR_ROWS:
    ldx #$00

MIRROR_ROWS_OUTER:
    ldy #$1F

MIRROR_ROWS_INNER:
    lda (DST2_PTR,x)
    eor #$01
    sta (SRC_PTR),y
    jsr PTR_AUX_INC
    lda DST2_PTR_HI
    cmp MAP_ROW_HI
    bne MIRROR_ROWS_CONTINUE
    lda DST2_PTR
    cmp MAP_ROW
    beq FLIP_MIRROR_DONE

MIRROR_ROWS_CONTINUE:
    dey
    bpl MIRROR_ROWS_INNER
    lda #$20
    jsr PTR_SRC_ADD
    jmp MIRROR_ROWS_OUTER

; Helper for the block-flip step: similar row walk, but instead of a
; straight mirror it re-maps certain tile ranges ($14-$2B, +-4 shift based
; on bit 2) before an EOR #$02 - building a left/right-flipped variant of
; the road edge/shoulder tiles rather than a plain mirror.
DRAW_FLIP_ROWS:
    ldx #$00

FLIP_ROWS_OUTER:
    ldy #$1F

FLIP_ROWS_INNER:
    lda (DST_PTR,x)
    cmp #$14
    bcc FLIP_TILE_REMAP
    cmp #$2C
    bcs FLIP_TILE_REMAP
    pha
    and #$04
    bne FLIP_NUDGE_DOWN
    pla
    sec
    sbc #$04
    jmp FLIP_TILE_REMAP

FLIP_NUDGE_DOWN:
    pla
    clc
    adc #$04

FLIP_TILE_REMAP:
    eor #$02
    sta (SRC_PTR),y
    sec
    lda DST_PTR
    sbc #$01
    sta DST_PTR
    bcs FLIP_ROWS_HI_OK
    dec DST_PTR_HI

FLIP_ROWS_HI_OK:
    lda DST_PTR_HI
    cmp MAP_PREV_HI
    bcc FLIP_MIRROR_DONE
    beq FLIP_ROWS_CHECK_LO

FLIP_ROWS_CONTINUE:
    dey
    bpl FLIP_ROWS_INNER
    lda #$20
    jsr PTR_SRC_ADD
    jmp FLIP_ROWS_OUTER

FLIP_ROWS_CHECK_LO:
    lda DST_PTR
    cmp MAP_PREV
    bcs FLIP_ROWS_CONTINUE

; Shared tail for both DRAW_MIRROR_ROWS and DRAW_FLIP_ROWS: advance
; MAP_ROW/MAP_PREV/MAP_DST bookkeeping to just past the block that was
; just built, ready for the next one.
FLIP_MIRROR_DONE:
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

; Expand one road-FEATURE's template (indexed by ZTMP_0B, walking up to
; ZTMP_0C) by run-length-copying it from OBJ_ADDR_LO/HI (claude/
; Road_Map_Decode.md's 16-entry table) into place via MAP_COPY_BLOCK -
; repeated BLIT_COUNT times per feature, i.e. this is what actually
; materialises each feature code's road-row graphics into RAM at load time,
; using the same table the runtime scroll engine later reads from.
MAP_EXPAND_RUN:
    ldx ZTMP_0B
    cpx ZTMP_0C
    bne EXPAND_NEXT_FEATURE
    jmp MAP_EXPAND_DONE

EXPAND_NEXT_FEATURE:
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
    beq EXPAND_DST_ADJUST
    bcc EXPAND_ROW_INIT
    sec
    lda SRC_PTR_HI
    sbc #$73
    sta SRC_PTR_HI

EXPAND_DST_ADJUST:
    sec
    lda DST_PTR_HI
    sbc #$73
    sta DST_PTR_HI

EXPAND_ROW_INIT:
    lda #$00
    sta ZTMP_0A

EXPAND_ROW_LOOP:
    ldy #$00

EXPAND_BYTE_SCAN:
    lda (SRC_PTR),y
    iny
    cmp #$04
    bcc EXPAND_ROW_END
    cmp #$08
    bcc EXPAND_CHECK_WIDTH

EXPAND_ROW_END:
    tya
    jmp EXPAND_ADVANCE

EXPAND_CHECK_WIDTH:
    cpy ZTMP_30
    bne EXPAND_BYTE_SCAN
    inc ZTMP_0A
    lda BLIT_COUNT
    cmp ZTMP_0A
    bne EXPAND_NEXT_ROW
    sec
    sbc #$01
    asl a
    asl a
    asl a
    asl a
    asl a
    bcc EXPAND_ROLLBACK
    dec SRC_PTR_HI

EXPAND_ROLLBACK:
    sta BIT_MASK
    sec
    lda SRC_PTR
    sbc BIT_MASK
    sta SRC_PTR
    bcs EXPAND_DO_COPY
    dec SRC_PTR_HI

EXPAND_DO_COPY:
    jsr MAP_COPY_BLOCK
    lda #$03

EXPAND_ADVANCE:
    jsr PTR_SRC_ADD
    lda SRC_PTR_HI
    cmp DST_PTR_HI
    bcc EXPAND_ROW_INIT
    lda SRC_PTR
    cmp DST_PTR
    bcc EXPAND_ROW_INIT
    jmp MAP_EXPAND_RUN

EXPAND_NEXT_ROW:
    lda #$20
    jsr PTR_SRC_ADD
    lda SRC_PTR_HI
    cmp DST_PTR_HI
    bcc EXPAND_ROW_LOOP
    lda SRC_PTR
    cmp DST_PTR
    bcc EXPAND_ROW_LOOP
    jmp MAP_EXPAND_RUN

MAP_EXPAND_DONE:
    rts

; Copy BLIT_COUNT rows x ZTMP_30 bytes from SCREEN_PTR to SRC_PTR - a plain
; rectangular block copy, used above by both the object-expansion chain and
; MAP_EXPAND_RUN's run-length path.
MAP_COPY_BLOCK:
    lda BLIT_COUNT
    sta BLIT_ROWS
    ldy #$00
    ldx #$00

COPY_BLOCK_ROW:
    lda ZTMP_30
    sta BLIT_WIDTH

COPY_BLOCK_BYTE:
    lda (SCREEN_PTR),y
    sta (SRC_PTR,x)
    iny
    dec BLIT_WIDTH
    beq COPY_BLOCK_ROW_DONE
    jsr PTR_SRC_INC
    jmp COPY_BLOCK_BYTE

COPY_BLOCK_ROW_DONE:
    dec BLIT_ROWS
    beq MAP_COPY_BLOCK_DONE
    lda #$21
    sec
    sbc ZTMP_30
    jsr PTR_SRC_ADD
    jmp COPY_BLOCK_ROW

MAP_COPY_BLOCK_DONE:
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
; Fetch the next byte from STREAM_PTR and post-increment - the shared "read
; one compressed byte" primitive behind UNPACK_CHARSET and UNPACK_MAP_DATA
; above (X is used as a forced zero-page-indexed-indirect index, ",x" with
; x=0, purely because that addressing mode is what's available - it isn't
; walking an array).
STREAM_NEXT_BYTE:
    ldx #$00
    lda (STREAM_PTR,x)
    inc STREAM_PTR
    bne STREAM_NEXT_NO_CARRY
    inc STREAM_PTR_HI

STREAM_NEXT_NO_CARRY:
    tax
    rts

; -----------------------------------------------------------------------
; Advance SRC_PTR by 1 (PTR_SRC_INC) or by A (PTR_SRC_ADD) - falling straight
; through from the "+1" entry into the "+A" entry with A already loaded is a
; common space-saving pattern in this file (one shared add/carry tail serves
; both the "+1" and "+A" callers).
PTR_SRC_INC:
    lda #$01

PTR_SRC_ADD:
    clc
    adc SRC_PTR
    sta SRC_PTR
    bcc PTR_SRC_DONE
    inc SRC_PTR_HI

PTR_SRC_DONE:
    rts

; -----------------------------------------------------------------------
; Advance DST_PTR by 1 or by A (same pattern as PTR_SRC_INC/ADD above).
PTR_DST_INC:
    lda #$01

PTR_DST_ADD:
    clc
    adc DST_PTR
    sta DST_PTR
    bcc PTR_DST_DONE
    inc DST_PTR_HI

PTR_DST_DONE:
    rts

; -----------------------------------------------------------------------
; Advance DST2_PTR by 1 or by A (same pattern again).
PTR_AUX_INC:
    lda #$01

PTR_AUX_ADD:
    clc
    adc DST2_PTR
    sta DST2_PTR
    bcc PTR_AUX_DONE
    inc DST2_PTR_HI

PTR_AUX_DONE:
    rts

; -----------------------------------------------------------------------
; Charset builder helper: roll the top 2 bits of A into ZTMP_09, 4 times
; (i.e. rotate a whole byte's worth, 2 bits at a time) - part of the
; ROM-charset-to-custom-multicolour-format repacking used by
; BUILD_CHARSET_INNER (Stage 2).
PACK_2BITS:
    ldx #$04

PACK_2BITS_LOOP:
    clc
    rol ZTMP_09
    asl a
    rol ZTMP_09
    dex
    bne PACK_2BITS_LOOP
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
; Charset builder: emit ZTMP_0C characters, each 8 bytes read from the
; stream and written both as-is (top half of a 16-byte character-pair slot)
; and mirrored (via MIRROR_BYTE); if ZTMP_0D (the flag byte passed in A) is
; nonzero, the mirrored bytes are also stashed on the stack and written a
; second time into the FOLLOWING character slot - building two related
; characters (a shape and its mirror image) from one 8-byte source.
BUILD_CHAR_PAIR:
    sta ZTMP_0D

BUILD_CHAR_PAIR_OUTER:
    lda #$08
    sta ZTMP_0B

BUILD_CHAR_PAIR_ROW:
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
    bne BUILD_CHAR_PAIR_KEEP
    pla
    pla                 ; ZTMP_0D=0 -> discard the stashed bytes, don't
                        ;   build the second character

BUILD_CHAR_PAIR_KEEP:
    dec ZTMP_0B
    bne BUILD_CHAR_PAIR_ROW
    lda #$08
    sta ZTMP_0B
    jsr PTR_DST_ADD
    lda ZTMP_0D
    beq BUILD_CHAR_PAIR_NEXT

; Pop the stashed bytes back off (LIFO order) into the second character slot.
BUILD_CHAR_PAIR_TWIN:
    ldy #$08
    pla
    sta (DST_PTR),y
    ldy #$00
    pla
    sta (DST_PTR),y
    jsr PTR_DST_INC
    dec ZTMP_0B
    bne BUILD_CHAR_PAIR_TWIN
    lda #$08
    jsr PTR_DST_ADD

BUILD_CHAR_PAIR_NEXT:
    dec ZTMP_0C
    bne BUILD_CHAR_PAIR_OUTER
    rts

; -----------------------------------------------------------------------
; Horizontally mirror a multicolour byte (swap the four 2-bit pixels): shift
; each pair of bits out through the carry (ASL, stashed via PHP so the
; second ASL doesn't clobber it) and ROR them into ZTMP_0A from the other
; end - after 4 rounds the 4 pixel-pairs have been reversed end-to-end.
MIRROR_BYTE:
    ldx #$04

MIRROR_BYTE_LOOP:
    asl a
    php
    asl a
    ror ZTMP_0A
    plp
    ror ZTMP_0A
    dex
    bne MIRROR_BYTE_LOOP
    lda ZTMP_0A
    rts

; -----------------------------------------------------------------------
; memcpy: copy X*256 bytes from SRC_PTR to DST_PTR (page-aligned - the inner
; loop copies a full 256-byte page at a time by just letting Y wrap $FF->$00).
COPY_PAGES:
    sta SRC_PTR_HI
    sty DST_PTR_HI
    ldy #$00
    sty SRC_PTR
    sty DST_PTR

COPY_PAGES_LOOP:
    lda (SRC_PTR),y
    sta (DST_PTR),y
    iny
    bne COPY_PAGES_LOOP
    inc SRC_PTR_HI
    inc DST_PTR_HI
    dex
    bne COPY_PAGES_LOOP
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

FILL_PAGES_LOOP:
    sta (SRC_PTR),y
    iny
    bne FILL_PAGES_LOOP
    inc SRC_PTR_HI
    dex
    bne FILL_PAGES_LOOP
    rts

; -----------------------------------------------------------------------
; Busy-wait some frames using the IRQ COPY_BLOCK_FLAG / FRAME_SUBCTR.
DELAY_FRAMES:
    lda SCROLL_SPEED
    bne DELAY_WAIT_COPY_FLAG
    inc SCROLL_SPEED

DELAY_WAIT_COPY_FLAG:
    lda COPY_BLOCK_FLAG
    beq DELAY_WAIT_COPY_FLAG
    lda #$0C
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
DELAY_FRAMES_ALT:
    lda #$1A
    ldx #$01
    stx SCROLL_SPEED
    dex
    stx FRAME_SUBCTR

DELAY_WAIT_SUBCTR:
    cmp FRAME_SUBCTR
    bne DELAY_WAIT_SUBCTR
    stx SCROLL_SPEED
    rts

; -----------------------------------------------------------------------
; Scan the joystick/keys once per frame; return the first code seen.
POLL_INPUT_FRAME:
    ldy FRAME_FLAG
    dey

POLL_INPUT_LOOP:
    jsr SCAN_JOY_KEYS
    bne POLL_INPUT_DONE
    cpy FRAME_FLAG
    bne POLL_INPUT_LOOP

POLL_INPUT_DONE:
    rts

; -----------------------------------------------------------------------
; Blank the status panel (11 cells of blanks via PANEL_PUT_CHAR_PAIR).
CLEAR_PANEL:
    jsr CLEAR_PANEL_ALT

CLEAR_PANEL_FULL:
    ldx #$00
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
CLEAR_PANEL_ALT:
    ldx #$12
    ldy #$0B

CLEAR_PANEL_LOOP:
    lda #$40
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bne CLEAR_PANEL_LOOP
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
; Attract / road-reset helper CODE (not yet disassembled - same situation as
; the larger blocks noted in Stage 5) plus a $5Axx screen row-address table.
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
; This is the very first call in GAME_LOOP (Stage 2) - the whole game's pace
; is set by this "wait for the IRQ to tick FRAME_FLAG" spin-loop.
WAIT_FRAME_TIMER:
    lda FRAME_FLAG
    cmp #$02
    bcc WAIT_FRAME_TIMER
    lda #$00
    sta FRAME_FLAG
    inc FRAME_CTR
    lda TIMER_ENABLE
    beq COPY_SPRITE_REGS
    lda FRAME_CTR
    and #$03
    bne COPY_SPRITE_REGS   ; only 1 frame in 4 actually decrements the timer
    sed                 ; BCD subtraction (see the 6502 primer's BCD note)
    sec
    lda GAME_TIME_LO
    sbc #$01
    sta GAME_TIME_LO
    tax
    lda GAME_TIME_HI
    sbc #$00
    sta GAME_TIME_HI
    cld
    bne COPY_SPRITE_REGS
    txa
    bne COPY_SPRITE_REGS
    lda #$FF
    sta EXTRA_LIFE_AVAIL
    lda SCENE_ID
    cmp #$05
    bne COPY_SPRITE_REGS
    inc FLAG_FC

; -----------------------------------------------------------------------
; Push every staged sprite X/Y (SPR_X_SHADOW/SPR_Y_SHADOW) out to the real
; VIC hardware sprite registers ($D000-$D010), then copy the sprite-pointer
; shadow (SPRITE_PTRS) out to both play-buffer sprite-pointer areas
; ($7BF8/$7FF8) - the one place per frame where all the position/graphics
; work done elsewhere (OBJ_CALC_SCREEN_POS, PROCESS_OBJECTS, ...) actually
; reaches the screen.
COPY_SPRITE_REGS:
    ldy #$10

COPY_SPRITE_XY_LOOP:
    lda a:SPR_X_SHADOW,y
    sta VIC_SPR0X,y
    dey
    bpl COPY_SPRITE_XY_LOOP
    ldx #$07

COPY_SPRITE_PTR_LOOP:
    lda SPRITE_PTRS,x
    sta SPRPTR_7800,x
    sta SPRPTR_7C00,x
    dex
    bpl COPY_SPRITE_PTR_LOOP
    rts

; -----------------------------------------------------------------------
; Blit a multi-character object (car / weapons van / boat / smoke plume / the
; on-road text messages from ONROAD_MSG_TBL, e.g. "GAME OVER") into the
; scrolling $7800 screen buffer + colour RAM (never the ROM/road template),
; so blitted content becomes MAP tiles that scroll with the road. This is
; the single shared blitter behind everything documented in
; claude/Boat_River_Notes.md, Smoke_Weapon_Notes.md and
; Game_Over_Text_Notes.md - it doesn't know or care WHAT it's drawing, just
; where (BLIT_COL/BLIT_ROW), how big (BLIT_WIDTH/BLIT_ROWS), what colour
; (OBJ_COLOR, 0 = "don't touch colour RAM"), and where to read the tile
; bytes from (STREAM_PTR). The BLIT_FLAGS high-bit path (WIDEN_PLUME_ENTRY
; below) grows the shape wider each row - the smoke-plume expansion effect.
DRAW_OBJECT_TILES:
    ldx BLIT_ROWS
    bne CALC_BLIT_PTRS
    rts

; Convert BLIT_ROW/BLIT_COL into two real memory pointers: SCREEN_PTR (the
; $7800 buffer cell to write) and COLOR_PTR (the matching $D800 colour-RAM
; cell) - a chain of carried 8-bit adds building up what's really a bigger
; address calculation than the 6502 can do in one step. The precise carry
; bookkeeping (PHP/PLP pairs stashing intermediate carries) isn't unpacked
; further here; the net effect is "screen row address (from ROWADDR_LO/HI,
; the table built in BUILD_ROWADDR_LOOP) + column, offset into the
; currently-active scroll buffer (SCROLL_DST)". (???: exact per-step carry
; semantics not re-derived.)
CALC_BLIT_PTRS:
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
    bcs BLIT_COLOR_HI_OK
    dec COLOR_PTR_HI

BLIT_COLOR_HI_OK:
    clc
    adc BLIT_COL
    php
    bcc BLIT_COLOR_LO_OK
    inc COLOR_PTR_HI

BLIT_COLOR_LO_OK:
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

; Main copy loop: for BLIT_ROWS rows of BLIT_WIDTH tiles each, copy from
; STREAM_PTR into SCREEN_PTR (and, if OBJ_COLOR is nonzero, stamp OBJ_COLOR
; into COLOR_PTR too). While copying, also record which screen ROW each
; destination column landed on into ZVEC_MOVE,x - a small per-column
; "what row is object data at this column" lookup, presumably consulted
; elsewhere (collision detection against blitted objects?). (???)
BLIT_ROW_LOOP:
    ldy BLIT_WIDTH
    dey

BLIT_COL_LOOP:
    lda (STREAM_PTR),y
    sta (SCREEN_PTR),y
    lda OBJ_COLOR
    beq BLIT_COL_NEXT
    sta (COLOR_PTR),y
    cpx #$00
    beq BLIT_COL_NEXT
    lda BLIT_ROW
    sta ZVEC_MOVE,x

BLIT_COL_NEXT:
    inx
    dey
    bpl BLIT_COL_LOOP
    dec BLIT_ROWS
    beq BLIT_ROWS_DONE
    ldx #$00
    lda SCREEN_PTR
    clc
    adc #$28            ; advance to the next screen row (40 cols/row)
    bcc BLIT_NEXT_ROW_LO
    inc SCREEN_PTR_HI
    inc COLOR_PTR_HI

BLIT_NEXT_ROW_LO:
    sta SCREEN_PTR
    lda COLOR_PTR
    clc
    adc #$28
    sta COLOR_PTR
    lda STREAM_PTR
    clc
    adc BLIT_WIDTH      ; advance the source past this row's tiles
    bcc BLIT_STREAM_LO_OK
    inc STREAM_PTR_HI

BLIT_STREAM_LO_OK:
    sta STREAM_PTR
    bne BLIT_ROW_LOOP

; All rows copied: if BLIT_FLAGS has its top bit set (the smoke-plume
; expansion flag), fall into the widening pass below; otherwise done.
BLIT_ROWS_DONE:
    lda BLIT_FLAGS
    bmi WIDEN_PLUME_ENTRY

DRAW_OBJECT_TILES_DONE:
    rts

; Smoke-plume expansion: for BLIT_FLAGS-many more rows, widen the shape by 2
; tiles each row (BLIT_COL/BLIT_WIDTH shrink/grow accordingly) while reading
; from TWO alternating small source offsets (STREAM_PTR / STREAM_PTR2) -
; this is what turns a small fixed source shape into the triangular,
; growing smoke-plume trail documented in claude/Smoke_Weapon_Notes.md
; ("3 -> 5 -> 7 -> 9 tiles wide over successive rows").
WIDEN_PLUME_ENTRY:
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

WIDEN_ROW_LOOP:
    dec BLIT_ROWS
    beq DRAW_OBJECT_TILES_DONE
    clc
    lda SCREEN_PTR
    adc #$27
    sta SCREEN_PTR
    bcc WIDEN_COLOR_ADD
    inc SCREEN_PTR_HI

WIDEN_COLOR_ADD:
    clc
    lda COLOR_PTR
    adc #$27
    sta COLOR_PTR
    bcc WIDEN_ROW_STEP
    inc COLOR_PTR_HI

WIDEN_ROW_STEP:
    dec BLIT_ROW
    lda BLIT_ROW
    cmp #$02
    bcs WIDEN_ROW_EXPAND

WIDEN_ROW_STOP:
    lda #$00
    sta BLIT_ROWS
    beq DRAW_OBJECT_TILES_DONE

; Grow the shape by 2 (one tile each side) and blit the two new edge tiles
; (from STREAM_PTR/STREAM_PTR2, the "left edge" and "right edge" sources)
; plus refresh the middle columns' ZVEC_MOVE row-tracking.
WIDEN_ROW_EXPAND:
    dec BLIT_COL
    inc BLIT_WIDTH
    inc BLIT_WIDTH
    ldx #$00
    ldy #$00
    beq WIDEN_EDGE_BLIT

WIDEN_EDGE_RIGHT:
    ldx #$02
    ldy BLIT_WIDTH

WIDEN_EDGE_BLIT:
    lda (STREAM_PTR,x)
    sta (SCREEN_PTR),y
    lda OBJ_COLOR
    beq WIDEN_EDGE_NEXT
    sta (COLOR_PTR),y
    tya
    clc
    adc BLIT_COL
    tax
    lda BLIT_ROW
    sta ZVEC_MOVE,x
    cpx #$23
    bcs WIDEN_ROW_STOP
    cpx #$05
    bcc WIDEN_ROW_STOP

WIDEN_EDGE_NEXT:
    dey
    bpl WIDEN_ROW_LOOP
    bmi WIDEN_EDGE_RIGHT

; -----------------------------------------------------------------------
; Per-frame weapon / special-vehicle update (weapons van, smoke/missile fx).
; Smoke: decrements the $F7 charge and blits the plume tiles ($AD/$10/$AE, edge
; variants $B0-$B6) from ROM ~$A538-$A567 (STREAM_PTR) into the $7800 road buffer
; via DRAW_OBJECT_TILES, colour $09; blit col/row from STATE_4DB9 / STATE_4DC1.
; Fully traced structure: skip entirely while a blit is still in progress
; (BLIT_ROWS nonzero, i.e. DRAW_OBJECT_TILES hasn't finished last frame's
; shape yet); otherwise either toggle the requested weapon (STATE_4D0C=0
; path) or fire whichever of smoke/missile is currently selected and has
; ammo (STATE_4D0C nonzero path).
UPDATE_WEAPONS:
    lda BLIT_ROWS
    bne WEAPONS_DONE
    lda STATE_4D0C
    bne WEAPON_FIRE_ENTRY
    sta BLIT_FLAGS
    lda WEAPON_STATE
    and #$10
    beq WEAPONS_DONE
    lda WEAPON_STATE
    and #$0F
    eor #$03            ; toggle between weapon slots (exact encoding of
    sta WEAPON_STATE     ;   WEAPON_STATE's low nibble not independently
                        ;   re-derived here)

WEAPONS_DONE:
    rts

; Decide which weapon to actually fire: WEAPON_STATE==$11 or out-of-missiles
; -> smoke; WEAPON_STATE>$11 or out-of-smoke -> missile. If both are
; available, flip WEAPON_STATE's request bit and re-check (so this can
; alternate between the two if both are requested).
WEAPON_FIRE_ENTRY:
    lda WEAPON_STATE

WEAPON_FIRE_CHECK:
    cmp #$11
    beq FIRE_SMOKE
    bcs FIRE_MISSILE
    lda MISSILE_CNT
    beq FIRE_SMOKE
    lda SMOKE_CNT
    beq FIRE_MISSILE
    lda WEAPON_STATE
    ora #$10
    sta WEAPON_STATE
    bne WEAPON_FIRE_CHECK   ; (unconditional - ORA of a nonzero bit is nonzero)

FIRE_SMOKE:
    lda SMOKE_CNT
    beq WEAPONS_DONE     ; out of smoke -> nothing to fire
    ldy #$12
    jsr SOUND_REQ_V0     ; play the smoke sound effect
    dec SMOKE_CNT
    lda #$08
    sta BLIT_FLAGS       ; 8 more widening rows (the smoke-plume expansion,
                        ;   see WIDEN_PLUME_ENTRY in DRAW_OBJECT_TILES)
    ldx #$FD
    ldy #$00
    beq WEAPON_FX_COMMON    ; (unconditional)

FIRE_MISSILE:
    lda MISSILE_CNT
    beq WEAPONS_DONE     ; out of missiles -> nothing to fire
    ldy #$14
    jsr SOUND_REQ_V0     ; play the missile sound effect
    dec MISSILE_CNT
    inc BLIT_FLAGS       ; cycle an animation-frame counter 1-4...
    lda BLIT_FLAGS
    cmp #$05
    bcc MISSILE_FRAME_OK
    lda #$04

MISSILE_FRAME_OK:
    ora #$80            ; ...with the widen flag set too (missiles get a
    sta BLIT_FLAGS        ;   small trail effect, same mechanism as smoke)
    lda #$09
    ldx #$15
    ldy #$08

; Shared tail for both weapons: search up to 8 entries in the SPR_MATCH_A/
; B/C tables for one matching the current OBJ_TBL69/71/79 values (candidate:
; identifying which weapons-icon graphic is currently on-screen, to decide
; whether to override the blit colour below) - the precise role of
; OBJ_TBL69/71/79 here isn't confirmed. (???)
WEAPON_FX_COMMON:
    sta OBJ_COLOR
    stx ZTMP_08
    ldx #$08

FIND_MATCH_LOOP:
    clc
    lda ZTMP_08
    adc #$03            ; ZTMP_08 walks forward 3 bytes per try - becomes
    sta ZTMP_08           ;   the eventual STREAM_PTR offset below
    lda SPR_MATCH_A,y
    cmp OBJ_TBL69
    bne FIND_MATCH_NEXT
    lda SPR_MATCH_B,y
    cmp OBJ_TBL79
    bne FIND_MATCH_NEXT
    lda SPR_MATCH_C,y
    cmp OBJ_TBL71
    beq MATCH_FOUND

FIND_MATCH_NEXT:
    iny
    dex
    bne FIND_MATCH_LOOP
    rts                 ; no match in 8 tries -> give up, nothing blitted

; A match was found "early" (X still >=4, i.e. within the first few tries)
; keeps the colour set above; a "late" match (X<4) overrides to light blue.
MATCH_FOUND:
    cpx #$04
    bcs SET_BLIT_SOURCE
    lda #$0E
    sta OBJ_COLOR

; Point STREAM_PTR at the matched tile-triple in ROM ($A538 + the offset
; accumulated in ZTMP_08 - confirms the header's "$A538-$A567" smoke/effect
; source range), then set up a single blit row at the object's current
; position (STATE_4DB9/STATE_4DC1) for DRAW_OBJECT_TILES to pick up.
SET_BLIT_SOURCE:
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
; Two independent trigger mechanisms feed into the same blit tail
; (COMMON_FX_BLIT below): the traced RNG-gated random spawn on
; ROAD_FEATURE==$14 (see claude/Boat_River_Notes.md - the repeating water-
; loop's random enemy-boat spawn) and a second, segment-id-gated path
; (SEGMENT_FX_TRIGGER) for segments $1D/$1E specifically (the level's
; closing segments, per claude/Road_Map_Decode.md's decoded graph) that
; pulls its parameters from the FX_PARAM_E9-EC tables instead of rolling
; randomly.
UPDATE_HAZARDS:
    jsr DRAW_OBJECT_TILES
    ldx #$05

; Four independent effect timers (FX_TIMER0-3) count down in parallel; the
; FIRST one still running (checked 3,2,1,0) is decremented and its expiry
; jumps to SEGMENT_FX_TRIGGER below - i.e. only one timer's countdown
; matters per frame, checked in priority order. These are the same
; FX_TIMER1/2/3 armed conditionally in UPDATE_SCENE_SELECT near segments
; $0F/$1B (Stage 6, earlier) - this is where those armed timers actually
; DO something once they expire, supporting the "road-sign/effect arming"
; hypothesis noted there.
    lda FX_TIMER3
    bne DEC_TIMER3
    dex
    lda FX_TIMER2
    bne DEC_TIMER2
    dex
    lda FX_TIMER1
    bne DEC_TIMER1
    dex
    lda FX_TIMER0
    beq SPAWN_CHECK_ENTRY
    dec FX_TIMER0
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
DEC_TIMER1:
    dec FX_TIMER1
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
DEC_TIMER2:
    dec FX_TIMER2
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
DEC_TIMER3:
    dec FX_TIMER3
    jmp SEGMENT_FX_FIRE  ; a timer is still running - re-load this effect's
                        ;   params (from FX_PARAM_E9-EB,x) and redraw it
                        ;   every frame while its timer counts down

; No timer needs decrementing this frame: if an effect is still mid-blit
; (FX_COUNT nonzero), just continue it. Otherwise check the two trigger
; conditions: ROAD_FEATURE==$14 (random spawn, RANDOM_SPAWN_ROLL below), or
; being on segment $1D/$1E (SEGMENT_FX_TRIGGER, further down past the data
; tables).
SPAWN_CHECK_ENTRY:
    lda FX_COUNT
    bne COMMON_FX_BLIT
    lda ROAD_FEATURE
    cmp #$14
    beq RANDOM_SPAWN_ROLL
    lda SEG_REPEAT
    dex
    ldy ROAD_SEG_IDX
    cpy #$1D
    bne CHECK_SEG_1E
    jmp SEGMENT_FX_TRIGGER

CHECK_SEG_1E:
    dex
    cpy #$1E
    bne SPAWN_CHECK_DONE
    jmp SEGMENT_FX_TRIGGER_B

SPAWN_CHECK_DONE:
    rts

; The traced random-spawn roll from claude/Boat_River_Notes.md: ~2.3% chance
; (RNG_NEXT >= $FA) to arm a spawn; if it fires, a second roll picks between
; two small tile-blit shapes ($A5BB or $A598) with a randomised width
; (FX_LEN).
RANDOM_SPAWN_ROLL:
    jsr RNG_NEXT
    cmp #$FA
    bcc SPAWN_CHECK_DONE   ; ~97.7% of the time: nothing
    jsr RNG_NEXT
    pha
    cmp #$7F
    lda #$09
    ldx #$A5
    ldy #$BB
    bcc RANDOM_SPAWN_SET
    lda #$07
    ldx #$A5
    ldy #$98

RANDOM_SPAWN_SET:
    sta FX_COUNT
    stx FX_SRC_HI
    sty FX_SRC
    pla
    and #$0E
    adc #$0A
    sta FX_LEN
    lda #$05
    sta ZTMP_30

; Shared blit tail for BOTH trigger paths (random spawn and the segment-$1D/
; $1E path below, which jumps here too): position and draw one row via
; DRAW_OBJECT_TILES from whatever FX_SRC/FX_LEN/ZTMP_30 currently hold.
COMMON_FX_BLIT:
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
    bcc FX_SRC_HI_OK
    inc FX_SRC_HI

FX_SRC_HI_OK:
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
; -----------------------------------------------------------------------
; ONROAD_MSG_TBL: on-road/status message strings, drawn by DRAW_OBJECT_TILES
; as blitted playfield tiles (NOT sprites/panel). Each letter is a 2-cell
; multicolour font-glyph PAIR from charset $7000: letter L -> ($CC+2L,$CD+2L),
; so A=$CC/$CD, G=$D8/$D9, O=$E8/$E9, R=$EE/$EF ... Z=$FE/$FF; $00 separates
; words. 'GAME'($A700) over 'OVER'($A6F8) is the game-over text on the road.
ONROAD_MSG_TBL:
    .byte $E0,$E1,$D4,$D5,$FC,$FD    ; "KEY"
    .byte $00    ; (word separator)
    .byte $E8,$E9,$EE,$EF    ; "OR"
    .byte $00    ; (word separator)
    .byte $DE,$DF,$E8,$E9,$FC,$FD    ; "JOY"
    .byte $E8,$E9,$F6,$F7,$D4,$D5,$EE,$EF    ; "OVER"  <- GAME OVER, screen row 11
    .byte $D8,$D9,$CC,$CD,$E4,$E5,$D4,$D5    ; "GAME"  <- GAME OVER, screen row 10
    .byte $E8,$E9,$E6,$E7    ; "ON"
    .byte $00,$00    ; (word separator)
    .byte $E2,$E3,$D4,$D5,$D6,$D7,$F2,$F3    ; "LEFT"
    .byte $00    ; (word separator)
    .byte $D2,$D3,$D4,$D5,$F2,$F3,$E8,$E9,$F4,$F5,$EE,$EF    ; "DETOUR"
    .byte $00,$00,$00,$00,$00    ; (word separator)
    .byte $E8,$E9,$F4,$F5,$F2,$F3    ; "OUT"
    .byte $00,$00,$00,$00,$00    ; (word separator)
    .byte $CE,$CF,$EE,$EF,$DC,$DD,$D2,$D3,$D8,$D9,$D4,$D5    ; "BRIDGE"
    .byte $00    ; (word separator)
    .byte $CC,$CD,$DA,$DB,$D4,$D5,$CC,$CD,$D2,$D3    ; "AHEAD"
    .byte $EE,$EF,$E8,$E9,$CC,$CD,$D2,$D3,$F0,$F1    ; "ROADS"
    .byte $00,$00    ; (word separator)
    .byte $DC,$DD,$D0,$D1,$FC,$FD    ; "ICY"
    .byte $00,$00    ; (word separator)
    .byte $E6,$86,$F8,$08,$40,$40,$A6,$A6    ; FX_PARAM_E9.. (effect params)
    .byte $A6,$A7,$A7,$A7,$12,$20,$08,$0E,$0A,$0A,$01,$03,$02,$04,$03,$03
    .byte $0B,$04,$10,$0D,$07,$17

; Gate check for segment $1D: only fires when SEG_REPEAT (still in A from
; the jump-in site above) is exactly $0D - a specific row within the
; segment, not the whole segment.
SEGMENT_FX_TRIGGER:
    cmp #$0D
    beq SEGMENT_FX_FIRE

SEGMENT_FX_SKIP:
    rts

; Gate check for segment $1E: fires only when SEG_REPEAT == $0F.
SEGMENT_FX_TRIGGER_B:
    cmp #$0F
    bne SEGMENT_FX_SKIP

; Load this effect's parameters from the FX_PARAM_E9/EA/30/EC/EB tables
; (indexed by X - which of the 4 FX_TIMERs expired, from UPDATE_HAZARDS
; above) and draw via the same COMMON_FX_BLIT tail the random-spawn path uses.
SEGMENT_FX_FIRE:
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
    jmp COMMON_FX_BLIT
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
; POINTS_TBL_LO/HI: interleaved BCD (lo,hi) point-value pairs, read by
; ADD_SCORE below (indexed by y=2*event, i.e. 2 bytes per entry). Confirmed
; against the official manual (claude/Enemy_Agents_Manual_Reference.md) -
; every value matches exactly: entry 0=0 (unused - note POINTS_TBL_LO's very
; first byte, $A89D, is the preceding BRK instruction's own $00 opcode byte,
; reused as data), 1=15 (water travel, pts/quarter-screen), 2=25 (road
; travel), 3=150 (Road Lord/Switch Blade/Barrel Dumper - a shared "kill
; tier", not one entry per enemy), 4=500 (Enforcer/Doctor Torpedo), 5=700
; (The Copter), 6=1500 (boathouse land<->water transition). Whatever queues
; SCORE_EVENT with these indices (not yet located) must map OBJ_TYPE down to
; one of these 3 kill tiers on enemy destruction.
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
    ldx #$E0            ; SCORE_LO's address - see the shared-entry note below
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
; -----------------------------------------------------------------------
; Render the BCD score digits into the status-panel screen rows, reading
; from a small zero-page pointer (SRC_PTR/SRC_PTR_HI) that's deliberately
; set to a tiny value (not a real 16-bit address) so that "(SRC_PTR),y"
; ends up reading directly from zero page address SRC_PTR+y - a compact way
; to walk 3 (or 4) consecutive zero-page bytes with one indirect-indexed
; addressing mode instead of several absolute-addressed instructions.
;
; TWO different entry points share this one routine:
;  - DRAW_SCORE itself (SRC_PTR=$0002=HISCORE_LO): draws the HIGH score.
;  - The fall-through from ADD_SCORE just above (SRC_PTR=$00E0=SCORE_LO,
;    via the BIT-skip trick - ADD_SCORE's "ldx #$E0" survives into here
;    because the skip-2 jumps straight past DRAW_SCORE's own "ldx #$02"):
;    draws the CURRENT score instead. One shared digit-renderer, two
;    different score buffers, selected by how you enter it.
DRAW_SCORE:
    ldx #$02
    stx SRC_PTR
    ldx #$00
    stx SRC_PTR_HI
    lda #$F0            ; ZTMP_08 = a nibble mask, starting at the high
    sta ZTMP_08           ;   nibble of the most-significant byte
    ldy #$02
    lda SCORE_OVFL
    bne DIGIT_SCAN_ENTRY  ; SCORE_OVFL nonzero -> there's a 4th ("millions")
    iny                    ;   byte to consider too, so start one further out

; Skip leading-zero DIGITS (not just bytes): walk from the most significant
; nibble down, checking "byte AND mask"; while it's still zero, blank that
; digit position (inx inx, skip 2 panel cells) and flip the mask between
; $F0/$0F (i.e. move to the other nibble of the same byte) via EOR #$FF,
; only moving to the PREVIOUS byte (dey) once both its nibbles were checked.
DIGIT_SKIP_LOOP:
    dey

DIGIT_SKIP_CHECK:
    lda (SRC_PTR),y
    and ZTMP_08
    bne DIGIT_SCAN_ENTRY   ; found the first nonzero nibble -> start drawing
    inx
    inx
    lda ZTMP_08
    eor #$FF
    sta ZTMP_08
    bmi DIGIT_SKIP_LOOP    ; mask is back to $F0 -> that byte's done, move on
    cpy #$00
    bne DIGIT_SKIP_CHECK

; Draw every remaining digit (both nibbles of each remaining byte, from
; here down to the last byte) - entering at DIGIT_LOW_NIBBLE directly (via
; LSR/BCS) if the mask says only the low nibble of the CURRENT byte still
; needs drawing (i.e. we just arrived here mid-byte from the skip loop).
DIGIT_SCAN_ENTRY:
    lsr ZTMP_08
    bcs DIGIT_LOW_NIBBLE

DIGIT_HIGH_NIBBLE:
    lda (SRC_PTR),y
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PANEL_PUT_DIGIT

DIGIT_LOW_NIBBLE:
    lda (SRC_PTR),y
    and #$0F
    jsr PANEL_PUT_DIGIT
    dey
    bpl DIGIT_HIGH_NIBBLE
    rts

; -----------------------------------------------------------------------
; PANEL_PUT_DIGIT: convert a 0-9 digit value to its double-height panel
; character pair ($60+2N/$61+2N, see claude/Snapshot_Analysis.md) and fall
; into PANEL_PUT_CHAR_PAIR, which writes any char code + its +1 neighbour
; into both panel screen rows (PANEL_SCR0/PANEL_SCR1) at column X, advancing
; X by 2 - the shared "write one double-wide panel cell" primitive used
; throughout this whole section (score digits, icons, timer, lives).
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

; Timer entry point: point SRC_PTR at GAME_TIME_LO/HI ($4D01) - a REAL 16-bit
; pointer this time (SRC_PTR_HI isn't zeroed here, unlike DRAW_SCORE's zero-
; page trick) - then jump straight into DIGIT_LOW_NIBBLE to draw just
; GAME_TIME_HI's low nibble (its high nibble is always 0 - the timer only
; ever needs 3 decimal digits total for a 0-999 range), then fall through
; (dey/bpl) to draw both nibbles of GAME_TIME_LO - giving exactly 3 digits.
DRAW_TIMER:
    ldy #$01
    sty SRC_PTR
    ldy #$4D
    sty SRC_PTR_HI
    ldy #$01
    ldx #$14            ; panel column $14 (centre)
    bne DIGIT_LOW_NIBBLE   ; (unconditional - Y was just set to 1)
; -----------------------------------------------------------------------
; PANEL_ICON_TBL: status-panel indicator icon char-codes (weapon/fuel).
    .byte $80,$82,$84,$86

; -----------------------------------------------------------------------
; Draw the panel indicators: weapon/fuel icons, then EITHER the game timer
; (DRAW_TIMER, when EXTRA_LIFE_AVAIL=$00) OR the lives markers (when
; EXTRA_LIFE_AVAIL=$FF, i.e. the timer has expired) - which is why the timer
; vanishes at 0 (see the header's "timer gone" notes).
DRAW_STATUS_PANEL:
    ldx #$1C
    stx PANEL_X
    ldy #$00

; Draw up to 4 ammo/weapon icons (GUN_HEAT/MISSILE_CNT/SMOKE_CNT and a 4th
; slot): blank ($40) if that ammo counter is 0, otherwise the matching
; PANEL_ICON_TBL icon.
DRAW_ICONS_LOOP:
    lda a:GUN_HEAT,y
    beq ICON_BLANK
    lda PANEL_ICON_TBL,y
    bne ICON_DRAW

ICON_BLANK:
    lda #$40

ICON_DRAW:
    jsr PANEL_PUT_CHAR_PAIR
    inx
    iny
    cpy #$04
    bne DRAW_ICONS_LOOP
    lda EXTRA_LIFE_AVAIL
    beq DRAW_TIMER
    ldx #$0E
    lda #$06
    sta ZTMP_08         ; draw up to 6 life-icon cells
    ldy LIVES
    bmi PANEL_DONE       ; LIVES=$FF (game-over sentinel) -> draw nothing

; Draw one filled ($88) life icon per remaining life, then blanks ($40) for
; the rest of the 6 cells.
DRAW_LIVES_LOOP:
    lda #$88
    dey
    bpl LIVES_ICON_DRAW
    lda #$40

LIVES_ICON_DRAW:
    jsr PANEL_PUT_CHAR_PAIR
    dec ZTMP_08
    bne DRAW_LIVES_LOOP

PANEL_DONE:
    rts

; -----------------------------------------------------------------------
; Scan the CIA1 keyboard/joystick matrix and return a key/joystick code in
; A. This uses the classic C64 matrix-scan technique: CIA1_PRA drives one
; "column" line low at a time (via ROL, walking a single 0 bit through the
; port each pass - the same repeat-N-times-without-a-counter idiom seen
; elsewhere, here also doubling as the column-select signal itself) while
; CIA1_PRB reads back which "row" lines respond - a pressed key/direction
; pulls its row line low, showing up as a 0 bit once inverted (EOR #$FF).
;
; This first loop only checks the joystick port's 5 lines (up/down/left/
; right/fire, reached by stepping X down by 8 each pass - not a real
; keyboard column scan yet, just probing the joystick-shaped subset of the
; matrix); if nothing shows up there, KEYBOARD_SCAN_LOOP below does a fuller
; keyboard-column scan.
SCAN_JOY_KEYS:
    lda #$FF
    sta CIA1_DDRA       ; CIA1 port A = all outputs (so we can drive columns)
    lda #$FE
    sta CIA1_PRA        ; start with only bit 0 low (select first column)
    lda #$3F
    sec

JOY_PROBE_LOOP:
    sbc #$08
    tax
    lda CIA1_PRB
    rol CIA1_PRA        ; walk the driven-low bit to the next column
    eor #$FF
    bne KEYBOARD_SCAN_LOOP   ; a row line responded -> go decode which one

JOY_PROBE_NEXT:
    txa
    bcs JOY_PROBE_LOOP
    bcc NOTHING_PRESSED

; A row responded: temporarily switch CIA1_PRA to read-all-lines mode ($FF)
; to check whether this is a genuine single-line response or PRB is
; floating/all-lines-active (some CIA matrix wiring needs this extra check
; to disambiguate a real keypress from crosstalk); if PRB still reads all
; zero-bits-inverted-to-zero (beq), treat it as confirmed and decode below,
; otherwise restore state and keep scanning.
KEYBOARD_SCAN_LOOP:
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
    beq KEY_CONFIRMED
    pla
    sta CIA1_PRA
    pla
    tax
    pla
    plp
    jmp JOY_PROBE_NEXT

; Confirmed: restore saved state and count which BIT position in A
; responded (INX/ROL loop) - that bit index becomes the returned key code.
KEY_CONFIRMED:
    pla
    sta CIA1_PRA
    pla
    tax
    pla
    plp

COUNT_KEY_BIT:
    inx
    rol a
    bcc COUNT_KEY_BIT

SCAN_DONE:
    lda #$00
    sta CIA1_DDRA       ; restore CIA1 port A to input (release the matrix)
    txa
    rts

NOTHING_PRESSED:
    ldx #$00
    beq SCAN_DONE       ; (always taken - X was just set to 0) so everything
                        ;   below is unreachable from here; it's a SEPARATE
                        ;   entry point, reached only via VEC_STATE (see
                        ;   SET_STATE_VEC, Stage 2: this is the $A9F6 handler
                        ;   selected for 2-player games)
STATE_2P_ENTRY:
    lda #$00
    ldx #$03

; Decoded joystick/key reader: clear the 4-entry JOY_STATE array, take one
; raw scan (SCAN_JOY_KEYS above), then look the result up in KEYCODE_TBL -
; on a match, KEYVAL_TBL/KEYIDX_TBL say what value to store into which
; JOY_STATE slot (translating a raw matrix code into this game's own
; decoded joystick-direction/button representation).
DECODE_JOY_LOOP:
    sta JOY_STATE,x
    dex
    bpl DECODE_JOY_LOOP
    jsr SCAN_JOY_KEYS
    ldx #$06

MATCH_KEYCODE_LOOP:
    dex
    bmi DECODE_JOY_DONE
    cmp KEYCODE_TBL,x
    bne MATCH_KEYCODE_LOOP
    lda KEYVAL_TBL,x
    ldy KEYIDX_TBL,x
    sta JOY_STATE,y

DECODE_JOY_DONE:
    rts
; -----------------------------------------------------------------------
; KEYCODE_TBL / KEYIDX_TBL / KEYVAL_TBL: console-key scan decode tables.
    .byte $1E,$1A,$15,$1D,$35,$33,$00,$00,$01,$01,$02,$03,$01,$FF,$01,$FF
    .byte $FF,$FF

; -----------------------------------------------------------------------
; Read the pause/mute console keys, debounce, toggle freeze/mute. Watches 3
; keys (PAUSEKEY_TBL) in parallel, each with its own KEY_LAST/KEY_DEBOUNCE/
; KEY_TOGGLE slot; only KEY_TOGGLE[0] (the pause key) is actually acted on
; here (freezing SCROLL_SPEED and silencing sound) - the other two toggles
; are presumably read elsewhere (candidate: mute-only, not confirmed). (???)
HANDLE_PAUSE_KEYS:
    lda SCROLL_SPEED
    pha                 ; stash the current scroll speed to restore on resume

PAUSE_POLL_LOOP:
    jsr SCAN_JOY_KEYS
    ldx #$02            ; check all 3 watched keys each pass

; Debounced toggle: if this frame's scanned code matches PAUSEKEY_TBL[x] AND
; differs from what it was last frame (a fresh press, not still-held), start
; (or continue) a 10-frame debounce countdown; only once that countdown
; reaches 0 does KEY_TOGGLE[x] actually flip. This is the standard "ignore
; key-repeat, act once per distinct press" pattern.
PAUSE_KEY_CHECK:
    tay
    cmp PAUSEKEY_TBL,x
    bne PAUSE_KEY_MISS
    cmp KEY_LAST,x
    beq PAUSE_DEBOUNCE_RESET
    dec KEY_DEBOUNCE,x
    bne PAUSE_KEY_NEXT
    lda KEY_TOGGLE,x
    eor #$FF
    sta KEY_TOGGLE,x

PAUSE_KEY_MISS:
    sty KEY_LAST,x

PAUSE_DEBOUNCE_RESET:
    ldy #$0A
    sty KEY_DEBOUNCE,x

PAUSE_KEY_NEXT:
    dex
    bpl PAUSE_KEY_CHECK
    lda KEY_TOGGLE
    beq PAUSE_RESUME
    lda #$00
    sta SCROLL_SPEED    ; paused: freeze the road scroll...
    jsr SOUND_SILENCE    ; ...and mute all sound
    jmp PAUSE_POLL_LOOP   ; keep polling every frame until un-paused

PAUSE_RESUME:
    pla
    sta SCROLL_SPEED    ; not paused (any more): restore the saved scroll speed
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

CLEAR_SID_LOOP:
    sta SID_V1_FLO,x
    dex
    bpl CLEAR_SID_LOOP
    lda #$0F
    sta SID_VOL
    rts

; -----------------------------------------------------------------------
; Request sound sequence Y (an index into SND_SEQPTR_LO/HI, the per-effect
; sequence-pointer table) on a SID voice. Four entry points, one per voice
; (0, "0B", 1, 2) - but only SOUND_REQ_V0 actually checks whether its voice
; is busy first (SND_SEQ nonzero -> already playing something, bail via
; RTS). SOUND_REQ_V0B/V1/V2 jump straight into the shared queue code
; (QUEUE_SOUND_REQ) unconditionally.
;
; Worth calling out: the "lda SND_SEQ_V1 / bne ..." and "lda SND_SEQ_V2 /
; bne ..." lines below are UNREACHABLE dead code - the branch just above
; each one (BEQ with A just loaded as an immediate #$00, or BNE with A as a
; nonzero immediate) is unconditional, so control always jumps past them
; into QUEUE_SOUND_REQ. This looks like a leftover from an earlier version
; of the code where every voice had its own busy-check (like SOUND_REQ_V0
; still does) before being simplified - the dead bytes were left in place
; rather than removed. Confirmed by direct reading, not a guess.
SOUND_REQ_V0:
    lda SND_SEQ
    bne SOUND_REQ_DONE

SOUND_REQ_V0B:
    lda #$00
    beq QUEUE_SOUND_REQ  ; (unconditional - A is always 0 here)
    lda SND_SEQ_V1        ; unreachable (see note above)
    bne SOUND_REQ_DONE

SOUND_REQ_V1:
    lda #$01
    bne QUEUE_SOUND_REQ  ; (unconditional - A is always 1, nonzero)
    lda SND_SEQ_V2        ; unreachable (see note above)
    bne SOUND_REQ_DONE

SOUND_REQ_V2:
    lda #$02            ; falls straight into QUEUE_SOUND_REQ below

; Reset the chosen voice's playback state (SND_SEQ/SND_POS/SND_SLIDE_HI=0,
; SND_DUR=1) and load its new sequence pointer from SND_SEQPTR_LO/HI,y.
; Storing the sequence's HIGH byte back into SND_SEQ,x (after having just
; zeroed it) is doing double duty: it's both part of the pointer AND the
; nonzero "this voice is busy" flag SOUND_REQ_V0 checks above (a real ROM/
; RAM high byte is never 0).
QUEUE_SOUND_REQ:
    stx ZTMP_08         ; save caller's X (not the voice index - see below)
    tax                 ; X = voice index (0/1/2, from A above)
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
    ldx ZTMP_08         ; restore caller's X

SOUND_REQ_DONE:
    rts

; -----------------------------------------------------------------------
; Gate off all three SID voices (silences sound immediately) and clear all
; 3 voices' SND_SEQ "busy" flags, so any in-flight SOUND_REQ_* is abandoned.
SOUND_SILENCE:
    txa
    pha
    lda #$00
    sta SID_V1_CTRL
    sta SID_V2_CTRL
    sta SID_V3_CTRL
    lda #$00
    ldx #$02

CLEAR_VOICE_SEQ_LOOP:
    sta SND_SEQ,x
    dex
    bpl CLEAR_VOICE_SEQ_LOOP
    pla
    tax
    rts

; -----------------------------------------------------------------------
; Per-frame SID player (called once per frame from the IRQ, via
; IRQ_MAIN_TAIL - Stage 3). Drives all 3 SID voices independently, each
; voice running its own little bytecode "program": a byte stream of notes,
; durations and commands (jumps/loops/etc, dispatched through
; SNDCMD_VEC_LO/HI below) that MUSIC_START_THEME and SOUND_REQ_* point a
; voice at. This is the least-explored area of the file - the overall
; sequencer structure below is traced with reasonable confidence, but some
; of the frequency-slide (portamento) arithmetic is marked (???).
MUSIC_DRIVER:
    lda #$0E
    sta SND_REGOFS      ; SID register offset: $0E/$07/$00 = voice 3/2/1's
                        ;   7-register block ($D400+SND_REGOFS)
    ldx #$02            ; voice index 2, 1, 0 (SND_* arrays are per-voice)

VOICE_LOOP:
    stx SND_VOICE
    ldy SND_POS,x
    lda SND_SEQ,x
    beq VOICE_ADVANCE   ; SND_SEQ=0 -> nothing queued on this voice, skip it
    sta SND_SEQ_PTR_HI  ; SND_SEQ,x doubles as the sequence pointer's high
                        ;   byte (see the note in QUEUE_SOUND_REQ above)
    lda SND_PTR0_LO,x
    sta SND_SEQ_PTR
    cpy #$00
    bne DUR_COUNTDOWN   ; position already advanced past the header -> skip
                        ;   the one-time envelope setup below

; Fresh sequence (position still 0): its first 3 bytes are an ADSR/control
; setup, written straight to this voice's SID registers (sustain/release,
; attack/decay, then control - order matches the SID_V1_SR/AD/CTRL
; equates), then the read position is set to 3, past this header.
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

; Count down this voice's note-duration timer; once it hits 0, the current
; note/command is finished and it's time to read the next one (PROCESS_STEP).
DUR_COUNTDOWN:
    dec SND_DUR,x
    beq PROCESS_STEP

; Move on to the next voice (register offset steps back by 7 per voice).
VOICE_ADVANCE:
    sty SND_POS,x
    lda SND_REGOFS
    sec
    sbc #$07
    sta SND_REGOFS
    dex
    bpl VOICE_LOOP
    rts

; Duration expired: if a frequency slide (portamento) is in progress
; (SND_SLIDE_HI nonzero), continue it (APPLY_SLIDE); otherwise read the
; next token from the sequence stream.
PROCESS_STEP:
    lda SND_SLIDE_HI,x
    beq READ_NEXT_TOKEN
    jmp APPLY_SLIDE

; A $00 token means "the next byte is a COMMAND index" (DISPATCH_COMMAND);
; any other value is itself a note to play (PLAY_NOTE).
READ_NEXT_TOKEN:
    lda (SND_SEQ_PTR),y
    iny
    cmp #$00
    beq DISPATCH_COMMAND
    jmp PLAY_NOTE

; Look up a command handler in SNDCMD_VEC_LO/HI (indexed by the command
; byte x2) and jump to it via the classic 6502 "push address-1, then RTS"
; indirect-jump trick - the handler runs and its own RTS returns to
; whatever called MUSIC_DRIVER, not back here (the handler is responsible
; for its own control flow, e.g. looping the sequence or continuing on).
DISPATCH_COMMAND:
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
; SNDCMD_VEC_LO/HI (the command-handler address table DISPATCH_COMMAND
; reads) plus the music command-handler CODE itself, stored as raw data -
; the same "only reached indirectly" situation as the blocks noted in
; Stage 5/9 (PROCESS_OBJECTS, MUSIC_START_THEME's data block). Candidate
; commands based on what a music sequencer typically needs: loop/repeat,
; jump to a different sequence, tempo/rate change - not individually
; decoded in this pass.
    .byte $29,$AB,$38,$AB,$7A,$AB,$A9,$00,$95,$55,$A8,$A6,$4C,$9D,$04,$D4
    .byte $A6,$4B,$4C,$F6,$AA,$B1,$50,$C8,$29,$1F,$0A,$AA,$BD,$BB,$BC,$85
    .byte $4D,$BD,$BC,$BC,$85,$4E,$20,$04,$AC,$A5,$4D,$95,$61,$A5,$4E,$95
    .byte $5E,$B1,$50,$C8,$29,$1F,$0A,$AA,$BD,$BB,$BC,$85,$4D,$BD,$BC,$BC
    .byte $A6,$4B,$95,$64,$A5,$4D,$95,$67,$B1,$50,$C8,$95,$6D,$B1,$50,$C8
    .byte $95,$6A,$95,$58,$4C,$F6,$AA,$B1,$50,$C8,$95,$52,$48,$B1,$50,$C8
    .byte $95,$55,$85,$51,$68,$85,$50,$A0,$00,$4C,$03,$AB

; Play a note: the byte just read packs a 6-bit note index (bits 0-5, look
; up its frequency in SND_FREQ_LO/HI_TBL and write it to the SID via
; SID_WRITE_FREQ) AND a 2-bit duration class in its TOP two bits (re-read
; via "dey/lda/iny" - stepping back to re-examine the SAME byte - then
; rotated down via 3x ROL). Duration class 0 means "read one more explicit
; duration byte from the stream"; classes 1-3 look up a preset duration
; from SND_DUR_TBL instead - short/common durations cost 0 extra bytes,
; unusual ones cost 1.
PLAY_NOTE:
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
    bne SET_DURATION
    lda (SND_SEQ_PTR),y
    iny

SET_DURATION:
    ldx SND_VOICE
    sta SND_DUR,x
    jmp VOICE_ADVANCE

; Continue an in-progress frequency slide (portamento): step SND_FREQ_LO,x
; by SND_SLIDE_LO,x each frame (the slide "rate", signed - SLIDE_DOWN below
; handles the negative-rate case), write the new frequency, and check
; against the SND_TGT_LO/HI target to know when the slide is complete.
; (???: SND_SLIDE_HI's exact role - both "is a slide active" flag, per
; PROCESS_STEP's check above, and part of the stepped value here - isn't
; fully disentangled.)
APPLY_SLIDE:
    clc
    lda SND_SLIDE_LO,x
    bmi SLIDE_DOWN
    adc SND_FREQ_LO,x
    sta SND_FREQ_LO,x
    sta SND_PTR_LO
    bcc SLIDE_UP_CHECK
    inc SND_SLIDE_HI,x

SLIDE_UP_CHECK:
    lda SND_SLIDE_HI,x
    sta SND_PTR_HI
    cmp SND_TGT_LO,x
    bcc SLIDE_CONTINUE
    lda SND_FREQ_LO,x
    cmp SND_TGT_HI,x
    bcs SLIDE_DONE

SLIDE_CONTINUE:
    jsr SID_WRITE_FREQ
    lda SND_RATE,x
    sta SND_DUR,x
    jmp VOICE_ADVANCE

SLIDE_DOWN:
    adc SND_FREQ_LO,x
    sta SND_FREQ_LO,x
    sta SND_PTR_LO
    bcs SLIDE_DOWN_CHECK
    dec SND_SLIDE_HI,x

SLIDE_DOWN_CHECK:
    lda SND_SLIDE_HI,x
    sta SND_PTR_HI
    lda SND_TGT_LO,x
    cmp SND_SLIDE_HI,x
    bcc SLIDE_CONTINUE
    lda SND_TGT_HI,x
    cmp SND_FREQ_LO,x
    bcc SLIDE_CONTINUE

; Slide finished: clear SND_SLIDE_HI (the "sliding" flag) and go read the
; next sequence token as normal.
SLIDE_DONE:
    lda #$00
    sta SND_SLIDE_HI,x
    jmp READ_NEXT_TOKEN

; -----------------------------------------------------------------------
; Write a 16-bit frequency (SND_PTR_LO/HI) to the SID voice selected by
; SND_VOICE/SND_REGOFS - the shared "actually talk to the SID chip" step
; used by both PLAY_NOTE and APPLY_SLIDE above. Y (the caller's sequence
; read position) is stashed in SND_TMP for the duration, since this
; routine needs Y itself as the SID register offset.
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
; ROAD_SEG_TBL: 32 x (main, branch) next-segment-id pairs - the road's
; segment graph, fully decoded (all 31 segments, row-by-row) in
; claude/Road_Map_Decode.md. Read by ADVANCE_ROAD_SEGMENT (Stage 6):
; ROAD_SEG_TBL[2*current] = main (steer left), [2*current+1] = branch
; (steer right, taken when SCENE_IDX >= $13).
ROAD_SEG_TBL:
    .byte $1D,$1D,$02,$03,$08,$05,$06,$04,$07,$07,$07,$07,$07,$07,$10,$10
    .byte $09,$0E,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$0D,$0F,$0F,$0F,$0F,$11,$11
    .byte $12,$0B,$12,$0B,$13,$13,$12,$14,$15,$17,$16,$16,$1A,$1A,$18,$18
    .byte $19,$19,$1A,$1A,$1B,$1B,$1C,$1C,$01,$01,$01,$1E,$01,$01,$01,$1D

; ROAD_PTR_LO_TBL / ROAD_PTR_HI_TBL: per-segment pointer into the
; feature-list bytes below (FEATURE_LISTS) - where each segment's row/
; feature stream starts. 31 entries (segments $00-$1E).
ROAD_PTR_LO_TBL:
    .byte $EE,$EF,$F2,$01,$11,$16,$1B,$1D,$20,$29,$2B,$2C,$2F,$30,$36,$39
    .byte $3C,$3D,$40,$42,$44,$54,$55,$56,$58,$59,$5A,$5F,$60,$62,$62
ROAD_PTR_HI_TBL:
    .byte $AC,$AC,$AC,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD
    .byte $AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD,$AD

; ROAD_LEN_TBL: per-segment row count (how many rows to read from its
; feature-list entry before advancing to the next segment).
ROAD_LEN_TBL:
    .byte $01,$03
    .byte $0F,$10,$05,$05,$02,$03,$09,$02,$01,$03,$01,$06,$03,$03,$01,$03
    .byte $02,$02,$10,$01,$01,$02,$01,$01,$05,$01,$02,$01,$01

; ROAD_COLIDX_TBL / ROAD_BORDER_TBL / ROAD_MC1_TBL / ROAD_MC2_TBL: per-
; segment palette. COLIDX combines with ROAD_PHASE (Stage 6,
; APPLY_SEGMENT_PALETTE) to pick a row into the BORDER/MC1/MC2 colour
; tables - this is what gives the bridge/water sections their distinct
; look (claude/Water_Bridge_Notes.md).
ROAD_COLIDX_TBL:
    .byte $00,$00,$00
    .byte $00,$00,$00,$00,$00,$00,$00,$04,$00,$04,$00,$00,$00,$04,$04,$00
    .byte $00,$00,$00,$04,$00,$04,$00,$00,$04,$00,$08,$08
ROAD_BORDER_TBL:
    .byte $0B,$0B,$0C,$0B
    .byte $0B,$0B,$0C,$0B,$00
ROAD_MC1_TBL:
    .byte $05,$07,$0F,$07,$0F,$0F,$0F,$0F,$08
ROAD_MC2_TBL:
    .byte $07,$08
    .byte $01,$08,$01,$01,$01,$01,$01

; FEATURE_LISTS ($ACEE-$AD62): the per-segment row/feature byte streams
; that ROAD_PTR_LO/HI_TBL point into - read backwards (dey-first) by
; READ_ROAD_ROW (Stage 6). Every segment's exact row-by-row feature
; sequence is fully decoded in claude/Road_Map_Decode.md's "Full segment
; row-by-row table" - not re-split here byte-by-byte since that
; cross-reference already gives the authoritative per-segment breakdown.
FEATURE_LISTS:
    .byte $11,$12,$09,$11,$12,$09,$08,$07,$04,$06,$05,$10,$0B,$0A,$12,$09
    .byte $08,$10,$0C,$12,$09,$08,$07,$04,$06,$05,$0B,$11,$08,$07,$04,$06
    .byte $05,$10,$0D,$07,$04,$06,$05,$0D,$07,$04,$06,$05,$0D,$10,$0C,$13
    .byte $11,$08,$12,$09,$11,$0A,$12,$09,$08,$10,$0C,$04,$0C,$02,$06,$05
    .byte $0F,$01,$07,$04,$06,$05,$06,$05,$06,$05,$0D,$13,$11,$08,$02,$02
    .byte $03,$02,$14,$0E,$15,$14,$12,$09,$08,$07,$04,$07,$04,$06,$05,$06
    .byte $05,$0B,$11,$08,$10,$0F,$0C,$01,$04,$0D,$02,$07,$12,$09,$11,$08
    .byte $10,$00,$0A,$12,$19

; OBJ_ADDR_LO/HI + OBJ_ROWREP_TBL/OBJ_SEGREP_TBL: the 16-entry ($00-$0F)
; road-graphics table fully decoded in claude/Road_Map_Decode.md and
; claude/Boat_River_Notes.md / Broken_Bridge_Notes.md - $01=bridge,
; $02=boat/water crossing, $0F=broken-bridge return-to-road, etc. Indexed
; by ROAD_FEATURE (READ_ROAD_ROW, Stage 6) to pick SCROLL_SRC + repeat
; counts for each row.
OBJ_ADDR_LO:
    .byte $80,$20,$C0,$60
    .byte $C0,$40,$C0,$40,$C0,$40,$C0,$40,$C0,$A0,$80,$40,$00,$00,$00,$00
    .byte $00,$00,$00,$00,$00,$70
OBJ_ADDR_HI:
    .byte $29,$2A,$2A,$2B,$2B,$2F,$32,$36,$39,$3B
    .byte $3D,$40,$41,$44,$47,$4A,$C0,$C2,$C3,$C4,$C8,$CC,$D0,$00,$00,$67
OBJ_ROWREP_TBL:
    .byte $05,$05,$05,$03,$1C,$1C,$1C,$1C,$0C,$14,$14,$0C,$17,$17,$16,$16
    .byte $10,$08,$08,$20,$20,$20,$01,$01,$01,$01
OBJ_SEGREP_TBL:
    .byte $14,$0F,$0A,$04,$01,$01
    .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$0A,$1E,$0A,$01,$0A,$01
    .byte $01,$01,$01,$1A

; -----------------------------------------------------------------------
; The bulk graphics and audio data through $BFFF (charsets, sprite shapes,
; screen layouts, SID music tables) continues below, emitted verbatim from
; the ROM - not individually catalogued in this annotation pass.
    .byte $36,$36,$01,$09,$37,$37,$39,$10,$02,$00,$80,$36
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
