#!/usr/bin/env python3
"""
NEURONIX OS Official Branding & Banner Generator
Generates canonical multi-resolution logo assets, symbol icons, and the 1920x640 GitHub header banner.
"""

import os, math, shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRANDING_DIR = os.path.join(REPO_ROOT, "artwork", "branding")
SOURCE_LOGO = os.path.join(REPO_ROOT, "Neuronix_Logo.png")

os.makedirs(BRANDING_DIR, exist_ok=True)

print(f"[*] Processing official logo from: {SOURCE_LOGO}")
logo_master = Image.open(SOURCE_LOGO).convert("RGBA")

# 1. Canonical Master Logo
canonical_logo_path = os.path.join(BRANDING_DIR, "neuronix-logo.png")
shutil.copyfile(SOURCE_LOGO, canonical_logo_path)
print(f"[*] Saved canonical logo -> {canonical_logo_path} (2048x2048)")

# 2. Multi-Resolution Logo Assets
resolutions = [1024, 512, 256, 128, 64]
for res in resolutions:
    scaled = logo_master.resize((res, res), Image.Resampling.LANCZOS)
    out_path = os.path.join(BRANDING_DIR, f"neuronix-logo-{res}.png")
    scaled.save(out_path, "PNG", optimize=True)
    print(f"[*] Generated logo icon -> {out_path} ({res}x{res})")

# 3. Square 3D Mondrian "N" Symbol Icon (Authentic Grid Background)
symbol_base = logo_master.copy()
grid_row = logo_master.crop((0, 1843, 2048, 1945))
symbol_base.paste(grid_row, (0, 1536))
symbol_base.paste(grid_row, (0, 1638))
symbol_base.paste(grid_row, (0, 1740))

symbol_512 = symbol_base.resize((512, 512), Image.Resampling.LANCZOS)
symbol_path = os.path.join(BRANDING_DIR, "neuronix-symbol.png")
symbol_512.save(symbol_path, "PNG", optimize=True)
print(f"[*] Generated symbol icon -> {symbol_path} (512x512)")

# 4. Generate Official GitHub Header Banner (1920x640) - Seamless Authentic Background
W, H = 1920, 640
logo_scaled = logo_master.resize((H, H), Image.Resampling.LANCZOS)

banner = Image.new("RGBA", (W, H), (0, 0, 0, 255))
banner.paste(logo_scaled, (0, 0))

# Seamless background extension using authentic grid period (strip width 27, height 640)
# Columns 613..640 in logo_scaled form an exact 27px period with zero boundary mismatch
strip = logo_scaled.crop((613, 0, 640, H))
for x in range(640, W, 27):
    banner.paste(strip, (x, 0))

## Ambient soft glowing atmosphere
glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow_layer)

for radius in range(380, 0, -15):
    alpha = int(14 * (1 - radius / 380))
    glow_draw.ellipse(
        [(1050 - radius, 280 - radius), (1050 + radius, 280 + radius)],
        fill=(0, 229, 255, alpha)
    )

for radius in range(320, 0, -15):
    alpha = int(14 * (1 - radius / 320))
    glow_draw.ellipse(
        [(1550 - radius, 340 - radius), (1550 + radius, 340 + radius)],
        fill=(139, 92, 246, alpha)
    )

glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(16))
banner = Image.alpha_composite(banner, glow_layer)

# Fonts
font_bold_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationSans-Bold.ttf"
font_reg_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationSans-Regular.ttf"
font_mono_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationMono-Bold.ttf"

font_title = ImageFont.truetype(font_bold_path, 82)
font_subtitle = ImageFont.truetype(font_bold_path, 28)
font_desc = ImageFont.truetype(font_reg_path, 20)
font_pillar = ImageFont.truetype(font_bold_path, 18)
font_footer = ImageFont.truetype(font_reg_path, 17)
font_footer_bold = ImageFont.truetype(font_bold_path, 17)
font_quote = ImageFont.truetype(font_mono_path, 15)

draw_banner = ImageDraw.Draw(banner)

cx = 640

