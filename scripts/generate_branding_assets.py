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

# Ambient glowing atmosphere (soft cyan and purple radial glows)
glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow_layer)

for radius in range(360, 0, -15):
    alpha = int(14 * (1 - radius / 360))
    glow_draw.ellipse(
        [(960 - radius, 240 - radius), (960 + radius, 240 + radius)],
        fill=(0, 229, 255, alpha)
    )

for radius in range(300, 0, -15):
    alpha = int(16 * (1 - radius / 300))
    glow_draw.ellipse(
        [(1640 - radius, 320 - radius), (1640 + radius, 320 + radius)],
        fill=(139, 92, 246, alpha)
    )

glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(16))
banner = Image.alpha_composite(banner, glow_layer)

# Fonts
font_bold_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationSans-Bold.ttf"
font_reg_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationSans-Regular.ttf"
font_mono_path = "/nix/store/q073g38yhrjb3lh985r68k0553pmg2dd-liberation-fonts-2.1.5/share/fonts/truetype/LiberationMono-Bold.ttf"

font_title = ImageFont.truetype(font_bold_path, 74)
font_subtitle = ImageFont.truetype(font_bold_path, 24)
font_desc = ImageFont.truetype(font_reg_path, 18)
font_badge = ImageFont.truetype(font_bold_path, 15)
font_chip = ImageFont.truetype(font_bold_path, 13)
font_card_head = ImageFont.truetype(font_bold_path, 16)
font_card_lbl = ImageFont.truetype(font_bold_path, 13)
font_card_val = ImageFont.truetype(font_mono_path, 13)
font_footer = ImageFont.truetype(font_reg_path, 15)
font_footer_bold = ImageFont.truetype(font_bold_path, 15)

draw_banner = ImageDraw.Draw(banner)

# Center Content
cx = 620

# Status Chip
chip_y = 65
chip_w = 460
chip_h = 28
draw_banner.rounded_rectangle(
    [(cx, chip_y), (cx + chip_w, chip_y + chip_h)],
    radius=14,
    fill=(14, 20, 34, 220),
    outline=(0, 229, 255, 140),
    width=1
)
draw_banner.ellipse([(cx + 12, chip_y + 8), (cx + 22, chip_y + 18)], fill=(34, 197, 94, 255))
draw_banner.text((cx + 30, chip_y + 6), "PRODUCTION BASELINE v1.0.3  •  VERIFIED PRODUCTION-GRADE", font=font_chip, fill=(226, 232, 240, 255))

# Title
title_y = 106
draw_banner.text((cx + 4, title_y + 5), "NEURONIX OS", font=font_title, fill=(0, 0, 0, 220))
draw_banner.text((cx + 2, title_y + 2), "NEURONIX OS", font=font_title, fill=(0, 180, 216, 90))
draw_banner.text((cx, title_y), "NEURONIX OS", font=font_title, fill=(248, 250, 252, 255))

# Subtitle & Description
sub_y = 196
draw_banner.text((cx, sub_y), "The Autonomous, Declarative, Pure-Functional Linux Platform", font=font_subtitle, fill=(56, 189, 248, 255))

desc_y = 232
draw_banner.text((cx, desc_y), "Engineered on NixOS Substrate  •  Btrfs Subvolumes  •  Instant Atomic Rollback", font=font_desc, fill=(148, 163, 184, 255))

# Badges
badges = [
    ("Pure NixOS Substrate", (15, 23, 42), (56, 189, 248), (56, 189, 248), 235),
    ("Btrfs + Zstandard:3", (10, 35, 25), (16, 185, 129), (16, 185, 129), 215),
    ("Instant Zero-Loss Rollback", (35, 25, 10), (245, 158, 11), (245, 158, 11), 255),
    ("Native AI Copilot & MCP", (8, 30, 45), (6, 182, 212), (6, 182, 212), 235),
    ("Active Memory Shield", (30, 15, 45), (168, 85, 247), (168, 85, 247), 215),
    ("854 Verified Assertions", (15, 35, 20), (34, 197, 94), (34, 197, 94), 255)
]

badge_h = 36
badge_r = 8

row1_y = 280
b_x = cx
for label, bg, border, dot_col, bw in badges[:3]:
    draw_banner.rounded_rectangle(
        [(b_x, row1_y), (b_x + bw, row1_y + badge_h)],
        radius=badge_r,
        fill=(*bg, 230),
        outline=(*border, 180),
        width=1
    )
    draw_banner.ellipse([(b_x + 12, row1_y + 13), (b_x + 22, row1_y + 23)], fill=(*dot_col, 255))
    draw_banner.text((b_x + 30, row1_y + 9), label, font=font_badge, fill=(241, 245, 249, 255))
    b_x += bw + 15

