#!/usr/bin/env python3
"""Deterministic P0-07 fixtures. Python stdlib only; no clocks, fonts or codecs from the host."""
import argparse
import hashlib
from pathlib import Path
import struct
import zlib

VERSION = 1
# A deliberately tiny, fixed 5x7 bitmap alphabet, authored for these fixtures.
FONT = {
 '0':['01110','10001','10011','10101','11001','10001','01110'],
 '1':['00100','01100','00100','00100','00100','00100','01110'],
 '2':['01110','10001','00001','00010','00100','01000','11111'],
 '3':['11110','00001','00001','01110','00001','00001','11110'],
 '4':['00010','00110','01010','10010','11111','00010','00010'],
 '5':['11111','10000','10000','11110','00001','00001','11110'],
 '6':['01110','10000','10000','11110','10001','10001','01110'],
 '7':['11111','00001','00010','00100','01000','01000','01000'],
 '8':['01110','10001','10001','01110','10001','10001','01110'],
 '9':['01110','10001','10001','01111','00001','00001','01110'],
 ',':['00000','00000','00000','00000','00100','00100','01000'],
 'T':['11111','00100','00100','00100','00100','00100','00100'],
 'O':['01110','10001','10001','10001','10001','10001','01110'],
 'P':['11110','10001','10001','11110','10000','10000','10000'],
 'L':['10000','10000','10000','10000','10000','10000','11111'],
 'R':['11110','10001','10001','11110','10100','10010','10001'],
}

def text(pixels, width, x, y, label, scale=2):
    for char in label:
        for dy, row in enumerate(FONT[char]):
            for dx, bit in enumerate(row):
                if bit == '1':
                    for sy in range(scale):
                        for sx in range(scale):
                            pixels[(y + dy*scale + sy)*width + x + dx*scale + sx] = 0
        x += 6*scale

def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind+payload) & 0xffffffff)

def png(width, height, rows, rgba=False):
    encoder = zlib.compressobj(9, zlib.DEFLATED, 15, strategy=zlib.Z_FIXED)
    compressed = bytearray()
    for row in rows:
        compressed.extend(encoder.compress(b'\0' + row))
    compressed.extend(encoder.flush())
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6 if rgba else 0, 0, 0, 0))
            + chunk(b'IDAT', compressed) + chunk(b'IEND', b''))

def grid(width, height, spacing):
    pixels = bytearray([255]) * (width*height)
    for y in range(height):
        for x in range(width):
            if x % spacing == 0 or y % spacing == 0: pixels[y*width+x] = 0
            elif x % 32 == 0 or y % 32 == 0: pixels[y*width+x] = 210
    for y in range(0, height, spacing):
        for x in range(0, width, spacing):
            text(pixels, width, x+6, y+8, f'{x},{y}')
    return png(width, height, (pixels[y*width:(y+1)*width] for y in range(height)))

def tiff(width, height, pixels, orientation=1, exif=False):
    # TIFF/EXIF Orientation (0x0112), uncompressed 8-bit grayscale, one strip.
    root_end=8+2+(11 if exif else 10)*12+4
    exif_data=(struct.pack('<H',3)+struct.pack('<HHI4s',36864,7,4,b'0232')+
               struct.pack('<HHII',40962,4,1,width)+struct.pack('<HHII',40963,4,1,height)+b'\0'*4) if exif else b''
    fields = [(256,4,width),(257,4,height),(258,3,8),(259,3,1),(262,3,1),
              (273,4,root_end+len(exif_data)),(274,3,orientation),(277,3,1),(278,4,height),(279,4,len(pixels))]
    if exif: fields.append((34665,4,root_end))
    directory = b''.join(struct.pack('<HHI', tag, kind, 1) +
                         (struct.pack('<H', value)+b'\0\0' if kind==3 else struct.pack('<I',value))
                         for tag,kind,value in fields)
    return b'II*\0'+struct.pack('<I',8)+struct.pack('<H',len(fields))+directory+b'\0'*4+exif_data+pixels

