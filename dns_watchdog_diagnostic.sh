#!/bin/sh
# DNS Watchdog DIAGNOSTIC VERSION - Enhanced logging to identify false positives
# Version: 0.3.0-diagnostic
#
# This version adds extensive diagnostics to help identify false positive DNS failures.
# Run this temporarily in place of dns_watchdog.sh to gather diagnostic data.
#
# Key enhancements:
# - Multiple test attempts before declaring failure
# - Tests multiple domains
# - Compares local DNS vs external DNS
# - Detailed failure analysis
# - Network condition logging
# - Consecutive failure tracking
# - DRY-RUN mode (logs everything but doesn't restart services)

LOGFILE="/tmp/dns_watchdog_diagnostic.log"
FAILURE_TRACKER="/tmp/dns_watchdog_failures.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
VERBOSE=0
DRY_RUN=0

# Test configuration
TEST_DOMAINS="google.com cloudflare.com amazon.com"
PRIMARY_TEST_DOMAIN="google.com"
TEST_ATTEMPTS=3
TEST_TIMEOUT=10
EXTERNAL_DNS="8.8.8.8"  # Google DNS for comparison

# Check for flags
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose)
            VERBOSE=1
            echo "DNS Watchdog running in VERBOSE mode"
            ;;
        --dry-run)
            DRY_RUN=1
            echo "DNS Watchdog running in DRY-RUN mode (no service restarts)"
            ;;
    esac
    shift
done

# Function to log with timestamp
log_message() {
    echo "[$TIMESTAMP] DNS Watchdog: $1" >> $LOGFILE
    logger "DNS Watchdog: $1"
    if [ "$VERBOSE" = "1" ]; then
        echo "[$TIMESTAMP] DNS Watchdog: $1"
    fi
}

