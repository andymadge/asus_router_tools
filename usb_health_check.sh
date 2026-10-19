#!/bin/sh
# USB Storage Health Check for ASUS routers with Asuswrt-Merlin
# Version: 0.1.1
#
# Alerts (via Telegram) when a USB disk attached to the router shows signs of
# failing, so a dying stick is noticed before whatever lives on it (Entware,
# swap, traffic history) breaks in confusing ways. Checks:
#   1. Kernel log  - media/filesystem errors (e.g. "Unrecovered read error",
#                    "critical medium error", "EXT4-fs error")
#   2. amtm disk check - new results in amtm's boot-time disk check log that
#                    report filesystem errors ("RUN fsck MANUALLY")
#   3. Read-only remount - a USB filesystem the kernel has remounted read-only
#
# Each problem is alerted once, not on every run; an alert Telegram doesn't
# accept is retried on the next run. Healthy runs are silent apart
# from one daily heartbeat log line (and one on the first run after each boot).
#
# Install: run ./install.sh (registers an hourly cron job that survives reboots)
# Manual:  /jffs/scripts/usb_health_check.sh --verbose
# Logs:    /tmp/usb_health_check.log
#
# Testing: the inputs can be overridden with environment variables, e.g.
#   USB_HEALTH_DMESG_SOURCE=/tmp/fake_dmesg \
#   USB_HEALTH_DISK_CHECK_LOG=/tmp/fake_disk_check.log \
#   USB_HEALTH_MOUNTS_FILE=/tmp/fake_mounts \
#   USB_HEALTH_STATE_DIR=/tmp/usb_test_state \
#   /jffs/scripts/usb_health_check.sh --verbose

VERSION="0.1.1"
LOGFILE="/tmp/usb_health_check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
VERBOSE=0
LOG_PREFIX="USB Health"

# Inputs (overridable for testing)
DMESG_SOURCE="${USB_HEALTH_DMESG_SOURCE:-}"
DISK_CHECK_LOG="${USB_HEALTH_DISK_CHECK_LOG:-/jffs/addons/amtm/disk_check.log}"
MOUNTS_FILE="${USB_HEALTH_MOUNTS_FILE:-/proc/mounts}"

# State. The disk-check offset must survive reboots (amtm checks disks at
# boot, and its log persists in /jffs), so it lives in /jffs; it is only
# rewritten when the log has grown. Kernel-log and mount state live in /tmp,
# which is wiped at boot together with the kernel log itself.
STATE_DIR="${USB_HEALTH_STATE_DIR:-/jffs/addons/asus_router_tools}"
DISK_CHECK_OFFSET_FILE="$STATE_DIR/usb_health_disk_check_offset"
TMP_STATE_DIR="${USB_HEALTH_STATE_DIR:-/tmp}"
KERNEL_LAST_FILE="$TMP_STATE_DIR/usb_health_kernel_last"
READONLY_ALERTED_FILE="$TMP_STATE_DIR/usb_health_readonly_alerted"
# Problems whose alert couldn't be delivered yet (retried every run)
PENDING_PREFIX="$TMP_STATE_DIR/usb_health_pending"
HEARTBEAT_FILE="$TMP_STATE_DIR/usb_health_heartbeat"

KERNEL_PATTERN='critical medium error|Unrecovered read error|Medium Error|I/O error, dev sd|Buffer I/O error on dev sd|EXT[234]-fs error|remounting filesystem read-only'
DISK_CHECK_PATTERN='UNEXPECTED INCONSISTENCY|contains a file system with errors|RUN fsck MANUALLY|Bad magic number|short read|I/O error'

# Check for command line arguments
if [ "$1" = "--version" ]; then
    echo "USB Health Check version $VERSION"
    exit 0
elif [ "$1" = "--verbose" ]; then
    VERBOSE=1
    echo "USB Health Check running in VERBOSE mode"
fi

# Shared helpers: log_message, log_verbose, send_alert, trim_log
. "$(dirname "$(readlink -f "$0")")/lib_common.sh"

# Escape text for Telegram HTML messages
html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# An undelivered alert is retried on every run. Log a problem's details only
# on its first attempt, so a long Telegram outage doesn't flood the log.
# Usage: first_attempt NAME KEY - true unless KEY is already pending for NAME
first_attempt() {
    [ "$2" != "$(cat "${PENDING_PREFIX}_$1" 2>/dev/null)" ]
}

