param(
    [string]$PetId = 'bully',
    [string]$PetRoot = (Join-Path $PSScriptRoot 'assets'),
    [string]$PetDir = '',
    [double]$Scale = 0.85,
    [ValidateSet('zh-CN', 'en-US')]
    [string]$Language = 'zh-CN',
    [int]$ApiPort = 17888,
    [switch]$DisableApi,
    [switch]$NotTopmost
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:launchParameters = $PSBoundParameters

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class DesktopPetNativeMethods {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
}
"@

$cellWidth = 192
$cellHeight = 208
$script:dataDir = Join-Path $PSScriptRoot 'data'
$script:settingsPath = Join-Path $script:dataDir 'settings.json'
$script:carePath = Join-Path $script:dataDir 'care.json'
$script:apiListener = $null
$script:apiPendingContext = $null
$script:apiTimer = $null
$script:notifyIcon = $null
$script:apiEnabled = -not $DisableApi
$script:locked = $false
$script:systemMonitorEnabled = $true
$script:systemMonitorTimer = $null
$script:careTimer = $null
$script:cpuSamples = [System.Collections.Generic.List[double]]::new()
$script:memorySamples = [System.Collections.Generic.List[double]]::new()
$script:lastSystemStateChange = [DateTime]::MinValue
$script:lastSystemMood = 'idle'
$script:lastIdleSeconds = 0.0
$script:systemStateHoldSeconds = 12
$script:lastSystemMetrics = [ordered]@{
    cpu = 0.0
    memory = 0.0
    idleSeconds = 0.0
    batteryPercent = $null
    charging = $null
    reason = 'starting'
}
$script:careData = $null
$script:careState = $null
$script:lastCareReason = 'balanced'
$script:baseStates = $null
$script:stateFallbacks = @{
    'feeding'  = 'waving'
    'cleaning' = 'review'
    'bathing'  = 'jumping'
    'playing'  = 'jumping'
    'resting'  = 'idle'
    'hungry'   = 'waiting'
    'dirty'    = 'waiting'
    'tired'    = 'failed'
    'lonely'   = 'failed'
}

function Copy-StateMap {
    param([Parameter(Mandatory = $true)][hashtable]$Source)

    $copy = @{}
    foreach ($key in $Source.Keys) {
        $value = $Source[$key]
        $copy[$key] = @{
            Row = [int]$value.Row
            Frames = [int]$value.Frames
            Interval = [int]$value.Interval
        }
    }
    return $copy
}

$states = @{
    'idle'          = @{ Row = 0; Frames = 6; Interval = 180 }
    'running-right' = @{ Row = 1; Frames = 8; Interval = 110 }
    'running-left'  = @{ Row = 2; Frames = 8; Interval = 110 }
    'waving'        = @{ Row = 3; Frames = 4; Interval = 150 }
    'jumping'       = @{ Row = 4; Frames = 5; Interval = 135 }
    'failed'        = @{ Row = 5; Frames = 8; Interval = 170 }
    'waiting'       = @{ Row = 6; Frames = 6; Interval = 180 }
    'running'       = @{ Row = 7; Frames = 6; Interval = 145 }
    'review'        = @{ Row = 8; Frames = 6; Interval = 170 }
    'feeding'       = @{ Row = 9; Frames = 6; Interval = 145 }
    'cleaning'      = @{ Row = 10; Frames = 6; Interval = 150 }
    'bathing'       = @{ Row = 11; Frames = 6; Interval = 145 }
    'playing'       = @{ Row = 12; Frames = 6; Interval = 125 }
    'resting'       = @{ Row = 13; Frames = 6; Interval = 210 }
    'hungry'        = @{ Row = 14; Frames = 6; Interval = 180 }
    'dirty'         = @{ Row = 15; Frames = 6; Interval = 180 }
    'tired'         = @{ Row = 16; Frames = 6; Interval = 200 }
    'lonely'        = @{ Row = 17; Frames = 6; Interval = 185 }
}
$script:baseStates = Copy-StateMap $states

$script:bitmap = $null
$script:window = $null
$script:petImage = $null
$script:timer = $null
$script:activePetDir = ''
$script:activePetId = ''
$script:activePetName = ''
$script:currentState = 'idle'
$script:frameIndex = 0
$script:temporaryUntil = $null
$script:isMouseDown = $false
$script:isDragging = $false
$script:startCursor = $null
$script:startLeft = 0.0
$script:startTop = 0.0
$script:lastDragDirection = 'running-right'
$script:language = $Language

$script:i18n = @{
    'en-US' = @{
        pets = 'Pets'
        language = 'Language'
        english = 'English'
        chinese = '中文'
        noPets = 'No pets found'
        idle = 'Relaxing'
        waiting = 'Asking for attention'
        runningTask = 'Focused'
        review = 'Inspecting'
        failed = 'Sulking'
        show = 'Show'
        hide = 'Hide'
        lockMove = 'Lock movement'
        unlockMove = 'Unlock movement'
        autoStartOn = 'Enable auto-start'
        autoStartOff = 'Disable auto-start'
        systemLinkOn = 'Enable system link'
        systemLinkOff = 'Disable system link'
        systemStatus = 'System link'
        care = 'Care'
        careStatus = 'Care status'
        fullness = 'Fullness'
        cleanliness = 'Cleanliness'
        mood = 'Mood'
        energy = 'Energy'
        feed = 'Feed'
        clean = 'Clean'
        bath = 'Bath'
        play = 'Play'
        rest = 'Rest'
        apiStatus = 'Local API'
        bigger = 'Bigger'
        smaller = 'Smaller'
        toggleTopmost = 'Toggle Topmost'
        exit = 'Exit'
    }
    'zh-CN' = @{
        pets = '宠物'
        language = '语言'
        english = 'English'
        chinese = '中文'
        noPets = '未找到宠物'
        idle = '休息'
        waiting = '求关注'
        runningTask = '专注中'
        review = '认真观察'
        failed = '委屈趴下'
        show = '显示'
        hide = '隐藏'
        lockMove = '锁定位置'
        unlockMove = '解除锁定'
        autoStartOn = '开启开机自启'
        autoStartOff = '关闭开机自启'
        systemLinkOn = '开启系统联动'
        systemLinkOff = '关闭系统联动'
        systemStatus = '系统联动'
        care = '照顾宠物'
        careStatus = '照顾状态'
        fullness = '饱食'
        cleanliness = '清洁'
        mood = '心情'
        energy = '精力'
        feed = '喂食'
        clean = '打扫'
        bath = '洗澡'
        play = '玩耍'
        rest = '休息'
        apiStatus = '本地 API'
        bigger = '放大'
        smaller = '缩小'
        toggleTopmost = '切换置顶'
        exit = '退出'
    }
}

function T {
    param([Parameter(Mandatory = $true)][string]$Key)

    $table = $script:i18n[$script:language]
    if ($null -eq $table -or -not $table.ContainsKey($Key)) {
        $table = $script:i18n['en-US']
    }
    if ($table.ContainsKey($Key)) {
        return $table[$Key]
    }
    return $Key
}

function Get-ObjectProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if ($Object -ne $null -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Clamp-Percent {
    param([double]$Value)

    return [Math]::Round([Math]::Max(0, [Math]::Min(100, $Value)), 1)
}

function Load-Settings {
    $defaults = [ordered]@{
        petId = $PetId
        language = $Language
        scale = $Scale
        left = 80
        top = 120
        topmost = -not $NotTopmost
        locked = $false
        apiEnabled = -not $DisableApi
        apiPort = $ApiPort
        systemMonitorEnabled = $true
    }

    if (Test-Path -LiteralPath $script:settingsPath) {
        try {
            $loaded = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
            foreach ($property in $loaded.PSObject.Properties) {
                $defaults[$property.Name] = $property.Value
            }
        }
        catch {
            # Ignore invalid settings and fall back to defaults.
        }
    }

    if ($script:launchParameters.ContainsKey('PetId')) { $defaults.petId = $PetId }
    if ($script:launchParameters.ContainsKey('Language')) { $defaults.language = $Language }
    if ($script:launchParameters.ContainsKey('Scale')) { $defaults.scale = $Scale }
    if ($script:launchParameters.ContainsKey('ApiPort')) { $defaults.apiPort = $ApiPort }
    if ($script:launchParameters.ContainsKey('DisableApi')) { $defaults.apiEnabled = -not $DisableApi }
    if ($script:launchParameters.ContainsKey('NotTopmost')) { $defaults.topmost = -not $NotTopmost }

    return [pscustomobject]$defaults
}

function Save-Settings {
    if ($script:window -eq $null) {
        return
    }

    New-Item -ItemType Directory -Force -Path $script:dataDir | Out-Null
    $settings = [ordered]@{
        petId = $script:activePetId
        language = $script:language
        scale = [Math]::Round(($script:window.Width / $cellWidth), 2)
        left = [Math]::Round($script:window.Left, 0)
        top = [Math]::Round($script:window.Top, 0)
        topmost = [bool]$script:window.Topmost
        locked = [bool]$script:locked
        apiEnabled = [bool]$script:apiEnabled
        apiPort = [int]$ApiPort
        systemMonitorEnabled = [bool]$script:systemMonitorEnabled
    }
    $json = $settings | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $script:settingsPath -Value $json -Encoding UTF8
}

function New-CareState {
    return [ordered]@{
        fullness = 85.0
        cleanliness = 85.0
        mood = 80.0
        energy = 80.0
        updatedAt = [DateTimeOffset]::Now.ToString('o')
    }
}

function Convert-CareState {
    param($Value)

    return [ordered]@{
        fullness = Clamp-Percent ([double](Get-ObjectProperty $Value 'fullness' 85.0))
        cleanliness = Clamp-Percent ([double](Get-ObjectProperty $Value 'cleanliness' 85.0))
        mood = Clamp-Percent ([double](Get-ObjectProperty $Value 'mood' 80.0))
        energy = Clamp-Percent ([double](Get-ObjectProperty $Value 'energy' 80.0))
        updatedAt = [string](Get-ObjectProperty $Value 'updatedAt' ([DateTimeOffset]::Now.ToString('o')))
    }
}

function Load-CareData {
    if ($script:careData -ne $null) {
        return
    }

    $script:careData = [ordered]@{ pets = @{} }
    if (-not (Test-Path -LiteralPath $script:carePath -PathType Leaf)) {
        return
    }

    try {
        $loaded = Get-Content -LiteralPath $script:carePath -Raw | ConvertFrom-Json
        $pets = Get-ObjectProperty $loaded 'pets' $null
        if ($pets -ne $null) {
            foreach ($property in $pets.PSObject.Properties) {
                $script:careData.pets[$property.Name] = Convert-CareState $property.Value
            }
        }
    }
    catch {
        $script:careData = [ordered]@{ pets = @{} }
    }
}

function Save-CareData {
    Load-CareData
    New-Item -ItemType Directory -Force -Path $script:dataDir | Out-Null
    Set-Content -LiteralPath $script:carePath -Value ($script:careData | ConvertTo-Json -Depth 10) -Encoding UTF8
}

function Ensure-CareState {
    Load-CareData
    if ([string]::IsNullOrWhiteSpace($script:activePetId)) {
        return $null
    }

    if (-not $script:careData.pets.ContainsKey($script:activePetId)) {
        $script:careData.pets[$script:activePetId] = New-CareState
        Save-CareData
    }
    $script:careState = $script:careData.pets[$script:activePetId]
    return $script:careState
}

function Update-CareDecay {
    $state = Ensure-CareState
    if ($state -eq $null) {
        return
    }

    try {
        $lastUpdated = [DateTimeOffset]::Parse([string]$state.updatedAt)
    }
    catch {
        $lastUpdated = [DateTimeOffset]::Now
    }

    $now = [DateTimeOffset]::Now
    $elapsedMinutes = ($now - $lastUpdated).TotalMinutes
    if ($elapsedMinutes -lt 0.5) {
        return
    }

    $hours = $elapsedMinutes / 60.0
    $state.fullness = Clamp-Percent ([double]$state.fullness - (6.0 * $hours))
    $state.cleanliness = Clamp-Percent ([double]$state.cleanliness - (4.0 * $hours))
    $state.mood = Clamp-Percent ([double]$state.mood - (3.0 * $hours))
    $state.energy = Clamp-Percent ([double]$state.energy - (4.0 * $hours))

    if ([double]$state.fullness -lt 25) {
        $state.mood = Clamp-Percent ([double]$state.mood - (2.0 * $hours))
    }
    if ([double]$state.cleanliness -lt 25) {
        $state.mood = Clamp-Percent ([double]$state.mood - (1.5 * $hours))
    }

    $state.updatedAt = $now.ToString('o')
    Save-CareData
}

function Format-CareLine {
    $state = Ensure-CareState
    if ($state -eq $null) {
        return ''
    }
    return "$(T 'fullness') $([int]$state.fullness)  $(T 'cleanliness') $([int]$state.cleanliness)  $(T 'mood') $([int]$state.mood)  $(T 'energy') $([int]$state.energy)"
}

function Resolve-CareMood {
    Update-CareDecay
    $state = Ensure-CareState
    if ($state -eq $null) {
        return [ordered]@{ state = 'idle'; temporaryMs = 0; reason = 'no_pet' }
    }

    if ([double]$state.fullness -le 15) {
        return [ordered]@{ state = 'hungry'; temporaryMs = 0; reason = 'hungry' }
    }
    if ([double]$state.cleanliness -le 15) {
        return [ordered]@{ state = 'dirty'; temporaryMs = 0; reason = 'dirty' }
    }
    if ([double]$state.energy -le 12) {
        return [ordered]@{ state = 'tired'; temporaryMs = 0; reason = 'tired' }
    }
    if ([double]$state.mood -le 20) {
        return [ordered]@{ state = 'lonely'; temporaryMs = 0; reason = 'lonely' }
    }
    if ([double]$state.energy -le 28) {
        return [ordered]@{ state = 'resting'; temporaryMs = 0; reason = 'low_energy' }
    }
    return [ordered]@{ state = 'idle'; temporaryMs = 0; reason = 'balanced' }
}

function Invoke-CareAction {
    param([Parameter(Mandatory = $true)][string]$Action)

    Update-CareDecay
    $state = Ensure-CareState
    if ($state -eq $null) {
        return
    }

    switch ($Action) {
        'feed' {
            $state.fullness = Clamp-Percent ([double]$state.fullness + 28)
            $state.mood = Clamp-Percent ([double]$state.mood + 4)
            $state.energy = Clamp-Percent ([double]$state.energy + 3)
            Set-PetState 'feeding' 1800
        }
        'clean' {
            $state.cleanliness = Clamp-Percent ([double]$state.cleanliness + 18)
            $state.mood = Clamp-Percent ([double]$state.mood + 3)
            Set-PetState 'cleaning' 1800
        }
        'bath' {
            $state.cleanliness = Clamp-Percent ([double]$state.cleanliness + 35)
            $state.mood = Clamp-Percent ([double]$state.mood + 5)
            $state.energy = Clamp-Percent ([double]$state.energy - 3)
            Set-PetState 'bathing' 1800
        }
        'play' {
            $state.mood = Clamp-Percent ([double]$state.mood + 24)
            $state.energy = Clamp-Percent ([double]$state.energy - 14)
            $state.fullness = Clamp-Percent ([double]$state.fullness - 4)
            $state.cleanliness = Clamp-Percent ([double]$state.cleanliness - 5)
            Set-PetState 'playing' 1900
        }
        'rest' {
            $state.energy = Clamp-Percent ([double]$state.energy + 28)
            $state.mood = Clamp-Percent ([double]$state.mood + 3)
            Set-PetState 'resting' 2200
        }
        default {
            return
        }
    }

    $state.updatedAt = [DateTimeOffset]::Now.ToString('o')
    Save-CareData
    Build-ContextMenu
    Build-TrayMenu
}

function Get-AutoStartCommand {
    $scriptPath = Join-Path $PSScriptRoot 'DesktopPet.ps1'
    return "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
}

function Get-AutoStartEnabled {
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $name = 'DesktopPet'
    try {
        $value = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
        return -not [string]::IsNullOrWhiteSpace([string]$value)
    }
    catch {
        return $false
    }
}

function Set-AutoStart {
    param([bool]$Enabled)

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $name = 'DesktopPet'
    if ($Enabled) {
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name $name -Value (Get-AutoStartCommand)
    }
    else {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    }
}

function Get-PetInfo {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $leaf = Split-Path -Leaf $Directory
    $info = [ordered]@{
        id = $leaf
        displayName = $leaf
        description = ''
    }

    $metaPath = Join-Path $Directory 'pet.json'
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        if ($meta.PSObject.Properties.Name -contains 'id' -and $meta.id) {
            $info.id = [string]$meta.id
        }
        if ($meta.PSObject.Properties.Name -contains 'displayName' -and $meta.displayName) {
            $info.displayName = [string]$meta.displayName
        }
        if ($meta.PSObject.Properties.Name -contains 'description' -and $meta.description) {
            $info.description = [string]$meta.description
        }
    }

    return [pscustomobject]$info
}

function Load-PetAnimations {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $script:states = Copy-StateMap $script:baseStates
    $metaPath = Join-Path $Directory 'pet.json'
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        return
    }

    try {
        $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
        $animations = Get-ObjectProperty $meta 'animations' $null
        if ($animations -eq $null) {
            return
        }

        foreach ($property in $animations.PSObject.Properties) {
            $animation = $property.Value
            $row = [int](Get-ObjectProperty $animation 'row' (Get-ObjectProperty $animation 'Row' -1))
            $frames = [int](Get-ObjectProperty $animation 'frames' (Get-ObjectProperty $animation 'Frames' 6))
            $interval = [int](Get-ObjectProperty $animation 'interval' (Get-ObjectProperty $animation 'Interval' 160))
            if ($row -ge 0 -and $frames -gt 0 -and $interval -gt 0) {
                $script:states[$property.Name] = @{
                    Row = $row
                    Frames = $frames
                    Interval = $interval
                }
            }
        }
    }
    catch {
        $script:states = Copy-StateMap $script:baseStates
    }
}

