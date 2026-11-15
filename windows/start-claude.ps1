# Claude Recovery - Windows mode
#
# Diagnoses a software or browser problem on Windows, then cleans up completely.
#
# Run from the key, in PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\windows\start-claude.ps1 [-Lang fr|en]
#
# What the script does:
#   1. creates a temporary session folder (Claude's config, credentials and work)
#   2. finds Claude Code: windows\bin\claude.exe on the key, else the one on the PC,
#      else a temporary install with the official installer
#   3. starts the session, following the procedure of the key's edition and language
#      (windows\edition.txt and windows\lang.txt, written by the key on first boot)
#   4. on exit, whatever happens: signs out, copies the report to the key, removes the
#      session folder and everything the install added
#
# Nothing the PC already had (its own Claude Code, for instance) is touched.

param(
    [string]$Technician,
    [string]$Job,
    [ValidateSet('', 'fr', 'en')][string]$Lang = ''
)

$ErrorActionPreference = 'Stop'
$KeyRoot = Split-Path -Parent $PSScriptRoot

function Read-KeyFile([string]$name, [string[]]$allowed, [string]$default) {
    $file = Join-Path $PSScriptRoot $name
    if (Test-Path $file) {
        $value = (Get-Content $file -TotalCount 1).Trim()
        if ($allowed -contains $value) { return $value }
    }
    return $default
}

# Language: -Lang, else the key's language, else the language of this Windows.
if (-not $Lang) {
    $system = 'en'
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'fr') { $system = 'fr' }
    $Lang = Read-KeyFile 'lang.txt' @('fr', 'en') $system
}
function T([string]$fr, [string]$en) { if ($Lang -eq 'fr') { return $fr } else { return $en } }

$Edition = Read-KeyFile 'edition.txt' @('entreprise', 'particulier') 'entreprise'

Write-Host ''
Write-Host (T '=== Claude Recovery - mode Windows ===' '=== Claude Recovery - Windows mode ===') -ForegroundColor Cyan
if ($Edition -eq 'entreprise') { Write-Host (T 'Edition : entreprise' 'Edition: business') }
else { Write-Host (T 'Edition : particulier' 'Edition: personal') }

if ($Edition -eq 'entreprise') {
    if (-not $Technician) { $Technician = Read-Host (T 'Technicien' 'Technician') }
    if (-not $Technician) { Write-Host (T 'Nom du technicien obligatoire.' "The technician's name is required."); exit 1 }
    if (-not $Job) { $Job = Read-Host (T 'Reference du job (ex. dupont-pc)' 'Job reference (e.g. smith-pc)') }
} else {
    $Technician = 'personal'
    if (-not $Job) { $Job = 'diagnostic' }
}
$Job = ($Job -replace '[^A-Za-z0-9._-]', '-').Trim('-')
if (-not $Job) { Write-Host (T 'Reference obligatoire.' 'A reference is required.'); exit 1 }
$Job = '{0}_{1}' -f (Get-Date -Format 'yyyy-MM-dd'), $Job

# --- Folders ----------------------------------------------------------------
$Session   = Join-Path $env:TEMP ('claude-recovery-' + [guid]::NewGuid().ToString('N'))
$ConfigDir = Join-Path $Session 'config'
$WorkDir   = Join-Path $Session 'work'
$Journal   = Join-Path $PSScriptRoot 'journal'
New-Item -ItemType Directory -Force -Path $ConfigDir, $WorkDir, $Journal | Out-Null

# --- State of the PC before we touch it (so we only remove what we add) ------
$UserHome   = $env:USERPROFILE
$ExePath    = Join-Path $UserHome '.local\bin\claude.exe'
$SharePath  = Join-Path $UserHome '.local\share\claude'
$LocalDir   = Join-Path $UserHome '.local'
$DotClaude  = Join-Path $UserHome '.claude'
$DotJson    = Join-Path $UserHome '.claude.json'
$Before = @{
    Exe       = Test-Path $ExePath
    Share     = Test-Path $SharePath
    LocalDir  = Test-Path $LocalDir
    DotClaude = Test-Path $DotClaude
    DotJson   = Test-Path $DotJson
    UserPath  = [Environment]::GetEnvironmentVariable('Path', 'User')
}
$Installed = $false
$Claude = $null

