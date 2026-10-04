#Requires -Version 5.1
<#
.SYNOPSIS
  Removes local Claude Desktop and Claude Code identity stores.

.DESCRIPTION
  Prints the plan and deletes nothing unless you choose 1 (or pass -Apply).
  The next launch recreates machineID, userID, ant-did, the device registry,
  telemetry salts, and Chromium storage.
  Local chat transcripts are kept.

  The Squirrel install under %LOCALAPPDATA%\AnthropicClaude is kept
  (claude.exe stays). Windows locale, timezone, public IP, and Chrome/Edge
  cookies are outside this script.

.PARAMETER Apply
  Stop Claude processes and delete the stores.

.PARAMETER Force
  Skip the YES prompt. Only meaningful with -Apply.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Reset-ClaudeIdentity.ps1 -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# Desktop data roots (real %APPDATA%\Claude and any Microsoft Store package).
# Filled in while building the target list, used by the markers display.
$DesktopRoots = @()

function Wait-Exit {
    param(
        [int]$Code,
        [string]$Message
    )
    Write-Host ''
    Write-Host $Message
    Write-Host ''
    Read-Host 'Нажми Enter, чтобы закрыть окно' | Out-Null
    exit $Code
}

function Get-FullPath {
    param([string]$Path)
    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $null
    }
}

function Add-UniquePath {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = Get-FullPath $Path
    if (-not $full) { return }
    foreach ($existing in $List) {
        if ($existing.Equals($full, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$List.Add($full)
}

function Test-ChildPath {
    param([string]$Child, [string]$Parent)
    $c = $Child.TrimEnd('\') + '\'
    $p = $Parent.TrimEnd('\') + '\'
    return $c.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ByteLength {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return [int64]0 }
    if (-not $item.PSIsContainer) { return [int64]$item.Length }
    $sum = [int64]0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $sum += [int64]$_.Length
    }
    return $sum
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Get-Prefix {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '(empty)' }
    $v = $Value.Trim()
    if ($v.Length -le 12) { return $v }
    return ($v.Substring(0, 8) + '...' + $v.Substring($v.Length - 4))
}

function Read-Utf8Json {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }
    return $text | ConvertFrom-Json
}

function Get-JsonProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Get-FirstExisting {
    param([string[]]$Roots, [string]$Leaf)
    foreach ($r in $Roots) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        $p = Join-Path $r $Leaf
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Show-IdentityMarkers {
    $roots = @($DesktopRoots)
    if ($roots.Count -eq 0) { $roots = @((Join-Path $env:APPDATA 'Claude')) }

    $cli = Join-Path $env:USERPROFILE '.claude.json'
    if (Test-Path -LiteralPath $cli) {
        try {
            $j = Read-Utf8Json $cli
            Write-Host ('  CLI machineID : {0}' -f (Get-Prefix ([string](Get-JsonProp $j 'machineID'))))
            Write-Host ('  CLI userID    : {0}' -f (Get-Prefix ([string](Get-JsonProp $j 'userID'))))
            $acct = Get-JsonProp $j 'oauthAccount'
            $uuid = Get-JsonProp $acct 'accountUuid'
            if ($uuid) {
                Write-Host ('  CLI account   : {0}' -f (Get-Prefix ([string]$uuid)))
            } else {
                Write-Host '  CLI account   : absent'
            }
        } catch {
            Write-Host '  CLI .claude.json: present, unreadable'
        }
    } else {
        Write-Host '  CLI .claude.json: absent'
    }

    $didPath = Get-FirstExisting $roots 'ant-did'
    if ($didPath) {
        $raw = [System.IO.File]::ReadAllText($didPath)
        Write-Host ('  ant-did       : {0}' -f (Get-Prefix $raw))
    } else {
        Write-Host '  ant-did       : absent'
    }

    $regPath = Get-FirstExisting $roots 'ant-device-registry.json'
    if ($regPath) {
        try {
            $reg = Read-Utf8Json $regPath
            $count = @($reg.PSObject.Properties).Count
            Write-Host ('  device registry entries: {0}' -f $count)
        } catch {
            Write-Host '  device registry: present, unreadable'
        }
    }

    $rcPath = Get-FirstExisting $roots 'remote-control-state.json'
    if ($rcPath) {
        try {
            $rc = Read-Utf8Json $rcPath
            Write-Host ('  telemetrySalt : {0}' -f (Get-Prefix ([string](Get-JsonProp $rc 'telemetrySalt'))))
        } catch {
            Write-Host '  telemetrySalt : unreadable'
        }
    }

    $ccdPath = Get-FirstExisting $roots 'ccd-ids.json'
    if ($ccdPath) {
        try {
            $ccd = Read-Utf8Json $ccdPath
            Write-Host ('  ccd salt      : {0}' -f (Get-Prefix ([string](Get-JsonProp $ccd 'salt'))))
        } catch {
            Write-Host '  ccd salt      : unreadable'
        }
    }
}

function Get-ClaudeProcesses {
    $hits = New-Object System.Collections.Generic.List[object]
    $cim = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
    foreach ($proc in $cim) {
        $name = [string]$proc.Name
        $exe = [string]$proc.ExecutablePath
        $cmd = [string]$proc.CommandLine
        $match = $false
        if ($name -match '^(Claude|claude)\.exe$') { $match = $true }
        elseif ($name -match '^cowork') { $match = $true }
        elseif ($exe -like '*\AnthropicClaude\*') { $match = $true }
        elseif ($exe -like '*\WindowsApps\Claude*') { $match = $true }
        elseif ($cmd -match 'claude-code|@anthropic-ai\\claude' -and $exe -notlike '*\Cursor\*' -and $cmd -notlike '*\Cursor\*') {
            $match = $true
        }
        if ($match) { [void]$hits.Add($proc) }
    }
    return @($hits.ToArray())
}

function Test-TreeHasReparsePoint {
    param([string]$Path)
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($Path)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $true }
            if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) }
        }
    }
    return $false
}

