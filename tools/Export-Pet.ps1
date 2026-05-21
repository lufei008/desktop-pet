param(
    [Parameter(Mandatory = $true)]
    [string]$PetId,
    [string]$PetRoot = (Join-Path $PSScriptRoot '..\assets'),
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\exports'),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredFiles = @('pet.json', 'spritesheet.png')
$optionalFiles = @('spritesheet.webp', 'preview.png', 'README.md', 'README.zh-CN.md', 'LICENSE')

$petDir = Join-Path $PetRoot $PetId
if (-not (Test-Path -LiteralPath $petDir -PathType Container)) {
    throw "Pet not found: $petDir"
}

foreach ($file in $requiredFiles) {
    $path = Join-Path $petDir $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required pet file: $path"
    }
}

$meta = Get-Content -LiteralPath (Join-Path $petDir 'pet.json') -Raw | ConvertFrom-Json
if ($meta.PSObject.Properties.Name -contains 'id' -and $meta.id -and [string]$meta.id -ne $PetId) {
    throw "pet.json id '$($meta.id)' does not match package id '$PetId'."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$outputPath = Join-Path $OutputDir "$PetId.pet.zip"
if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
    throw "Package already exists: $outputPath. Re-run with -Force to overwrite."
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "desktop-pet-export-$([Guid]::NewGuid().ToString('N'))"
$stagingPet = Join-Path $stagingRoot $PetId

try {
    New-Item -ItemType Directory -Force -Path $stagingPet | Out-Null

    foreach ($file in ($requiredFiles + $optionalFiles)) {
        $source = Join-Path $petDir $file
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $stagingPet $file)
        }
    }

    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    Compress-Archive -LiteralPath $stagingPet -DestinationPath $outputPath -CompressionLevel Optimal

    [pscustomobject]@{
        ok = $true
        petId = $PetId
        packagePath = (Resolve-Path -LiteralPath $outputPath).Path
    }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
