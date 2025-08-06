#!/bin/sh
# Installation script for ASUS Router DNS Watchdog with Telegram notifications
# Version: 0.1.0
# Run this script on your ASUS router after cloning the repo

set -e  # Exit on any error

echo "=== ASUS Router DNS Watchdog Installation ==="
echo ""

# Check if we're running on the router
if [ ! -d "/jffs" ]; then
    echo "Error: This script must be run on an ASUS router with /jffs partition"
    exit 1
fi

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Script directory: $SCRIPT_DIR"
echo "Repository root: $REPO_ROOT"
echo ""

# Create symlinks in /jffs/scripts/
echo "Creating symlinks in /jffs/scripts/..."

# Remove existing files/symlinks if they exist
rm -f /jffs/scripts/dns_watchdog.sh
rm -f /jffs/scripts/telegram_notify.sh

# Create symlinks
ln -sf "$SCRIPT_DIR/dns_watchdog.sh" /jffs/scripts/dns_watchdog.sh
ln -sf "$SCRIPT_DIR/telegram_notify.sh" /jffs/scripts/telegram_notify.sh

echo "✓ Created symlink: /jffs/scripts/dns_watchdog.sh -> $SCRIPT_DIR/dns_watchdog.sh"
echo "✓ Created symlink: /jffs/scripts/telegram_notify.sh -> $SCRIPT_DIR/telegram_notify.sh"
echo ""

# Set up Telegram config
if [ ! -f "$SCRIPT_DIR/telegram.conf" ]; then
    echo "Setting up Telegram configuration..."
    cp "$SCRIPT_DIR/telegram.conf.example" "$SCRIPT_DIR/telegram.conf"
    chmod 600 "$SCRIPT_DIR/telegram.conf"
    echo "✓ Created $SCRIPT_DIR/telegram.conf from example"
    echo ""
    echo "IMPORTANT: Edit $SCRIPT_DIR/telegram.conf with your bot credentials:"
    echo "  1. Message @BotFather on Telegram and create a bot with /newbot"
    echo "  2. Get your bot token and chat ID (see telegram_notify.sh header for details)"
    echo "  3. Edit the config file with your credentials"
    echo ""
else
    echo "✓ Telegram config already exists: $SCRIPT_DIR/telegram.conf"
    echo ""
fi

# Set up cron job
echo "Setting up cron job..."
# Remove existing cron job if it exists
cru d DNSWatchdog 2>/dev/null || true

# Add new cron job (every 5 minutes)
cru a DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh"
echo "✓ Created cron job: DNS Watchdog runs every 5 minutes"
echo ""

# Verify installation
echo "Verifying installation..."
if [ -L "/jffs/scripts/dns_watchdog.sh" ] && [ -L "/jffs/scripts/telegram_notify.sh" ]; then
    echo "✓ Symlinks created successfully"
else
    echo "✗ Error creating symlinks"
    exit 1
fi

# Check cron job
if cru l | grep -q "DNSWatchdog"; then
    echo "✓ Cron job installed successfully"
else
    echo "✗ Error installing cron job"
    exit 1
fi

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Next steps:"
echo "1. Edit $SCRIPT_DIR/telegram.conf with your Telegram credentials"
echo "2. Test Telegram notifications: /jffs/scripts/telegram_notify.sh"
echo "3. Test DNS watchdog: /jffs/scripts/dns_watchdog.sh --verbose"
echo ""
echo "To update scripts in the future, run:"
echo "  cd $(dirname "$SCRIPT_DIR") && git pull"
echo ""
echo "View cron jobs: cru l"
echo "View logs: tail -f /tmp/dns_watchdog.log"