#!/bin/sh
# DNS Watchdog for ASUS RT-AX86U Pro with Merlin firmware
# Place this script in /jffs/scripts/dns_watchdog.sh
# Make it executable: chmod +x /jffs/scripts/dns_watchdog.sh

## Set up the cron job to run every 5 minutes:
#     cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
# Verify the cron job is installed
#     cru l

## To check if it's working:
# View recent log entries
#     tail -20 /tmp/dns_watchdog.log
# Monitor logs in real-time (if you want to watch it)
#     tail -f /tmp/dns_watchdog.log

## Temporarily switch to verbose mode for debugging:
# Remove normal cron job
#     cru d DNSWatchdog
# Add verbose cron job for debugging
#     cru a DNSWatchdogVerbose "*/5 * * * * /jffs/scripts/dns_watchdog.sh --verbose"
# Switch back to normal mode later
#     cru d DNSWatchdogVerbose
#     cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"

VERSION="0.4.0"
LOGFILE="/tmp/dns_watchdog.log"
HEARTBEAT_FILE="/tmp/dns_watchdog_heartbeat"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TEST_DOMAIN="google.com"
VERBOSE=0

# Check for command line arguments
if [ "$1" = "--version" ]; then
    echo "DNS Watchdog version $VERSION"
    exit 0
elif [ "$1" = "--verbose" ]; then
    VERBOSE=1
    echo "DNS Watchdog running in VERBOSE mode"
fi

# Function to log with timestamp
log_message() {
    echo "[$TIMESTAMP] DNS Watchdog: $1" >> $LOGFILE
    logger "DNS Watchdog: $1"
    # Also print to stdout in verbose mode
    if [ "$VERBOSE" = "1" ]; then
        echo "[$TIMESTAMP] DNS Watchdog: $1"
    fi
}

# Function to log only if verbose or if it's an error/action
log_conditional() {
    local message="$1"
    local is_error="$2"
    
    if [ "$VERBOSE" = "1" ] || [ "$is_error" = "1" ]; then
        echo "[$TIMESTAMP] DNS Watchdog: $message" >> $LOGFILE
        logger "DNS Watchdog: $message"
        # Print to stdout in verbose mode OR for errors/actions
        if [ "$VERBOSE" = "1" ] || [ "$is_error" = "1" ]; then
            echo "[$TIMESTAMP] DNS Watchdog: $message"
        fi
    fi
}

# Function to get dnsmasq process info
get_dnsmasq_info() {
    PID=$(pidof dnsmasq)
    if [ -n "$PID" ]; then
        if [ -f "/proc/$PID/status" ]; then
            MEMORY=$(grep VmRSS /proc/$PID/status 2>/dev/null | awk '{print $2 $3}')
            if [ -n "$MEMORY" ]; then
                echo "PID: $PID, Memory: $MEMORY"
            else
                echo "PID: $PID, Memory: unknown"
            fi
        else
            echo "PID: $PID"
        fi
    else
        echo "Process not found"
    fi
}

# Improved DNS test function (silent fallback)
# Usage: test_dns [server]   (default: local dnsmasq at 127.0.0.1)
test_dns() {
    local server="${1:-127.0.0.1}"
    # Try with timeout if available, otherwise silently use background process with kill
    if command -v timeout >/dev/null 2>&1; then
        timeout 10 nslookup $TEST_DOMAIN $server >/dev/null 2>&1
        return $?
    else
        # Silent fallback method
        TEMP_FILE="/tmp/dns_test_$$"

        # Run nslookup in background and capture PID
        nslookup $TEST_DOMAIN $server >"$TEMP_FILE" 2>&1 &
        DNS_PID=$!
        
        # Wait up to 10 seconds (using 1-second intervals)
        COUNT=0
        while [ $COUNT -lt 10 ]; do
            if ! kill -0 $DNS_PID 2>/dev/null; then
                # Process finished
                wait $DNS_PID
                RESULT=$?
                rm -f "$TEMP_FILE"
                return $RESULT
            fi
            sleep 1
            COUNT=$((COUNT + 1))
        done
        
        # Timeout reached, kill the process
        kill $DNS_PID 2>/dev/null
        wait $DNS_PID 2>/dev/null  # Clean up zombie
        rm -f "$TEMP_FILE"
        return 1
    fi
}