# Usage: alert_result NAME KEY STATUS - record a send attempt's outcome
alert_result() {
    if [ "$3" = "0" ]; then
        rm -f "${PENDING_PREFIX}_$1"
    else
        UNDELIVERED=1
        if first_attempt "$1" "$2"; then
            log_message "Alert not delivered; will retry on every run until it is"
            echo "$2" > "${PENDING_PREFIX}_$1"
        else
            log_verbose "Alert still not delivered; will retry on the next run"
        fi
    fi
}

get_kernel_log() {
    if [ -n "$DMESG_SOURCE" ]; then
        cat "$DMESG_SOURCE" 2>/dev/null
    else
        dmesg 2>/dev/null
    fi
}

# 1. Kernel log: alert when the most recent matching line changes. Comparing
# the last line (not a count) avoids false alerts when the ring buffer wraps
# and drops old lines; a repeat of the identical error is not re-alerted.
check_kernel_log() {
    MATCHES=$(get_kernel_log | grep -E "$KERNEL_PATTERN")
    if [ -z "$MATCHES" ]; then
        rm -f "${PENDING_PREFIX}_kernel"
        log_verbose "Kernel log: no USB media/filesystem errors"
        return 0
    fi

    LAST=$(echo "$MATCHES" | tail -1)
    if [ "$LAST" = "$(cat "$KERNEL_LAST_FILE" 2>/dev/null)" ]; then
        log_verbose "Kernel log: errors present but already alerted"
        return 1
    fi

    COUNT=$(echo "$MATCHES" | wc -l)
    if first_attempt kernel "$LAST"; then
        log_message "=== USB DISK ERRORS IN KERNEL LOG ($COUNT lines since boot) ==="
        echo "$MATCHES" | tail -3 | while read -r line; do log_message "  $line"; done
    fi
    if send_alert "🚨 <b>USB Disk Errors</b>
<i>Kernel reports storage errors on a USB disk ($COUNT lines since boot).</i>
<code>$(echo "$MATCHES" | tail -3 | cut -c1-120 | html_escape)</code>
⚠️ <b>Recommendation:</b> Back up anything important on the disk and plan to replace it. Media errors mean failing hardware; fsck won't fix that."; then
        echo "$LAST" > "$KERNEL_LAST_FILE"
        alert_result kernel "$LAST" 0
    else
        alert_result kernel "$LAST" 1
    fi
    return 1
}

# 2. amtm disk check log: scan only content added since the last run
check_amtm_disk_check() {
    if [ ! -f "$DISK_CHECK_LOG" ]; then
        log_verbose "amtm disk check log not found ($DISK_CHECK_LOG) - skipping"
        return 0
    fi

    SIZE=$(wc -c < "$DISK_CHECK_LOG")
    if [ -f "$DISK_CHECK_OFFSET_FILE" ]; then
        OFFSET=$(cat "$DISK_CHECK_OFFSET_FILE")
        # Log was trimmed or replaced: start again from the beginning
        [ "$OFFSET" -gt "$SIZE" ] 2>/dev/null && OFFSET=0
    else
        # First run: don't alert on old history, but do check the most recent
        # results (roughly the last disk check run)
        OFFSET=$((SIZE - $(tail -n 15 "$DISK_CHECK_LOG" | wc -c)))
        [ "$OFFSET" -lt 0 ] && OFFSET=0
    fi

    if [ "$OFFSET" = "$SIZE" ]; then
        log_verbose "amtm disk check: no new results"
        return 0
    fi

    NEW_ERRORS=$(tail -c +$((OFFSET + 1)) "$DISK_CHECK_LOG" | grep -E "$DISK_CHECK_PATTERN" | sort -u)

    if [ -z "$NEW_ERRORS" ]; then
        echo "$SIZE" > "$DISK_CHECK_OFFSET_FILE"
        rm -f "${PENDING_PREFIX}_disk_check"
        log_verbose "amtm disk check: new results are clean"
        return 0
    fi

    if first_attempt disk_check "$NEW_ERRORS"; then
        log_message "=== amtm DISK CHECK REPORTS FILESYSTEM ERRORS ==="
        echo "$NEW_ERRORS" | while read -r line; do log_message "  $line"; done
    fi
    if send_alert "⚠️ <b>USB Disk Check Failed</b>
<i>amtm's boot-time disk check found filesystem errors.</i>
<code>$(echo "$NEW_ERRORS" | head -3 | cut -c1-120 | html_escape)</code>
🔍 <b>Details:</b> $DISK_CHECK_LOG
⚠️ <b>Recommendation:</b> Check the kernel log for media errors (dmesg). Repeated filesystem errors usually mean the disk is failing."; then
        echo "$SIZE" > "$DISK_CHECK_OFFSET_FILE"
        alert_result disk_check "$NEW_ERRORS" 0
    else
        # Save where these results start, so the retry rescans the same
        # content even if this was the first run (no offset saved yet) and the
        # log grows before the next run
        echo "$OFFSET" > "$DISK_CHECK_OFFSET_FILE"
        alert_result disk_check "$NEW_ERRORS" 1
    fi
    return 1
}

