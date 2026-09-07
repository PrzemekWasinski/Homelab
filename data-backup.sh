#!/bin/bash

set -u

PROJECT_SOURCE="/the_vault/ComputerScience/"
STORAGE_SOURCE="/the_cave/"

# Keep the lock until both backups and final disk shutdown have finished.
exec 9>/run/projects-backup.lock || exit 1
flock -n 9 || {
    echo "ERROR: Cannot acquire backup lock; another backup may be running."
    exit 1
}

# Failed ZFS queries must never be mistaken for confirmation of export.
pool_is_exported() {
    local pool="$1"
    local imported
    if ! imported="$(zpool list -H -o name)"; then
        echo "ERROR: Cannot verify that $pool is exported."
        return 1
    fi
    if grep -Fxq "$pool" <<< "$imported"; then
        echo "ERROR: $pool is still imported; refusing to spin down its disk."
        return 1
    fi
    return 0
}

disk_is_standby() {
    local disk="$1"
    local output
    output="$(smartctl -n standby -i "$disk" 2>&1 || true)"
    grep -q "Device is in STANDBY mode" <<< "$output"
}

shutdown_disk() (
    set -euo pipefail
    local pool="$1"
    local disk="$2"
    local attempt

    pool_is_exported "$pool" || exit 1
    [ -b "$disk" ] || {
        echo "ERROR: Backup disk $disk is unavailable."
        exit 1
    }

    echo "Waiting 30 seconds before shutting down $pool disk..."
    sleep 30

    for attempt in 1 2 3; do
        if [ "$attempt" -gt 1 ]; then
            echo "Waiting 10 seconds before retrying $pool..."
            sleep 10
        fi

        # Recheck after each delay, immediately before the ATA command.
        pool_is_exported "$pool" || exit 1
        echo "Forcing $pool disk into standby (attempt $attempt/3)..."
        if ! hdparm -y "$disk"; then
            echo "WARNING: hdparm reported failure for $pool; checking standby."
        fi
        sleep 5
        if disk_is_standby "$disk"; then
            echo "$pool disk is confirmed in STANDBY."
            exit 0
        fi
        echo "$pool disk standby was not confirmed."
    done

    echo "ERROR: $pool disk failed to enter standby after 3 attempts."
    exit 1
)

verify_destination() {
    local dataset="$1"
    local destination="$2"
    local actual
    mountpoint -q "$destination" || {
        echo "ERROR: $destination is not mounted."
        return 1
    }
    actual="$(findmnt -rn -M "$destination" -o SOURCE,FSTYPE)" || return 1
    if [ "$actual" != "$dataset zfs" ]; then
        echo "ERROR: $destination is not mounted from $dataset as ZFS."
        return 1
    fi
}