function Get-AvailablePets {
    if (-not (Test-Path -LiteralPath $PetRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $PetRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'spritesheet.png') } |
            Sort-Object Name
    )
}

function Load-Pet {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $resolved = Resolve-Path -LiteralPath $Directory
    $directoryPath = $resolved.Path
    $spritesheetPath = Join-Path $directoryPath 'spritesheet.png'
    if (-not (Test-Path -LiteralPath $spritesheetPath)) {
        throw "Missing spritesheet: $spritesheetPath"
    }

    $image = [System.Windows.Media.Imaging.BitmapImage]::new()
    $image.BeginInit()
    $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $image.UriSource = [Uri]$spritesheetPath
    $image.EndInit()
    $image.Freeze()

    $info = Get-PetInfo $directoryPath
    $script:bitmap = $image
    Load-PetAnimations $directoryPath
    $script:activePetDir = $directoryPath
    $script:activePetId = $info.id
    $script:activePetName = $info.displayName
    $script:careState = $null
    Ensure-CareState | Out-Null
    $script:frameIndex = 0
    $script:temporaryUntil = $null
    $script:currentState = 'idle'

    if ($script:window -ne $null) {
        $script:window.Title = "$($script:activePetName) Desktop Pet"
    }
    Save-Settings
}

function Test-PetStateAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $states.ContainsKey($Name)) {
        return $false
    }
    if ($script:bitmap -eq $null) {
        return $true
    }

    $row = [int]$states[$Name].Row
    return ((($row + 1) * $cellHeight) -le [int]$script:bitmap.PixelHeight)
}

