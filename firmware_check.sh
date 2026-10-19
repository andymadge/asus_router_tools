#!/bin/sh
# Firmware Update Check for ASUS routers with Asuswrt-Merlin
# Version: 0.1.0
#
# Alerts (via Telegram) when a new firmware release is available, so the router
# doesn't quietly fall months behind. The firmware already checks for updates
# daily, but only shows the result as a web UI banner that nobody sees. This
# script reads the firmware's own result from nvram:
#   firmware_check_enable - 1 when the firmware's daily update check is on
#   webs_state_flag       - 1 (or 2) when a newer release is available
#   webs_state_info       - the available version, e.g. 3006_102_9_0
#   webs_state_error      - non-zero when the firmware's own check failed
#
# Alerts once per new release, plus one reminder if it's still not installed
# REMIND_DAYS after its alert. Also alerts once if the firmware's own update
# check is turned off, since then no release would ever be seen. An alert that
# can't be delivered is retried on the next run. Healthy runs are silent apart
# from one daily heartbeat log line (and one on the first run after each boot).
#
# Install: run ./install.sh (registers a daily cron job that survives reboots)
# Manual:  /jffs/scripts/firmware_check.sh --verbose
# Logs:    /tmp/firmware_check.log
#
# Testing: the inputs can be overridden with environment variables, e.g.
#   FW_CHECK_INSTALLED=3006_102_6_0 FW_CHECK_FLAG=1 FW_CHECK_LATEST=3006_102_9_0 \
#   FW_CHECK_ENABLED=1 FW_CHECK_NOW=$(date +%s) FW_CHECK_STATE_DIR=/tmp/fw_test_state \
#   FW_CHECK_DRY_RUN=1 /jffs/scripts/firmware_check.sh --verbose

VERSION="0.1.0"
LOGFILE="/tmp/firmware_check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
VERBOSE=0
LOG_PREFIX="Firmware Check"
DRY_RUN="${FW_CHECK_DRY_RUN:-0}"
REMIND_DAYS=30

# State must survive reboots (the reminder clock runs for weeks), so it lives
# in /jffs; it is only rewritten when something changes. The heartbeat lives
# in /tmp, which is wiped at boot.
STATE_DIR="${FW_CHECK_STATE_DIR:-/jffs/addons/asus_router_tools}"
STATE_FILE="$STATE_DIR/firmware_check_state"
DISABLED_ALERTED_FILE="$STATE_DIR/firmware_check_disabled_alerted"
TMP_STATE_DIR="${FW_CHECK_STATE_DIR:-/tmp}"
HEARTBEAT_FILE="$TMP_STATE_DIR/firmware_check_heartbeat"

# Check for command line arguments
if [ "$1" = "--version" ]; then
    echo "Firmware Check version $VERSION"
    exit 0
elif [ "$1" = "--verbose" ]; then
    VERBOSE=1
    echo "Firmware Check running in VERBOSE mode"
fi

# Shared helpers: log_message, log_verbose, send_alert, trim_log
. "$(dirname "$(readlink -f "$0")")/lib_common.sh"

# Installed version in the same form as webs_state_info, e.g. 3006_102_6_0
# (firmver 3.0.0.6 + buildno 102.6 + extendno 0)
get_installed() {
    if [ -n "$FW_CHECK_INSTALLED" ]; then
        echo "$FW_CHECK_INSTALLED"
    else
        echo "$(nvram get firmver | tr -d .)_$(nvram get buildno | tr . _)_$(nvram get extendno)"
    fi
}

# 3006_102_9_0 -> 3006.102.9 (a trailing _0 extendno is dropped)
pretty_version() {
    echo "$1" | sed -e 's/_0$//' -e 's/_/./g'
}

