<#
.SYNOPSIS
    Fully removes a USB headset from Windows - including hidden "ghost" copies left over
    from earlier installs - so Windows sets it up fresh, like the first time you plugged it in.

.DESCRIPTION
    Fixes the classic "my USB headset mic stopped working" problem caused by stale or
    duplicate device entries (seen a lot with Astro A50, Arctis, HyperX, Corsair, etc.).

    1. You pick your headset from a list (or pass -VendorId).
    2. The script shows every entry it will remove and asks before doing anything.
    3. You unplug the headset (or its base station / USB dongle).
    4. All of its device entries are removed with Windows' own pnputil tool.
    5. You plug it back in and Windows installs it fresh.

    Only devices from the chosen vendor that have an audio function are removed, so a mouse
    or keyboard from the same brand is left alone. Driver packages and apps are not touched.

.PARAMETER VendorId
    The 4-character USB vendor ID to reset (for example 9886 for Astro). Skips the menu.

.PARAMETER DryRun
    Only show what would be removed. Changes nothing and does not need admin rights.

.EXAMPLE
    .\Reset-Headset.ps1

.EXAMPLE
    .\Reset-Headset.ps1 -VendorId 9886 -DryRun
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{4}$')]
    [string]$VendorId,
    [switch]$DryRun
)

function Exit-WithPause([int]$Code = 0) {
    Write-Host ''
    Read-Host 'Press Enter to close this window' | Out-Null
    exit $Code
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProductId([string]$Text, [string]$Vid) {
    if ($Text -match "VID_$Vid&PID_([0-9A-F]{4})") { return $Matches[1].ToUpper() }
    return $null
}

# Every USB audio device Windows knows about (connected or not), grouped by vendor.
function Get-HeadsetChoices {
    $present = @{}
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $present[$_.InstanceId] = $true }

    Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}' } |
        Group-Object { ([regex]::Match($_.InstanceId, 'VID_([0-9A-F]{4})')).Groups[1].Value.ToUpper() } |
        ForEach-Object {
            $connected = @($_.Group | Where-Object { $present[$_.InstanceId] }).Count -gt 0
            [pscustomobject]@{
                VendorId  = $_.Name
                Names     = (@($_.Group | ForEach-Object { $_.FriendlyName } | Select-Object -Unique) -join ', ')
                Connected = $connected
            }
        } |
        Sort-Object @{ Expression = 'Connected'; Descending = $true }, Names
}

# All device entries that belong to this vendor's audio devices: the USB device itself,
# its sub-devices (audio, HID controls) and the speaker/mic entries Windows made for it.
function Get-HeadsetEntries([string]$Vid) {
    $all = @(Get-PnpDevice -ErrorAction SilentlyContinue)
    $present = @{}
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $present[$_.InstanceId] = $true }

    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($d in $all) {
        if ($d.InstanceId -notmatch "^(USB|HID)\\VID_$Vid&PID_") { continue }
        $entries.Add([pscustomobject]@{
            InstanceId = $d.InstanceId
            Name       = $d.FriendlyName
            Class      = $d.Class
            ProductId  = Get-ProductId $d.InstanceId $Vid
            Connected  = [bool]$present[$d.InstanceId]
        })
    }

    foreach ($d in $all) {
        if ($d.InstanceId -notlike 'SWD\MMDEVAPI\*') { continue }
        $parent = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_Parent -ErrorAction SilentlyContinue).Data
        $productId = Get-ProductId "$parent" $Vid
        if (-not $productId) { continue }
        $entries.Add([pscustomobject]@{
            InstanceId = $d.InstanceId
            Name       = $d.FriendlyName
            Class      = 'AudioEndpoint'
            ProductId  = $productId
            Connected  = [bool]$present[$d.InstanceId]
        })
    }

    # Keep only products that actually have audio, so same-brand mice/keyboards are skipped.
    $audioProducts = @($entries | Where-Object { $_.Class -eq 'MEDIA' -or $_.Class -eq 'AudioEndpoint' } |
        ForEach-Object { $_.ProductId } | Select-Object -Unique)

    # Children before parents: speaker/mic entries, then HID, then USB sub-devices, then the USB device.
    $order = {
        if ($_.InstanceId -like 'SWD\*') { 0 }
        elseif ($_.InstanceId -like 'HID\*') { 1 }
        elseif ($_.InstanceId -match '&MI_') { 2 }
        else { 3 }
    }
    @($entries | Where-Object { $audioProducts -contains $_.ProductId } | Sort-Object $order)
}

function Get-ConnectedAudio([string]$Vid) {
    @(Get-PnpDevice -PresentOnly -Class MEDIA -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "^USB\\VID_$Vid&" -and $_.Status -eq 'OK' })
}

# --- Checks and admin rights ----------------------------------------------------------

if ([Environment]::OSVersion.Version.Build -lt 19041) {
    Write-Host 'This script needs Windows 10 version 2004 or newer (or Windows 11).' -ForegroundColor Red
    Exit-WithPause 1
}

if (-not $DryRun -and -not (Test-IsAdmin)) {
    Write-Host 'Asking Windows for admin permission - click Yes on the popup...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($VendorId) { $argList += @('-VendorId', $VendorId) }
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -ErrorAction Stop
        exit 0
    } catch {
        Write-Host 'Admin permission was not given, so nothing was changed.' -ForegroundColor Red
        Exit-WithPause 1
    }
}

