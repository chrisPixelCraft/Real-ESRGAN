#!/usr/bin/env bash
set -euo pipefail

out_file="golden_stone_all.pdf"

files=()
while IFS= read -r -d '' line; do
  files+=("${line#*$'\t'}")
done < <(
  while IFS= read -r -d '' file_path; do
    file_name="$(basename -- "$file_path")"
    # Avoid reading the previous merged output as an input.
    [[ "$file_name" == "$out_file" ]] && continue

    if [[ "$file_name" =~ ^P([0-9]+) ]]; then
      page_no="${BASH_REMATCH[1]}"
    else
      # Put files without a P<number> prefix at the end.
      page_no="999999"
    fi

    printf '%09d\t%s\0' "$page_no" "$file_path"
  done < <(find . -maxdepth 1 -type f -name '*.pdf' -print0) \
    | sort -z -t $'\t' -k1,1n -k2,2
)

if (( ${#files[@]} == 0 )); then
  echo "No PDF files found to merge."
  exit 1
fi

tmp_file="$(mktemp --tmpdir=. .golden_stone_all.XXXXXX.tmp)"
trap 'rm -f -- "$tmp_file"' EXIT

pdfunite "${files[@]}" "$tmp_file"
mv -f -- "$tmp_file" "$out_file"
echo "Merged ${#files[@]} PDFs -> $out_file"
