# Codex Restart for Windows

[한국어](README.ko.md) · [Usage and recovery](docs/usage.md) · [Validation](docs/validation.md)

A small, user-armed restart coordinator for Windows. It waits for a specific
desktop process to exit, then invokes your trusted PowerShell launcher **at most
once** from an independent, non-elevated Task Scheduler worker. Your ordinary
taskbar shortcut stays unchanged.

**Source preview:** the standalone implementation has passed real Windows Task
Scheduler tests with synthetic processes. A real Codex GUI restart using this
standalone package and a fresh-PC installation are **not yet verified**.
This is an independent community project, not an OpenAI product or update service.

## What it does

- Binds the selected process by PID, creation time, parent, executable path,
  command-line hash, owner SID and session; retains its process handle.
- Requires exit code zero, unchanged bound files and no competing same-name
  root in that user session before one launch dispatch.
- Observes the expected new executable twice and requires launcher exit zero.
  The result is called `RELAUNCH_OBSERVED`, not GUI/model readiness.
- Uses a one-shot registration with no recurring trigger, stored password,
  elevation, forced termination or automatic retry. It removes its own task.

You must finish active work and use the application's **normal Quit** action.
The helper cannot determine whether all chats are idle or distinguish a normal
Quit from another exit with code zero. Closing a window may leave the app alive.
It does not back up databases, verify backend cleanup, manage AgentMemory, change
authentication, or launch a fallback version. Read [scope and design](docs/design.md).

## Requirements

- Windows with Windows PowerShell 5.1, WMI/CIM and Task Scheduler available to the
  logged-in interactive user. **Do not run as administrator.**
- A local, canonical directory with an existing parent, writable by that user;
  network paths, symlinks and junctions are rejected.
- The same installed desktop executable before and after the restart. An app
  update that changes its path or hash is outside this tool's acceptance scope.
- A trusted `.ps1` launcher that starts the app and exits promptly with code zero.
  Its dependencies and behavior remain the launcher's responsibility.
- Local policy must permit the reviewed scripts. This project does not relax
  execution policy, ACLs or organization controls.

No Node, Python, native build or model call is required. PowerShell 7 runs source
checks; the runtime worker intentionally uses Windows PowerShell 5.1.

## Quick start

Extract a source release into a local directory and open an ordinary PowerShell
there. Use a separate terminal if closing Codex would close its terminal.
Review the scripts first. Do not download and execute remote text directly.

```powershell
# In Task Manager, identify the actual GUI's main process and its PID first.
# Do not select a CLI/app-server/backend or a renderer with a similar name.
$desktopPid = 12345 # Replace with the inspected current GUI root PID.
Get-CimInstance Win32_Process -Filter "ProcessId=$desktopPid" |
  Select-Object ProcessId, ParentProcessId, ExecutablePath, CreationDate, CommandLine

$parent = Join-Path $PWD 'operations'
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$op = Join-Path $parent ([guid]::NewGuid().ToString())
$launch = (Resolve-Path '.\examples\Launch-InstalledCodex.ps1').Path

.\Restart-Codex.ps1 -Action Arm -DesktopPid $desktopPid `
  -LaunchScript $launch -OperationRoot $op
```

The example launcher uses the current user's registered `OpenAI.Codex` package
and `App` entry. This discovery path is provided as an **untested real-Codex
example**, not a guarantee for every Store or unpacked installation. Use your
existing reviewed launcher if your installation differs; see [usage](docs/usage.md).

Only after Arm exits zero and reports `WAITING_FOR_EXIT`, finish other work and
normally Quit the selected app within the default 180 seconds. Do not change
the launcher, tool files or app installation while it is armed.

```powershell
.\Restart-Codex.ps1 -Action Status -OperationRoot $op
```

Do not arm a second operation if a result is uncertain. A consumed operation
never retries. Status exit zero means the record was read, not that a restart
succeeded. [Recovery instructions](docs/usage.md#failure-and-recovery) explain
cancellation, stale registrations, update, uninstall and manual recovery.

## Tests and provenance

See [validation](docs/validation.md) for the exact test classes, preserved
development failures and limitations. Hosted CI covers source checks, not an
interactive desktop restart. Release notes link the exact released commit's CI.

[MIT](LICENSE) covers this repository's scripts and documentation. No Codex,
OpenAI, Ares runtime, database, credentials or third-party binary is bundled.
[Provenance and privacy](docs/privacy-and-license.md) describe local records and
what must never be uploaded. [Changes](CHANGELOG.md) list this preview's behavior.
