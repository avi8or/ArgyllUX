#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-HEAD}"
missing_files=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue

  if grep -Eiq "(workflow|bridge|command|persistence|export|failure|public path|diagnostics|privacy|observability)" "$file"; then
    if ! grep -q "^## Diagnostics, Privacy, And Observability$" "$file"; then
      missing_files+=("$file")
    fi
  fi
done < <(git diff --name-only --diff-filter=ACMRT "$base_ref" -- \
  docs/superpowers/specs \
  docs/superpowers/plans \
  docs/plans)

if (( ${#missing_files[@]} > 0 )); then
  printf 'Missing "Diagnostics, Privacy, And Observability" section in relevant docs:\n' >&2
  printf ' - %s\n' "${missing_files[@]}" >&2
  exit 1
fi

printf 'Diagnostics section check passed.\n'
