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
ZTMP_0E = $0E
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
STATE_9B = $9B    ; per-slot countdown/state byte, used in move handlers (???)
FLAG_A1 = $A1    ; flag (???)
OBJ_TYPE = $A2    ; per-object type ($FF=empty); slot1=hero, =$03 in weapons van
HERO_STATE = $A3    ; hero state = OBJ_TYPE[1]; $FF normal, $03 in weapons van
SCENE_ID = $A8    ; high-level scene id (car/boat/...); $FF during van sequence
ANIM_STATE = $A9    ; sub-state / animation selector (???)
OBJ_POS_X = $AA    ; per-slot world/scroll X position, pre-delta (???, tentative -
                     ;   8-byte stride matches the object-slot arrays; swapped
                     ;   between slots by the move handlers below)
STEER_ACCUM = $B0    ; SPEEDCODE_IMAGE: steering accumulator, paired with
                     ;   STEER_SUM (???, mirrors SPEED_ACCUM/SPEED_SUM below)
OBJ_POS_Y = $B2    ; per-slot world/scroll Y position, paired with OBJ_POS_X (???)
SPEED_ACCUM = $B8    ; SPEEDCODE_IMAGE: speed accumulator - decremented by
                     ;   JOY_STATE (up), clamped to <=0, never observed
                     ;   positive (???: exact game-feel meaning not confirmed)
SPR_STAGE = $BA    ; staged hardware sprite coords
SPR_X_SHADOW = $CA    ; sprite X shadow (->$D000)
SPR_Y_SHADOW = $CB    ; sprite Y shadow
SPAWN_Y = $CD    ; object spawn y (= sprite1 Y shadow; van vertical pos)
STEER_SUM = $D6    ; SPEEDCODE_IMAGE: running sum feeding the steering
                    ;   snap-to-target index (paired with STEER_ACCUM) (???)
SPEED_SUM = $D7    ; SPEEDCODE_IMAGE: running sum feeding the SPEED_SET
                    ;   snap-to-target index (paired with SPEED_ACCUM) (???)
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
GUN_HEAT = $F6    ; machine-gun heat/cooldown gauge, decremented per shot at
                  ;   $8CE0-$8D05 when JOY1_FIRE_BTN is pressed (HERO_STATE=$07
                  ;   gate; exact recharge/reset mechanics not traced) - reset
                  ;   to 0 alongside MISSILE_CNT/SMOKE_CNT on a water crash
                  ;   (MOVE_BOAT_CRASH)
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
STATE_4D04 = $4D04    ; per-slot value set alongside a committed OBJ_TYPE
                      ;   change (hero/object move-handler block, Stage 5) -
                      ;   COMMIT_DIR_LEFT_PTR/RIGHT_PTR (the edge-spawn tail)
                      ;   both read it, add 3, and compare against $1E (30)
                      ;   to help decide the new spawn's type/column, and
                      ;   MOVE_HERO's SLOT1_SET_09 path sets it to $09
                      ;   directly - consistent with a "recent spawn/type-
                      ;   change activity" counter used to pace how often a
                      ;   slot can respawn, but the exact scale (frames?
                      ;   spawn attempts?) isn't confirmed (???)
STATE_4D05 = $4D05
NEXT_LIFE_SCORE = $4D06    ; next extra-life threshold
STATE_4D07 = $4D07
STATE_4D08 = $4D08
; JOY_STATE: 4-byte decoded-input array, written EITHER by
; READ_DUAL_JOYSTICK_INPUT or by DECODE_JOY_LOOP (Stage 8) depending on
; CONTROL_SCHEME below, so the rest of the game reads it the same way
; regardless of which control method produced it:
;   [0] JOY_STATE   - speed delta: joystick 1 up=+1 (accelerate), down=-1 (brake)
;   [1] JOY_STATE+1 - steering delta: joystick 1 right=+1, left=-1
;   [2] JOY1_FIRE_BTN ($4D0B) - joystick 1's own fire button. CONFIRMED read
;       at $8CE0, inside the still-undissected hero/object move-handler
;       block after OBJINIT_PARAM_TBL (Stage 5): gates a DEC of GUN_HEAT
;       ($F6) when HERO_STATE=$07 and a couple of other checks pass - this
;       is almost certainly the MACHINE GUN fire trigger (GUN_HEAT acting
;       as a per-shot heat/cooldown gauge, not literal ammo - matches
;       MOVE_BOAT_CRASH clearing it to 0 alongside MISSILE_CNT/SMOKE_CNT on
;       a crash). Not expanded into labelled instructions yet - that whole
;       block is a substantial task of its own (see its header comment) -
;       but the joystick-1-fire connection itself is confirmed.
;   [3] WEAPON_FIRE_INPUT ($4D0C) - joystick PORT 2's fire button, read
;       directly (not via the port-1 steering decode) - this is what
;       UPDATE_WEAPONS (Stage 6) checks to fire the current SPECIAL weapon
;       (smoke/missile, limited ammo via SMOKE_CNT/MISSILE_CNT).
; CONFIRMED (user-reported, verified by tracing READ_DUAL_JOYSTICK_INPUT
; below, and cross-checked against references/Commodore_64_memory_map.rtf's
; CIA1 port bit layout): Spy Hunter is single-player only, but does read a
; SECOND joystick port - its fire button, and only its fire button, fires
; the special weapon; joystick 1's OWN fire button (same port as steering)
; fires the machine gun instead. This has nothing to do with
; CONTROL_SCHEME/DIFFICULTY_MODE below, which were previously (incorrectly)
; named as if they were a 2-player mode.
JOY_STATE = $4D09    ; decoded joystick/keyboard input (see above)
STATE_4D0A = $4D0A    ; state byte, used by DRAW_STATE_4D89_PREP (???)
JOY1_FIRE_BTN = $4D0B    ; joystick 1's own fire button - fires the machine gun
WEAPON_FIRE_INPUT = $4D0C    ; joystick 2's fire button - fires the current weapon
IRQ_HALF = $4D0D    ; IRQ top/bottom toggle
STATE_4D0E = $4D0E    ; state byte, used by DRAW_STATE_4D89_PREP (???)
FRAME_SUBCTR = $4D0F    ; frame sub-counter
STATE_4D10 = $4D10
; CONTROL_SCHEME: an input-METHOD choice, NOT a player count - confirmed by
; tracing its two dispatch targets (Stage 2's INIT_PLAY_STATE): 1 selects
; READ_DUAL_JOYSTICK_INPUT (joystick 1 steers, joystick 2 fires), 2 selects
; CONTROL_KEYBOARD_ENTRY (the keyboard-matrix decoder, SCAN_JOY_KEYS/
; DECODE_JOY_LOOP, Stage 8) - i.e. "play with two joysticks" vs. "play with
; the keyboard". This game has no two-player mode.
CONTROL_SCHEME = $4D11    ; 1=dual joystick, 2=keyboard (was wrongly named NUM_PLAYERS)
EXTRA_LIFE_AVAIL = $4D12    ; timer-expired flag: $00 running(timer shown),
                            ;   $FF expired (DRAW_STATUS_PANEL shows lives, hides timer)
GAME_STATE = $4D13    ; game state machine
; DIFFICULTY_MODE: CONFIRMED Novice(1)/Expert(2) difficulty select, NOT a
; 2-player flag - ADD_SCORE (Stage 9-adjacent) adds this value directly to
; NEXT_LIFE_SCORE (a BCD ten-thousands-digit counter), giving +10,000/life
; in Novice vs +20,000/life in Expert - an exact match to the manual's
; documented figures (claude/Enemy_Agents_Manual_Reference.md).
DIFFICULTY_MODE = $4D14    ; 1=Novice, 2=Expert (was wrongly named TWO_PLAYER)
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
OBJ_TBL23 = $4D23    ; per-slot BASE sprite pointer - COMMIT_TYPE copies
                      ;   TYPE_TBL_SPRPTR's value here AND into SPRITE_PTRS at
                      ;   spawn; every frame after, COMMIT_SPRITE_OFS recomputes
                      ;   SPRITE_PTRS = OBJ_TBL33 (anim-frame offset) + this
                      ;   base - confirmed by direct reading, not a guess
SPRITE_PTRS = $4D2B    ; sprite pointer shadow (copied to $7BF8 each frame)
OBJ_TBL33 = $4D33    ; per-slot animation-frame sprite-pointer OFFSET - added
                      ;   to OBJ_TBL23 (the base pointer) by COMMIT_SPRITE_OFS
                      ;   every frame to get the current SPRITE_PTRS value;
                      ;   the DRAW_DISPATCH_99CB/99D8 tail (per-type draw code)
                      ;   is what advances it frame to frame
STATE_4D34 = $4D34    ; per-slot draw-timer value, used by the shared
                       ;   "decrement/loop" draw-routine tail (???)
STATE_4D39 = $4D39    ; state byte (???)
OBJ_TBL3B = $4D3B    ; per-slot X target threshold (negative/left direction)
                      ;   - confirmed this session: DRAW_MOVE_X_NEG/CHECK
                      ;   compare OBJ_POS_X against it to decide whether to
                      ;   nudge the slot's position one step closer per frame
OBJ_TBL43 = $4D43    ; per-slot X target threshold (positive/right
                      ;   direction) - same DRAW_MOVE_X_POS mechanism as
                      ;   OBJ_TBL3B above, mirrored
STATE_4D44 = $4D44    ; TYPE $07 (the Copter)'s own approach-phase index:
                      ;   DRAW_T07_PROX_CHECK adjusts it up/down (clamped
                      ;   0-2) based on the $C6 proximity value each frame,
                      ;   and it indexes DRAW_T07_TAIL_TBL to pick a per-
                      ;   phase timer/VIC_SPR_YEXP value - reads as a
                      ;   near/mid/far bombing-run stage, not confirmed
                      ;   against the visual (???)
OBJ_TBL4B = $4D4B    ; per-slot Y target threshold - same DRAW_MOVE_Y_CHECK
                      ;   step-toward-target mechanism as OBJ_TBL3B/43,
                      ;   confirmed this session (see those comments)
OBJ_TBL53 = $4D53    ; per-slot Y target threshold, combines OBJ_TBL3B/4B/43
                      ;   nibbles (COMMIT_TYPE) - the DRAW_MOVE_DISPATCH
                      ;   frame-parity path compares OBJ_POS_Y against it
STATE_4D54 = $4D54    ; state byte (???)
OBJ_TBL5B = $4D5B    ; per-slot value (???)
STATE_4D5C = $4D5C    ; state byte (???)
STATE_4D61 = $4D61    ; state byte (???)
OBJ_TBL63 = $4D63
STATE_4D64 = $4D64    ; hero-draw state, checked together with STATE_4D6C/
                      ;   STATE_4D74 (all-zero -> DRAW_T00_F3 moves on to F4).
                      ;   Its own value (0/{3,4,5}/other) selects a -1/0/+1
                      ;   sprite X-nudge in DRAW_T00_F3 - candidate: current
                      ;   steering/lane direction, not confirmed (???)
OBJ_TBL69 = $4D69
OBJ_TBL6B = $4D6B
STATE_4D6C = $4D6C    ; hero-draw state, checked alongside STATE_4D64 (see
                      ;   its comment) - part of the same all-zero gate (???)
OBJ_TBL71 = $4D71
OBJ_TBL73 = $4D73
STATE_4D74 = $4D74    ; hero-draw state, checked alongside STATE_4D64 (see
                      ;   its comment); DRAW_T00_F1 also checks it alone to
                      ;   decide whether to tick STATE_9B/STATE_4D54 (???)
OBJ_TBL79 = $4D79
OBJ_TBL7B = $4D7B    ; per-slot hazard-check value (HAZARD_CHECK_CHAIN)
STATE_4D7C = $4D7C    ; state byte (???)
STATE_4D81 = $4D81    ; state byte (???)
STATE_4D83 = $4D83    ; per-slot "hit pending" flag - confirmed the shared
                      ;   signal between the bullet's hit-resolution
                      ;   (MOVE_TYPE_1B_B sets it on a proximity match) and
                      ;   each TYPE's own MOVE_TYPE_* handler (checks it
                      ;   nonzero next frame to award its hardcoded
                      ;   POINTS_TBL kill tier via ARM_SCORE_EVENT_X8 - see
                      ;   claude/Enemy_Scoring_Notes.md). MOVE_TYPE_0C
                      ;   uniquely decrements it as a multi-frame counter
                      ;   instead of a single flag (candidate: the Road
                      ;   Lord's "must be rammed repeatedly" mechanic)
STATE_4D84 = $4D84    ; single flag/counter, not per-slot - incremented by
                      ;   MOVE_TYPE_1B_HIT (the bullet's direct hit on TYPE
                      ;   $07/$08) and reset by MOVE_TYPE_18 - candidate: a
                      ;   global "just scored an aerial hit" flag, not
                      ;   confirmed (???)
STATE_4D89 = $4D89    ; boat: "already crashed/handled this frame" flag -
                      ;   confirmed by MOVE_BOAT_MAIN/MOVE_BOAT_CRASH
                      ;   (claude/Collision_Detection_Notes.md); also armed
                      ;   by DRAW_STATE_4D89_PREP when SPEED_SUM falls in
                      ;   [$23,$DC) - candidate: re-arms once the car/boat
                      ;   has settled into a mid-range speed after a crash
OBJ_TBL8B = $4D8B    ; per-slot hazard-check match counter: MOVE_HAZARD_TAIL
                      ;   increments it when HAZARD_CHECK_07 matches, and
                      ;   again for HAZARD_CHECK_0B (only attempted if still
                      ;   zero) - gates which hazard checks still run this
                      ;   pass once one has already matched
OBJ_TBL93 = $4D93    ; per-slot proximity/hitbox threshold, compared against
                      ;   the clamped SPR_STAGE sprite-distance in
                      ;   CONSUME_HIT_MASK_BIT - the sprite-to-sprite
                      ;   collision check (see that routine's own comment).
                      ;   Exact units (pixels? clamped delta steps?) (???)
OBJ_TBL9B = $4D9B    ; per-slot value, added to/subtracted from OBJ_TBLA3 in
                      ;   CONSUME_HIT_MASK_BIT's threshold comparison -
                      ;   candidate: hitbox half-width paired with OBJ_TBLA3's
                      ;   centre offset (???)
OBJ_TBLA3 = $4DA3    ; per-slot value, combined with OBJ_TBL9B (see above) (???)
OBJ_TBLAB = $4DAB
STATE_4DAC = $4DAC
STATE_4DAE = $4DAE    ; state byte (???)
OBJ_TBLB3 = $4DB3
STATE_4DB9 = $4DB9
OBJ_TBLBB = $4DBB
STATE_4DC1 = $4DC1
SCORE_EVENT = $4DC3    ; queued score events
STAT_CTR = $4DC4    ; statistic counters
STATE_4DC9 = $4DC9    ; state byte (???)
STATE_4DCA = $4DCA    ; short countdown, armed to $3C (60) on a hazard/hit event (???)
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
VIC_SPR_YEXP = $D017    ; sprite Y-expand (double height), one bit per sprite
VIC_MEMPTR = $D018    ; screen+charset pointers
VIC_IRR = $D019    ; interrupt request reg
VIC_IMR = $D01A    ; interrupt mask reg
VIC_SPR_BGPRI = $D01B    ; sprite-bg priority
VIC_SPR_MCM = $D01C    ; per-sprite multicolour-mode enable, one bit per sprite
VIC_SPR_XEXP = $D01D    ; sprite X-expand (double width), one bit per sprite
VIC_BORDER = $D020    ; border colour
VIC_BG0 = $D021    ; background colour 0
VIC_BG1 = $D022    ; background colour 1
VIC_BG2 = $D023    ; background colour 2
VIC_SPRMC0 = $D025    ; sprite multicolour 0
VIC_SPRMC1 = $D026    ; sprite multicolour 1
VIC_SPR_COLOR = $D027    ; per-sprite individual colour (8 regs, $D027-$D02E)
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
; CIA1_PRA/PRB bit layout (active-low; confirmed against
; references/Commodore_64_memory_map.rtf): bit0=up, bit1=down, bit2=left,
; bit3=right, bit4=fire, for whichever joystick port shares that register.
CIA1_PRA = $DC00    ; CIA1 port A (keyboard cols/joy2 - bit4=joy2 fire)
CIA1_PRB = $DC01    ; CIA1 port B (keyboard rows/joy1 - bit4=joy1 fire)
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
    jsr ATTRACT_MENU    ; show the menu (control scheme, difficulty) until START is hit

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
; how long it's been held, and once both menu choices (control scheme,
; difficulty) have been made, start playing.
START_OR_SELECT_PRESSED:
    inc START_HELD
    lda CONTROL_SCHEME
    beq GOTO_MENU_SELECT  ; no control scheme chosen yet -> go pick one
    lda DIFFICULTY_MODE
    beq GOTO_MENU_SELECT  ; no difficulty chosen yet either -> same menu
    sta GAME_STATE          ; otherwise commit to playing (A = DIFFICULTY_MODE here)

; Reached every frame once GAME_STATE is nonzero (i.e. once actually playing).
; Its job is to notice "game over" and, after a short wait, either restart
; the game (if the player presses something) or fall back to attract mode.
ATTRACT_LOOP_CHECK:
    lda DEMO_TIMER
    bne GOTO_MENU_SELECT  ; demo/attract countdown still running
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

GOTO_MENU_SELECT:
    lda #$01
    sta GAME_STATE
    jsr RESET_ROAD_INDEX_ALT
    inc SCENE_IDX
    jmp MAIN_RUN_MENU             ; go show the control-scheme/difficulty menu

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
; MENU_MSG_TBL / MENU_MSG_TBL_B: char-codes for the control-scheme/difficulty
; select screen (previously mislabelled "player-select" - see below).
    .byte $28,$24,$0A,$20,$30,$0A,$40,$24,$1E,$40,$0A,$06,$12,$2C,$1E,$1C
    .byte $0A,$24,$1E,$06,$26,$40,$10,$0E,$12,$10

; -----------------------------------------------------------------------
; Control-scheme / difficulty select screen: like ATTRACT_TITLE, this runs
; once per pass through the boot-order chain, not in an internal wait-loop
; (see the note above ATTRACT_TITLE). Two sequential single-poll prompts:
; first "how to play" (CONTROL_SCHEME: dual joystick vs. keyboard), then
; "which difficulty" (DIFFICULTY_MODE: Novice vs. Expert). The exact key
; codes compared against ($1D/$1A/$18/$31) are POLL_INPUT_FRAME's raw
; decoded-input values - see SCAN_JOY_KEYS/KEYCODE_TBL in a later section for
; how those are produced; not cross-checked here. (???)
;
; NOTE: this pair of prompts was previously mislabelled as a "how many
; players" / player-count select - CONFIRMED wrong (user-reported): Spy
; Hunter is single-player only. The first prompt selects an INPUT method
; (CONTROL_SCHEME - see READ_DUAL_JOYSTICK_INPUT, Stage 8, for where the
; game reads a second joystick port's fire button for weapons, unrelated to
; player count); the second selects DIFFICULTY_MODE (Novice/Expert),
; confirmed by its exact effect on the extra-life score threshold in
; ADD_SCORE matching the manual's 10,000/20,000-point figures exactly.
ATTRACT_MENU:
    jsr RESET_SCREEN_STATE
    lda GAME_STATE
    beq MENU_ABORT      ; GAME_STATE=0 (attract mode) -> nothing to do, bail
    jsr DELAY_FRAMES_ALT
    ldx #$14
    ldy #$09            ; 10 entries in MENU_MSG_TBL_B

DRAW_CONTROL_PROMPT_LOOP:
    lda MENU_MSG_TBL_B,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl DRAW_CONTROL_PROMPT_LOOP
    jsr DRAW_SCORE

POLL_CONTROL_CHOICE:
    jsr POLL_INPUT_FRAME
    beq MENU_ABORT       ; no input this frame -> bail
    ldx #$01
    ldy #$11
    cmp #$1D
    beq CONTROL_SCHEME_CHOSEN   ; input $1D -> dual joystick (X stays 1)
    inx                  ; X=2
    ldy #$1D
    cmp #$1A
    bne POLL_CONTROL_CHOICE  ; not $1A either -> keep polling next frame

CONTROL_SCHEME_CHOSEN:
    stx CONTROL_SCHEME    ; CONTROL_SCHEME = 1 (joystick) or 2 (keyboard)
    ldx #$12
    lda #$00

; Clear a block of rows across all 6 play/high-score screen-buffer areas
; (play buffer x3 + high-score buffer x3, see the SCR_PLAY_*/SCR_HISC_*
; equates) to erase the control-scheme prompt before the next one.
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

DRAW_DIFFICULTY_PROMPT_LOOP:
    lda MENU_MSG_TBL,y
    jsr PANEL_PUT_CHAR_PAIR
    dey
    bpl DRAW_DIFFICULTY_PROMPT_LOOP

POLL_DIFFICULTY_CHOICE:
    jsr POLL_INPUT_FRAME
    beq MENU_ABORT
    ldy #$01
    cmp #$18
    beq DIFFICULTY_CHOSEN  ; input $18 -> Novice (Y stays 1)
    cmp #$31
    bne POLL_DIFFICULTY_CHOICE   ; not $31 either -> keep polling
    iny                     ; input $31 -> Expert (Y=2)

DIFFICULTY_CHOSEN:
    sty GAME_STATE
    sty DIFFICULTY_MODE     ; both set to the same 1(Novice)/2(Expert) value
    dey
    beq MENU_DONE_NOVICE     ; Novice chosen -> clear the panel's right half
    jmp CLEAR_PANEL_FULL     ; Expert chosen -> clear its left half instead
                              ;   (CLEAR_PANEL_FULL's second entry point,
                              ;   see the CLEAR_PANEL/CLEAR_PANEL_ALT note
                              ;   near WAIT_FRAME_TIMER)

MENU_DONE_NOVICE:
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
    ldx DIFFICULTY_MODE
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
    stx NEXT_LIFE_SCORE ; CONFIRMED: a BCD ten-thousands-digit score threshold
                        ;   (2 = 20,000 points), not an index - ADD_SCORE later
                        ;   adds DIFFICULTY_MODE (1 or 2) to it directly,
                        ;   matching the manual's Novice(+10,000)/
                        ;   Expert(+20,000) extra-life figures exactly.
    stx MUX_SLOT_IDX
    lda #$0E
    sta VIC_SPRMC0      ; shared sprite colour 1: light blue
    lda #$01
    sta VIC_SPRMC1      ; shared sprite colour 2: white

; Pick which game-state handler VEC_STATE should dispatch to (via
; GAME_DISPATCH, every frame) for the game that's about to start - one of
; three addresses depending on GAME_STATE/CONTROL_SCHEME. $A189 (attract
; auto-drive) and $A9F6 (CONTROL_KEYBOARD_ENTRY, Stage 8, near
; SCAN_JOY_KEYS - the keyboard-matrix input decoder) aren't covered by this
; annotation pass; $A152 is READ_DUAL_JOYSTICK_INPUT (Stage 8) - CONFIRMED
; this dispatch is an input CONTROL METHOD choice (joystick vs. keyboard),
; NOT a player count (there is no 2-player mode in this game).
    lda #$89
    ldy #$A1
    ldx GAME_STATE
    beq SET_STATE_VEC        ; GAME_STATE=0 (attract) -> $A189
    ldx CONTROL_SCHEME
    dex
    beq JOYSTICK_CONTROL_VEC ; CONTROL_SCHEME=1 -> $A152 (dual joystick)
    lda #$F6
    ldy #$A9
    bne SET_STATE_VEC         ; CONTROL_SCHEME=2 -> $A9F6 (keyboard)

JOYSTICK_CONTROL_VEC:
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
; SPEEDCODE_IMAGE: a small routine kept here as its ROM master copy, copied
; to and run from RAM at $2800 each frame (for consistent cycle timing, not
; because it's about vehicle "speed" specifically - see the header's memory
; map notes). Its own internal absolute references (SPEEDCODE_TBL, the
; SPEED_SET call) still correctly point at these ROM addresses even when
; executing from $2800, since 6502 absolute addressing doesn't care where
; the executing code itself lives.
;
; This is the actual player-input-to-car-physics routine: it's the ONLY
; place in the whole ROM that reads JOY_STATE (the decoded joystick/
; keyboard input array, Stage 8) rather than just writing it, at both byte
; 0 (speed, here) and byte 1 (steering, further down) - CONFIRMED by an
; exhaustive search of every absolute reference to JOY_STATE in the
; assembled ROM.
;
; Speed half: SPEED_ACCUM is a small accumulator, decremented by
; JOY_STATE's speed delta (so pressing "up" - JOY_STATE=+1 - decreases it)
; and clamped so it's never positive (0 or negative only). It's folded into
; a running sum (SPEED_SUM, combined with ROAD_X_REF), which is then
; divided by 16 and re-centred (-8) to produce a small index (0-4); when in
; range, that index (via SPEEDCODE_TBL, which stores it REVERSED: 4,3,2,1,0)
; is used to SNAP SCROLL_SPEED directly to a target value via SPEED_SET
; (Stage 6) - i.e. this is a low-pass-filtered "ease toward a target scroll
; speed" mechanism, not a direct 1:1 joystick-to-speed mapping. Gated by a
; frame-parity/SCENE_ID check whose exact throttling logic isn't fully
; interpreted. (???: whether "up" nets out to actually mean faster or
; slower isn't confirmed from static analysis alone - would need a live
; snapshot pair capturing SCROLL_SPEED change immediately after an up/down
; press to settle it.)
;
; Steering half (STEER_GATE onward): the exact mirror of the above using
; JOY_STATE+1 (steering delta), STEER_ACCUM and STEER_SUM in place of
; SPEED_ACCUM/SPEED_SUM - but instead of snapping a value via a table, it
; toggles bit 6 of SPR_XMSB (the sprite-X-MSB shadow) when STEER_SUM
; overflows/goes negative, which reads as some kind of screen-position or
; scroll-direction flip rather than literal sprite positioning. (???: not
; fully interpreted.)
SPEEDCODE_TBL:
    .byte $04,$03,$02,$01,$00

SPEEDCODE_IMAGE:
    lda FRAME_CTR
    lsr
    bcc SPEED_ACCUM_ADJUST
    ldy SCENE_ID
    cpy #$05
    beq SPEED_ACCUM_ADJUST
    lsr
SPEED_ACCUM_ADJUST:
    lda SPEED_ACCUM
    bcc SPEED_ACCUM_CLAMP
    sbc JOY_STATE
SPEED_ACCUM_CLAMP:
    bmi SPEED_ACCUM_CLAMP2
    lda #$00
SPEED_ACCUM_CLAMP2:
    cmp #$F8
    bpl SPEED_ACCUM_DONE
    lda #$F8
SPEED_ACCUM_DONE:
    sta SPEED_ACCUM
    clc
    adc ROAD_X_REF
    clc
    adc SPEED_SUM
    sta SPEED_SUM
    lsr
    lsr
    lsr
    lsr
    sec
    sbc #$08
    tax
    bmi SPEED_SNAP_CHECK
    cpx #$05
    bcs SPEED_SNAP_CHECK
    lda SPEEDCODE_TBL,x
    jsr SPEED_SET
SPEED_SNAP_CHECK:
    cpy #$06
    beq STEER_GATE
    lda ROAD_PHASE
    cmp #$02
    bne STEER_ACCUM_ADJUST
STEER_GATE:
    lda FRAME_CTR
    lsr
    bcc STEER_SNAP_CHECK
STEER_ACCUM_ADJUST:
    ldx ROAD_X_REF
    beq STEER_ACCUM_DONE
    ldy JOY_STATE+1
    tya
    clc
    adc STEER_ACCUM
    tax
    bmi STEER_ACCUM_NEG
    beq STEER_ACCUM_DONE
    cpy #$00
    beq STEER_ACCUM_DEC
    cmp ROAD_X_REF
    bcc STEER_ACCUM_DONE
    beq STEER_ACCUM_DONE
    bcs STEER_ACCUM_DEC
STEER_ACCUM_NEG:
    cpy #$00
    beq STEER_ACCUM_INC
    adc ROAD_X_REF
    beq STEER_ACCUM_INC
    bpl STEER_ACCUM_DONE
STEER_ACCUM_INC:
    inx
    inx
STEER_ACCUM_DEC:
    dex
STEER_ACCUM_DONE:
    stx STEER_ACCUM
STEER_SNAP_CHECK:
    lda STEER_ACCUM
    php
    clc
    adc STEER_SUM
    sta STEER_SUM
    bcs XMSB_TOGGLE_CHECK
    plp
    bmi XMSB_TOGGLE
    bpl SPEEDCODE_DONE
XMSB_TOGGLE_CHECK:
    plp
    bmi SPEEDCODE_DONE
XMSB_TOGGLE:
    lda SPR_XMSB
    eor #$40
    sta SPR_XMSB
SPEEDCODE_DONE:
    rts

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
; smaller/differently). The resulting bucket values (OBJ_TBL63/6B/73) ARE
; consumed further downstream, confirmed this session: the HAZARD_CHECK_*
; chain (claude/Collision_Detection_Notes.md) compares them against specific
; hazard tile codes, and ATTRACT_HELPER/COMMIT_DIR_LEFT_PTR read OBJ_TBL73
; directly as the confirmed boat-mode flag ($02) - so "distance bucket" also
; doubles as this game's tile/terrain classification used for hazard and
; boat-mode detection, not purely a perspective effect.
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
; OBJ_DIST_TBL: object distance thresholds (13 bytes) - the rest of this
; block, previously mislabelled "aux data (computed jumps)" and left as raw
; bytes, is genuine code: COMMIT_DIR_RIGHT_PTR/RIGHT_PTR, already called via
; JSR from COMMIT_TYPE's COMMIT_DIR_LEFT/COMMIT_DIR_RIGHT (Hero_Object_Move_
; Handler_Notes.md) to finish spawning a newly-committed object entering
; from the left/right screen edge: stages its initial Y position, derives a
; hazard threshold (OBJ_TBL7B) and a matching screen-tile scan range
; (ZTMP_08/09), possibly reclassifies STATE_4D04 based on this slot's
; current OBJ_TYPE/SCENE_IDX (special-cased for slot 6, the boat), scans up
; to 35 columns of the road-template screen for the first tile in that
; range, and finally derives an initial staged X position/SPR_XMSB bit from
; where (if anywhere) it found one (carry clear = found, set = not found -
; matching the "bcs MOVE_BAIL"-style convention callers elsewhere use). One
; more "BIT-absolute as a 2-byte skip" overlap trick, same idiom as
; elsewhere in this file.
    .byte $04,$08,$14,$1C,$24,$30,$38,$40,$72,$7A,$A7,$AD,$B7