function Remove-Target {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host "SKIP reparse point: $Path"
        return $false
    }

    if (-not $item.PSIsContainer) {
        $item.Attributes = [IO.FileAttributes]::Normal
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return -not (Test-Path -LiteralPath $Path)
    }

    if (Test-TreeHasReparsePoint $Path) {
        Write-Host "SKIP tree that contains a junction or symlink: $Path"
        return $false
    }

    $quoted = '"' + $Path + '"'
    & cmd.exe /c "attrib -R $quoted\* /S /D >nul 2>&1 & rmdir /s /q $quoted"
    return -not (Test-Path -LiteralPath $Path)
}

function Clear-DesktopIdentityFields {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        $config = Read-Utf8Json $Path
        $prefs = Get-JsonProp $config 'preferences'
        if ($null -ne $prefs) {
            $names = @($prefs.PSObject.Properties.Name)
            foreach ($name in $names) {
                if ($name -eq 'remoteToolsDeviceName' -or $name -like '*ByAccount') {
                    $prefs.PSObject.Properties.Remove($name)
                }
            }
        }
        $json = $config | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($Path, $json)
        return $true
    } catch {
        Write-Host "Could not edit $Path"
        return $false
    }
}

$DesktopIdentityNames = @(
    'ant-did', 'ant-device-registry.json', 'remote-control-state.json', 'ccd-ids.json', 'config.json',
    'Preferences', 'Local State', 'DIPS', 'DIPS-wal', 'SharedStorage', 'SharedStorage-wal',
    'InterestGroups', 'InterestGroups-wal', 'declarative_performance_observer.db',
    'declarative_performance_observer.db-journal', 'fcache'
)
$DesktopChromiumNames = @(
    'Network', 'Local Storage', 'Session Storage', 'IndexedDB', 'WebStorage', 'shared_proto_db',
    'sentry', 'logs', 'Cache', 'Code Cache', 'GPUCache', 'DawnGraphiteCache', 'DawnWebGPUCache',
    'blob_storage', 'Crashpad', 'Partitions', 'File System', 'VideoDecodeStats', 'Shared Dictionary',
    'Service Worker', 'Storage'
)

function Add-DesktopDataTargets {
    param([System.Collections.Generic.List[string]]$List, [string]$Root)
    foreach ($name in $DesktopIdentityNames) { Add-UniquePath -List $List -Path (Join-Path $Root $name) }
    foreach ($name in $DesktopChromiumNames) { Add-UniquePath -List $List -Path (Join-Path $Root $name) }
}

function Add-CacheBreakTargets {
    param([System.Collections.Generic.List[string]]$List, [string]$Dir)
    if (Test-Path -LiteralPath $Dir) {
        Get-ChildItem -LiteralPath $Dir -Force -File -Filter 'cache-break-state-*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { Add-UniquePath -List $List -Path $_.FullName }
    }
}

