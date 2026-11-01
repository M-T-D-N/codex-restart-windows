# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Arm','Status','Cancel','Cleanup')][string]$Action,
    [Parameter(Mandatory)][string]$OperationRoot,
    [int]$DesktopPid,
    [string]$LaunchScript,
    [string[]]$LaunchArguments=@(),
    [ValidateRange(5,1800)][int]$ExitWaitSeconds=180,
    [ValidateRange(5,300)][int]$LaunchWaitSeconds=90
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src\Restart.Core.ps1')
try {
    if ($Action -eq 'Arm') {
        if ($DesktopPid -le 0 -or -not $LaunchScript) { throw 'DESKTOP_PID_AND_LAUNCH_SCRIPT_REQUIRED' }
        New-CrOperation $DesktopPid $LaunchScript $LaunchArguments $OperationRoot $ExitWaitSeconds $LaunchWaitSeconds | ConvertTo-Json -Depth 12
        exit 0
    }
    $null=Assert-CrPath $OperationRoot -Directory
    $plan=Read-CrJson (Join-Path $OperationRoot 'plan.json')
    $state=Read-CrJson (Join-Path $OperationRoot 'result.json')
    $context=Get-CrContext
    if ($plan.root -cne $OperationRoot -or $plan.sid -cne $context.sid -or $plan.operationId -cne $state.operationId) { throw 'OPERATION_OWNER_MISMATCH' }
    if ($Action -eq 'Status') {
        foreach($kind in @('arm-error','worker-error')){
            $extra=Join-Path $OperationRoot ($kind+'.json')
            if(Test-Path -LiteralPath $extra){$state | Add-Member -NotePropertyName $kind -NotePropertyValue (Read-CrJson $extra)}
        }
        $state | ConvertTo-Json -Depth 12; exit 0
    }
    if ($Action -eq 'Cancel') {
        if ($state.dispatchCount -gt 0) { throw 'DISPATCH_ALREADY_CLAIMED_NO_ROLLBACK' }
        $path=Join-Path $OperationRoot 'cancel'
        if (-not (Test-Path -LiteralPath $path)) { $f=[IO.File]::Open($path,[IO.FileMode]::CreateNew); $f.Dispose() }
        Write-Output 'Cancellation requested. Read Status for acknowledgement; no process is terminated.'
        exit 0
    }
    if ($state.helper -and (Read-CrProcess $state.helper.pid)) { throw 'HELPER_STILL_PRESENT' }
    $state.cleanup=Remove-CrTask $plan (Get-CrHash (Join-Path $OperationRoot 'plan.json'))
    Write-CrJson $state (Join-Path $OperationRoot 'result.json')
    $state | ConvertTo-Json -Depth 12
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
