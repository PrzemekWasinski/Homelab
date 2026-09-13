#!/bin/bash

set -u

DISK1="/dev/disk/by-id/ata-ST2000DM008-2FR102_WFL37651"
DISK2="/dev/disk/by-id/ata-ST2000VM003-1ET164_W521SWPS"

POOL1="backup1"
POOL2="backup2"

FAILED=0

disk_is_standby() {
    local disk="$1"
    local output

    output="$(smartctl -n standby -i "$disk" 2>&1 || true)"
    grep -q "Device is in STANDBY mode" <<< "$output"
}

export_pool() {
    local pool="$1"

    if zpool list -H -o name 2>/dev/null | grep -Fxq "$pool"; then
        echo "Exporting $pool..."

        sync

        if zpool export "$pool"; then
            echo "$pool exported successfully."
        else
            echo "ERROR: Could not export $pool."
            return 1
        fi
    else
        echo "$pool is already exported."
    fi

    # Absolutely do not spin down an imported pool.
    if zpool list -H -o name 2>/dev/null | grep -Fxq "$pool"; then
        echo "ERROR: $pool is still imported."
        return 1
    fi

    return 0
}

spin_down() {
    local pool="$1"
    local disk="$2"
    local attempt

    if [ ! -b "$disk" ]; then
        echo "ERROR: $disk is unavailable."
        return 1
    fi

    if disk_is_standby "$disk"; then
        echo "$pool HDD is already in STANDBY."
        return 0
    fi

    for attempt in 1 2 3; do
        echo "Spinning down $pool HDD (attempt $attempt/3)..."

        hdparm -y "$disk" >/dev/null 2>&1 || true
        sleep 5

        if disk_is_standby "$disk"; then
            echo "$pool HDD confirmed in STANDBY."
            return 0
        fi

        echo "$pool HDD is still awake."

        if [ "$attempt" -lt 3 ]; then
            sleep 5
        fi
    done

    echo "ERROR: Could not confirm standby for $pool HDD."
    return 1
}

echo "========================================"
echo "Backup HDD shutdown"
echo "========================================"

echo
echo "Flushing pending writes..."
sync

echo
if ! export_pool "$POOL1"; then
    FAILED=1
fi

echo
if ! export_pool "$POOL2"; then
    FAILED=1
fi

echo
echo "Flushing writes after pool exports..."
sync

echo
if ! zpool list -H -o name 2>/dev/null | grep -Fxq "$POOL1"; then
    spin_down "$POOL1" "$DISK1" || FAILED=1
else
    echo "REFUSING to spin down $POOL1 because it is imported."
    FAILED=1
fi

echo
if ! zpool list -H -o name 2>/dev/null | grep -Fxq "$POOL2"; then
    spin_down "$POOL2" "$DISK2" || FAILED=1
else
    echo "REFUSING to spin down $POOL2 because it is imported."
    FAILED=1
fi

echo
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
    echo "One or more HDDs could not be safely shut down."
    exit 1
fi

echo "Both backup HDDs are in standby."
echo "========================================"