function Resolve-PetStateName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Test-PetStateAvailable $Name) {
        return $Name
    }

    $visited = @{}
    $candidate = $Name
    while ($script:stateFallbacks.ContainsKey($candidate) -and -not $visited.ContainsKey($candidate)) {
        $visited[$candidate] = $true
        $candidate = [string]$script:stateFallbacks[$candidate]
        if (Test-PetStateAvailable $candidate) {
            return $candidate
        }
    }

    if (Test-PetStateAvailable 'idle') {
        return 'idle'
    }
    return ''
}

function Set-PetState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TemporaryMs = 0
    )

    $resolvedName = Resolve-PetStateName $Name
    if ([string]::IsNullOrWhiteSpace($resolvedName)) {
        return
    }
    if ($script:currentState -ne $resolvedName) {
        $script:frameIndex = 0
    }
    $script:currentState = $resolvedName
    if ($TemporaryMs -gt 0) {
        $script:temporaryUntil = [DateTime]::Now.AddMilliseconds($TemporaryMs)
    }
    else {
        $script:temporaryUntil = $null
    }
}

function Set-PetScale {
    param([double]$NewScale)

    $bounded = [Math]::Max(0.55, [Math]::Min(2.5, $NewScale))
    $script:window.Width = $cellWidth * $bounded
    $script:window.Height = $cellHeight * $bounded
    $script:petImage.Width = $script:window.Width
    $script:petImage.Height = $script:window.Height
    Save-Settings
}