# Function to log diagnostic details
log_diagnostic() {
    echo "[$TIMESTAMP] DIAGNOSTIC: $1" >> $LOGFILE
    if [ "$VERBOSE" = "1" ]; then
        echo "[$TIMESTAMP] DIAGNOSTIC: $1"
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

# Function to test DNS with detailed output capture
test_dns_detailed() {
    local domain="$1"
    local dns_server="$2"
    local attempt="$3"

    log_diagnostic "Test attempt $attempt: domain=$domain, dns_server=$dns_server"

    # Capture full output for analysis
    TEMP_FILE="/tmp/dns_test_detailed_$$_$attempt"
    START_TIME=$(date +%s%3N 2>/dev/null || date +%s)

    if command -v timeout >/dev/null 2>&1; then
        timeout $TEST_TIMEOUT nslookup "$domain" "$dns_server" >"$TEMP_FILE" 2>&1
        RESULT=$?
    else
        # Fallback method
        nslookup "$domain" "$dns_server" >"$TEMP_FILE" 2>&1 &
        DNS_PID=$!

        COUNT=0
        while [ $COUNT -lt $TEST_TIMEOUT ]; do
            if ! kill -0 $DNS_PID 2>/dev/null; then
                wait $DNS_PID
                RESULT=$?
                break
            fi
            sleep 1
            COUNT=$((COUNT + 1))
        done

        if [ $COUNT -eq $TEST_TIMEOUT ]; then
            kill $DNS_PID 2>/dev/null
            wait $DNS_PID 2>/dev/null
            RESULT=124  # Timeout exit code
        fi
    fi

    END_TIME=$(date +%s%3N 2>/dev/null || date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Log detailed results
    log_diagnostic "Result: exit_code=$RESULT, duration=${DURATION}ms"

    if [ $RESULT -ne 0 ]; then
        log_diagnostic "FAILED - Full output:"
        while IFS= read -r line; do
            log_diagnostic "  | $line"
        done < "$TEMP_FILE"
    else
        # For successful queries, log just the IP addresses
        IP_ADDRS=$(grep "^Address" "$TEMP_FILE" | grep -v "#53" | awk '{print $2}' | tr '\n' ' ')
        log_diagnostic "SUCCESS - Resolved IPs: $IP_ADDRS"
    fi

    rm -f "$TEMP_FILE"
    return $RESULT
}

# Function to perform comprehensive DNS test
comprehensive_dns_test() {
    local test_name="$1"
    local domain="$2"
    local dns_server="$3"
    local attempts="$4"

    log_diagnostic "=== Starting $test_name ==="

    local success_count=0
    local failure_count=0

    for i in $(seq 1 $attempts); do
        if test_dns_detailed "$domain" "$dns_server" "$i"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi

        # Small delay between attempts
        if [ $i -lt $attempts ]; then
            sleep 2
        fi
    done

    log_diagnostic "=== $test_name Complete: $success_count/$attempts successful ==="

    # Return success if at least one attempt succeeded
    [ $success_count -gt 0 ]
}

# Function to test multiple domains
test_multiple_domains() {
    local dns_server="$1"
    local server_label="$2"

    log_diagnostic "=== Testing Multiple Domains via $server_label ==="

    local total_success=0
    local total_tested=0

    for domain in $TEST_DOMAINS; do
        total_tested=$((total_tested + 1))
        if test_dns_detailed "$domain" "$dns_server" "1"; then
            total_success=$((total_success + 1))
        fi
        sleep 1
    done

    log_diagnostic "=== Multi-domain test: $total_success/$total_tested domains resolved ==="

    # Return success if at least half of domains resolved
    [ $total_success -ge $((total_tested / 2)) ]
}

# Function to check network conditions
check_network_conditions() {
    log_diagnostic "=== Network Conditions Check ==="

    # Check interface status
    log_diagnostic "Network interfaces:"
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | grep -E "^[a-z]|inet " | while IFS= read -r line; do
            log_diagnostic "  $line"
        done
    fi

    # Ping test to external host
    log_diagnostic "Ping test to 8.8.8.8:"
    PING_RESULT=$(ping -c 3 -W 2 8.8.8.8 2>&1 | tail -2)
    echo "$PING_RESULT" | while IFS= read -r line; do
        log_diagnostic "  $line"
    done

    # Memory and load
    log_diagnostic "System load: $(uptime | awk -F'load average:' '{print $2}')"
    log_diagnostic "Memory: $(free | grep Mem: | awk '{printf "Used: %.1f%% ", $3/$2*100}')"
}

# Function to track consecutive failures
track_failure() {
    local failure_type="$1"
    echo "$(date +%s)|$failure_type|$TIMESTAMP" >> "$FAILURE_TRACKER"

    # Keep only last 24 hours of failures
    if [ -f "$FAILURE_TRACKER" ]; then
        TEMP_TRACKER="/tmp/dns_failure_tracker_$$"
        CUTOFF_TIME=$(($(date +%s) - 86400))

        while IFS='|' read -r timestamp type timestr; do
            if [ "$timestamp" -gt "$CUTOFF_TIME" ]; then
                echo "$timestamp|$type|$timestr" >> "$TEMP_TRACKER"
            fi
        done < "$FAILURE_TRACKER"

        if [ -f "$TEMP_TRACKER" ]; then
            mv "$TEMP_TRACKER" "$FAILURE_TRACKER"
        fi
    fi

    # Count recent failures (last hour)
    ONE_HOUR_AGO=$(($(date +%s) - 3600))
    RECENT_FAILURES=$(awk -F'|' -v cutoff="$ONE_HOUR_AGO" '$1 > cutoff' "$FAILURE_TRACKER" 2>/dev/null | wc -l)

    log_diagnostic "Recent failures in last hour: $RECENT_FAILURES"
}

# Function to analyze and classify the failure
classify_failure() {
    local local_dns_failed="$1"
    local external_dns_failed="$2"
    local multi_domain_failed="$3"

    log_diagnostic "=== Failure Classification ==="

    if [ "$local_dns_failed" = "1" ] && [ "$external_dns_failed" = "0" ]; then
        log_diagnostic "Classification: LOCAL DNSMASQ ISSUE (legitimate failure)"
        log_diagnostic "Reason: Local DNS fails but external DNS works"
        return 0  # Legitimate failure
    elif [ "$local_dns_failed" = "1" ] && [ "$external_dns_failed" = "1" ]; then
        log_diagnostic "Classification: NETWORK/INTERNET ISSUE (likely false positive)"
        log_diagnostic "Reason: Both local and external DNS fail - broader network problem"
        return 1  # False positive
    elif [ "$local_dns_failed" = "1" ] && [ "$multi_domain_failed" = "0" ]; then
        log_diagnostic "Classification: SINGLE DOMAIN ISSUE (likely false positive)"
        log_diagnostic "Reason: Only primary test domain fails, others succeed"
        return 1  # False positive
    else
        log_diagnostic "Classification: TRANSIENT ISSUE (possible false positive)"
        log_diagnostic "Reason: Inconsistent test results suggest temporary glitch"
        return 1  # False positive
    fi
}

# Main diagnostic check
log_message "=== DIAGNOSTIC DNS Watchdog Check Started ==="
log_diagnostic "Configuration: DRY_RUN=$DRY_RUN, VERBOSE=$VERBOSE, ATTEMPTS=$TEST_ATTEMPTS"
log_diagnostic "Test domains: $TEST_DOMAINS"

# Check network conditions first
check_network_conditions

# Phase 1: Test primary domain against local DNS with retries
log_message "Phase 1: Testing primary domain ($PRIMARY_TEST_DOMAIN) via local DNS (127.0.0.1)"
if comprehensive_dns_test "Local DNS Test" "$PRIMARY_TEST_DOMAIN" "127.0.0.1" "$TEST_ATTEMPTS"; then
    log_message "DNS check PASSED - System operational"
    log_message "=== DIAGNOSTIC DNS Watchdog Check Completed - NO ISSUES ==="
else
    local_dns_failed=1
    log_message "=== DNS FAILURE DETECTED - Starting Diagnostic Analysis ==="

    # Phase 2: Test against external DNS for comparison
    log_message "Phase 2: Testing same domain via external DNS ($EXTERNAL_DNS)"
    if comprehensive_dns_test "External DNS Test" "$PRIMARY_TEST_DOMAIN" "$EXTERNAL_DNS" "2"; then
        external_dns_failed=0
        log_diagnostic "External DNS works - Issue is with local dnsmasq"
    else
        external_dns_failed=1
        log_diagnostic "External DNS also fails - Broader network issue"
    fi

    # Phase 3: Test multiple domains via local DNS
    log_message "Phase 3: Testing multiple domains via local DNS"
    if test_multiple_domains "127.0.0.1" "Local DNS"; then
        multi_domain_failed=0
        log_diagnostic "Other domains resolve - Issue specific to $PRIMARY_TEST_DOMAIN"
    else
        multi_domain_failed=1
        log_diagnostic "Multiple domains fail - Systematic DNS issue"
    fi

    # Classify the failure
    if classify_failure "$local_dns_failed" "$external_dns_failed" "$multi_domain_failed"; then
        log_message "=== LEGITIMATE DNS FAILURE CONFIRMED ==="
        SHOULD_RESTART=1
    else
        log_message "=== FALSE POSITIVE DETECTED ==="
        log_message "This appears to be a false positive - NOT restarting dnsmasq"
        SHOULD_RESTART=0
    fi

    # Track this failure
    if [ "$SHOULD_RESTART" = "1" ]; then
        track_failure "legitimate"
    else
        track_failure "false_positive"
    fi

    # Log dnsmasq status
    log_message "Current dnsmasq status: $(get_dnsmasq_info)"

    # Take action if needed
    if [ "$SHOULD_RESTART" = "1" ]; then
        if [ "$DRY_RUN" = "1" ]; then
            log_message "DRY-RUN MODE: Would restart dnsmasq here"
        else
            log_message "Attempting dnsmasq service restart..."

            # Send Telegram notification
            if [ -f "/jffs/scripts/telegram_notify.sh" ]; then
                /jffs/scripts/telegram_notify.sh "⚠️ <b>DNS Failure Detected</b>
<i>Legitimate DNS resolution failure confirmed after diagnostic tests.</i>
🔧 <b>Action:</b> Restarting dnsmasq service..." &
            fi

            RESTART_TIME=$(date '+%Y-%m-%d %H:%M:%S')
            service restart_dnsmasq
            log_message "dnsmasq restart command issued at $RESTART_TIME"

            sleep 5
            log_message "Post-restart dnsmasq status: $(get_dnsmasq_info)"

            # Test again after restart
            if comprehensive_dns_test "Post-restart Test" "$PRIMARY_TEST_DOMAIN" "127.0.0.1" "2"; then
                log_message "SUCCESS - DNS resolution restored after dnsmasq restart"
                log_message "=== DNS RECOVERY COMPLETE ==="
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
                log_message "=== ROUTER REBOOT WOULD BE INITIATED (disabled in diagnostic mode) ==="
                if [ -f "/jffs/scripts/telegram_notify.sh" ]; then
                    /jffs/scripts/telegram_notify.sh "🚨 <b>CRITICAL: DNS Failure Persists</b>
<i>dnsmasq restart failed to resolve DNS issues.</i>
⚠️ <b>Note:</b> Reboot disabled in diagnostic mode" &
                fi
            fi
        fi
    else
        log_message "No action taken - classified as false positive"
        if [ -f "/jffs/scripts/telegram_notify.sh" ] && [ "$VERBOSE" = "1" ]; then
            /jffs/scripts/telegram_notify.sh "ℹ️ <b>DNS False Positive Detected</b>
<i>DNS test failure detected but classified as false positive.</i>
✅ <b>Action:</b> No restart needed - likely network/internet issue" &
        fi
    fi
fi

log_message "=== DIAGNOSTIC DNS Watchdog Check Completed ==="

# Log rotation
if [ -f "$LOGFILE" ]; then
    LINE_COUNT=$(wc -l < "$LOGFILE" 2>/dev/null)
    if [ "$LINE_COUNT" -gt 1000 ] 2>/dev/null; then
        TEMP_LOG="/tmp/dns_watchdog_diagnostic_trim_$$"
        tail -1000 "$LOGFILE" > "$TEMP_LOG" 2>/dev/null
        if [ -s "$TEMP_LOG" ]; then
            mv "$TEMP_LOG" "$LOGFILE"
        else
            rm -f "$TEMP_LOG"
        fi
    fi
fi

if [ "$VERBOSE" = "1" ]; then
    echo "=== Diagnostic check completed ==="
    echo "View detailed logs: tail -50 $LOGFILE"
    echo "View failure tracking: cat $FAILURE_TRACKER"
fi
