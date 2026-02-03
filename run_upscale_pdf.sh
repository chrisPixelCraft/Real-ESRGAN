#!/usr/bin/env bash
set -euo pipefail

# Batch workflow for:
# 1) (optional) split PDF -> PNGs in golden_tmp
# 2) upscale PNGs with RealESRGAN_x4plus + GFPGAN face enhance (with progress bar)
# 3) rebuild PDF at 300 DPI in numeric P-order

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

CONDA_SH="${CONDA_SH:-/root/miniconda3/etc/profile.d/conda.sh}"
CONDA_ENV="${CONDA_ENV:-side_proj_3_9}"

PDF_IN="${PDF_IN:-golden_stone_all.pdf}"
INPUT_DIR="${INPUT_DIR:-golden_tmp}"
OUTPUT_DIR="${OUTPUT_DIR:-golden_tmp_upscaled}"
FINAL_PDF="${FINAL_PDF:-golden_stone_all_x4plus_300dpi.pdf}"
MODEL_PATH="${MODEL_PATH:-weights/RealESRGAN_x4plus.pth}"

# Extra tags for stability on CPU-only environments.
TILE="${TILE:-512}"
OUTSCALE="${OUTSCALE:-4}"
FP32="${FP32:-1}"
FACE_ENHANCE="${FACE_ENHANCE:-1}"
RESUME="${RESUME:-1}"

echo "[0/3] Preparing environment..."
if [[ ! -f "$CONDA_SH" ]]; then
  echo "Conda init script not found: $CONDA_SH" >&2
  exit 1
fi
source "$CONDA_SH"
conda activate "$CONDA_ENV"

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model missing, downloading: $MODEL_PATH"
  wget "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" -P weights
fi

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

png_count="$(find "$INPUT_DIR" -maxdepth 1 -type f -name 'P*.png' | wc -l | tr -d ' ')"
if [[ "$png_count" == "0" ]]; then
  echo "[1/3] Splitting PDF into PNG pages -> $INPUT_DIR"
  pdftoppm -png -r 300 "$PDF_IN" "$INPUT_DIR/page"
  INPUT_DIR="$INPUT_DIR" python3 - <<'PY'
from pathlib import Path
import re

input_dir = Path(__import__("os").environ["INPUT_DIR"])
count = 0
for f in sorted(input_dir.glob("page-*.png")):
    m = re.search(r"page-(\d+)\.png$", f.name)
    if not m:
        continue
    n = int(m.group(1))
    f.rename(input_dir / f"P{n}.png")
    count += 1
print(f"Renamed {count} pages to P*.png")
PY
else
  echo "[1/3] Reusing existing PNG pages in $INPUT_DIR ($png_count files)"
fi

echo "[2/3] Upscaling pages with RealESRGAN_x4plus + face_enhance..."
INPUT_DIR="$INPUT_DIR" \
OUTPUT_DIR="$OUTPUT_DIR" \
MODEL_PATH="$MODEL_PATH" \
TILE="$TILE" \
OUTSCALE="$OUTSCALE" \
FP32="$FP32" \
FACE_ENHANCE="$FACE_ENHANCE" \
RESUME="$RESUME" \
python - <<'PY'
import contextlib
import io
import os
import re
from pathlib import Path

import cv2
from basicsr.archs.rrdbnet_arch import RRDBNet
from tqdm import tqdm

from realesrgan import RealESRGANer


def page_key(p: Path) -> int:
    m = re.fullmatch(r"P(\d+)\.png", p.name)
    return int(m.group(1)) if m else 10**9


input_dir = Path(os.environ["INPUT_DIR"])
output_dir = Path(os.environ["OUTPUT_DIR"])
model_path = os.environ["MODEL_PATH"]
tile = int(os.environ.get("TILE", "512"))
outscale = float(os.environ.get("OUTSCALE", "4"))
fp32 = os.environ.get("FP32", "1") == "1"
face_enhance = os.environ.get("FACE_ENHANCE", "1") == "1"
resume = os.environ.get("RESUME", "1") == "1"