$raw = New-Object System.Collections.Generic.List[string]
$claudeHome = Join-Path $env:USERPROFILE '.claude'
$desktop = Join-Path $env:APPDATA 'Claude'

# claude_desktop_config.json files are edited (device fields stripped), not deleted
$configEdits = New-Object System.Collections.Generic.List[string]
[void]$configEdits.Add((Join-Path $desktop 'claude_desktop_config.json'))

# chat folders we keep and show
$keptPaths = New-Object System.Collections.Generic.List[string]
foreach ($p in @(
    (Join-Path $claudeHome 'projects'),
    (Join-Path $claudeHome 'sessions'),
    (Join-Path $claudeHome 'file-history'),
    (Join-Path $claudeHome 'settings.json'),
    (Join-Path $desktop 'claude-code-sessions'),
    (Join-Path $desktop 'local-agent-mode-sessions')
)) { [void]$keptPaths.Add($p) }

# desktop data roots for the markers display
$DesktopRoots = @($desktop)

# CLI (~/.claude): identity, not chats
foreach ($name in @('.credentials.json', 'backups', 'cache', 'ide', 'session-env')) {
    Add-UniquePath -List $raw -Path (Join-Path $claudeHome $name)
}

# Squirrel / normal install desktop data
Add-DesktopDataTargets -List $raw -Root $desktop

foreach ($root in @(
    (Join-Path $env:LOCALAPPDATA 'Claude\logs'),
    (Join-Path $env:LOCALAPPDATA 'Claude-3p'),
    (Join-Path $env:LOCALAPPDATA 'claude-cli-nodejs'),
    (Join-Path $env:LOCALAPPDATA 'ClaudeDesktopRollbackBackups')
)) {
    Add-UniquePath -List $raw -Path $root
}

Add-CacheBreakTargets -List $raw -Dir (Join-Path $env:TEMP 'claude')

Get-ChildItem -LiteralPath $env:USERPROFILE -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq '.claude.json' -or $_.Name -like '.claude.json.*' } |
    ForEach-Object { Add-UniquePath -List $raw -Path $_.FullName }

# Microsoft Store (MSIX) install: the package data is virtualized under
# ...\Packages\Claude_*\LocalCache\. The package root has protected ACLs and
# cannot be deleted, so we only touch the identity data inside it.
$packageRoot = Join-Path $env:LOCALAPPDATA 'Packages'
if (Test-Path -LiteralPath $packageRoot) {
    Get-ChildItem -LiteralPath $packageRoot -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Claude*' -or $_.Name -like 'Anthropic*' } |
        ForEach-Object {
            $lc = Join-Path $_.FullName 'LocalCache'
            $roaming = Join-Path $lc 'Roaming\Claude'
            if (Test-Path -LiteralPath $roaming) { $DesktopRoots += $roaming }
            Add-DesktopDataTargets -List $raw -Root $roaming
            [void]$configEdits.Add((Join-Path $roaming 'claude_desktop_config.json'))
            foreach ($p in @(
                (Join-Path $roaming 'claude-code-sessions'),
                (Join-Path $roaming 'local-agent-mode-sessions')
            )) { [void]$keptPaths.Add($p) }
            Add-UniquePath -List $raw -Path (Join-Path $lc 'Local\Claude\logs')
            Add-UniquePath -List $raw -Path (Join-Path $lc 'Local\Claude-3p')
            Add-UniquePath -List $raw -Path (Join-Path $lc 'Local\claude-cli-nodejs')
            Add-CacheBreakTargets -List $raw -Dir (Join-Path $lc 'Local\Temp\claude')
            Add-CacheBreakTargets -List $raw -Dir (Join-Path $_.FullName 'TempState\claude')
        }
}

$install = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
if (Test-Path -LiteralPath $install) {
    Get-ChildItem -LiteralPath $install -Force -File -Filter 'Squirrel-*.log' -ErrorAction SilentlyContinue |
        ForEach-Object { Add-UniquePath -List $raw -Path $_.FullName }
}

$targets = New-Object System.Collections.Generic.List[string]
foreach ($candidate in @($raw | Sort-Object { $_.Length })) {
    $covered = $false
    foreach ($kept in $targets) {
        $keptIsDir = Test-Path -LiteralPath $kept -PathType Container
        if ($keptIsDir -and (Test-ChildPath -Child $candidate -Parent $kept)) {
            $covered = $true
            break
        }
    }
    if (-not $covered) { [void]$targets.Add($candidate) }
}

