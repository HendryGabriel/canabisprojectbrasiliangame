from __future__ import annotations

import argparse
import html
import json
from collections import deque
from pathlib import Path
from typing import Iterable

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Detect visible sprites in a transparent PNG atlas.")
    parser.add_argument("image", type=Path)
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--html", type=Path, default=None)
    parser.add_argument("--data-js", type=Path, default=None)
    parser.add_argument("--alpha", type=int, default=8)
    parser.add_argument("--merge-gap", type=int, default=1)
    parser.add_argument("--min-pixels", type=int, default=3)
    return parser.parse_args()


def neighbors(x: int, y: int, width: int, height: int) -> Iterable[tuple[int, int]]:
    for ny in range(max(0, y - 1), min(height, y + 2)):
        for nx in range(max(0, x - 1), min(width, x + 2)):
            if nx == x and ny == y:
                continue
            yield nx, ny


def build_masks(image: Image.Image, alpha_threshold: int, merge_gap: int) -> tuple[list[list[bool]], list[list[bool]]]:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    original = [[alpha.getpixel((x, y)) > alpha_threshold for x in range(width)] for y in range(height)]
    if merge_gap <= 0:
        return original, original

    merged = [[False for _x in range(width)] for _y in range(height)]
    for y in range(height):
        for x in range(width):
            if not original[y][x]:
                continue
            for yy in range(max(0, y - merge_gap), min(height, y + merge_gap + 1)):
                for xx in range(max(0, x - merge_gap), min(width, x + merge_gap + 1)):
                    merged[yy][xx] = True
    return original, merged


def detect_components(original: list[list[bool]], merged: list[list[bool]], min_pixels: int) -> list[dict]:
    height = len(merged)
    width = len(merged[0]) if height > 0 else 0
    visited = [[False for _x in range(width)] for _y in range(height)]
    components: list[dict] = []

    for y in range(height):
        for x in range(width):
            if visited[y][x] or not merged[y][x]:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[y][x] = True
            merged_points: list[tuple[int, int]] = []
            while queue:
                px, py = queue.popleft()
                merged_points.append((px, py))
                for nx, ny in neighbors(px, py, width, height):
                    if visited[ny][nx] or not merged[ny][nx]:
                        continue
                    visited[ny][nx] = True
                    queue.append((nx, ny))

            original_points = [(px, py) for px, py in merged_points if original[py][px]]
            if len(original_points) < min_pixels:
                continue
            xs = [point[0] for point in original_points]
            ys = [point[1] for point in original_points]
            min_x = min(xs)
            min_y = min(ys)
            max_x = max(xs)
            max_y = max(ys)
            components.append(
                {
                    "x": min_x,
                    "y": min_y,
                    "w": max_x - min_x + 1,
                    "h": max_y - min_y + 1,
                    "visible_pixels": len(original_points),
                }
            )
    components.sort(key=lambda item: (item["y"], item["x"], item["h"], item["w"]))
    return components


def suggested_type(sprite: dict) -> str:
    width = sprite["w"]
    height = sprite["h"]
    pixels = sprite["visible_pixels"]
    coverage = pixels / max(1, width * height)
    if width >= 28 and height >= 28:
        return "tree_or_large_bush"
    if height >= 24 and width <= 24:
        return "branch_or_tall_plant"
    if width <= 10 and height <= 10:
        return "tiny_decor"
    if coverage < 0.28:
        return "thin_plant"
    if width >= 14 and height >= 10:
        return "bush_or_plant"
    return "decor"


