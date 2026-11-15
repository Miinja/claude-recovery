# Draws the installer's icon (installer/app.ico): a "bring it back" arrow on the
# application's accent colour. Needs Pillow; run it again only to change the drawing.
#
#   python installer/make-icon.py
import math
import os

from PIL import Image, ImageDraw

BACK = (22, 24, 31, 255)
ACCENT = (108, 140, 255, 255)
WHITE = (255, 255, 255, 255)


def draw(size):
    k = 8                                    # supersampling
    n = size * k
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=int(n * 0.22), fill=BACK)
    m = n * 0.14
    d.ellipse([m, m, n - m, n - m], fill=ACCENT)

    # Counter-clockwise arrow: an open ring, with its head at the top left.
    cx = cy = n / 2
    r = n * 0.20
    w = max(2, int(n * 0.075))
    start, end = -150, 120                   # degrees, clockwise from 3 o'clock
    d.arc([cx - r, cy - r, cx + r, cy + r], start=start, end=end, fill=WHITE, width=w)
    a = math.radians(end)
    # Round the tail of the arc.
    tx, ty = cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
    d.ellipse([tx - w / 2, ty - w / 2, tx + w / 2, ty + w / 2], fill=WHITE)
    # Arrow head at the start of the arc, pointing back along it.
    s = math.radians(start)
    px, py = cx + (r - w / 2) * math.cos(s), cy + (r - w / 2) * math.sin(s)
    tangent = s - math.pi / 2                # direction of travel, counter-clockwise
    h = w * 1.55
    tip = (px + h * 1.25 * math.cos(tangent), py + h * 1.25 * math.sin(tangent))
    left = (px + h * math.cos(s), py + h * math.sin(s))
    right = (px - h * math.cos(s), py - h * math.sin(s))
    d.polygon([tip, left, right], fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


here = os.path.dirname(os.path.abspath(__file__))
sizes = [16, 24, 32, 48, 64, 128, 256]
images = [draw(s) for s in sizes]
images[-1].save(os.path.join(here, 'app.ico'), format='ICO', sizes=[(s, s) for s in sizes],
                append_images=images[:-1])
images[-1].save(os.path.join(here, 'out', 'icon-preview.png')) if os.path.isdir(os.path.join(here, 'out')) else None
print('app.ico written')
