# PostToolUse hook (Windows mode): logs every command Claude runs.
# Claude Code sends the details of the call as JSON on standard input.
# The log is written to the key (RECOVERY_JOURNAL), never to the customer's PC.
# This script never fails: it must not block the session.

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $call = $raw | ConvertFrom-Json

    $entry = [ordered]@{
        ts      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        tech    = $env:RECOVERY_TECH
        job     = $env:RECOVERY_JOB
        host    = $env:COMPUTERNAME
        mode    = 'windows'
        session = $call.session_id
        cwd     = $call.cwd
        tool    = $call.tool_name
        # A BitLocker recovery key (8 groups of 6 digits) never reaches a log.
        command = ([string]$call.tool_input.command) -replace '\d{6}([- ]?\d{6}){7}', '[recovery key removed]'
    }

    if ($env:RECOVERY_JOURNAL) {
        $line = $entry | ConvertTo-Json -Compress
        # UTF-8 without BOM, one entry per line
        [System.IO.File]::AppendAllText($env:RECOVERY_JOURNAL, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
} catch {
    # deliberately silent
}
exit 0
