#!/bin/bash
#
# One-time migration: push the values currently in Secrets.xcconfig into Bitwarden.
#
# Run this once, after `bw login`, to populate the vault from what is already on
# disk. After that, Secrets.xcconfig can be deleted and regenerated on demand with
# scripts/gen-secrets.sh — so plaintext keys stop living in the working tree.
#
# Usage:
#   export BW_SESSION=$(bw unlock --raw)
#   ./scripts/bw-seed-secrets.sh
#
set -euo pipefail

ITEM_NAME="Scripture Unlock — build secrets"
XCCONFIG="$(cd "$(dirname "$0")/.." && pwd)/Scripture_Unlock/Resources/Secrets.xcconfig"

if [[ -z "${BW_SESSION:-}" ]]; then
  echo "error: BW_SESSION is not set. Run: export BW_SESSION=\$(bw unlock --raw)" >&2
  exit 1
fi
if [[ ! -f "$XCCONFIG" ]]; then
  echo "error: $XCCONFIG not found — nothing to seed from." >&2
  exit 1
fi

if bw get item "$ITEM_NAME" --session "$BW_SESSION" >/dev/null 2>&1; then
  echo "\"$ITEM_NAME\" already exists in the vault. Refusing to overwrite."
  echo "Delete it in Bitwarden first if you really want to re-seed."
  exit 1
fi

# Only these reach the app — Scripture-Unlock-Info.plist maps exactly these
# into the bundle. Anything else in the xcconfig is inert at runtime.
KEYS=(SUPABASE_HOST SUPABASE_ANON_KEY)

echo "Reading values from $XCCONFIG"
PAYLOAD=$(python3 - "$XCCONFIG" "$ITEM_NAME" "${KEYS[@]}" <<'PY'
import json, re, sys

path, item_name, *keys = sys.argv[1:]
values = {}
for line in open(path):
    line = line.strip()
    if not line or line.startswith("//"):
        continue
    m = re.match(r'^([A-Z_]+)\s*=\s*(.*)$', line)
    if m and m.group(1) in keys:
        # xcconfig treats // as a comment; strip any trailing one.
        values[m.group(1)] = m.group(2).split("//")[0].strip()

missing = [k for k in keys if not values.get(k)]
if missing:
    sys.exit(f"error: missing or empty in xcconfig: {', '.join(missing)}")

print(json.dumps({
    "type": 2,                     # 2 = secure note
    "name": item_name,
    "notes": "Generated from Secrets.xcconfig. Regenerate the file with scripts/gen-secrets.sh.",
    "secureNote": {"type": 0},
    "fields": [
        {"name": k, "value": values[k], "type": 1}   # type 1 = hidden
        for k in keys
    ],
}))
PY
)

echo "Creating vault item: $ITEM_NAME"
printf '%s' "$PAYLOAD" | bw encode | bw create item --session "$BW_SESSION" >/dev/null
echo "Done. ${#KEYS[@]} fields stored."
echo
echo "Next: prove the round-trip before treating the local file as disposable —"
echo "  cp \"$XCCONFIG\" /tmp/xcconfig.before"
echo "  ./scripts/gen-secrets.sh"
echo "  diff /tmp/xcconfig.before \"$XCCONFIG\"   # values should be identical"
