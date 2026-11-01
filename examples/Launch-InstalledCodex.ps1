# SPDX-License-Identifier: MIT
# Launch the single registered OpenAI.Codex package for the current user.
$ErrorActionPreference='Stop'
$packages=@(Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop)
if($packages.Count -ne 1){throw 'Exactly one registered OpenAI.Codex package is required.'}
$manifest=Get-AppxPackageManifest -Package $packages[0].PackageFullName -ErrorAction Stop
$apps=@($manifest.Package.Applications.Application | Where-Object { $_.Id -ceq 'App' })
if($apps.Count -ne 1){throw 'The registered Codex App entry was not found.'}
$shell=New-Object -ComObject Shell.Application
$shell.ShellExecute('shell:AppsFolder\'+$packages[0].PackageFamilyName+'!'+$apps[0].Id,'','','open',1)
# Activation returning does not prove startup. The restart worker observes the process.
