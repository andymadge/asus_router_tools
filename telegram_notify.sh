#!/bin/sh
# Telegram Notification Script for ASUS Router
# Version: 0.3.0
# Works even when DNS is down by using direct IP addresses

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
TELEGRAM_IPS="149.154.167.50 149.154.167.51 149.154.167.220 149.154.167.99"

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

# Function to send raw telegram message (without queue processing)
send_telegram_raw() {
    local message="$1"
    local success=0
    
    # First try with hostname (if DNS works)
    if curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        --connect-timeout 10 --max-time 30 >/dev/null 2>&1; then
        return 0
    fi
    
    # If hostname fails, try direct IPs
    for ip in $TELEGRAM_IPS; do
        if curl -s -X POST "https://${ip}/bot${BOT_TOKEN}/sendMessage" \
            -H "Host: api.telegram.org" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" \
            --connect-timeout 10 --max-time 30 >/dev/null 2>&1; then
            success=1
            break
        fi
    done
    
    return $((1 - success))
}

# Function to process queued messages
process_queue() {
    if [ ! -f "$QUEUE_FILE" ] || [ ! -s "$QUEUE_FILE" ]; then
        return 0
    fi
    
    local temp_file="${QUEUE_FILE}.tmp"
    local temp_processed="${QUEUE_FILE}.processed"
    local line_num=0
    local sent_count=0
    local failed_messages=""
    
    # Process each message in the queue
    while IFS= read -r escaped_message; do
        line_num=$((line_num + 1))
        
        if [ -n "$escaped_message" ]; then
            local message=$(unescape_message "$escaped_message")
            
            if send_telegram_raw "$message"; then
                sent_count=$((sent_count + 1))
            else
                # Keep failed message for retry
                if [ -n "$failed_messages" ]; then
                    failed_messages="${failed_messages}\n${escaped_message}"
                else
                    failed_messages="$escaped_message"
                fi
            fi
        fi
    done < "$QUEUE_FILE"
    
    # Update queue with only failed messages
    if [ -n "$failed_messages" ]; then
        printf %b "$failed_messages" > "$temp_file" 2>/dev/null && mv "$temp_file" "$QUEUE_FILE"
    else
        # All messages sent successfully, clear queue
        rm -f "$QUEUE_FILE" 2>/dev/null
    fi
    
    # Clean up temp files
    rm -f "$temp_file" "$temp_processed" 2>/dev/null
    
    return 0
}

# Function to send telegram message with queue support
send_telegram() {
    local message="$1"
    local queue_size
    
    # First, try to process any existing queued messages
    process_queue
    
    # Try to send the new message
    if send_telegram_raw "$message"; then
        return 0
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
        echo "Telegram Notification Script version 0.3.0"
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
    
    # Send the message
    if send_telegram "$MESSAGE"; then
        echo "Telegram notification sent successfully"
        logger "Telegram notification sent: $*"
        return 0
    else
        echo "Failed to send Telegram notification"
        logger "Failed to send Telegram notification: $*"
        return 1
    fi
}

# Execute main function with all arguments
main "$@"