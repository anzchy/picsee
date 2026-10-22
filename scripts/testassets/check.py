#!/usr/bin/env python3
"""Validate manifest coverage, dimensions, sizes, hashes and source/recipe metadata."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import generate

ROOT=Path(__file__).resolve().parents[2]

def dimensions(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return list(struct.unpack('>II',data[16:24]))
    if data.startswith(b'II*\0'):
        offset=struct.unpack_from('<I',data,4)[0];count=struct.unpack_from('<H',data,offset)[0];tags={}
        for i in range(count):
            tag,kind,n,value=struct.unpack_from('<HHII',data,offset+2+i*12)
            tags[tag]=value & 65535 if kind==3 else value
        return [tags[256],tags[257]]
    return None

def verify(args):
    manifest=json.loads(args.manifest.read_text())
    if manifest['schema']!='picsee-testassets/v1':raise ValueError('unknown schema')
    if manifest['generator_version']!=generate.VERSION:raise ValueError('generator version mismatch')
    if manifest['generator_sha256']!=hashlib.sha256((ROOT/'scripts/testassets/generate.py').read_bytes()).hexdigest():raise ValueError('generator source hash mismatch')
    specs={(1,s['path']):s for s in generate.small_specs()}
    specs.update({(2,s['path']):s for s in generate.bulk_specs()+generate.large_specs()})
    oriented_hashes=[]
    seen=set();counts={1:0,2:0,3:0};checked={1:0,2:0,3:0};total_small=0
    for a in manifest['assets']:
        tier,path=a['tier'],a['path'];relative=Path(path)
        if relative.is_absolute() or '..' in relative.parts or not relative.parts:raise ValueError('unsafe asset path')
        key=(tier,path)
        if key in seen:raise ValueError('duplicate manifest path '+path)
        seen.add(key);counts[tier]+=1
        if not re.fullmatch('[0-9a-f]{64}',a['sha256']) or a['byte_size']<=0:raise ValueError('invalid hash/size '+path)
        if a['license']!='CC0-1.0':raise ValueError('unreviewed licence '+path)
        if tier in (1,2):
            spec=specs[key]
            if a['generator']!='scripts/testassets/generate.py' or a['parameters']!={k:v for k,v in spec.items() if k!='path'}:raise ValueError('recipe differs '+path)
            if a['pixel_size']!=[spec['width'],spec['height']]:raise ValueError('recipe dimensions differ '+path)
        else:
            for field in ('url','license_url','source_url','provenance_url'):
                if not a[field].startswith('https://'):raise ValueError('missing HTTPS source '+path)
            if not a['has_exif']:raise ValueError('photo requires EXIF '+path)
        if tier!=1 and not args.external:continue
        target=(args.small_root if tier==1 else args.generated_root if tier==2 else args.external_root)/relative
        data=target.read_bytes()
        if len(data)!=a['byte_size']:raise ValueError('byte size mismatch '+path)
        if hashlib.sha256(data).hexdigest()!=a['sha256']:raise ValueError('sha256 mismatch '+path)
        if tier in (1,2) and dimensions(data)!=a['pixel_size'] and a['parameters']['kind']!='corrupt':raise ValueError('header dimensions mismatch '+path)
        if tier==3 and data.startswith(b'version https://git-lfs'):raise ValueError('download is a pointer, not image bytes')
        if args.native and (tier==3 or (tier==1 and a['parameters']['kind'] not in ('corrupt','truncated','oversize'))):
            mode=['oriented-pixels'] if tier==1 and a['parameters']['kind']=='orientation' else []
            observed=json.loads(subprocess.check_output(['/usr/bin/osascript','-l','JavaScript',str(ROOT/'scripts/testassets/inspect.js'),str(target),*mode],text=True))
            if [observed['width'],observed['height']]!=a['pixel_size']:raise ValueError('ImageIO dimensions mismatch '+path)
            if tier==3 and not observed['hasExif']:raise ValueError('ImageIO found no EXIF '+path)
            if tier==1 and a['parameters']['kind']=='orientation' and (observed['orientation']!=a['parameters']['orientation'] or not observed['hasExif']):raise ValueError('ImageIO EXIF orientation mismatch '+path)
            if mode:
                if [observed['displayWidth'],observed['displayHeight']]!=a['display_size']:raise ValueError('oriented display size mismatch '+path)
                oriented_hashes.append(hashlib.sha256(base64.b64decode(observed['pixels'])).hexdigest())
            if tier==1 and a['parameters']['kind']=='alpha' and not observed['hasAlpha']:raise ValueError('ImageIO found no alpha '+path)
        checked[tier]+=1
        if tier==1:total_small+=len(data)
    if not set(specs).issubset(seen):raise ValueError('missing generated manifest entries')
    if counts!={1:14,2:5002,3:2}:raise ValueError('tier counts differ')
    disk={str(p.relative_to(args.small_root)) for p in args.small_root.rglob('*') if p.is_file() and str(p.relative_to(args.small_root)) not in ('README.md','manifest.json')}
    if disk!={p for tier,p in seen if tier==1}:raise ValueError('unlisted or missing tier-1 files')
    print(f'PASS manifest schema/recipes/licences: 5018 entries; verified tier1={checked[1]} tier2={checked[2]} tier3={checked[3]}; tier1 bytes={total_small}')
    if args.native:
        if len(oriented_hashes)!=8 or len(set(oriented_hashes))!=1:raise ValueError('orientations do not render identical upright pixels')
        print('PASS independent ImageIO: dimensions, EXIF orientations 1–8 render identical upright 128x96 pixels, alpha and photo EXIF')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,default=ROOT/'TestAssets/manifest.json')
    p.add_argument('--small-root',type=Path,default=ROOT/'TestAssets')
    p.add_argument('--generated-root',type=Path,default=Path.home()/'.picsee/testassets/generated')
    p.add_argument('--external-root',type=Path,default=Path.home()/'.picsee/testassets')
    p.add_argument('--external',action='store_true');p.add_argument('--native',action='store_true')
    try:verify(p.parse_args());return 0
    except Exception as e:print('FAIL manifest — '+str(e));return 1

if __name__=='__main__':sys.exit(main())
