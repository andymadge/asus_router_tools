# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Firmware Check (`firmware_check.sh` 0.1.0): daily Telegram alert when a new Asuswrt-Merlin release is available, plus one reminder if it's still not installed 30 days after the alert. It reads the firmware's own daily update check from nvram (`webs_state_flag`/`webs_state_info`), which otherwise only shows as a web UI banner. Daily heartbeat; the heartbeat also notes when the firmware's own check is failing. Motivated by the October 2026 DNS outage, caused by firmware ~8 months behind the release that carried the new DNSSEC root key.
- install.sh 0.4.0 installs the Firmware Check (symlink, daily cron job at 10:43, boot persistence via services-start).
- USB Health Check (`usb_health_check.sh` 0.1.0): hourly check for a failing USB disk, with Telegram alerts. It watches the kernel log for media/filesystem errors, amtm's boot-time disk check log for filesystem errors, and USB filesystems remounted read-only. Each problem is alerted once, and there's a daily heartbeat. Motivated by a router USB stick that amtm had flagged at almost every boot for ~18 months unnoticed, until it failed with physical read errors.
- install.sh 0.3.0 installs the USB Health Check (symlink, hourly cron job, boot persistence via services-start), using a shared helper for registering cron jobs.
- Failure diagnosis in dns_watchdog.sh (0.4.0): when DNS is still broken after a dnsmasq restart, the watchdog now tests the upstream servers directly and checks whether DNSSEC is enabled, then names the likely cause in the log and the Telegram alert: upstream/WAN outage, DNSSEC validation failure (e.g. a stale root trust anchor after the October 2026 root KSK rollover), or unknown. The alert no longer blindly recommends a router reboot, which can't fix the first two.
- Daily heartbeat log line in dns_watchdog.sh (0.3.0): healthy checks are silent by design, which made a dead watchdog indistinguishable from a healthy one — now one "Heartbeat: watchdog alive" line is logged per day, plus on the first run after each reboot (/tmp is wiped), so `grep Heartbeat /tmp/dns_watchdog.log` always answers "when did it last run?"

### Changed

### Fixed
- Cron job now survives router reboots: install.sh (0.2.0) registers the `cru a DNSWatchdog` line in `/jffs/scripts/services-start` (created if missing, made executable), so the watchdog is re-armed at every boot. Previously the job was only added to the live crontab, which is held in RAM — the first reboot silently killed the watchdog.

## [v0.3.0] - 2025-08-06

### Added
- Rich HTML formatting for all Telegram notifications with emojis, bold headers, and styled text
- HTML formatting examples in script headers and README documentation
- Enhanced DNS watchdog notifications with visual hierarchy and better readability
- Support for custom HTML formatting in telegram_notify.sh messages
- Comprehensive CHANGELOG.md for release tracking

### Changed
- Improved Telegram message order to prioritize content in notification previews
- Enhanced message presentation with code blocks and italic descriptions
- Updated telegram_notify.sh to version 0.2.0 with new formatting features
- Updated dns_watchdog.sh to version 0.2.0 with rich notification formatting
- Repository versioning system changed to semantic versioning (v0.x.x)
- Added changelog requirement to CLAUDE.md for future releases

### Fixed
- Install script bugs: missing telegram.conf symlink and incorrect git pull directory
- Corrected newline formatting in DNS watchdog notification messages
- Fixed execute permissions on scripts

## [v0.2.0] - 2025-08-06

### Added
- Comprehensive security requirements and credential protection guidelines
- Mandatory git discipline requirements and workflow documentation

### Changed
- Updated all documentation for renamed repository folder structure (asus_router → asus_router_tools)
- Fixed repository URL references for correct installation instructions
- Enhanced Entware installation instructions to use amtm tool

### Fixed
- Repository naming consistency throughout documentation

## [v0.1.0] - 2024-08-06

### Added
- Initial DNS watchdog system for ASUS routers with Asuswrt-Merlin firmware
- Telegram notification system with DNS-independent operation using direct IP addresses
- Automated installation script with symlink management for easy updates
- Comprehensive documentation and setup instructions in README.md
- CLAUDE.md with system architecture and development guidelines
- Semantic versioning requirements for individual scripts
- Dual logging system (file and syslog) with automatic log rotation
- Memory monitoring and dnsmasq process tracking
- Cron job integration for continuous DNS monitoring (every 5 minutes)
- Fallback router reboot mechanism for critical DNS failures
- Three notification types: DNS failure, recovery, and critical failure

### Security
- Telegram credentials stored separately in telegram.conf (never committed to git)
- Configuration files protected with restrictive permissions (600)
- Git discipline requirements to prevent credential exposure
- Direct IP address fallbacks for Telegram API during DNS outages

---

## Notes

- Repository versions are independent of individual script versions
- All releases maintain backward compatibility with existing configurations
- No migration steps required between versions