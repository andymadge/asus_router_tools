#!/bin/sh
# Shared helpers for the ASUS Router Tools check scripts
# Version: 0.1.0
#
# Sourced, not run. Callers set these before using the helpers:
#   LOGFILE    - log file path, e.g. /tmp/usb_health_check.log
#   LOG_PREFIX - prefix for log and syslog lines, e.g. "USB Health"
#   TIMESTAMP  - timestamp for this run's log lines
#   VERBOSE    - 1 to also print to stdout
#   DRY_RUN    - 1 to print alerts instead of sending them (testing)

# Log with timestamp (file + syslog)
log_message() {
    echo "[$TIMESTAMP] $LOG_PREFIX: $1" >> "$LOGFILE"
    logger "$LOG_PREFIX: $1"
    if [ "$VERBOSE" = "1" ]; then
        echo "[$TIMESTAMP] $LOG_PREFIX: $1"
    fi
}

# Log only in verbose mode
log_verbose() {
    if [ "$VERBOSE" = "1" ]; then
        echo "[$TIMESTAMP] $LOG_PREFIX: $1" >> "$LOGFILE"
        echo "[$TIMESTAMP] $LOG_PREFIX: $1"
    fi
}

# Send a Telegram alert if the notifier is installed. Returns non-zero if it
# couldn't be delivered (the notifier queues it for its next successful send),
# so callers that alert only once can retry on their next run.
send_alert() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "--- would send Telegram alert ---"
        echo "$1"
        echo "---"
    elif [ -f "/jffs/scripts/telegram_notify.sh" ]; then
        /jffs/scripts/telegram_notify.sh "$1" > /dev/null
    fi
}

# Trim the log to its last 500 lines if it gets large
trim_log() {
    if [ -f "$LOGFILE" ]; then
        LINE_COUNT=$(wc -l < "$LOGFILE" 2>/dev/null)
        if [ "$LINE_COUNT" -gt 500 ] 2>/dev/null; then
            TEMP_LOG="${LOGFILE}.trim_$$"
            tail -500 "$LOGFILE" > "$TEMP_LOG" 2>/dev/null
            if [ -s "$TEMP_LOG" ]; then
                mv "$TEMP_LOG" "$LOGFILE"
            else
                rm -f "$TEMP_LOG"
            fi
        fi
    fi
}
