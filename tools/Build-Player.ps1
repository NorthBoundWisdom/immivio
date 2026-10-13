param(
    [ValidateSet('Quest', 'Pico', 'OpenXR')][string]$XrVendor = 'Quest',
    [ValidateSet('Debug', 'Release')][string]$BuildType = 'Debug',
    [string]$GodotExe = 'godot',
    [string]$Templates = ''
)
$ErrorActionPreference = 'Stop'
$builder = Join-Path $PSScriptRoot 'build_player.py'
$buildArguments = @($builder, '--vendor', $XrVendor, '--build-type', $BuildType, '--godot', $GodotExe)
if ($Templates) { $buildArguments += @('--templates', $Templates) }
& python @buildArguments
if ($LASTEXITCODE -ne 0) { throw "Immivio Android build failed ($LASTEXITCODE)." }
