# Compile l'installeur Windows avec le compilateur C# livre avec Windows
# (.NET Framework 4.x) : aucun SDK a installer, et l'exe tourne tel quel sur
# Windows 10 et 11.
#
#   .\installer\build.ps1                      -> installer\out\ClaudeRecoveryInstaller.exe
#   .\installer\build.ps1 -Version v0.1.0
#   .\installer\build.ps1 -NoElevation         -> variante de test, sans demande de droits

param(
    [string]$Version = 'dev',
    [switch]$NoElevation
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out  = Join-Path $here 'out'
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "Compilateur introuvable : $csc" }

New-Item -ItemType Directory -Force -Path $out | Out-Null
$safe = $Version -replace '[^A-Za-z0-9._-]', ''
$info = Join-Path $out 'BuildInfo.cs'
"namespace ClaudeRecovery { static class BuildInfo { public const string Version = `"$safe`"; } }" |
    Set-Content -Path $info -Encoding UTF8

$name = if ($NoElevation) { 'ClaudeRecoveryInstaller-test.exe' } else { 'ClaudeRecoveryInstaller.exe' }
$exe  = Join-Path $out $name
$cscArgs = @(
    '/nologo', '/target:winexe', '/optimize+', '/codepage:65001', '/platform:anycpu',
    "/out:$exe",
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll'
)
if ($NoElevation) { $cscArgs += '/nowin32manifest' } else { $cscArgs += "/win32manifest:$(Join-Path $here 'app.manifest')" }
$cscArgs += (Get-ChildItem (Join-Path $here 'src') -Filter *.cs | ForEach-Object { $_.FullName })
$cscArgs += $info

& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Compilation echouee ($LASTEXITCODE)." }
Write-Host "OK : $exe"
