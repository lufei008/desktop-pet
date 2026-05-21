param(
    [ValidateSet('validate-config', 'new-request', 'generate', 'validate-output', 'install')]
    [string]$Command = 'new-request',
    [string]$PetId = '',
    [string]$DisplayName = '',
    [string]$Description = '',
    [string]$ReferenceImage = '',
    [string]$Style = 'sticker',
    [string]$Provider = 'unset',
    [string]$RunDir = '',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'model-config.example.json'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'runs'),
    [string]$AssetRoot = (Join-Path $PSScriptRoot '..\assets'),
    [switch]$Install,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$cellWidth = 192
$cellHeight = 208
$atlasWidth = 1536
$atlasHeight = 1872

$stateDefinitions = @(
    [ordered]@{ name = 'idle'; row = 0; frames = 6 },
    [ordered]@{ name = 'running-right'; row = 1; frames = 8 },
    [ordered]@{ name = 'running-left'; row = 2; frames = 8 },
    [ordered]@{ name = 'waving'; row = 3; frames = 4 },
    [ordered]@{ name = 'jumping'; row = 4; frames = 5 },
    [ordered]@{ name = 'failed'; row = 5; frames = 8 },
    [ordered]@{ name = 'waiting'; row = 6; frames = 6 },
    [ordered]@{ name = 'running'; row = 7; frames = 6 },
    [ordered]@{ name = 'review'; row = 8; frames = 6 }
)

function Get-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if ($Object -ne $null -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $slug = $Value.ToLowerInvariant()
    $slug = [Regex]::Replace($slug, '[^a-z0-9._-]+', '-')
    $slug = $slug.Trim('.', '-', '_')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "pet-$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
    }
    if ($slug -notmatch '^[a-z0-9]') {
        $slug = "pet-$slug"
    }
    if ($slug.Length -gt 64) {
        $slug = $slug.Substring(0, 64).Trim('.', '-', '_')
    }
    return $slug
}

function Read-ModelConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing model config: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Validate-ModelConfig {
    param([Parameter(Mandatory = $true)]$Config)

    $errors = [System.Collections.Generic.List[string]]::new()
    $providerNames = @()

    if (-not ($Config.PSObject.Properties.Name -contains 'providers')) {
        $errors.Add('config must contain providers')
    }
    else {
        $providerNames = @($Config.providers.PSObject.Properties.Name)
        foreach ($property in $Config.providers.PSObject.Properties) {
            $provider = $property.Value
            $kind = [string](Get-JsonProperty $provider 'kind' '')
            $displayName = [string](Get-JsonProperty $provider 'displayName' '')
            if ([string]::IsNullOrWhiteSpace($kind)) {
                $errors.Add("provider '$($property.Name)' must contain kind")
            }
            elseif (@('local-template', 'command', 'manual') -notcontains $kind) {
                $errors.Add("provider '$($property.Name)' has unsupported kind '$kind'")
            }
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $errors.Add("provider '$($property.Name)' must contain displayName")
            }
        }
    }

    $defaultProvider = [string](Get-JsonProperty $Config 'defaultProvider' '')
    if ([string]::IsNullOrWhiteSpace($defaultProvider)) {
        $errors.Add('config must contain defaultProvider')
    }
    elseif ($providerNames -notcontains $defaultProvider) {
        $errors.Add("defaultProvider '$defaultProvider' is not defined in providers")
    }

    if ($errors.Count -gt 0) {
        throw ($errors -join [Environment]::NewLine)
    }
    return $true
}

function Resolve-Provider {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RequestedProvider
    )

    $resolvedProvider = $RequestedProvider
    if ($resolvedProvider -eq 'unset') {
        $resolvedProvider = [string]$Config.defaultProvider
    }
    if (-not ($Config.providers.PSObject.Properties.Name -contains $resolvedProvider)) {
        throw "Provider '$resolvedProvider' not found in $ConfigPath"
    }

    return [ordered]@{
        name = $resolvedProvider
        config = $Config.providers.$resolvedProvider
    }
}

