# v0.1.0-preview.1 — Windows restart coordinator (source preview)

A user-armed coordinator that waits for a specific desktop process to exit,
then dispatches a trusted PowerShell launcher at most once through an independent
non-elevated Windows Task Scheduler worker. The normal taskbar shortcut is
unchanged. Scripts and documentation are MIT licensed; no app binary is bundled.

Local integration: seven real Task Scheduler scenarios with synthetic processes
passed, including survival after the arming parent exits, cancellation, timeout,
nonzero exit, changed launcher, competing version, and a launcher that exits
without starting an app. The consumed-operation check rejected a second launch.

**This is a source preview.** Real Codex GUI/normal-Quit/backend/model acceptance
and fresh-PC installation of this standalone package are not yet verified.
`RELAUNCH_OBSERVED` means only that the launcher exited zero and the expected new
process matched twice. It does not prove app readiness, clean data or a normal
Quit action. No database backup, AgentMemory management, forced termination,
automatic retry, fallback version, or update support is included.

Read the README, usage/recovery and validation documents at the released commit
before use. Use an ordinary logged-in Windows PowerShell 5.1 session and your
existing reviewed launcher. Preserve private operation records locally; never
upload credentials, launcher secrets or conversation data.

Assets are a source ZIP and SHA256SUMS. The published Release adds the immutable
source links, exact-commit CI URL/result and downloaded-asset SHA-256 verification.
This file is the release-body template, not evidence of a completed publication.
