# Spy Hunter - SID music command handlers ($AB24-$AB8F)

Full decode of the block flagged since Stage 9 as "the music command-handler
CODE itself, stored as raw data" - now converted to labelled instructions in
`spyhunter.asm`. Method: verified straight-line disassembly, mechanically
generated from address/mnemonic data (not hand-transcribed - see below for
why), byte-diffed against the ROM before being applied.

## The "-1" vector table

`SNDCMD_VEC_LO/HI` (6 bytes, `$AB24`-`$AB29`) stores each handler's address
**minus one**, not the literal address - the classic 6502 "push
address-1, then RTS" indirect-jump trick (`DISPATCH_COMMAND`, already
labelled, ends with a bare `rts` after pushing the vector). This wasn't
obvious at first: decoding the table naively gives targets `$AB29`/`$AB38`/
`$AB7A`, and the very first of those (`$AB29`) is a genuine illegal 6502
opcode (`$AB`) - not something a real game would deliberately execute.
Adding 1 to each gives `$AB2A`/`$AB39`/`$AB7B`, which disassemble as clean,
sensible code - confirming the "-1" convention and resolving the apparent
illegal-opcode problem.

## Command 0 - `CMD_VOICE_OFF` ($AB2A)

```
lda #$00
sta SND_SEQ,x       ; deactivate this voice's sequence (0 = idle, the same
                     ;   flag MUSIC_DRIVER's VOICE_LOOP checks)
tay
ldx SND_REGOFS
sta SID_V1_CTRL,x   ; silence the SID control register directly
ldx SND_VOICE
jmp VOICE_ADVANCE
```

A "stop/rest" command - equivalent to a musical rest or the end of a
sequence, since it also directly gates the SID voice off rather than
waiting for a duration countdown.

## Command 1 - `CMD_SLIDE_START` ($AB39)

Reads a note index from the sequence, looks up its frequency
(`SND_FREQ_LO/HI_TBL`) and writes it to the SID immediately via the
already-labelled `SID_WRITE_FREQ` - the slide's starting pitch. Then reads
a **second** note index for the target frequency (`SND_TGT_LO/HI`), a rate
byte (`SND_RATE`), and a duration byte (`SND_DUR` - reuses the same byte as
`SND_RATE`, i.e. one sequence byte serves both). This arms
`SND_SLIDE_HI`/`SND_SLIDE_LO` (nonzero), which `PROCESS_STEP` (in
`MUSIC_DRIVER`) checks each duration tick to decide whether to call
`APPLY_SLIDE` - i.e. this is a **pitch-bend/portamento** note command,
distinct from the plain `PLAY_NOTE` path.

## Command 2 - `CMD_SEQ_JUMP` ($AB7B)

Reads a new 16-bit pointer from the current sequence position and installs
it both into this voice's saved slots (`SND_PTR0_LO,x`/`SND_SEQ,x`) and the
*live* `SND_SEQ_PTR`/`SND_SEQ_PTR_HI`, resets the read position to 0, and
jumps back into `PROCESS_STEP` to continue from the new location - a
**loop/jump to a different point in the music data** command. Confirms the
original comment's guess exactly.

## A transcription trap, caught by the verify step

An early hand-written pass got `CMD_SLIDE_START`'s tail wrong - swapping
which of the two trailing sequence-byte reads feeds `SND_SLIDE_LO` vs.
`SND_RATE`/`SND_DUR`. Re-derived mechanically from the verified
instruction list instead (same approach as the collision-detection and
hero-move-handler blocks) and confirmed correct.

A second mistake surfaced by the build-and-diff step: the vector table's
`.byte` layout is **interleaved** `(lo,hi)` pairs per entry (matching the
`x = cmd*2` indexing `DISPATCH_COMMAND` uses - `SNDCMD_VEC_HI` is literally
`SNDCMD_VEC_LO+1`, the same convention as `OBJMOVE_VEC_LO/HI` elsewhere in
this file), not two separate 3-byte LO/HI blocks. Writing it as two
separate blocks assembled fine (ca65 has no way to know it's wrong) but
produced 3 wrong bytes, caught immediately by the MD5/byte-diff check
before the edit was ever applied to the real file.

Rebuilt and verified: `spyhunter.bin` MD5 unchanged at
`5af76758a98f7fc30dda87e48f94f5db` - the whole conversion is
comment/label/data-to-code only, no assembled bytes changed.
