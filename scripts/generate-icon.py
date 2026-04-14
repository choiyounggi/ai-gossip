#!/usr/bin/env python3
"""Generate the AI Gossip macOS AppIcon.

Produces a 1024x1024 PNG in resources/icon-1024.png. The render is pure
PIL primitive drawing — no AI model required — so the script runs on any
machine with Pillow installed.

Design goals:
  - Match the DeskRPG palette used inside the app (parchment + game-green).
  - Read as "mischievous gossiping robot": exaggerated eyes, sly raised
    brow on one side, finger-over-mouth shhh gesture, headphone-ish ears
    for "eavesdropping".
  - Lean pixelated / cartoon — fine for an icon at 128px, still cute at
    1024px. We avoid hyper-realistic rendering that PIL isn't suited for.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

# ---- Canvas --------------------------------------------------------------

W = H = 1024

# ---- Palette (matches Theme/DeskRPGTheme.swift) --------------------------

PARCHMENT      = (243, 233, 215, 255)   # #F3E9D7
PARCHMENT_DEEP = (232, 215, 183, 255)   # #E8D7B7
INK            = ( 45,  35,  24, 255)   # #2D2318
INK_SOFT       = ( 92,  68,  46, 255)   # #5C442E
ACCENT_GREEN   = ( 96, 143, 126, 255)   # #608F7E
ACCENT_WARM    = (218, 151,  84, 255)   # tan/orange accent
ROBOT_BODY     = (180, 200, 192, 255)   # sage for the robot plating
ROBOT_BODY_DK  = (138, 160, 152, 255)
TOOTH          = (255, 252, 240, 255)
CHEEK          = (224, 144, 120, 180)   # translucent pink for cheeks
SPARKLE        = (255, 237, 169, 255)

# ---- Geometry helpers ----------------------------------------------------

def rounded_rect(draw, bbox, radius, fill=None, outline=None, width=0):
    draw.rounded_rectangle(bbox, radius=radius, fill=fill, outline=outline, width=width)


def circle(draw, cx, cy, r, **kw):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), **kw)


def ellipse_bbox(cx, cy, rx, ry):
    return (cx - rx, cy - ry, cx + rx, cy + ry)


# ---- Scene ---------------------------------------------------------------

def render() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background squircle — macOS auto-masks but we pre-squircle for preview fidelity.
    bg_pad = 18
    rounded_rect(
        draw,
        (bg_pad, bg_pad, W - bg_pad, H - bg_pad),
        radius=230,
        fill=PARCHMENT,
    )

    # Subtle inner vignette — a second faint rect for warmth.
    rounded_rect(
        draw,
        (bg_pad + 40, bg_pad + 40, W - bg_pad - 40, H - bg_pad - 40),
        radius=200,
        fill=None,
        outline=PARCHMENT_DEEP,
        width=6,
    )

    # --- Antennas (gossip radar) ------------------------------------------

    # Left rod
    draw.rectangle((462, 110, 482, 240), fill=INK)
    # Right rod
    draw.rectangle((542, 110, 562, 240), fill=INK)

    # Left antenna ball (green — "recording")
    circle(draw, 472, 110, 42, fill=ACCENT_GREEN, outline=INK, width=8)
    # Right antenna ball (warm — "broadcasting")
    circle(draw, 552, 110, 42, fill=ACCENT_WARM, outline=INK, width=8)

    # --- Headphone-ish side cans (eavesdropping) --------------------------

    # Band running over the head
    draw.arc((270, 150, 750, 370), start=180, end=360, fill=INK, width=18)

    circle(draw, 240, 500, 78, fill=ACCENT_GREEN, outline=INK, width=10)
    circle(draw, 240, 500, 44, fill=PARCHMENT_DEEP, outline=INK, width=6)

    circle(draw, 784, 500, 78, fill=ACCENT_GREEN, outline=INK, width=10)
    circle(draw, 784, 500, 44, fill=PARCHMENT_DEEP, outline=INK, width=6)

    # --- Robot face (rounded rectangle body) ------------------------------

    face_box = (280, 260, 744, 800)
    # Subtle drop shadow
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (face_box[0] + 14, face_box[1] + 18, face_box[2] + 14, face_box[3] + 18),
        radius=150,
        fill=(0, 0, 0, 90),
    )
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius=16)))

    rounded_rect(draw, face_box, radius=150, fill=ROBOT_BODY, outline=INK, width=10)

    # Gentle highlight along the top inside edge of the face
    draw.arc(
        (face_box[0] + 20, face_box[1] + 20, face_box[2] - 20, face_box[1] + 180),
        start=190,
        end=350,
        fill=(255, 255, 255, 120),
        width=12,
    )

    # --- Cheeks (translucent blush) ---------------------------------------

    cheek_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cheek_layer)
    cd.ellipse(ellipse_bbox(365, 610, 48, 24), fill=CHEEK)
    cd.ellipse(ellipse_bbox(660, 610, 48, 24), fill=CHEEK)
    img.alpha_composite(cheek_layer.filter(ImageFilter.GaussianBlur(radius=4)))
    draw = ImageDraw.Draw(img)  # re-bind after composite

    # --- Eyes (big, expressive, one mid-wink) -----------------------------

    # Left eye — full round, very curious
    circle(draw, 400, 475, 92, fill="white", outline=INK, width=9)
    # Pupil
    circle(draw, 412, 488, 48, fill=INK)
    # Highlights
    circle(draw, 428, 468, 18, fill="white")
    circle(draw, 398, 502, 8, fill="white")

    # Right eye — partially narrowed (sly)
    # Bottom-half lid: we draw the eyeball then occlude top with face color.
    circle(draw, 625, 475, 92, fill="white", outline=INK, width=9)
    circle(draw, 635, 492, 48, fill=INK)
    circle(draw, 651, 472, 18, fill="white")
    # Upper eyelid — heavy line for the "one eye almost winking" look
    draw.chord(
        (533, 383, 717, 567),
        start=200,
        end=340,
        fill=ROBOT_BODY,
        outline=INK,
        width=9,
    )

    # --- Eyebrows (one flat, one raised — classic mischief) --------------

    # Left brow — level, slightly angled down toward center (innocent-ish)
    draw.polygon([(310, 360), (480, 338), (478, 378), (310, 400)], fill=INK)
    # Right brow — raised, cocked upward (skeptical/sly)
    draw.polygon([(552, 330), (722, 300), (724, 340), (556, 370)], fill=INK)

    # --- Sly grin + peeking tooth ----------------------------------------

    # Mouth outline: a lopsided arc
    draw.arc((380, 620, 640, 790), start=10, end=150, fill=INK, width=12)
    # Tongue-hint: a slight red-ish filled chord beneath the arc
    draw.chord((400, 640, 620, 770), start=20, end=140, fill=(178, 78, 70, 200))
    # Peeking tooth on one side
    draw.rectangle((500, 700, 528, 735), fill=TOOTH, outline=INK, width=3)

    # --- "Shhh" finger over the mouth -------------------------------------
    # Hand comes in from the right, blocking part of the smile with a
    # vertical finger. We draw the hand as a soft rounded pill + a finger
    # bar so it reads at 128px too.

    # Forearm (rounded rect)
    rounded_rect(
        draw,
        (640, 720, 900, 870),
        radius=72,
        fill=ROBOT_BODY_DK,
        outline=INK,
        width=9,
    )
    # Knuckle fist (circle)
    circle(draw, 660, 795, 70, fill=ROBOT_BODY_DK, outline=INK, width=9)
    # Extended index finger — pointing up over lips
    rounded_rect(
        draw,
        (605, 640, 670, 800),
        radius=32,
        fill=ROBOT_BODY_DK,
        outline=INK,
        width=9,
    )
    # Fingernail highlight
    rounded_rect(
        draw,
        (618, 652, 658, 700),
        radius=14,
        fill=(230, 240, 235, 255),
    )

    # --- Sparkle decorations (little gossip bubbles) ---------------------

    def sparkle(cx, cy, s):
        draw.polygon(
            [
                (cx, cy - s),
                (cx + s * 0.3, cy - s * 0.3),
                (cx + s, cy),
                (cx + s * 0.3, cy + s * 0.3),
                (cx, cy + s),
                (cx - s * 0.3, cy + s * 0.3),
                (cx - s, cy),
                (cx - s * 0.3, cy - s * 0.3),
            ],
            fill=SPARKLE,
            outline=INK,
            width=4,
        )

    sparkle(170, 300, 28)
    sparkle(870, 280, 22)
    sparkle(130, 720, 20)
    sparkle(910, 760, 26)

    # --- Little "gossip cloud" whisper icon near the finger --------------

    # Triangle tail
    draw.polygon(
        [(720, 610), (770, 580), (750, 640)],
        fill=(255, 255, 255, 230),
        outline=INK,
        width=5,
    )
    rounded_rect(draw, (720, 540, 920, 620), radius=36, fill=(255, 255, 255, 230), outline=INK, width=6)
    # Three dots to suggest "..."
    for i, x in enumerate([760, 820, 880]):
        circle(draw, x, 580, 10, fill=INK)

    return img


def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "resources"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "icon-1024.png"

    img = render()
    img.save(out_path, format="PNG")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
