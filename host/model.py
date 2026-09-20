"""Executable numerical contract and host packet encoder. No dependencies."""
from dataclasses import dataclass

FIELDS = dict(v=0, u=1, syn=2, bias=3, a=4, b=5, c=6, d=7,
              w0=8, w1=9, src0=10, src1=11)

def encode(value, dimensionless=False):
    return round(value * 65536 / (1 if dimensionless else 100))

def signed(raw):
    return (raw & 0x1ffff) - (raw & 0x20000)

def sat(x):
    return min(131071, max(-131072, x))

def packet(op, address=0, data=0):
    raw = data & 0x3ffff
    return bytes((op, address, raw & 255, (raw >> 8) & 255, raw >> 16))

def write(neuron, field, value):
    return packet(1, (FIELDS[field] << 4) | neuron, value)

@dataclass
class Context:
    v:int=-42598; u:int=-8520; syn:int=0; bias:int=0
    a:int=1311; b:int=13107; c:int=-42598; d:int=5243
    w0:int=0; w1:int=0; src0:int=31; src1:int=31

class Bank:
    def __init__(self, n):
        assert n in (4,16)
        self.cells=[Context() for _ in range(n)]
        self.spikes=0; self.pending=0; self.overrun=False

    def events(self, mask):
        self.overrun |= bool(self.pending & mask)
        self.pending |= mask

    def step(self):
        old=self.spikes; ext=self.pending; self.pending=0
        def fired(source):
            if source < len(self.cells): return (old >> source)&1
            if 16 <= source < 20: return (ext >> (source-16))&1
            return 0
        bitmap=0; clipped=False
        for i,c in enumerate(self.cells):
            retained=(abs(c.syn)*15)//16
            if c.syn < 0: retained=-retained
            s=retained+c.w0*fired(c.src0)+c.w1*fired(c.src1)
            clipped |= sat(s)!=s
            s=sat(s)
            dv=((c.v*c.v+8192)>>14)+5*c.v+91750-c.u+c.bias+s
            du=c.a*(((c.b*c.v+32768)>>16)-c.u)
            vn=c.v+((dv+8)>>4); un=c.u+((du+524288)>>20)
            if vn>=19661:
                bitmap |= 1<<i; vn=c.c; un+=c.d
            clipped |= sat(vn)!=vn or sat(un)!=un
            c.v=sat(vn); c.u=sat(un); c.syn=s
        self.spikes=bitmap
        return packet(int(clipped)|(int(self.overrun)<<1),0,bitmap)

    def command(self, cmd):
        op,addr,lo,mid,hi=cmd
        raw=lo|(mid<<8)|((hi&3)<<16)
        if op==3: return self.step()
        if op not in (1,2): return packet(0x80,addr)
        field=addr>>4; idx=addr&15
        if idx>=len(self.cells) or field>=len(FIELDS): return packet(0x81,addr)
        name=list(FIELDS)[field]; cell=self.cells[idx]
        if op==1:
            setattr(cell,name,raw&31 if field>=10 else signed(raw))
            return packet(0,addr)
        return packet(0,addr,getattr(cell,name))