# 3. Read-only remounts of USB filesystems (the kernel does this after errors)
check_readonly_mounts() {
    RO_MOUNTS=$(awk '$2 ~ /^\/tmp\/mnt\// && $4 ~ /(^|,)ro(,|$)/ {print $1 " on " $2 " (" $3 ")"}' "$MOUNTS_FILE" 2>/dev/null \
        | grep -v '^ubi')
    if [ -z "$RO_MOUNTS" ]; then
        log_verbose "Mounts: no USB filesystems mounted read-only"
        rm -f "$READONLY_ALERTED_FILE" "${PENDING_PREFIX}_readonly"
        return 0
    fi

    if [ "$RO_MOUNTS" = "$(cat "$READONLY_ALERTED_FILE" 2>/dev/null)" ]; then
        log_verbose "Mounts: read-only USB filesystem already alerted"
        return 1
    fi

    if first_attempt readonly "$RO_MOUNTS"; then
        log_message "=== USB FILESYSTEM MOUNTED READ-ONLY ==="
        echo "$RO_MOUNTS" | while read -r line; do log_message "  $line"; done
    fi
    if send_alert "🚨 <b>USB Filesystem Read-Only</b>
<i>A USB filesystem is mounted read-only, usually after the kernel detected errors.</i>
<code>$(echo "$RO_MOUNTS" | html_escape)</code>
⚠️ <b>Recommendation:</b> Anything writing to it (Entware, swap, traffic history) is now failing. Check dmesg and plan to replace the disk."; then
        echo "$RO_MOUNTS" > "$READONLY_ALERTED_FILE"
        alert_result readonly "$RO_MOUNTS" 0
    else
        alert_result readonly "$RO_MOUNTS" 1
    fi
    return 1
}

# Run all checks
mkdir -p "$STATE_DIR" "$TMP_STATE_DIR"
log_verbose "=== USB Health Check Started ==="
PROBLEMS=0
UNDELIVERED=0
check_kernel_log || PROBLEMS=1
check_amtm_disk_check || PROBLEMS=1
check_readonly_mounts || PROBLEMS=1

# Daily heartbeat: routine runs are otherwise silent, so log one line per day
# (and on the first run after each boot, since /tmp is wiped) to prove the
# check is still running - including while a known problem persists.
TODAY=$(date '+%Y-%m-%d')
if [ "$(cat "$HEARTBEAT_FILE" 2>/dev/null)" != "$TODAY" ]; then
    if [ "$PROBLEMS" = "0" ]; then
        log_message "Heartbeat: check alive, USB storage healthy (v$VERSION)"
    elif [ "$UNDELIVERED" = "1" ]; then
        log_message "Heartbeat: check alive, USB storage problems present, alert NOT delivered yet (retrying every run; check telegram.conf) (v$VERSION)"
    else
        log_message "Heartbeat: check alive, USB storage problems present (already alerted) (v$VERSION)"
    fi
    echo "$TODAY" > "$HEARTBEAT_FILE"
fi
log_verbose "=== USB Health Check Completed ==="

trim_log

if [ "$VERBOSE" = "1" ]; then
    echo "USB Health Check verbose check completed"
fi
