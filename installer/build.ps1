# Builds the Windows installer with the C# compiler that ships with Windows
# (.NET Framework 4.x): no SDK to install, and the exe runs as is on Windows 10
# and 11.
#
#   .\installer\build.ps1                      -> installer\out\CtrlZInstaller.exe
#   .\installer\build.ps1 -Version v0.1.0
#   .\installer\build.ps1 -NoElevation         -> test build, without the elevation prompt

param(
    [string]$Version = 'dev',
    [switch]$NoElevation
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out  = Join-Path $here 'out'
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "Compiler not found: $csc" }

New-Item -ItemType Directory -Force -Path $out | Out-Null
$safe = $Version -replace '[^A-Za-z0-9._-]', ''
$info = Join-Path $out 'BuildInfo.cs'
"namespace CtrlZ { static class BuildInfo { public const string Version = `"$safe`"; } }" |
    Set-Content -Path $info -Encoding UTF8

$name = if ($NoElevation) { 'CtrlZInstaller-test.exe' } else { 'CtrlZInstaller.exe' }
$exe  = Join-Path $out $name
$cscArgs = @(
    '/nologo', '/target:winexe', '/optimize+', '/codepage:65001', '/platform:anycpu',
    "/out:$exe",
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll', '/r:System.Web.Extensions.dll'
)
$cscArgs += "/win32icon:$(Join-Path $here 'app.ico')"
if ($NoElevation) { $cscArgs += '/nowin32manifest' } else { $cscArgs += "/win32manifest:$(Join-Path $here 'app.manifest')" }
$cscArgs += (Get-ChildItem (Join-Path $here 'src') -Filter *.cs | ForEach-Object { $_.FullName })
$cscArgs += $info

& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)." }
Write-Host "OK : $exe"
