#!/bin/sh
# Installation script for ASUS Router Tools (DNS Watchdog, USB Health Check,
# Firmware Check)
# with Telegram notifications
# Run this script on your ASUS router after cloning the repo

VERSION="0.4.0"

# Check for --version argument
if [ "$1" = "--version" ]; then
    echo "Installation Script version $VERSION"
    exit 0
fi

set -e  # Exit on any error

echo "=== ASUS Router Tools Installation ==="
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
rm -f /jffs/scripts/usb_health_check.sh
rm -f /jffs/scripts/firmware_check.sh
rm -f /jffs/scripts/telegram_notify.sh
rm -f /jffs/scripts/telegram.conf

# Create symlinks
ln -sf "$SCRIPT_DIR/dns_watchdog.sh" /jffs/scripts/dns_watchdog.sh
ln -sf "$SCRIPT_DIR/usb_health_check.sh" /jffs/scripts/usb_health_check.sh
ln -sf "$SCRIPT_DIR/firmware_check.sh" /jffs/scripts/firmware_check.sh
ln -sf "$SCRIPT_DIR/telegram_notify.sh" /jffs/scripts/telegram_notify.sh
ln -sf "$SCRIPT_DIR/telegram.conf" /jffs/scripts/telegram.conf

echo "✓ Created symlink: /jffs/scripts/dns_watchdog.sh -> $SCRIPT_DIR/dns_watchdog.sh"
echo "✓ Created symlink: /jffs/scripts/usb_health_check.sh -> $SCRIPT_DIR/usb_health_check.sh"
echo "✓ Created symlink: /jffs/scripts/firmware_check.sh -> $SCRIPT_DIR/firmware_check.sh"
echo "✓ Created symlink: /jffs/scripts/telegram_notify.sh -> $SCRIPT_DIR/telegram_notify.sh"
echo "✓ Created symlink: /jffs/scripts/telegram.conf -> $SCRIPT_DIR/telegram.conf"
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

# Set up cron jobs
# cru registrations live in RAM and are wiped on every reboot; Asuswrt-Merlin
# re-runs /jffs/scripts/services-start at each boot, so each job must also be
# re-added from there or it silently dies at the first reboot.
SERVICES_START="/jffs/scripts/services-start"

if [ ! -f "$SERVICES_START" ]; then
    printf '#!/bin/sh\n' > "$SERVICES_START"
    chmod 755 "$SERVICES_START"
    echo "✓ Created $SERVICES_START"
fi

# Usage: install_cron_job NAME "SCHEDULE COMMAND" DESCRIPTION
install_cron_job() {
    NAME="$1"
    ENTRY="$2"
    DESCRIPTION="$3"

    cru d "$NAME" 2>/dev/null || true
    cru a "$NAME" "$ENTRY"
    echo "✓ Created cron job: $DESCRIPTION"

    if grep -q "$NAME" "$SERVICES_START"; then
        echo "✓ Boot registration for $NAME already present in $SERVICES_START"
    else
        echo "cru a $NAME \"$ENTRY\"" >> "$SERVICES_START"
        echo "✓ Added boot registration for $NAME to $SERVICES_START"
    fi
}

echo "Setting up cron jobs..."
install_cron_job DNSWatchdog "*/5 * * * * /jffs/scripts/dns_watchdog.sh" "DNS Watchdog runs every 5 minutes"
install_cron_job USBHealthCheck "17 * * * * /jffs/scripts/usb_health_check.sh" "USB Health Check runs hourly"
install_cron_job FirmwareCheck "43 10 * * * /jffs/scripts/firmware_check.sh" "Firmware Check runs daily at 10:43"

# The firmware only runs services-start if it is executable
if [ ! -x "$SERVICES_START" ]; then
    chmod 755 "$SERVICES_START"
    echo "✓ Made $SERVICES_START executable"
fi
echo ""

# Verify installation
echo "Verifying installation..."
if [ -L "/jffs/scripts/dns_watchdog.sh" ] && [ -L "/jffs/scripts/usb_health_check.sh" ] && [ -L "/jffs/scripts/firmware_check.sh" ] && [ -L "/jffs/scripts/telegram_notify.sh" ] && [ -L "/jffs/scripts/telegram.conf" ]; then
    echo "✓ Symlinks created successfully"
else
    echo "✗ Error creating symlinks"
    exit 1
fi

# Check cron jobs and boot persistence
for NAME in DNSWatchdog USBHealthCheck FirmwareCheck; do
    if cru l | grep -q "$NAME"; then
        echo "✓ Cron job $NAME installed successfully"
    else
        echo "✗ Error installing cron job $NAME"
        exit 1
    fi
    if [ -x "$SERVICES_START" ] && grep -q "$NAME" "$SERVICES_START"; then
        echo "✓ Cron job $NAME will be re-registered at boot via services-start"
    else
        echo "✗ Error persisting cron job $NAME in $SERVICES_START"
        exit 1
    fi
done

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Next steps:"
echo "1. Edit $SCRIPT_DIR/telegram.conf with your Telegram credentials"
echo "2. Test Telegram notifications: /jffs/scripts/telegram_notify.sh"
echo "3. Test DNS watchdog: /jffs/scripts/dns_watchdog.sh --verbose"
echo "4. Test USB health check: /jffs/scripts/usb_health_check.sh --verbose"
echo "5. Test firmware check: /jffs/scripts/firmware_check.sh --verbose"
echo ""
echo "To update scripts in the future, run:"
echo "  cd $SCRIPT_DIR && git pull"
echo ""
echo "View cron jobs: cru l"
echo "View logs: tail -f /tmp/dns_watchdog.log /tmp/usb_health_check.log /tmp/firmware_check.log"