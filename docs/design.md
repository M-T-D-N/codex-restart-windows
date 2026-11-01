# Design and supported boundary

The public tool is a small standalone coordinator, not the private Ares
environment's restart/backup harness. It deliberately has no database, WAL,
memory-directory, tunnel, console-control or service-management code.

`Restart-Codex.ps1` arms an operation. A unique Task Scheduler action starts
`src/Restart.Worker.ps1` in the logged-in user's token (interactive logon, least
privilege). The worker shares `src/Restart.Core.ps1`; it survives the arming
PowerShell's normal exit. There is no recurring trigger or stored password.

The plan binds the worker, core, launcher and desktop image by SHA-256 and the
old process by identity. A retained process handle protects the wait from PID
reuse. Same-basename non-renderer processes in the same user/session are treated
conservatively as possible competitors, even at another executable path. Unknown
metadata fails closed. This may reject unrelated programs with the same name.

A create-new `claim` permanently consumes an operation. The worker writes
`DISPATCH_INTENT` before starting the launcher. A crash in between may therefore
produce **zero** launches and still consume the operation. The promise is at
most one dispatch per operation, not exactly one successful restart. Different
operation directories are not a global lock. Do not arm multiple operations for
one app. The absence check cannot eliminate a simultaneous external launch.

The worker requires old exit zero, unchanged bound inputs and no competing root.
After dispatch, launcher exit zero and two matching observations of the new
root's identity/path/hash produce `RELAUNCH_OBSERVED`. Observations are at least
500 ms apart, subject to OS scheduling. The new root must have been created
after dispatch and have a different PID. PID reuse at that instant is refused.

State replacement is same-directory atomic file replacement with an explicitly
null backup name compatible with Windows PowerShell 5.1. Arm errors use a
separate sidecar if a worker may be running. A second worker cannot overwrite a
consumed operation's successful result. No cross-process database is introduced.

Checks and file hashes are safety evidence, not a security boundary against
malicious same-user modification. Use a trusted private directory. The tool
does not hash a launcher's dependency closure or authenticate its publisher.
It cannot prove a normal Quit, child/backend shutdown, clean databases, GUI
readiness, model response, or AgentMemory health. It does not inspect chats.

Scheduled work is cooperative and time-bounded in its polling loops. Blocking OS
calls and the launcher's own lifetime can exceed those windows. There is no force
cleanup, fallback launch or automatic restart loop. Errors preserve state for
inspection. This scope is appropriate for a source preview, not an unattended
recovery service or a replacement for managed update infrastructure.
