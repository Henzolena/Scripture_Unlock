#!/bin/bash
#
# Regenerates Scripture_Unlock/Resources/Secrets.xcconfig from Bitwarden.
#
# The point is that the file no longer needs to be kept anywhere: it is derived
# on demand, so a lost or wiped machine needs only a Bitwarden login rather than a
# copy of the plaintext keys.
#
# Usage:
#   export BW_SESSION=$(bw unlock --raw)
#   ./scripts/gen-secrets.sh
#
set -euo pipefail

ITEM_NAME="Scripture Unlock — build secrets"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCCONFIG="$ROOT/Scripture_Unlock/Resources/Secrets.xcconfig"

if [[ -z "${BW_SESSION:-}" ]]; then
  echo "error: BW_SESSION is not set. Run: export BW_SESSION=\$(bw unlock --raw)" >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Fetching \"$ITEM_NAME\" from Bitwarden…"
bw get item "$ITEM_NAME" --session "$BW_SESSION" > "$WORK/item.json"

# The JSON is passed as a file path, not on stdin: a heredoc already owns stdin
# here, so reading sys.stdin would read this script's own source text.
python3 "$ROOT/scripts/render_xcconfig.py" "$WORK/item.json" "$WORK/out.xcconfig"

# Move into place only after a successful render, so a failure never leaves a
# half-written config that would build into a broken app.
mkdir -p "$(dirname "$XCCONFIG")"
mv "$WORK/out.xcconfig" "$XCCONFIG"
chmod 600 "$XCCONFIG"
echo "Regenerated $XCCONFIG (mode 600)"
