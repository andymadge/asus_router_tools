# DNS Watchdog False Positive Identification Guide

## Overview

This guide helps you identify and analyze false positives in the DNS watchdog system. False positives occur when the watchdog thinks DNS is failing but it's actually working, or when the issue is not with dnsmasq but with broader network connectivity.

## What Are False Positives?

False positives in DNS monitoring typically fall into these categories:

1. **Network/Internet Issues** - Broader connectivity problems, not dnsmasq
2. **Transient Failures** - Temporary glitches that resolve themselves
3. **Single Domain Issues** - The test domain is down, not your DNS
4. **Timing Issues** - Tests timeout due to slow responses, not actual failures

## Quick Start: Identifying False Positives

### Step 1: Deploy Diagnostic Version

Temporarily replace your regular watchdog with the diagnostic version:

```bash
# Stop the regular cron job
cru d DNSWatchdog

# Run diagnostic version (choose one approach)

# Option A: One-time manual test with verbose output
./dns_watchdog_diagnostic.sh --verbose

# Option B: Run in dry-run mode (logs but doesn't restart services)
./dns_watchdog_diagnostic.sh --dry-run --verbose

# Option C: Set up diagnostic cron job for 24 hours
cru a DNSWatchdogDiag "*/5 * * * * /jffs/asus_router_tools/dns_watchdog_diagnostic.sh --dry-run"
```

### Step 2: Let It Run

Allow the diagnostic version to run through several cycles:
- **Minimum**: 1 hour (12 checks)
- **Recommended**: 24 hours for pattern analysis
- **Ideal**: 48-72 hours if you suspect intermittent issues

### Step 3: Analyze Results

```bash
# View summary analysis
./analyze_false_positives.sh

# View detailed diagnostic log
tail -100 /tmp/dns_watchdog_diagnostic.log

# Watch in real-time
tail -f /tmp/dns_watchdog_diagnostic.log
```

### Step 4: Return to Normal

```bash
# Remove diagnostic cron job
cru d DNSWatchdogDiag

# Restore normal watchdog
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
```

## Understanding Diagnostic Output

### Classification Types

The diagnostic script classifies each failure:

#### ✅ Legitimate Failure
```
Classification: LOCAL DNSMASQ ISSUE (legitimate failure)
Reason: Local DNS fails but external DNS works
```
**Meaning**: Your local dnsmasq is actually broken. Restart is warranted.

#### ⚠️ Network/Internet Issue (False Positive)
```
Classification: NETWORK/INTERNET ISSUE (likely false positive)
Reason: Both local and external DNS fail - broader network problem
```
**Meaning**: Your internet/network is having issues. Restarting dnsmasq won't help.

#### ⚠️ Single Domain Issue (False Positive)
```
Classification: SINGLE DOMAIN ISSUE (likely false positive)
Reason: Only primary test domain fails, others succeed
```
**Meaning**: The test domain (google.com) is having issues, but DNS is working fine.

#### ⚠️ Transient Issue (False Positive)
```
Classification: TRANSIENT ISSUE (possible false positive)
Reason: Inconsistent test results suggest temporary glitch
```
**Meaning**: Temporary network hiccup that resolved during testing.

## Analyzing the Results

### High False Positive Rate (>50%)

**Indicators:**
```bash
./analyze_false_positives.sh
# Output shows:
# False positive rate: 85.7%
# ⚠️ HIGH false positive rate
```

**Common Causes:**
1. **Unstable Internet Connection**
   - Your ISP has intermittent connectivity issues
   - Router's WAN connection is dropping
   - Solution: Focus on network stability, not DNS

2. **Test Domain Unreliability**
   - google.com occasionally slow/unreachable from your location
   - Solution: Change TEST_DOMAIN or test multiple domains

3. **Aggressive Timeout**
   - 10-second timeout too short for your network
   - Solution: Increase TEST_TIMEOUT to 15-20 seconds

4. **Single Test Attempt**
   - One failure triggers restart
   - Solution: Add retry logic (see Mitigation Strategies below)

### Timing Patterns

Look for patterns in when false positives occur:

```bash
# View false positive timestamps
grep "false_positive" /tmp/dns_watchdog_failures.log

# Example output showing pattern:
# 2025-11-25 02:15:00  <- Night time
# 2025-11-25 02:45:00  <- Night time
# 2025-11-25 03:20:00  <- Night time
```

**If clustered at night**: May indicate ISP maintenance windows
**If during peak hours**: May indicate network congestion
**If random**: Likely intermittent connectivity issues

### Duration Analysis

Check test durations from the diagnostic log:

```bash
grep "duration=" /tmp/dns_watchdog_diagnostic.log | tail -20
```

**Good (Normal):**
```
duration=45ms   ✓
duration=52ms   ✓
duration=38ms   ✓
```

**Concerning (Slow):**
```
duration=8500ms   ⚠️
duration=9200ms   ⚠️
duration=10000ms  ⚠️ (timeout)
```

If many tests are >8000ms, your network has latency issues.

## Mitigation Strategies

### Strategy 1: Add Retry Logic to Production Script

Modify `dns_watchdog.sh` to test multiple times before declaring failure:

```bash
# In the main script, replace single test_dns with:
FAILURE_COUNT=0
for attempt in 1 2 3; do
    if ! test_dns; then
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        sleep 2
    else
        FAILURE_COUNT=0
        break
    fi
done

if [ "$FAILURE_COUNT" -ge 2 ]; then
    # Proceed with failure handling
```

### Strategy 2: Test Multiple Domains

