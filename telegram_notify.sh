#!/bin/sh
# Telegram Notification Script for ASUS Router
# Version: 0.1.0
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

# Function to send telegram message
send_telegram() {
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

# Function to get router info
get_router_info() {
    HOSTNAME=$(uname -n 2>/dev/null || echo "Unknown")
    UPTIME=$(uptime 2>/dev/null || echo "Unknown")
    MEMORY=$(free 2>/dev/null | grep Mem: | awk '{printf "%.1f%%", $3/$2*100}' 2>/dev/null || echo "Unknown")
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
}

# Main script logic
main() {
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

This is a test message from your ASUS router.

Router: ${HOSTNAME}
Time: ${TIMESTAMP}
Uptime: ${UPTIME}
Memory Usage: ${MEMORY}"
    else
        # Arguments provided - use as message
        MESSAGE="🚨 <b>Router Alert</b>

$*

Router: ${HOSTNAME}
Time: ${TIMESTAMP}"
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