function Update-PetFrame {
    if ($script:bitmap -eq $null) {
        return
    }

    $resolvedStateName = Resolve-PetStateName $script:currentState
    if ([string]::IsNullOrWhiteSpace($resolvedStateName)) {
        return
    }
    if ($resolvedStateName -ne $script:currentState) {
        $script:currentState = $resolvedStateName
        $script:frameIndex = 0
    }

    $state = $states[$script:currentState]
    $row = [int]$state.Row
    $frames = [int]$state.Frames

    if ($script:temporaryUntil -ne $null -and [DateTime]::Now -ge $script:temporaryUntil) {
        $script:temporaryUntil = $null
        Set-PetState 'idle'
        $state = $states[$script:currentState]
        $row = [int]$state.Row
        $frames = [int]$state.Frames
    }

    $x = ($script:frameIndex % $frames) * $cellWidth
    $y = $row * $cellHeight
    $rect = [System.Windows.Int32Rect]::new($x, $y, $cellWidth, $cellHeight)
    $crop = [System.Windows.Media.Imaging.CroppedBitmap]::new($script:bitmap, $rect)
    $script:petImage.Source = $crop

    $script:frameIndex = ($script:frameIndex + 1) % $frames
    $script:timer.Interval = [TimeSpan]::FromMilliseconds([int]$state.Interval)
}

function Add-MetricSample {
    param(
        [System.Collections.Generic.List[double]]$Samples,
        [double]$Value,
        [int]$Limit = 3
    )

    [void]$Samples.Add($Value)
    while ($Samples.Count -gt $Limit) {
        $Samples.RemoveAt(0)
    }
}

function Get-MetricAverage {
    param([System.Collections.Generic.List[double]]$Samples)

    if ($null -eq $Samples -or $Samples.Count -eq 0) {
        return 0.0
    }
    $sum = 0.0
    foreach ($sample in $Samples) {
        $sum += $sample
    }
    return [Math]::Round($sum / $Samples.Count, 1)
}

function Get-UserIdleSeconds {
    try {
        $info = [DesktopPetNativeMethods+LASTINPUTINFO]::new()
        $info.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type][DesktopPetNativeMethods+LASTINPUTINFO])
        if (-not [DesktopPetNativeMethods]::GetLastInputInfo([ref]$info)) {
            return 0.0
        }
        $now = [uint32][Environment]::TickCount
        $elapsed = [uint32]($now - $info.dwTime)
        return [Math]::Round($elapsed / 1000.0, 1)
    }
    catch {
        return 0.0
    }
}