function New-PetRequest {
    if ([string]::IsNullOrWhiteSpace($DisplayName) -and [string]::IsNullOrWhiteSpace($Description)) {
        throw 'Provide at least -DisplayName or -Description.'
    }

    $config = Read-ModelConfig $ConfigPath
    [void](Validate-ModelConfig $config)
    $resolvedProvider = Resolve-Provider $config $Provider

    $resolvedDisplayName = $DisplayName
    if ([string]::IsNullOrWhiteSpace($resolvedDisplayName)) {
        $resolvedDisplayName = $Description
    }

    $resolvedPetId = $PetId
    if ([string]::IsNullOrWhiteSpace($resolvedPetId)) {
        $resolvedPetId = Convert-ToSlug $resolvedDisplayName
    }
    else {
        $resolvedPetId = Convert-ToSlug $resolvedPetId
    }

    $timestamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
    $runDirectory = Join-Path $OutputRoot "$resolvedPetId-$timestamp"
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $runDirectory 'references') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $runDirectory 'outputs') | Out-Null

    $referencePath = ''
    if (-not [string]::IsNullOrWhiteSpace($ReferenceImage)) {
        $resolvedReference = Resolve-Path -LiteralPath $ReferenceImage
        $target = Join-Path (Join-Path $runDirectory 'references') (Split-Path -Leaf $resolvedReference.Path)
        Copy-Item -LiteralPath $resolvedReference.Path -Destination $target -Force
        $referencePath = "references/$([IO.Path]::GetFileName($target))"
    }

    $request = [ordered]@{
        schemaVersion = 1
        createdAt = [DateTimeOffset]::Now.ToString('o')
        petId = $resolvedPetId
        displayName = $resolvedDisplayName
        description = $Description
        style = $Style
        referenceImage = $referencePath
        provider = $resolvedProvider.name
        outputContract = [ordered]@{
            atlasWidth = $atlasWidth
            atlasHeight = $atlasHeight
            columns = 8
            rows = 9
            cellWidth = $cellWidth
            cellHeight = $cellHeight
            requiredFiles = @('pet.json', 'spritesheet.png')
            optionalFiles = @('spritesheet.webp', 'preview.png')
        }
        states = $stateDefinitions
        notes = 'Provider-agnostic request. Generate a transparent 1536x1872 atlas and pet.json under outputs/.'
    }

    $requestPath = Join-Path $runDirectory 'pet-request.json'
    Set-Content -LiteralPath $requestPath -Value ($request | ConvertTo-Json -Depth 20) -Encoding UTF8

    return [pscustomobject]@{
        ok = $true
        runDir = (Resolve-Path -LiteralPath $runDirectory).Path
        request = (Resolve-Path -LiteralPath $requestPath).Path
        provider = $resolvedProvider.name
    }
}

function Read-RunRequest {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        throw 'Provide -RunDir.'
    }
    $requestPath = Join-Path $Directory 'pet-request.json'
    if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
        throw "Missing request file: $requestPath"
    }
    return Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
}

function Get-RunOutputDir {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $outputDir = Join-Path $Directory 'outputs'
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    return $outputDir
}

