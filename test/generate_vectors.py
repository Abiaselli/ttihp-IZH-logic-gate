"""Numerical, state-isolation, routing, overflow and malformed-command vectors."""
import sys, random, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from model import Bank, packet, write, encode

def generate(n, dest):
    b=Bank(n); rows=[]; rng=random.Random(4920+n); counts=[0]*n
    def cmd(c, events=0, repeat=False):
        if events: b.events(events)
        if repeat: b.events(events)
        r=b.command(c)
        rows.append(f'{events|(16 if repeat else 0):02x} {c.hex()} {r.hex()}')
    for j in range(n):
        for field in range(12): cmd(packet(2,(field<<4)|j))
        cmd(write(j,'bias',encode(5+j)))
        cmd(write(j,'a',encode(.1 if j%2 else .02,True)))
        cmd(write(j,'d',encode(2 if j%2 else 8)))
        cmd(write(j,'src0',(j+1)%n))
        cmd(write(j,'src1',16+j%4))
        cmd(write(j,'w0',encode(-1 if j%2 else 1)))
        cmd(write(j,'w1',encode(-3 if j%2 else 3)))
    for t in range(1600):
        cmd(packet(3), (1<<rng.randrange(4)) if t%19==0 else 0)
        for j in range(n):
            counts[j]+=(b.spikes>>j)&1
            for field in (0,1,2): cmd(packet(2,(field<<4)|j))
    # Stress representable endpoints and reset after this test in the SV bench.
    for j in range(n):
        for field in ('v','u','syn','bias','a','b','d','w0','w1'):
            cmd(write(j,field,rng.choice((-131072,131071))))
    for _ in range(8):
        cmd(packet(3),15)
        for j in range(n):
            for field in (0,1,2): cmd(packet(2,(field<<4)|j))
    cmd(packet(2,0),1,True) # Two input edges before a step must flag coalescing.
    cmd(packet(3))
    cmd(packet(0xff,0x55))
    cmd(packet(2,0xf0))
    if n==4: cmd(packet(2,0x07))
    Path(dest).write_text('\n'.join(rows)+'\n')
    return dict(neurons=n,transactions=len(rows),spikes_per_neuron=counts)

if __name__=='__main__':
    print(json.dumps(generate(int(sys.argv[1]),sys.argv[2])))
