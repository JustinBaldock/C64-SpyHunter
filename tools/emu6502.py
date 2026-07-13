#!/usr/bin/env python3
"""Cycle-inexact 6502 + minimal C64 emulator to validate the Spy Hunter loader
and trace reachable code. Not pixel-accurate; models banking, raster, CIA, SID
enough to run init + IRQ handlers and follow jump tables."""
import random
 
class C64:
    def __init__(self, prg_path):
        self.ram = bytearray(65536)
        self.chargen = bytes([i & 0xFF for i in range(4096)])  # synthetic char ROM
        # load PRG
        data = open(prg_path,'rb').read()
        load = data[0]|(data[1]<<8)
        for i,b in enumerate(data[2:]):
            self.ram[(load+i)&0xFFFF]=b
        self.pc=load  # we'll start at stub via BASIC SYS; caller sets pc
        self.a=self.x=self.y=0
        self.sp=0xFF
        self.p=0x24  # I set
        self.ram[0x01]=0x37; self.ram[0x00]=0x2F
        self.cycles=0
        self.raster=0
        self.exec_pcs=set()
        self.banked_exec=[]   # PCs executed in a ROM-banked region (would be non-game)
        self.io_writes=[]     # (pc, addr, val) for D000-DFFF
        self.illegal=[]
        self.brk_hit=None
        self.joy=0xFF         # no input
        self.halt=False
 
    # ---- banking ----
    def cfg(self):
        return self.ram[0x01]&0x07
    def read(self,a):
        a&=0xFFFF
        if 0xA000<=a<0xC000:
            c=self.cfg()
            if (c&0x03)==0x03:  # LORAM&HIRAM -> BASIC ROM
                return 0xFF     # sentinel: BASIC ROM (we don't have it)
            return self.ram[a]
        if 0xD000<=a<0xE000:
            c=self.cfg()
            if (c&0x04)==0 and (c&0x03)!=0:  # CHAREN=0 and a ROM selected -> char ROM
                return self.chargen[a-0xD000]
            if (c&0x03)==0:  # all-RAM
                return self.ram[a]
            return self.io_read(a)
        if 0xE000<=a:
            c=self.cfg()
            if (c&0x02):  # HIRAM -> KERNAL ROM
                return 0xEA  # sentinel
            return self.ram[a]
        return self.ram[a]
    def write(self,a,v):
        a&=0xFFFF; v&=0xFF
        if 0xD000<=a<0xE000:
            c=self.cfg()
            if (c&0x03)!=0 and (c&0x04)!=0:  # I/O visible
                self.io_writes.append((self.pc,a,v)); self.io_write(a,v); return
            if (c&0x03)==0:  # all RAM
                self.ram[a]=v; return
            # char ROM window: writes go to RAM underneath
            self.ram[a]=v; return
        self.ram[a]=v  # writes always hit RAM (under ROM too)
 
    def io_read(self,a):
        if a==0xD012: return self.raster&0xFF
        if a==0xD011: return (0x1B|((self.raster>>1)&0x80))
        if a==0xD019: return 0x81  # raster IRQ latched
        if a==0xD41B: return random.randint(0,255)  # SID osc3
        if a==0xD41C: return random.randint(0,255)
        if a==0xDC00: return 0xFF  # keyboard cols
        if a==0xDC01: return self.joy  # joystick port1
        if a==0xDC0D: return 0x00
        if a==0xDD0D: return 0x00
        if 0xDC04<=a<=0xDC07: return random.randint(0,255)
        return 0x00
    def io_write(self,a,v):
        pass
 
    # ---- 6502 core ----
    def push(self,v): self.ram[0x100+self.sp]=v&0xFF; self.sp=(self.sp-1)&0xFF
    def pop(self): self.sp=(self.sp+1)&0xFF; return self.ram[0x100+self.sp]
    def setzn(self,v):
        v&=0xFF
        self.p=(self.p&~0x82)|(0x02 if v==0 else 0)|(v&0x80)
    def irq(self):
        if self.p&0x04: return
        self.push((self.pc>>8)&0xFF); self.push(self.pc&0xFF)
        self.push((self.p|0x20)&~0x10)
        self.p|=0x04
        self.pc=self.read(0xFFFE)|(self.read(0xFFFF)<<8)
 
    def step(self):
        pc=self.pc
        self.exec_pcs.add(pc)
        # detect execution in banked ROM (non-game) region
        if 0xA000<=pc<0xC000 and (self.cfg()&0x03)==0x03:
            self.banked_exec.append(pc)
        if 0xE000<=pc and (self.cfg()&0x02):
            self.banked_exec.append(pc)
        op=self.read(pc)
        from dis6502 import OPS
        if op not in OPS:
            self.illegal.append((pc,op)); self.halt=True; return
        mn,mode,length=OPS[op]
        # operand fetch
        b1=self.read(pc+1); b2=self.read(pc+2)
        addr=None; val=None
        if mode=='imm': val=b1
        elif mode=='zp': addr=b1
        elif mode=='zpx': addr=(b1+self.x)&0xFF
        elif mode=='zpy': addr=(b1+self.y)&0xFF
        elif mode=='izx':
            p=(b1+self.x)&0xFF; addr=self.ram[p]|(self.ram[(p+1)&0xFF]<<8)
        elif mode=='izy':
            addr=(self.ram[b1]|(self.ram[(b1+1)&0xFF]<<8))+self.y; addr&=0xFFFF
        elif mode=='abs': addr=b1|(b2<<8)
        elif mode=='abx': addr=((b1|(b2<<8))+self.x)&0xFFFF
        elif mode=='aby': addr=((b1|(b2<<8))+self.y)&0xFFFF
        elif mode=='ind': addr=b1|(b2<<8)
        elif mode=='rel': addr=(pc+2+((b1^0x80)-0x80))&0xFFFF
        self.pc=(pc+length)&0xFFFF
        def M(): return val if mode=='imm' else self.read(addr)
        c=self.p
        if mn=='LDA': self.a=M(); self.setzn(self.a)
        elif mn=='LDX': self.x=M(); self.setzn(self.x)
        elif mn=='LDY': self.y=M(); self.setzn(self.y)
        elif mn=='STA': self.write(addr,self.a)
        elif mn=='STX': self.write(addr,self.x)
        elif mn=='STY': self.write(addr,self.y)
        elif mn=='TAX': self.x=self.a; self.setzn(self.x)
        elif mn=='TAY': self.y=self.a; self.setzn(self.y)
        elif mn=='TXA': self.a=self.x; self.setzn(self.a)
        elif mn=='TYA': self.a=self.y; self.setzn(self.a)
        elif mn=='TSX': self.x=self.sp; self.setzn(self.x)
        elif mn=='TXS': self.sp=self.x
        elif mn=='PHA': self.push(self.a)
        elif mn=='PLA': self.a=self.pop(); self.setzn(self.a)
        elif mn=='PHP': self.push(self.p|0x30)
        elif mn=='PLP': self.p=(self.pop()&~0x10)|0x20
        elif mn=='AND': self.a&=M(); self.setzn(self.a)
        elif mn=='ORA': self.a|=M(); self.setzn(self.a)
        elif mn=='EOR': self.a^=M(); self.setzn(self.a)
        elif mn=='BIT':
            m=M(); self.p=(self.p&~0xC2)|(m&0xC0)|(0x02 if (self.a&m)==0 else 0)
        elif mn in ('ADC','SBC'):
            m=M();
            if mn=='SBC': m^=0xFF
            t=self.a+m+(self.p&1)
            self.p=(self.p&~0x01)|(1 if t>0xFF else 0)
            ov=(~(self.a^m)&(self.a^t)&0x80)
            self.p=(self.p&~0x40)|(0x40 if ov else 0)
            self.a=t&0xFF; self.setzn(self.a)
        elif mn=='CMP':
            m=M(); t=(self.a-m)&0x1FF; self.p=(self.p&~0x01)|(1 if self.a>=m else 0); self.setzn((self.a-m)&0xFF)
        elif mn=='CPX':
            m=M(); self.p=(self.p&~0x01)|(1 if self.x>=m else 0); self.setzn((self.x-m)&0xFF)
        elif mn=='CPY':
            m=M(); self.p=(self.p&~0x01)|(1 if self.y>=m else 0); self.setzn((self.y-m)&0xFF)
        elif mn=='INC':
            m=(self.read(addr)+1)&0xFF; self.write(addr,m); self.setzn(m)
        elif mn=='DEC':
            m=(self.read(addr)-1)&0xFF; self.write(addr,m); self.setzn(m)
        elif mn=='INX': self.x=(self.x+1)&0xFF; self.setzn(self.x)
        elif mn=='INY': self.y=(self.y+1)&0xFF; self.setzn(self.y)
        elif mn=='DEX': self.x=(self.x-1)&0xFF; self.setzn(self.x)
        elif mn=='DEY': self.y=(self.y-1)&0xFF; self.setzn(self.y)
        elif mn=='ASL':
            if mode=='acc': m=self.a; self.p=(self.p&~1)|(m>>7); m=(m<<1)&0xFF; self.a=m
            else: m=self.read(addr); self.p=(self.p&~1)|(m>>7); m=(m<<1)&0xFF; self.write(addr,m)
            self.setzn(m)
        elif mn=='LSR':
            if mode=='acc': m=self.a; self.p=(self.p&~1)|(m&1); m>>=1; self.a=m
            else: m=self.read(addr); self.p=(self.p&~1)|(m&1); m>>=1; self.write(addr,m)
            self.setzn(m)
        elif mn=='ROL':
            cin=self.p&1
            if mode=='acc': m=self.a; self.p=(self.p&~1)|(m>>7); m=((m<<1)|cin)&0xFF; self.a=m
            else: m=self.read(addr); self.p=(self.p&~1)|(m>>7); m=((m<<1)|cin)&0xFF; self.write(addr,m)
            self.setzn(m)
        elif mn=='ROR':
            cin=self.p&1
            if mode=='acc': m=self.a; self.p=(self.p&~1)|(m&1); m=((m>>1)|(cin<<7))&0xFF; self.a=m
            else: m=self.read(addr); self.p=(self.p&~1)|(m&1); m=((m>>1)|(cin<<7))&0xFF; self.write(addr,m)
            self.setzn(m)
        elif mn=='JMP':
            if mode=='ind':
                lo=self.read(addr); hi=self.read((addr&0xFF00)|((addr+1)&0xFF)); self.pc=lo|(hi<<8)
            else: self.pc=addr
        elif mn=='JSR':
            r=(pc+2)&0xFFFF; self.push((r>>8)&0xFF); self.push(r&0xFF); self.pc=addr
        elif mn=='RTS': lo=self.pop(); hi=self.pop(); self.pc=((lo|(hi<<8))+1)&0xFFFF
        elif mn=='RTI':
            self.p=(self.pop()&~0x10)|0x20; lo=self.pop(); hi=self.pop(); self.pc=lo|(hi<<8)
        elif mn=='BRK': self.brk_hit=pc; self.halt=True
        elif mn=='NOP': pass
        elif mn=='SEC': self.p|=0x01
        elif mn=='CLC': self.p&=~0x01
        elif mn=='SEI': self.p|=0x04
        elif mn=='CLI': self.p&=~0x04
        elif mn=='SED': self.p|=0x08
        elif mn=='CLD': self.p&=~0x08
        elif mn=='CLV': self.p&=~0x40
        elif mn[0]=='B' and mode=='rel':
            take={'BPL':not(c&0x80),'BMI':c&0x80,'BVC':not(c&0x40),'BVS':c&0x40,
                  'BCC':not(c&0x01),'BCS':c&0x01,'BNE':not(c&0x02),'BEQ':c&0x02}[mn]
            if take: self.pc=addr
        self.cycles+=1
 
