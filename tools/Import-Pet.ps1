param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [string]$PetRoot = (Join-Path $PSScriptRoot '..\assets'),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

$allowedFiles = @(
    'pet.json',
    'spritesheet.png',
    'spritesheet.webp',
    'preview.png',
    'README.md',
    'README.zh-CN.md',
    'LICENSE'
)
$requiredFiles = @('pet.json', 'spritesheet.png')

function Assert-SafeRelativeZipPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Replace('\', '/').Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return
    }
    if ($normalized.StartsWith('/') -or $normalized.StartsWith('~')) {
        throw "Unsafe package path: $Path"
    }
    foreach ($part in $normalized.Split('/')) {
        if ($part -eq '..' -or $part -eq '.' -or [string]::IsNullOrWhiteSpace($part)) {
            throw "Unsafe package path: $Path"
        }
    }
}

function Get-PackageRelativeName {
    param(
        [Parameter(Mandatory = $true)][string]$EntryName,
        [string]$TopFolder
    )

    $normalized = $EntryName.Replace('\', '/').Trim('/')
    if (-not [string]::IsNullOrWhiteSpace($TopFolder) -and $normalized.StartsWith("$TopFolder/")) {
        return $normalized.Substring($TopFolder.Length + 1)
    }
    return $normalized
}

$resolvedPackage = Resolve-Path -LiteralPath $PackagePath
$resolvedPackagePath = $resolvedPackage.Path
if (-not (Test-Path -LiteralPath $resolvedPackagePath -PathType Leaf)) {
    throw "Package not found: $PackagePath"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackagePath)
try {
    $fileEntries = @($zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })
    if ($fileEntries.Count -eq 0) {
        throw "Package is empty: $resolvedPackagePath"
    }

    $firstSegments = @()
    $hasRootFiles = $false
    foreach ($entry in $fileEntries) {
        Assert-SafeRelativeZipPath $entry.FullName
        $normalized = $entry.FullName.Replace('\', '/').Trim('/')
        $parts = $normalized.Split('/')
        if ($parts.Count -eq 1) {
            $hasRootFiles = $true
        }
        else {
            $firstSegments += $parts[0]
        }
    }

    $topFolder = ''
    $uniqueFirstSegments = @($firstSegments | Select-Object -Unique)
    if (-not $hasRootFiles -and $uniqueFirstSegments.Count -eq 1) {
        $topFolder = [string]$uniqueFirstSegments[0]
    }

    $relativeNames = @()
    foreach ($entry in $fileEntries) {
        $relativeName = Get-PackageRelativeName $entry.FullName $topFolder
        if ($relativeName.Contains('/')) {
            throw "Nested files are not supported in pet packages: $($entry.FullName)"
        }
        if ($allowedFiles -notcontains $relativeName) {
            throw "Unsupported file in pet package: $($entry.FullName)"
        }
        $relativeNames += $relativeName
    }

    foreach ($file in $requiredFiles) {
        if ($relativeNames -notcontains $file) {
            throw "Missing required pet file in package: $file"
        }
    }
}
finally {
    $zip.Dispose()
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "desktop-pet-import-$([Guid]::NewGuid().ToString('N'))"

try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($resolvedPackagePath, $tempRoot)
    $candidateDirs = @(
        Get-ChildItem -LiteralPath $tempRoot -Directory -Recurse |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName 'pet.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'spritesheet.png') -PathType Leaf)
            }
    )

    if ((Test-Path -LiteralPath (Join-Path $tempRoot 'pet.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $tempRoot 'spritesheet.png') -PathType Leaf)) {
        $candidateDirs = @((Get-Item -LiteralPath $tempRoot)) + $candidateDirs
    }

    if ($candidateDirs.Count -ne 1) {
        throw "Expected exactly one pet package folder, found $($candidateDirs.Count)."
    }

    $sourceDir = $candidateDirs[0].FullName
    $meta = Get-Content -LiteralPath (Join-Path $sourceDir 'pet.json') -Raw | ConvertFrom-Json
    $petId = Split-Path -Leaf $sourceDir
    if ($meta.PSObject.Properties.Name -contains 'id' -and $meta.id) {
        $petId = [string]$meta.id
    }
    if ($petId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Invalid pet id '$petId'. Use letters, numbers, dots, underscores, or hyphens."
    }

    New-Item -ItemType Directory -Force -Path $PetRoot | Out-Null
    $rootFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PetRoot).Path)
    $destination = Join-Path $rootFullPath $petId
    $destinationFullPath = [System.IO.Path]::GetFullPath($destination)
    $rootWithSeparator = $rootFullPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $destinationFullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Import destination escapes pet root: $destinationFullPath"
    }

    if ((Test-Path -LiteralPath $destinationFullPath) -and -not $Force) {
        throw "Pet already exists: $destinationFullPath. Re-run with -Force to overwrite."
    }
    if (Test-Path -LiteralPath $destinationFullPath) {
        Remove-Item -LiteralPath $destinationFullPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destinationFullPath | Out-Null

    foreach ($file in $allowedFiles) {
        $sourceFile = Join-Path $sourceDir $file
        if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
            Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $destinationFullPath $file)
        }
    }

    [pscustomobject]@{
        ok = $true
        petId = $petId
        petPath = $destinationFullPath
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
