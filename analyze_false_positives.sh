#!/bin/sh
# Analyzer script for DNS watchdog false positives
# Version: 1.0.0

DIAGNOSTIC_LOG="/tmp/dns_watchdog_diagnostic.log"
FAILURE_TRACKER="/tmp/dns_watchdog_failures.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

print_section() {
    echo ""
    echo "--- $1 ---"
}

# Check if diagnostic log exists
if [ ! -f "$DIAGNOSTIC_LOG" ]; then
    echo "${RED}Error: Diagnostic log not found at $DIAGNOSTIC_LOG${NC}"
    echo ""
    echo "Please run the diagnostic version first:"
    echo "  ./dns_watchdog_diagnostic.sh --verbose"
    exit 1
fi

print_header "DNS Watchdog False Positive Analysis"

# Summary statistics
print_section "Summary Statistics"

TOTAL_CHECKS=$(grep -c "DNS Watchdog Check Started" "$DIAGNOSTIC_LOG" 2>/dev/null || echo "0")
FAILURES_DETECTED=$(grep -c "DNS FAILURE DETECTED" "$DIAGNOSTIC_LOG" 2>/dev/null || echo "0")
FALSE_POSITIVES=$(grep -c "FALSE POSITIVE DETECTED" "$DIAGNOSTIC_LOG" 2>/dev/null || echo "0")
LEGITIMATE_FAILURES=$(grep -c "LEGITIMATE DNS FAILURE CONFIRMED" "$DIAGNOSTIC_LOG" 2>/dev/null || echo "0")

echo "Total DNS checks: $TOTAL_CHECKS"
echo "${YELLOW}Failures detected: $FAILURES_DETECTED${NC}"
echo "${RED}False positives: $FALSE_POSITIVES${NC}"
echo "${GREEN}Legitimate failures: $LEGITIMATE_FAILURES${NC}"

if [ "$FAILURES_DETECTED" -gt 0 ]; then
    FALSE_POSITIVE_RATE=$(awk "BEGIN {printf \"%.1f\", ($FALSE_POSITIVES / $FAILURES_DETECTED) * 100}")
    echo ""
    echo "${YELLOW}False positive rate: ${FALSE_POSITIVE_RATE}%${NC}"
fi

# Recent failures from tracker
if [ -f "$FAILURE_TRACKER" ]; then
    print_section "Failure Tracking (Last 24 Hours)"

    ONE_HOUR_AGO=$(($(date +%s) - 3600))
    RECENT_FP=$(awk -F'|' -v cutoff="$ONE_HOUR_AGO" '$1 > cutoff && $2 == "false_positive"' "$FAILURE_TRACKER" 2>/dev/null | wc -l)
    RECENT_LEGIT=$(awk -F'|' -v cutoff="$ONE_HOUR_AGO" '$1 > cutoff && $2 == "legitimate"' "$FAILURE_TRACKER" 2>/dev/null | wc -l)

    echo "Last hour:"
    echo "  False positives: $RECENT_FP"
    echo "  Legitimate failures: $RECENT_LEGIT"

    TWELVE_HOURS_AGO=$(($(date +%s) - 43200))
    RECENT_12H_FP=$(awk -F'|' -v cutoff="$TWELVE_HOURS_AGO" '$1 > cutoff && $2 == "false_positive"' "$FAILURE_TRACKER" 2>/dev/null | wc -l)
    RECENT_12H_LEGIT=$(awk -F'|' -v cutoff="$TWELVE_HOURS_AGO" '$1 > cutoff && $2 == "legitimate"' "$FAILURE_TRACKER" 2>/dev/null | wc -l)

    echo ""
    echo "Last 12 hours:"
    echo "  False positives: $RECENT_12H_FP"
    echo "  Legitimate failures: $RECENT_12H_LEGIT"

    TOTAL_TRACKED_FP=$(grep -c "false_positive" "$FAILURE_TRACKER" 2>/dev/null || echo "0")
    TOTAL_TRACKED_LEGIT=$(grep -c "legitimate" "$FAILURE_TRACKER" 2>/dev/null || echo "0")

    echo ""
    echo "Last 24 hours:"
    echo "  False positives: $TOTAL_TRACKED_FP"
    echo "  Legitimate failures: $TOTAL_TRACKED_LEGIT"
fi

# Classification breakdown
print_section "False Positive Classifications"

