# SPDX-License-Identifier: MIT
param([Parameter(Mandatory)][string]$ScratchRoot)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Restart.Core.ps1')
$null=Assert-CrPath $ScratchRoot -Directory
$root=Join-Path $ScratchRoot ('unit-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$env:TEMP=$root; $env:TMP=$root; $env:TMPDIR=$root
$script:passed=0; $script:failed=0
function Check([string]$Name,[scriptblock]$Test) {
    try { & $Test; $script:passed++; Write-Output "PASS $Name" }
    catch { $script:failed++; Write-Output "FAIL $Name : $($_.Exception.Message)" }
}
function Assert($Condition,[string]$Why='assertion failed') { if(-not $Condition){throw $Why} }
function Throws([scriptblock]$Test,[string]$Match) {
    try { & $Test; throw 'EXPECTED_EXCEPTION_MISSING' }
    catch { if($_.Exception.Message -notmatch $Match){throw} }
}
function Throws-FileCollision([scriptblock]$Test) {
    try { & $Test; throw 'EXPECTED_FILE_COLLISION_MISSING' }
    catch {
        $e=$_.Exception
        while($e.InnerException){$e=$e.InnerException}
        if($e -isnot [IO.IOException] -or ($e.HResult -band 65535) -notin @(32,80,183)){throw}
    }
}
$base=[pscustomobject]@{pid=17;parentPid=11;path='C:\Fixture\ChatGPT.exe';createdAt='2026-01-01T00:00:00.0000000Z';commandHash=('a'*64);sid='S-1-5-21-1';sessionId=1;childRole=$false}
Check 'exact identity is accepted' { Assert (Test-CrIdentity $base $base) }
foreach($field in @('pid','parentPid','path','createdAt','commandHash','sid','sessionId','childRole')) {
    $fieldCopy=$field
    Check "changed identity field $field is rejected" {
        $other=$base.PSObject.Copy(); $other.$fieldCopy='different'
        Assert (-not (Test-CrIdentity $base $other))
    }
}
Check 'missing identity is rejected' { Assert (-not (Test-CrIdentity $base $null)) }
Check 'missing identity key is rejected' {
    $other=$base.PSObject.Copy(); $other.PSObject.Properties.Remove('commandHash')
    Assert (-not (Test-CrIdentity $base $other))
}
Check 'new JSON is valid UTF8' {
    Write-CrJson @{stage='FIRST';text='Unicode example'} (Join-Path $root 'state.json') -New
    Assert ((Read-CrJson (Join-Path $root 'state.json')).stage -ceq 'FIRST')
}
Check 'initial JSON collision preserves original' {
    Throws-FileCollision {Write-CrJson @{stage='WRONG'} (Join-Path $root 'state.json') -New}
    Assert ((Read-CrJson (Join-Path $root 'state.json')).stage -ceq 'FIRST')
}
Check 'PS5 atomic existing JSON update succeeds' {
    Write-CrJson @{stage='SECOND'} (Join-Path $root 'state.json')
    Assert ((Read-CrJson (Join-Path $root 'state.json')).stage -ceq 'SECOND')
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count -eq 0)
}
Check 'relative path rejected' { Throws {Assert-CrPath 'relative\file'} 'LOCAL_ABSOLUTE_PATH_REQUIRED' }
Check 'UNC path rejected' { Throws {Assert-CrPath '\\server\share\file'} 'LOCAL_ABSOLUTE_PATH_REQUIRED' }
Check 'alternate stream rejected' { Throws {Assert-CrPath 'C:\Fixture\file:stream'} 'LOCAL_ABSOLUTE_PATH_REQUIRED' }
Check 'dot traversal rejected before IO' { Throws {Assert-CrPath 'C:\Fixture\..\Other'} 'CANONICAL_PATH_REQUIRED' }
Check 'existing new destination rejected' { Throws {Assert-CrPath $root -New -Directory} 'NEW_PATH_ALREADY_EXISTS' }
Check 'quoted executable arguments remain literal' { Assert ((Join-CrArguments @('a b','x"y','trail\','')) -ceq '"a b" "x\"y" "trail\\" ""') }
Check 'argument line break rejected' { Throws {Join-CrArguments @("first`nsecond")} 'ARGUMENT_CONTROL_CHARACTER' }
Check 'arguments round trip through the real Windows PowerShell launcher' {
    $probe=Join-Path $root 'arguments.ps1'; $output=Join-Path $root 'arguments.json'
    [IO.File]::WriteAllText($probe,'[IO.File]::WriteAllText($args[0], (ConvertTo-Json -InputObject @($args[1..($args.Length-1)])), [Text.UTF8Encoding]::new($false))')
    $expected=@('a b','x"y','trail\','literal $() ; &',('unicode-'+[char]0xD55C))
    $command=Join-CrArguments (@('-NoProfile','-NonInteractive','-File',$probe,$output)+$expected)
    $child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $command -WindowStyle Hidden -PassThru
    try {
        $null=$child.Handle
        Assert ($child.WaitForExit(10000)) 'argument child timeout'
        Assert ($child.ExitCode -eq 0) 'argument child failed'
        $actual=Read-CrJson $output
        Assert ($actual.Count -eq $expected.Count) 'argument count changed'
        for($i=0;$i -lt $expected.Count;$i++){Assert ($actual[$i] -ceq $expected[$i]) "argument $i changed"}
    } finally {$child.Dispose()}
}
Check 'Task Scheduler binding accepts the intended definition and rejects mutations' {
    $service=Connect-CrScheduler; $definition=$service.NewTask(0)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $plan=[pscustomobject]@{sid=$sid;powershell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';root=$root}
    $definition.Principal.UserId=$sid;$definition.Principal.LogonType=3;$definition.Principal.RunLevel=0
    $definition.Settings.ExecutionTimeLimit='PT0S';$definition.Settings.AllowHardTerminate=$false
    $action=$definition.Actions.Create(0);$action.Path=$plan.powershell;$action.Arguments='fixed';$action.WorkingDirectory=$root
    Assert (Test-CrTask $definition $plan 'fixed')
    $action.Arguments='changed';Assert (-not (Test-CrTask $definition $plan 'fixed'));$action.Arguments='fixed'
    $action.Path='C:\Wrong\powershell.exe';Assert (-not (Test-CrTask $definition $plan 'fixed'));$action.Path=$plan.powershell
    $definition.Principal.RunLevel=1;Assert (-not (Test-CrTask $definition $plan 'fixed'));$definition.Principal.RunLevel=0
    $definition.Settings.AllowHardTerminate=$true;Assert (-not (Test-CrTask $definition $plan 'fixed'));$definition.Settings.AllowHardTerminate=$false
    $definition.Settings.ExecutionTimeLimit='PT1M';Assert (-not (Test-CrTask $definition $plan 'fixed'));$definition.Settings.ExecutionTimeLimit='PT0S'
    $null=$definition.Triggers.Create(7);Assert (-not (Test-CrTask $definition $plan 'fixed'))
}
Check 'changed plan is rejected before creating a claim' {
    $op=Join-Path $root 'bad-plan';[IO.Directory]::CreateDirectory($op)|Out-Null
    Write-CrJson @{schema=1} (Join-Path $op 'plan.json') -New
    Throws {Invoke-CrWorker $op ('0'*64)} 'PLAN_HASH_MISMATCH'
    Assert (-not (Test-Path -LiteralPath (Join-Path $op 'claim')))
}
Check 'persistent claim rejects a second invocation even after close' {
    $p=Join-Path $root 'claim'; $claim=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { Throws-FileCollision {[IO.File]::Open($p,[IO.FileMode]::CreateNew)} } finally {$claim.Dispose()}
    Throws-FileCollision {[IO.File]::Open($p,[IO.FileMode]::CreateNew)}
}
Check 'all scripts parse' {
    foreach($f in Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -Filter '*.ps1' -Recurse) {
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
        Assert (-not $errors) $f.Name
    }
}
$summary=@{suite='synthetic-unit';host=$PSVersionTable.PSVersion.ToString();passed=$script:passed;failed=$script:failed;skipped=0}
$summary | ConvertTo-Json -Compress
if($script:failed -eq 0) {
    # Only this invocation's generated fixtures; no recursion into links.
    if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($ScratchRoot).TrimEnd('\')+'\') -and
       -not ((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
    exit 0
}
Write-Output "Failed fixtures retained: $root"
exit 1