COMMIT_DIR_RIGHT_PTR:
    lda #$00
    sta SRC_PTR
    lda #$78
    sta SRC_PTR_HI
    lda #$0F
    bne COMMIT_DIR_SPAWN_Y   ; (unconditional - A is always $0F, nonzero)
COMMIT_DIR_LEFT_PTR:
    lda #$C0
    sta SRC_PTR
    lda #$7B
    sta SRC_PTR_HI
    lda #$F3
COMMIT_DIR_SPAWN_Y:
    sta a:SPR_Y_SHADOW,y
    lda #$00
    ldy #$04
    asl ZTMP_08
    bcc COMMIT_DIR_HAZARD_STORE
    lda #$08
    ldy #$14
COMMIT_DIR_HAZARD_STORE:
    sta ZTMP_08
    sty ZTMP_09
    lsr a
    lsr a
    sta OBJ_TBL7B,x
    cpx #$06
    beq COMMIT_DIR_TYPE_ALT
    lda OBJ_TYPE,x
    beq COMMIT_DIR_CHECK_SCENE
    cmp #$18
    beq COMMIT_DIR_SET_TYPE
    clc
    lda STATE_4D04
    adc #$03
    cmp #$1E
    bcc COMMIT_DIR_SET_TYPE
    bcs COMMIT_DIR_TYPE_ALT
COMMIT_DIR_CHECK_SCENE:
    lda SCENE_IDX
    cmp #$13
    bcc COMMIT_DIR_TYPE_ALT
    lda #$12
    .byte $2C
COMMIT_DIR_TYPE_ALT:
    .byte $A9,$03
COMMIT_DIR_SET_TYPE:
    sta STATE_4D04
    tay
COMMIT_DIR_SCAN_LOOP:
    iny
    cpy #$23
    bcs COMMIT_DIR_DONE
    lda (SRC_PTR),y
    cmp ZTMP_08
    bcc COMMIT_DIR_SCAN_LOOP
    cmp ZTMP_09
    bcs COMMIT_DIR_SCAN_LOOP
    sty STATE_4D04
    tya
    ldy OBJ_IDX2
    asl a
    clc
    adc #$06
    asl a
    asl a
    sta a:SPR_X_SHADOW,y
    lda BIT_MASK
    bcc COMMIT_DIR_XMSB_CLR
    ora SPR_XMSB
    bne COMMIT_DIR_XMSB_STORE
COMMIT_DIR_XMSB_CLR:
    eor #$FF
    and SPR_XMSB
COMMIT_DIR_XMSB_STORE:
    sta SPR_XMSB
    clc
COMMIT_DIR_DONE:
    rts


