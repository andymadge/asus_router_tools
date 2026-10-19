#!/bin/sh
# Telegram Notification Script for ASUS Router
# Works even when DNS is down by using direct IP addresses

VERSION="0.3.1"

# SETUP INSTRUCTIONS:
# 1. Message @BotFather on Telegram and create a bot with /newbot
# 2. Copy the bot token provided
# 3. Message your new bot (send any text like "hello")
# 4. Visit https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
# 5. Find your chat ID in the response (look for "chat":{"id":123456789})
# 6. Create telegram.conf in the same directory as this script:
#    BOT_TOKEN="your_bot_token_here"
#    CHAT_ID="your_chat_id_here"
# 7. Secure the config: chmod 600 telegram.conf
# 8. Test with: `./telegram_notify.sh` or `./telegram_notify.sh "Custom message here"`
#
# HTML FORMATTING EXAMPLES:
# ./telegram_notify.sh "<b>DNS Failed</b>"
# ./telegram_notify.sh "<i>Warning:</i> <code>High CPU usage detected</code>"
# ./telegram_notify.sh "🔥 <b>Critical:</b> Router temperature: <code>85°C</code>"

# Configuration - Load from config file
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/telegram.conf"

# Load configuration from file
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    # Fallback to environment variables
    BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
    CHAT_ID="${TELEGRAM_CHAT_ID}"
fi

# Telegram API server IPs (fallback when DNS is down)
# Checked 2026-10-19 with --resolve; refresh with: nslookup api.telegram.org
TELEGRAM_IPS="149.154.166.110 149.154.167.220 149.154.167.99"

# Queue configuration
QUEUE_FILE="/tmp/telegram_queue.txt"
QUEUE_MAX_SIZE=20

# Function to escape message for queue storage
escape_message() {
    local message="$1"
    # Escape newlines, backslashes, and other shell special characters
    printf '%s' "$message" | sed 's/\\/\\\\/g; s/$/\\n/g' | tr -d '\n'
}

# Function to unescape message from queue storage
unescape_message() {
    local escaped="$1"
    printf '%s' "$escaped" | sed 's/\\n/\n/g; s/\\\\/\\/g'
}

# Function to check if queue is full
is_queue_full() {
    local count=$(get_queue_size)
    [ "$count" -ge "$QUEUE_MAX_SIZE" ]
}

# Function to add message to queue
queue_message() {
    local message="$1"
    local escaped_message
    
    escaped_message=$(escape_message "$message")
    
    # Create queue file if it doesn't exist
    touch "$QUEUE_FILE" 2>/dev/null || return 1
    
    # Add message to end of queue
    echo "$escaped_message" >> "$QUEUE_FILE" 2>/dev/null || return 1
    
    return 0
}

# Function to get queue size
get_queue_size() {
    if [ ! -f "$QUEUE_FILE" ] || [ ! -s "$QUEUE_FILE" ]; then
        echo "0"
        return
    fi
    grep -c . "$QUEUE_FILE" 2>/dev/null || echo "0"
}

# POST a message to the Bot API and print the HTTP status ("000" if there was
# no response). Extra arguments go to curl, e.g. --resolve to pin an IP.
post_message() {
    local message="$1"
    shift
    curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=HTML" \
        --connect-timeout 10 --max-time 30 "$@" 2>/dev/null
}

# Function to send raw telegram message (without queue processing)
# Returns 0 if sent, 1 if it may succeed later (no connection, 5xx, 429), or
# 2 if Telegram rejected it permanently (other 4xx, e.g. bad token or HTML it
# can't parse), which retrying won't fix.
send_telegram_raw() {
    local message="$1"
    local code

    # First try with hostname (if DNS works), then pin each known API address
    # with --resolve: during a DNS outage the hostname can't be looked up, and
    # the TLS certificate is only valid for the name, not the bare IP
    for ip in "" $TELEGRAM_IPS; do
        if [ -z "$ip" ]; then
            code=$(post_message "$message")
        else
            code=$(post_message "$message" --resolve "api.telegram.org:443:${ip}")
        fi
        case "$code" in
            2??) return 0 ;;
            429) return 1 ;;
            4??) return 2 ;;
        esac
    done

    return 1
}

# Function to process queued messages
process_queue() {
    if [ ! -s "$QUEUE_FILE" ]; then
        return 0
    fi

    # Take the whole queue atomically, so a notifier running at the same time
    # (e.g. a backgrounded DNS Watchdog alert) neither sends these messages
    # again nor has a message it queues meanwhile overwritten. Messages that
    # still fail are appended back.
    local work_file="${QUEUE_FILE}.$$"
    local rc
    mv "$QUEUE_FILE" "$work_file" 2>/dev/null || return 0

    while IFS= read -r escaped_message; do
        [ -n "$escaped_message" ] || continue
        local message=$(unescape_message "$escaped_message")

        send_telegram_raw "$message"
        rc=$?
        if [ "$rc" = "2" ]; then
            # Rejected by Telegram: retrying won't help, so drop it rather
            # than let it block the queue forever, but say what was lost
            logger "Telegram rejected a queued message; dropped it: $(printf '%s' "$message" | tr '\n' ' ' | cut -c1-80)"
        elif [ "$rc" != "0" ]; then
            # Keep failed message for retry
            echo "$escaped_message" >> "$QUEUE_FILE"
        fi
    done < "$work_file"

    rm -f "$work_file"
    return 0
}

