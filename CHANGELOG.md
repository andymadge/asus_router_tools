# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Firmware Check (`firmware_check.sh` 0.1.0): daily Telegram alert when a new Asuswrt-Merlin release is available, plus one reminder if it's still not installed 30 days after the alert. It reads the firmware's own daily update check from nvram (`webs_state_flag`/`webs_state_info`), which otherwise only shows as a web UI banner. Versions are compared numerically, so a manually installed newer build isn't reported as out of date. It also alerts once if the firmware's own update check is turned off. An alert that Telegram doesn't accept is retried on the next run instead of being marked as sent. Daily heartbeat; the heartbeat also notes when the firmware's own check is failing. Motivated by the October 2026 DNS outage, caused by firmware ~8 months behind the release that carried the new DNSSEC root key.
- `lib_common.sh`: shared logging, alert and log-trim helpers for the check scripts, sourced via the script's real path (no extra symlink needed).
- install.sh 0.4.0 installs the Firmware Check (symlink, daily cron job at 10:43, boot persistence via services-start).
- USB Health Check (`usb_health_check.sh` 0.1.0): hourly check for a failing USB disk, with Telegram alerts. It watches the kernel log for media/filesystem errors, amtm's boot-time disk check log for filesystem errors, and USB filesystems remounted read-only. Each problem is alerted once, and there's a daily heartbeat. Motivated by a router USB stick that amtm had flagged at almost every boot for ~18 months unnoticed, until it failed with physical read errors.
- install.sh 0.3.0 installs the USB Health Check (symlink, hourly cron job, boot persistence via services-start), using a shared helper for registering cron jobs.
- Failure diagnosis in dns_watchdog.sh (0.4.0): when DNS is still broken after a dnsmasq restart, the watchdog now tests the upstream servers directly and checks whether DNSSEC is enabled, then names the likely cause in the log and the Telegram alert: upstream/WAN outage, DNSSEC validation failure (e.g. a stale root trust anchor after the October 2026 root KSK rollover), or unknown. The alert no longer blindly recommends a router reboot, which can't fix the first two.
- Daily heartbeat log line in dns_watchdog.sh (0.3.0): healthy checks are silent by design, which made a dead watchdog indistinguishable from a healthy one — now one "Heartbeat: watchdog alive" line is logged per day, plus on the first run after each reboot (/tmp is wiped), so `grep Heartbeat /tmp/dns_watchdog.log` always answers "when did it last run?"

### Changed
- usb_health_check.sh 0.1.1 uses the shared helpers in `lib_common.sh`. Alerts are now sent synchronously, and a problem is only recorded as alerted once Telegram accepts the message; otherwise it's retried every hourly run (details logged once, and the daily heartbeat says the alert hasn't been delivered).
- telegram_notify.sh 0.3.1: `TELEGRAM_NO_QUEUE=1` skips the retry queue for callers that retry undelivered alerts themselves (the check scripts, via `lib_common.sh`), so they don't get duplicate messages.

### Fixed
- telegram_notify.sh 0.3.1: the direct-IP fallback used during DNS outages never worked. It connected to `https://<ip>/` with a Host header, which fails TLS verification because the certificate doesn't cover the IP; it now pins the IP with `curl --resolve`. The IP list is refreshed (two of the four no longer served the API).
- telegram_notify.sh 0.3.1 checks Telegram's HTTP status. Previously any HTTP response counted as delivered, so a rejected message (bad token, HTML it can't parse) was silently lost. Now 5xx/429 count as temporary failures (queued, or retried by the caller), and other 4xx as permanent: logged and not queued, and dropped from the queue (with a preview in syslog), so one bad message can't block it. A permanent rejection exits with status 2, and the check scripts then stop retrying that alert.
- telegram_notify.sh 0.3.1 URL-encodes the message text (`--data-urlencode`). Previously an `&` cut the text short and a `+` became a space, so any alert containing HTML-escaped text (`&lt;`, `&amp;`) was truncated mid-tag and rejected by Telegram.
- telegram_notify.sh 0.3.1: the retry queue is taken atomically before flushing, so overlapping notifier runs no longer send the same queued messages twice or overwrite messages queued meanwhile. Rewriting the queue also no longer turns escaped newlines inside messages into line breaks, which split a queued multi-line message into broken entries.
- Firmware Check alerts once if NTP stays unsynced for 3 daily runs, since it skips its check until the clock is right.
- Firmware Check skips runs before NTP has synced the clock (`ntp_ready`), so a wrong clock after a power cut can't make valid alert state look damaged and trigger a repeat alert.
- USB Health Check: if an amtm disk-check alert can't be delivered, the retry rescans the same results even when the log grows before the next run.
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