# True if version $1 is newer than $2, comparing the first three fields
# numerically (3006_102_10_0 is newer than 3006_102_9_0). The installed build
# can be newer than a stale webs_state_info, e.g. right after a manual update.
version_newer() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a, x, "_"); split(b, y, "_")
        for (i = 1; i <= 3; i++) {
            if (x[i] + 0 > y[i] + 0) exit 0
            if (x[i] + 0 < y[i] + 0) exit 1
        }
        exit 1
    }'
}

# A plausible epoch timestamp: digits only, after 2017 and not in the future
valid_epoch() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -gt 1500000000 ] && [ "$1" -le "$NOW" ]
}

# "1 day" / "N days"
days() {
    if [ "$1" = "1" ]; then echo "1 day"; else echo "$1 days"; fi
}

INSTALLED=$(get_installed)
ENABLED="${FW_CHECK_ENABLED:-$(nvram get firmware_check_enable)}"
FLAG="${FW_CHECK_FLAG:-$(nvram get webs_state_flag)}"
LATEST="${FW_CHECK_LATEST:-$(nvram get webs_state_info)}"
CHECK_ERROR="${FW_CHECK_ERROR:-$(nvram get webs_state_error)}"
NOW="${FW_CHECK_NOW:-$(date +%s)}"

mkdir -p "$STATE_DIR" "$TMP_STATE_DIR"
log_verbose "=== Firmware Check Started ==="
log_verbose "Installed $(pretty_version "$INSTALLED"), check enabled=$ENABLED, flag=$FLAG, available=${LATEST:-none}, check error=${CHECK_ERROR:-0}"

# State file: "<last alerted version> <epoch first out of date> <epoch alerted> <reminder sent 0|1>"
# The reminder clock runs from when the current release was alerted, so a new
# release arriving while already behind gets its own full REMIND_DAYS.
ALERTED_VERSION=""
FIRST_SEEN=""
ALERTED_AT=""
REMINDED=0
if [ -f "$STATE_FILE" ]; then
    read -r ALERTED_VERSION FIRST_SEEN ALERTED_AT REMINDED < "$STATE_FILE"
    # A damaged state file (e.g. a write cut off by a power loss) is discarded:
    # at worst the current release is alerted again
    if [ -z "$ALERTED_VERSION" ] || ! valid_epoch "$FIRST_SEEN" || ! valid_epoch "$ALERTED_AT" \
        || { [ "$REMINDED" != "0" ] && [ "$REMINDED" != "1" ]; }; then
        log_message "Alert state file damaged, discarding: $(head -c 100 "$STATE_FILE")"
        rm -f "$STATE_FILE"
        ALERTED_VERSION=""
        FIRST_SEEN=""
        ALERTED_AT=""
        REMINDED=0
    fi
fi

if [ "$ENABLED" != "1" ]; then
    # The firmware's own check is off, so webs_state_* never changes and no
    # release would ever be seen: alert once, until it's turned back on
    STATUS="UNKNOWN, firmware's own update check is disabled"
    if [ ! -f "$DISABLED_ALERTED_FILE" ]; then
        log_message "=== FIRMWARE UPDATE CHECK DISABLED (firmware_check_enable=${ENABLED:-unset}) ==="
        if send_alert "⚠️ <b>Router Firmware Update Check Disabled</b>
<i>The router's own daily check for new firmware is turned off, so new releases can't be detected.</i>
🔧 <b>Fix:</b> Administration → Firmware Upgrade → turn the automatic firmware check back on."; then
            touch "$DISABLED_ALERTED_FILE"
        else
            log_message "Alert not delivered; will retry on the next run"
        fi
    fi