# Title (Clean, bold typography without version pill)
title_y = 100
draw_banner.text((cx + 4, title_y + 5), "NEURONIX OS", font=font_title, fill=(0, 0, 0, 240))
draw_banner.text((cx + 2, title_y + 2), "NEURONIX OS", font=font_title, fill=(0, 180, 216, 100))
draw_banner.text((cx, title_y), "NEURONIX OS", font=font_title, fill=(248, 250, 252, 255))

# Subtitle
sub_y = 202
draw_banner.text((cx, sub_y), "The Autonomous, Declarative, Pure-Functional Linux Platform", font=font_subtitle, fill=(56, 189, 248, 255))

# Description Tagline
desc_y = 246
draw_banner.text((cx, desc_y), "Engineered on NixOS Substrate  •  Btrfs Subvolumes  •  Instant Atomic Rollback", font=font_desc, fill=(148, 163, 184, 255))

# Architectural Pillars (Clean typography with colored indicator dots, NO WRAPPERS/PILLS)
pillars_row1 = [
    ("Pure NixOS Substrate", (56, 189, 248)),
    ("Btrfs + Zstandard:3 Compression", (52, 211, 153)),
    ("Instant Zero-Loss Rollback", (251, 191, 36))
]

pillars_row2 = [
    ("Native AI Copilot & MCP", (34, 211, 238)),
    ("Active Memory Shield (ZRAM + PSI)", (192, 132, 252)),
    ("854 Verified Industrial Assertions", (74, 222, 128))
]

p_y1 = 310
p_x = cx
for text, dot_col in pillars_row1:
    draw_banner.ellipse([(p_x, p_y1 + 5), (p_x + 10, p_y1 + 15)], fill=(*dot_col, 255))
    draw_banner.text((p_x + 20, p_y1), text, font=font_pillar, fill=(226, 232, 240, 255))
    txt_w = int(font_pillar.getlength(text))
    p_x += txt_w + 50

p_y2 = 352
p_x = cx
for text, dot_col in pillars_row2:
    draw_banner.ellipse([(p_x, p_y2 + 5), (p_x + 10, p_y2 + 15)], fill=(*dot_col, 255))
    draw_banner.text((p_x + 20, p_y2), text, font=font_pillar, fill=(226, 232, 240, 255))
    txt_w = int(font_pillar.getlength(text))
    p_x += txt_w + 50

# Divider line
div_y = 415
for dx in range(cx, 1820):
    ratio = (dx - cx) / (1820 - cx)
    alpha = int(140 * math.sin(ratio * math.pi))
    draw_banner.line([(dx, div_y), (dx, div_y)], fill=(0, 229, 255, alpha), width=1)

# Specifications line
foot_y = 445
specs = [
    ("Architectures:", " x86_64-linux & aarch64-linux"),
    ("Kernel Flavors:", " Zen • LTS • Hardened • Default"),
    ("Installer Engine:", " Calamares GUI & Declarative Generator")
]

spec_x = cx
for label, val in specs:
    draw_banner.text((spec_x, foot_y), label, font=font_footer_bold, fill=(203, 213, 225, 255))
    lbl_w = int(font_footer_bold.getlength(label))
    draw_banner.text((spec_x + lbl_w, foot_y), val, font=font_footer, fill=(56, 189, 248, 255))
    val_w = int(font_footer.getlength(val))
    spec_x += lbl_w + val_w + 40

# Quality Declaration
quote_y = 502
draw_banner.text(
    (cx, quote_y),
    "\"Zero Error Swallowing  •  Authentic Telemetry  •  Immutable Nix Store  •  Production Baseline\"",
    font=font_quote,
    fill=(100, 116, 139, 255)
)

# Top & Bottom subtle neon borders
for x in range(W):
    ratio = x / W
    alpha = int(220 * math.sin(ratio * math.pi))
    draw_banner.line([(x, H - 2), (x, H - 2)], fill=(0, 229, 255, alpha), width=2)
    draw_banner.line([(x, 0), (x, 0)], fill=(0, 180, 216, alpha // 2), width=1)

banner_path = os.path.join(BRANDING_DIR, "neuronix-banner.png")
banner.save(banner_path, "PNG", optimize=True)
print(f"[*] Generated official GitHub header banner -> {banner_path} (1920x640)")
print("[✓] All branding assets generated successfully!")