function Get-ReferencePath {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)]$Request
    )

    $reference = [string](Get-JsonProperty $Request 'referenceImage' '')
    if ([string]::IsNullOrWhiteSpace($reference)) {
        return ''
    }
    return Join-Path $Directory $reference.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-TemplatePalette {
    param([Parameter(Mandatory = $true)]$Request)

    $text = "$($Request.displayName) $($Request.description) $($Request.style)".ToLowerInvariant()
    if ($text -match 'bulldog|斗牛') {
        return [ordered]@{
            body = [System.Drawing.Color]::FromArgb(250, 248, 240)
            patch = [System.Drawing.Color]::FromArgb(187, 122, 58)
            accent = [System.Drawing.Color]::FromArgb(63, 96, 155)
            muzzle = [System.Drawing.Color]::FromArgb(239, 201, 196)
            outline = [System.Drawing.Color]::FromArgb(54, 46, 43)
        }
    }
    if ($text -match 'shiba|柴') {
        return [ordered]@{
            body = [System.Drawing.Color]::FromArgb(231, 126, 45)
            patch = [System.Drawing.Color]::FromArgb(255, 238, 204)
            accent = [System.Drawing.Color]::FromArgb(80, 143, 166)
            muzzle = [System.Drawing.Color]::FromArgb(255, 235, 209)
            outline = [System.Drawing.Color]::FromArgb(67, 45, 30)
        }
    }
    if ($text -match 'cat|猫') {
        return [ordered]@{
            body = [System.Drawing.Color]::FromArgb(196, 199, 204)
            patch = [System.Drawing.Color]::FromArgb(245, 245, 242)
            accent = [System.Drawing.Color]::FromArgb(224, 113, 126)
            muzzle = [System.Drawing.Color]::FromArgb(247, 224, 219)
            outline = [System.Drawing.Color]::FromArgb(54, 54, 58)
        }
    }

    $palettes = @(
        [ordered]@{ body = [System.Drawing.Color]::FromArgb(112, 162, 132); patch = [System.Drawing.Color]::FromArgb(242, 237, 211); accent = [System.Drawing.Color]::FromArgb(232, 174, 73); muzzle = [System.Drawing.Color]::FromArgb(245, 221, 205); outline = [System.Drawing.Color]::FromArgb(42, 55, 48) },
        [ordered]@{ body = [System.Drawing.Color]::FromArgb(129, 151, 199); patch = [System.Drawing.Color]::FromArgb(243, 244, 247); accent = [System.Drawing.Color]::FromArgb(222, 117, 86); muzzle = [System.Drawing.Color]::FromArgb(236, 217, 208); outline = [System.Drawing.Color]::FromArgb(38, 47, 70) },
        [ordered]@{ body = [System.Drawing.Color]::FromArgb(207, 145, 91); patch = [System.Drawing.Color]::FromArgb(252, 240, 214); accent = [System.Drawing.Color]::FromArgb(71, 132, 142); muzzle = [System.Drawing.Color]::FromArgb(246, 220, 202); outline = [System.Drawing.Color]::FromArgb(66, 49, 35) }
    )
    $sum = 0
    foreach ($byte in [Text.Encoding]::UTF8.GetBytes($text)) {
        $sum += $byte
    }
    return $palettes[$sum % $palettes.Count]
}

function New-SolidBrush {
    param([Parameter(Mandatory = $true)][System.Drawing.Color]$Color)
    return [System.Drawing.SolidBrush]::new($Color)
}

function Draw-Ellipse {
    param($Graphics, $Brush, $Pen, [float]$X, [float]$Y, [float]$W, [float]$H)
    $Graphics.FillEllipse($Brush, $X, $Y, $W, $H)
    $Graphics.DrawEllipse($Pen, $X, $Y, $W, $H)
}

