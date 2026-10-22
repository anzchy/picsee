#!/usr/bin/env python3
"""Generate twice independently; compare system shasum inventories, not encoder claims."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import generate

ROOT=Path(__file__).resolve().parents[2]

def inventory(folder):
    files=sorted(p for p in folder.rglob('*') if p.is_file());result={}
    for offset in range(0,len(files),200):
        lines=subprocess.check_output(['/usr/bin/shasum','-a','256',*map(str,files[offset:offset+200])],text=True).splitlines()
        for line in lines:
            digest,path=line.split(maxsplit=1)
            result[str(Path(path).relative_to(folder))]=digest
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tier',choices=['small','all'],default='small')
    args=parser.parse_args()
    base=Path.home()/'.picsee/testassets';base.mkdir(parents=True,exist_ok=True)
    run=Path(tempfile.mkdtemp(prefix='determinism-',dir=base))
    records=[]
    for name in ['a','b']:
        folder=run/name
        subprocess.run([sys.executable,str(ROOT/'scripts/testassets/generate.py'),'--tier',args.tier,'--output',str(folder)],check=True)
        hashes=inventory(folder);records.append(hashes)
        (run/(name+'.sha256')).write_text(''.join(f'{sha}  {path}\n' for path,sha in sorted(hashes.items())))
    if records[0]!=records[1]:raise ValueError('different file sets or SHA-256 values')
    for path,sha in sorted(records[0].items()):
        if path.startswith('synthetic/'):print(sha+'  '+path)
    digest=hashlib.sha256((run/'a.sha256').read_bytes()).hexdigest()
    print(f'PASS determinism: {len(records[0])} files; two independent directories; shasum -a 256 inventories identical')
    print('PASS inventory sha256='+digest)
    print('Evidence: '+str(run))

if __name__=='__main__':
    try:main()
    except Exception as e:sys.exit('FAIL determinism — '+str(e))
