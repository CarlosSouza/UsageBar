# UsageBar

A native macOS 14+ menu bar app, in SwiftUI, that monitors subscription limits for Claude, Codex and, experimentally, Devin. It does not measure API spend.

## Run

```sh
git clone https://github.com/CarlosSouza/UsageBar.git
cd UsageBar
bash scripts/build-app.sh
open dist/UsageBar.app
```

The script produces an ad hoc signed `.app` for local use, without installing it into Applications. Distributing to other people still needs a Developer ID signature and notarization. Requires Command Line Tools / Swift 6. The app only runs while it is open and the Mac is awake and online; there is no server-side monitoring.

## Claude

Requires Claude Code v2.1.251+ with a subscription that exposes `rate_limits` in the statusline (documented for Pro/Max). After connecting, data shows up after the assistant's next reply.

```sh
/usr/bin/python3 scripts/connect-claude.py
```

The installer backs up `~/.claude/settings.json`, preserves other preferences and chains the previous statusline command. It is not run automatically by the build. Restart your Claude Code session after installing. A project-specific statusline configuration can override the global one.

Only the percentage, reset time and observation time are exported to `~/Library/Application Support/UsageBar/claude.json`; prompts and replies are never stored. UsageBar reads the file every 30 seconds. Re-runs with identical metrics keep the previous timestamp: after 15 minutes without change the data is conservatively treated as stale. Missing or stale data never becomes zero and never triggers new alerts. Usage outside Claude Code is only observed when the CLI refreshes its limits.

To undo: restore only `statusLine` from the backup and remove the scripts from `~/Library/Application Support/UsageBar/`; keep later changes to other preferences.

## Codex

Log in to the Codex CLI with your ChatGPT subscription and check the executable path in Settings. The app uses `codex app-server` and `account/rateLimits/read` every 5 minutes, with every window returned. It opens no conversations, sends no prompts and does not read authentication tokens directly. API key logins may not return subscription quotas.

## Devin (experimental)

The public consumption API requires Enterprise. This adapter uses the undocumented web dashboard endpoint, also identified in the CodexBar source. Compatibility with Core/basic accounts still needs confirming; no ACU balance is artificially converted into a percentage.

1. Sign in at `https://app.devin.ai/` and open the organization's Usage & Limits.
2. In the browser inspector, Network tab, find the successful request ending in `/billing/quota/usage`.
3. Copy **only into UsageBar's local settings** the Bearer token from `Authorization` and the internal `x-cog-org-id` (`org_…` or `org-…`). Never paste these values into a chat.
4. This version reads `daily_percentage`, `weekly_percentage`, `daily_reset_at` and `weekly_reset_at`. Percentages are used as is: `100` means 100%, `1` means 1%. The old fraction option was removed and any saved preference for it is ignored.
5. Save the session, enable the monitor and compare with the dashboard before enabling alerts.

The token is kept in the Keychain, sent only to `https://app.devin.ai`, and redirects are refused. The session is not renewed automatically; replace it when it expires. There is no browser cookie scanning. Plans without these quotas, or endpoint changes, show up as errors, not as zero usage. Refreshed every 5 minutes.

## Local export (codex.json and devin.json)

Besides `claude.json`, the app writes `~/Library/Application Support/UsageBar/codex.json` and `devin.json` on every read (every 5 minutes while the provider is enabled): `observed_at`, `windows[]` with `id`, `title`, `usedPercent`, `resetsAt`, `observedAt` (epoch seconds) and `error`. Metrics only, no tokens. Local scripts can read these files instead of holding credentials.

## Alerts

Each provider has a 1–100% threshold, initially 90%. An alert is sent when a valid reading reaches or exceeds the threshold, including when the very first reading is already above it. Dedup state per provider, window, reset time and channel persists across runs. Changing the threshold does not resend an already notified window. Delivery failures retry after 5 minutes while the metric stays fresh; network timeouts can cause duplicates if the server had accepted the message.

- **macOS:** in Settings, use "Allow notifications", enable the channel and test. The system may silence banners according to Focus and preferences.
- **iPhone/Apple Watch:** install [ntfy for iOS](https://docs.ntfy.sh/subscribe/phone/). In ntfy, add a subscription filling `Server = https://ntfy.sh` and `Topic = usagebar_...` separately; do not paste the whole URL into the topic field. Then save the configuration in UsageBar, test and enable the channel. Self-hosted HTTPS servers are also accepted.
- On the public server the random topic name acts as the password. Keep it private or configure an access token on a protected topic. UsageBar keeps the optional token in the Keychain and sends ntfy only the alert text.
- Enable ntfy notification mirroring on the Watch. Apple normally delivers to the iPhone **or** the Watch depending on use/lock state, with no guarantee of two simultaneous alerts.

Notifications are disabled until configured. A send being accepted by the system or by ntfy does not prove the device displayed it. The Mac must be on, online and with UsageBar open.

## Verify

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/usagebar-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/usagebar-modules swift run --scratch-path /private/tmp/usagebar-build --cache-path /private/tmp/usagebar-cache --disable-sandbox UsageCoreChecks
/usr/bin/python3 -m unittest discover -s Tests -p 'test_*.py'
```

Tests cover thresholds, reset handling, persistent per-channel dedup, stale/missing data and parsing. Real login validation and device delivery depend on the account setup.

## Sources

- [Claudebar, functional reference](https://github.com/mryll/claudebar)
- [Claude Code: statusline and rate limits](https://code.claude.com/docs/en/statusline#rate-limit-usage)
- [OpenAI docs: Codex App Server](https://developers.openai.com/docs/app-server)
- [Devin: Enterprise consumption API](https://docs.devin.ai/api-reference/v3/consumption/organizations-consumption-daily)
- [CodexBar: Devin web integration](https://github.com/steipete/CodexBar/blob/main/docs/devin.md)
- [ntfy: publishing over HTTP](https://docs.ntfy.sh/publish/)
- [ntfy for iPhone](https://docs.ntfy.sh/subscribe/phone/)
- [Apple: notifications on the Watch](https://support.apple.com/en-us/108369)

## License

[MIT](LICENSE).
