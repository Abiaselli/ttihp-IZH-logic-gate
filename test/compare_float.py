"""Independent double-precision check of unconnected RS and FS neurons."""
import json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from model import Bank,encode

reports=[]
for a,d,name in [(.02,8,'regular_spiking'),(.1,2,'fast_spiking')]:
    bank=Bank(4); cell=bank.cells[0]
    cell.a=encode(a,True); cell.d=encode(d); cell.bias=encode(10)
    v=-65.; u=-13.; floating=[]; fixed=[]
    for step in range(8000):
        dv=.04*v*v+5*v+140-u+10
        du=a*(.2*v-u)
        v+=dv/16; u+=du/16
        if v>=30:
            v=-65.; u+=d; floating.append(step)
        bank.step()
        if bank.spikes&1: fixed.append(step)
    drift=max(abs(x-y)/16 for x,y in zip(floating,fixed))
    reports.append(dict(mode=name,simulated_ms=500,float_spikes=len(floating),
        fixed_spikes=len(fixed),max_paired_spike_time_error_ms=drift))
    assert abs(len(floating)-len(fixed))<=1, reports[-1]
    assert drift<2., reports[-1]
print(json.dumps(reports,indent=2))
