#!/usr/bin/env python3
"""Builds the app icon and the menu bar icon from a logo on a white background.

Usage: generate-icons.py <logo-image> <resources-dir>

Writes AppIcon.png, AppIcon.icns and MenuBarIcon.png. Needs Pillow and macOS iconutil.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

CANVAS = 1024
# Apple's icon grid: an 824 px rounded square centered on a 1024 px canvas.
BODY = 824
BODY_RADIUS = 185
LOGO_SIZE = 640
MENU_BAR_PIXELS = 36
ICONSET_SIZES = [16, 32, 128, 256, 512]


def ink_mask(logo):
    """Returns an opaque mask of everything that is not background, including the orange dot."""
    red, green, blue = logo.convert("RGB").split()
    darkest = ImageChops.darker(ImageChops.darker(red, green), blue)
    return ImageChops.invert(darkest).point(lambda value: min(255, max(0, (value - 30) * 3)))


def cropped_to_ink(logo):
    return logo.crop(ink_mask(logo).point(lambda value: 255 if value > 128 else 0).getbbox())


def fit(image, size):
    scale = size / max(image.size)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def centered_offset(outer, inner):
    return (outer - inner.width) // 2, (outer - inner.height) // 2


def rounded_mask():
    scale = 4
    mask = Image.new("L", (CANVAS * scale, CANVAS * scale), 0)
    inset = (CANVAS - BODY) // 2 * scale
    box = (inset, inset, (CANVAS * scale) - inset, (CANVAS * scale) - inset)
    ImageDraw.Draw(mask).rounded_rectangle(box, BODY_RADIUS * scale, fill=255)
    return mask.resize((CANVAS, CANVAS), Image.LANCZOS)


def make_app_icon(logo):
    mask = rounded_mask()
    shadow_alpha = mask.point(lambda value: value * 80 // 255).filter(ImageFilter.GaussianBlur(14))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 255), (0, 12), shadow_alpha)
    shadow.putalpha(ImageChops.offset(shadow_alpha, 0, 12))

    body = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 255))
    artwork = fit(cropped_to_ink(logo).convert("RGB"), LOGO_SIZE)
    # The source is a JPEG, so its near-white background is flattened to pure white.
    artwork = artwork.point(lambda value: 255 if value > 245 else value)
    body.paste(artwork, centered_offset(CANVAS, artwork))
    body.putalpha(mask)
    return Image.alpha_composite(shadow, body)


def make_menu_bar_icon():
    """Draws the logo simplified by hand, because its fine sleepers blur together at 18 points."""
    scale = 8
    mask = Image.new("L", (MENU_BAR_PIXELS * scale, MENU_BAR_PIXELS * scale), 0)
    draw = ImageDraw.Draw(mask)

    def polygon(points):
        draw.polygon([(x * scale, y * scale) for x, y in points], fill=255)

    def mirrored(x):
        return MENU_BAR_PIXELS - x

    def inner_rail_x(y):
        return 6 + (17.8 - 6) * (35.5 - y) / (35.5 - 11)

    draw.ellipse((14 * scale, 0.5 * scale, 22 * scale, 8.5 * scale), fill=255)
    for side in (lambda x: x, mirrored):
        polygon([(side(1), 35.5), (side(6), 35.5), (side(17.8), 11), (side(17.2), 11)])
    for top, bottom in ((29.5, 33), (23, 25.8), (18, 20)):
        left_top, left_bottom = inner_rail_x(top) + 1.4, inner_rail_x(bottom) + 1.4
        polygon([(left_top, top), (mirrored(left_top), top), (mirrored(left_bottom), bottom), (left_bottom, bottom)])

    mask = mask.resize((MENU_BAR_PIXELS, MENU_BAR_PIXELS), Image.LANCZOS)
    icon = Image.new("RGBA", mask.size, (0, 0, 0, 255))
    icon.putalpha(mask)
    return icon


def write_icns(icon, output):
    with tempfile.TemporaryDirectory() as directory:
        iconset = Path(directory) / "AppIcon.iconset"
        iconset.mkdir()
        for size in ICONSET_SIZES:
            icon.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
            icon.resize((size * 2, size * 2), Image.LANCZOS).save(iconset / f"icon_{size}x{size}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(output)], check=True)


def main():
    logo = Image.open(sys.argv[1])
    resources = Path(sys.argv[2])
    app_icon = make_app_icon(logo)
    app_icon.save(resources / "AppIcon.png")
    write_icns(app_icon, resources / "AppIcon.icns")
    make_menu_bar_icon().save(resources / "MenuBarIcon.png")


if __name__ == "__main__":
    main()
