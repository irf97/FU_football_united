[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Status', 'Logs')]
    [string]$Action = 'Start',
    [string]$HostIP = '',
    [ValidateRange(1024, 65535)]
    [int]$Port = 4000,
    [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env.local-mobile'
$composeFile = Join-Path $PSScriptRoot 'compose.local-mobile.yml'

function Test-PrivateAddress([string]$Address) {
    if ($Address -eq '127.0.0.1') { return $true }
    $parsed = $null
    if ($Address -notmatch '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$' -or
        -not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return $bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
}

function New-RandomHex([int]$Length) {
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}

function Invoke-Docker([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Docker could not complete the command. Open Docker Desktop, wait until its engine is ready, then try again.' }
}

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Install Docker Desktop, open it, and then start Spontaan again. No Elixir, Node or SMS account is required.'
    }
    Invoke-Docker -Arguments @('info', '--format', 'Docker engine: {{.ServerVersion}}')
    Invoke-Docker -Arguments @('compose', 'version', '--short')

    $settings = @{}
    if (Test-Path -LiteralPath $envFile) {
        foreach ($line in [IO.File]::ReadAllLines($envFile)) {
            if ($line -match '^([A-Z_]+)=(.*)$') { $settings[$Matches[1]] = $Matches[2] }
        }
        foreach ($key in @('SPONTAAN_COOKIE_SECRET', 'SPONTAAN_DB_PASSWORD', 'SPONTAAN_LOCAL_IP', 'SPONTAAN_LOCAL_PORT')) {
            if (-not $settings[$key]) { throw 'The saved local settings are incomplete. Keep the existing file and database; restore the settings before continuing.' }
        }
    } elseif ($Action -ne 'Start') {
        throw 'This local workspace has not been started yet. Double-click Start_Spontaan.cmd first.'
    }

    if ($Action -eq 'Start') {
        if (-not $PSBoundParameters.ContainsKey('Port') -and $settings['SPONTAAN_LOCAL_PORT']) {
            $Port = [int]$settings['SPONTAAN_LOCAL_PORT']
        }
        if (-not $HostIP) {
            if (-not (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
                throw 'Supply your private Wi-Fi/Ethernet IPv4 address with -HostIP. Automatic selection is available on Windows.'
            }
            $network = @(Get-NetIPConfiguration | Where-Object {
                $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' -and $_.NetAdapter.HardwareInterface
            } | Sort-Object InterfaceIndex | Select-Object -First 1)
            if ($network.Count -eq 0) { throw 'No active Wi-Fi/Ethernet address was found. Connect to Wi-Fi or supply -HostIP.' }
            $HostIP = @($network[0].IPv4Address)[0].IPAddress
        }
        if (-not (Test-PrivateAddress $HostIP)) { throw 'Choose a private Wi-Fi/Ethernet IPv4 address, such as 192.168.x.x or 10.x.x.x.' }
        if (-not $settings['SPONTAAN_COOKIE_SECRET']) {
            $settings['SPONTAAN_COOKIE_SECRET'] = New-RandomHex 48
            $settings['SPONTAAN_DB_PASSWORD'] = New-RandomHex 24
        }
        $settings['SPONTAAN_LOCAL_IP'] = $HostIP
        $settings['SPONTAAN_LOCAL_PORT'] = [string]$Port
        $keys = @('SPONTAAN_COOKIE_SECRET', 'SPONTAAN_DB_PASSWORD', 'SPONTAAN_LOCAL_IP', 'SPONTAAN_LOCAL_PORT')
        $lines = @($keys | ForEach-Object { $_ + '=' + $settings[$_] })
        [IO.File]::WriteAllText($envFile, ($lines -join "`n") + "`n", [System.Text.Encoding]::ASCII)
    }

    $compose = @('compose', '--project-name', 'spontaan-local-mobile', '--env-file', $envFile, '-f', $composeFile)
    Invoke-Docker ($compose + @('config', '--quiet'))

    switch ($Action) {
        'Start' {
            Write-Host 'Building your local Spontaan workspace. The first start downloads dependencies; later starts reuse them.'
            Invoke-Docker ($compose + @('up', '--detach', '--build', '--wait', '--wait-timeout', '240', 'app'))
            $address = 'http://' + $settings['SPONTAAN_LOCAL_IP'] + ':' + $settings['SPONTAAN_LOCAL_PORT']
            $health = Invoke-WebRequest -Uri ($address + '/healthz') -UseBasicParsing -TimeoutSec 15
            if ($health.StatusCode -ne 200) { throw 'The local app has not become ready yet. Use -Action Logs to inspect it.' }
            Write-Host ''
            Write-Host ('OPEN ON YOUR PHONE: ' + $address) -ForegroundColor Green
            Write-Host 'Connect the phone and this computer to the same private Wi-Fi/network.'
            Write-Host 'Sign in as Ari: +31680000601. Request a code; it appears on the phone screen.'
            Write-Host 'No real SMS is sent. Your changes are saved in the local database.'
            Write-Host 'Keep Docker Desktop running. Close this window freely; the app keeps running.'
            Write-Host 'Stop with: .\fu\local-mobile.ps1 -Action Stop'
            if (-not $NoOpen) { Start-Process $address }
        }
        'Stop' { Invoke-Docker ($compose + @('down')); Write-Host 'Spontaan stopped. Your local database and settings are retained.' }
        'Status' { Invoke-Docker ($compose + @('ps')) }
        'Logs' { Invoke-Docker ($compose + @('logs', '--tail', '100', 'app', 'init')) }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
