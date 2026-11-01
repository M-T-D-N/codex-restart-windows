# Validation scope

This is the **prepublication local validation snapshot** for the initial source
preview. The Release links the exact published commit's completed CI; this
document does not pre-claim a remote result.

## Reproducible commands

Use an existing, local, user-owned scratch parent. These tests create isolated
fixtures beneath it. No real Codex process is closed or restarted.

```powershell
powershell.exe -NoProfile -File tests/run.ps1 -ScratchRoot C:\TestScratch
pwsh.exe -NoProfile -File tests/run.ps1 -ScratchRoot C:\TestScratch
pwsh.exe -NoProfile -File tests/publication.ps1
```

`tests/run.ps1` covers identity changes/missing fields, path rejection, atomic
state replacement, actual PowerShell argument round-trip, task-definition
binding, changed plan rejection, persistent claim and parsing. It uses no model,
does not register a task and never terminates a process. A short argument probe
exits naturally. `tests/publication.ps1` checks the source allowlist, selected
sensitive signatures and local documentation links. Failure exits nonzero.

The separate integration command requires a non-elevated, logged-in Windows
PowerShell 5.1 session with permission to create one's own scheduled tasks:

```powershell
powershell.exe -NoProfile -File tests/scheduler.ps1 -ScratchRoot C:\TestScratch
```

This **does** register transient tasks and compile/start harmless synthetic
processes that exit naturally or through their own stop-file protocol. It keeps
private evidence under its unique scratch directory. Do not run it against real
Codex, and do not treat it as hosted-CI or real-GUI acceptance.

## Completed local integration

The final synthetic unit suite passed **26/26, zero failed/skipped** on both
Windows PowerShell `5.1.26100.9711` and PowerShell `7.6.5`. Source publication
checks covered **20 files, 23 local links and 9 PowerShell command blocks**.
An earlier PowerShell 7 assertion matched an English file-collision message;
the host returned a localized message. The test now verifies the IOException
and Windows error code, and the prior failed log is retained privately.

Windows PowerShell `5.1.26100.9711`, ordinary interactive user: **7 passed,
0 failed, 0 skipped**, command exit 0. Each scenario required exact owned-task
removal as well as its expected terminal/count.

| Scenario | Observed result | Dispatches |
|---|---|---:|
| Arming parent exits; old fixture exits zero | `RELAUNCH_OBSERVED`; duplicate invocation rejected | 1 |
| Cancel before exit | `CANCELLED` | 0 |
| Old fixture stays alive past wait | `EXIT_TIMEOUT` | 0 |
| Old fixture exits 7 | `HOLD` | 0 |
| Bound launcher changed after arm | `HOLD` | 0 |
| Same-name root at another path appears | `HOLD` | 0 |
| Launcher exits zero without new process | `LAUNCH_UNCONFIRMED` | 1 |

The earlier local runs are preserved privately: an atomic-replace null argument
failed under Windows PowerShell; Scheduler normalized a SID to an account name;
and process exit between a wait and CIM query was misclassified as changed
identity. Each was corrected and covered by the final checks above. An argument
round-trip test initially wrapped PowerShell 5.1's returned JSON array twice;
the raw output was correct, and only that test assertion was corrected.
These findings do not establish the cause of unrelated historical Ares failures.

## Not established

- This standalone package's actual Codex GUI/normal-Quit/backend/model path.
- Fresh-PC installation, packaged launcher execution, lock/logoff/reboot,
  multi-session environments or organization-restricted hosts.
- A normal-Quit action or clean data from exit code zero alone.
- Backup/restore, data integrity, AgentMemory health or active-chat detection.
- Future reliability, performance/cost improvement, or updater compatibility.

No old Ares model test or restart receipt is counted as a standalone-package
pass. `RELAUNCH_OBSERVED` remains a limited process observation. CI runs only
source/unit checks and explicitly excludes interactive scheduler acceptance.