echo "Reasons for false positives:"
NETWORK_ISSUES=$(grep -A1 "FALSE POSITIVE DETECTED" "$DIAGNOSTIC_LOG" | grep -c "NETWORK/INTERNET ISSUE" 2>/dev/null || echo "0")
SINGLE_DOMAIN=$(grep -A1 "FALSE POSITIVE DETECTED" "$DIAGNOSTIC_LOG" | grep -c "SINGLE DOMAIN ISSUE" 2>/dev/null || echo "0")
TRANSIENT=$(grep -A1 "FALSE POSITIVE DETECTED" "$DIAGNOSTIC_LOG" | grep -c "TRANSIENT ISSUE" 2>/dev/null || echo "0")

echo "  Network/Internet issues: $NETWORK_ISSUES"
echo "  Single domain failures: $SINGLE_DOMAIN"
echo "  Transient issues: $TRANSIENT"

# Recent false positive details
print_section "Recent False Positive Details"

echo "Last 3 false positives:"
grep -B5 -A10 "FALSE POSITIVE DETECTED" "$DIAGNOSTIC_LOG" | tail -45 | grep -E "DNS Watchdog Check Started|Classification:|Reason:|External DNS|domains resolved"

# Pattern analysis
print_section "Pattern Analysis"

# Check if false positives cluster at certain times
if [ -f "$FAILURE_TRACKER" ]; then
    echo "False positive timestamps (last 10):"
    grep "false_positive" "$FAILURE_TRACKER" | tail -10 | while IFS='|' read -r timestamp type timestr; do
        echo "  $timestr"
    done
fi

# Check for timing patterns
print_section "Timing Patterns"

echo "Test duration analysis (from diagnostic logs):"
grep "duration=" "$DIAGNOSTIC_LOG" | tail -20 | awk -F'duration=' '{print $2}' | awk -F'ms' '{print $1}' | awk '
BEGIN {
    sum=0; count=0; max=0; min=999999;
}
{
    sum+=$1; count++;
    if ($1 > max) max=$1;
    if ($1 < min) min=$1;
}
END {
    if (count > 0) {
        printf "  Average test duration: %.0fms\n", sum/count;
        printf "  Min: %dms, Max: %dms\n", min, max;
        if (max > 8000) {
            printf "  ⚠️  Warning: Some tests are timing out or very slow\n";
        }
    }
}'

# Recommendations
print_section "Recommendations"

if [ "$FALSE_POSITIVES" -gt 0 ]; then
    if [ "$FAILURES_DETECTED" -gt 0 ]; then
        FALSE_POSITIVE_RATE=$(awk "BEGIN {printf \"%.0f\", ($FALSE_POSITIVES / $FAILURES_DETECTED) * 100}")

        if [ "$FALSE_POSITIVE_RATE" -gt 80 ]; then
            echo "${RED}⚠️  HIGH false positive rate (${FALSE_POSITIVE_RATE}%)${NC}"
            echo ""
            echo "Recommended actions:"
            echo "1. Consider increasing TEST_ATTEMPTS in dns_watchdog.sh"
            echo "2. The current test domain (google.com) may be unreliable"
            echo "3. Check if network/internet connectivity is unstable"
            echo "4. Review if TEST_TIMEOUT needs adjustment"
        elif [ "$FALSE_POSITIVE_RATE" -gt 50 ]; then
            echo "${YELLOW}⚠️  MODERATE false positive rate (${FALSE_POSITIVE_RATE}%)${NC}"
            echo ""
            echo "Recommended actions:"
            echo "1. Monitor for patterns in false positive times"
            echo "2. Consider adding retry logic to production script"
        else
            echo "${GREEN}✓ Acceptable false positive rate (${FALSE_POSITIVE_RATE}%)${NC}"
        fi
    fi

    if [ "$NETWORK_ISSUES" -gt "$LEGITIMATE_FAILURES" ]; then
        echo ""
        echo "${YELLOW}Note: Most false positives are network/internet issues${NC}"
        echo "This suggests DNS is working but internet connectivity is intermittent"
    fi
else
    echo "${GREEN}✓ No false positives detected${NC}"
fi

print_section "Viewing Detailed Logs"
echo "Full diagnostic log:"
echo "  tail -100 $DIAGNOSTIC_LOG"
echo ""
echo "Watch live:"
echo "  tail -f $DIAGNOSTIC_LOG"
echo ""
echo "Filter for failures only:"
echo "  grep -E 'FAILURE|Classification' $DIAGNOSTIC_LOG"

print_header "Analysis Complete"
echo ""