# Work out *why* DNS is still failing after a dnsmasq restart, so the alert
# points at the right fix. A blanket "reboot the router" is wrong for the
# commonest persistent causes: rebooting can't fix an unreachable upstream or
# a DNSSEC validation failure (e.g. a stale root trust anchor after a root KSK
# rollover, as happened on 2026-10-11).
# Sets DIAG_CAUSE (upstream_down | dnssec | unknown) and DIAG_DETAIL.
diagnose_persistent_failure() {
    DIAG_CAUSE="unknown"
    DIAG_DETAIL=""

    # Upstream servers dnsmasq forwards to (written by the firmware)
    UPSTREAMS=$(sed -n 's/^server=\([0-9.]*\)$/\1/p' /tmp/resolv.dnsmasq 2>/dev/null | head -2)
    [ -z "$UPSTREAMS" ] && UPSTREAMS="1.1.1.1"

    UPSTREAM_OK=""
    for SERVER in $UPSTREAMS; do
        if test_dns "$SERVER"; then
            UPSTREAM_OK="$SERVER"
            log_message "Diagnosis: upstream $SERVER resolves $TEST_DOMAIN OK"
            break
        fi
        log_message "Diagnosis: upstream $SERVER also FAILS to resolve $TEST_DOMAIN"
    done

    if [ -z "$UPSTREAM_OK" ]; then
        DIAG_CAUSE="upstream_down"
        DIAG_DETAIL="Upstream DNS ($(echo $UPSTREAMS | tr ' ' ',')) unreachable - likely a WAN/ISP outage, not dnsmasq"
    elif grep -q '^dnssec$' /etc/dnsmasq.conf 2>/dev/null; then
        # Upstream answers but dnsmasq won't: with DNSSEC on, validation
        # failure is the prime suspect. Log the trusted root key tags so they
        # can be compared with: dig +dnssec . DNSKEY | grep RRSIG
        ANCHORS=$(echo $(sed -n 's/^trust-anchor=\.,\([0-9]*\),.*/\1/p' /etc/dnsmasq.conf))
        DIAG_CAUSE="dnssec"
        DIAG_DETAIL="Upstream $UPSTREAM_OK works but dnsmasq fails, with DNSSEC on - likely DNSSEC validation failure (trusted root key tags: ${ANCHORS:-none})"
    else
        DIAG_DETAIL="Upstream $UPSTREAM_OK works but dnsmasq fails (DNSSEC off) - cause unknown"
    fi
    log_message "Diagnosis: $DIAG_DETAIL"
}

# Start logging
log_conditional "=== DNS Watchdog Check Started ===" 0

# Test DNS resolution
if test_dns; then
    log_conditional "DNS check PASSED - $TEST_DOMAIN resolved successfully" 0

    # Daily heartbeat: healthy runs are otherwise silent, which makes a dead
    # watchdog indistinguishable from a healthy one. Log one line per day
    # (and on the first run after each reboot, since /tmp is wiped) so the
    # log always answers "when did it last run?"
    TODAY=$(date '+%Y-%m-%d')
    if [ "$(cat "$HEARTBEAT_FILE" 2>/dev/null)" != "$TODAY" ]; then
        log_message "Heartbeat: watchdog alive, DNS healthy (v$VERSION)"
        echo "$TODAY" > "$HEARTBEAT_FILE"
    fi
