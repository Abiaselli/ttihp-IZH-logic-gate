"""Run from any directory. Requires Python 3 and Verilator with a C++ toolchain."""
import os, sys, subprocess, shutil, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
verilator=os.environ.get('VERILATOR') or shutil.which('verilator') or shutil.which('verilator-cli')
if not verilator: raise SystemExit('Set VERILATOR to your Verilator executable.')
def run(args): subprocess.run([str(x) for x in args],cwd=ROOT,check=True)
run([sys.executable,ROOT/'test/compare_float.py'])
with tempfile.TemporaryDirectory(prefix='izh-test-') as tmp:
    tmp=Path(tmp)
    for top,n in [('tb_mul',None),('tb',4),('tb',16)]:
        tag=top+str(n or '')
        obj=tmp/tag
        sources=[ROOT/'src/serial_mul.v']
        if n: sources += [ROOT/'src/neuron_bank.v',ROOT/'src/project.v']
        args=[verilator,'--binary','--timing','-Wno-DECLFILENAME','--top-module',top,'--Mdir',obj]
        if n: args += [f'-GN={n}']
        run(args+sources+[ROOT/f'test/{top}.sv'])
        extra=[]
        if n:
            vectors=tmp/f'vectors{n}.hex'
            run([sys.executable,ROOT/'test/generate_vectors.py',n,vectors])
            extra=[f'+vectors={vectors}']
        run([obj/f'V{top}']+extra)