try {
    # --- Find Claude Code ----------------------------------------------------
    $Portable = Join-Path $PSScriptRoot 'bin\claude.exe'
    $Existing = Get-Command claude -ErrorAction SilentlyContinue
    if (Test-Path $Portable) {
        $Claude = $Portable
        Write-Host (T 'Claude Code : binaire de la cle.' 'Claude Code: binary from the key.')
    } elseif ($Existing) {
        $Claude = $Existing.Source
        Write-Host (T 'Claude Code : deja present sur ce PC (il ne sera pas desinstalle).' 'Claude Code: already on this PC (it will not be uninstalled).')
    } else {
        Write-Host (T 'Claude Code : installation temporaire...' 'Claude Code: temporary install...')
        $Installed = $true
        Invoke-Expression (Invoke-RestMethod -Uri 'https://claude.ai/install.ps1')
        if (-not (Test-Path $ExePath)) { throw (T "Installation echouee : $ExePath introuvable." "Install failed: $ExePath not found.") }
        $Claude = $ExePath
    }

    # --- Windows-mode config, isolated in the session folder -----------------
    Copy-Item (Join-Path $KeyRoot "config\windows\CLAUDE.$Edition.$Lang.md") (Join-Path $ConfigDir 'CLAUDE.md')
    $HookPath = (Join-Path $PSScriptRoot 'log-command.ps1') -replace '\\', '\\'
    $Settings = (Get-Content (Join-Path $KeyRoot 'config\windows\settings.json') -Raw).Replace('__HOOK_PATH__', $HookPath)
    [System.IO.File]::WriteAllText((Join-Path $ConfigDir 'settings.json'), $Settings, (New-Object System.Text.UTF8Encoding($false)))

    $env:CLAUDE_CONFIG_DIR   = $ConfigDir
    $env:DISABLE_AUTOUPDATER = '1'
    $env:RECOVERY_TECH    = $Technician
    $env:RECOVERY_JOB     = $Job
    $env:RECOVERY_JOURNAL = Join-Path $Journal ($Job + '.jsonl')

    Write-Host ''
    Write-Host "Job : $Job"
    if ($Edition -eq 'entreprise') {
        Write-Host ((T 'Technicien : ' 'Technician: ') + $Technician)
        Write-Host (T 'Connectez-vous au compte Claude de votre entreprise quand Claude le demande.' "Sign in to your company's Claude account when Claude asks.")
    } else {
        Write-Host (T 'Connectez-vous a votre compte Claude quand Claude le demande.' 'Sign in to your Claude account when Claude asks.')
        Write-Host (T 'A la fermeture, tout ce que cette session a ajoute au PC sera supprime.' 'On exit, everything this session added to the PC is removed.')
    }
    Write-Host ''

    Push-Location $WorkDir
    try { & $Claude } finally { Pop-Location }
}
finally {
    Write-Host ''
    Write-Host (T '=== Nettoyage ===' '=== Cleanup ===') -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'
    $Problems = @()

    # 1. Sign out (invalidates the session, not just the local file)
    if ($Claude -and (Test-Path $Claude) -and $env:CLAUDE_CONFIG_DIR) {
        try { & $Claude auth logout 2>&1 | Out-Null } catch { }
    }

    # 2. Report copied to the key
    $Report = Join-Path $WorkDir 'report.md'
    if (Test-Path $Report) {
        Copy-Item $Report (Join-Path $Journal ($Job + '_report.md')) -Force
        Write-Host (T 'Rapport copie sur la cle.' 'Report copied to the key.')
    }

    # 3. Session folder (config, credentials, history, work)
    Remove-Item -Path $Session -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $Session) { $Problems += $Session }

    # 4. What the temporary install added, and only that
    if ($Installed) {
        if (-not $Before.Exe)       { Remove-Item $ExePath   -Force          -ErrorAction SilentlyContinue }
        if (-not $Before.Share)     { Remove-Item $SharePath -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not $Before.DotClaude) { Remove-Item $DotClaude -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not $Before.DotJson)   { Remove-Item $DotJson   -Force          -ErrorAction SilentlyContinue }
        if (-not $Before.LocalDir)  { Remove-Item $LocalDir  -Recurse -Force -ErrorAction SilentlyContinue }
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $Before.UserPath) {
            [Environment]::SetEnvironmentVariable('Path', $Before.UserPath, 'User')
        }
        foreach ($item in @(
            @{ Path = $ExePath;   Was = $Before.Exe },
            @{ Path = $SharePath; Was = $Before.Share },
            @{ Path = $DotClaude; Was = $Before.DotClaude },
            @{ Path = $DotJson;   Was = $Before.DotJson }
        )) {
            if (-not $item.Was -and (Test-Path $item.Path)) { $Problems += $item.Path }
        }
    }

    Remove-Item Env:CLAUDE_CONFIG_DIR, Env:RECOVERY_TECH, Env:RECOVERY_JOB, Env:RECOVERY_JOURNAL, Env:DISABLE_AUTOUPDATER -ErrorAction SilentlyContinue

    if ($Problems.Count -gt 0) {
        Write-Host (T 'ATTENTION : elements non supprimes, a retirer a la main :' 'WARNING: items not removed, delete them by hand:') -ForegroundColor Red
        $Problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    } else {
        Write-Host (T 'Nettoyage termine : rien ne reste sur ce PC.' 'Cleanup done: nothing is left on this PC.') -ForegroundColor Green
    }
    Write-Host ((T "Journal de l'intervention : " 'Session log: ') + $Journal)
}
