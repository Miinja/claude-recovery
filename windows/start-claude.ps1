# Claude Recovery - mode Windows
# Diagnostic d'un bug logiciel/navigateur sous Windows, puis nettoyage complet.
# Present dans les deux editions : la procedure suivie depend de windows\edition.txt.
#
# A lancer depuis la cle, dans PowerShell :
#   powershell -ExecutionPolicy Bypass -File .\windows\start-claude.ps1
#
# Ce que fait le script :
#   1. cree un dossier de session temporaire (config, identifiants et travail de Claude)
#   2. trouve Claude Code : windows\bin\claude.exe sur la cle, sinon celui du PC,
#      sinon installation temporaire avec l'installeur officiel
#   3. lance la session (le technicien se connecte au compte Claude de l'entreprise)
#   4. a la fermeture, quoi qu'il arrive : deconnexion, copie du rapport sur la cle,
#      suppression du dossier de session et de tout ce que l'installation a ajoute
#
# Rien de ce que le client avait deja (un Claude Code a lui, par exemple) n'est touche.

param(
    [string]$Technicien,
    [string]$Job
)

$ErrorActionPreference = 'Stop'
$KeyRoot = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== Claude Recovery - mode Windows ===' -ForegroundColor Cyan

# Edition de la cle (ecrite par la cle a son premier demarrage)
$Edition = 'entreprise'
$EditionFile = Join-Path $PSScriptRoot 'edition.txt'
if (Test-Path $EditionFile) {
    $read = (Get-Content $EditionFile -TotalCount 1).Trim()
    if ($read -eq 'particulier') { $Edition = 'particulier' }
}
Write-Host "Edition : $Edition"

if ($Edition -eq 'entreprise') {
    if (-not $Technicien) { $Technicien = Read-Host 'Technicien' }
    if (-not $Technicien) { Write-Host 'Nom du technicien obligatoire.'; exit 1 }
    if (-not $Job) { $Job = Read-Host 'Reference du job (ex. dupont-pc)' }
} else {
    $Technicien = 'particulier'
    if (-not $Job) { $Job = 'diagnostic' }
}
$Job = ($Job -replace '[^A-Za-z0-9._-]', '-').Trim('-')
if (-not $Job) { Write-Host 'Reference obligatoire.'; exit 1 }
$Job = '{0}_{1}' -f (Get-Date -Format 'yyyy-MM-dd'), $Job

# --- Dossiers ---------------------------------------------------------------
$Session   = Join-Path $env:TEMP ('ordi-claude-' + [guid]::NewGuid().ToString('N'))
$ConfigDir = Join-Path $Session 'config'
$WorkDir   = Join-Path $Session 'travail'
$Journal   = Join-Path $PSScriptRoot 'journal'
New-Item -ItemType Directory -Force -Path $ConfigDir, $WorkDir, $Journal | Out-Null

# --- Etat du PC avant notre passage (pour ne supprimer que ce qu'on ajoute) --
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
    # --- Trouver Claude Code -------------------------------------------------
    $Portable = Join-Path $PSScriptRoot 'bin\claude.exe'
    $Existing = Get-Command claude -ErrorAction SilentlyContinue
    if (Test-Path $Portable) {
        $Claude = $Portable
        Write-Host 'Claude Code : binaire de la cle.'
    } elseif ($Existing) {
        $Claude = $Existing.Source
        Write-Host 'Claude Code : deja present sur ce PC (il ne sera pas desinstalle).'
    } else {
        Write-Host 'Claude Code : installation temporaire...'
        $Installed = $true
        Invoke-Expression (Invoke-RestMethod -Uri 'https://claude.ai/install.ps1')
        if (-not (Test-Path $ExePath)) { throw "Installation echouee : $ExePath introuvable." }
        $Claude = $ExePath
    }

    # --- Config du mode Windows, isolee dans le dossier de session --------------
    Copy-Item (Join-Path $KeyRoot "config\windows\CLAUDE.$Edition.md") (Join-Path $ConfigDir 'CLAUDE.md')
    $HookPath = (Join-Path $PSScriptRoot 'log-command.ps1') -replace '\\', '\\'
    $Settings = (Get-Content (Join-Path $KeyRoot 'config\windows\settings.json') -Raw).Replace('__HOOK_PATH__', $HookPath)
    [System.IO.File]::WriteAllText((Join-Path $ConfigDir 'settings.json'), $Settings, (New-Object System.Text.UTF8Encoding($false)))

    $env:CLAUDE_CONFIG_DIR   = $ConfigDir
    $env:DISABLE_AUTOUPDATER = '1'
    $env:ORDI_TECH    = $Technicien
    $env:ORDI_JOB     = $Job
    $env:ORDI_JOURNAL = Join-Path $Journal ($Job + '.jsonl')

    Write-Host ''
    Write-Host "Job        : $Job"
    if ($Edition -eq 'entreprise') {
        Write-Host "Technicien : $Technicien"
        Write-Host 'Connectez-vous au compte Claude de votre entreprise quand Claude le demande.'
    } else {
        Write-Host 'Connectez-vous a votre compte Claude quand Claude le demande.'
        Write-Host 'A la fermeture, tout ce que cette session a ajoute au PC sera supprime.'
    }
    Write-Host ''

    Push-Location $WorkDir
    try { & $Claude } finally { Pop-Location }
}
finally {
    Write-Host ''
    Write-Host '=== Nettoyage ===' -ForegroundColor Cyan
    $ErrorActionPreference = 'Continue'
    $Problems = @()

    # 1. Deconnexion du compte (invalide la session, pas seulement le fichier local)
    if ($Claude -and (Test-Path $Claude) -and $env:CLAUDE_CONFIG_DIR) {
        try { & $Claude auth logout 2>&1 | Out-Null } catch { }
    }

    # 2. Rapport recopie sur la cle
    $Report = Join-Path $WorkDir 'rapport.md'
    if (Test-Path $Report) {
        Copy-Item $Report (Join-Path $Journal ($Job + '_rapport.md')) -Force
        Write-Host 'Rapport copie sur la cle.'
    }

    # 3. Dossier de session (config, identifiants, historique, travail)
    Remove-Item -Path $Session -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $Session) { $Problems += $Session }

    # 4. Ce que l'installation temporaire a ajoute, et seulement cela
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

    Remove-Item Env:CLAUDE_CONFIG_DIR, Env:ORDI_TECH, Env:ORDI_JOB, Env:ORDI_JOURNAL, Env:DISABLE_AUTOUPDATER -ErrorAction SilentlyContinue

    if ($Problems.Count -gt 0) {
        Write-Host 'ATTENTION : elements non supprimes, a retirer a la main :' -ForegroundColor Red
        $Problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    } else {
        Write-Host 'Nettoyage termine : rien ne reste sur ce PC.' -ForegroundColor Green
    }
    Write-Host "Journal de l'intervention : $Journal"
}