# Function to send telegram message with queue support
send_telegram() {
    local message="$1"
    local queue_size
    local rc
    
    # First, try to process any existing queued messages
    process_queue
    
    # Try to send the new message
    send_telegram_raw "$message"
    rc=$?
    if [ "$rc" = "0" ]; then
        return 0
    elif [ "$rc" = "2" ]; then
        # Rejected by Telegram (bad token, malformed message): queuing won't help
        logger "Telegram rejected the message (check telegram.conf and the message HTML); not queued"
        return 2
    fi
    
    # Callers that retry undelivered alerts themselves set TELEGRAM_NO_QUEUE=1,
    # so a queued copy isn't delivered as well (a duplicate)
    if [ "$TELEGRAM_NO_QUEUE" = "1" ]; then
        return 1
    fi

    # Message failed to send, check if we can queue it
    if is_queue_full; then
        # Queue is full, send overflow notification instead of queuing
        local overflow_msg="🚫 <b>Message Queue Full</b>

<i>Unable to deliver notification - queue has reached maximum capacity of ${QUEUE_MAX_SIZE} messages.</i>

<b>Original message preview:</b>
$(printf '%.100s' "$message" | sed 's/</\&lt;/g; s/>/\&gt;/g')$([ ${#message} -gt 100 ] && echo "...")"
        
        # Try to send overflow notification (don't queue this one)
        send_telegram_raw "$overflow_msg" >/dev/null 2>&1
        return 1
    fi
    
    # Queue the failed message
    if queue_message "$message"; then
        queue_size=$(get_queue_size)
        logger "Telegram message queued (queue size: $queue_size/$QUEUE_MAX_SIZE)"
        return 1
    fi
    
    # Failed to queue message
    logger "Failed to queue Telegram message"
    return 1
}

# Function to get router info
get_router_info() {
    HOSTNAME=$(uname -n 2>/dev/null || echo "Unknown")
    UPTIME=$(uptime 2>/dev/null || echo "Unknown")
    MEMORY=$(free 2>/dev/null | grep Mem: | awk '{printf "%.1f%%", $3/$2*100}' 2>/dev/null || echo "Unknown")
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
}

# Main script logic
main() {
    # Check for --version argument first (before configuration check)
    if [ "$1" = "--version" ]; then
        echo "Telegram Notification Script version $VERSION"
        exit 0
    fi

    # Check if required configuration is set
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        echo "Error: BOT_TOKEN and CHAT_ID not configured"
        echo ""
        echo "Setup instructions:"
        echo "1. Message @BotFather on Telegram"
        echo "2. Create a new bot with /newbot command"
        echo "3. Message your bot, then visit:"
        echo "   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
        echo "4. Create $CONFIG_FILE with:"
        echo "   BOT_TOKEN=\"your_bot_token_here\""
        echo "   CHAT_ID=\"your_chat_id_here\""
        echo "5. Set permissions: chmod 600 $CONFIG_FILE"
        exit 1
    fi
    
    # Get router information
    get_router_info
    
    # Determine message based on arguments
    if [ $# -eq 0 ]; then
        # No arguments - send test message
        MESSAGE="🤖 <b>Router Test Notification</b>

<i>✅ This is a test message from your ASUS router.</i>

<b>📡 Router:</b> <code>${HOSTNAME}</code>
<b>🕐 Time:</b> <code>${TIMESTAMP}</code>
<b>⏱️ Uptime:</b> <code>${UPTIME}</code>
<b>💾 Memory:</b> <code>${MEMORY}</code>"
    else
        # Arguments provided - use as message
        MESSAGE="🚨 <b>Router Alert</b>

$*

<b>📡 Router:</b> <code>${HOSTNAME}</code>
<b>🕐 Time:</b> <code>${TIMESTAMP}</code>"
    fi
    
    # Send the message. Exit status: 0 sent, 1 failed (queued, or for
    # TELEGRAM_NO_QUEUE callers worth retrying), 2 rejected by Telegram
    # (retrying won't help)
    send_telegram "$MESSAGE"
    rc=$?
    if [ "$rc" = "0" ]; then
        echo "Telegram notification sent successfully"
        logger "Telegram notification sent: $*"
    else
        echo "Failed to send Telegram notification"
        logger "Failed to send Telegram notification: $*"
    fi
    return $rc
}

# Execute main function with all arguments
main "$@"