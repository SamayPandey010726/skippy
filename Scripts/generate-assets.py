#!/usr/bin/env python3
"""Original procedural art and very quiet paper sound; no downloaded artwork."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import random,math,wave,struct
root=Path(__file__).resolve().parents[1]
assets=root/'Assets';assets.mkdir(exist_ok=True)
samples=root/'Samples';samples.mkdir(exist_ok=True)
resources=root/'Sources/ParcelApp/Resources';resources.mkdir(exist_ok=True)
s=3;im=Image.new('RGBA',(1024*s,1024*s),(0,0,0,0));d=ImageDraw.Draw(im)
def poly(points,color):d.polygon([(int(x*s),int(y*s))for x,y in points],fill=color)
def ellipse(box,color):d.ellipse(tuple(int(x*s)for x in box),fill=color)
# Two fletchings share a diagonal, matching the quiver mark in AppKit.
d.rounded_rectangle((96*s,96*s,928*s,928*s),radius=185*s,fill='#1d4938',outline='#55735a',width=5*s)
poly([(245,530),(505,270),(640,270),(380,530)],'#bfda94')
poly([(300,750),(750,300),(850,300),(400,750)],'#e0f4ab')
icon=im.resize((1024,1024),Image.Resampling.LANCZOS);icon.save(assets/'AppIcon-1024.png')
iconset=assets/'AppIcon.iconset';iconset.mkdir(exist_ok=True)
for n in [16,32,128,256,512]:
 icon.resize((n,n),Image.Resampling.LANCZOS).save(iconset/f'icon_{n}x{n}.png')
 icon.resize((n*2,n*2),Image.Resampling.LANCZOS).save(iconset/f'icon_{n}x{n}@2x.png')
land=Image.new('RGB',(1200,820),'#e8edda');ld=ImageDraw.Draw(land)
ld.ellipse((887,112,1040,265),fill='#f4dba1');ld.polygon([(0,600),(400,363),(800,502),(1200,414),(1200,820),(0,820)],fill='#a6b98b')
ld.polygon([(0,741),(457,574),(820,657),(1200,525),(1200,820),(0,820)],fill='#819f6d')
ld.rectangle((449,392,746,637),fill='#d9c08e');ld.polygon([(412,406),(590,244),(789,406)],fill='#778e65')
ld.rectangle((489,444,550,512),fill='#f4edd1');ld.rectangle((646,444,705,512),fill='#f4edd1');ld.rectangle((571,523,632,637),fill='#917b57')
land.save(samples/'A little place.png')
(samples/'Launch notes.txt').write_text('The little launch kit\n\nA calm, useful way to gather, prepare and send your files.\n')
(samples/'Garden sketch.svg').write_bytes((root/'Preview/parcel-art.svg').read_bytes())
audio=[];rng=random.Random(7);rate=22050
for n in range(int(rate*.22)):
 t=n/rate;envelope=math.exp(-t*23)*(1-math.exp(-t*130))
 value=(rng.random()*2-1)*envelope*.085+math.sin(2*math.pi*190*t)*envelope*.035
 audio.append(struct.pack('<h',int(max(-1,min(1,value))*32767)))
with wave.open(str(resources/'paper-seal.wav'),'wb')as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(b''.join(audio))
print('Original icon, sample files and optional paper sound generated.')
