#!/usr/bin/env python3
"""
vsf_extract.py - extract C64 RAM + key state from a VICE .vsf snapshot.
Usage: python3 vsf_extract.py snapshot.vsf [out_ram.bin]
Validated against Spy Hunter snapshots (C64SC machine module).
 
NOTE: the C64MEM module stores 4 bytes (pport.data, pport.dir, exrom, game)
BEFORE the 65536-byte RAM image. RAM therefore starts at payload+4.  Reading
at payload+2 shifts every address up by 2 - verified via the invariant
SPRITE_PTRS ($4D2B) == SPRPTR_7800 ($7BF8), which the game copies each frame.
"""
import struct, sys
 
def load(fn):
    data = open(fn,'rb').read()
    assert data[:18]==b"VICE Snapshot File", "not a VICE snapshot"
    mods=[]; o=36
    while o+22 <= len(data):
        nm = data[o:o+16].split(b'\x00')[0]
        if not nm or not all(32<=c<127 for c in nm): o+=1; continue
        size = struct.unpack('<I', data[o+18:o+22])[0]
        if size<22 or o+size>len(data): o+=1; continue
        mods.append((o, nm.decode(), data[o+16], data[o+17], size)); o+=size
    return data, mods
 
def extract_ram(data, mods):
    m=[x for x in mods if x[1]=="C64MEM"][0]
    base=m[0]+22                       # module payload start
    pport_data, pport_dir = data[base], data[base+1]   # $01, $00 values
    ram = data[base+4: base+4+65536]   # +4: skip data,dir,exrom,game
    return ram, pport_data, pport_dir
 
if __name__=="__main__":
    fn=sys.argv[1]; out=sys.argv[2] if len(sys.argv)>2 else "ram.bin"
    data,mods=load(fn)
    ram,pd,pdir=extract_ram(data,mods)
    open(out,'wb').write(ram)
    b=lambda a:ram[a]; bcd=lambda x:f"{x>>4}{x&0xF}"
    print(f"modules: {len(mods)}  pport $01={pd:02X} $00={pdir:02X}  RAM->{out} ({len(ram)}B)")
    print("--- Spy Hunter state (addresses per spyhunter.asm) ---")
    print(f"SCORE    $E0-$E2 (BCD lo->hi): {bcd(b(0xE2))} {bcd(b(0xE1))} {bcd(b(0xE0))}")
    print(f"HISCORE  $02-$04 (BCD lo->hi): {bcd(b(0x04))} {bcd(b(0x03))} {bcd(b(0x02))}")
    print(f"TIMER    $4D01/$4D02 (BCD)   : {bcd(b(0x4D02))}{bcd(b(0x4D01))}   enable $E3={b(0xE3):02X}")
    print(f"WEAPON   $4D1E={b(0x4D1E):02X}  ammo guns$F6={b(0xF6):02X} miss$F7={b(0xF7):02X} smoke$F9={b(0xF9):02X}")
    print(f"LIVES    $4D15={b(0x4D15):02X}  GAME_STATE $4D13={b(0x4D13):02X}")
    print(f"ROAD     seg_idx$42={b(0x42):02X} seg_len$43={b(0x43):02X} feature$44={b(0x44):02X} "
          f"prev$45={b(0x45):02X} scene_idx$4A={b(0x4A):02X}")
    def read_panel(addr):     # digit N -> char $60+2N ; blank=$40
        s=""
        for c in range(0,40,2):
            v=ram[addr+c]
            if v==0x40: s+=" "
            elif 0x60<=v<=0x73 and (v-0x60)%2==0: s+=str((v-0x60)//2)
            else: s+="?"
        return s
    print(f"PANEL $6798: '{read_panel(0x6798)}'")