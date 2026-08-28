$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$localPropertiesPath = Join-Path $projectRoot 'android/local.properties'
$dartDefinesPath = Join-Path $projectRoot 'android/dart_defines.local.env'

if (-not (Test-Path -LiteralPath $localPropertiesPath)) {
    throw 'android/local.properties was not found.'
}

$keyLine = Get-Content -LiteralPath $localPropertiesPath |
    Where-Object { $_ -match '^MAPS_API_KEY=' } |
    Select-Object -First 1

if (-not $keyLine) {
    throw 'MAPS_API_KEY is missing from android/local.properties.'
}

$mapsApiKey = ($keyLine -split '=', 2)[1].Trim()
if ([string]::IsNullOrWhiteSpace($mapsApiKey) -or
    $mapsApiKey -eq 'DEFAULT_API_KEY' -or
    $mapsApiKey -eq 'YOUR_GOOGLE_MAPS_API_KEY') {
    throw 'MAPS_API_KEY in android/local.properties is not configured.'
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    $dartDefinesPath,
    "MAPS_API_KEY=$mapsApiKey`n",
    $utf8WithoutBom
)

Write-Host 'Created android/dart_defines.local.env for Flutter runs.'
