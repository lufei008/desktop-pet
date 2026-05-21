from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


CELL_W = 192
CELL_H = 208
COLUMNS = 8
BASE_ROWS = 9

ANIMATIONS = {
    "idle": {"row": 0, "frames": 6, "interval": 180},
    "running-right": {"row": 1, "frames": 8, "interval": 110},
    "running-left": {"row": 2, "frames": 8, "interval": 110},
    "waving": {"row": 3, "frames": 4, "interval": 150},
    "jumping": {"row": 4, "frames": 5, "interval": 135},
    "failed": {"row": 5, "frames": 8, "interval": 170},
    "waiting": {"row": 6, "frames": 6, "interval": 180},
    "running": {"row": 7, "frames": 6, "interval": 145},
    "review": {"row": 8, "frames": 6, "interval": 170},
    "feeding": {"row": 9, "frames": 6, "interval": 145, "source": "waving"},
    "cleaning": {"row": 10, "frames": 6, "interval": 150, "source": "review"},
    "bathing": {"row": 11, "frames": 6, "interval": 145, "source": "jumping"},
    "playing": {"row": 12, "frames": 6, "interval": 125, "source": "jumping"},
    "resting": {"row": 13, "frames": 6, "interval": 210, "source": "idle"},
    "hungry": {"row": 14, "frames": 6, "interval": 180, "source": "waiting"},
    "dirty": {"row": 15, "frames": 6, "interval": 180, "source": "failed"},
    "tired": {"row": 16, "frames": 6, "interval": 200, "source": "failed"},
    "lonely": {"row": 17, "frames": 6, "interval": 185, "source": "failed"},
}


SOURCE_ROWS = {
    name: data["row"]
    for name, data in ANIMATIONS.items()
    if data["row"] < BASE_ROWS
}
SOURCE_FRAMES = {
    name: data["frames"]
    for name, data in ANIMATIONS.items()
    if data["row"] < BASE_ROWS
}


def draw_bowl(draw: ImageDraw.ImageDraw, frame: int, empty: bool = False) -> None:
    x0, y0, x1, y1 = 63, 166, 130, 190
    draw.ellipse((x0, y0, x1, y1), fill=(245, 245, 248, 255), outline=(58, 62, 70, 255), width=3)
    draw.rectangle((x0 + 3, y0 + 8, x1 - 3, y1 - 5), fill=(82, 130, 186, 255))
    draw.arc((x0, y0, x1, y1), 0, 180, fill=(58, 62, 70, 255), width=3)
    if not empty:
        bob = int(math.sin(frame / 6 * math.tau) * 3)
        for i, color in enumerate(((211, 128, 68, 255), (232, 175, 78, 255), (127, 176, 99, 255))):
            cx = 79 + i * 15
            draw.ellipse((cx, 156 + bob - i, cx + 10, 166 + bob - i), fill=color, outline=(66, 47, 35, 255), width=1)


def draw_broom(draw: ImageDraw.ImageDraw, frame: int) -> None:
    sway = int(math.sin(frame / 6 * math.tau) * 5)
    draw.line((128 + sway, 111, 79 + sway, 176), fill=(127, 82, 45, 255), width=5)
    draw.polygon(
        ((69 + sway, 173), (98 + sway, 158), (113 + sway, 183), (82 + sway, 193)),
        fill=(231, 184, 93, 255),
        outline=(66, 51, 35, 255),
    )
    for offset in (0, 7, 14, 21):
        draw.line((78 + sway + offset, 171, 84 + sway + offset, 190), fill=(121, 90, 49, 255), width=1)


def draw_bubbles(draw: ImageDraw.ImageDraw, frame: int) -> None:
    phase = frame / 6 * math.tau
    bubbles = [(56, 87, 13), (137, 91, 10), (72, 132, 11), (124, 137, 14), (96, 68, 9), (109, 155, 8)]
    for idx, (x, y, r) in enumerate(bubbles):
        rr = r + int(math.sin(phase + idx) * 2)
        draw.ellipse((x - rr, y - rr, x + rr, y + rr), fill=(235, 251, 255, 205), outline=(102, 176, 208, 230), width=2)


def draw_ball(draw: ImageDraw.ImageDraw, frame: int) -> None:
    t = frame / 5
    x = int(43 + t * 91)
    y = int(172 - abs(math.sin(t * math.pi)) * 26)
    draw.ellipse((x, y, x + 24, y + 24), fill=(230, 84, 83, 255), outline=(58, 50, 48, 255), width=3)
    draw.arc((x + 3, y + 3, x + 21, y + 21), 105, 285, fill=(255, 234, 132, 255), width=3)


def draw_pillow_underlay(draw: ImageDraw.ImageDraw, frame: int) -> None:
    shift = int(math.sin(frame / 6 * math.tau) * 2)
    draw.rounded_rectangle((42, 150 + shift, 151, 188 + shift), radius=18, fill=(159, 194, 220, 210), outline=(67, 95, 128, 230), width=3)
    draw.arc((51, 156 + shift, 87, 183 + shift), 190, 340, fill=(221, 240, 250, 210), width=2)


