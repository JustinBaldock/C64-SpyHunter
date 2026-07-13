#!/usr/bin/env python3
"""Build a disk-loadable .PRG for Spy Hunter from the 16KB cartridge ROM.
 
Structure (loads at $0801):
  - BASIC line: 10 SYS<stub>
  - ML relocator stub
  - 16KB payload (patched cart ROM), page-aligned
The stub selects memory config $05 (RAM at $A000/$E000, I/O at $D000),
copies the 16KB payload up to $8000-$BFFF, then JMP $8027 (game cold start).
 
Patch: the charset-copy init writes $01=$03 (config 3 -> BASIC ROM over $A000
on a real C64, which would crash the JSR $A1xx calls). Translated to $02
(config 2: RAM at $A000, char ROM at $D000) so it works from disk.
"""
ROM = bytearray(open('/root/spyhunter/spyhunter.rom','rb').read())
assert len(ROM)==16384
 
# --- patch $03 -> $02 at offset $811E ---
assert ROM[0x11E]==0x03, hex(ROM[0x11E])
ROM[0x11E]=0x02
 
LOAD=0x0801
# BASIC: link(2) line#(2) 0x9E "SYS" digits 0x00 ; end 0x00 0x00
# We'll aim the SYS at the stub which begins right after the BASIC line.
# Build BASIC line with a placeholder, compute stub addr, then fill digits.
def basic_line(sys_addr):
    body = bytes([0x9E]) + str(sys_addr).encode() + b'\x00'
    line_no = 10
    # next-line link = LOAD + 2(link) +2(lineno)+len(body)
    total = 2+2+len(body)
    link = LOAD + total
    return (link.to_bytes(2,'little') + line_no.to_bytes(2,'little')
            + body + b'\x00\x00')  # trailing end-of-program
 
# iterate to converge on SYS address (digit count can change length)
sys_addr = LOAD+20
for _ in range(5):
    bl = basic_line(sys_addr)
    stub_addr = LOAD + len(bl)
    if stub_addr==sys_addr: break
    sys_addr=stub_addr
bl = basic_line(sys_addr)
stub_addr = LOAD + len(bl)
assert stub_addr==sys_addr
 
# payload must be page aligned; place after stub with padding.
# First assemble stub with a symbolic src; we know stub length is fixed below.
# Stub machine code:
def make_stub(src, stub_org):
    # zero page temp pointers: $FB/$FC = src, $FD/$FE = dest ($8000)
    c=[]
    c+=[0x78]                       # SEI
    c+=[0xA9,0x05, 0x85,0x01]       # LDA #$05 : STA $01  (config 5)
    c+=[0xA9,src&0xFF,0x85,0xFB]    # LDA #<src : STA $FB
    c+=[0xA9,(src>>8)&0xFF,0x85,0xFC]# LDA #>src : STA $FC
    c+=[0xA9,0x00,0x85,0xFD]        # LDA #$00 : STA $FD
    c+=[0xA9,0x80,0x85,0xFE]        # LDA #$80 : STA $FE  (dest $8000)
    c+=[0xA2,0x40]                  # LDX #$40  (64 pages)
    # loop:
    loop=stub_org+len(c)
    c+=[0xA0,0x00]                  # LDY #$00
    inner=stub_org+len(c)
    c+=[0xB1,0xFB]                  # LDA ($FB),Y
    c+=[0x91,0xFD]                  # STA ($FD),Y
    c+=[0xC8]                       # INY
    c+=[0xD0,(inner-(stub_org+len(c)+2))&0xFF]  # BNE inner
    c+=[0xE6,0xFC]                  # INC $FC
    c+=[0xE6,0xFE]                  # INC $FE
    c+=[0xCA]                       # DEX
    c+=[0xD0,(loop-(stub_org+len(c)+2))&0xFF]   # BNE loop
    c+=[0x4C,0x27,0x80]             # JMP $8027
    return bytes(c)
 
# stub length is constant; compute payload location page-aligned
tmp_stub=make_stub(0x0000,stub_addr)
payload_addr = stub_addr+len(tmp_stub)
payload_addr = (payload_addr+0xFF)&0xFF00  # round up to page
pad = payload_addr-(stub_addr+len(tmp_stub))
stub=make_stub(payload_addr,stub_addr)
 
prg = bytearray()
prg += LOAD.to_bytes(2,'little')   # PRG load address header
prg += bl
prg += stub
prg += b'\x00'*pad
prg += ROM
open('/root/spyhunter/spyhunter.prg','wb').write(prg)
print(f"BASIC SYS -> ${sys_addr:04X} ({sys_addr})")
print(f"stub @ ${stub_addr:04X}, len {len(stub)}")
print(f"payload @ ${payload_addr:04X}, pad {pad}")
print(f"PRG total {len(prg)} bytes ({len(prg)-2} + 2 header)")
print(f"config patch: $811E $03->$02 applied")