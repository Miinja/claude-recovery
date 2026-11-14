# Hook PostToolUse (mode Windows) : journalise chaque commande lancee par Claude.
# Claude Code envoie le detail de l'appel en JSON sur l'entree standard.
# Le journal est ecrit sur la cle (ORDI_JOURNAL), jamais sur le PC du client.
# Ce script n'echoue jamais : il ne doit pas bloquer l'intervention.

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $call = $raw | ConvertFrom-Json

    $entry = [ordered]@{
        ts      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        tech    = $env:ORDI_TECH
        job     = $env:ORDI_JOB
        host    = $env:COMPUTERNAME
        mode    = 'windows'
        session = $call.session_id
        cwd     = $call.cwd
        tool    = $call.tool_name
        command = $call.tool_input.command
    }

    if ($env:ORDI_JOURNAL) {
        $line = $entry | ConvertTo-Json -Compress
        # UTF-8 sans BOM, une entree par ligne
        [System.IO.File]::AppendAllText($env:ORDI_JOURNAL, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
} catch {
    # volontairement silencieux
}
exit 0