Write-Host ''
Write-Host 'Claude local identity reset'
Write-Host '---------------------------'
if ($Apply) {
    Write-Host 'Mode: APPLY (files will be deleted)'
} else {
    Write-Host 'Mode: PREVIEW (deletion starts only after you choose 1)'
}
if ($Force -and -not $Apply) {
    Write-Host '-Force is ignored without -Apply.'
}

Write-Host ''
Write-Host 'Current markers:'
Show-IdentityMarkers

Write-Host ''
Write-Host 'Targets:'
if ($targets.Count -eq 0) {
    Write-Host '  nothing found'
} else {
    foreach ($target in $targets) {
        $kind = 'file'
        if (Test-Path -LiteralPath $target -PathType Container) { $kind = 'dir ' }
        $size = Format-Bytes (Get-ByteLength $target)
        Write-Host ('  [{0}] {1,10}  {2}' -f $kind, $size, $target)
    }
}

$procs = @(Get-ClaudeProcesses)
Write-Host ''
Write-Host 'Processes that -Apply will stop:'
if ($procs.Count -eq 0) {
    Write-Host '  none'
} else {
    foreach ($proc in $procs) {
        Write-Host ('  PID {0}  {1}' -f $proc.ProcessId, $proc.Name)
    }
}

Write-Host ''
Write-Host 'Kept (local chats):'
$keptShown = $false
foreach ($path in $keptPaths) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $keptShown = $true
    $kind = 'file'
    if (Test-Path -LiteralPath $path -PathType Container) { $kind = 'dir ' }
    $size = Format-Bytes (Get-ByteLength $path)
    Write-Host ('  [{0}] {1,10}  {2}' -f $kind, $size, $path)
}
if (-not $keptShown) { Write-Host '  none found' }

Write-Host ''
Write-Host 'Also left in place:'
Write-Host '  %LOCALAPPDATA%\AnthropicClaude   (the app itself)'
Write-Host '  Windows locale, timezone, public IP'
Write-Host '  Chrome and Edge site data for claude.ai (ajs_anonymous_id)'
Write-Host '  HKCU uninstall key'
Write-Host '  claude_desktop_config.json will be edited, not deleted'
Write-Host ''
Write-Host 'Login and device IDs are removed. Local chat transcripts stay on disk.'

if (-not $Apply -and -not $Force) {
    Write-Host ''
    while ($true) {
        try {
            $answer = Read-Host 'Напишите 1, чтобы удалить идентификаторы, 2 чтобы выйти из программы'
        } catch {
            Wait-Exit 0 'Выход из программы.'
        }
        if ($answer -eq '1') { break }
        if ($answer -eq '2' -or [string]::IsNullOrWhiteSpace($answer)) { Wait-Exit 0 'Выход из программы.' }
        Write-Host 'Нужно 1 или 2.'
    }
}

Write-Host ''
Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*cowork*' -or $_.DisplayName -like '*Cowork*' -or $_.DisplayName -like '*Claude*' } |
    ForEach-Object {
        if ($_.Status -ne 'Stopped') {
            Write-Host ('Stopping service {0}' -f $_.Name)
            Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        }
    }
foreach ($proc in $procs) {
    Write-Host ('Stopping PID {0} {1}' -f $proc.ProcessId, $proc.Name)
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($procs.Count -gt 0) { Start-Sleep -Seconds 2 }

$failed = New-Object System.Collections.Generic.List[string]
foreach ($target in $targets) {
    Write-Host "Removing $target"
    if (-not (Remove-Target $target)) {
        [void]$failed.Add($target)
    }
}

if ($failed.Count -gt 0) {
    Start-Sleep -Seconds 1
    $retry = @($failed.ToArray())
    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($target in $retry) {
        if (-not (Remove-Target $target)) {
            [void]$failed.Add($target)
        }
    }
}

Write-Host 'Editing claude_desktop_config.json'
foreach ($cfg in $configEdits) {
    if (Test-Path -LiteralPath $cfg) {
        if (-not (Clear-DesktopIdentityFields -Path $cfg)) {
            [void]$failed.Add($cfg)
        }
    }
}

Write-Host ''
Write-Host 'Markers after wipe:'
Show-IdentityMarkers

if ($failed.Count -eq 0) {
    Wait-Exit 0 'Все хорошо. Локальные идентификаторы удалены.'
}

Write-Host ''
Write-Host 'Still present:'
foreach ($target in $failed) { Write-Host "  $target" }
Wait-Exit 2 'Не все файлы удалились. Полностью закрой Claude и запусти этот файл ещё раз.'
