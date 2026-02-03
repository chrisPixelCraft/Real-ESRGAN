# Real-ESRGAN PDF Inference Flow (Run From `/root/Real-ESRGAN`)

This guide records the full workflow we used, from setup/download to final PDF export, with commands and why each command is needed.

## 1) Processing Logic (ASCII Diagram)

```text
Start
  |
  v
[Activate conda env: side_proj_3_9]
  |
  v
[Install/verify Python deps + model weights]
  |
  v
[Input PDF: golden_stone_all.pdf]
  |
  v
[Split PDF -> PNG pages at 300 DPI]
  |
  v
[Rename pages to P1.png ... P66.png (numeric order key)]
  |
  v
[Batch super-resolution]
  |- Model: RealESRGAN_x4plus
  |- Face enhancement: GFPGAN
  |- Progress bar: tqdm
  |- Resume supported
  |
  v
[Upscaled PNGs output]
  |
  v
[Convert pages -> per-page PDF (300 DPI) -> merge by numeric P-order]
  |
  v
[Final PDF: golden_stone_all_x4plus_300dpi.pdf]
```

## 2) Commands From Start To End (with meaning)

All commands below are executed in:

```bash
cd /root/Real-ESRGAN
```

### Step A. Activate environment

```bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate side_proj_3_9
```

- Meaning: load conda and switch to the inference environment.

### Step B. Install required packages (one-time)

```bash
pip install Cython
pip install -r requirements.txt
pip install basicsr facexlib gfpgan
python setup.py develop
```

- Meaning: install Real-ESRGAN runtime dependencies and editable package setup.

### Step C. Compatibility patch (only if you hit `functional_tensor` import error)

```bash
/root/miniconda3/envs/side_proj_3_9/bin/python - <<'PY'
from pathlib import Path
path = Path('/root/miniconda3/envs/side_proj_3_9/lib/python3.9/site-packages/basicsr/data/degradations.py')
text = path.read_text()
old = 'from torchvision.transforms.functional_tensor import rgb_to_grayscale\n'
new = 'try:\n    from torchvision.transforms.functional_tensor import rgb_to_grayscale\nexcept ImportError:\n    from torchvision.transforms.functional import rgb_to_grayscale\n'
if old in text:
    path.write_text(text.replace(old, new, 1))
    print('patched')
else:
    print('already patched / not needed')
PY
```

- Meaning: avoid version mismatch between `basicsr` and newer `torchvision`.

### Step D. Download model weights (one-time)

```bash
wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P weights
```

- Meaning: download the strongest requested model checkpoint into `weights/`.

### Step E. (Optional manual prep) Split PDF to PNG at 300 DPI

```bash
mkdir -p /root/Real-ESRGAN/golden_tmp
pdftoppm -png -r 300 /root/Real-ESRGAN/golden_stone_all.pdf /root/Real-ESRGAN/golden_tmp/page
python3 - <<'PY'
from pathlib import Path
import re
p = Path('/root/Real-ESRGAN/golden_tmp')
for f in sorted(p.glob('page-*.png')):
    m = re.search(r'page-(\d+)\.png$', f.name)
    if m:
        f.rename(p / f'P{int(m.group(1))}.png')
print('done')
PY
```

- Meaning: create page images and rename for stable numeric ordering (`P1`, `P2`, ..., `P66`).

### Step F. Main batch inference + rebuild PDF (recommended)

```bash
CUDA_VISIBLE_DEVICES=0,1 FP32=0 TILE=1024 FACE_ENHANCE=1 RESUME=1 /root/Real-ESRGAN/run_upscale_pdf.sh
```

- Meaning:
  - `CUDA_VISIBLE_DEVICES=0,1`: expose GPU 0/1.
  - `FP32=0`: use FP16 for speed and lower VRAM.
  - `TILE=1024`: process by 1024 tiles to fit memory.
  - `FACE_ENHANCE=1`: enable GFPGAN face enhancement.
  - `RESUME=1`: skip finished output pages if rerun.
  - Script does:
    1) reuse or create `golden_tmp`
    2) upscale all `P*.png` into `golden_tmp_upscaled`
    3) convert to 300 DPI PDF and merge as `golden_stone_all_x4plus_300dpi.pdf`

### Step G. Optional GPU monitor while running

```bash
watch -n 1 nvidia-smi
```

- Meaning: verify active `python` process, VRAM usage, and GPU utilization.

## 3) Output Paths

- Input PDF: `/root/Real-ESRGAN/golden_stone_all.pdf`
- Split pages: `/root/Real-ESRGAN/golden_tmp/P*.png`
- Upscaled pages: `/root/Real-ESRGAN/golden_tmp_upscaled/P*.png`
- Final PDF: `/root/Real-ESRGAN/golden_stone_all_x4plus_300dpi.pdf`

## 4) Files Added / Moved

- Added: `/root/Real-ESRGAN/Inference.md`
- Moved: `/root/Real-ESRGAN/golden_stone/run_upscale_pdf.sh` -> `/root/Real-ESRGAN/run_upscale_pdf.sh`
- Updated: `/root/Real-ESRGAN/run_upscale_pdf.sh` to run directly from repo root paths.

## 5) Final Command To Remember

```bash
cd /root/Real-ESRGAN
source /root/miniconda3/etc/profile.d/conda.sh
conda activate side_proj_3_9
CUDA_VISIBLE_DEVICES=0,1 FP32=0 TILE=1024 FACE_ENHANCE=1 RESUME=1 ./run_upscale_pdf.sh
```
