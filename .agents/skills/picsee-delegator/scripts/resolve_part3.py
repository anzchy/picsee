# -*- coding: utf-8 -*-
# Resolve ledger conflicts limited to Part 3 area-review rows: '分发' keeps HEAD (main), others take THEIRS (branch).
import sys
p=sys.argv[1]; s=open(p).read().splitlines(); out=[]; i=0; ok=True
while i<len(s):
    if s[i].startswith('<<<<<<<'):
        j=s.index('=======',i); k=next(n for n in range(j,len(s)) if s[n].startswith('>>>>>>>'))
        head=s[i+1:j]; theirs=s[j+1:k]
        hk={l.split('|')[1].strip():l for l in head}; tk={l.split('|')[1].strip():l for l in theirs}
        if list(hk)!=list(tk): ok=False; out+=s[i:k+1]
        else:
            for key in hk: out.append(hk[key] if key=='分发' else tk[key])
        i=k+1; continue
    out.append(s[i]); i+=1
open(p,'w').write('\n'.join(out)+'\n'); print('ok' if ok else 'UNRESOLVED')