else
    if [ -f "$DISABLED_ALERTED_FILE" ]; then
        log_message "Firmware's own update check is enabled again"
        rm -f "$DISABLED_ALERTED_FILE"
    fi

    if { [ "$FLAG" = "1" ] || [ "$FLAG" = "2" ]; } && [ -n "$LATEST" ] && version_newer "$LATEST" "$INSTALLED"; then
        STATUS="update $(pretty_version "$LATEST") available"
        [ -z "$FIRST_SEEN" ] && FIRST_SEEN="$NOW"
        PENDING_DAYS=$(( (NOW - FIRST_SEEN) / 86400 ))

        if [ "$LATEST" != "$ALERTED_VERSION" ]; then
            # A release we haven't alerted on yet
            log_message "=== NEW FIRMWARE AVAILABLE: $(pretty_version "$LATEST") (installed $(pretty_version "$INSTALLED")) ==="
            if [ "$PENDING_DAYS" -gt 0 ]; then
                BEHIND="
⏳ Out of date for $(days "$PENDING_DAYS") (an earlier release was never installed)."
            else
                BEHIND=""
            fi
            if send_alert "🆕 <b>Router Firmware Update Available</b>
<i>Asuswrt-Merlin $(pretty_version "$LATEST") is out; the router is on $(pretty_version "$INSTALLED").</i>$BEHIND
📋 <b>Plan:</b> Install it within 2–4 weeks, at a quiet time, after skimming the release thread on SNBForums for problems.
🔗 https://www.asuswrt-merlin.net/changelog"; then
                echo "$LATEST $FIRST_SEEN $NOW 0" > "$STATE_FILE"
            else
                log_message "Alert not delivered; will retry on the next run"
            fi
        elif [ "$REMINDED" != "1" ] && [ $(( (NOW - ALERTED_AT) / 86400 )) -ge "$REMIND_DAYS" ]; then
            # Same release, still not installed after REMIND_DAYS: remind once
            log_message "=== REMINDER: firmware $(pretty_version "$LATEST") still not installed ($(days "$PENDING_DAYS") out of date) ==="
            if send_alert "⏰ <b>Router Firmware Still Out of Date</b>
<i>Asuswrt-Merlin $(pretty_version "$LATEST") is still not installed; the router is on $(pretty_version "$INSTALLED") and has been out of date for $(days "$PENDING_DAYS").</i>
⚠️ <b>Recommendation:</b> Install it soon. Falling further behind makes each upgrade bigger and riskier (stale firmware caused the October 2026 DNS outage).
🔗 https://www.asuswrt-merlin.net/changelog"; then
                echo "$LATEST $FIRST_SEEN $ALERTED_AT 1" > "$STATE_FILE"
            else
                log_message "Reminder not delivered; will retry on the next run"
            fi
        else
            log_verbose "Update $(pretty_version "$LATEST") already alerted (pending $(days "$PENDING_DAYS"), reminder sent: $REMINDED)"
        fi
    else
        STATUS="up to date"
        if [ -f "$STATE_FILE" ]; then
            log_message "Firmware is now up to date ($(pretty_version "$INSTALLED")); clearing alert state"
            rm -f "$STATE_FILE"
        else
            log_verbose "Firmware up to date ($(pretty_version "$INSTALLED"))"
        fi
    fi
fi

# The firmware's own check can fail (no internet, ASUS server down); if it
# keeps failing, this script can't see new releases, so say so in the heartbeat
if [ -n "$CHECK_ERROR" ] && [ "$CHECK_ERROR" != "0" ]; then
    STATUS="$STATUS, firmware's own update check reports error $CHECK_ERROR"
fi

# Daily heartbeat: routine runs are otherwise silent, so log one line per day
# (and on the first run after each boot, since /tmp is wiped) to prove the
# check is still running
TODAY=$(date '+%Y-%m-%d')
if [ "$(cat "$HEARTBEAT_FILE" 2>/dev/null)" != "$TODAY" ]; then
    log_message "Heartbeat: check alive, installed $(pretty_version "$INSTALLED"), $STATUS (v$VERSION)"
    echo "$TODAY" > "$HEARTBEAT_FILE"
fi
log_verbose "=== Firmware Check Completed ==="

trim_log

if [ "$VERBOSE" = "1" ]; then
    echo "Firmware Check verbose check completed"
fi
