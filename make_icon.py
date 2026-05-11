"""Generate CodexUsage app icon.

Design: OpenAI-ish charcoal squircle with a green Codex prompt.
"""
from PIL import Image, ImageDraw, ImageFilter
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "icon_1024.png"

SIZE = 1024
PAD = 60
SQ = SIZE - 2 * PAD
RADIUS = int(SQ * 0.224)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

# Vertical gradient (near-black -> soft OpenAI green-black)
top = (32, 35, 32)
bot = (8, 44, 36)
strip = Image.new("RGB", (1, SQ))
for y in range(SQ):
    t = y / SQ
    strip.putpixel((0, y), tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)))
grad = strip.resize((SQ, SQ))

# Squircle mask
mask = Image.new("L", (SQ, SQ), 0)
ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (SQ, SQ)], radius=RADIUS, fill=255)
img.paste(grad, (PAD, PAD), mask)

# Soft green glow
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse(
    [
        (int(SIZE * 0.20), int(SIZE * 0.06)),
        (int(SIZE * 0.98), int(SIZE * 0.76)),
    ],
    fill=(16, 163, 127, 80),
)
glow = glow.filter(ImageFilter.GaussianBlur(radius=80))
img.alpha_composite(glow)

# Soft top highlight
hl = Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0))
ImageDraw.Draw(hl).rounded_rectangle(
    [(0, 0), (SQ, int(SQ * 0.42))], radius=RADIUS, fill=(255, 255, 255, 32)
)
hl_blur = hl.filter(ImageFilter.GaussianBlur(radius=35))
hl_masked = Image.composite(hl_blur, Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0)), mask)
img.alpha_composite(hl_masked, (PAD, PAD))

# Inner top-edge sheen
sheen = Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0))
ImageDraw.Draw(sheen).rounded_rectangle(
    [(0, 0), (SQ, int(SQ * 0.08))], radius=RADIUS, fill=(255, 255, 255, 42)
)
sheen_blur = sheen.filter(ImageFilter.GaussianBlur(radius=15))
sheen_masked = Image.composite(sheen_blur, Image.new("RGBA", (SQ, SQ), (0, 0, 0, 0)), mask)
img.alpha_composite(sheen_masked, (PAD, PAD))

# Codex prompt mark
draw = ImageDraw.Draw(img)
stroke = int(SIZE * 0.07)
green = (16, 163, 127, 255)
white = (246, 247, 244, 255)

left = int(SIZE * 0.30)
mid_y = int(SIZE * 0.48)
arrow = int(SIZE * 0.13)
draw.line([(left, mid_y - arrow), (left + arrow, mid_y), (left, mid_y + arrow)],
          fill=green, width=stroke, joint="curve")

cap = stroke // 2
for x, y in [(left, mid_y - arrow), (left + arrow, mid_y), (left, mid_y + arrow)]:
    draw.ellipse([(x - cap, y - cap), (x + cap, y + cap)], fill=green)

underline_y = int(SIZE * 0.64)
draw.line([(int(SIZE * 0.48), underline_y), (int(SIZE * 0.72), underline_y)],
          fill=white, width=stroke)
for x in [int(SIZE * 0.48), int(SIZE * 0.72)]:
    draw.ellipse([(x - cap, underline_y - cap), (x + cap, underline_y + cap)], fill=white)

if OUT.lower().endswith(".icns"):
    img.save(
        OUT,
        format="ICNS",
        sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)],
    )
else:
    img.save(OUT)
print(f"Saved {OUT} ({img.size[0]}x{img.size[1]})")
