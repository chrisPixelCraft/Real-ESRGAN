#!/usr/bin/env bash
set -euo pipefail

FOLDER_URL="https://drive.google.com/drive/u/0/folders/1mUfF6InjLJvKNkG4OO8JPmMNkfT0jlRd"
OUT_DIR="${1:-./gdrive_folder}"

python3 -m pip install --user -U gdown >/dev/null
PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
export PATH="$HOME/.local/bin:$HOME/Library/Python/$PY_VER/bin:$PATH"

mkdir -p "$OUT_DIR"
gdown --folder "$FOLDER_URL" -O "$OUT_DIR" --remaining-ok --continue

# gdown 1G9KA81LChF3RJQicdGE0mN93yU8yRQX_ -O bookmarks_v2.zip
# unzip bookmarks_v2.zip
gdown 1Cqn3uu3oFB8vlOcsTI1uNLUoxtSyZ6In -O bookmark_extra.zip
unzip bookmark_extra.zip