if __name__=='__main__':
    import sys
    c=C64('/root/spyhunter/spyhunter.prg')
    c.pc=2061  # BASIC SYS target = stub
    MAX=3_000_000
    irq_period=8000
    next_irq=irq_period
    while not c.halt and c.cycles<MAX:
        c.step()
        c.raster=(c.raster+1)&0x1FF
        if c.cycles>=next_irq and not (c.p&0x04):
            c.irq(); next_irq=c.cycles+irq_period
        else:
            next_irq=max(next_irq,c.cycles+1) if (c.p&0x04) else next_irq
    print("cycles:",c.cycles,"halt:",c.halt)
    print("illegal:",c.illegal[:5])
    print("brk_hit:",hex(c.brk_hit) if c.brk_hit else None)
    print("banked_exec (BASIC/KERNAL region executed):",len(c.banked_exec), c.banked_exec[:5])
    print("distinct PCs executed:",len(c.exec_pcs))
    print("$01 final:",hex(c.ram[0x01]))
    # VIC/SID writes summary
    vic=set(a for _,a,_ in c.io_writes if 0xD000<=a<0xD400)
    sid=set(a for _,a,_ in c.io_writes if 0xD400<=a<0xD500)
    print("VIC regs written:",sorted(hex(a) for a in vic))
    print("SID regs written:",sorted(hex(a) for a in sid))
    import pickle
    pickle.dump(c.exec_pcs, open('/root/spyhunter/exec_pcs.pkl','wb'))