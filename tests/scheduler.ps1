# SPDX-License-Identifier: MIT
# Explicit integration: creates only named synthetic fixture processes and one-shot tasks.
param([Parameter(Mandatory)][string]$ScratchRoot)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'Run this integration with Windows PowerShell 5.1.'}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Restart.Core.ps1')
$null=Get-CrContext; $null=Assert-CrPath $ScratchRoot -Directory
$root=Join-Path $ScratchRoot ('scheduler-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$temp=Join-Path $root 'temp'; [IO.Directory]::CreateDirectory($temp) | Out-Null
$env:TEMP=$temp; $env:TMP=$temp; $env:TMPDIR=$temp
$exe=Join-Path $root 'CrTestFixture.exe'
$source=@'
using System;
using System.IO;
using System.Threading;
public class CrTestFixture {
    public static int Main(string[] args) {
        if(args.Length < 3) return 12;
        File.WriteAllText(args[1], "started");
        DateTime deadline=DateTime.UtcNow.AddSeconds(args[0] == "old" ? 60 : 8);
        while(DateTime.UtcNow < deadline && !File.Exists(args[2])) Thread.Sleep(100);
        return args.Length > 3 ? Int32.Parse(args[3]) : 0;
    }
}
'@
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$true; $parameters.GenerateInMemory=$false; $parameters.OutputAssembly=$exe
$parameters.TempFiles=[CodeDom.Compiler.TempFileCollection]::new($temp,$false)
try{Add-Type -TypeDefinition $source -CompilerParameters $parameters -ErrorAction Stop | Out-Null}
finally{$parameters.TempFiles.Delete()}
$results=@(); $children=@(); $operations=@()
function Wait-Terminal([string]$Operation,[int]$Seconds=25) {
    $until=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        Start-Sleep -Milliseconds 250
        $record=Read-CrJson (Join-Path $Operation 'result.json')
        if($record.stage -cin @('RELAUNCH_OBSERVED','HOLD','CANCELLED','EXIT_TIMEOUT','LAUNCH_UNCONFIRMED') -and $record.cleanup -ne 'not_attempted'){return $record}
    }while([DateTime]::UtcNow -lt $until)
    throw 'TEST_TERMINAL_TIMEOUT'
}
function Fixture-Text([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
try {
    foreach($case in @('success','cancel','wait-timeout','nonzero-exit','changed-launcher','competing-version','launcher-no-process')) {
        $caseRoot=Join-Path $root $case; [IO.Directory]::CreateDirectory($caseRoot)|Out-Null
        $oldStarted=Join-Path $caseRoot 'old-started'; $oldStop=Join-Path $caseRoot 'old-stop'
        $newStarted=Join-Path $caseRoot 'new-started'; $newStop=Join-Path $caseRoot 'new-stop'
        $dispatch=Join-Path $caseRoot 'dispatch.txt'; $launcher=Join-Path $caseRoot 'launch.ps1'
        $literalExe=$exe.Replace("'","''"); $literalDispatch=$dispatch.Replace("'","''")
        $newArgs=Join-CrArguments @('new',$newStarted,$newStop)
        $body="`$ErrorActionPreference='Stop'`n[IO.File]::AppendAllText('$literalDispatch', 'dispatch'+[Environment]::NewLine)`n"
        if($case -ne 'launcher-no-process'){$body+="Start-Process -FilePath '$literalExe' -ArgumentList '"+$newArgs.Replace("'","''")+"' -WindowStyle Hidden | Out-Null`n"}
        Fixture-Text $launcher $body
        $oldCode=if($case -eq 'nonzero-exit'){'7'}else{'0'}
        $old=Start-Process -FilePath $exe -ArgumentList (Join-CrArguments @('old',$oldStarted,$oldStop,$oldCode)) -WindowStyle Hidden -PassThru
        $null=$old.Handle; $children+=@{process=$old;stop=$oldStop}
        $until=[DateTime]::UtcNow.AddSeconds(5)
        while(-not (Test-Path -LiteralPath $oldStarted)){if([DateTime]::UtcNow -gt $until){throw 'FIXTURE_START_TIMEOUT'};Start-Sleep -Milliseconds 50}
        $raw=Get-CimInstance Win32_Process -Filter "ProcessId=$($old.Id)" -ErrorAction Stop
        Write-CrJson @{pid=$raw.ProcessId;parentPid=$raw.ParentProcessId;createdAt=$raw.CreationDate;commandLine=$raw.CommandLine;path=$raw.ExecutablePath;persistent=$false} (Join-Path $caseRoot 'owned-fixture.json') -New
        $op=Join-Path $caseRoot 'operation'; $operations+=$op
        if($case -eq 'success'){
            # The arming caller exits first. The scheduled worker must remain alive.
            $armScript=Join-Path $caseRoot 'arm-from-child.ps1'; $armResult=Join-Path $caseRoot 'arm-result.json'
            $core=Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Restart.Core.ps1'
            $armText="`$ErrorActionPreference='Stop'`n. '"+$core.Replace("'","''")+"'`n"
            $armText+="`$r=New-CrOperation $($old.Id) '"+$launcher.Replace("'","''")+"' @() '"+$op.Replace("'","''")+"' 10 8`n"
            $armText+="Write-CrJson `$r '"+$armResult.Replace("'","''")+"' -New`n"
            Fixture-Text $armScript $armText
            $armer=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList (Join-CrArguments @('-NoProfile','-File',$armScript)) -WindowStyle Hidden -PassThru
            $null=$armer.Handle
            if(-not $armer.WaitForExit(30000) -or $armer.ExitCode -ne 0){throw 'ARMING_PARENT_FAILED'}
            $armed=Read-CrJson $armResult
            if($armed.helper.parentPid -eq $armer.Id -or -not (Read-CrProcess $armed.helper.pid)){throw 'HELPER_NOT_INDEPENDENT'}
            $armer.Dispose()
        }else{$armed=New-CrOperation $old.Id $launcher @() $op 5 5}
        if($armed.stage -ne 'WAITING_FOR_EXIT'){throw 'TEST_ARM_NOT_READY'}
        if($case -eq 'cancel'){Fixture-Text (Join-Path $op 'cancel') 'cancel'}
        elseif($case -eq 'changed-launcher'){Fixture-Text $launcher ($body+"# changed after arm`n");Fixture-Text $oldStop 'stop'}
        elseif($case -eq 'competing-version'){
            $otherExe=Join-Path $caseRoot 'CrTestFixture.exe'; Copy-Item -LiteralPath $exe -Destination $otherExe
            $otherStop=Join-Path $caseRoot 'other-stop';$otherStarted=Join-Path $caseRoot 'other-started'
            $other=Start-Process -FilePath $otherExe -ArgumentList (Join-CrArguments @('new',$otherStarted,$otherStop)) -WindowStyle Hidden -PassThru
            $null=$other.Handle; $children+=@{process=$other;stop=$otherStop}
            while(-not (Test-Path -LiteralPath $otherStarted)){Start-Sleep -Milliseconds 50;if($other.HasExited){throw 'OTHER_FIXTURE_FAILED'}}
            Fixture-Text $oldStop 'stop'
        }
        elseif($case -ne 'wait-timeout'){Fixture-Text $oldStop 'stop'}
        $record=Wait-Terminal $op
        $expected=switch($case){'success'{'RELAUNCH_OBSERVED'} 'cancel'{'CANCELLED'} 'wait-timeout'{'EXIT_TIMEOUT'} 'launcher-no-process'{'LAUNCH_UNCONFIRMED'} default{'HOLD'}}
        $count=if(Test-Path -LiteralPath $dispatch){@(Get-Content -LiteralPath $dispatch).Count}else{0}
        $expectedCount=if($case -cin @('success','launcher-no-process')){1}else{0}
        if($record.stage -cne $expected -or $count -ne $expectedCount -or $record.dispatchCount -ne $expectedCount -or $record.cleanup -cne 'deleted'){
            throw "TEST_RESULT_MISMATCH $case $($record | ConvertTo-Json -Compress -Depth 6) count=$count"
        }
        if($case -eq 'success'){
            if(-not $record.newDesktop -or $record.newDesktop.pid -eq $old.Id -or $record.newDesktop.path -cne $exe){throw 'TEST_NEW_IDENTITY_MISMATCH'}
            # Consumed operation cannot dispatch again, even after its registration is gone.
            $plan=Read-CrJson (Join-Path $op 'plan.json'); $hash=Get-CrHash (Join-Path $op 'plan.json')
            $second=Start-Process -FilePath $plan.powershell -ArgumentList (Get-CrWorkerArguments $plan $hash) -WindowStyle Hidden -PassThru
            $null=$second.Handle
            if(-not $second.WaitForExit(10000)){throw 'SECOND_WORKER_TIMEOUT'}
            if($second.ExitCode -eq 0 -or @(Get-Content -LiteralPath $dispatch).Count -ne 1){throw 'DUPLICATE_DISPATCH'}
            $second.Dispose()
            Fixture-Text $newStop 'stop'
        }
        Fixture-Text $oldStop 'stop'
        if($case -eq 'competing-version'){Fixture-Text $otherStop 'stop';if(-not $other.WaitForExit(10000)){throw 'OTHER_FIXTURE_DID_NOT_EXIT'}}
        if(-not $old.WaitForExit(10000)){throw 'FIXTURE_DID_NOT_EXIT_NATURALLY'}
        $results+=@{scenario=$case;stage=$record.stage;dispatches=$count;cleanup=$record.cleanup;pass=$true}
        Write-Output "PASS scheduler $case"
        Start-Sleep -Milliseconds 350
    }
    $summary=@{suite='real-task-scheduler-synthetic-processes';host=$PSVersionTable.PSVersion.ToString();passed=$results.Count;failed=0;skipped=0;scenarios=$results;realCodexRestarted=$false}
    Write-CrJson $summary (Join-Path $root 'summary.json') -New
    $summary | ConvertTo-Json -Depth 6
    Write-Output "Evidence retained: $root"
} finally {
    # Cooperative fixture cleanup only; never Stop-Process/taskkill.
    foreach($entry in $children){try{Fixture-Text $entry.stop 'stop';$null=$entry.process.WaitForExit(10000);$entry.process.Dispose()}catch{}}
    foreach($op in $operations){
        if(Test-Path -LiteralPath (Join-Path $op 'plan.json')){
            try{
                if(-not (Test-Path -LiteralPath (Join-Path $op 'cancel'))){Fixture-Text (Join-Path $op 'cancel') 'cleanup'}
                $plan=Read-CrJson (Join-Path $op 'plan.json')
                $null=Remove-CrTask $plan (Get-CrHash (Join-Path $op 'plan.json'))
            }catch{Write-Warning 'Exact fixture scheduler cleanup requires inspection.'}
        }
    }
}