function Draw-TemplateFrame {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]$Palette,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][int]$Frame,
        [Parameter(Mandatory = $true)][int]$FrameCount,
        [Parameter(Mandatory = $true)][int]$CellX,
        [Parameter(Mandatory = $true)][int]$CellY,
        [Parameter(Mandatory = $true)]$Request
    )

    $phase = (2 * [Math]::PI * $Frame) / [Math]::Max(1, $FrameCount)
    $bob = [Math]::Sin($phase) * 2.5
    $lean = 0
    $jump = 0
    $direction = 1
    $pawWave = $false
    $sad = $false
    $focused = $false

    switch ($State) {
        'running-right' { $lean = 7; $direction = 1; $bob = [Math]::Sin($phase) * 4 }
        'running-left' { $lean = -7; $direction = -1; $bob = [Math]::Sin($phase) * 4 }
        'waving' { $pawWave = $true; $bob = [Math]::Sin($phase) * 2 }
        'jumping' { $jump = -[Math]::Abs([Math]::Sin($phase)) * 26; $bob = 0 }
        'failed' { $sad = $true; $bob = 8 }
        'waiting' { $bob = [Math]::Sin($phase) * 3; $lean = [Math]::Sin($phase) * 3 }
        'running' { $focused = $true; $bob = [Math]::Sin($phase) * 3 }
        'review' { $focused = $true; $lean = [Math]::Sin($phase) * 4 }
    }

    $cx = [float]($CellX + 96 + $lean)
    $cy = [float]($CellY + 106 + $bob + $jump)
    $outlinePen = [System.Drawing.Pen]::new($Palette.outline, 4)
    $bodyBrush = New-SolidBrush $Palette.body
    $patchBrush = New-SolidBrush $Palette.patch
    $accentBrush = New-SolidBrush $Palette.accent
    $muzzleBrush = New-SolidBrush $Palette.muzzle
    $eyeBrush = New-SolidBrush $Palette.outline
    $whiteBrush = New-SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255))

    try {
        $earLeft = @(
            [System.Drawing.PointF]::new($cx - 42, $cy - 52),
            [System.Drawing.PointF]::new($cx - 20, $cy - 83),
            [System.Drawing.PointF]::new($cx - 6, $cy - 45)
        )
        $earRight = @(
            [System.Drawing.PointF]::new($cx + 42, $cy - 52),
            [System.Drawing.PointF]::new($cx + 20, $cy - 83),
            [System.Drawing.PointF]::new($cx + 6, $cy - 45)
        )
        $Graphics.FillPolygon($patchBrush, $earLeft)
        $Graphics.DrawPolygon($outlinePen, $earLeft)
        $Graphics.FillPolygon($patchBrush, $earRight)
        $Graphics.DrawPolygon($outlinePen, $earRight)

        Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx - 42) ($cy + 12) 84 78
        Draw-Ellipse $Graphics $patchBrush $outlinePen ($cx - 51) ($cy + 40) 31 36
        Draw-Ellipse $Graphics $patchBrush $outlinePen ($cx + 20) ($cy + 40) 31 36
        Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx - 47) ($cy - 54) 94 76
        Draw-Ellipse $Graphics $patchBrush $outlinePen ($cx - 43) ($cy - 46) 38 46

        if ($pawWave) {
            $pawX = $cx + (36 * $direction)
            Draw-Ellipse $Graphics $bodyBrush $outlinePen ($pawX - 11) ($cy - 46 + ([Math]::Sin($phase) * 5)) 22 34
        }
        else {
            Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx - 49) ($cy + 29 + ([Math]::Sin($phase) * 3)) 22 40
            Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx + 27) ($cy + 29 - ([Math]::Sin($phase) * 3)) 22 40
        }

        Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx - 36) ($cy + 73) 27 18
        Draw-Ellipse $Graphics $bodyBrush $outlinePen ($cx + 9) ($cy + 73) 27 18
        Draw-Ellipse $Graphics $muzzleBrush $outlinePen ($cx - 28) ($cy - 19) 56 34
        Draw-Ellipse $Graphics $eyeBrush $outlinePen ($cx - 21) ($cy - 27) 8 8
        Draw-Ellipse $Graphics $eyeBrush $outlinePen ($cx + 13) ($cy - 27) 8 8
        Draw-Ellipse $Graphics $eyeBrush $outlinePen ($cx - 8) ($cy - 12) 16 12

        if ($sad) {
            $Graphics.DrawArc($outlinePen, ($cx - 14), ($cy + 4), 28, 18, 200, 140)
        }
        else {
            $Graphics.DrawArc($outlinePen, ($cx - 15), ($cy - 2), 30, 22, 20, 140)
        }

        if ($focused) {
            $Graphics.DrawLine($outlinePen, ($cx - 26), ($cy - 39), ($cx - 12), ($cy - 34))
            $Graphics.DrawLine($outlinePen, ($cx + 26), ($cy - 39), ($cx + 12), ($cy - 34))
        }

        $text = "$($Request.displayName) $($Request.description)".ToLowerInvariant()
        if ($text -match 'hat|cap|帽') {
            $Graphics.FillRectangle($accentBrush, ($cx - 35), ($cy - 66), 70, 16)
            $Graphics.DrawRectangle($outlinePen, ($cx - 35), ($cy - 66), 70, 16)
            $Graphics.FillEllipse($accentBrush, ($cx + 18), ($cy - 63), 38, 13)
            $Graphics.DrawEllipse($outlinePen, ($cx + 18), ($cy - 63), 38, 13)
        }

        Draw-Ellipse $Graphics $accentBrush $outlinePen ($cx - 16) ($cy + 17) 32 12
        Draw-Ellipse $Graphics $whiteBrush $outlinePen ($cx - 5) ($cy + 18) 10 10
    }
    finally {
        $outlinePen.Dispose()
        $bodyBrush.Dispose()
        $patchBrush.Dispose()
        $accentBrush.Dispose()
        $muzzleBrush.Dispose()
        $eyeBrush.Dispose()
        $whiteBrush.Dispose()
    }
}