function Get-SystemMetrics {
    $cpu = 0.0
    $memory = 0.0
    $batteryPercent = $null
    $charging = $null

    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        if ($processors.Count -gt 0) {
            $totalCpu = 0.0
            foreach ($processor in $processors) {
                $totalCpu += [double]$processor.LoadPercentage
            }
            $cpu = [Math]::Round($totalCpu / $processors.Count, 1)
        }
    }
    catch {
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $total = [double]$os.TotalVisibleMemorySize
        $free = [double]$os.FreePhysicalMemory
        if ($total -gt 0) {
            $memory = [Math]::Round((($total - $free) / $total) * 100.0, 1)
        }
    }
    catch {
    }

    try {
        $battery = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($battery.Count -gt 0 -and $battery[0] -ne $null) {
            $batteryPercent = [int]$battery[0].EstimatedChargeRemaining
            $charging = [int]$battery[0].BatteryStatus -in @(2, 6, 7, 8, 9)
        }
    }
    catch {
    }

    Add-MetricSample $script:cpuSamples $cpu
    Add-MetricSample $script:memorySamples $memory

    return [ordered]@{
        cpu = Get-MetricAverage $script:cpuSamples
        memory = Get-MetricAverage $script:memorySamples
        idleSeconds = Get-UserIdleSeconds
        batteryPercent = $batteryPercent
        charging = $charging
        reason = 'normal'
    }
}

function Resolve-SystemMood {
    param([Parameter(Mandatory = $true)]$Metrics)

    $cpu = [double]$Metrics.cpu
    $memory = [double]$Metrics.memory
    $idleSeconds = [double]$Metrics.idleSeconds
    $batteryPercent = $Metrics.batteryPercent
    $charging = $Metrics.charging

    if ($script:lastIdleSeconds -ge 300 -and $idleSeconds -le 10) {
        return [ordered]@{ state = 'waving'; temporaryMs = 1800; reason = 'welcome_back' }
    }
    if ($batteryPercent -ne $null -and [int]$batteryPercent -le 15 -and $charging -eq $false) {
        return [ordered]@{ state = 'waiting'; temporaryMs = 0; reason = 'low_battery' }
    }
    if ($cpu -ge 95 -and $memory -ge 90) {
        return [ordered]@{ state = 'failed'; temporaryMs = 0; reason = 'system_pressure' }
    }
    if ($memory -ge 88) {
        return [ordered]@{ state = 'waiting'; temporaryMs = 0; reason = 'high_memory' }
    }
    if ($cpu -ge 82) {
        return [ordered]@{ state = 'running'; temporaryMs = 0; reason = 'high_cpu' }
    }
    if ($idleSeconds -ge 300) {
        return [ordered]@{ state = 'idle'; temporaryMs = 0; reason = 'user_idle' }
    }
    return [ordered]@{ state = 'idle'; temporaryMs = 0; reason = 'normal' }
}

function Update-SystemMonitor {
    if (-not $script:systemMonitorEnabled) {
        return
    }
    if ($script:isMouseDown -or $script:isDragging -or $script:temporaryUntil -ne $null) {
        return
    }

    $careMood = Resolve-CareMood
    if ($careMood.reason -notin @('balanced', 'low_energy', 'no_pet')) {
        return
    }

    $metrics = Get-SystemMetrics
    $mood = Resolve-SystemMood $metrics
    $metrics.reason = $mood.reason
    $script:lastSystemMetrics = $metrics

    $now = [DateTime]::Now
    $canChange = (($now - $script:lastSystemStateChange).TotalSeconds -ge $script:systemStateHoldSeconds)
    if ($mood.state -ne $script:lastSystemMood -and -not $canChange) {
        $script:lastIdleSeconds = [double]$metrics.idleSeconds
        return
    }

    if ($mood.state -ne $script:currentState -or $mood.temporaryMs -gt 0) {
        Set-PetState ([string]$mood.state) ([int]$mood.temporaryMs)
        $script:lastSystemStateChange = $now
        $script:lastSystemMood = [string]$mood.state
    }
    $script:lastIdleSeconds = [double]$metrics.idleSeconds
}

function Start-SystemMonitor {
    if ($script:systemMonitorTimer -ne $null) {
        return
    }
    $script:systemMonitorTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:systemMonitorTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:systemMonitorTimer.Add_Tick({ Update-SystemMonitor })
    $script:systemMonitorTimer.Start()
    Update-SystemMonitor
}

function Stop-SystemMonitor {
    if ($script:systemMonitorTimer -ne $null) {
        try {
            $script:systemMonitorTimer.Stop()
        }
        catch {
        }
        $script:systemMonitorTimer = $null
    }
}

function Set-SystemMonitorEnabled {
    param([bool]$Enabled)

    $script:systemMonitorEnabled = $Enabled
    if ($Enabled) {
        $script:lastSystemStateChange = [DateTime]::MinValue
        Update-SystemMonitor
    }
    else {
        Set-PetState 'idle'
    }
    Build-ContextMenu
    Build-TrayMenu
    Save-Settings
}

function Format-SystemStatus {
    $metrics = $script:lastSystemMetrics
    $battery = ''
    if ($metrics.batteryPercent -ne $null) {
        $battery = ", BAT $($metrics.batteryPercent)%"
    }
    return "CPU $($metrics.cpu)%, RAM $($metrics.memory)%$battery"
}

function Update-CareMonitor {
    if ($script:isMouseDown -or $script:isDragging -or $script:temporaryUntil -ne $null) {
        return
    }

    $careMood = Resolve-CareMood
    $script:lastCareReason = [string]$careMood.reason
    if ($careMood.reason -eq 'balanced') {
        return
    }
    if ($careMood.state -ne $script:currentState -or $careMood.temporaryMs -gt 0) {
        Set-PetState ([string]$careMood.state) ([int]$careMood.temporaryMs)
    }
}

function Start-CareMonitor {
    if ($script:careTimer -ne $null) {
        return
    }
    $script:careTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:careTimer.Interval = [TimeSpan]::FromSeconds(30)
    $script:careTimer.Add_Tick({ Update-CareMonitor })
    $script:careTimer.Start()
    Update-CareMonitor
}

