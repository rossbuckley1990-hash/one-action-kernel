#!/usr/bin/env bash
# ============================================================================
#  setup.sh — wire the dependencies the one-action kernel composes.
#  Idempotent: safe to re-run. Expects this checkout to live inside an agent-lab/
#  directory; sibling tool repos are cloned next to it and venvs built under .venvs/.
#
#  Nothing here needs cloud credentials. Actenon packages install from PyPI/git.
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${LAB:-$(cd "$HERE/.." && pwd)}"
VENV="$LAB/.venvs"
ACCOUNT="rossbuckley1990-hash"
PY="${PYTHON:-python3}"

say() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

say "LAB root: $LAB"
mkdir -p "$VENV"

# ── sibling tool repos (your own work, composed by the kernel) ───────────────
for repo in blastradius sentinel-verified Howdex apprentice workproof; do
  if [ -d "$LAB/$repo/.git" ]; then
    echo "  have  $repo"
  else
    echo "  clone $repo"
    git clone --depth 1 "https://github.com/$ACCOUNT/$repo.git" "$LAB/$repo"
  fi
done

# ── Node deps for Sentinel + property-verify (tsx, vitest) ───────────────────
if [ -d "$LAB/sentinel-verified" ] && [ ! -d "$LAB/sentinel-verified/node_modules" ]; then
  say "npm install (sentinel-verified: tsx, vitest)"
  ( cd "$LAB/sentinel-verified" && npm install )
fi
# Sentinel CLI build (dist/cli.js) if missing
if [ -d "$LAB/sentinel-verified" ] && [ ! -f "$LAB/sentinel-verified/dist/cli.js" ]; then
  say "build sentinel-verified"
  ( cd "$LAB/sentinel-verified" && npm run build 2>/dev/null || npx tsc 2>/dev/null || true )
fi

# ── Python venvs ─────────────────────────────────────────────────────────────
mkvenv() {  # mkvenv <name>
  if [ ! -x "$VENV/$1/bin/python" ]; then
    echo "  venv  $1"; "$PY" -m venv "$VENV/$1"; "$VENV/$1/bin/pip" -q install --upgrade pip
  fi
}

say "Python venvs + installs"
mkvenv blastradius
( cd "$LAB/blastradius" && "$VENV/blastradius/bin/pip" -q install -e . 2>/dev/null || "$VENV/blastradius/bin/pip" -q install -e "$LAB/blastradius" )

mkvenv apprentice
"$VENV/apprentice/bin/pip" -q install -e "$LAB/apprentice" 2>/dev/null || "$VENV/apprentice/bin/pip" -q install apprentice 2>/dev/null || true

mkvenv howdex
"$VENV/howdex/bin/pip" -q install -e "$LAB/Howdex" 2>/dev/null || true

mkvenv workproof
"$VENV/workproof/bin/pip" -q install -e "$LAB/workproof" 2>/dev/null || true

# Actenon ecosystem: scan (discovery) + the kernel/permit/protocol/airlock stack (fusion)
mkvenv actenon
"$VENV/actenon/bin/pip" -q install "actenon-scan[typescript]" 2>/dev/null || "$VENV/actenon/bin/pip" -q install actenon-scan

mkvenv airlock
# airlock git-installs the candidate kernel/permit/protocol/scan stack + cryptography/fastapi
"$VENV/airlock/bin/pip" -q install "git+https://github.com/Actenon/actenon-airlock.git@main"

say "Done. Run the product with:  ./run.sh"
echo "  (LAB=$LAB)"