function Invoke-LocalTemplateGenerator {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    Add-Type -AssemblyName System.Drawing

    $palette = Get-TemplatePalette $Request
    $bitmap = [System.Drawing.Bitmap]::new($atlasWidth, $atlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        foreach ($state in $stateDefinitions) {
            for ($frame = 0; $frame -lt [int]$state.frames; $frame++) {
                Draw-TemplateFrame $graphics $palette ([string]$state.name) $frame ([int]$state.frames) ($frame * $cellWidth) ([int]$state.row * $cellHeight) $Request
            }
        }

        $spritePath = Join-Path $OutputDir 'spritesheet.png'
        $bitmap.Save($spritePath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $petJson = [ordered]@{
        id = [string]$Request.petId
        displayName = [string]$Request.displayName
        description = [string]$Request.description
        spritesheetPath = 'spritesheet.png'
        generatedBy = 'local-template'
        generatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Set-Content -LiteralPath (Join-Path $OutputDir 'pet.json') -Value ($petJson | ConvertTo-Json -Depth 10) -Encoding UTF8

    return [pscustomobject]@{
        ok = $true
        provider = 'local-template'
        outputDir = (Resolve-Path -LiteralPath $OutputDir).Path
    }
}

function Invoke-CommandProvider {
    param(
        [Parameter(Mandatory = $true)]$ProviderConfig,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    $commandPath = [string](Get-JsonProperty $ProviderConfig 'command' '')
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        throw 'Command provider is missing command.'
    }

    $arguments = @()
    $configuredArguments = Get-JsonProperty $ProviderConfig 'arguments' @()
    foreach ($arg in @($configuredArguments)) {
        $value = [string]$arg
        $value = $value.Replace('{request}', (Join-Path $RunDirectory 'pet-request.json'))
        $value = $value.Replace('{output}', $OutputDir)
        $value = $value.Replace('{reference}', (Get-ReferencePath $RunDirectory $Request))
        $arguments += $value
    }

    $savedEnv = @{
        PET_CREATOR_REQUEST = $env:PET_CREATOR_REQUEST
        PET_CREATOR_OUTPUT_DIR = $env:PET_CREATOR_OUTPUT_DIR
        PET_CREATOR_REFERENCE_IMAGE = $env:PET_CREATOR_REFERENCE_IMAGE
        PET_CREATOR_PET_ID = $env:PET_CREATOR_PET_ID
        PET_CREATOR_DISPLAY_NAME = $env:PET_CREATOR_DISPLAY_NAME
        PET_CREATOR_DESCRIPTION = $env:PET_CREATOR_DESCRIPTION
    }

    try {
        $env:PET_CREATOR_REQUEST = Join-Path $RunDirectory 'pet-request.json'
        $env:PET_CREATOR_OUTPUT_DIR = $OutputDir
        $env:PET_CREATOR_REFERENCE_IMAGE = Get-ReferencePath $RunDirectory $Request
        $env:PET_CREATOR_PET_ID = [string]$Request.petId
        $env:PET_CREATOR_DISPLAY_NAME = [string]$Request.displayName
        $env:PET_CREATOR_DESCRIPTION = [string]$Request.description

        $output = & $commandPath @arguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne $null -and $exitCode -ne 0) {
            throw "Command provider failed with exit code $exitCode. Output: $($output -join [Environment]::NewLine)"
        }
    }
    finally {
        foreach ($name in $savedEnv.Keys) {
            if ($null -eq $savedEnv[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -LiteralPath "Env:$name" -Value $savedEnv[$name]
            }
        }
    }

    return [pscustomobject]@{
        ok = $true
        provider = 'command'
        outputDir = (Resolve-Path -LiteralPath $OutputDir).Path
    }
}

function Validate-PetOutput {
    param([Parameter(Mandatory = $true)][string]$OutputDir)

    $petJsonPath = Join-Path $OutputDir 'pet.json'
    $spritePath = Join-Path $OutputDir 'spritesheet.png'
    if (-not (Test-Path -LiteralPath $petJsonPath -PathType Leaf)) {
        throw "Missing output file: $petJsonPath"
    }
    if (-not (Test-Path -LiteralPath $spritePath -PathType Leaf)) {
        throw "Missing output file: $spritePath"
    }

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Bitmap]::new($spritePath)
    try {
        if ($image.Width -ne $atlasWidth -or $image.Height -ne $atlasHeight) {
            throw "spritesheet.png must be ${atlasWidth}x${atlasHeight}, got $($image.Width)x$($image.Height)."
        }
    }
    finally {
        $image.Dispose()
    }

    $meta = Get-Content -LiteralPath $petJsonPath -Raw | ConvertFrom-Json
    $petId = [string](Get-JsonProperty $meta 'id' '')
    if ($petId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Invalid pet id in pet.json: '$petId'"
    }

    return [pscustomobject]@{
        ok = $true
        petId = $petId
        outputDir = (Resolve-Path -LiteralPath $OutputDir).Path
    }
}

function Install-PetOutput {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [switch]$Overwrite
    )

    $validation = Validate-PetOutput $OutputDir
    New-Item -ItemType Directory -Force -Path $AssetRoot | Out-Null
    $rootFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $AssetRoot).Path)
    $destination = Join-Path $rootFullPath $validation.petId
    $destinationFullPath = [System.IO.Path]::GetFullPath($destination)
    $rootWithSeparator = $rootFullPath.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $destinationFullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Install destination escapes asset root: $destinationFullPath"
    }

    if ((Test-Path -LiteralPath $destinationFullPath) -and -not $Overwrite) {
        throw "Pet already exists: $destinationFullPath. Re-run with -Force to overwrite."
    }
    if (Test-Path -LiteralPath $destinationFullPath) {
        Remove-Item -LiteralPath $destinationFullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destinationFullPath | Out-Null

    foreach ($file in @('pet.json', 'spritesheet.png', 'spritesheet.webp', 'preview.png')) {
        $source = Join-Path $OutputDir $file
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $destinationFullPath $file)
        }
    }

    return [pscustomobject]@{
        ok = $true
        petId = $validation.petId
        petPath = $destinationFullPath
    }
}