function Stop-CareMonitor {
    if ($script:careTimer -ne $null) {
        try {
            $script:careTimer.Stop()
        }
        catch {
        }
        $script:careTimer = $null
    }
}

function New-MenuItem {
    param(
        [string]$Header,
        [scriptblock]$Action
    )

    $item = [System.Windows.Controls.MenuItem]::new()
    $item.Header = $Header
    $item.Add_Click($Action)
    return $item
}

function New-PetsMenu {
    $petMenu = [System.Windows.Controls.MenuItem]::new()
    $petMenu.Header = T 'pets'

    foreach ($dir in Get-AvailablePets) {
        $petPath = $dir.FullName
        $info = Get-PetInfo $petPath
        $label = $info.displayName
        if ($info.id -eq $script:activePetId) {
            $label = "$label *"
        }
        $action = {
        Load-Pet $petPath
            Set-PetState 'idle'
            Build-ContextMenu
            Build-TrayMenu
            Update-PetFrame
        }.GetNewClosure()
        [void]$petMenu.Items.Add((New-MenuItem $label $action))
    }

    if ($petMenu.Items.Count -eq 0) {
        $empty = [System.Windows.Controls.MenuItem]::new()
        $empty.Header = T 'noPets'
        $empty.IsEnabled = $false
        [void]$petMenu.Items.Add($empty)
    }

    return $petMenu
}

function New-LanguageMenu {
    $languageMenu = [System.Windows.Controls.MenuItem]::new()
    $languageMenu.Header = T 'language'

    $zhLabel = T 'chinese'
    if ($script:language -eq 'zh-CN') {
        $zhLabel = "$zhLabel *"
    }
    [void]$languageMenu.Items.Add((New-MenuItem $zhLabel {
        $script:language = 'zh-CN'
        Build-ContextMenu
        Build-TrayMenu
        Save-Settings
    }))

    $enLabel = T 'english'
    if ($script:language -eq 'en-US') {
        $enLabel = "$enLabel *"
    }
    [void]$languageMenu.Items.Add((New-MenuItem $enLabel {
        $script:language = 'en-US'
        Build-ContextMenu
        Build-TrayMenu
        Save-Settings
    }))

    return $languageMenu
}

function Build-ContextMenu {
    $menu = [System.Windows.Controls.ContextMenu]::new()
    [void]$menu.Items.Add((New-PetsMenu))
    [void]$menu.Items.Add((New-LanguageMenu))
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add((New-MenuItem (T 'idle') { Set-PetState 'idle' }))
    [void]$menu.Items.Add((New-MenuItem (T 'waiting') { Set-PetState 'waiting' }))
    [void]$menu.Items.Add((New-MenuItem (T 'runningTask') { Set-PetState 'running' }))
    [void]$menu.Items.Add((New-MenuItem (T 'review') { Set-PetState 'review' }))
    [void]$menu.Items.Add((New-MenuItem (T 'failed') { Set-PetState 'failed' }))
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    $careStatusItem = [System.Windows.Controls.MenuItem]::new()
    $careStatusItem.Header = "$(T 'careStatus'): $(Format-CareLine)"
    $careStatusItem.IsEnabled = $false
    [void]$menu.Items.Add($careStatusItem)
    [void]$menu.Items.Add((New-MenuItem (T 'feed') { Invoke-CareAction 'feed' }))
    [void]$menu.Items.Add((New-MenuItem (T 'clean') { Invoke-CareAction 'clean' }))
    [void]$menu.Items.Add((New-MenuItem (T 'bath') { Invoke-CareAction 'bath' }))
    [void]$menu.Items.Add((New-MenuItem (T 'play') { Invoke-CareAction 'play' }))
    [void]$menu.Items.Add((New-MenuItem (T 'rest') { Invoke-CareAction 'rest' }))
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    $lockLabel = if ($script:locked) { T 'unlockMove' } else { T 'lockMove' }
    [void]$menu.Items.Add((New-MenuItem $lockLabel {
        $script:locked = -not $script:locked
        Build-ContextMenu
        Build-TrayMenu
        Save-Settings
    }))
    $autoStartLabel = if (Get-AutoStartEnabled) { T 'autoStartOff' } else { T 'autoStartOn' }
    [void]$menu.Items.Add((New-MenuItem $autoStartLabel {
        Set-AutoStart (-not (Get-AutoStartEnabled))
        Build-ContextMenu
        Build-TrayMenu
    }))
    $systemLabel = if ($script:systemMonitorEnabled) { T 'systemLinkOff' } else { T 'systemLinkOn' }
    [void]$menu.Items.Add((New-MenuItem $systemLabel {
        Set-SystemMonitorEnabled (-not $script:systemMonitorEnabled)
    }))
    $systemStatusItem = [System.Windows.Controls.MenuItem]::new()
    $systemStatusItem.Header = "$(T 'systemStatus'): $(Format-SystemStatus)"
    $systemStatusItem.IsEnabled = $false
    [void]$menu.Items.Add($systemStatusItem)
    $apiLabel = "$(T 'apiStatus'): http://127.0.0.1:$ApiPort/state"
    $apiItem = [System.Windows.Controls.MenuItem]::new()
    $apiItem.Header = $apiLabel
    $apiItem.IsEnabled = $false
    [void]$menu.Items.Add($apiItem)
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add((New-MenuItem (T 'bigger') { Set-PetScale (($script:window.Width / $cellWidth) + 0.15) }))
    [void]$menu.Items.Add((New-MenuItem (T 'smaller') { Set-PetScale (($script:window.Width / $cellWidth) - 0.15) }))
    [void]$menu.Items.Add((New-MenuItem (T 'toggleTopmost') { $script:window.Topmost = -not $script:window.Topmost; Save-Settings }))
    [void]$menu.Items.Add([System.Windows.Controls.Separator]::new())
    [void]$menu.Items.Add((New-MenuItem (T 'exit') { $script:window.Close() }))
    $script:petImage.ContextMenu = $menu
}

