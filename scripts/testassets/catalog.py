#!/usr/bin/env python3
"""Rebuild the manifest after explicit review of generator/source changes."""
import argparse
import hashlib
import json
from pathlib import Path
import generate

ROOT=Path(__file__).resolve().parents[2]
COMMIT='df0d5df406ad0dbe2124d6f2a3700fe73dd3ead7'
UPSTREAM='https://github.com/aaron-rust/hdr-sample-images'
PHOTOS=[('5B_JPEG_SDR.jpg',10500045,'b4d013555225a431fb744d44863db529c9b34ba90843842a4b7aa450857bd6c9'),
        ('3B_HEIC_SDR.heic',4479456,'0e366a983db397b1c1fbcb638e51ecbb6f2163f03f1e652f62ec8e192d96ce6e')]

def generated_record(spec,tier,root):
    path=root/spec['path'];data=path.read_bytes()
    result=dict(tier=tier,path=spec['path'],pixel_size=[spec['width'],spec['height']],byte_size=len(data),
                sha256=hashlib.sha256(data).hexdigest(),generator='scripts/testassets/generate.py',
                parameters={k:v for k,v in spec.items() if k!='path'},license='CC0-1.0')
    if spec['kind']=='orientation':result['display_size']=[128,96]
    if spec['kind'] in ('corrupt','truncated','oversize'):
        result['expected']='decode failure; oversize dimensions must be rejected before pixel allocation' if spec['kind']=='oversize' else 'decode failure'
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generated-root',type=Path,default=Path.home()/'.picsee/testassets/generated')
    parser.add_argument('--photo-root',type=Path,default=Path.home()/'.picsee/testassets/photos')
    args=parser.parse_args()
    assets=[generated_record(s,1,ROOT/'TestAssets') for s in generate.small_specs()]
    assets += [generated_record(s,2,args.generated_root) for s in generate.bulk_specs()+generate.large_specs()]
    for name,size,digest in PHOTOS:
        data=(args.photo_root/name).read_bytes()
        if len(data)!=size or hashlib.sha256(data).hexdigest()!=digest:raise ValueError('unverified source '+name)
        source_path='different_file_formats_in_sdr_and_hdr/'+name
        assets.append(dict(tier=3,path='photos/'+name,pixel_size=[8256,5504],byte_size=size,sha256=digest,
            url=f'https://media.githubusercontent.com/media/aaron-rust/hdr-sample-images/{COMMIT}/{source_path}',
            source_url=f'{UPSTREAM}/blob/{COMMIT}/{source_path}',license='CC0-1.0',
            license_url=f'{UPSTREAM}/blob/{COMMIT}/LICENSE',provenance_url=f'{UPSTREAM}/blob/{COMMIT}/README.md',
            has_exif=True,content='real photograph; Nikon Z8, upstream developed SDR'))
    metadata=dict(schema='picsee-testassets/v1',generator_version=generate.VERSION,
        generator_sha256=hashlib.sha256((ROOT/'scripts/testassets/generate.py').read_bytes()).hexdigest(),
        roots={'1':'TestAssets/','2':'~/.picsee/testassets/generated/','3':'~/.picsee/testassets/'},
        performance_rule='Flat synthetic images must never feed performance numbers. All generated fixtures here are correctness/stress data, not a photo performance baseline.',
        gaps=['S1 recommended 50-file 1–12MP mixed photo corpus is not complete; selected real photos are 45.4MP.',
              'S4 RAW/GIF/PDF sources are deferred; no unsupported licence or format claim.',
              'S5 replacement/symlink/permissions/unmount and S6 multiwindow/pins require runtime setup, not static files.'])
    # One record per line keeps the 5000-file index reviewable without bloating indentation.
    header=json.dumps(metadata,indent=2)[:-2]
    output=header+',\n  "assets": [\n'+',\n'.join('    '+json.dumps(a,sort_keys=True,separators=(',',':')) for a in assets)+'\n  ]\n}\n'
    (ROOT/'TestAssets/manifest.json').write_text(output)
    print(f'PASS catalogued {len(assets)} assets (14 committed; 5002 generated externally; 2 downloaded externally)')

if __name__=='__main__':main()
