#!/bin/bash
set -euo pipefail

POOL="backup1"
DISK="/dev/disk/by-id/ata-ST2000DM008-2FR102_WFL37651"

PROJECT_SOURCE="/the_vault/ComputerScience/"
PROJECT_DEST="/backup1/projects_backup/ComputerScience/"

STORAGE_SOURCE="/the_cave/"
STORAGE_DEST="/backup1/data/"

SNAP="pre-sync-$(date +%Y-%m-%d_%H-%M-%S)"

cleanup() {
    sync

    if zpool list -H "$POOL" >/dev/null 2>&1; then
        zpool export "$POOL" || true
    fi

    sleep 10
    hdparm -y "$DISK" >/dev/null 2>&1 || true
}

trap cleanup EXIT

# Import the backup HDD if it is not already imported
if ! zpool list -H "$POOL" >/dev/null 2>&1; then
    zpool import -f "$POOL"
fi

# Make sure expected destinations exist
test -d "$PROJECT_DEST"
test -d "$STORAGE_DEST"

# Snapshot current backups before syncing
zfs snapshot "backup1/projects_backup@$SNAP"
zfs snapshot "backup1/data@$SNAP"

# Backup programming projects
rsync -aHAX --delete \
    "$PROJECT_SOURCE" \
    "$PROJECT_DEST"

# Backup main storage
rsync -aHAX --delete \
    "$STORAGE_SOURCE" \
    "$STORAGE_DEST"

# Flush all writes before cleanup/export
sync