Add multi-domain testing to production script:

```bash
# Test multiple domains before declaring failure
test_multiple_domains() {
    DOMAINS="google.com cloudflare.com amazon.com"
    FAILURES=0
    for domain in $DOMAINS; do
        if ! nslookup "$domain" 127.0.0.1 >/dev/null 2>&1; then
            FAILURES=$((FAILURES + 1))
        fi
    done
    # If 2 or more domains fail, DNS is really broken
    [ "$FAILURES" -ge 2 ]
}
```

### Strategy 3: Increase Timeout

If your network is consistently slow:

```bash
# In dns_watchdog.sh, change:
TEST_TIMEOUT=15  # or even 20
```

### Strategy 4: Add External DNS Comparison

Before restarting dnsmasq, verify it's a local issue:

```bash
# Test if external DNS works
if nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
    # External DNS works, so restart dnsmasq
    service restart_dnsmasq
else
    # External DNS also fails, network issue
    log_message "Network issue detected, not restarting dnsmasq"
    exit 0
fi
```

### Strategy 5: Consecutive Failure Threshold

Only restart after multiple consecutive failures:

```bash
FAILURE_FILE="/tmp/dns_consecutive_failures"
THRESHOLD=2  # Require 2 consecutive failures (10 minutes apart)

if test_dns fails; then
    CURRENT_FAILURES=$(cat "$FAILURE_FILE" 2>/dev/null || echo "0")
    CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
    echo "$CURRENT_FAILURES" > "$FAILURE_FILE"

    if [ "$CURRENT_FAILURES" -ge "$THRESHOLD" ]; then
        # Restart dnsmasq
    fi
else
    # Success, reset counter
    echo "0" > "$FAILURE_FILE"
fi
```

## Recommended Configuration Based on Analysis

### If False Positive Rate < 20%
✅ **Current configuration is good**
- Keep existing dns_watchdog.sh
- No changes needed

### If False Positive Rate 20-50%
⚠️ **Minor improvements recommended**
- Add 2-3 retry attempts
- Or increase timeout to 15 seconds
- Or test 2-3 domains instead of one

### If False Positive Rate > 50%
🚨 **Significant changes needed**
- Implement retry logic (Strategy 1)
- Add multi-domain testing (Strategy 2)
- Add external DNS comparison (Strategy 4)
- Consider consecutive failure threshold (Strategy 5)

## Example: Real-World Analysis

```bash
$ ./analyze_false_positives.sh

==================================================
DNS Watchdog False Positive Analysis
==================================================

--- Summary Statistics ---
Total DNS checks: 288
Failures detected: 12
False positives: 10
Legitimate failures: 2

False positive rate: 83.3%

--- False Positive Classifications ---
Reasons for false positives:
  Network/Internet issues: 7
  Single domain failures: 2
  Transient issues: 1

--- Recommendations ---
⚠️ HIGH false positive rate (83%)

Recommended actions:
1. Consider increasing TEST_ATTEMPTS in dns_watchdog.sh
2. The current test domain (google.com) may be unreliable
3. Check if network/internet connectivity is unstable
4. Review if TEST_TIMEOUT needs adjustment

Note: Most false positives are network/internet issues
This suggests DNS is working but internet connectivity is intermittent
```

**Interpretation:**
- 83% false positive rate is very high
- Most are "Network/Internet issues" (7 out of 10)
- Recommendation: Implement external DNS comparison (Strategy 4)
- This will prevent unnecessary dnsmasq restarts when internet is flaky

## Testing Your Changes

After implementing mitigation strategies:

1. Deploy changes to production
2. Run diagnostic version in parallel for comparison:
   ```bash
   # Keep production running
   cru l  # Verify DNSWatchdog is active

   # Run diagnostic manually when you suspect a false positive
   ./dns_watchdog_diagnostic.sh --verbose --dry-run
   ```

3. Monitor for 1-2 weeks
4. Re-run analysis to verify improvement

## Additional Diagnostic Commands

### View Only Failures
```bash
grep -E "FAILURE|Classification|Reason:" /tmp/dns_watchdog_diagnostic.log
```

### Count Failure Types
```bash
grep "Classification:" /tmp/dns_watchdog_diagnostic.log | sort | uniq -c
```

### View Network Conditions During Failures
```bash
grep -B5 "FAILURE DETECTED" /tmp/dns_watchdog_diagnostic.log | grep -E "load average|Memory|Ping"
```

### Export Data for Spreadsheet Analysis
```bash
# Create CSV of all failures with timestamps and classifications
awk '/DNS FAILURE DETECTED/{getline; ts=$0} /Classification:/{print ts","$0}' \
  /tmp/dns_watchdog_diagnostic.log > dns_failures.csv
```

## Troubleshooting

### "Diagnostic log not found"
- Run `./dns_watchdog_diagnostic.sh --verbose` first
- Check that script has write permissions to /tmp/

### "Too few data points"
- Let diagnostic run for at least 24 hours
- Manually trigger tests during suspect times

### "All tests show legitimate failures"
- Your dnsmasq may actually be broken
- Check: `pidof dnsmasq` (should return a PID)
- Check: `service restart_dnsmasq && sleep 3 && nslookup google.com 127.0.0.1`

## Support

After running diagnostics, you should be able to answer:
1. What is my false positive rate?
2. What type of false positives am I seeing?
3. When do false positives occur (time patterns)?
4. What mitigation strategy should I implement?

Review this guide alongside your analysis output to determine the best approach for your specific situation.
