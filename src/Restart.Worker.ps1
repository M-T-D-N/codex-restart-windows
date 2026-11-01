# SPDX-License-Identifier: MIT
param([Parameter(Mandatory)][string]$OperationRoot,[Parameter(Mandatory)][string]$PlanSha256)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Restart.Core.ps1')
    $code=Invoke-CrWorker $OperationRoot $PlanSha256
    exit $code
} catch {
    # Do not overwrite the winner's result if a consumed claim rejected this invocation.
    try {
        $null=Assert-CrPath $OperationRoot -Directory
        if(-not (Test-Path -LiteralPath (Join-Path $OperationRoot 'claim'))){
            Write-CrJson @{stage='WORKER_INPUT_REJECTED';errorCode='WORKER_INPUT_REJECTED';at=Get-CrUtc} (Join-Path $OperationRoot 'worker-error.json') -New
        }
    } catch {}
    Write-Error 'RESTART_WORKER_REJECTED; inspect the operation without re-running it.' -ErrorAction Continue
    exit 2
}
