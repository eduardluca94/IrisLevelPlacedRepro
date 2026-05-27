#!/usr/bin/env bash
# Apply UE-357736-fix.patch to C:\UE_5.7 engine source.
# Backs up the original, records its SHA-256 for restore verification, applies the patch.
# After running this, rebuild the Engine module before testing in UE.

set -euo pipefail

ENGINE_ROOT="/c/UE_5.7"
TARGET_FILE="Engine/Source/Runtime/Engine/Private/Net/Iris/ReplicationSystem/NetActorFactory.cpp"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ENGINE_ROOT"

if [[ -f "${TARGET_FILE}.UE357736-backup" ]]; then
    echo "ERROR: ${TARGET_FILE}.UE357736-backup already exists. Run revert-patch.sh first." >&2
    exit 1
fi

echo "Recording SHA-256 of original..."
sha256sum "$TARGET_FILE" > "$PATCH_DIR/NetActorFactory.cpp.sha256.original"
cat "$PATCH_DIR/NetActorFactory.cpp.sha256.original"

echo "Backing up original to ${TARGET_FILE}.UE357736-backup..."
cp "$TARGET_FILE" "${TARGET_FILE}.UE357736-backup"

echo "Making target writable..."
chmod u+w "$TARGET_FILE"

echo "Applying patch..."
patch -p1 < "$PATCH_DIR/UE-357736-fix.patch"

echo "Verifying the new branch is present..."
grep -q "UE-357736:" "$TARGET_FILE" && echo "  OK: UE-357736 comment found in patched file."

echo
echo "Patch applied. Next: rebuild the UnrealEditor target (e.g. via Visual Studio Build Solution)"
echo "in the IrisLevelPlacedRepro.sln, then launch UE and PIE the repro map."