else
    DNS_EXIT_CODE=$?
    log_message "=== DNS FAILURE DETECTED ==="
    log_message "DNS check FAILED - $TEST_DOMAIN resolution failed (exit code: $DNS_EXIT_CODE)"
    
    # Debug: Try manual test and log the actual output
    log_message "Debug: Attempting manual nslookup test..."
    MANUAL_TEST=$(nslookup $TEST_DOMAIN 127.0.0.1 2>&1)
    MANUAL_EXIT=$?
    log_message "Manual test exit code: $MANUAL_EXIT"
    if [ "$VERBOSE" = "1" ]; then
        echo "Manual nslookup output:"
        echo "$MANUAL_TEST"
    fi
    
    log_message "Current dnsmasq status: $(get_dnsmasq_info)"
    log_message "Attempting dnsmasq service restart..."
    
    # Send Telegram notification about DNS failure
    if [ -f "/jffs/scripts/telegram_notify.sh" ]; then
        /jffs/scripts/telegram_notify.sh "⚠️ <b>DNS Failure Detected</b>
<i>DNS resolution failed for test domain.</i>
🔧 <b>Action:</b> Restarting dnsmasq service..." &
    fi
    
    RESTART_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    service restart_dnsmasq
    log_message "dnsmasq restart command issued at $RESTART_TIME"
    
    sleep 5
    log_message "Post-restart dnsmasq status: $(get_dnsmasq_info)"
    
    # Test again after restart
    if test_dns; then
        log_message "SUCCESS - DNS resolution restored after dnsmasq restart"
        log_message "=== DNS RECOVERY COMPLETE ==="
        # Send success notification
        if [ -f "/jffs/scripts/telegram_notify.sh" ]; then
            /jffs/scripts/telegram_notify.sh "✅ <b>DNS Recovery Successful</b>
<i>DNS resolution restored after dnsmasq restart.</i>
🎉 <b>Status:</b> System operational" &
        fi
    else
        log_message "=== CRITICAL SYSTEM FAILURE ==="
        log_message "CRITICAL FAILURE - DNS still not working after dnsmasq restart"
        log_message "Pre-reboot memory: $(cat /proc/meminfo | grep MemAvailable)"
        log_message "Pre-reboot uptime: $(uptime)"

        diagnose_persistent_failure
        case "$DIAG_CAUSE" in
            upstream_down)
                RECOMMENDATION="Check the internet connection / ISP. A router reboot is unlikely to help unless the WAN link itself is stuck."
                ;;
            dnssec)
                RECOMMENDATION="Rebooting will NOT help. Check the DNSSEC root trust anchor (outdated firmware after a root KSK rollover?), or disable DNSSEC as a temporary workaround."
                ;;
            *)
                RECOMMENDATION="Manual router reboot recommended."
                ;;
        esac
        log_message "=== RECOMMENDATION: $RECOMMENDATION ==="

        # Send critical failure notification
        if [ -f "/jffs/scripts/telegram_notify.sh" ]; then
            /jffs/scripts/telegram_notify.sh "🚨 <b>CRITICAL: DNS Failure Persists</b>
<i>dnsmasq restart failed to resolve DNS issues.</i>
🔍 <b>Diagnosis:</b> $DIAG_DETAIL
⚠️ <b>Recommendation:</b> $RECOMMENDATION" &
        fi
        # Reboot command commented out - manual intervention required
        # reboot
    fi
fi

log_conditional "=== DNS Watchdog Check Completed ===" 0

# Improved log cleanup - only trim if file is getting large
if [ -f "$LOGFILE" ]; then
    LINE_COUNT=$(wc -l < "$LOGFILE" 2>/dev/null)
    if [ "$LINE_COUNT" -gt 500 ] 2>/dev/null; then
        # Create backup and trim
        TEMP_LOG="/tmp/dns_watchdog_trim_$$"
        tail -500 "$LOGFILE" > "$TEMP_LOG" 2>/dev/null
        if [ -s "$TEMP_LOG" ]; then
            mv "$TEMP_LOG" "$LOGFILE"
        else
            rm -f "$TEMP_LOG"
        fi
    fi
fi

if [ "$VERBOSE" = "1" ]; then
    echo "DNS Watchdog verbose check completed"
fi