$log = Join-Path $env:TEMP 'headset-clean-reset-log.txt'
if (-not $DryRun) { Start-Transcript -Path $log -Force | Out-Null }

Write-Host ''
Write-Host '=== Headset clean reset ===' -ForegroundColor Cyan
if ($DryRun) { Write-Host '(Dry run: nothing will be changed)' -ForegroundColor DarkYellow }
Write-Host ''

# --- Pick the headset -----------------------------------------------------------------

if (-not $VendorId) {
    $choices = @(Get-HeadsetChoices)
    if ($choices.Count -eq 0) {
        Write-Host 'No USB audio devices found. Plug your headset in and run this again.' -ForegroundColor Red
        Exit-WithPause 1
    }

    Write-Host 'Which headset do you want to reset?'
    for ($i = 0; $i -lt $choices.Count; $i++) {
        $c = $choices[$i]
        $state = if ($c.Connected) { 'connected' } else { 'not connected' }
        Write-Host ("  {0}) {1}   [vendor {2}, {3}]" -f ($i + 1), $c.Names, $c.VendorId, $state)
    }
    Write-Host ''
    $pick = Read-Host 'Type the number and press Enter'
    $n = 0
    if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $choices.Count) {
        Write-Host 'That was not one of the numbers, so nothing was changed.' -ForegroundColor Red
        Exit-WithPause 1
    }
    $VendorId = $choices[$n - 1].VendorId
}
$VendorId = $VendorId.ToUpper()

# --- Show what will be removed and confirm ---------------------------------------------

$targets = Get-HeadsetEntries $VendorId
if ($targets.Count -eq 0) {
    Write-Host "No audio devices from vendor $VendorId were found. Nothing to do." -ForegroundColor Yellow
    Exit-WithPause 0
}

Write-Host ''
Write-Host "These $($targets.Count) entries will be removed:" -ForegroundColor Cyan
foreach ($t in $targets) {
    $state = if ($t.Connected) { 'connected' } else { 'leftover' }
    Write-Host ("  [{0,-9}] {1}" -f $state, $t.Name)
}
Write-Host ''
Write-Host 'Your apps and settings are not touched. Windows reinstalls the headset when you plug it back in.'

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run finished. Run again without -DryRun to remove them.' -ForegroundColor DarkYellow
    exit 0
}

$answer = Read-Host 'Type Y and press Enter to continue (anything else cancels)'
if ($answer -notmatch '^(y|yes)$') {
    Write-Host 'Cancelled. Nothing was changed.'
    Stop-Transcript | Out-Null
    Exit-WithPause 0
}

# --- Unplug ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'STEP 1: Unplug the headset''s USB cable (or its base station / wireless dongle).' -ForegroundColor Yellow
Write-Host '        Leave everything else plugged in.'
Read-Host 'Press Enter once it is unplugged' | Out-Null
Start-Sleep -Seconds 2

if ((Get-ConnectedAudio $VendorId).Count -gt 0) {
    Write-Host ''
    Write-Host 'It still looks plugged in. Please unplug its USB cable / dongle now.' -ForegroundColor Red
    Read-Host 'Press Enter once it is unplugged (or just press Enter to continue anyway)' | Out-Null
    Start-Sleep -Seconds 2
}

# --- Remove ---------------------------------------------------------------------------

$targets = Get-HeadsetEntries $VendorId
Write-Host ''
Write-Host "Removing $($targets.Count) entries..." -ForegroundColor Cyan
foreach ($t in $targets) {
    Write-Host "  - $($t.Name)"
    $out = & pnputil.exe /remove-device "$($t.InstanceId)" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { Write-Host $out -ForegroundColor DarkYellow }
}

$left = @(Get-HeadsetEntries $VendorId | Where-Object { -not $_.Connected })
Write-Host ''
if ($left.Count -eq 0) {
    Write-Host 'All entries removed.' -ForegroundColor Green
} else {
    Write-Host "$($left.Count) entries could not be removed:" -ForegroundColor Red
    $left | ForEach-Object { Write-Host "  - $($_.Name)  [$($_.InstanceId)]" }
}

# --- Plug back in ---------------------------------------------------------------------

Write-Host ''
Write-Host 'STEP 2: Plug the headset back in now.' -ForegroundColor Yellow
Write-Host '        (If it has a PC / console switch, make sure it is set to PC.)'
Write-Host 'Waiting for Windows to set it up fresh (up to 2 minutes)...'
$deadline = (Get-Date).AddMinutes(2)
$ready = $false
while ((Get-Date) -lt $deadline) {
    if ((Get-ConnectedAudio $VendorId).Count -gt 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 8

Write-Host ''
if ($ready) {
    Write-Host 'Windows installed the headset fresh:' -ForegroundColor Green
    Get-HeadsetEntries $VendorId | Where-Object { $_.Connected -and $_.Class -eq 'AudioEndpoint' } |
        ForEach-Object { Write-Host "  $($_.Name)" }
    Write-Host ''
    Write-Host 'Last step: Windows sees it as a brand-new device, so open the apps you talk in' -ForegroundColor Yellow
    Write-Host '(Discord, SteelSeries Sonar, OBS, your game, ...) and pick the headset''s microphone again.' -ForegroundColor Yellow
} else {
    Write-Host 'The headset did not show up yet. Try a different USB port and give it a minute.' -ForegroundColor Red
}

Stop-Transcript | Out-Null
Write-Host ''
Write-Host "A log of this run was saved to: $log"
Exit-WithPause 0