backup_disk() (
    set -euo pipefail

    POOL="$1"
    DISK="$2"
    VZDUMP_STORAGE="$3"

    PROJECT_DATASET="${POOL}/projects_backup"
    STORAGE_DATASET="${POOL}/data"

    PROJECT_DEST="/${POOL}/projects_backup/ComputerScience/"
    STORAGE_DEST="/${POOL}/data/"

    SNAP="pre-sync-$(date +%Y-%m-%d_%H-%M-%S)"

    cleanup() {
        local RC=$?

        trap - EXIT
        set +e

        echo
        echo "========================================"
        echo "Cleaning up $POOL"
        echo "========================================"

        echo "Flushing all pending writes..."
        if ! sync; then
            echo "ERROR: Failed to flush writes for $POOL."
            RC=1
        fi

        local IMPORTED
        if ! IMPORTED="$(zpool list -H -o name)"; then
            echo "ERROR: Cannot determine whether $POOL is imported; attempting export."
            if ! timeout 60 zpool export "$POOL"; then
                echo "ERROR: Failed to export $POOL."
            fi
            RC=1
        elif grep -Fxq "$POOL" <<< "$IMPORTED"; then
            echo "Exporting $POOL..."

            if timeout 60 zpool export "$POOL"; then
                echo "$POOL exported successfully."
            else
                echo "ERROR: Failed to export $POOL."
                RC=1
            fi
        else
            echo "$POOL is already exported."
        fi

        echo "Cleanup for $POOL finished."
        echo

        exit "$RC"
    }

    trap cleanup EXIT

    echo
    echo "========================================"
    echo "Starting backup to $POOL"
    echo "========================================"

    #
    # Verify source pools are mounted.
    #

    [ "$(zfs get -H -o value mounted the_vault/data)" = "yes" ] || {
        echo "ERROR: the_vault/data is not mounted."
        exit 1
    }

    [ "$(zfs get -H -o value mounted the_cave/data)" = "yes" ] || {
        echo "ERROR: the_cave/data is not mounted."
        exit 1
    }

    [ -d "$PROJECT_SOURCE" ] || {
        echo "ERROR: Project source is unavailable."
        exit 1
    }

    [ -d "$STORAGE_SOURCE" ] || {
        echo "ERROR: Main storage source is unavailable."
        exit 1
    }

    #
    # Verify correct physical disk exists.
    #

    [ -b "$DISK" ] || {
        echo "ERROR: Backup disk $DISK is unavailable."
        exit 1
    }

    #
    # Import pool.
    #

    IMPORTED="$(zpool list -H -o name)"
    if grep -Fxq "$POOL" <<< "$IMPORTED"; then
        echo "$POOL is already imported."
    else
        echo "Importing $POOL..."
        zpool import -f -o cachefile=none "$POOL"
    fi

    #
    # Verify datasets exist.
    #

    zfs list -H "$PROJECT_DATASET" >/dev/null || {
        echo "ERROR: $PROJECT_DATASET does not exist."
        exit 1
    }

    zfs list -H "$STORAGE_DATASET" >/dev/null || {
        echo "ERROR: $STORAGE_DATASET does not exist."
        exit 1
    }

    #
    # Verify actual ZFS mountpoints.
    # This prevents rsync from accidentally writing into
    # ordinary directories on the Proxmox root filesystem.
    #

    mountpoint -q "/${POOL}/projects_backup" || {
        echo "ERROR: /${POOL}/projects_backup is not mounted."
        exit 1
    }

    mountpoint -q "/${POOL}/data" || {
        echo "ERROR: /${POOL}/data is not mounted."
        exit 1
    }

    verify_destination "$PROJECT_DATASET" "/${POOL}/projects_backup"
    verify_destination "$STORAGE_DATASET" "/${POOL}/data"
    [ ! -L "${PROJECT_DEST%/}" ] || {
        echo "ERROR: Project destination is a symbolic link."
        exit 1
    }
    mkdir -p "$PROJECT_DEST"
    [ "$(findmnt -rn -T "$PROJECT_DEST" -o SOURCE,FSTYPE)" = "$PROJECT_DATASET zfs" ] || {
        echo "ERROR: Project destination is outside the expected ZFS dataset."
        exit 1
    }

    #
    # Snapshot previous backup state.
    #

    echo "Creating ZFS snapshots..."

    zfs snapshot "${PROJECT_DATASET}@${SNAP}"
    zfs snapshot "${STORAGE_DATASET}@${SNAP}"

    #
    # Filesystem backups.
    #

    echo "Backing up programming projects to $POOL..."
    verify_destination "$PROJECT_DATASET" "/${POOL}/projects_backup"

    rsync -aHAX --delete \
        "$PROJECT_SOURCE" \
        "$PROJECT_DEST"

    echo "Backing up main storage to $POOL..."
    verify_destination "$STORAGE_DATASET" "/${POOL}/data"

    rsync -aHAX --delete \
        "$STORAGE_SOURCE" \
        "$STORAGE_DEST"

    #
    # Proxmox guest backups.
    #

    echo "Backing up Proxmox guests to $POOL..."

    vzdump 100 101 102 \
        --storage "$VZDUMP_STORAGE" \
        --mode snapshot \
        --compress zstd \
        --prune-backups 'keep-daily=7'

    #
    # Explicit final flush before cleanup/export.
    #

    echo "Flushing writes..."
    sync

    echo "Backup to $POOL completed successfully."
)


FAILED=0


#
# BACKUP HDD 1
#

backup_disk \
    "backup1" \
    "/dev/disk/by-id/ata-ST2000DM008-2FR102_WFL37651" \
    "backup1-vzdump"

RC=$?

if [ "$RC" -ne 0 ]; then
    echo "ERROR: backup1 failed."
    FAILED=1
fi


#
# BACKUP HDD 2
#

backup_disk \
    "backup2" \
    "/dev/disk/by-id/ata-ST2000VM003-1ET164_W521SWPS" \
    "backup2-vzdump"

RC=$?

if [ "$RC" -ne 0 ]; then
    echo "ERROR: backup2 failed."
    FAILED=1
fi


#
# FINAL HDD SHUTDOWN -- both backup jobs and their cleanup have finished.
#

BACKUP1_EXPORTED=0
BACKUP2_EXPORTED=0
if pool_is_exported backup1; then
    BACKUP1_EXPORTED=1
else
    FAILED=1
fi
if pool_is_exported backup2; then
    BACKUP2_EXPORTED=1
else
    FAILED=1
fi

# Direct calls preserve errexit inside each shutdown subshell.
# Still handle the other exported disk when one disk fails.
if [ "$BACKUP1_EXPORTED" -eq 1 ]; then
    shutdown_disk "backup1" "/dev/disk/by-id/ata-ST2000DM008-2FR102_WFL37651"
    RC=$?
    if [ "$RC" -ne 0 ]; then
        FAILED=1
    fi
fi

if [ "$BACKUP2_EXPORTED" -eq 1 ]; then
    shutdown_disk "backup2" "/dev/disk/by-id/ata-ST2000VM003-1ET164_W521SWPS"
    RC=$?
    if [ "$RC" -ne 0 ]; then
        FAILED=1
    fi
fi

#
# FINAL RESULT
#

if [ "$FAILED" -ne 0 ]; then
    echo "One or more backup operations, pool exports, or HDD shutdowns failed."
    exit 1
fi

echo "========================================"
echo "All backups completed successfully."
echo "Both backup pools were exported."
echo "Both backup HDDs were confirmed in standby."
echo "========================================"