function Invoke-PetGeneration {
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw 'Provide -RunDir.'
    }

    $request = Read-RunRequest $RunDir
    $outputDir = Get-RunOutputDir $RunDir
    $config = Read-ModelConfig $ConfigPath
    [void](Validate-ModelConfig $config)
    $resolvedProvider = Resolve-Provider $config ([string]$request.provider)
    $kind = [string](Get-JsonProperty $resolvedProvider.config 'kind' '')

    switch ($kind) {
        'local-template' {
            $generation = Invoke-LocalTemplateGenerator $request $outputDir
        }
        'command' {
            $generation = Invoke-CommandProvider $resolvedProvider.config $request $RunDir $outputDir
        }
        'manual' {
            throw 'Manual provider does not generate files. Put pet.json and spritesheet.png under outputs/, then run -Command install.'
        }
        default {
            throw "Unsupported provider kind: $kind"
        }
    }

    $validation = Validate-PetOutput $outputDir
    $installed = $null
    if ($Install) {
        $installed = Install-PetOutput $outputDir -Overwrite:$Force
    }

    return [pscustomobject]@{
        ok = $true
        generation = $generation
        validation = $validation
        installed = $installed
    }
}

switch ($Command) {
    'validate-config' {
        $config = Read-ModelConfig $ConfigPath
        [void](Validate-ModelConfig $config)
        [pscustomobject]@{
            ok = $true
            config = (Resolve-Path -LiteralPath $ConfigPath).Path
        } | ConvertTo-Json -Depth 10
    }
    'new-request' {
        New-PetRequest | ConvertTo-Json -Depth 10
    }
    'generate' {
        Invoke-PetGeneration | ConvertTo-Json -Depth 20
    }
    'validate-output' {
        $outputDir = Get-RunOutputDir $RunDir
        Validate-PetOutput $outputDir | ConvertTo-Json -Depth 10
    }
    'install' {
        $outputDir = Get-RunOutputDir $RunDir
        Install-PetOutput $outputDir -Overwrite:$Force | ConvertTo-Json -Depth 10
    }
}