def draw_dirty_smudges(draw: ImageDraw.ImageDraw, frame: int) -> None:
    alpha = 135 + int(math.sin(frame / 6 * math.tau) * 18)
    for box in ((56, 86, 78, 100), (118, 111, 143, 127), (74, 143, 100, 159)):
        draw.ellipse(box, fill=(83, 80, 75, alpha))
    draw.arc((52, 125, 83, 149), 210, 330, fill=(91, 88, 82, alpha), width=4)


def draw_tired_marks(draw: ImageDraw.ImageDraw, frame: int) -> None:
    droop = int(math.sin(frame / 6 * math.tau) * 2)
    draw.line((68, 86 + droop, 87, 90 + droop), fill=(54, 54, 58, 220), width=4)
    draw.line((106, 90 + droop, 126, 86 + droop), fill=(54, 54, 58, 220), width=4)
    draw.arc((76, 116, 116, 143), 15, 165, fill=(55, 50, 50, 210), width=3)


def draw_tear(draw: ImageDraw.ImageDraw, frame: int) -> None:
    bob = int(math.sin(frame / 6 * math.tau) * 2)
    points = [(123, 101 + bob), (114, 119 + bob), (132, 119 + bob)]
    draw.polygon(points, fill=(93, 178, 224, 230), outline=(50, 112, 160, 240))
    draw.ellipse((114, 110 + bob, 132, 127 + bob), fill=(93, 178, 224, 230), outline=(50, 112, 160, 240), width=2)


def render_extra_cell(source: Image.Image, state_name: str, frame: int) -> Image.Image:
    data = ANIMATIONS[state_name]
    source_name = data["source"]
    source_row = SOURCE_ROWS[source_name]
    source_frames = SOURCE_FRAMES[source_name]
    source_frame = frame % source_frames
    crop = source.crop(
        (
            source_frame * CELL_W,
            source_row * CELL_H,
            (source_frame + 1) * CELL_W,
            (source_row + 1) * CELL_H,
        )
    ).convert("RGBA")

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(cell, "RGBA")
    if state_name in {"resting", "tired"}:
        draw_pillow_underlay(draw, frame)
    cell.alpha_composite(crop)
    draw = ImageDraw.Draw(cell, "RGBA")

    if state_name == "feeding":
        draw_bowl(draw, frame, empty=False)
    elif state_name == "cleaning":
        draw_broom(draw, frame)
    elif state_name == "bathing":
        draw_bubbles(draw, frame)
    elif state_name == "playing":
        draw_ball(draw, frame)
    elif state_name == "hungry":
        draw_bowl(draw, frame, empty=True)
    elif state_name == "dirty":
        draw_dirty_smudges(draw, frame)
    elif state_name == "tired":
        draw_tired_marks(draw, frame)
    elif state_name == "lonely":
        draw_tear(draw, frame)

    return cell


def update_pet_json(pet_json_path: Path, total_rows: int) -> None:
    meta = json.loads(pet_json_path.read_text(encoding="utf-8"))
    meta["spritesheetPath"] = "spritesheet.webp"
    meta["spriteSheet"] = {
        "width": CELL_W * COLUMNS,
        "height": CELL_H * total_rows,
        "columns": COLUMNS,
        "rows": total_rows,
        "cellWidth": CELL_W,
        "cellHeight": CELL_H,
    }
    meta["animations"] = {
        name: {
            "row": data["row"],
            "frames": data["frames"],
            "interval": data["interval"],
        }
        for name, data in ANIMATIONS.items()
    }
    pet_json_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def extend_pet(pet_dir: Path) -> None:
    png_path = pet_dir / "spritesheet.png"
    webp_path = pet_dir / "spritesheet.webp"
    pet_json_path = pet_dir / "pet.json"
    if not png_path.exists() or not pet_json_path.exists():
        raise FileNotFoundError(f"Missing pet files under {pet_dir}")

    source = Image.open(png_path).convert("RGBA")
    if source.width != CELL_W * COLUMNS or source.height < CELL_H * BASE_ROWS:
        raise ValueError(f"Unexpected spritesheet size for {png_path}: {source.size}")

    total_rows = max(data["row"] for data in ANIMATIONS.values()) + 1
    output = Image.new("RGBA", (CELL_W * COLUMNS, CELL_H * total_rows), (0, 0, 0, 0))
    output.alpha_composite(source.crop((0, 0, CELL_W * COLUMNS, CELL_H * BASE_ROWS)), (0, 0))

    for name, data in ANIMATIONS.items():
        if data["row"] < BASE_ROWS:
            continue
        for frame in range(data["frames"]):
            cell = render_extra_cell(source, name, frame)
            output.alpha_composite(cell, (frame * CELL_W, data["row"] * CELL_H))

    output.save(png_path)
    output.save(webp_path, "WEBP", lossless=True, quality=95, method=6)
    update_pet_json(pet_json_path, total_rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pet-root", default=str(Path(__file__).resolve().parents[1] / "assets"))
    parser.add_argument("--pets", nargs="*", default=["bully", "kai"])
    args = parser.parse_args()

    pet_root = Path(args.pet_root)
    for pet in args.pets:
        extend_pet(pet_root / pet)
        print(f"extended {pet}")


if __name__ == "__main__":
    main()
