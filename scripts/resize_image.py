#!/usr/bin/env python3
"""iPhone 写真などを記事用 JPEG に落とす。位置情報は捨てる。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MAX_EDGE = 1600
TARGET_MAX_BYTES = 380_000
QUALITY_START = 84
QUALITY_MIN = 68


def _pil():
    try:
        from PIL import Image, ImageOps
    except ImportError as exc:
        raise SystemExit(
            "Pillow が必要です。python3 -m pip install --user Pillow"
        ) from exc
    return Image, ImageOps


def load_image(path: Path):
    Image, ImageOps = _pil()

    try:
        from pillow_heif import register_heif_opener

        register_heif_opener()
    except ImportError:
        pass

    image = Image.open(path)
    image = ImageOps.exif_transpose(image)
    if image.mode in ("RGBA", "LA", "P"):
        rgba = image.convert("RGBA")
        background = Image.new("RGB", rgba.size, (250, 250, 250))
        background.paste(rgba, mask=rgba.split()[-1])
        return background
    return image.convert("RGB")


def fit(image, max_edge: int = MAX_EDGE):
    w, h = image.size
    longest = max(w, h)
    if longest <= max_edge:
        return image
    scale = max_edge / longest
    new_size = (max(1, round(w * scale)), max(1, round(h * scale)))
    Image, _ = _pil()
    return image.resize(new_size, Image.Resampling.LANCZOS)


def save_jpeg(image, dest: Path) -> int:
    dest.parent.mkdir(parents=True, exist_ok=True)
    quality = QUALITY_START
    last_size = 0
    while quality >= QUALITY_MIN:
        image.save(
            dest,
            format="JPEG",
            quality=quality,
            optimize=True,
            progressive=True,
            exif=b"",
        )
        last_size = dest.stat().st_size
        if last_size <= TARGET_MAX_BYTES:
            return last_size
        quality -= 4
    return last_size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    src = Path(args.file)
    dest = Path(args.out)
    if not src.is_file():
        print(f"missing file: {src}", file=sys.stderr)
        return 1

    image = load_image(src)
    image = fit(image)
    size = save_jpeg(image, dest)
    print(f"{dest}\t{image.size[0]}x{image.size[1]}\t{size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