def oriented(orientation):
    width, height = 128, 96
    upright = bytearray([255]) * (width*height)
    text(upright,width,38,6,'TOP',3)
    text(upright,width,8,68,'L',2)
    text(upright,width,108,68,'R',2)
    for y in range(35,82):
        for x in range(44,85):
            if (y < 56 and abs(x-64) <= y-35) or (y >= 50 and 59 <= x <= 69): upright[y*width+x] = 0
    sw, sh = (width,height) if orientation<=4 else (height,width)
    def display(x,y):
        return {1:lambda:(x,y),2:lambda:(sw-1-x,y),3:lambda:(sw-1-x,sh-1-y),4:lambda:(x,sh-1-y),
                5:lambda:(y,x),6:lambda:(sh-1-y,x),7:lambda:(sh-1-y,sw-1-x),8:lambda:(y,sw-1-x)}[orientation]()
    raw=bytearray()
    for y in range(sh):
        for x in range(sw):
            dx,dy=display(x,y);raw.append(upright[dy*width+dx])
    return tiff(sw,sh,bytes(raw),orientation,exif=True)

def small_specs():
    result=[dict(path='synthetic/checkerboard-1px.png',kind='checkerboard',width=1024,height=768),
            dict(path='synthetic/coordinate-grid.png',kind='grid',width=1280,height=960,spacing=128)]
    result += [dict(path=f'synthetic/orientation-{i}.tiff',kind='orientation',width=128 if i<=4 else 96,
                    height=96 if i<=4 else 128,orientation=i) for i in range(1,9)]
    result += [dict(path='synthetic/alpha-gradient.png',kind='alpha',width=256,height=128),
               dict(path='synthetic/truncated.png',kind='truncated',width=64,height=48),
               dict(path='synthetic/corrupt.png',kind='corrupt',width=None,height=None),
               dict(path='synthetic/oversize-header.png',kind='oversize',width=2147483647,height=2147483647)]
    return result

def bulk_specs():
    return [dict(path=f'S2/group-{i//100:02d}/nested-{i%5}/image-{i%100:03d}.' + ('png' if i%2==0 else 'tiff'),
                 kind='bulk-png' if i%2==0 else 'bulk-tiff', width=64+i%3*16, height=48+i%3*12, seed=i)
            for i in range(5000)]

def large_specs():
    return [dict(path='S3/noise-48mp.png',kind='noise',width=8000,height=6000,seed=48007),
            dict(path='S3/noise-100mp.png',kind='noise',width=10000,height=10000,seed=100007)]

def render(spec):
    w,h=spec['width'],spec['height'];kind=spec['kind']
    if kind=='checkerboard':return png(w,h,(bytes(255*((x+y)%2) for x in range(w)) for y in range(h)))
    if kind=='grid':return grid(w,h,spec['spacing'])
    if kind=='orientation':return oriented(spec['orientation'])
    if kind=='alpha':return png(w,h,(bytes(v for x in range(w) for v in (240,40,100,x)) for _ in range(h)),True)
    if kind=='corrupt':return b'PICSEE deliberately corrupt image\0not a PNG\n'
    if kind=='truncated':return png(w,h,(bytes([y])*w for y in range(h)))[:48]
    if kind=='oversize':return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,0,0,0,0))+chunk(b'IEND',b'')
    if kind in ('bulk-png','bulk-tiff','noise'):
        rows=(hashlib.shake_256(f'picsee-v1:{spec["seed"]}:{y}'.encode('ascii')).digest(w) for y in range(h))
        return tiff(w,h,b''.join(rows)) if kind=='bulk-tiff' else png(w,h,rows)
    raise ValueError(kind)

def generate(output, specs):
    for spec in specs:
        target=output/spec['path'];target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(render(spec))
    print(f'PASS generated {len(specs)} fixtures at {output}')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--tier',choices=['small','bulk','large','all'],default='small')
    args=parser.parse_args()
    specs={'small':small_specs,'bulk':bulk_specs,'large':large_specs,
           'all':lambda:small_specs()+bulk_specs()+large_specs()}[args.tier]()
    repo=Path(__file__).resolve().parents[2]
    output=args.output.expanduser().resolve()
    if args.tier!='small' and (output==repo or repo in output.parents):
        parser.error('bulk/large output must be outside the repository')
    generate(output,specs)
