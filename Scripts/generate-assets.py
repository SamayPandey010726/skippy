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
d.rounded_rectangle((40*s,40*s,984*s,984*s),radius=210*s,fill='#f8f3df')
shadow=Image.new('RGBA',im.size);sd=ImageDraw.Draw(shadow);sd.ellipse((205*s,770*s,845*s,842*s),fill=(60,78,42,36));im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18*s)));d=ImageDraw.Draw(im)
# One stationery family: kraft folder, forest tab, small face and metal clip.
poly([(183,785),(183,286),(310,286),(350,340),(800,340),(800,785)],'#d0ac77')
d.rounded_rectangle((790*s,460*s,866*s,637*s),radius=20*s,fill='#4e6965')
d.rounded_rectangle((182*s,355*s,802*s,787*s),radius=16*s,fill='#dfbd8b',outline='#ad8b60',width=2*s)
d.rounded_rectangle((260*s,485*s,493*s,556*s),radius=7*s,fill='#eee6d1',outline='#c2b18c',width=2*s)
d.line((294*s,514*s,451*s,514*s),fill='#667771',width=7*s)
d.line((294*s,532*s,408*s,532*s),fill='#9aa395',width=5*s)
ellipse((622,646,635,663),'#494439');ellipse((683,646,696,663),'#494439')
d.arc((648*s,672*s,671*s,692*s),0,180,fill='#635440',width=3*s)
d.rounded_rectangle((260*s,307*s,298*s,463*s),radius=17*s,outline='#72796f',width=7*s)
d.rounded_rectangle((273*s,318*s,289*s,443*s),radius=9*s,outline='#d6dbd1',width=3*s)
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
