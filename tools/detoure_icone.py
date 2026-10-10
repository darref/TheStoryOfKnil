import sys
from collections import deque
from PIL import Image, ImageFilter
import numpy as np
src, out = sys.argv[1], sys.argv[2]
im = np.array(Image.open(src).convert('RGB')).astype(int)
h, w, _ = im.shape
mx, mn = im.max(2), im.min(2)
# Fond : un gris NEUTRE et clair (le fond ~204, l'anneau ~240). La tunique écrue n'est pas neutre, le trait noir non plus.
fondable = ((mx - mn) <= 12) & (mn >= 180)
bg = np.zeros((h, w), bool)
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if fondable[y, x] and not bg[y, x]:
            bg[y, x] = True; q.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if fondable[y, x] and not bg[y, x]:
            bg[y, x] = True; q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and fondable[ny, nx]:
            bg[ny, nx] = True; q.append((ny, nx))
# Les îlots de fond enfermés (entre le doigt et l'oreille…) : un gris neutre clair entouré de fond, plus grand que 40 px.
from scipy import ndimage
lab, n = ndimage.label(fondable & ~bg)
sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
for i, s in enumerate(sizes, 1):
    if s > 40:
        comp = lab == i
        ring = ndimage.binary_dilation(comp, iterations=3) & ~comp
        # îlot dont le pourtour est surtout du trait sombre : du fond vu à travers le personnage
        if (mx[ring] < 90).mean() > 0.5 and im[comp].mean() < 215:
            bg |= comp
alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8))
alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
rgba = Image.fromarray(im.astype(np.uint8)).convert('RGBA'); rgba.putalpha(alpha)
box = alpha.point(lambda v: 255 if v > 8 else 0).getbbox()
rgba = rgba.crop(box)
side = max(rgba.size); pad = int(side * 0.04); side += 2 * pad
sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
sq.paste(rgba, ((side - rgba.size[0]) // 2, (side - rgba.size[1]) // 2))
sq = sq.resize((1024, 1024), Image.LANCZOS)
sq.save(out)
print('boite', box, 'iles', n)