files = sorted(
    [p for p in input_dir.iterdir() if p.is_file() and re.fullmatch(r"P\d+\.png", p.name)],
    key=page_key,
)
if not files:
    raise SystemExit(f"No input pages found in {input_dir}")

to_process = []
skipped = 0
for src in files:
    dst = output_dir / src.name
    # If resuming, keep existing non-empty outputs and only process missing pages.
    if resume and dst.exists() and dst.stat().st_size > 0:
        skipped += 1
        continue
    to_process.append(src)

if not to_process:
    print(f"All pages already upscaled. skipped={skipped}, total={len(files)}")
else:
    model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=4)
    upsampler = RealESRGANer(
        scale=4,
        model_path=model_path,
        dni_weight=None,
        model=model,
        tile=tile,
        tile_pad=10,
        pre_pad=0,
        half=not fp32,
        gpu_id=None,
    )

    face_enhancer = None
    if face_enhance:
        from gfpgan import GFPGANer

        face_enhancer = GFPGANer(
            model_path="https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.3.pth",
            upscale=outscale,
            arch="clean",
            channel_multiplier=2,
            bg_upsampler=upsampler,
        )

    processed = 0
    with tqdm(total=len(to_process), desc="Upscale", unit="page") as pbar:
        for src in to_process:
            dst = output_dir / src.name
            img = cv2.imread(str(src), cv2.IMREAD_UNCHANGED)
            if img is None:
                raise RuntimeError(f"Cannot read image: {src}")

            # RealESRGAN prints per-tile logs; silence them to keep tqdm clean.
            with contextlib.redirect_stdout(io.StringIO()):
                if face_enhancer is not None:
                    _, _, output = face_enhancer.enhance(
                        img, has_aligned=False, only_center_face=False, paste_back=True
                    )
                else:
                    output, _ = upsampler.enhance(img, outscale=outscale)

            ok = cv2.imwrite(str(dst), output)
            if not ok:
                raise RuntimeError(f"Failed to save image: {dst}")

            processed += 1
            pbar.update(1)

    print(
        f"Upscale complete: processed={processed}, skipped={skipped}, "
        f"remaining_after_run={len(files) - processed - skipped}, total={len(files)}"
    )
PY

echo "[3/3] Building final 300 DPI PDF in numeric P order -> $FINAL_PDF"
OUTPUT_DIR="$OUTPUT_DIR" FINAL_PDF="$FINAL_PDF" python - <<'PY'
import os
import re
import shutil
import subprocess
from pathlib import Path

from PIL import Image
from tqdm import tqdm


def page_key(p: Path) -> int:
    m = re.fullmatch(r"P(\d+)\.png", p.name)
    return int(m.group(1)) if m else 10**9


output_dir = Path(os.environ["OUTPUT_DIR"])
final_pdf = Path(os.environ["FINAL_PDF"])
tmp_pages = Path(".tmp_pdf_pages")

files = sorted(
    [p for p in output_dir.iterdir() if p.is_file() and re.fullmatch(r"P\d+\.png", p.name)],
    key=page_key,
)
if not files:
    raise SystemExit(f"No upscaled pages found in {output_dir}")

if tmp_pages.exists():
    shutil.rmtree(tmp_pages)
tmp_pages.mkdir(parents=True, exist_ok=True)

page_pdfs = []
for idx, img_path in enumerate(tqdm(files, desc="PDF pages", unit="page"), start=1):
    one_page_pdf = tmp_pages / f"page_{idx:04d}.pdf"
    with Image.open(img_path) as img:
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        img.save(one_page_pdf, "PDF", resolution=300.0)
    page_pdfs.append(str(one_page_pdf))

subprocess.run(["pdfunite", *page_pdfs, str(final_pdf)], check=True)
shutil.rmtree(tmp_pages)
print(f"Saved: {final_pdf}")
PY

echo "Done."