row2_y = 330
b_x = cx
for label, bg, border, dot_col, bw in badges[3:]:
    draw_banner.rounded_rectangle(
        [(b_x, row2_y), (b_x + bw, row2_y + badge_h)],
        radius=badge_r,
        fill=(*bg, 230),
        outline=(*border, 180),
        width=1
    )
    draw_banner.ellipse([(b_x + 12, row2_y + 13), (b_x + 22, row2_y + 23)], fill=(*dot_col, 255))
    draw_banner.text((b_x + 30, row2_y + 9), label, font=font_badge, fill=(241, 245, 249, 255))
    b_x += bw + 15

foot_div_y = 398
for dx in range(cx, 1370):
    ratio = (dx - cx) / (1370 - cx)
    alpha = int(120 * math.sin(ratio * math.pi))
    draw_banner.line([(dx, foot_div_y), (dx, foot_div_y)], fill=(0, 229, 255, alpha), width=1)

foot_y = 416
specs = [
    ("Architectures:", " x86_64 & aarch64"),
    ("Installer:", " Calamares GUI + CLI"),
    ("Kernel:", " Zen • LTS • Hardened")
]

spec_x = cx
for label, val in specs:
    draw_banner.text((spec_x, foot_y), label, font=font_footer_bold, fill=(203, 213, 225, 255))
    lbl_w = int(font_footer_bold.getlength(label))
    draw_banner.text((spec_x + lbl_w, foot_y), val, font=font_footer, fill=(56, 189, 248, 255))
    val_w = int(font_footer.getlength(val))
    spec_x += lbl_w + val_w + 30

quote_y = 458
draw_banner.text(
    (cx, quote_y),
    "\"Zero Error Swallowing  •  Authentic Telemetry  •  Immutable Nix Store  •  Enterprise Ready\"",
    font=font_card_val,
    fill=(100, 116, 139, 255)
)

# Right Panel: Glassmorphism System Telemetry Card
tx = 1410
ty = 65
tw = 455
th = 510

telemetry_card = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
t_draw = ImageDraw.Draw(telemetry_card)
t_draw.rounded_rectangle(
    [(0, 0), (tw, th)],
    radius=16,
    fill=(12, 16, 28, 235),
    outline=(56, 189, 248, 120),
    width=1
)

t_draw.text((20, 18), "SYSTEM TELEMETRY", font=font_card_head, fill=(241, 245, 249, 255))
t_draw.rounded_rectangle([(tw - 105, 16), (tw - 20, 38)], radius=11, fill=(20, 35, 25, 240), outline=(34, 197, 94, 200), width=1)
t_draw.ellipse([(tw - 95, 23), (tw - 87, 31)], fill=(34, 197, 94, 255))
t_draw.text((tw - 80, 21), "ONLINE", font=font_chip, fill=(34, 197, 94, 255))

t_draw.line([(20, 48), (tw - 20, 48)], fill=(30, 41, 59, 255), width=1)

telemetry_data = [
    ("SUBSTRATE", "NixOS 26.05 Channel"),
    ("PLATFORM ARCH", "x86_64-linux & aarch64"),
    ("ROOT FILESYSTEM", "Btrfs (zstd:3) + Auto-TRIM"),
    ("MEMORY SHIELD", "ZRAM ZSTD + systemd-oomd"),
    ("ATOMIC UPGRADE", "Staged (nixos-rebuild boot)"),
    ("ROLLBACK GATE", "Zero-Loss (nixos-rebuild undo)"),
    ("AI COPILOT", "OpenCode + MCP JSON-RPC 2.0"),
    ("KERNEL FLAVOR", "default / zen / lts / hardened"),
    ("TEST HARNESS", "854 / 854 Assertions (100%)"),
    ("SECURITY POSTURE", "PolKit + Sudo Wheel + CA Store"),
    ("RELEASE ENGINE", "v1.0.3 Certified Production")
]

row_y = 62
for key, val in telemetry_data:
    t_draw.text((20, row_y), key, font=font_card_lbl, fill=(100, 116, 139, 255))
    t_draw.text((170, row_y), val, font=font_card_val, fill=(56, 189, 248, 255))
    t_draw.line([(20, row_y + 24), (tw - 20, row_y + 24)], fill=(20, 28, 42, 180), width=1)
    row_y += 38

t_draw.text((20, th - 30), "SHA-256 : da258b378acadb5ca477cbd17...", font=font_chip, fill=(71, 85, 105, 255))

banner.paste(telemetry_card, (tx, ty), telemetry_card)

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