function New-TrayItem {
    param(
        [string]$Text,
        [scriptblock]$Action
    )

    $item = [System.Windows.Forms.ToolStripMenuItem]::new($Text)
    [void]$item.add_Click($Action)
    return $item
}

function Build-TrayMenu {
    if ($script:notifyIcon -eq $null) {
        return
    }

    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    [void]$menu.Items.Add((New-TrayItem (T 'show') { $script:window.Show(); $script:window.Activate() }))
    [void]$menu.Items.Add((New-TrayItem (T 'hide') { $script:window.Hide() }))
    [void]$menu.Items.Add((New-TrayItem (T 'idle') { Set-PetState 'idle' }))
    [void]$menu.Items.Add((New-TrayItem (T 'waiting') { Set-PetState 'waiting' }))
    [void]$menu.Items.Add((New-TrayItem (T 'runningTask') { Set-PetState 'running' }))
    [void]$menu.Items.Add((New-TrayItem (T 'review') { Set-PetState 'review' }))
    [void]$menu.Items.Add((New-TrayItem (T 'failed') { Set-PetState 'failed' }))
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add((New-TrayItem (T 'feed') { Invoke-CareAction 'feed' }))
    [void]$menu.Items.Add((New-TrayItem (T 'bath') { Invoke-CareAction 'bath' }))
    [void]$menu.Items.Add((New-TrayItem (T 'play') { Invoke-CareAction 'play' }))
    [void]$menu.Items.Add((New-TrayItem (T 'rest') { Invoke-CareAction 'rest' }))
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $systemLabel = if ($script:systemMonitorEnabled) { T 'systemLinkOff' } else { T 'systemLinkOn' }
    [void]$menu.Items.Add((New-TrayItem $systemLabel {
        Set-SystemMonitorEnabled (-not $script:systemMonitorEnabled)
    }))
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    [void]$menu.Items.Add((New-TrayItem (T 'exit') { $script:window.Close() }))
    $script:notifyIcon.ContextMenuStrip = $menu
}

function Initialize-Tray {
    $script:notifyIcon = [System.Windows.Forms.NotifyIcon]::new()
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $script:notifyIcon.Text = 'Desktop Pet'
    $script:notifyIcon.Visible = $true
    $script:notifyIcon.add_DoubleClick({ $script:window.Show(); $script:window.Activate() })
    Build-TrayMenu
}

function Send-ApiResponse {
    param(
        [Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$StatusCode = 200
    )

    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers['Access-Control-Allow-Origin'] = '*'
    $Context.Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    $Context.Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Get-ApiRequestState {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerRequest]$Request)

    $state = $Request.QueryString['state']
    if (-not [string]::IsNullOrWhiteSpace($state)) {
        return [string]$state
    }

    if (-not $Request.HasEntityBody) {
        return ''
    }

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        return ''
    }

    try {
        $json = $body | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains 'state') {
            return [string]$json.state
        }
    }
    catch {
        return $body.Trim()
    }

    return ''
}

function Get-ApiRequestCareAction {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerRequest]$Request)

    $careAction = $Request.QueryString['care']
    if ([string]::IsNullOrWhiteSpace($careAction)) {
        $careAction = $Request.QueryString['action']
    }
    if (-not [string]::IsNullOrWhiteSpace($careAction)) {
        return [string]$careAction
    }

    if (-not $Request.HasEntityBody) {
        return ''
    }

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        return ''
    }

    try {
        $json = $body | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains 'care') {
            return [string]$json.care
        }
        if ($json.PSObject.Properties.Name -contains 'action') {
            return [string]$json.action
        }
    }
    catch {
        return $body.Trim()
    }

    return ''
}

function Get-ApiStatePayload {
    Update-CareDecay
    return [ordered]@{
        ok = $true
        petId = $script:activePetId
        petName = $script:activePetName
        state = $script:currentState
        language = $script:language
        locked = [bool]$script:locked
        topmost = [bool]$script:window.Topmost
        scale = [Math]::Round(($script:window.Width / $cellWidth), 2)
        systemMonitorEnabled = [bool]$script:systemMonitorEnabled
        metrics = $script:lastSystemMetrics
        care = $script:careState
        careReason = $script:lastCareReason
    }
}

