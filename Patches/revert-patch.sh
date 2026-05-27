#!/usr/bin/env bash
# Revert UE-357736-fix.patch from C:\UE_5.7 engine source.
# Restores the backup, verifies SHA-256 matches the pre-patch original, restores read-only attribute.
# After running this, rebuild the Engine module to return to clean-binary state.

set -euo pipefail

ENGINE_ROOT="/c/UE_5.7"
TARGET_FILE="Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ENGINE_ROOT"

if [[ ! -f "${TARGET_FILE}.UE357736-backup" ]]; then
    echo "ERROR: ${TARGET_FILE}.UE357736-backup not found. Was apply-patch.sh run?" >&2
    exit 1
fi

echo "Restoring backup..."
cp "${TARGET_FILE}.UE357736-backup" "$TARGET_FILE"

echo "Verifying SHA-256 matches pre-patch original..."
if sha256sum -c "$PATCH_DIR/NetActorFactory.cpp.sha256.original" >/dev/null 2>&1; then
    echo "  OK: restored file matches original byte-for-byte."
else
    echo "  WARNING: hash mismatch. Manual inspection required." >&2
    sha256sum "$TARGET_FILE"
    cat "$PATCH_DIR/NetActorFactory.cpp.sha256.original"
    exit 1
fi

echo "Removing backup..."
rm "${TARGET_FILE}.UE357736-backup"

echo "Restoring read-only attribute (matching original engine source convention)..."
chmod a-w "$TARGET_FILE"

echo
echo "Engine source restored. Next: rebuild the UnrealEditor target so the precompiled"
echo "Engine.lib also returns to identical-binary clean state. After that, the engine"
echo "is bit-exact to its pre-patch state."
