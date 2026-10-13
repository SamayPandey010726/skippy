#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
template=(root/'Preview/preview-template.html').read_text()
art=(root/'Preview/parcel-art.svg').read_text().replace('<svg xmlns=', '<svg class="box" xmlns=',1)
result=template.replace('__CSS__',(root/'Preview/preview.css').read_text()).replace('__ART__',art).replace('__FFLATE__',(root/'Preview/fflate.js').read_text().replace('</script','<\\/script')).replace('__JS__',(root/'Preview/preview.js').read_text())
(root/'Preview/Parcel-preview.html').write_text(result)
print(root/'Preview/Parcel-preview.html')
