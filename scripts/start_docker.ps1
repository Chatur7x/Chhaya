param([switch]$RepairStaleSockets)
$ErrorActionPreference = 'Stop'
$docker = (Get-Command docker.exe).Source
$desktop = Join-Path (Split-Path (Split-Path (Split-Path $docker))) 'Docker Desktop.exe'
if (!(Test-Path -LiteralPath $desktop)) { throw "Docker Desktop executable not found: $desktop" }

if ($RepairStaleSockets) {
    # Only use this for the Windows AF_UNIX 'file cannot be accessed' startup error.
    # Preserve the runtime directories; never touch settings, volumes or WSL disks.
    $processes = Get-Process 'Docker Desktop','com.docker.backend','com.docker.build' -ErrorAction SilentlyContinue
    $processes | Stop-Process -Force
    $processes | Wait-Process -ErrorAction SilentlyContinue
    $suffix = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    foreach ($relative in @('Docker\run', 'docker-secrets-engine')) {
        $runtime = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA $relative))
        $allowed = @((Join-Path $env:LOCALAPPDATA 'Docker\run'), (Join-Path $env:LOCALAPPDATA 'docker-secrets-engine'))
        if ($runtime -notin $allowed) { throw 'Unexpected Docker runtime path' }
        if (Test-Path -LiteralPath $runtime) {
            Move-Item -LiteralPath $runtime -Destination "$runtime-stale-$suffix"
        }
    }
}
Start-Process -FilePath $desktop -WindowStyle Hidden
Write-Output 'Docker Desktop started. Verify with: docker version; docker compose ps'