function Complete-ApiRequest {
    param([Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $path = $request.Url.AbsolutePath.Trim('/').ToLowerInvariant()

    if ($request.HttpMethod -eq 'OPTIONS') {
        Send-ApiResponse $Context ([ordered]@{ ok = $true })
        return
    }

    if ($path -ne '' -and $path -ne 'state' -and $path -ne 'action' -and $path -ne 'care') {
        Send-ApiResponse $Context ([ordered]@{ ok = $false; error = 'not_found' }) 404
        return
    }

    if ($path -eq 'care') {
        $careAction = Get-ApiRequestCareAction $request
        if ([string]::IsNullOrWhiteSpace($careAction)) {
            Send-ApiResponse $Context (Get-ApiStatePayload)
            return
        }
        if (@('feed', 'clean', 'bath', 'play', 'rest') -notcontains $careAction) {
            Send-ApiResponse $Context ([ordered]@{ ok = $false; error = 'unknown_care_action'; action = $careAction }) 400
            return
        }
        Invoke-CareAction $careAction
        Send-ApiResponse $Context (Get-ApiStatePayload)
        return
    }

    $requestedState = Get-ApiRequestState $request
    if (-not [string]::IsNullOrWhiteSpace($requestedState)) {
        if ([string]::IsNullOrWhiteSpace((Resolve-PetStateName $requestedState))) {
            Send-ApiResponse $Context ([ordered]@{ ok = $false; error = 'unknown_state'; state = $requestedState }) 400
            return
        }
        Set-PetState $requestedState 3000
    }

    Send-ApiResponse $Context (Get-ApiStatePayload)
}

function Request-NextApiContext {
    if ($script:apiListener -eq $null -or -not $script:apiListener.IsListening) {
        return
    }
    if ($script:apiPendingContext -eq $null) {
        $script:apiPendingContext = $script:apiListener.GetContextAsync()
    }
}

function Start-LocalApi {
    if (-not $script:apiEnabled) {
        return
    }

    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$ApiPort/")
        $listener.Start()
        $script:apiListener = $listener
        Request-NextApiContext

        $script:apiTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:apiTimer.Interval = [TimeSpan]::FromMilliseconds(100)
        $script:apiTimer.Add_Tick({
            if ($script:apiListener -eq $null -or -not $script:apiListener.IsListening) {
                return
            }
            if ($script:apiPendingContext -eq $null) {
                Request-NextApiContext
                return
            }
            if (-not $script:apiPendingContext.IsCompleted) {
                return
            }

            $task = $script:apiPendingContext
            $script:apiPendingContext = $null
            try {
                $context = $task.GetAwaiter().GetResult()
                Request-NextApiContext
                Complete-ApiRequest $context
            }
            catch {
                Request-NextApiContext
            }
        })
        $script:apiTimer.Start()
    }
    catch {
        $script:apiEnabled = $false
    }
}

function Stop-LocalApi {
    if ($script:apiTimer -ne $null) {
        try {
            $script:apiTimer.Stop()
        }
        catch {
        }
        $script:apiTimer = $null
    }
    $script:apiPendingContext = $null
    if ($script:apiListener -ne $null) {
        try {
            $script:apiListener.Stop()
            $script:apiListener.Close()
        }
        catch {
        }
        $script:apiListener = $null
    }
}

$initialPetDir = $PetDir
if ([string]::IsNullOrWhiteSpace($initialPetDir)) {
    $script:settings = Load-Settings
    $script:language = [string]$script:settings.language
    $Scale = [double]$script:settings.scale
    $script:locked = [bool]$script:settings.locked
    $script:apiEnabled = [bool]$script:settings.apiEnabled
    $ApiPort = [int]$script:settings.apiPort
    if ($script:settings.PSObject.Properties.Name -contains 'systemMonitorEnabled') {
        $script:systemMonitorEnabled = [bool]$script:settings.systemMonitorEnabled
    }
    if (-not $script:launchParameters.ContainsKey('PetId')) {
        $PetId = [string]$script:settings.petId
    }
    $initialPetDir = Join-Path $PetRoot $PetId
}
else {
    $script:settings = Load-Settings
}
if ($script:settings.PSObject.Properties.Name -contains 'systemMonitorEnabled') {
    $script:systemMonitorEnabled = [bool]$script:settings.systemMonitorEnabled
}

$script:window = [System.Windows.Window]::new()
$script:window.Title = 'Desktop Pet'
$script:window.Width = $cellWidth * $Scale
$script:window.Height = $cellHeight * $Scale
$script:window.WindowStyle = [System.Windows.WindowStyle]::None
$script:window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$script:window.AllowsTransparency = $true
$script:window.Background = [System.Windows.Media.Brushes]::Transparent
$script:window.Topmost = -not $NotTopmost
$script:window.ShowInTaskbar = $false
$script:window.Left = [double]$script:settings.left
$script:window.Top = [double]$script:settings.top
$script:window.Topmost = [bool]$script:settings.topmost
if ($NotTopmost) {
    $script:window.Topmost = $false
}

$script:petImage = [System.Windows.Controls.Image]::new()
$script:petImage.Width = $script:window.Width
$script:petImage.Height = $script:window.Height
$script:petImage.Stretch = [System.Windows.Media.Stretch]::Fill
$script:petImage.SnapsToDevicePixels = $true
$script:window.Content = $script:petImage

Load-Pet $initialPetDir

Build-ContextMenu
Initialize-Tray
Start-LocalApi
Start-CareMonitor
Start-SystemMonitor

$script:petImage.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)

    if ($eventArgs.ClickCount -ge 2) {
        Set-PetState 'jumping' 900
        $eventArgs.Handled = $true
        return
    }

    if ($script:locked) {
        Set-PetState 'waving' 900
        $eventArgs.Handled = $true
        return
    }

    $script:isMouseDown = $true
    $script:isDragging = $false
    $script:startCursor = [System.Windows.Forms.Cursor]::Position
    $script:startLeft = $script:window.Left
    $script:startTop = $script:window.Top
    [void]$script:petImage.CaptureMouse()
    $eventArgs.Handled = $true
})

$script:petImage.Add_MouseMove({
    param($sender, $eventArgs)

    if (-not $script:isMouseDown) {
        return
    }
    if ($script:locked) {
        return
    }

    $cursor = [System.Windows.Forms.Cursor]::Position
    $dx = $cursor.X - $script:startCursor.X
    $dy = $cursor.Y - $script:startCursor.Y
    if (-not $script:isDragging -and ([Math]::Abs($dx) + [Math]::Abs($dy)) -lt 4) {
        return
    }

    $script:isDragging = $true
    $script:window.Left = $script:startLeft + $dx
    $script:window.Top = $script:startTop + $dy
    if ($dx -lt -1) {
        $script:lastDragDirection = 'running-left'
    }
    elseif ($dx -gt 1) {
        $script:lastDragDirection = 'running-right'
    }
    Set-PetState $script:lastDragDirection
})

$script:petImage.Add_MouseLeftButtonUp({
    param($sender, $eventArgs)

    if ($script:isMouseDown) {
        $script:isMouseDown = $false
        [void]$script:petImage.ReleaseMouseCapture()
        if ($script:isDragging) {
            $script:isDragging = $false
            Set-PetState 'idle'
            Save-Settings
        }
        else {
            Set-PetState 'waving' 900
        }
    }
    $eventArgs.Handled = $true
})

$script:timer = [System.Windows.Threading.DispatcherTimer]::new()
$script:timer.Interval = [TimeSpan]::FromMilliseconds(160)
$script:timer.Add_Tick({ Update-PetFrame })
$script:timer.Start()

$script:window.Add_Closed({
    Save-Settings
    Stop-CareMonitor
    Stop-SystemMonitor
    Stop-LocalApi
    if ($script:notifyIcon -ne $null) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    $script:timer.Stop()
})
Update-PetFrame
[void]$script:window.ShowDialog()


