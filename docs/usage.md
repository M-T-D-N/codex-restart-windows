# Usage and recovery

This guide owns the operating procedure. [README](../README.md) describes scope;
[validation](validation.md) states which environments were actually tested.

## Prepare and arm

1. Review the code and your existing trusted launcher. Finish active chats and
   other work that relies on the app. This tool cannot check that for you.
2. Select the actual GUI's main process in Task Manager, then inspect that PID
   with `Get-CimInstance Win32_Process`. Do not select a CLI/app-server/backend,
   `--type=renderer` or another child. Executable names differ by installation;
   the tool cannot infer whether an arbitrary selected process is the GUI.
3. Use a regular, non-admin Windows PowerShell session. Keep the logged-in
   session active. Lock/logoff/reboot, another user, remote sessions and app
   upgrades have not been validated.
4. Choose a **new** operation directory under an existing, user-owned local
   parent. Preserve the previous directory and its claim. Never delete a claim
   to make an operation run again.
5. Run `Restart-Codex.ps1 -Action Arm` as shown in the README. Wait for exit zero
   and `WAITING_FOR_EXIT`. If Arm fails or readiness is missing, **do not Quit**.
6. Normally Quit the app; do not use force termination. Read Status after the
   restart window. Verify the GUI and your work yourself before resuming.

`-ExitWaitSeconds` defaults to 180 (allowed 5–1800); `-LaunchWaitSeconds` defaults
to 90 (5–300). Arm allows up to 25 seconds for readiness. These bound polling
windows, not a hard real-time deadline for OS/COM calls or the trusted launcher.
There is no scheduler hard-kill timeout. A hung launcher is not terminated.

For an existing launcher needing arguments, invoke from PowerShell with an array:

```powershell
$launcher = (Resolve-Path 'C:\Tools\MyCodex\Start.ps1').Path # Example only.
.\Restart-Codex.ps1 -Action Arm -DesktopPid $desktopPid -OperationRoot $op `
  -LaunchScript $launcher -LaunchArguments @('-Mode', 'Desktop')
```

Do not put secrets in arguments. The plan stores them in clear text. Do not use
`Invoke-Expression`, policy bypass, administrator execution or unreviewed remote
scripts as substitutes for a permitted local launcher. A shortcut (`.lnk`) is not
a launcher input; leave the ordinary taskbar shortcut unchanged.

## Status and cancellation

```powershell
.\Restart-Codex.ps1 -Action Status -OperationRoot $op
.\Restart-Codex.ps1 -Action Cancel -OperationRoot $op
```

Cancel requests a cooperative stop before dispatch. Its exit zero means the
request was recorded. Wait for `CANCELLED`; a cancellation racing with dispatch
cannot recall an already-started launcher. No process is killed. Status exit
zero only means that a record was read. The stage and `cleanup` fields matter.

| Stage | Meaning / action |
|---|---|
| `PREPARED` | Not ready to Quit. Inspect sidecar errors and task state. |
| `WAITING_FOR_EXIT` | Worker bound the live old process; user may normally Quit. |
| `EXIT_OBSERVED` | Old handle exited zero; checks before dispatch are in progress. |
| `DISPATCH_INTENT` | Dispatch budget consumed, even if a crash prevented launch. |
| `LAUNCH_DISPATCHED` | Launcher started; result is not yet accepted. |
| `RELAUNCH_OBSERVED` | Launcher exited zero; expected new root matched twice. |
| `CANCELLED` / `EXIT_TIMEOUT` | No launch dispatch; old app is not terminated. |
| `HOLD` | A pre-dispatch check failed; no launch dispatch. |
| `LAUNCH_UNCONFIRMED` | Dispatch may have occurred. Inspect before any manual start. |
| `ARM_FAILED` or error sidecar | Preparation/worker rejection; do not Quit or retry blindly. |

Only worker completion exit zero plus `RELAUNCH_OBSERVED` denotes the limited
process observation. It does not establish causality against another concurrent
manual launch, backend health, data integrity or a completed model response.

## Failure and recovery

Keep `plan.json`, `result.json`, any error sidecars and the claim. Inspect the
actual app/process and Task Scheduler entry named by `plan.taskName`. An old
`WAITING_FOR_EXIT` record is not proof that the helper is still alive.

If the app is already running, use it; do not start a second instance. If it is
absent and the exact helper/launcher has finished, use your ordinary launch
shortcut manually. There is no automatic retry or old-version rollback.
Do not replace databases, authentication or app files as part of this procedure.

The worker normally removes its exact task. If `cleanup_required` remains,
first inspect the recorded helper PID and any launcher. The supported cleanup
command refuses while that PID is present and does not terminate it:

```powershell
.\Restart-Codex.ps1 -Action Cleanup -OperationRoot $op
```

An altered task binding is refused; investigate that exact registration rather
than deleting all tasks with a similar name. If Task Scheduler is unavailable,
leave the record and resolve the OS issue using your normal administration
process. Do not weaken security settings to pass a check.

## Update and uninstall

Wait for all your operations to finish and their task cleanup to complete.
Extract a newer source release into a **separate** directory; do not edit bound
files while an operation waits. A different installed app path/hash requires
a fresh operation only after the old operation is conclusively finished.

To uninstall, cancel waiting operations, confirm helpers have exited and remove
only their exact registrations with Cleanup. Then remove this tool's extracted
directory using your normal recoverable file deletion method. Keep private
operation records needed for diagnosis, or remove them separately after review.
No service, startup entry, taskbar link or Codex setting is installed by this tool.
