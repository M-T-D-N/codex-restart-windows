# SPDX-License-Identifier: MIT
# Adapted identity/claim/one-shot principles from the private Ares restart helper.
Set-StrictMode -Version Latest

function Get-CrUtc { [DateTimeOffset]::UtcNow.ToString('o') }
function Get-CrHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
function Get-CrTextHash([string]$Text) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Get-CrContext {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ELEVATED_EXECUTION_REFUSED' }
    [pscustomobject]@{ sid=$id.User.Value; sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId }
}
function Assert-CrPath([string]$Path, [switch]$Directory, [switch]$New) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path -match '[\x00-\x1f]' -or
        [IO.Path]::GetPathRoot($Path).Length -ne 3 -or $Path.Substring(2).Contains(':')) { throw 'LOCAL_ABSOLUTE_PATH_REQUIRED' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -cne $Path.TrimEnd('\','/')) { throw 'CANONICAL_PATH_REQUIRED' }
    $itemPath = if ($New) { Split-Path -Parent $full } else { $full }
    if ($New -and (Test-Path -LiteralPath $full)) { throw 'NEW_PATH_ALREADY_EXISTS' }
    $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
    if (-not $New -and (($item -is [IO.DirectoryInfo]) -ne [bool]$Directory)) { throw 'WRONG_PATH_TYPE' }
    for ($part=$item; $null -ne $part; $part=if($part -is [IO.DirectoryInfo]){$part.Parent}else{$part.Directory}) {
        if ($part.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'REPARSE_PATH_REFUSED' }
    }
    $full
}
function Write-CrJson($Value, [string]$Path, [switch]$New) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 16)+"`n")
    $tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $s.Write($bytes,0,$bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
        if ($New) { [IO.File]::Move($tmp,$Path) } else { [IO.File]::Replace($tmp,$Path,[NullString]::Value) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Read-CrJson([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json }
function ConvertTo-CrArgument([AllowEmptyString()][string]$Value) {
    if ($Value -match '[\x00\r\n]') { throw 'ARGUMENT_CONTROL_CHARACTER' }
    # Windows CommandLineToArgvW rules, including empty values and trailing slashes.
    '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Join-CrArguments([string[]]$Values) { ($Values | ForEach-Object { ConvertTo-CrArgument $_ }) -join ' ' }
function Read-CrProcess([int]$ProcessId) {
    $p=Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -OperationTimeoutSec 5 -ErrorAction Stop
    if (-not $p) { return $null }
    if (-not $p.ExecutablePath -or -not $p.CommandLine -or -not $p.CreationDate) { throw 'PROCESS_METADATA_UNAVAILABLE' }
    $owner=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
    if ($owner.ReturnValue -ne 0 -or -not $owner.Sid) { throw 'PROCESS_OWNER_UNAVAILABLE' }
    [pscustomobject]@{
        pid=[int]$p.ProcessId; parentPid=[int]$p.ParentProcessId
        path=[string]$p.ExecutablePath; createdAt=([DateTimeOffset]$p.CreationDate).ToString('o')
        commandHash=Get-CrTextHash $p.CommandLine; sessionId=[int]$p.SessionId; sid=[string]$owner.Sid
        childRole=[bool]($p.CommandLine -match '(?:^|\s)--type(?:=|\s)')
    }
}
function Test-CrIdentity($Expected,$Actual) {
    if (-not $Expected -or -not $Actual) { return $false }
    foreach ($key in @('pid','parentPid','path','createdAt','commandHash','sessionId','sid','childRole')) {
        if (-not $Expected.PSObject.Properties[$key] -or -not $Actual.PSObject.Properties[$key] -or
            [string]$Expected.$key -cne [string]$Actual.$key) { return $false }
    }
    $Expected.pid -gt 0 -and $Expected.commandHash -cmatch '^[a-f0-9]{64}$'
}
function Get-CrRoots($Plan) {
    $name=[IO.Path]::GetFileName($Plan.desktop.path).Replace("'","''")
    $rows=@(Get-CimInstance Win32_Process -Filter "Name = '$name'" -OperationTimeoutSec 5 -ErrorAction Stop)
    foreach ($row in $rows) {
        if ([int]$row.SessionId -ne [int]$Plan.sessionId) { continue }
        # An unreadable same-name process in this session is uncertainty, not absence.
        $p=Read-CrProcess ([int]$row.ProcessId)
        if (-not $p) { continue }
        if ($p.sid -ceq $Plan.sid -and -not $p.childRole) { $p }
    }
}
function Assert-CrInputs($Plan,[string]$Root) {
    $context=Get-CrContext
    if ($Plan.schema -ne 1 -or $Plan.operationId -cnotmatch '^[0-9a-f-]{36}$' -or
        $Plan.root -cne $Root -or $Plan.sid -cne $context.sid -or $Plan.sessionId -ne $context.sessionId -or
        $Plan.taskName -cne ('CodexRestart-'+$Plan.operationId)) { throw 'PLAN_CONTEXT_MISMATCH' }
    foreach ($bound in @($Plan.worker,$Plan.core,$Plan.launcher,$Plan.image)) {
        $null=Assert-CrPath $bound.path
        if ($bound.sha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-CrHash $bound.path) -cne $bound.sha256) { throw 'BOUND_FILE_CHANGED' }
    }
    if ($Plan.image.path -cne $Plan.desktop.path -or $Plan.exitWaitSeconds -lt 5 -or $Plan.exitWaitSeconds -gt 1800 -or
        $Plan.launchWaitSeconds -lt 5 -or $Plan.launchWaitSeconds -gt 300) { throw 'PLAN_VALUE_INVALID' }
}
function Set-CrStage($State,[string]$Root,[string]$Stage) {
    $State.stage=$Stage; $State.updatedAt=Get-CrUtc
    Write-CrJson $State (Join-Path $Root 'result.json')
}
function Connect-CrScheduler {
    $service=New-Object -ComObject Schedule.Service
    $service.Connect()
    $service
}
function Test-CrTask($Definition,$Plan,[string]$Arguments) {
    try {
        $user=[string]$Definition.Principal.UserId
        $sid=if($user -match '^S-1-'){[Security.Principal.SecurityIdentifier]::new($user).Value}else{
            [Security.Principal.NTAccount]::new($user).Translate([Security.Principal.SecurityIdentifier]).Value
        }
    } catch { return $false }
    $sid -ceq $Plan.sid -and $Definition.Principal.LogonType -eq 3 -and
    $Definition.Principal.RunLevel -eq 0 -and $Definition.Actions.Count -eq 1 -and
    $Definition.Actions.Item(1).Path -ceq $Plan.powershell -and
    $Definition.Actions.Item(1).Arguments -ceq $Arguments -and
    $Definition.Actions.Item(1).WorkingDirectory -ceq $Plan.root -and $Definition.Triggers.Count -eq 0 -and
    $Definition.Settings.ExecutionTimeLimit -ceq 'PT0S' -and -not $Definition.Settings.AllowHardTerminate
}
function Get-CrWorkerArguments($Plan,[string]$PlanHash) {
    Join-CrArguments @('-NoProfile','-NonInteractive','-File',$Plan.worker.path,'-OperationRoot',$Plan.root,'-PlanSha256',$PlanHash)
}
function Remove-CrTask($Plan,[string]$PlanHash) {
    if($Plan.operationId -cnotmatch '^[0-9a-f-]{36}$' -or $Plan.taskName -cne ('CodexRestart-'+$Plan.operationId) -or
       $Plan.sid -cne (Get-CrContext).sid){throw 'SCHEDULER_OWNER_MISMATCH'}
    $service=Connect-CrScheduler; $folder=$service.GetFolder('\')
    try { $task=$folder.GetTask($Plan.taskName) }
    catch { if ($_.Exception.HResult -eq -2147024894) { return 'already_absent' }; throw }
    if (-not (Test-CrTask $task.Definition $Plan (Get-CrWorkerArguments $Plan $PlanHash))) { throw 'SCHEDULER_BINDING_CHANGED' }
    $folder.DeleteTask($Plan.taskName,0)
    'deleted'
}
function New-CrOperation([int]$DesktopPid,[string]$LaunchScript,[string[]]$LaunchArguments,[string]$Root,
                         [int]$ExitWaitSeconds=180,[int]$LaunchWaitSeconds=90) {
    $context=Get-CrContext
    $null=Assert-CrPath $Root -New -Directory
    $null=Assert-CrPath $LaunchScript
    if ([IO.Path]::GetExtension($LaunchScript) -ine '.ps1') { throw 'POWERSHELL_LAUNCHER_REQUIRED' }
    $null=Join-CrArguments $LaunchArguments
    $desktop=Read-CrProcess $DesktopPid
    if (-not $desktop -or $desktop.sid -cne $context.sid -or $desktop.sessionId -ne $context.sessionId -or $desktop.childRole) { throw 'DESKTOP_IDENTITY_INVALID' }
    $null=Assert-CrPath $desktop.path
    $id=[guid]::NewGuid().ToString()
    $worker=Join-Path $PSScriptRoot 'Restart.Worker.ps1'; $core=Join-Path $PSScriptRoot 'Restart.Core.ps1'
    $plan=[pscustomobject][ordered]@{schema=1;operationId=$id;root=$Root;createdAt=Get-CrUtc
        sid=$context.sid;sessionId=$context.sessionId;desktop=$desktop
        taskName='CodexRestart-'+$id;powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        worker=@{path=$worker;sha256=Get-CrHash $worker};core=@{path=$core;sha256=Get-CrHash $core}
        launcher=@{path=$LaunchScript;sha256=Get-CrHash $LaunchScript};arguments=@($LaunchArguments)
        image=@{path=$desktop.path;sha256=Get-CrHash $desktop.path};exitWaitSeconds=$ExitWaitSeconds;launchWaitSeconds=$LaunchWaitSeconds}
    Assert-CrInputs $plan $Root
    $roots=@(Get-CrRoots $plan)
    if ($roots.Count -ne 1 -or -not (Test-CrIdentity $desktop $roots[0])) { throw 'COMPETING_DESKTOP_OR_IDENTITY_CHANGE' }
    [IO.Directory]::CreateDirectory($Root) | Out-Null
    Write-CrJson $plan (Join-Path $Root 'plan.json') -New
    $state=[pscustomobject][ordered]@{schema=1;operationId=$id;stage='PREPARED';updatedAt=Get-CrUtc;dispatchCount=0
        helper=$null;oldExitCode=$null;dispatchAt=$null;launcher=$null;launcherExitCode=$null;newDesktop=$null
        errorCode=$null;cleanup='not_attempted'}
    Write-CrJson $state (Join-Path $Root 'result.json') -New
    $planHash=Get-CrHash (Join-Path $Root 'plan.json')
    $arguments=Get-CrWorkerArguments $plan $planHash
    $registered=$false; $runAttempted=$false
    try {
        $service=Connect-CrScheduler; $folder=$service.GetFolder('\'); $task=$service.NewTask(0)
        $task.RegistrationInfo.Description='One user-armed Codex restart; no recurring trigger.'
        $task.Principal.UserId=$context.sid; $task.Principal.LogonType=3; $task.Principal.RunLevel=0
        $task.Settings.Enabled=$true; $task.Settings.AllowDemandStart=$true; $task.Settings.Hidden=$true
        $task.Settings.DisallowStartIfOnBatteries=$false; $task.Settings.StopIfGoingOnBatteries=$false
        $task.Settings.MultipleInstances=2; $task.Settings.ExecutionTimeLimit='PT0S'; $task.Settings.AllowHardTerminate=$false
        $a=$task.Actions.Create(0); $a.Path=$plan.powershell; $a.Arguments=$arguments; $a.WorkingDirectory=$Root
        # TASK_CREATE only: never update or replace an existing registration.
        $bound=$folder.RegisterTaskDefinition($plan.taskName,$task,2,$context.sid,$null,3); $registered=$true
        if (-not (Test-CrTask $bound.Definition $plan $arguments)) { throw 'SCHEDULER_REGISTRATION_MISMATCH' }
        $runAttempted=$true; $null=$bound.Run($null)
        $deadline=[DateTime]::UtcNow.AddSeconds(25)
        do {
            Start-Sleep -Milliseconds 250
            $state=Read-CrJson (Join-Path $Root 'result.json')
            if ($state.stage -ne 'PREPARED') { break }
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($state.stage -ne 'WAITING_FOR_EXIT') { throw 'HELPER_NOT_READY_DO_NOT_QUIT' }
        if (-not (Test-CrIdentity $state.helper (Read-CrProcess $state.helper.pid))) { throw 'HELPER_IDENTITY_UNCONFIRMED' }
        $state
    } catch {
        # A delayed helper must see cancellation before it may dispatch.
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'cancel'))) {
            $f=[IO.File]::Open((Join-Path $Root 'cancel'),[IO.FileMode]::CreateNew); $f.Dispose()
        }
        $cleanup='not_registered'
        if ($registered) { try { $cleanup=Remove-CrTask $plan $planHash } catch { $cleanup='cleanup_required' } }
        $errorCode=if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]+$'){$_.Exception.Message}else{'ARM_OPERATION_ERROR'}
        Write-CrJson @{stage='ARM_FAILED_CANCELLATION_REQUESTED';errorCode=$errorCode;at=Get-CrUtc;runAttempted=$runAttempted;cleanup=$cleanup} (Join-Path $Root 'arm-error.json') -New
        if (-not $runAttempted) {
            $state.errorCode=$errorCode; $state.cleanup=$cleanup; Set-CrStage $state $Root 'ARM_FAILED'
        }
        throw
    }
}
function Invoke-CrWorker([string]$Root,[string]$PlanSha256) {
    $null=Assert-CrPath $Root -Directory
    $planPath=Join-Path $Root 'plan.json'
    if ($PlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-CrHash $planPath) -cne $PlanSha256) { throw 'PLAN_HASH_MISMATCH' }
    $plan=Read-CrJson $planPath
    Assert-CrInputs $plan $Root
    # Claim remains after completion/crash: re-running an operation never retries it.
    $claim=[IO.File]::Open((Join-Path $Root 'claim'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $old=$null; $launch=$null; $exitCode=2
    $state=Read-CrJson (Join-Path $Root 'result.json')
    try {
        if ($state.operationId -cne $plan.operationId -or $state.stage -cne 'PREPARED') { throw 'OPERATION_ALREADY_STARTED' }
        $state.helper=Read-CrProcess $PID
        if (-not $state.helper -or $state.helper.sid -cne $plan.sid -or $state.helper.sessionId -ne $plan.sessionId) { throw 'HELPER_IDENTITY_INVALID' }
        if (-not (Test-CrIdentity $plan.desktop (Read-CrProcess $plan.desktop.pid))) { throw 'DESKTOP_CHANGED_BEFORE_WAIT' }
        $old=[Diagnostics.Process]::GetProcessById($plan.desktop.pid); $null=$old.Handle
        if ($old.HasExited -or ([DateTimeOffset]$old.StartTime).ToUnixTimeMilliseconds() -ne ([DateTimeOffset]$plan.desktop.createdAt).ToUnixTimeMilliseconds() -or
            -not (Test-CrIdentity $plan.desktop (Read-CrProcess $plan.desktop.pid))) { throw 'DESKTOP_CHANGED_AT_HANDLE' }
        if (Test-Path -LiteralPath (Join-Path $Root 'cancel')) { Set-CrStage $state $Root 'CANCELLED'; return 2 }
        Set-CrStage $state $Root 'WAITING_FOR_EXIT'
        $until=[DateTime]::UtcNow.AddSeconds($plan.exitWaitSeconds)
        while (-not $old.WaitForExit(200)) {
            if (Test-Path -LiteralPath (Join-Path $Root 'cancel')) { Set-CrStage $state $Root 'CANCELLED'; return 2 }
            if ([DateTime]::UtcNow -ge $until) { Set-CrStage $state $Root 'EXIT_TIMEOUT'; return 2 }
            try { $observed=Read-CrProcess $plan.desktop.pid }
            catch { if($old.WaitForExit(0)){break}; throw }
            # The process can exit between WaitForExit and the CIM read. Its retained
            # handle distinguishes that normal observation race from PID replacement.
            if($old.WaitForExit(0)){break}
            if (-not (Test-CrIdentity $plan.desktop $observed)) { throw 'DESKTOP_IDENTITY_CHANGED_WHILE_WAITING' }
        }
        $state.oldExitCode=$old.ExitCode
        if ($state.oldExitCode -ne 0) { throw 'DESKTOP_NONZERO_EXIT' }
        # Exit zero is recorded, never labelled proof of normal Quit or DB cleanup.
        Set-CrStage $state $Root 'EXIT_OBSERVED'
        Assert-CrInputs $plan $Root
        if ((Get-CrHash $planPath) -cne $PlanSha256) { throw 'PLAN_CHANGED_BEFORE_DISPATCH' }
        if (@(Get-CrRoots $plan).Count -ne 0) { throw 'COMPETING_DESKTOP_BEFORE_DISPATCH' }
        if (Test-Path -LiteralPath (Join-Path $Root 'cancel')) { Set-CrStage $state $Root 'CANCELLED'; return 2 }
        $state.dispatchAt=Get-CrUtc; $state.dispatchCount=1
        Set-CrStage $state $Root 'DISPATCH_INTENT'
        $args=Join-CrArguments (@('-NoProfile','-NonInteractive','-File',$plan.launcher.path)+@($plan.arguments))
        $launch=Start-Process -FilePath $plan.powershell -ArgumentList $args -WorkingDirectory (Split-Path -Parent $plan.launcher.path) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $null=$launch.Handle
        $state.launcher=[pscustomobject]@{pid=$launch.Id;createdAt=([DateTimeOffset]$launch.StartTime).ToString('o')}
        Set-CrStage $state $Root 'LAUNCH_DISPATCHED'
        $until=[DateTime]::UtcNow.AddSeconds($plan.launchWaitSeconds); $previous=$null
        do {
            Start-Sleep -Milliseconds 500
            $roots=@(Get-CrRoots $plan)
            if ($roots.Count -gt 1) { throw 'AMBIGUOUS_NEW_DESKTOP' }
            if ($launch.HasExited) {
                $state.launcherExitCode=$launch.ExitCode
                if ($launch.ExitCode -ne 0) { throw 'LAUNCHER_NONZERO_EXIT' }
                if ($roots.Count -eq 1) {
                    $candidate=$roots[0]
                    if ($candidate.path -cne $plan.image.path -or [DateTimeOffset]$candidate.createdAt -lt [DateTimeOffset]$state.dispatchAt -or
                        $candidate.pid -eq $plan.desktop.pid -or (Get-CrHash $candidate.path) -cne $plan.image.sha256) { throw 'NEW_DESKTOP_IDENTITY_MISMATCH' }
                    if (Test-CrIdentity $previous $candidate) {
                        $state.newDesktop=$candidate; Set-CrStage $state $Root 'RELAUNCH_OBSERVED'; $exitCode=0; return 0
                    }
                    $previous=$candidate
                } else { $previous=$null }
            }
        } while ([DateTime]::UtcNow -lt $until)
        throw 'LAUNCH_OBSERVATION_TIMEOUT'
    } catch {
        $code=[string]$_.Exception.Message
        $state.errorCode=if($code -cmatch '^[A-Z][A-Z0-9_]+$'){$code}else{'OPERATION_ERROR'}
        $stage=if($state.dispatchCount -gt 0){'LAUNCH_UNCONFIRMED'}else{'HOLD'}
        Set-CrStage $state $Root $stage
        return 2
    } finally {
        if ($old) { $old.Dispose() }; if ($launch) { $launch.Dispose() }; $claim.Dispose()
        try { $state.cleanup=Remove-CrTask $plan $PlanSha256 }
        catch { $state.cleanup='cleanup_required' }
        Write-CrJson $state (Join-Path $Root 'result.json')
    }
}
