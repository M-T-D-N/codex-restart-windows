# SPDX-License-Identifier: MIT
# Read-only publication checks. No network access, packaging or application start.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$allow=@(Get-Content -LiteralPath (Join-Path $root 'publication-files.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$allow=@($allow | ForEach-Object { $_ })
if(@($allow | Select-Object -Unique).Count -ne $allow.Count){throw 'DUPLICATE_ALLOWLIST_PATH'}
if(Test-Path -LiteralPath (Join-Path $root '.git')){
    Push-Location $root
    try{$actual=@(git ls-files --cached --others --exclude-standard);if($LASTEXITCODE -ne 0){throw 'GIT_LIST_FAILED'}}finally{Pop-Location}
}else{
    $actual=@(Get-ChildItem -LiteralPath $root -File -Force -Recurse | ForEach-Object {$_.FullName.Substring($root.Length+1).Replace('\','/')})
}
$difference=@(Compare-Object ($allow | Sort-Object) ($actual | Sort-Object))
if($difference){$difference | Format-Table | Out-String | Write-Output;throw 'PUBLICATION_FILE_SET_MISMATCH'}
$links=0; $blocks=0
foreach($relative in $allow){
    if($relative -match '(^/|\.\.|\\|\.(exe|dll|db|sqlite|sqlite3|jsonl|zip)$)'){throw "FORBIDDEN_PACKAGE_PATH $relative"}
    $file=Join-Path $root $relative
    $content=Get-Content -LiteralPath $file -Raw -Encoding UTF8
    foreach($pattern in @('(?i)C:[\\/]Users[\\/](?!Public[\\/])[^\\/\s]+','gh[pousr]_[A-Za-z0-9]{20,}','sk-[A-Za-z0-9]{20,}','-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----')){
        if($content -match $pattern){throw "SENSITIVE_SIGNATURE $relative"}
    }
    if($relative.EndsWith('.md')){
        foreach($match in [regex]::Matches($content,'\[[^\]]*\]\(([^)]+)\)')){
            $target=$match.Groups[1].Value.Split('#')[0]
            if(-not $target -or $target -match '^https://'){continue}
            if($target -match '^[a-zA-Z]+:'){throw "UNSUPPORTED_DOC_LINK $relative"}
            if(-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $file) $target))){throw "BROKEN_DOC_LINK $relative -> $target"}
            $links++
        }
        foreach($match in [regex]::Matches($content,'(?s)```powershell\r?\n(.*?)```')){
            $tokens=$null;$errors=$null
            [void][Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value,[ref]$tokens,[ref]$errors)
            if($errors){throw "INVALID_DOC_COMMAND_SYNTAX $relative"};$blocks++
        }
    }
}
@{suite='publication-source';files=$allow.Count;localLinks=$links;powershellBlocks=$blocks;result='PASS';scope='allowlist, selected signatures, local link targets, command syntax; no GUI acceptance'} | ConvertTo-Json -Compress