def build_manifest(image_path: Path, image: Image.Image, components: list[dict], alpha: int, merge_gap: int) -> dict:
    sprites = []
    for index, component in enumerate(components, start=1):
        sprite = dict(component)
        sprite_id = f"vegetation_{index:03d}"
        sprite["id"] = sprite_id
        sprite["name"] = sprite_id
        sprite["region"] = [component["x"], component["y"], component["w"], component["h"]]
        sprite["suggested_type"] = suggested_type(component)
        sprite["biomes"] = []
        sprite["chance"] = 1.0
        sprite["blocks_walk"] = False
        sprite["blocks_build"] = False
        sprite["pivot"] = [component["w"] // 2, component["h"] - 1]
        sprites.append(sprite)

    return {
        "source": image_path.name,
        "image_size": list(image.size),
        "generated_by": "tools/generate_sprite_manifest.py",
        "detection": {
            "alpha_threshold": alpha,
            "merge_gap": merge_gap,
            "sprite_count": len(sprites),
        },
        "sprites": sprites,
    }


def write_html(output_path: Path, manifest: dict) -> None:
    image_name = html.escape(manifest["source"])
    atlas_width = manifest["image_size"][0]
    atlas_height = manifest["image_size"][1]
    rows = []
    cards = []
    for sprite in manifest["sprites"]:
        sprite_id = html.escape(sprite["id"])
        suggested = html.escape(sprite["suggested_type"])
        x, y, width, height = sprite["region"]
        style = (
            f"width:{width * 3}px; height:{height * 3}px; "
            f"background-position:-{x * 3}px -{y * 3}px; "
            f"background-size:{atlas_width * 3}px {atlas_height * 3}px;"
        )
        shell_style = (
            f"min-height:{max(height * 3 + 16, 88)}px;"
        )
        cards.append(
            f"""
            <article class="card">
                <div class="preview-shell" style="{shell_style}">
                    <div class="preview" style="{style}"></div>
                </div>
                <strong>{sprite_id}</strong>
                <span>{suggested}</span>
                <code>{x}, {y}, {width}, {height}</code>
            </article>
            """
        )
        rows.append(
            f"""
            <tr>
                <td>{sprite_id}</td>
                <td>{x}</td>
                <td>{y}</td>
                <td>{width}</td>
                <td>{height}</td>
                <td>{sprite["visible_pixels"]}</td>
                <td>{suggested}</td>
            </tr>
            """
        )

    body = f"""<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Vegetation Sprite Manifest</title>
    <style>
        :root {{
            color-scheme: dark;
            font-family: Inter, Segoe UI, Arial, sans-serif;
            background: #181818;
            color: #eeeeee;
        }}
        body {{
            margin: 0;
            padding: 24px;
        }}
        header {{
            display: flex;
            align-items: end;
            justify-content: space-between;
            gap: 16px;
            margin-bottom: 20px;
        }}
        h1 {{
            margin: 0 0 6px;
            font-size: 24px;
        }}
        p {{
            margin: 0;
            color: #bbbbbb;
        }}
        .atlas {{
            max-width: 100%;
            image-rendering: pixelated;
            background:
                linear-gradient(45deg, #333 25%, transparent 25%),
                linear-gradient(-45deg, #333 25%, transparent 25%),
                linear-gradient(45deg, transparent 75%, #333 75%),
                linear-gradient(-45deg, transparent 75%, #333 75%);
            background-size: 16px 16px;
            background-position: 0 0, 0 8px, 8px -8px, -8px 0;
            border: 1px solid #444;
            margin-bottom: 24px;
        }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 12px;
            margin-bottom: 28px;
        }}
        .card {{
            background: #242424;
            border: 1px solid #3a3a3a;
            border-radius: 6px;
            padding: 10px;
            min-width: 0;
        }}
        .preview-shell {{
            display: grid;
            place-items: center;
            height: 88px;
            margin-bottom: 8px;
            overflow: hidden;
            background:
                linear-gradient(45deg, #303030 25%, transparent 25%),
                linear-gradient(-45deg, #303030 25%, transparent 25%),
                linear-gradient(45deg, transparent 75%, #303030 75%),
                linear-gradient(-45deg, transparent 75%, #303030 75%);
            background-color: #222;
            background-size: 14px 14px;
            background-position: 0 0, 0 7px, 7px -7px, -7px 0;
            border-radius: 4px;
        }}
        .preview {{
            image-rendering: pixelated;
            background-image: url("{image_name}");
            background-repeat: no-repeat;
            clip-path: inset(0);
        }}
        strong, span, code {{
            display: block;
            overflow-wrap: anywhere;
        }}
        span {{
            color: #bdbdbd;
            font-size: 13px;
            margin-top: 3px;
        }}
        code {{
            color: #f2d18b;
            font-size: 12px;
            margin-top: 6px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            background: #222;
            border: 1px solid #3a3a3a;
        }}
        th, td {{
            padding: 8px 10px;
            border-bottom: 1px solid #333;
            text-align: left;
            font-size: 13px;
        }}
        th {{
            color: #ffffff;
            background: #2b2b2b;
            position: sticky;
            top: 0;
        }}
    </style>
</head>
<body>
    <header>
        <div>
            <h1>Vegetation Sprite Manifest</h1>
            <p>{manifest["detection"]["sprite_count"]} sprites detectados em {image_name}</p>
        </div>
        <p>alpha &gt; {manifest["detection"]["alpha_threshold"]}, merge gap {manifest["detection"]["merge_gap"]}</p>
    </header>
    <img class="atlas" src="{image_name}" alt="Atlas original">
    <section class="grid">
        {''.join(cards)}
    </section>
    <table>
        <thead>
            <tr>
                <th>id</th>
                <th>x</th>
                <th>y</th>
                <th>w</th>
                <th>h</th>
                <th>pixels</th>
                <th>sugestao</th>
            </tr>
        </thead>
        <tbody>
            {''.join(rows)}
        </tbody>
    </table>
</body>
</html>
"""
    output_path.write_text(body, encoding="utf-8")


def main() -> None:
    args = parse_args()
    image_path = args.image
    image = Image.open(image_path).convert("RGBA")
    original, merged = build_masks(image, args.alpha, args.merge_gap)
    components = detect_components(original, merged, args.min_pixels)
    manifest = build_manifest(image_path, image, components, args.alpha, args.merge_gap)

    json_path = args.json or image_path.with_name(f"{image_path.stem}_sprites.json")
    html_path = args.html or image_path.with_name(f"{image_path.stem}_sprites.html")
    data_js_path = args.data_js or image_path.with_name(f"{image_path.stem}_sprites_data.js")
    json_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    data_js_path.write_text(
        "window.VEGETATION_MANIFEST = "
        + json.dumps(manifest, indent=2, ensure_ascii=False)
        + ";\n",
        encoding="utf-8",
    )
    write_html(html_path, manifest)
    print(f"Generated {len(components)} sprites")
    print(json_path)
    print(data_js_path)
    print(html_path)


if __name__ == "__main__":
    main()
