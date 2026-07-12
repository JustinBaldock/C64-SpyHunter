# ---- Spy Hunter (C64) reverse-engineering build ----
# Requires: cc65 (ca65 + ld65), Python 3
# Targets:
#   make            -> assemble ROM and build the disk-loadable PRG
#   make rom        -> spyhunter.bin  (raw 16K cartridge image, $8000-$BFFF)
#   make prg        -> spyhunter.prg  (loads at $0801, self-relocating)
#   make verify     -> check the ROM matches the original (MD5)
#   make clean

ROM_MD5 = ee7fe8c9a5179aa8b23d8f1e49cf113c

all: prg

spyhunter.o: spyhunter.asm
	ca65 -t c64 spyhunter.asm -o spyhunter.o

spyhunter.bin: spyhunter.o spyhunter.cfg
	ld65 -C spyhunter.cfg spyhunter.o -o spyhunter.bin

rom: spyhunter.bin

verify: spyhunter.bin
	@echo "$(ROM_MD5)  spyhunter.bin" | md5sum -c -

spyhunter.prg: spyhunter.bin build_prg.py
	cp spyhunter.bin spyhunter.rom
	python3 build_prg.py

prg: spyhunter.prg

clean:
	rm -f spyhunter.o spyhunter.bin spyhunter.rom spyhunter.prg

.PHONY: all rom prg verify clean