; -----------------------------------------------------------------------
; For the CURRENT object (OBJ_IDX2), compute its X/Y DELTA to each of the 8
; hardware sprites in turn, clamp each delta to a signed 7-bit range, and
; pack it (sign bit + magnitude) into SPR_STAGE. This looks like prep work
; for the sprite-multiplexing system (SPR_STAGE is consumed elsewhere as
; "staged hardware sprite coords") - likely used to decide proximity/
; ordering when deciding which hardware sprite to reassign to which object.
; Confirmed one concrete consumer this session: GUN_CHECK_FIRE (the machine-
; gun fire gate, claude/Enemy_Scoring_Notes.md) reads SPR_STAGE entry 6
; (`$C6`/`$C7`) as a proximity/clearance check before allowing a shot - so
; at least one use is "is hardware sprite 6 too close" gating player fire,
; though whether that's the primary purpose or a side-effect reuse of this
; general-purpose array is still open. (???)
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
; CODE for the per-object-type move/draw handlers themselves - now fully
; converted to labelled instructions below (previously left as raw .byte
; data; a straight-line disassembler has no way to know code lives here,
; since these routines are only reached INDIRECTLY through OBJMOVE_VEC_LO/HI
; - the "bit 7 set" dispatch path in PROCESS_OBJECTS above - not through
; OBJINIT_PARAM_TBL's own per-TYPE vectors).
;
; Five distinct routines, one per SLOT that OBJMOVE_VEC_LO/HI points at
; (decoded from the table above: slot0=$8BAF, slot1=$8BD4, slot2&4=$8C5B,
; slot3&5=$8C5E, slot6=$8C90, slot7=$8CC2):
;   - slot 0 (SLOT0_HERO_WATCH): watches HERO_STATE (slot 1) and transitions
;     ITS OWN type to $08/$0A/$19/$1A accordingly - a hero-state-reactive
;     companion/effect object (candidate: splash/dock/scripted-sequence
;     visuals; not confirmed which).
;   - slot 1 (MOVE_HERO): the hero/player car's own movement/state-machine
;     logic - by far the most complex routine here.
;   - slots 2 & 4 (SLOT_2_4_ENTRY/SLOT_3_5_ENTRY): react to ROAD_FEATURE
;     $0E/$14 (icy-road/water-spawn features) and randomize VIC_SPRMC0 (the
;     shared sprite multicolour register) - candidate: the icy-road/night
;     sprite-recolour effect noted in claude/Ice_Road_And_Lap_Notes.md.
;   - slot 6 (MOVE_BOAT_SLOT): sets STATE_4D05 to 5 or 6 based on
;     SEQ_STATE/HERO_STATE/ANIM_STATE - CONFIRMED as the boat object: STATE_4D05
;     is the exact "per-boat crash/special-sequence" flag traced from the
;     other side in MOVE_TYPE_05_06 (claude/Collision_Detection_Notes.md).
;   - slot 7 (MOVE_GUN_SLOT): the confirmed machine-gun/JOY1_FIRE_BTN check
;     (see below) - CORRECTING last session's notes, which speculated this
;     might be slot 6; it's slot 7. On a successful shot this slot's own
;     type becomes commits to $1B - directly explaining MOVE_TYPE_1B
;     (claude/Collision_Detection_Notes.md), previously unexplained.
;
; All five converge on a shared tail (COMMIT_TYPE) that commits the new
; OBJ_TYPE and reinitialises the slot's sprite pointer, hit-group masks,
; VIC sprite-multicolour/expand bits and X/Y position deltas from data
; tables TYPE_TBL_93/SPRPTR/ANIM/HITGRP/SPRATTR/A3 (see the block after
; INIT_OBJECT_SLOT, claude/Draw_Handler_Notes.md).
;
; Several BIT-absolute/zp "2-byte skip" multi-entry tricks (the same idiom
; documented at HAZARD_CHECK_0C/0B/0A) are kept as raw bytes with labels at
; each entry point, for the same reason as always: ca65 can't express two
; different readings of the same bytes with ordinary mnemonics.
;
; Confirmed (this and a prior session): at GUN_CHECK_FIRE ($8CE0, LDA
; JOY1_FIRE_BTN), joystick 1's own fire button gates a DEC of GUN_HEAT when
; HERO_STATE=$07 - the machine-gun fire trigger, paired with
; WEAPON_FIRE_INPUT/joystick 2 firing the special weapon instead (see the
; JOY_STATE equate comment near the top of this file, and
; claude/Controls_And_Difficulty_Notes.md).
    .byte $AF,$8B,$D4,$8B,$5B,$8C,$5E,$8C,$5B,$8C,$5E,$8C,$90,$8C,$C2,$8C
    .byte $8E,$9A,$AA,$90,$8E,$9A,$AA,$90,$8E,$9A,$AA,$90,$8E,$9A,$AA,$90
    .byte $2E,$8B,$4D,$92,$F1,$99,$AA,$92,$F1,$99,$A2,$93,$80,$9A,$38,$8F
    .byte $2E,$8B,$27,$90,$B0,$9A,$48,$94,$34,$9B,$78,$94,$88,$9B,$FB,$94
    .byte $C5,$9A,$49,$95,$B3,$9A,$49,$95,$A8,$9A,$6D,$95,$A8,$9A,$6D,$95
    .byte $A8,$9A,$6D,$95,$02,$9B,$BE,$95,$B6,$9A,$EB,$95,$B9,$9A,$EB,$95
    .byte $2E,$8B,$24,$96,$2E,$8B,$6F,$96,$2E,$8B,$EC,$96,$2E,$8B,$24,$96
    .byte $A1,$9A,$1E,$97,$2E,$8B,$6B,$97,$2F,$9B,$A8,$97,$62,$9B,$FF,$94
SLOT0_HERO_WATCH:
    lda HERO_STATE
    cmp #$07
    beq SLOT0_TYPE_08
    cmp #$09
    beq SLOT0_TYPE_0A
    cmp #$18
    beq SLOT0_TYPE_19
    lda $A5
    cmp #$12
    beq SLOT0_TYPE_1A
    jmp MOVE_BAIL
SLOT0_TYPE_1A:
    lda #$1A
    .byte $2C
SLOT0_TYPE_19:
    .byte $A9,$19,$2C
SLOT0_TYPE_0A:
    .byte $A9,$0A,$2C
SLOT0_TYPE_08:
    .byte $A9,$08
    jmp COMMIT_TYPE
MOVE_HERO:
    lda OBJ_TYPE
    sta ZTMP_08
    sec
    ror OBJ_TYPE
    lda #$00
    sta FLAG_FB
    ldy SEQ_STATE
    dey
    beq HERO_CHECK_ROAD_13
    dey
    beq HERO_CHECK_4D17
    dey
    dey
    beq HERO_CHECK_4D17
    dey
    bne HERO_RESTORE_TYPE
    lda ROAD_FEATURE
    cmp #$14
    beq SLOT1_SET_18
HERO_RESTORE_TYPE:
    lda ZTMP_08
    sta OBJ_TYPE
    jmp MOVE_BAIL
HERO_CHECK_ROAD_13:
    lda ROAD_FEATURE
    cmp #$13
    beq HERO_ARM_TIMER
    lda ROAD_SEG_IDX
    cmp #$11
    bne HERO_COUNTDOWN
HERO_ARM_TIMER:
    lda #$02
    jsr SPEED_SET
    lda #$64
    sta STATE_4D10
HERO_COUNTDOWN:
    dec STATE_4D10
    bne HERO_RESTORE_TYPE
    inc STATE_4D10
    bne SLOT1_SET_00
HERO_CHECK_ROAD_0F:
    lda ROAD_FEATURE
    cmp #$0F
    beq HERO_CHECK_RANGE
    cmp #$13
    bcs HERO_RESTORE_TYPE
    ldy FLAG_FC
    beq HERO_CHECK_RANGE
    dec FLAG_FC
    beq SLOT1_SET_09
HERO_CHECK_RANGE:
    cmp #$02
    bcc SLOT1_SET_11
    cmp #$0E
    bcs HERO_RESTORE_TYPE
    lda FLAG_DD
    bne SLOT1_SET_07
    beq HERO_RESTORE_TYPE
HERO_CHECK_4D17:
    lda STATE_4D17
    beq HERO_CHECK_ROAD_0F
    bmi HERO_CHECK_ROAD_0F
    sec
    ror STATE_4D17
    .byte $2C
SLOT1_SET_18:
    .byte $A9,$18,$2C
SLOT1_SET_00:
    .byte $A9,$00,$2C
SLOT1_SET_07:
    .byte $A9,$07,$2C
SLOT1_SET_11:
    .byte $A9,$11,$2C
SLOT1_SET_09:
    .byte $A9,$09
    sta STATE_4D04
    jmp COMMIT_TYPE
SLOT_2_4_ENTRY:
    lda #$0C
    .byte $2C
SLOT_3_5_ENTRY:
    .byte $A9,$0D
    sta ZTMP_08
    lda SCENE_ID
    bmi SLOT24_BAIL
    ldy #$0E
    lda ROAD_FEATURE
    cmp #$0E
    beq SLOT24_APPLY
    cmp #$14
    beq SLOT24_APPLY
    jsr RNG_NEXT
    and #$03
    clc
    adc ZTMP_08
    bne SLOT24_SET_COLOR
SLOT24_APPLY:
    ldy #$0B
    cpx #$03
    beq SLOT24_TYPE_12
    lda #$13
    .byte $2C
SLOT24_TYPE_12:
    .byte $A9,$12
SLOT24_SET_COLOR:
    sty VIC_SPRMC0
    jmp COMMIT_TYPE
SLOT24_BAIL:
    jmp MOVE_BAIL
MOVE_BOAT_SLOT:
    lda SEQ_STATE
    cmp #$01
    beq SLOT6_CHECK_ANIM
    cmp #$03
    beq SLOT6_STATE_06
    cmp #$05
    bne SLOT6_BAIL
    lda HERO_STATE
    cmp #$18
    bne SLOT6_BAIL
    lda STATE_9B
    bne SLOT6_STATE_06
SLOT6_BAIL:
    jmp MOVE_BAIL
SLOT6_CHECK_ANIM:
    lda HERO_STATE
    cmp #$04
    bcs SLOT6_BAIL
    lda STATE_9B
    cmp #$02
    bne SLOT6_BAIL
    lda #$05
    .byte $2C
SLOT6_STATE_06:
    .byte $A9,$06
    sta STATE_4D05
    jmp COMMIT_TYPE
MOVE_GUN_SLOT:
    lda SEQ_STATE
    beq SLOT7_IDLE
    cmp #$05
    beq SLOT7_BAIL
    cmp #$06
    beq SLOT7_SET_17
    bcs SLOT7_SET_16
    lda HERO_STATE
    cmp #$04
    bcs GUN_CHECK_FIRE
    lda STATE_9B
    cmp #$02
    beq TYPE_ANIM_BUSY
    cmp #$05
    beq TYPE_ANIM_BUSY
GUN_CHECK_FIRE:
    lda JOY1_FIRE_BTN
    beq SLOT7_BAIL
    lda SEQ_STATE
    cmp #$02
    bcc SLOT7_BAIL
    cmp #$05
    bcs SLOT7_BAIL
    lda HERO_STATE
    cmp #$07
    bne TYPE_GUN_NOFIRE
    lda GUN_HEAT
    beq TYPE_GUN_NOFIRE
    lda $C7
    bmi TYPE_GUN_NOFIRE
    lda $C6
    and #$7F
    cmp #$46
    bcs TYPE_GUN_NOFIRE
    dec GUN_HEAT
    bcc TYPE_GUN_FIRED
SLOT7_BAIL:
    jmp MOVE_BAIL
SLOT7_IDLE:
    lda #$15
    .byte $2C
SLOT7_SET_17:
    .byte $A9,$17,$2C
SLOT7_SET_16:
    .byte $A9,$16
    pha
    lda SEQ_STATE
    and #$04
    ora #$01
    sta SEQ_STATE
    sec
    ror SCENE_ID
    pla
    .byte $2C
TYPE_GUN_FIRED:
    .byte $A9,$1B,$2C
TYPE_GUN_NOFIRE:
    .byte $A9,$0B,$2C
TYPE_ANIM_BUSY:
    .byte $A9,$04,$2C
; Reached via direct JSR from TRIGGER_SWAP_FX (the tail of ARM_SCORE_EVENT,
; below) - i.e. this commits OBJ_TYPE=$14 specifically right after an enemy
; kill has just been queued for scoring. Strong candidate: the
; explosion/destroyed-enemy effect type.
TYPE_KILL_FX:
    .byte $A9,$14
COMMIT_TYPE:
    sta OBJ_TYPE,x
    tay
    lda TYPE_TBL_VEL,y
    pha
    and #$03
    asl
    sta OBJ_TBL43,x
    eor #$FF
    clc
    adc #$02
    sta OBJ_TBL3B,x
    pla
    lsr
    lsr
    pha
    beq COMMIT_YVEL_DONE
    ora #$FC
COMMIT_YVEL_DONE:
    sta OBJ_TBL4B,x
    pla
    lsr
    lsr
    beq COMMIT_TYPE_CONT
    ora #$F0
COMMIT_TYPE_CONT:
    sta OBJ_TBL53,x
    lda TYPE_TBL_93,y
    sta OBJ_TBL93,x
    lda TYPE_TBL_SPRPTR,y
    sta SPRITE_PTRS,x
    sta OBJ_TBL23,x
    lda TYPE_TBL_ANIM,y
    sta OBJ_ANIM,x
    lda TYPE_TBL_HITGRP,y
    sta ZTMP_08
    and #$3F
    sta OBJ_TBL9B,x
    lda BIT_MASK
    asl ZTMP_08
    bcc COMMIT_HITGROUP0_NEG
    ora HIT_GROUP0
    bne COMMIT_HITGROUP0_DONE
COMMIT_HITGROUP0_NEG:
    eor #$FF
    and HIT_GROUP0
COMMIT_HITGROUP0_DONE:
    sta HIT_GROUP0
    lda BIT_MASK
    asl ZTMP_08
    bcc COMMIT_HITGROUP2_NEG
    ora HIT_GROUP2
    bne COMMIT_HITGROUP2_DONE
COMMIT_HITGROUP2_NEG:
    eor #$FF
    and HIT_GROUP2
COMMIT_HITGROUP2_DONE:
    sta HIT_GROUP2
    lda TYPE_TBL_SPRATTR,y
    sta ZTMP_08
    and #$0F
    sta VIC_SPR_COLOR,x
    lda BIT_MASK
    asl ZTMP_08
    bcs COMMIT_SPRMCM_NEG
    ora VIC_SPR_MCM
    bne COMMIT_SPRMCM_DONE
COMMIT_SPRMCM_NEG:
    eor #$FF
    and VIC_SPR_MCM
COMMIT_SPRMCM_DONE:
    sta VIC_SPR_MCM
    lda BIT_MASK
    asl ZTMP_08
    bcc COMMIT_SPRXEXP_NEG
    ora VIC_SPR_XEXP
    bne COMMIT_SPRXEXP_DONE
COMMIT_SPRXEXP_NEG:
    eor #$FF
    and VIC_SPR_XEXP
COMMIT_SPRXEXP_DONE:
    sta VIC_SPR_XEXP
    lda BIT_MASK
    asl ZTMP_08
    bcc COMMIT_SPRYEXP_NEG
    ora VIC_SPR_YEXP
    bne COMMIT_SPRYEXP_DONE
COMMIT_SPRYEXP_NEG:
    eor #$FF
    and VIC_SPR_YEXP
COMMIT_SPRYEXP_DONE:
    sta VIC_SPR_YEXP
    lda TYPE_TBL_A3,y
    sta ZTMP_08
    and #$0F
    sta OBJ_TBLA3,x
    ldy OBJ_IDX2
    asl ZTMP_08
    bcc COMMIT_DIR_CHECK2
    asl ZTMP_08
    asl ZTMP_08
    lda SCROLL_SPEED
    cmp #$03
    bcc COMMIT_DIR_LEFT
    bcs COMMIT_DIR_RIGHT
COMMIT_DIR_CHECK2:
    asl ZTMP_08
    lda #$00
    bcc COMMIT_APPLY_XVEL
    asl ZTMP_08
    bcs COMMIT_DIR_RIGHT
COMMIT_DIR_LEFT:
    jsr COMMIT_DIR_LEFT_PTR
    lda OBJ_TBL53,x
    jmp COMMIT_APPLY_XVEL
COMMIT_DIR_RIGHT:
    jsr COMMIT_DIR_RIGHT_PTR
    lda OBJ_TBL4B,x
COMMIT_APPLY_XVEL:
    bcs MOVE_BAIL
    sta OBJ_POS_Y,x
    lda #$00
    sta OBJ_POS_X,x
    sta OBJ_TBL33,x
    sta OBJ_TBL5B,x
    sta OBJ_TBL8B,x
    sta STATE_4D83,x
    sta OBJ_TBLAB,x
    jsr COMMIT_SPRITE_OFS
    jsr CLEAR_HIT_STATE
    sec
    rts
MOVE_BAIL:
    ldy OBJ_IDX2

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
; Secondary entry point: clear just this slot's HIT_MASK_A/HIT_MASK_B/
; HIT_ACCUM bits (skipping the position/type/sprite-pointer/HIT_GROUP0/
; HIT_GROUP2 reset above) - called directly via JSR from COMMIT_APPLY_XVEL's
; tail once a new type/position has been committed.
CLEAR_HIT_STATE:
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
; Per-object DRAW handlers for OBJ_TYPEs $00-$05/$07/$08 (the hero's own type
; range plus a few more enemy/effect types) - the counterpart to
; claude/Draw_Handler_Notes.md's block, dispatched the same way via
; OBJINIT_PARAM_TBL's draw-vector column -> ZVEC_DRAW -> OBJ_VEC2_DISPATCH.
; Also holds the 7 per-OBJ_TYPE initialisation tables (TYPE_TBL_*, 28 bytes
; each) that COMMIT_TYPE (Stage 5, hero/object move-handler block) reads to
; set up a freshly-committed object's sprite pointer, hit groups, VIC
; sprite-attribute bits, animation frame and velocity nibbles - COMMIT_TYPE's
; own raw-hex references to these tables have been updated to use the names
; below.
;
; DRAW_TBL_T00 (TYPE $00-$03, the hero) has by far the most frames (10) -
; consistent with the hero being the most complex-to-animate object. Two
; more small byte-indexed tables (DRAW_T07_TAIL_TBL, DRAW_T00_F3_TBL) are
; read via indexed LDA/ADC from within their neighbouring routines, the same
; idiom as the two byte tables in the previous block.
;
; TYPE semantics are not interpreted here, same disclaimer as the previous
; block - this is a mechanical data-to-code conversion pass. Two more
; "BIT-absolute as a 2-byte skip" overlap tricks are kept as raw bytes with
; labels at each entry point.
TYPE_TBL_A3:
    .byte $44,$04,$04,$04,$04,$66,$04,$04,$00,$86,$04,$06,$86,$82,$86,$86
    .byte $86,$64,$94,$94,$00,$04,$04,$04,$52,$00,$04,$04
TYPE_TBL_HITGRP:
    .byte $D0,$D0,$D0,$D0,$10,$CC,$CE,$58,$58,$CC,$48,$4C,$CC,$D2,$CC,$CC
    .byte $CA,$5A,$D0,$D0,$18,$0C,$10,$18,$D4,$08,$02,$46
TYPE_TBL_93:
    .byte $20,$20,$20,$20,$07,$15,$16,$1E,$20,$1C,$01,$0E,$15,$14,$11,$14
    .byte $11,$0A,$1C,$16,$15,$10,$11,$15,$20,$06,$10,$0B
TYPE_TBL_SPRATTR:
    .byte $2A,$2A,$2A,$2A,$00,$04,$2A,$0A,$81,$2A,$0E,$28,$0A,$0A,$03,$0A
    .byte $08,$C3,$2F,$2A,$08,$08,$06,$08,$2A,$81,$20,$0A
TYPE_TBL_SPRPTR:
    .byte $5F,$5C,$5D,$5E,$8C,$50,$83,$68,$6D,$72,$8D,$90,$71,$78,$74,$73
    .byte $7B,$93,$80,$86,$64,$64,$8F,$64,$75,$77,$91,$92
TYPE_TBL_ANIM:
    .byte $04,$09,$09,$09,$03,$03,$01,$03,$03,$02,$02,$01,$00,$00,$00,$00
    .byte $00,$01,$00,$01,$01,$05,$03,$02,$02,$00,$01,$01
TYPE_TBL_VEL:
    .byte $D6,$DA,$DA,$DA,$00,$00,$00,$FC,$00,$73,$00,$00,$AB,$CA,$CA,$BF
    .byte $DD,$00,$CD,$B9,$00,$00,$00,$00,$C6,$00,$00,$00
DRAW_TBL_T07:
    .word DRAW_T07_F0
    .word DRAW_T07_F1
    .word DRAW_T07_F2
    .word DRAW_T07_F3
DRAW_T07_TAIL_TBL:
    .byte $00,$04,$01
DRAW_T07_NOT_READY:
    sec
    ror HERO_STATE
    lda #$00
    sta FLAG_FF
    rts
DRAW_T07_ARM_TIMER:
    jsr RNG_NEXT
    and #$3F
    sta STATE_4D5C
    lda #$01
    sta FLAG_FF
    rts
DRAW_T07_F0:
    ldy #$1C
    jsr SOUND_REQ_V0B
    lda SPAWN_Y
    cmp #$09
    bcc DRAW_T07_NOT_READY
    jmp DRAW_T07_DISPATCH
DRAW_T07_RESET:
    dec STATE_9B
    lda #$00
    sta $AB
    lda #$02
    sta STATE_4D54
    lda FLAG_FF
    pha
    lda #$FF
    sta FLAG_FF
    pla
    bpl DRAW_T07_RESET_DONE
    lda #$01
    sta STATE_4D5C
    jsr ATTRACT_HELPER
DRAW_T07_RESET_DONE:
    rts
DRAW_T07_F1:
    lda STATE_4DAC
    bne DRAW_T07_RESET
    lda FLAG_FF
    bpl DRAW_T07_CHECK_TIMER
    jmp DRAW_T07_CLEAR_AB
DRAW_T07_CHECK_TIMER:
    bne DRAW_T07_PROX_CHECK
    jsr DRAW_T07_ARM_TIMER
DRAW_T07_PROX_CHECK:
    lda $C6
    asl
    php
    cmp #$02
    bcc DRAW_T07_INDEX_MIN
    plp
    bcc DRAW_T07_INDEX_INC
    lda STATE_4D44
    beq DRAW_T07_INDEX_MAX
    dec STATE_4D44
DRAW_T07_INDEX_MAX:
    lda #$FF
    bne DRAW_T07_INDEX_STORE
DRAW_T07_INDEX_INC:
    lda STATE_4D44
    cmp #$02
    bcs DRAW_T07_INDEX_MID
    inc STATE_4D44
DRAW_T07_INDEX_MID:
    lda #$01
    bne DRAW_T07_INDEX_STORE
DRAW_T07_INDEX_MIN:
    plp
    lda #$00
DRAW_T07_INDEX_STORE:
    sta $AB
    lda SPEED_SUM
    sec
    sbc #$3C
    sbc SPAWN_Y
    beq DRAW_T07_DIR_ZERO
    bcs DRAW_T07_DIR_POS
    lda #$FF
    .byte $2C
DRAW_T07_DIR_POS:
    .byte $A9,$01
DRAW_T07_SET_DIR:
    sta STATE_4D54
    ldy STATE_4D44
    lda DRAW_T07_TAIL_TBL,y
    sta STATE_4D34
    lda VIC_SPR_YEXP
    dey
    bne DRAW_T07_YEXP_CLEAR
    ora BIT_MASK
    .byte $2C
DRAW_T07_YEXP_CLEAR:
    .byte $25,$10
    sta VIC_SPR_YEXP
DRAW_T07_DISPATCH:
    lda STATE_4D54
DRAW_T07_COMMIT:
    pha
    jsr DRAW_DISPATCH_99D8
    pla
    jsr DRAW_ADJUST_POS_Y
    ldx OBJ_IDX
    jmp ATTRACT_HELPER
DRAW_T07_DIR_ZERO:
    lda #$00
    beq DRAW_T07_SET_DIR
DRAW_T07_CLEAR_AB:
    lda #$00
    sta $AB
    jmp DRAW_T07_COMMIT
DRAW_T07_F2:
    lda $C7
    bmi DRAW_T07_DISPATCH
    dec STATE_9B
    jmp DRAW_T07_ARM_TIMER
DRAW_T07_F3:
    dec STATE_9B
    dec $AB
    lda #$FA
    sta SPAWN_Y
    lda BIT_MASK
    ora SPR_XMSB
    sta SPR_XMSB
    lda #$20
    sta $CC
    jsr SOUND_SILENCE
    ldy #$1A
    jmp SOUND_REQ_V0B
DRAW_TBL_T08:
    .word DRAW_T08_F0
    .word DRAW_T08_F1
    .word DRAW_T08_F2
    .word DRAW_T08_F3
DRAW_T08_F0:
    lda #$04
    sta OBJ_ANIM
    lda #$01
    jsr DRAW_T08_CALC_Y
    sbc #$0C
    jsr DRAW_T08_CALC_X
    jmp DRAW_T08_COMMIT
DRAW_T08_F1:
    lda #$00
    jsr DRAW_T08_CALC_Y
    jsr DRAW_T08_CALC_X
    jmp DRAW_T08_COMMIT
DRAW_T08_F2:
    lda #$02
    jsr DRAW_T08_CALC_Y
    jsr DRAW_T08_CALC_X
    sbc #$15
    jmp DRAW_T08_COMMIT
DRAW_T08_F3:
    lda #$03
    jsr DRAW_T08_CALC_Y
    sbc #$0C
    jsr DRAW_T08_CALC_X
    sbc #$15
DRAW_T08_COMMIT:
    sta SPR_Y_SHADOW
    ldx OBJ_IDX
    dec OBJ_ANIM
    jsr DRAW_DISPATCH_99D8
    lda VIC_SPR_ENA
    ora #$01
    sta VIC_SPR_ENA
    rts
DRAW_T08_CALC_Y:
    sta OBJ_TBL33
    lda VIC_SPR_ENA
    and #$FE
    sta VIC_SPR_ENA
    lda SPR_XMSB
    lsr
    lsr
    lda $CC
    ror
    rol ZTMP_08
    ldx STATE_4D44
    clc
    adc DRAW_T00_F3_TBL,x
    sec
    rts
DRAW_T00_F3_TBL:
    .byte $03,$05,$08
DRAW_T08_CALC_X:
    ror ZTMP_08
    rol
    php
    sta SPR_X_SHADOW
    lda SPR_XMSB
    lsr
    plp
    rol
    sta SPR_XMSB
    lda #$07
    clc
    adc SPAWN_Y
    sec
    rts
DRAW_TBL_T00:
    .word DRAW_T00_F0
    .word DRAW_T00_F1
    .word DRAW_T00_F2
    .word DRAW_T00_F3
    .word DRAW_T00_F4
    .word DRAW_T00_F5
    .word DRAW_T00_F6
    .word DRAW_T00_F7
    .word DRAW_T00_F8
    .word DRAW_T00_F9
DRAW_T00_F0:
    stx STATE_4DAC
    jmp DRAW_T00_TAIL
DRAW_T00_ANIM_TICK:
    dec STATE_9B
DRAW_T00_GATE:
    jmp DRAW_TIMER_GATE
DRAW_T00_F1:
    ldx #$FF
    stx $B3
    lda STATE_4D74
    bne DRAW_T00_F1_STORE
    dec STATE_9B
    inc STATE_4D54
    inx
DRAW_T00_F1_STORE:
    stx $AB
    jmp DRAW_T00_TO_T0A
DRAW_T00_F2:
    lda FLAG_A1
    bne DRAW_T00_GATE
    beq DRAW_T00_ANIM_TICK
DRAW_T00_F3:
    lda #$00
    cmp STATE_4D64
    bne DRAW_T00_F3_ADJUST
    cmp STATE_4D74
    bne DRAW_T00_F3_ADJUST
    cmp STATE_4D6C
    beq DRAW_T00_F4
DRAW_T00_F3_ADJUST:
    jsr SPEED_SET
    lda #$01
    sta $B3
    lda SPAWN_Y
    cmp #$A0
    beq DRAW_T00_ANIM_TICK
    ldx #$00
    lda STATE_4D64
    beq DRAW_T00_F3_INC
    cmp #$03
    beq DRAW_T00_F3_STORE
    cmp #$04
    beq DRAW_T00_F3_STORE
    cmp #$05
    beq DRAW_T00_F3_STORE
    dex
    dex
DRAW_T00_F3_INC:
    inx
DRAW_T00_F3_STORE:
    stx $AB
DRAW_T00_TO_T0A:
    ldx OBJ_IDX
    jsr DRAW_TIMER_GATE
    jmp DRAW_T0A_F0
DRAW_T00_F4:
    lda SCROLL_SPEED
    beq DRAW_T00_F4_STOPPED
    cmp #$01
    beq DRAW_T00_F4_CONT
    dec STATE_4D08
    ldy #$0F
    jsr SPEED_STEP_DOWN
    lda #$00
    sec
    sbc ROAD_X_REF
    sta $B3
    dec $B3
    jmp DRAW_T00_TAIL
DRAW_T00_F4_STOPPED:
    lda #$01
    jsr SPEED_SET
DRAW_T00_F4_CONT:
    lda #$FD
    sta $B3
    lda #$01
    sta $AB
    ldx STATE_4D64
    beq DRAW_T00_TO_T0A
    ldx STATE_4D74
    beq DRAW_T00_TO_T0A
    lda #$00
    sta $AB
    ldx SPAWN_Y
    cpx #$90
    bcs DRAW_T00_TO_T0A
    sta $B3
    dec STATE_9B
    bpl DRAW_T00_TO_T0A
DRAW_T00_F5:
    lda BIT_MASK_INV
    sta HIT_GROUP1
    lda SPEED_ACCUM
    sta STATE_4D54
    lda $C7
    bmi DRAW_T00_F5_HOLD
    cmp #$32
    bcs DRAW_T00_F5_HOLD
    cmp #$1E
    bcc DRAW_T00_F5_TRIGGER
    lda $C6
    and #$7F
    cmp #$01
    bcc DRAW_T00_F5_POS
DRAW_T00_F5_HOLD:
    inc STATE_9B
    bne DRAW_T00_F5_TICK
DRAW_T00_F5_TRIGGER:
    dec STATE_9B
    lda #$04
    sta $A0
    sta STATE_4D05
DRAW_T00_F5_TICK:
    inc STATE_4D07
DRAW_T00_F5_POS:
    dec STATE_4D08
    lda SPAWN_Y
    cmp #$65
    bcs DRAW_T00_F5_DONE
    sec
    lda #$00
    sbc ROAD_X_REF
    bpl DRAW_T00_F5_DONE
    cmp #$F8
    beq DRAW_T00_F5_DONE
    sta $B3
DRAW_T00_F5_DONE:
    jmp DRAW_T00_TAIL
DRAW_T00_F6:
    lda $C7
    bmi DRAW_T00_F6_FAR
    cmp #$31
    bcs DRAW_T00_F5_TICK
    cmp #$27
    bcc DRAW_T00_F6_DONE
    lda $C6
    and #$7F
    cmp #$01
    bcs DRAW_T00_F5_TICK
    sec
    ror ANIM_STATE
    inc STATE_4D54
    inc $B3
    dec STATE_9B
    bne DRAW_T00_F5_TICK
DRAW_T00_F6_FAR:
    and #$7F
    cmp #$35
    bcc DRAW_T00_F6_DONE
    inc STATE_4D07
DRAW_T00_F6_DONE:
    ldx SPEED_ACCUM
    dex
    stx STATE_4D54
    ldx OBJ_IDX
DRAW_T00_TAIL:
    jsr DRAW_TIMER_GATE
    jmp DRAW_PROXIMITY_CHECK
DRAW_T00_F7:
    lda #$58
    sta FLAG_FB
    sta $CC
    lda #$FD
    and SPR_XMSB
    sta SPR_XMSB
    lda SPAWN_Y
    cmp #$F0
    lda #$00
    bcc DRAW_T00_F7_CHECK
    dec STATE_9B
    sta FLAG_FB
DRAW_T00_F7_CHECK:
    dec STATE_4D5C
    bne DRAW_T00_F7_DONE
    sta STATE_9B
DRAW_T00_F7_DONE:
    jmp DRAW_TIMER_GATE
DRAW_T00_F8:
    lda #$DC
    sta FLAG_FB
    sta $CC
    lda #$FD
    and SPR_XMSB
    sta SPR_XMSB
    lda SPAWN_Y
    cmp #$10
    bcs DRAW_T00_F8_CONT
    clc
    adc #$0C
    sta SPAWN_Y
DRAW_T00_F8_CONT:
    lda SEQ_STATE
    cmp #$03
    bne DRAW_T00_F8_SPRY_CHECK
    lda #$04
    sta STATE_9B
    ldx #$00
    stx FLAG_FB
DRAW_T00_F8_DONE:
    ldx OBJ_IDX
    jmp DRAW_TIMER_GATE
DRAW_T00_F8_SPRY_CHECK:
    lda $D003
    cmp #$F0
    bcc DRAW_T00_F8_DONE
    ror HERO_STATE
    rts
DRAW_T00_F9:
    lda #$15
    cmp PREV_FEATURE
    beq DRAW_T00_F9_CONT
    dec OBJ_ANIM,x
DRAW_T00_F9_CONT:
    dec OBJ_ANIM,x
    lda #$00
    sta SPAWN_Y
    sta STATE_4D7C
    sta STATE_4DAC
    rts
DRAW_TBL_T04:
    .word DRAW_T04_F0
    .word DRAW_T04_F1
    .word DRAW_T04_F2
    .word DRAW_T04_F3
DRAW_T04_F0:
    dec $B9
    lda $B9
    cmp #$0A
    bne DRAW_T04_COMMIT
    ror ANIM_STATE
    rts
DRAW_T04_F1:
    lda $A0
    cmp #$01
    beq DRAW_T04_F1_DEC
    cmp #$04
    beq DRAW_T04_F1_DEC
    lda STATE_9B
    cmp #$06
    bcc DRAW_T04_F1_CHECK
DRAW_T04_F1_DEC:
    dec FLAG_A1
DRAW_T04_F1_CHECK:
    lda $B9
    bpl DRAW_T04_COMMIT
DRAW_T04_F2:
    inc $B9
    lda $B9
    cmp #$14
    bne DRAW_T04_COMMIT
DRAW_T04_DEC:
    dec FLAG_A1
DRAW_T04_COMMIT:
    clc
    adc SPAWN_Y
    sta $D9
    lda $CC
    sta $D8
    lda SPR_XMSB
    and #$02
    beq DRAW_T04_XMSB_CLR
    lda #$80
    ora SPR_XMSB
    bne DRAW_T04_XMSB_STORE
DRAW_T04_XMSB_CLR:
    lda #$7F
    and SPR_XMSB
DRAW_T04_XMSB_STORE:
    sta SPR_XMSB
    lda HERO_STATE
    cmp #$04
    bcc DRAW_T04_DONE
    ror ANIM_STATE
DRAW_T04_DONE:
    rts
DRAW_T04_F3:
    lda #$0A
    sta $B9
    bne DRAW_T04_DEC
DRAW_TBL_T05:
    .word DRAW_T05_F0
    .word DRAW_T05_F1
    .word DRAW_T05_F2
    .word DRAW_T05_F3
    .word DRAW_T05_F4
    .word DRAW_STATE_4D89_PREP
DRAW_T05_F0:
    lda OBJ_TBL79
    bne DRAW_T05_F0_CHECK
    sta STATE_4D05
DRAW_T05_F0_CHECK:
    cmp #$09
    bne DRAW_T05_F0_SPEED
    sta STATE_4D05
    ror SCENE_ID
    inc STATE_4DC9
    lda #$03
    sta SEQ_STATE
    rts
DRAW_T05_F0_SPEED:
    jsr DRAW_GATE_CHECK_SPEED
    jmp SPEEDCODE_IMAGE
DRAW_T05_F1:
    lda ANIM_STATE
    bpl DRAW_T05_F1_DONE
    lda #$00
    sta STATE_4D89
    sta STATE_4D0E
    sta STEER_ACCUM
    sta SPEED_ACCUM
    dec $A0
    lda #$02
    sta TIMER_ENABLE
    sta SEQ_STATE
DRAW_T05_F1_DONE:
    rts
DRAW_T05_F2:
    inc SPEED_SUM
    lda SPEED_SUM
    cmp #$D1
    bcc DRAW_T05_F2_DONE
    dec $A0
    lda #$FF
    ldx HERO_STATE
    beq DRAW_T05_F2_DONE
    dex
    beq DRAW_T05_F2_GUNHEAT
    dex
    beq DRAW_T05_F2_SMOKE
    sta MISSILE_CNT
    rts
DRAW_T05_F2_SMOKE:
    sta SMOKE_CNT
    rts
DRAW_T05_F2_GUNHEAT:
    clc
    lda GUN_HEAT
    adc #$03
    sta GUN_HEAT
DRAW_T05_F2_DONE:
    rts
DRAW_T05_F3:
    lda ANIM_STATE
    cmp #$04
    bne DRAW_T05_F3_MERGE
    lda FLAG_A1
    cmp #$01
    bne DRAW_T05_F3_MERGE
    dec $A0
DRAW_T05_F3_MERGE:
    lda #$0A
DRAW_ENTRY_9322:
    clc
    adc SPAWN_Y
    sta SPEED_SUM
DRAW_T05_STEER_UPDATE:
    lda $CC
    sta STEER_SUM
    lda SPR_XMSB
    and #$02
    beq DRAW_T05_XMSB_CLR
    lda #$40
    ora SPR_XMSB
    bne DRAW_T05_XMSB_STORE
DRAW_T05_XMSB_CLR:
    lda #$BF
    and SPR_XMSB
DRAW_T05_XMSB_STORE:
    sta SPR_XMSB
    rts
DRAW_T05_F4:
    lda SPEED_SUM
    sbc #$0A
    cmp SPAWN_Y
    bcc DRAW_T05_F4_START
    dec SPEED_SUM
    dec SPEED_SUM
    bcs DRAW_T05_STEER_UPDATE
DRAW_T05_F4_START:
    ldx #$00
    stx TIMER_ENABLE
    inx
    stx SEQ_STATE
    sec
    ror SCENE_ID

MUSIC_START_THEME:
    jsr SOUND_SILENCE
    ldy #$02
    jsr SOUND_REQ_V1
    ldy #$04
    jsr SOUND_REQ_V0B
    ldy #$06
    jmp SOUND_REQ_V2
; -----------------------------------------------------------------------
; Per-object DRAW handlers for enemy/effect OBJ_TYPEs $06/$09-$1B (dispatched
; via OBJINIT_PARAM_TBL's draw-vector column -> ZVEC_DRAW -> OBJ_VEC2_DISPATCH,
; Stage 5). This was the largest remaining raw-data block in the file
; (~1650 bytes). Each TYPE's draw entry points at a small per-animation-frame
; address table (DRAW_TBL_T*, indexed by OBJ_ANIM*2 through the two-stage
; ZVEC_DRAW indirection documented at PROCESS_OBJECTS) rather than at code
; directly - several tables/frame routines are shared between adjacent TYPE
; values (e.g. DRAW_TBL_T0E covers TYPE $0E/$0F/$10; DRAW_TBL_T14 covers
; TYPE $14/$17). TYPE $12/$13 (DRAW_TBL_T12) is the confirmed boat/water
; enemy pair; TYPE $1B (DRAW_TBL_T1B) is the confirmed live-bullet type from
; claude/Collision_Detection_Notes.md - both draw tables live here.
;
; DRAW_STATE_4D89_PREP ($9368, the block's first bytes) is NOT one of
; OBJINIT_PARAM_TBL's dispatch targets - nothing in the ROM JSR/JMPs to it
; directly, so it's reached some other way (candidate: the panel/HUD's own
; speed or boat-wake indicator, since it reads SPEED_SUM/STEER_ACCUM - not
; confirmed). It falls through into DRAW_T0A_F0.
;
; Individual TYPE semantics (which enemy/effect each one draws) are not
; interpreted here - deep semantic identification of enemy OBJ_TYPEs is
; tracked separately (claude/*.md, the open "pin down remaining enemy
; OBJ_TYPE values" item). Three "BIT-absolute/zp as a 2-byte skip" overlap
; tricks (same idiom as SPEED_STEP_DOWN/UP and MOVE_BOAT_SEQ_LO/ARM) are kept
; as raw bytes with labels at each entry point.
DRAW_STATE_4D89_PREP:
    lda SPEED_SUM
    cmp #$23
    bcc DRAW_PREP_ARM_BOAT
    cmp #$DC
    bcc DRAW_PREP_FRAME_CHECK
DRAW_PREP_ARM_BOAT:
    inc STATE_4D89
DRAW_PREP_FRAME_CHECK:
    lda FRAME_CTR
    lsr
    bcc DRAW_PREP_DONE
    lda #$07
    dec STATE_4D0E
    bpl DRAW_PREP_STEER_CHECK
    sta STATE_4D0E
DRAW_PREP_STEER_CHECK:
    ldy STEER_ACCUM
    bpl DRAW_PREP_CALC_INDEX
    lda STATE_4D0E
    asl
DRAW_PREP_CALC_INDEX:
    sec
    sbc STATE_4D0E
    tay
    lda DRAW_STATE_4D89_PREP_TBL,y
    jsr COMMIT_SPRITE_OFS
DRAW_PREP_DONE:
    jmp DRAW_T0A_F0
DRAW_STATE_4D89_PREP_TBL:
    .byte $00,$09,$05,$0B,$02,$0A,$04,$08
DRAW_TBL_T06:
    .word DRAW_T06_F0
    .word DRAW_T06_F1
    .word DRAW_T06_F2
DRAW_T06_F0:
    lda OBJ_TBL79
    cmp #$09
    bne DRAW_T06_F0_CHECK
    inc $A0
    inc STATE_4DC9
    sta STATE_4D05
    lda #$03
    sta SEQ_STATE
    rts
DRAW_T06_F0_CHECK:
    lda #$15
    cmp ROAD_FEATURE
    beq DRAW_T06_F0_ARM
    cmp PREV_FEATURE
    bne DRAW_T06_F0_DONE
    lda ROAD_FEATURE
    cmp #$0F
    bne DRAW_T06_F0_DONE
DRAW_T06_F0_ARM:
    lda STATE_4DB9
    cmp #$13
    bcc DRAW_T06_F0_DONE
    sta STATE_4D05
    ldy #$00
    sty STATE_4D61
    cmp #$19
    beq DRAW_T06_F0_IDX_STORE
    bcc DRAW_T06_F0_IDX_INC
    dey
    dey
DRAW_T06_F0_IDX_INC:
    iny
DRAW_T06_F0_IDX_STORE:
    sty STATE_4D0A
    ldy HERO_STATE
    cmp #$07
    bne DRAW_T06_F0_SPAWN
    sty STATE_4DAC
    inc SPAWN_Y
DRAW_T06_F0_SPAWN:
    ldy #$00
    lda SCROLL_SPEED
    cmp #$02
    beq DRAW_T06_F0_SPEED_STORE
    bcc DRAW_T06_F0_SPEED_INC
    dey
    dey
DRAW_T06_F0_SPEED_INC:
    iny
DRAW_T06_F0_SPEED_STORE:
    sty JOY_STATE
DRAW_T06_F0_DONE:
    jsr DRAW_CHECK_BLANK
    jmp SPEEDCODE_IMAGE
DRAW_T06_F1:
    lda SEQ_STATE
    cmp #$05
    beq DRAW_T06_F1_SEQ5
    lda ROAD_X_REF
    eor #$FF
    clc
    adc #$01
    sta SPEED_ACCUM
    lda OBJ_TBL79
    bne DRAW_T06_F1_WATER
    sec
    ror SCENE_ID
    lda #$01
    sta SEQ_STATE
    jmp DRAW_T06_F0_DONE
DRAW_T06_F1_WATER:
    cmp #$02
    bne DRAW_T06_F0_DONE
    dec $A0
    lda #$04
    sta SEQ_STATE
    lsr
    sta STATE_4D81
    lda #$00
    sta STATE_4DCB
    sta STATE_4D89
    sta STATE_4D05
    beq DRAW_T06_F0_DONE
DRAW_T06_F1_SEQ5:
    inc $A0
DRAW_T06_F2:
    lda #$22
    jmp DRAW_ENTRY_9322
DRAW_TBL_T09:
    .word DRAW_T09_F0
    .word DRAW_T09_F1
    .word DRAW_T09_F2
DRAW_T09_F0:
    lda #$01
    sta STATE_4DAC
    jmp DRAW_PROXIMITY_CHECK
DRAW_T09_F1:
    inc STATE_4D08
    lda $C7
    bmi DRAW_T09_F1_DONE
    cmp #$04
    bcs DRAW_T09_F1_DONE
    lda #$00
    sec
    sbc ROAD_X_REF
    sta OBJ_POS_Y,x
    dec STATE_4D08
    dec STATE_4D08
DRAW_T09_F1_DONE:
    jmp DRAW_PROXIMITY_CHECK
DRAW_T09_F2:
    dec STATE_9B
    ldx #$01
    stx $B3
    rts
DRAW_TBL_T0A:
    .word DRAW_T0A_F0
    .word DRAW_T0A_F1
    .word DRAW_T0A_F2
DRAW_T0A_F2:
    dec OBJ_ANIM
    bne DRAW_T0A_SET_COLOR
DRAW_T0A_F1:
    jsr DRAW_T0A_CALC_Y
    lda $B3
    sta OBJ_POS_Y
    lda $C7
    bpl DRAW_T0A_SET_COLOR
    and #$7F
    cmp #$28
    bcc DRAW_T0A_TRIGGER
DRAW_T0A_SET_COLOR:
    lda #$06
    sta VIC_SPR_COLOR
    lda SPR_XMSB
    lsr
    lsr
    php
    rol
    plp
    rol
    sta SPR_XMSB
    lda $CC
    clc
    adc #$04
    sta SPR_X_SHADOW
    bcc DRAW_T0A_CALC_Y
    lda BIT_MASK
    ora SPR_XMSB
    sta SPR_XMSB
DRAW_T0A_CALC_Y:
    lda SPAWN_Y
    clc
    adc #$0F
    sta SPR_Y_SHADOW
    rts
DRAW_T0A_TRIGGER:
    cmp #$14
    bcs DRAW_T0A_SET_COLOR2
    ldy #$0C
    jsr SOUND_REQ_V1
    dec OBJ_ANIM
    lda SCENE_ID
    bpl DRAW_T0A_SET_COLOR2
    dec STATE_9B
DRAW_T0A_SET_COLOR2:
    lda #$0A
    sta VIC_SPR_COLOR
    lda $C6
    bpl DRAW_T0A_POS_RIGHT
    lda #$F6
    sta OBJ_POS_X
    lda $CC
    sec
    sbc #$02
    sta SPR_X_SHADOW
    bcs DRAW_T0A_DONE
    lda SPR_XMSB
    lsr
    asl
    sta SPR_XMSB
    rts
DRAW_T0A_POS_RIGHT:
    lda #$0A
    sta OBJ_POS_X
    lda $CC
    clc
    adc #$0A
    sta SPR_X_SHADOW
    bcc DRAW_T0A_DONE
    lda SPR_XMSB
    ora BIT_MASK
    sta SPR_XMSB
DRAW_T0A_DONE:
    rts
DRAW_TBL_T0B:
    .word DRAW_T0B_F0
    .word DRAW_T0B_F1
DRAW_TBL_T1B:
    .word DRAW_T0B_F2
    .word DRAW_T0B_F1
DRAW_T0B_F2:
    lda #$FB
    pha
    lda $BC
    bmi DRAW_T0B_F2_ALT
    lda #$02
    .byte $2C
DRAW_T0B_F2_ALT:
    .byte $A9,$FE
    sta $B1
    lda #$78
    bne DRAW_T0B_CHECK
DRAW_T0B_F0:
    lda #$ED
    pha
    lda #$50
DRAW_T0B_CHECK:
    cmp $D9
    bcc DRAW_T0B_COMMIT
    ror ANIM_STATE
DRAW_T0B_COMMIT:
    pla
    jmp DRAW_ADJUST_POS_Y
DRAW_T0B_F1:
    dec FLAG_A1
    lda STEER_ACCUM
    sta $B1
    lda SPR_XMSB
    asl
    asl
    php
    ror
    plp
    ror
    sta SPR_XMSB
    lda STEER_SUM
    sta $D8
    lda SPEED_SUM
    sta $D9
    ldy #$10
    lda ANIM_STATE
    cmp #$0B
    beq DRAW_T0B_F1_DONE
    ldy #$22
DRAW_T0B_F1_DONE:
    jmp SOUND_REQ_V2
DRAW_TBL_T0C:
    .word DRAW_T0C_F0
DRAW_T0C_F0:
    lda $C7
    bmi DRAW_T0C_CHECK_TYPE
    cmp #$0F
    bcs DRAW_T0C_TICK
    inc OBJ_TBLAB,x
    lda STATE_4D05
    bne DRAW_T0C_TICK
    inc STATE_4D07
DRAW_T0C_TICK:
    inc STATE_4D08
DRAW_T0C_CHECK_TYPE:
    lda OBJ_TYPE,x
    cmp #$0D
    bne DRAW_T0C_DONE
    jsr DRAW_PROX_SOUND
DRAW_T0C_DONE:
    jmp DRAW_PROXIMITY_CHECK
DRAW_TBL_T0E:
    .word DRAW_T0E_F0
    .word DRAW_T0E_F1
    .word DRAW_T0E_F2
DRAW_T0E_F0:
    lda $C7
    and #$7F
    cmp #$14
    bcs DRAW_T0E_F0_DONE
    lda #$01
    sta OBJ_TBLAB,x
DRAW_T0E_F0_DONE:
    jmp DRAW_PROXIMITY_CHECK
DRAW_T0E_F1:
    dec OBJ_TBL5B,x
    bne DRAW_T0E_F1_TICK
    inc STATE_4D83,x
DRAW_T0E_F1_TICK:
    lda FRAME_CTR
    lsr
    lsr
    and #$03
    tay
    lda DRAW_T0E_F2_TBL,y
    cmp OBJ_TBL33,x
    beq DRAW_T0E_F1_DONE
    jsr DRAW_STORE_OFS
    lda DRAW_T0E_F2_TBL+4,y
    ldy OBJ_IDX2
    clc
    adc SPR_X_SHADOW,y
    sta SPR_X_SHADOW,y
DRAW_T0E_F1_DONE:
    ldy OBJ_IDX2
    bpl DRAW_T0E_F0
DRAW_T0E_F2_TBL:
    .byte $01,$00,$02,$00,$F8,$08,$06,$FA
DRAW_T0E_F2:
    dec OBJ_ANIM,x
    lda #$3C
    sta OBJ_TBL5B,x
    bne DRAW_T0E_F1
DRAW_TBL_T11:
    .word DRAW_T11_F0
    .word DRAW_T11_F1
DRAW_T11_F0:
    lda HIT_GROUP2
    and BIT_MASK_INV
    sta HIT_GROUP2
    lda #$00
    dec STATE_4D5C
    bne DRAW_T11_DONE
    beq DRAW_T11_TRIGGER
DRAW_T11_F1:
    lda FLAG_FC
    bne DRAW_T11_TRIGGER
    lda #$0F
    sta STATE_4D5C
    lda SPAWN_Y
    cmp #$F3
    txa
    sta FLAG_FB
    bcc DRAW_T11_DONE
DRAW_T11_TRIGGER:
    sec
    ror HERO_STATE
DRAW_T11_DONE:
    jmp COMMIT_SPRITE_OFS
DRAW_TBL_T12:
    .word DRAW_T12_F0
    .word DRAW_T12_F1
DRAW_T12_F0:
    lda $C7
    bmi DRAW_T12_HAZARD
    inc STATE_4D07
DRAW_T12_HAZARD:
    jsr DRAW_HAZARD_ENTRY
    jmp DRAW_PROXIMITY_SCAN
DRAW_T12_F1:
    lda STATE_4D05
    bne DRAW_T12_F0
    lda OBJ_TBL5B,x
    bmi DRAW_T12_F1_CHECK
    inc OBJ_TBL5B,x
    bpl DRAW_T12_F0
DRAW_T12_F1_CHECK:
    lda $C7
    bmi DRAW_T12_HAZARD
    lda $C6
    and #$7F
    cmp #$0F
    bcs DRAW_T12_F0
    jsr ATTRACT_HELPER_ADVANCE_B
    lda #$26
    sta OBJ_TBL5B,x
    sta OBJ_TBLAB,x
    bpl DRAW_T12_F0
DRAW_TBL_T14:
    .word DRAW_T14_F0
    .word DRAW_T14_F1
    .word DRAW_T14_F2
DRAW_T14_F0:
    dec OBJ_TBL5B,x
    bne DRAW_T14_TICK
    sec
    ror OBJ_TYPE,x
DRAW_T14_TICK:
    lda FRAME_CTR
    and #$03
    pha
    jsr COMMIT_SPRITE_OFS
    pla
    bne DRAW_T14_DONE
    inc OBJ_POS_Y,x
    bmi DRAW_T14_DONE
    beq DRAW_T14_DONE
    dec OBJ_POS_Y,x
DRAW_T14_DONE:
    jmp DRAW_T0A_F0
DRAW_T14_F1:
    lda #$1E
    sta OBJ_TBL5B,x
    dec OBJ_ANIM,x
    bpl DRAW_T14_TICK
DRAW_T14_F2:
    lda #$01
    jsr SPEED_SET
    lda #$FE
    sta OBJ_POS_Y,x
DRAW_T15_F5:
    lda SPEED_SUM
    sta $D9
    lda STEER_SUM
    sta $D8
    lda SPR_XMSB
    asl
    sec
    bmi DRAW_T15_F5_SIGN
    clc
DRAW_T15_F5_SIGN:
    ror
    sta SPR_XMSB
    dec OBJ_ANIM,x
    rts
DRAW_TBL_T15:
    .word DRAW_T15_F0
    .word DRAW_T15_F1
    .word DRAW_T15_F2
    .word DRAW_T15_F3
    .word DRAW_T15_F4
    .word DRAW_T15_F5
DRAW_T15_F0:
    lda #$01
    sta OBJ_TBLAB,x
    jmp DRAW_T0A_F0
DRAW_T15_F1:
    dec OBJ_TBL5B,x
    lda OBJ_TBL5B,x
    and #$07
    beq DRAW_T15_F1_DONE
    rts
DRAW_T15_F1_DONE:
    dec OBJ_ANIM,x
    lda SPR_Y_SHADOW,y
    clc
    adc #$05
    sta SPR_Y_SHADOW,y
    lda #$8B
    jmp SET_SPRITE_PTR
DRAW_T15_F2:
    dec OBJ_TBL5B,x
    lda OBJ_TBL5B,x
    and #$07
    beq DRAW_T15_F2_DONE
    rts
DRAW_T15_F2_DONE:
    dec OBJ_ANIM,x
    lda #$04
    sta VIC_SPR_COLOR,x
    lda #$8A
    jmp SET_SPRITE_PTR
DRAW_T15_F3:
    dec OBJ_TBL5B,x
    lda OBJ_TBL5B,x
    and #$07
    bne DRAW_T15_F3_CHECK
    lda #$01
    jsr SPEED_SET
    dec OBJ_ANIM,x
    lda #$89
    jmp SET_SPRITE_PTR
DRAW_T15_F3_CHECK:
    and #$03
    bne DRAW_T15_F3_DONE
DRAW_T15_SPEED_TICK:
    ldy #$07
    jsr SPEED_STEP_DOWN
    lda #$00
DRAW_T15_F3_DONE:
    jmp COMMIT_SPRITE_OFS
DRAW_T15_F4:
    jsr SOUND_SILENCE
    ldy #$1E
    jsr SOUND_REQ_V2
    ldy OBJ_IDX2
    lda #$2F
    sta OBJ_TBL5B,x
    dec OBJ_ANIM,x
    bpl DRAW_T15_SPEED_TICK
DRAW_TBL_T16:
    .word DRAW_T16_F0
    .word DRAW_T16_F1
    .word DRAW_T16_F2
    .word DRAW_T15_F5
DRAW_T16_F0:
    dec OBJ_TBL5B,x
    bne DRAW_T16_SPEED
    sec
    ror OBJ_TYPE,x
    bne DRAW_T16_DONE
DRAW_T16_F1:
    dec OBJ_TBL5B,x
    bne DRAW_T16_SPEED
    lda #$1E
    sta OBJ_TBL5B,x
    dec OBJ_ANIM,x
    dec SPRITE_PTRS,x
DRAW_T16_SPEED:
    lda #$01
    jsr SPEED_SET
DRAW_T16_DONE:
    jmp DRAW_T0A_F0
DRAW_T16_F2:
    lda #$1E
    sta OBJ_TBL5B,x
    dec OBJ_ANIM,x
    bpl DRAW_T16_F1
DRAW_TBL_T18:
    .word DRAW_T18_F0
    .word DRAW_T18_F1
    .word DRAW_T18_F2
DRAW_T18_F0:
    lda ROAD_FEATURE
    cmp #$15
    bne DRAW_T18_F0_CHECK
    dec STATE_4D08
    lda #$01
    sta $B3
DRAW_T18_F0_CHECK:
    lda #$01
    sta STATE_4DAC
    bne DRAW_T18_DONE
DRAW_T18_F2:
    lda #$F4
    sta SPEED_SUM
    lda #$01
    jsr SPEED_SET
    inc STATE_4D5C
    bmi DRAW_T18_F2_TRIGGER
    rts
DRAW_T18_F2_TRIGGER:
    ldy #$20
    jsr SOUND_REQ_V0B
    dec STATE_9B
DRAW_T18_F1:
    lda SPAWN_Y
    cmp #$A0
    bcs DRAW_T18_F1_ALT
    dec STATE_9B
    lda #$04
    sta SEQ_STATE
    lda #$01
    .byte $2C
DRAW_T18_F1_ALT:
    .byte $A9,$02
    sta $A0
DRAW_T18_DONE:
    jsr DRAW_HAZARD_ENTRY_B
    lda #$00
    sta $AB
    jmp DRAW_PROXIMITY_SCAN
DRAW_TBL_T19:
    .word DRAW_T19_F0
    .word DRAW_T19_F1
DRAW_T19_F0:
    lda SPR_XMSB
    lsr
    pha
    lsr
    lda $CC
    ror
    php
    clc
    adc #$04
    plp
    rol
    sta SPR_X_SHADOW
    pla
    rol
    sta SPR_XMSB
    inc OBJ_ANIM
    lda #$06
    sta OBJ_POS_Y
    lda #$14
    sta OBJ_TBL5B
DRAW_T19_F1:
    inc OBJ_POS_Y
    dec OBJ_TBL5B
    bne DRAW_T19_F1_POS
    dec OBJ_ANIM
DRAW_T19_F1_POS:
    clc
    lda SPAWN_Y
    adc OBJ_POS_Y
    sta SPR_Y_SHADOW
    lda HERO_STATE
    cmp #$18
    beq DRAW_T19_DONE
    sec
    ror OBJ_TYPE
DRAW_T19_DONE:
    rts
DRAW_TBL_T1A:
    .word DRAW_T1A_F0
    .word DRAW_T1A_F1
DRAW_T1A_F0:
    lda HIT_GROUP2
    ora #$01
    sta HIT_GROUP2
    lda #$01
    sta OBJ_TBLAB
    sta STATE_4DAE
    jmp DRAW_T0A_F0
DRAW_T1A_F1:
    lda SPR_XMSB
    and #$08
    clc
    beq DRAW_T1A_F1_SIGN
    sec
DRAW_T1A_F1_SIGN:
    php
    lda SPR_XMSB
    lsr
    plp
    rol
    lda $D0
    clc
    adc #$08
    sta SPR_X_SHADOW
    lda $D1
    clc
    adc #$05
    sta SPR_Y_SHADOW
    lda $C7
    bpl DRAW_T1A_F1_DONE
    lda #$FA
    sta OBJ_POS_Y
    lda $C6
    and #$7F
    cmp #$04
    bcs DRAW_T1A_F1_DONE
    dec OBJ_ANIM
    ldy #$2A
    jsr SOUND_REQ_V1
DRAW_T1A_F1_DONE:
    rts
DRAW_PROXIMITY_CHECK:
    lda ROAD_FEATURE
    cmp #$03
    bne DRAW_PROXIMITY_SCAN
    inc OBJ_POS_Y,x
DRAW_PROXIMITY_SCAN:
    ldy #$0C
    lda OBJ_TYPE,x
    cmp #$04
    bcs DRAW_PROX_SETUP
    ldy #$0E
DRAW_PROX_SETUP:
    sty ZTMP_09
    ldy #$00
    sty ZTMP_08
    sty ZTMP_0B
    iny
    bne DRAW_PROX_LOOP
DRAW_PROX_SKIP:
    plp
DRAW_PROX_LOOP:
    iny
    cpy ZTMP_09
    beq DRAW_PROX_DONE
    cpy OBJ_IDX2
    bne DRAW_PROX_TEST
    iny
    bne DRAW_PROX_LOOP
DRAW_PROX_TEST:
    lda SPR_STAGE,y
    iny
    asl
    php
    lsr
    cmp #$15
    bcs DRAW_PROX_SKIP
    lsr ZTMP_0B
    plp
    rol ZTMP_0B
    lda SPR_STAGE,y
    asl
    php
    lsr
    cmp #$23
    bcs DRAW_PROX_SKIP
    plp
    bcc DRAW_PROX_LOOP
    rol ZTMP_08
DRAW_PROX_DONE:
    ldy OBJ_IDX2
    lda STATE_4D07
    bne DRAW_PROX_STATE_CHECK
    lda FRAME_CTR
    lsr
    bcc DRAW_PROX_STATE_CHECK
    jmp DRAW_T0A_F0
DRAW_PROX_STATE_CHECK:
    lda OBJ_TBL8B,x
    beq DRAW_PROX_DISPATCH
    lda OBJ_POS_X,x
    bne DRAW_PROX_NUDGE_DONE
    inc OBJ_POS_X,x
DRAW_PROX_NUDGE_DONE:
    jmp DRAW_T0A_F0
DRAW_PROX_DISPATCH:
    lda ZTMP_08
    beq DRAW_MOVE_ENTRY
    lda ZTMP_0B
    beq DRAW_MOVE_X_NEG
    lda OBJ_TBL6B,x
    cmp OBJ_TBL7B,x
    bne DRAW_MOVE_Y_CHECK
DRAW_MOVE_X_POS:
    lda OBJ_POS_X,x
    bmi DRAW_MOVE_X_INC
    cmp OBJ_TBL43,x
    beq DRAW_MOVE_X_DONE_POS
    bcs DRAW_MOVE_X_DEC
DRAW_MOVE_X_INC:
    inc OBJ_POS_X,x
DRAW_MOVE_X_DONE_POS:
    jmp DRAW_T0A_F0
DRAW_MOVE_X_NEG:
    lda OBJ_TBL63,x
    cmp OBJ_TBL7B,x
    bne DRAW_MOVE_Y_CHECK
DRAW_MOVE_X_CHECK:
    lda OBJ_POS_X,x
    cmp OBJ_TBL3B,x
    beq DRAW_MOVE_X_DONE_NEG
    bmi DRAW_MOVE_X_INC
DRAW_MOVE_X_DEC:
    dec OBJ_POS_X,x
DRAW_MOVE_X_DONE_NEG:
    jmp DRAW_T0A_F0
DRAW_MOVE_Y_CHECK:
    lda OBJ_POS_Y,x
    cmp OBJ_TBL4B,x
    bpl DRAW_MOVE_X_SIGN
    inc OBJ_POS_Y,x
DRAW_MOVE_X_SIGN:
    lda OBJ_POS_X,x
    beq DRAW_T0A_F0
    bmi DRAW_MOVE_X_INC
    bpl DRAW_MOVE_X_DEC
DRAW_MOVE_ENTRY:
    lda STATE_4D08
    bmi DRAW_MOVE_DISPATCH
    clc
    beq DRAW_MOVE_FRAME_GATE
    sec
DRAW_MOVE_FRAME_GATE:
    lda FRAME_CTR
    and #$07
    bne DRAW_MOVE_DISPATCH
    bcs DRAW_MOVE_PROXIMITY
DRAW_MOVE_Y_ALT:
    lda OBJ_POS_Y,x
    cmp OBJ_TBL53,x
    bmi DRAW_MOVE_Y_INC
    dec OBJ_POS_Y,x
    jmp DRAW_MOVE_DISPATCH
DRAW_MOVE_Y_INC:
    inc OBJ_POS_Y,x
DRAW_MOVE_DISPATCH:
    lda OBJ_TBL63,x
    cmp OBJ_TBL7B,x
    bne DRAW_MOVE_X_POS
    lda OBJ_TBL6B,x
    cmp OBJ_TBL7B,x
    bne DRAW_MOVE_X_CHECK
    lda STATE_4D07
    beq DRAW_MOVE_X_SIGN
    lda $C6
    beq DRAW_MOVE_X_SIGN
    bpl DRAW_MOVE_X_POS
    bmi DRAW_MOVE_X_CHECK
DRAW_MOVE_PROXIMITY:
    lda $C7
    beq DRAW_MOVE_DISPATCH
    bmi DRAW_MOVE_Y_ALT
    cmp #$05
    bcc DRAW_MOVE_DISPATCH
    lda #$00
    sec
    sbc ROAD_X_REF
    cmp OBJ_POS_Y,x
    bmi DRAW_MOVE_DISPATCH
    lda OBJ_POS_Y,x
    cmp OBJ_TBL4B,x
    bpl DRAW_MOVE_DISPATCH
    inc OBJ_POS_Y,x
    jmp DRAW_MOVE_DISPATCH
DRAW_ADJUST_POS_Y:
    sec
    sbc ROAD_X_REF
    sta OBJ_POS_Y,x
DRAW_T0A_F0:
    ldx OBJ_IDX
    ldy OBJ_IDX2
    lda OBJ_POS_X,x
    php
    clc
    adc SPR_X_SHADOW,y
    sta SPR_X_SHADOW,y
    bcs DRAW_T0A_XMSB_CHECK
    plp
    bmi DRAW_T0A_XMSB_TOGGLE
    bpl DRAW_T0A_Y_POS
DRAW_T0A_XMSB_CHECK:
    plp
    bmi DRAW_T0A_Y_POS
DRAW_T0A_XMSB_TOGGLE:
    lda BIT_MASK
    eor SPR_XMSB
    sta SPR_XMSB
DRAW_T0A_Y_POS:
    lda OBJ_TBL73,x
    bpl DRAW_T0A_TBL73_CHECK
    sec
    ror OBJ_TYPE,x
DRAW_T0A_TBL73_CHECK:
    lda OBJ_POS_Y,x
    pha
    lda SPR_Y_SHADOW,y
    tax
    pla
    clc
    adc SPR_Y_SHADOW,y
    clc
    adc ROAD_X_REF
    cpx #$0C
    bcc DRAW_T0A_Y_LOW
    cpx #$F3
    bcc DRAW_T0A_Y_STORE
    cmp #$E9
    jsr DRAW_T0A_CLEAR_FLAG
    bcc DRAW_T0A_Y_DONE
    bcs DRAW_T0A_Y_STORE
DRAW_T0A_Y_LOW:
    cmp #$16
    jsr DRAW_T0A_CLEAR_FLAG
    bcs DRAW_T0A_Y_DONE
DRAW_T0A_Y_STORE:
    sta SPR_Y_SHADOW,y
DRAW_T0A_Y_DONE:
    rts
DRAW_T0A_CLEAR_FLAG:
    php
    pha
    ldx OBJ_IDX
    lda OBJ_TBLAB,x
    beq DRAW_T0A_CLEAR_DONE
    lda #$00
    sta OBJ_TBLAB,x
    sec
    ror OBJ_TYPE,x
DRAW_T0A_CLEAR_DONE:
    pla
    plp
    rts
DRAW_TIMER_GATE:
    lda FRAME_CTR
    and #$03
    beq DRAW_GATE_CHECK
    rts
DRAW_GATE_CHECK:
    lda STATE_9B
    cmp #$02
    lda #$04
    bcc DRAW_GATE_DONE
    eor STATE_4D34
    bpl DRAW_GATE_DONE
DRAW_GATE_CHECK_SPEED:
    lda SCROLL_SPEED
    beq DRAW_GATE_DONE
    lda OBJ_TBL79
    beq DRAW_GATE_DONE
    ldy #$0E
    jsr SOUND_REQ_V2_SAFE
    lda STATE_4D39
    eor #$01
DRAW_GATE_DONE:
    jmp DRAW_STORE_OFS
DRAW_CHECK_BLANK:
    lda $A0
    beq DRAW_CALC_BLINK
    lda #$95
    bne SET_SPRITE_PTR
DRAW_CALC_BLINK:
    sec
    lda #$04
    sbc SCROLL_SPEED
    tay
    lda #$00
DRAW_BLINK_LOOP:
    dey
    bmi DRAW_BLINK_APPLY
    sec
    rol
    bne DRAW_BLINK_LOOP
DRAW_BLINK_APPLY:
    and FRAME_CTR
    bne DRAW_DISPATCH_99D8
    dec STATE_4D39
    bpl DRAW_DISPATCH_99D8
    lda #$02
    sta STATE_4D39
    bpl DRAW_DISPATCH_99D8
DRAW_PROX_SOUND:
    ldy OBJ_IDX2
    lda SEQ_STATE
    cmp #$02
    bcc DRAW_ZERO_OFS
    lda $C7
    and #$7F
    cmp #$1E
    bcs DRAW_ZERO_OFS
    ldy #$18
    jsr SOUND_REQ_V0
DRAW_DISPATCH_99CB:
    dec OBJ_TBL33,x
    bpl DRAW_DISPATCH_99D8
    lda #$02
    .byte $2C
DRAW_ZERO_OFS:
    .byte $A9,$00
DRAW_STORE_OFS:
    sta OBJ_TBL33,x
DRAW_DISPATCH_99D8:
    lda OBJ_TBL33,x
COMMIT_SPRITE_OFS:
    clc
    adc OBJ_TBL23,x

SET_SPRITE_PTR:
    sta SPRITE_PTRS,x
    rts
; -----------------------------------------------------------------------
; Per-object-type MOVE handlers for several less-common OBJ_TYPEs, plus the
; shared hazard-check and sprite-proximity-collision primitives they call.
; Reached only indirectly via OBJINIT_PARAM_TBL's move-vector column
; (Stage 5) - manually disassembled this session from two confirmed
; VICE-snapshot program-counter entry points ($992C in become-boat.vsf,
; $9820 in weapon-oil-used.vsf). See claude/Collision_Detection_Notes.md for
; the full trace, including the confirmed finding that CONSUME_HIT_MASK_BIT/
; CONSUME_HIT_MASK_A/HIT_RESOLVE_* below is where HIT_MASK_A/HIT_MASK_B
; (built per-frame in PROCESS_OBJECTS, Stage 5) finally get consumed, and
; that SCORE_EVENT gets queued from ARM_SCORE_EVENT.
;
; DRAW_HAZARD_ENTRY: a frame-parity dispatcher into the DRAW-side sprite-
; offset commit tail (DRAW_DISPATCH_99D8/DRAW_DISPATCH_99CB/COMMIT_SPRITE_OFS,
; in the per-object draw-handler block above) - called from DRAW_T12 (the
; boat/water-type draw frames) as their hazard-check entry point. Not part
; of any MOVE handler here despite sitting right before one.
DRAW_HAZARD_ENTRY:
    lda FRAME_CTR
    and #$03
    bne DRAW_DISPATCH_99D8
    beq DRAW_DISPATCH_99CB
DRAW_HAZARD_ENTRY_B:
    lda FRAME_CTR
    and #$01
    bpl COMMIT_SPRITE_OFS
; Type $05/$06 MOVE handler - the boat. STATE_4D05 is a per-boat "crash/
; special-sequence in progress" flag; STATE_4DB9 is the same blit-column
; state var UPDATE_WEAPONS uses.
MOVE_TYPE_05_06:
    lda STATE_4D05
    beq MOVE_BOAT_MAIN
    lda STATE_4DB9
    cmp #$04
    bcc MOVE_BOAT_MAIN
    cmp #$23
    bcs MOVE_BOAT_MAIN
    lda #$00
    sta STATE_4D89
MOVE_BOAT_RTS:
    rts
; Reset both sequence flags, then run the environmental-hazard check chain
; (HAZARD_CHECK_* below) against this boat's nearby tile-classification
; codes (OBJ_TBL63/6B/73,x - populated per frame by OBJ_CALC_SCREEN_POS,
; Stage 5). OBJ_TBL79 is read directly here (not ,x-indexed) - not fully
; explained.
MOVE_BOAT_MAIN:
    lda #$00
    sta STATE_4DCB
    sta STATE_4D05
    lda OBJ_TBL79
    bmi MOVE_BOAT_CRASH
    cmp #$09
    beq MOVE_BOAT_RTS
    lda STATE_4D89
    bne MOVE_BOAT_CRASH
    jsr HAZARD_CHECK_0A
    beq MOVE_BOAT_CRASH
    jsr HAZARD_CHECK_0C
    beq MOVE_BOAT_CONTINUE
    jsr HAZARD_CHECK_0B
    beq MOVE_BOAT_CONTINUE
    jsr HAZARD_CHECK_CHAIN
    beq MOVE_BOAT_CRASH
    jsr HAZARD_CHECK_07
    bne MOVE_BOAT_CONTINUE
    jsr SEGMENT_FX_HELPER
; No hazard hit this frame - just continue (consume HIT_MASK_A for this slot).
MOVE_BOAT_CONTINUE:
    jmp CONSUME_HIT_MASK_A
; A hazard WAS hit: clear all ammo, and - CONFIRMED by reading this code -
; decrement LIVES unless the game timer has already expired
; (EXTRA_LIFE_AVAIL nonzero). This directly answers the open question in
; claude/Boat_River_Notes.md: crashing into a water hazard costs a life.
MOVE_BOAT_CRASH:
    ldx #$00
    stx GUN_HEAT
    stx MISSILE_CNT
    stx SMOKE_CNT
    ldx EXTRA_LIFE_AVAIL
    beq MOVE_BOAT_ALIVE
    dec LIVES
MOVE_BOAT_ALIVE:
    inc STATE_4DCB
    lda #$02
    sta STATE_4D05
    cmp OBJ_TBL69
    bne MOVE_BOAT_SEQ
    cmp OBJ_TBL71
MOVE_BOAT_SEQ:
    php
    lda SEQ_STATE
    cmp #$03
    bcs MOVE_BOAT_SEQ_HI
    lda #$08
    plp
    beq MOVE_BOAT_SEQ_ARM
    lda #$00
    beq MOVE_BOAT_SEQ_LO
MOVE_BOAT_SEQ_HI:
    lda #$07
    plp
    beq MOVE_BOAT_SEQ_ARM
    lda #$06
; MOVE_BOAT_SEQ_LO/MOVE_BOAT_SEQ_ARM overlap: falling through here runs
; "ldy #$1E" then a BIT-absolute skip trick over what would otherwise be
; "ldy #$24", landing on "sta SEQ_STATE" with Y=$1E. Branching directly to
; MOVE_BOAT_SEQ_ARM instead re-reads the same two bytes fresh as "ldy #$24"
; - the same multi-entry-point idiom as HAZARD_CHECK_0C/0B/0A further below.
; Kept as raw bytes since ca65 can't express two different instruction
; readings of the same bytes with ordinary mnemonics.
MOVE_BOAT_SEQ_LO:
    ldy #$1E
    .byte $2C
MOVE_BOAT_SEQ_ARM:
    .byte $A0,$24
    sta SEQ_STATE
    jsr SOUND_SILENCE
    jmp SOUND_REQ_V2
; Type $07's own (short) MOVE handler - a separate routine, not a
; continuation of the boat logic above (confirmed via the OBJINIT_PARAM_TBL
; vector table: type $07 move = $9A80 exactly). Candidate: a short-lived
; transient object (e.g. a dropped bomb - Enemy_Agents_Manual_Reference.md).
MOVE_TYPE_07:
    lda STATE_4D83,x
    beq MOVE_TYPE_07_DONE
    jsr SOUND_SILENCE
    ldx #$05
    jmp ARM_SCORE_EVENT
MOVE_TYPE_07_DONE:
    rts
; Types $00-$03 (the most common "plain driving" objects) share this
; handler. It does NOT touch position at all - it only decides whether to
; despawn/reset STATE_4D84, then falls into the type-$18 handler below on
; the "normal" path. (???: exact purpose of the STATE_9B check)
MOVE_TYPE_00_03:
    lda #$FF
    sta HIT_GROUP1
    lda STATE_9B
    beq MOVE_TYPE_18
    cmp #$06
    beq MOVE_TYPE_18
    lda #$00
    sta STATE_4D84
    rts
; Type $18 MOVE handler (also the fallthrough continuation from types
; $00-$03 above). Candidate: boat-respawn object - see
; claude/Ice_Road_And_Lap_Notes.md's OBJ_TYPE $18/$19 discussion.
MOVE_TYPE_18:
    lda ROAD_FEATURE
    cmp #$15
    bne MOVE_TYPE_0E_10
    rts
; Types $0E/$0F/$10 share this handler (also the fallthrough continuation
; from type $18 above): if this slot already has a hazard-hit pending
; (STATE_4D83,x nonzero) jump straight to ARM_HAZARD_TIMER; otherwise fall
; into the MOVE_TYPE_09/0D/12/13 overlap chain below.
MOVE_TYPE_0E_10:
    lda STATE_4D83,x
    beq MOVE_HAZARD_TAIL
    jmp ARM_HAZARD_TIMER
; Types $09/$0D/$12/$13 share a chain of BIT-skip "multi-entry" landings
; that all converge on storing a per-type value ($04/$03/$06/$03
; respectively) into ZTMP_08, then run the same hazard-hit check. Kept as
; raw bytes for the BIT-skip portion - see the HAZARD_CHECK_0C/0B/0A comment
; further below for the same idiom.
MOVE_TYPE_09:
    lda #$04
    .byte $2C
MOVE_TYPE_0D:
    .byte $A9,$03,$2C
MOVE_TYPE_12:
    .byte $A9,$06,$2C
MOVE_TYPE_13:
    .byte $A9,$03
    sta ZTMP_08
    lda STATE_4D83,x
    beq MOVE_HAZARD_TAIL
MOVE_TYPE_0C_RETRY:
    jmp ARM_SCORE_EVENT_X8
; Type $0C MOVE handler: same convergence point as above, but with its own
; countdown (STATE_4D83,x) before falling through to MOVE_HAZARD_TAIL.
MOVE_TYPE_0C:
    lda #$03
    sta ZTMP_08
    lda STATE_4D83,x
    beq MOVE_HAZARD_TAIL
    dec STATE_4D83,x
    bne MOVE_TYPE_0C_RETRY
    ldy #$28
    jsr SOUND_REQ_V1_SAFE
; Shared tail for the handlers above: run the hazard-check chain against
; this slot's nearby tile codes; on a match, consume HIT_MASK_A; on a full
; miss, jump to the sprite-position "swap" / sound-effect helper instead.
MOVE_HAZARD_TAIL:
    jsr HAZARD_CHECK_07
    bne MOVE_HAZARD_TAIL_B
    jsr SEGMENT_FX_HELPER
    inc OBJ_TBL8B,x
MOVE_HAZARD_TAIL_B:
    jsr HAZARD_CHECK_0C
    bne MOVE_HAZARD_TAIL_C
    ror OBJ_TYPE,x
MOVE_HAZARD_TAIL_C:
    lda OBJ_TBL8B,x
    bne MOVE_HAZARD_TAIL_D
    jsr HAZARD_CHECK_0B
    bne MOVE_HAZARD_TAIL_D
    inc OBJ_TBL8B,x
MOVE_HAZARD_TAIL_D:
    jsr HAZARD_CHECK_CHAIN
    bne MOVE_HAZARD_MATCH
    jmp TRIGGER_SWAP_FX
MOVE_HAZARD_MATCH:
    jmp CONSUME_HIT_MASK_A
; Type $0B MOVE handler: consumes HIT_MASK_B against every other slot
; (CONSUME_HIT_MASK_BIT below); on a specific proximity result (y=$00),
; retries, otherwise toggles STATE_4D1D and nudges this slot's OBJ_POS_X.
MOVE_TYPE_0B:
    lda HIT_MASK_B
MOVE_TYPE_0B_LOOP:
    jsr CONSUME_HIT_MASK_BIT
    cpy #$08
    beq MOVE_TYPE_0B_RTS
    cpy #$00
    beq MOVE_TYPE_0B_RETRY
    cpy #$07
    bne MOVE_TYPE_0B_APPLY
MOVE_TYPE_0B_RETRY:
    lda ZTMP_0C
    ora BIT_MASK
    bne MOVE_TYPE_0B_LOOP
MOVE_TYPE_0B_APPLY:
    lda STATE_4D1D
    eor #$FE
    sta STATE_4D1D
    adc OBJ_POS_X,y
    sta OBJ_POS_X,y
    dec STATE_9B
    ldy #$16
    jsr SOUND_REQ_V2_SAFE
MOVE_TYPE_0B_RTS:
    rts
; Types $1A/$0A share this handler via another BIT-skip overlap entry (see
; the HAZARD_CHECK_0C/0B/0A comment for the same idiom): type $1A starts at
; MOVE_TYPE_1A with Y preloaded to $02 and A=$12, while type $0A enters
; directly at MOVE_TYPE_0A with A=$09 and Y left as the caller set it. Both
; paths then check OBJ_TYPE,y against A and, on a miss, just flip a bit of
; this slot's own OBJ_TYPE via ROR (???: exact purpose unclear).
MOVE_TYPE_1A:
    ldy #$02
    lda #$12
    .byte $2C
MOVE_TYPE_0A:
    .byte $A9,$09
    iny
    cmp OBJ_TYPE,y
    beq MOVE_0A1A_HIT
    sec
    ror OBJ_TYPE
    rts
; On a match: consume HIT_MASK_B against every other slot; a hit specifically
; on slot y=$06 marks STATE_4D89 (the boat's own "already crashed" flag -
; see MOVE_TYPE_05_06 above) and resets STATE_4D05.
MOVE_0A1A_HIT:
    lda HIT_MASK_B
MOVE_0A1A_LOOP:
    jsr CONSUME_HIT_MASK_BIT
    cpy #$08
    beq MOVE_0A1A_DONE
    cpy #$06
    beq MOVE_0A1A_HAZARD
    lda ZTMP_0C
    ora BIT_MASK
    bne MOVE_0A1A_LOOP
MOVE_0A1A_HAZARD:
    inc STATE_4D89
    lda #$00
    sta STATE_4D05
    ror OBJ_TYPE
MOVE_0A1A_DONE:
    lda ZTMP_0C
    sta HIT_MASK_B
    rts
; Type $1B MOVE handler: consumes HIT_MASK_B twice against two slightly
; different sets of type codes ($08/$07 first pass, $11/$07 second pass),
; marking a hit via STATE_4D84/STATE_4D83,y and ROR'ing ANIM_STATE/OBJ_TYPE.
MOVE_TYPE_1B:
    lda HIT_MASK_B
MOVE_TYPE_1B_LOOP:
    jsr CONSUME_HIT_MASK_BIT
    cpy #$08
    beq MOVE_TYPE_1B_DONE
    lda OBJ_TYPE,y
    cmp #$08
    beq MOVE_TYPE_1B_HIT
    cmp #$07
    bne MOVE_TYPE_1B_SKIP
MOVE_TYPE_1B_HIT:
    inc STATE_4D84
    ror ANIM_STATE
    ror OBJ_TYPE
MOVE_TYPE_1B_DONE:
    lda ZTMP_0C
    sta HIT_MASK_B
    rts
MOVE_TYPE_1B_SKIP:
    lda ZTMP_0C
    ora BIT_MASK
    bne MOVE_TYPE_1B_LOOP
MOVE_TYPE_1B_B:
    lda HIT_MASK_B
MOVE_TYPE_1B_B_OR:
    ora BIT_MASK
    jsr CONSUME_HIT_MASK_BIT
    cpy #$08
    beq MOVE_TYPE_1B_B_DONE
    cpy #$00
    beq MOVE_TYPE_1B_B_NOHIT
    cpy #$06
    beq MOVE_TYPE_1B_B_NOHIT
    lda OBJ_TYPE,y
    cmp #$11
    beq MOVE_TYPE_1B_B_NOHIT
    cmp #$07
    beq MOVE_TYPE_1B_B_NOHIT
    lda #$01
    sta STATE_4D83,y
    sec
    ror ANIM_STATE
MOVE_TYPE_1B_B_DONE:
    lda ZTMP_0C
    sta HIT_MASK_B
    rts
MOVE_TYPE_1B_B_NOHIT:
    lda ZTMP_0C
    bcs MOVE_TYPE_1B_B_OR
; Arm the short hazard-effect countdown (STATE_4DCA=$3C) then fall into
; ARM_SCORE_EVENT_X8 - reached both by jmp from several MOVE_TYPE_* handlers
; above and by falling through from MOVE_TYPE_1B_B_NOHIT.
ARM_HAZARD_TIMER:
    lda #$3C
    sta STATE_4DCA
    bne TRIGGER_SWAP_FX
; Queue a SCORE_EVENT for the slot in ZTMP_08 (used when the caller already
; knows which slot, rather than the current OBJ_IDX).
ARM_SCORE_EVENT_X8:
    ldx ZTMP_08
; Queue a SCORE_EVENT for slot x - the confirmed enemy-kill scoring trigger
; (see claude/Enemy_Agents_Manual_Reference.md/Collision_Detection_Notes.md)
; - then fall into the position-preserve + sound-effect helper below.
ARM_SCORE_EVENT:
    inc SCORE_EVENT,x
; Preserve this object's OBJ_POS_X/OBJ_POS_Y across a call to TYPE_KILL_FX (push,
; call, pop back unchanged - not a swap, despite first appearances), then
; queue sound effect $1E via SOUND_REQ_V2_SAFE. Shared tail for several handlers above;
; the trailing two extra PLAs balance pushes made by the (unseen) caller
; before it dispatched into this MOVE-handler block.
TRIGGER_SWAP_FX:
    ldx OBJ_IDX
    lda OBJ_POS_X,x
    pha
    lda OBJ_POS_Y,x
    pha
    jsr TYPE_KILL_FX
    pla
    sta OBJ_POS_Y,x
    pla
    sta OBJ_POS_X,x
    ldy #$1E
    jsr SOUND_REQ_V2_SAFE
    pla
    pla
    jmp TYPE_DISPATCH
; Consume one bit of a caller-supplied collision mask (A = HIT_MASK_A or
; HIT_MASK_B on entry): for this object slot (x = OBJ_IDX) paired against
; each other slot (y = 0..7), compare the clamped sprite-distance values
; (SPR_STAGE/SPR_STAGE+1,x - populated by OBJ_CALC_SPRITE_DELTA, Stage 5)
; against per-slot thresholds (OBJ_TBL93,x/y, OBJ_TBLA3 and OBJ_TBL9B) and
; fold a hit/miss bit into the mask (ZTMP_0C) via XOR with BIT_MASK. This is
; where HIT_MASK_A/HIT_MASK_B (built by PROCESS_OBJECTS, Stage 5) actually
; get consumed - i.e. the sprite-to-sprite proximity/collision check.
CONSUME_HIT_MASK_BIT:
    ldy #$00
    sty ZTMP_0D
    ldy #$08
    sta ZTMP_0C
    and BIT_MASK
    beq CONSUME_HIT_MASK_BIT_DONE
    eor ZTMP_0C
    sta ZTMP_0C
    beq CONSUME_HIT_MASK_BIT_DONE
    lda OBJ_TBL93,x
    sta ZTMP_08
    ldy #$FF
    sec
; Overlap: falling through here runs "sec : bit $18" (a no-op test) before
; ROL; branching directly to CONSUME_HIT_MASK_ALT instead re-reads the same
; byte fresh as "clc", giving ROL a clear carry - a carry-select trick, not
; a real BIT test. Kept as raw bytes for the same reason as the other
; multi-entry idioms in this file.
    .byte $24
CONSUME_HIT_MASK_ALT:
    .byte $18
    rol ZTMP_0D
    iny
    bcs CONSUME_HIT_MASK_BIT_DONE
    lda #$00
    sta ZTMP_0E
    lda ZTMP_0C
    and ZTMP_0D
    beq CONSUME_HIT_MASK_ALT
    ldx OBJ_IDX
    lda OBJ_TBL93,y
    sta ZTMP_09
    clc
    lda OBJ_TBLA3,y
    adc OBJ_TBL9B,y
    sec
    sbc OBJ_TBLA3,x
    sta ZTMP_0A
    clc
    lda OBJ_TBLA3,x
    adc OBJ_TBL9B,x
    sec
    sbc OBJ_TBLA3,y
    sta ZTMP_0B
    tya
    asl
    tax
    lda SPR_STAGE+1,x
    bmi CONSUME_HIT_MASK_X1
    cmp ZTMP_08
    bcs CONSUME_HIT_MASK_ALT
    bcc CONSUME_HIT_MASK_X2
CONSUME_HIT_MASK_X1:
    and #$7F
    cmp ZTMP_09
    bcs CONSUME_HIT_MASK_ALT
CONSUME_HIT_MASK_X2:
    cmp #$0E
    bcc CONSUME_HIT_MASK_X3
    inc ZTMP_0E
CONSUME_HIT_MASK_X3:
    lda SPR_STAGE,x
    bmi CONSUME_HIT_MASK_X4
    cmp ZTMP_0B
    bcs CONSUME_HIT_MASK_ALT
    bcc CONSUME_HIT_MASK_X5
CONSUME_HIT_MASK_X4:
    and #$7F
    cmp ZTMP_0A
    bcs CONSUME_HIT_MASK_ALT
CONSUME_HIT_MASK_X5:
    lda ZTMP_0C
    eor ZTMP_0D
    sta ZTMP_0C
CONSUME_HIT_MASK_BIT_DONE:
    rts
; Consume HIT_MASK_A for this slot, then - if the loop actually ran (cpy
; check distinguishes that from "masked out immediately") - run the
; object-type-specific effect resolution below (arm hazard timers, pair up
; slots, nudge sprite shadow positions, queue a sound effect).
CONSUME_HIT_MASK_A:
    lda HIT_MASK_A
CONSUME_HIT_MASK_A_CONT:
    jsr CONSUME_HIT_MASK_BIT
    lda ZTMP_0C
    sta HIT_MASK_A
    cpy #$08
    bne HIT_RESOLVE_START
    rts
HIT_RESOLVE_START:
    ldx OBJ_IDX
    cpx #$06
    beq HIT_RESOLVE_TYPE10
    cpy #$06
    bne HIT_RESOLVE_SWAPXY
HIT_RESOLVE_TYPE10:
    lda #$10
    cmp OBJ_TYPE,x
    bne HIT_RESOLVE_TYPE10_Y
    lda #$02
    sta OBJ_ANIM,x
    bne HIT_RESOLVE_ARM
HIT_RESOLVE_TYPE10_Y:
    cmp OBJ_TYPE,y
    bne HIT_RESOLVE_TYPE0D
    lda #$02
    sta OBJ_ANIM,y
HIT_RESOLVE_ARM:
    lda #$3C
    sta STATE_4DCA
HIT_RESOLVE_TYPE0D:
    lda #$0D
    cmp OBJ_TYPE,x
    beq HIT_RESOLVE_TYPE0D_CHECK
    cmp OBJ_TYPE,y
    bne HIT_RESOLVE_TYPE0C
HIT_RESOLVE_TYPE0D_CHECK:
    lda ZTMP_0E
    bne HIT_RESOLVE_TYPE0C
    lda STATE_4D05
    bne HIT_RESOLVE_SWAPXY
    lda SCENE_ID
    cmp #$05
    bne HIT_RESOLVE_SWAPXY
    sta $A0
    tya
    pha
    ldy #$26
    jsr SOUND_REQ_V1
    pla
    tay
    bne HIT_RESOLVE_SWAPXY
HIT_RESOLVE_TYPE0C:
    lda #$0C
    cmp OBJ_TYPE,x
    beq HIT_RESOLVE_SWAPXY
    cmp OBJ_TYPE,y
    beq HIT_RESOLVE_SWAPXY
    sec
    lda OBJ_POS_Y,x
    sbc OBJ_POS_Y,y
    cmp #$07
    bpl HIT_RESOLVE_PAIR
    sec
    lda OBJ_POS_Y,y
    sbc OBJ_POS_Y,x
    cmp #$07
    bmi HIT_RESOLVE_SWAPXY
HIT_RESOLVE_PAIR:
    txa
    sta STATE_4D83,x
    sta STATE_4D83,y
; Swap OBJ_POS_X between slots x and y, then nudge SPR_X_SHADOW/SPR_XMSB and
; the SPR_Y_SHADOW-family counters for both slots. (???: exact meaning of
; the doubled-index adjustments below.)
HIT_RESOLVE_SWAPXY:
    lda OBJ_POS_X,y
    pha
    lda OBJ_POS_X,x
    sta OBJ_POS_X,y
    pla
    sta OBJ_POS_X,x
    sty ZTMP_08
    lda OBJ_POS_X,x
    cmp OBJ_POS_X,y
    bpl HIT_RESOLVE_SWAPXY2
    txa
    pha
    tya
    tax
    pla
    tay
HIT_RESOLVE_SWAPXY2:
    inc OBJ_POS_X,x
    inc OBJ_POS_X,x
    txa
    asl
    tax
    clc
    lda SPR_X_SHADOW,x
    adc #$02
    sta SPR_X_SHADOW,x
    bcc HIT_RESOLVE_INCPOS
    lda BIT_MASK
    ora SPR_XMSB
    sta SPR_XMSB
HIT_RESOLVE_INCPOS:
    tya
    tax
    dec OBJ_POS_X,x
    dec OBJ_POS_X,x
    asl
    tax
    sec
    lda SPR_X_SHADOW,x
    sbc #$02
    sta SPR_X_SHADOW,x
    bcs HIT_RESOLVE_DECPOS
    lda ZTMP_0D
    eor #$FF
    and SPR_XMSB
    sta SPR_XMSB
HIT_RESOLVE_DECPOS:
    ldy ZTMP_08
    ldx OBJ_IDX
    lda OBJ_POS_Y,y
    pha
    lda OBJ_POS_Y,x
    sta OBJ_POS_Y,y
    pla
    sta OBJ_POS_Y,x
    cmp OBJ_POS_Y,y
    bpl HIT_RESOLVE_TAIL
    tya
    pha
    txa
    tay
    pla
    tax
HIT_RESOLVE_TAIL:
    inc OBJ_POS_Y,x
    txa
    asl
    tax
    inc SPR_Y_SHADOW,x
    inc SPR_Y_SHADOW,x
    tya
    tax
    dec OBJ_POS_Y,x
    asl
    tax
    dec SPR_Y_SHADOW,x
    dec SPR_Y_SHADOW,x
    ldx OBJ_IDX
    ldy #$2C
    jsr SOUND_REQ_V2_SAFE
    lda BIT_MASK
    ora ZTMP_0C
    jmp CONSUME_HIT_MASK_A_CONT
; Shared hazard-detection primitive (HAZARD_CHECK_0C/0B/0A/COMMON): each of
; the first three entries preloads a different target byte before falling
; into the common comparison - the same "multiple entry points into
; overlapping code" trick used elsewhere in this file (e.g. UPDATE_HAZARDS's
; DEC_TIMER1/2/3). Confirmed by disassembling from each JSR target
; independently - see claude/Collision_Detection_Notes.md.
HAZARD_CHECK_0C:
    lda #$0C
    .byte $2C
HAZARD_CHECK_0B:
    .byte $A9,$0B,$2C
HAZARD_CHECK_0A:
    .byte $A9,$0A
; Z=1 if A matches any of OBJ_TBL63/6B/73,x (the tile-classification bytes
; OBJ_CALC_SCREEN_POS populates each frame), Z=0 otherwise.
HAZARD_CHECK_COMMON:
    cmp OBJ_TBL63,x
    beq HAZARD_CHECK_RTS
    cmp OBJ_TBL6B,x
    beq HAZARD_CHECK_RTS
    cmp OBJ_TBL73,x
HAZARD_CHECK_RTS:
    rts
; Simpler single-slot variant (checks OBJ_TBL73,x only).
HAZARD_CHECK_07:
    lda #$07
    cmp OBJ_TBL73,x
    rts
; Checks a per-slot value (OBJ_TBL7B,x) then a fixed sequence of hazard
; codes in turn ($04,$06,$07,$03,$05,$02) - falls into HAZARD_CHECK_CHAIN2.
HAZARD_CHECK_CHAIN:
    lda OBJ_TBL7B,x
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
    cmp #$00
    bne HAZARD_CHECK_CHAIN2
    lda #$04
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
    lda #$06
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
    lda #$07
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
    bne HAZARD_CHECK_NOMATCH
HAZARD_CHECK_CHAIN2:
    lda #$03
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_NOMATCH
    lda #$05
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
    lda #$02
    jsr HAZARD_CHECK_COMMON
    beq HAZARD_CHECK_MATCH
; A=0: none of the chain's hazard codes matched.
HAZARD_CHECK_NOMATCH:
    lda #$00
    rts
; A=1: one of the chain's hazard codes matched.
HAZARD_CHECK_MATCH:
    lda #$01
    rts

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
; -----------------------------------------------------------------------
; SPEED_STEP: nudges SCROLL_SPEED (and ROAD_X_REF, doubled) by one step,
; throttled by a caller-supplied frame-counter bitmask - now fully
; converted to labelled instructions (previously "small mirror/fill helper
; fragment stored as data", a guessed name that doesn't match what this
; code actually does). Three real entry points, confirmed by tracing actual
; callers (SPEEDCODE_IMAGE and the hero/object move-handler block):
;   - SPEED_STEP_DOWN (fallthrough): A=-1 (decelerate)
;   - SPEED_STEP_UP (overlap entry): A=+1 (accelerate) - called from the
;     hero/object move-handler block (Stage 5)
;   - SPEED_SET (overlap entry, mid-routine): skips the throttle/clamp
;     entirely and stores whatever's in A straight to SCROLL_SPEED/
;     ROAD_X_REF - called from SPEEDCODE_IMAGE with a precomputed target
;     value (Stage 6).
; Y (saved to ZTMP_08) is presumably a period bitmask - the routine only
; commits the change when FRAME_CTR AND that mask is zero, i.e. once every
; N frames - then bails without applying if the result would go negative or
; reach 5 (keeping SCROLL_SPEED in the range 0-4).
SPEED_STEP_DOWN:
    lda #$FF
    .byte $2C
SPEED_STEP_UP:
    .byte $A9,$01
    sty ZTMP_08
    clc
    adc SCROLL_SPEED
    bmi SPEED_STEP_DONE
    cmp #$05
    bcs SPEED_STEP_DONE
    pha
    lda FRAME_CTR
    and ZTMP_08
    bne SPEED_STEP_SKIP
    pla
SPEED_SET:
    sta SCROLL_SPEED
    asl
    sta ROAD_X_REF
    .byte $24
SPEED_STEP_SKIP:
    .byte $68
SPEED_STEP_DONE:
    rts

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
; READ_DUAL_JOYSTICK_INPUT: the CONTROL_SCHEME=1 ("joystick") input decoder,
; set up as a dispatch-vector target above (JOYSTICK_CONTROL_VEC, Stage 2).
; Previously left as raw undissected data under a "player-count" framing;
; now fully traced and CONFIRMED (user-reported, verified here): this game
; is single-player only, but reads a SECOND joystick port - port 2's fire
; button, and ONLY its fire button, fires the current weapon (see
; WEAPON_FIRE_INPUT/UPDATE_WEAPONS, Stage 6). Steering and joystick 1's own
; fire button are decoded from port 1 first, into the same JOY_STATE array
; the keyboard control scheme (CONTROL_KEYBOARD_ENTRY, below) also writes.
READ_DUAL_JOYSTICK_INPUT:
    lda CIA1_PRB         ; joystick port 1: up/down/left/right/fire (active-low)
    eor #$FF              ; invert so pressed bits read as 1
    tax                   ; keep the full inverted port-1 state in X
    ldy #$00
    and #$03              ; bits 0-1: up/down
    beq JOY1_VERT_DONE     ; neither -> vertical delta stays 0
    lsr a                 ; bit0 (up) into carry
    bcc JOY1_VERT_DOWN     ; carry clear -> down was the one pressed
    iny                    ; up -> delta = +1 (accelerate)
; Overlap: falling through here runs a no-op "bit $88" before storing;
; branching directly to JOY1_VERT_DOWN instead re-reads that same byte
; fresh as "dey" (delta = -1, brake) - the classic "BIT-absolute/zp as a
; 2-byte skip, reinterpreted when entered mid-instruction" idiom used
; throughout this file (e.g. HAZARD_CHECK_0C/0B/0A in the collision code).
    .byte $24
JOY1_VERT_DOWN:
    .byte $88
JOY1_VERT_DONE:
    sty JOY_STATE          ; JOY_STATE[0] = speed delta: +1 up, -1 down, 0 neither
    txa
    and #$10               ; joystick 1's own fire button
    sta JOY1_FIRE_BTN
    txa
    ldy #$00
    and #$0C               ; bits 2-3: left/right
    beq JOY1_HORIZ_DONE     ; neither -> horizontal delta stays 0
    cmp #$08                ; exactly "right" bit pattern?
    beq JOY1_HORIZ_RIGHT
    dey                     ; not right (so left) -> delta = -1
; Same overlap idiom as above: falling through runs a no-op "bit $C8";
; entering directly at JOY1_HORIZ_RIGHT instead reads that byte fresh as
; "iny" (delta = +1, right).
    .byte $24
JOY1_HORIZ_RIGHT:
    .byte $C8
JOY1_HORIZ_DONE:
    sty JOY_STATE+1         ; JOY_STATE[1] = steering delta: +1 right, -1 left
; CONFIRMED: joystick port 2 is read here directly (not through the port-1
; decode above), keeping only its fire-button bit - this is exactly the
; input UPDATE_WEAPONS (Stage 6) checks before firing the current weapon.
    lda CIA1_PRA            ; joystick port 2
    eor #$FF
    and #$10                ; fire button only
    sta WEAPON_FIRE_INPUT
    rts

; -----------------------------------------------------------------------
; Attract-mode auto-drive: generates pseudo-random steering/speed deltas
; into the same JOY_STATE slots the real input routines use (so the rest of
; the game can't tell the difference), for the demo car shown while the
; title/menu screens cycle. This is the $A189 handler referenced above
; (GAME_STATE=0 dispatch target) - not part of the control-scheme question,
; but sits in the same data block and is now fully traced too. Uses
; RNG_NEXT for randomness and reads OBJ_TBL69/OBJ_TBL71 (slot 0, unindexed -
; i.e. SLOT0_HERO_WATCH's own tile/hazard-classification bytes, confirmed
; this session via OBJ_CALC_SCREEN_POS/HAZARD_CHECK_* and the boat-mode-flag
; finding in claude/Enemy_Scoring_Notes.md) and SCROLL_SPEED as pacing/
; decision inputs. Both compares are against 0 (plain/clear terrain), which
; fits the original guess: steer randomly but differently depending on
; whether the demo car's slot is currently over a hazard/non-plain tile,
; rather than a purely cosmetic random wobble (???: exact demo-AI logic
; beyond that framing).
ATTRACT_AUTODRIVE:
    jsr RNG_NEXT
    and #$03
    sta JOY1_FIRE_BTN        ; (reused as scratch/output here, not a real fire press)
    lda #$00
    tay
    tax
    cmp OBJ_TBL71            ; slot 0's tile/hazard-classification byte (see header)
    bne AUTODRIVE_HORIZ_A
    cmp OBJ_TBL69
    bne AUTODRIVE_HORIZ_B
    jsr RNG_NEXT
    bpl AUTODRIVE_HORIZ_A
AUTODRIVE_HORIZ_B:
    iny
    iny
AUTODRIVE_HORIZ_A:
    dey
    sty JOY_STATE+1
    cmp SCROLL_SPEED         ; (???) reused as a pacing check in this context
    beq AUTODRIVE_VERT_DONE
    jsr RNG_NEXT
    bmi AUTODRIVE_VERT_DONE
    dex
    dex
AUTODRIVE_VERT_DONE:
    inx
    stx JOY_STATE
    rts

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
; Attract / road-reset helper: arms/advances a short countdown
; (OBJ_TBL5B,x / FLAG_FF) and, once it expires (BLIT_ROWS reaches 0), sets
; up STREAM_PTR to ATTRACT_HELPER_TBL ($A298, a small 5-byte value table -
; consumed indirectly elsewhere, not decoded further here), computes a
; staged screen row/column (BLIT_ROW/BLIT_COL) from OBJ_TBLB3/OBJ_TBLBB, and
; finally writes a fixed set of 9 $5Axx screen-row addresses (candidate:
; attract-mode text row pointers). Called from the hero/object move-handler
; block (claude/Hero_Object_Move_Handler_Notes.md) - the two call sites
; there have been updated from raw hex to this name. One more
; "BIT-absolute as a 2-byte skip" overlap trick, same idiom as the two
; larger draw-handler blocks.
ATTRACT_HELPER_TBL:
    .byte $9E,$9F,$A0,$A1,$A2
ATTRACT_HELPER:
    dec OBJ_TBL5B,x
    bne ATTRACT_HELPER_RTS
    lda FLAG_FF
    bmi ATTRACT_HELPER_ADVANCE
    bne ATTRACT_HELPER_ARM
ATTRACT_HELPER_REARM:
    inc OBJ_TBL5B,x
ATTRACT_HELPER_RTS:
    rts
ATTRACT_HELPER_ARM:
    lda #$FF
    sta FLAG_FF
    lda #$2D
    sta OBJ_TBL5B,x
    ldy #$0A
    jsr SOUND_REQ_V1
    jmp ATTRACT_HELPER_ROWS
ATTRACT_HELPER_ADVANCE:
    lda #$00
    sta FLAG_FF
    ldy #$1E
    jsr SOUND_REQ_V1
ATTRACT_HELPER_ADVANCE_B:
    lda BLIT_ROWS
    bne ATTRACT_HELPER_REARM
    lda #$98
    sta STREAM_PTR
    lda #$A2
    sta STREAM_PTR_HI
    ldy #$01
    lda OBJ_TBL73,x         ; this slot's tile-classification byte - $02 is
    cmp #$02                 ;   the confirmed boat-mode flag (Boat_River_Notes.md)
    beq ATTRACT_HELPER_POS    ; boat-mode -> read ATTRACT_HELPER_TBL from Y=1;
    iny                        ;   otherwise nudge the pointer/index by one
    inc STREAM_PTR              ;   (Y=2, table+1) - selects between two
    bne ATTRACT_HELPER_POS       ;   adjacent table entries by boat/road context
    inc STREAM_PTR_HI
ATTRACT_HELPER_POS:
    clc
    lda OBJ_TBLB3,x
    adc #$01
    sta BLIT_COL
    lda OBJ_TBLBB,x
    adc #$01
    sta BLIT_ROW
    cmp #$14
    lda #$00
    bcs ATTRACT_HELPER_NOBLIT
    sta OBJ_COLOR
    sty BLIT_WIDTH
    sty BLIT_ROWS
ATTRACT_HELPER_NOBLIT:
    .byte $2C
ATTRACT_HELPER_ROWS:
    .byte $A9,$A0
    ldy #$03
    jsr ATTRACT_HELPER_STORE_ROWS
    ldy #$00
ATTRACT_HELPER_STORE_ROWS:
    sta $5A2D,y
    sta $5A33,y
    sta $5A6F,y
    sta $5A75,y
    sta $5A86,y
    sta $5A8C,y
    sta $5AC8,y
    sta $5ACE,y
    sta $5B1E,y
    rts


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
; shape yet); otherwise either toggle the requested weapon
; (WEAPON_FIRE_INPUT=0 path) or fire whichever of smoke/missile is
; currently selected and has ammo (WEAPON_FIRE_INPUT nonzero path).
; WEAPON_FIRE_INPUT is joystick PORT 2's fire button - CONFIRMED (user-
; reported): this single-player game reads a second joystick port purely to
; fire weapons; see READ_DUAL_JOYSTICK_INPUT, Stage 8.
UPDATE_WEAPONS:
    lda BLIT_ROWS
    bne WEAPONS_DONE
    lda WEAPON_FIRE_INPUT
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
; Effect spawn/param helper: given a ROAD_FEATURE/PREV_FEATURE code, looks
; it up in SEGMENT_FX_FEATURE_TBL to find a column offset (BLIT_COL) and
; picks between two 10-byte parameter tables (SEGMENT_FX_TBL_A/B, set up as
; a STREAM_PTR for indirect consumption elsewhere - same idiom as
; ATTRACT_HELPER's table in the previous block) based on odd/even feature
; index. Falls into the existing TALLY_CHAR_TBL bytes at the end (already a
; named equate from elsewhere in the file - no new label needed there, the
; assembled bytes are unchanged).
;
; Entry point SEGMENT_FX_HELPER was previously left as raw hex ($A7C1) at
; its two call sites inside the collision-detection block
; (claude/Collision_Detection_Notes.md's MOVE_BOAT_MAIN hazard chain) -
; updated to use this name.
SEGMENT_FX_TBL_A:
    .byte $10,$10,$B7,$10,$B9,$BB,$10,$BD,$10,$10
SEGMENT_FX_TBL_B:
    .byte $10,$10,$10,$B8,$BC,$BA,$BE,$10,$10,$10
SEGMENT_FX_FEATURE_TBL:
    .byte $17,$10,$15,$11,$0C,$1B,$0A,$1C,$12,$21,$10,$22
SEGMENT_FX_HELPER:
    lda BLIT_ROWS
    bne SEGMENT_FX_HELPER_RTS
    lda #$04
    cmp ROAD_FEATURE
    bcs SEGMENT_FX_USE_CURRENT
    cmp PREV_FEATURE
    bcc SEGMENT_FX_HELPER_RTS
    lda PREV_FEATURE
    bpl SEGMENT_FX_CALC_INDEX
SEGMENT_FX_USE_CURRENT:
    lda ROAD_FEATURE
SEGMENT_FX_CALC_INDEX:
    asl
    asl
    tay
    bne SEGMENT_FX_CHECK_A
    lda OBJ_TBLB3,x
    cmp #$14
    bcc SEGMENT_FX_CHECK_B
SEGMENT_FX_CHECK_A:
    lda OBJ_TBLB3,x
    cmp #$0A
    bcc SEGMENT_FX_HELPER_RTS
    cmp #$23
    bcs SEGMENT_FX_HELPER_RTS
    sec
    sbc SEGMENT_FX_FEATURE_TBL,y
    clc
    adc #$04
    bmi SEGMENT_FX_RELOAD_B
    cmp #$08
    bcc SEGMENT_FX_SET_COL
SEGMENT_FX_RELOAD_B:
    lda OBJ_TBLB3,x
SEGMENT_FX_CHECK_B:
    iny
    sec
    sbc SEGMENT_FX_FEATURE_TBL,y
    clc
    adc #$04
    bmi SEGMENT_FX_HELPER_RTS
    cmp #$08
    bcs SEGMENT_FX_HELPER_RTS
SEGMENT_FX_SET_COL:
    iny
    iny
    lda SEGMENT_FX_FEATURE_TBL,y
    sta BLIT_COL
    tya
    lsr
    bcc SEGMENT_FX_PTR_A
    lda #$AB
    ldy #$A7
    bne SEGMENT_FX_SET_PTR
SEGMENT_FX_PTR_A:
    lda #$A1
    ldy #$A7
SEGMENT_FX_SET_PTR:
    sta STREAM_PTR
    sty STREAM_PTR_HI
    lda #$02
    sta BLIT_WIDTH
    lda #$00
    sta OBJ_COLOR
    lda OBJ_TBLBB,x
    sta BLIT_ROW
    cmp #$14
    bcs SEGMENT_FX_HELPER_RTS
    lda #$05
    sta BLIT_ROWS
SEGMENT_FX_HELPER_RTS:
    ldy OBJ_IDX2
    rts
    .byte $1C,$1E,$40,$20,$28,$26


; -----------------------------------------------------------------------
; Award any queued scoring events (SCORE_EVENT[]).
TALLY_SCORE_EVENTS:
    ldx #$07
    lda STATE_4DCB
    beq TALLY_ONE_EVENT
    lda SCORE_EVENT,x
    beq TALLY_CLEAR_ENTRY
    lda #$01
    sta SCORE_EVENT,x
    lda #$00
    jsr TALLY_ONE_EVENT
    ldy #$00
    jsr ADD_SCORE
    ldx #$07
    jmp TALLY_CLEAR_ENTRY

TALLY_ONE_EVENT:
    dec SCORE_EVENT,x
    bmi TALLY_NEXT_SLOT
    php
    tax
    tay

TALLY_CHAR_LOOP:
    plp
    php
    beq TALLY_CHAR_DRAW
    lda TALLY_CHAR_TBL,y
    .byte $2C            ; [skip-2] BIT-abs opcode; falls through skipping next 2 bytes
TALLY_CHAR_DRAW:
    lda #$40
    jsr PANEL_PUT_CHAR_PAIR
    iny
    cpy #$06
    bcc TALLY_CHAR_LOOP
    plp
    ldx #$06

TALLY_CLEAR_ENTRY:
    lda #$00

TALLY_CLEAR_LOOP:
    sta SCORE_EVENT,x
    dex
    bpl TALLY_CLEAR_LOOP

TALLY_SCORE_EVENTS_RTS:
    rts

TALLY_NEXT_SLOT:
    inc SCORE_EVENT,x
    dex
    bmi TALLY_SCORE_EVENTS_RTS

TALLY_DRAIN_LOOP:
    dec SCORE_EVENT,x
    bmi TALLY_NEXT_SLOT
    txa
    pha
    asl a
    tay
    jsr ADD_SCORE
    pla
    tax
    bpl TALLY_DRAIN_LOOP
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
    bcc ADD_SCORE_CHECK_HISCORE
    inc SCORE_OVFL

ADD_SCORE_CHECK_HISCORE:
    cmp HISCORE_HI
    bcc ADD_SCORE_CHECK_EXTRALIFE
    bne ADD_SCORE_NEW_HISCORE
    cpy HISCORE_MID
    bcc ADD_SCORE_CHECK_EXTRALIFE
    bne ADD_SCORE_NEW_HISCORE
    cpx HISCORE_LO
    bcc ADD_SCORE_CHECK_EXTRALIFE

ADD_SCORE_NEW_HISCORE:
    sta HISCORE_HI
    sty HISCORE_MID
    stx HISCORE_LO

ADD_SCORE_CHECK_EXTRALIFE:
    cmp NEXT_LIFE_SCORE
    bcc ADD_SCORE_REDRAW
    clc
    lda NEXT_LIFE_SCORE
; CONFIRMS DIFFICULTY_MODE: this BCD-add advances the extra-life threshold
; by 1 (Novice, so +10,000 points - this byte is the score's ten-thousands
; digit) or 2 (Expert, so +20,000 points) - an exact match to the manual's
; figures. Definitively not a "2-player" value.
    adc DIFFICULTY_MODE
    sta NEXT_LIFE_SCORE
    ldx LIVES
    cpx #$06
    bcs ADD_SCORE_REDRAW
    inc LIVES
    ldy #$08
    jsr SOUND_REQ_V1

ADD_SCORE_REDRAW:
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
                        ;   selected when CONTROL_SCHEME=2, i.e. keyboard
                        ;   control - NOT a "2-player" mode; this game is
                        ;   single-player only (see READ_DUAL_JOYSTICK_INPUT,
                        ;   Stage 8, for the joystick control scheme, which
                        ;   reads a second joystick port's fire button for
                        ;   weapons - the actual source of the old "2-player"
                        ;   mislabelling)
CONTROL_KEYBOARD_ENTRY:
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
; (QUEUE_SOUND_REQ) unconditionally, UNLESS entered instead at
; SOUND_REQ_V1_SAFE/SOUND_REQ_V2_SAFE below - two more entry points that
; DO check busy-ness first, just like SOUND_REQ_V0. These aren't dead code:
; despite sitting right after an unconditional branch (making them
; unreachable via fallthrough from SOUND_REQ_V0B/V1), both are called
; directly via JSR from several places elsewhere in the file (the
; per-object draw handlers' sound cues) - confirmed by searching every
; reference to their addresses, not assumed from the fallthrough shape.
SOUND_REQ_V0:
    lda SND_SEQ
    bne SOUND_REQ_DONE

SOUND_REQ_V0B:
    lda #$00
    beq QUEUE_SOUND_REQ  ; (unconditional - A is always 0 here)
SOUND_REQ_V1_SAFE:
    lda SND_SEQ_V1
    bne SOUND_REQ_DONE

SOUND_REQ_V1:
    lda #$01
    bne QUEUE_SOUND_REQ  ; (unconditional - A is always 1, nonzero)
SOUND_REQ_V2_SAFE:
    lda SND_SEQ_V2
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
; SNDCMD_VEC_LO/HI (the command-handler address table DISPATCH_COMMAND
; reads) plus the three music command handlers themselves - now fully
; converted to labelled instructions. Reached only via DISPATCH_COMMAND's
; "push address-1, then RTS" indirect jump, so a straight-line disassembler
; never finds them; the vector table stores each handler's address MINUS
; ONE (confirmed: the raw bytes decode to $AB29/$AB38/$AB7A, each exactly
; one byte before a clean instruction boundary - the classic 6502 "JSR/RTS
; trick" offset, needed because RTS always adds 1 to the popped address).
;
; Command 0 - CMD_VOICE_OFF: deactivate this voice's sequence (SND_SEQ,x=0,
; the same flag MUSIC_DRIVER's VOICE_LOOP checks to skip an idle voice) and
; silence its SID control register directly - a "stop/rest" command.
;
; Command 1 - CMD_SLIDE_START: reads a note index from the sequence, looks
; up its frequency and writes it to the SID immediately (via
; SID_WRITE_FREQ) as the slide's starting point, then reads a SECOND note
; index for the slide's target frequency (SND_TGT_LO/HI), a rate byte
; (SND_RATE) and a duration byte (SND_DUR, reusing the same value as
; SND_RATE) - arming SND_SLIDE_HI/LO (nonzero) so PROCESS_STEP's
; APPLY_SLIDE continues the portamento on subsequent duration ticks. A
; pitch-bend/portamento note command.
;
; Command 2 - CMD_SEQ_JUMP: reads a new 16-bit sequence pointer from the
; current position and installs it both into this voice's saved pointer
; slots (SND_PTR0_LO,x/SND_SEQ,x) and the live SND_SEQ_PTR/HI, resets the
; read position to 0, and jumps back into PROCESS_STEP to continue from the
; new location - a "loop/jump to a different sequence" command, confirming
; the original comment's guess.
; SNDCMD_VEC_LO/HI equates (declared near the top of this file) already
; point at this exact address - not re-labelled here to avoid a duplicate
; symbol. Entries are interleaved (lo,hi) pairs, matching the x=cmd*2
; indexing DISPATCH_COMMAND uses (SNDCMD_VEC_HI = SNDCMD_VEC_LO+1) - the
; same layout as OBJMOVE_VEC_LO/HI elsewhere in this file.
    .byte <(CMD_VOICE_OFF-1), >(CMD_VOICE_OFF-1)
    .byte <(CMD_SLIDE_START-1), >(CMD_SLIDE_START-1)
    .byte <(CMD_SEQ_JUMP-1), >(CMD_SEQ_JUMP-1)

CMD_VOICE_OFF:
    lda #$00
    sta SND_SEQ,x
    tay
    ldx SND_REGOFS
    sta SID_V1_CTRL,x
    ldx SND_VOICE
    jmp VOICE_ADVANCE
CMD_SLIDE_START:
    lda (SND_SEQ_PTR),y
    iny
    and #$1F
    asl
    tax
    lda SND_FREQ_LO_TBL,x
    sta SND_PTR_LO
    lda SND_FREQ_HI_TBL,x
    sta SND_PTR_HI
    jsr SID_WRITE_FREQ
    lda SND_PTR_LO
    sta SND_FREQ_LO,x
    lda SND_PTR_HI
    sta SND_SLIDE_HI,x
    lda (SND_SEQ_PTR),y
    iny
    and #$1F
    asl
    tax
    lda SND_FREQ_LO_TBL,x
    sta SND_PTR_LO
    lda SND_FREQ_HI_TBL,x
    ldx SND_VOICE
    sta SND_TGT_LO,x
    lda SND_PTR_LO
    sta SND_TGT_HI,x
    lda (SND_SEQ_PTR),y
    iny
    sta SND_SLIDE_LO,x
    lda (SND_SEQ_PTR),y
    iny
    sta SND_RATE,x
    sta SND_DUR,x
    jmp VOICE_ADVANCE
CMD_SEQ_JUMP:
    lda (SND_SEQ_PTR),y
    iny
    sta SND_PTR0_LO,x
    pha
    lda (SND_SEQ_PTR),y
    iny
    sta SND_SEQ,x
    sta SND_SEQ_PTR_HI
    pla
    sta SND_SEQ_PTR
    ldy #$00
    jmp PROCESS_STEP

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
