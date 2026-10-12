param([string]$FromDirectory, [string]$Manifest, [switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$python = if (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { 'python' }
$arguments = @((Join-Path $PSScriptRoot 'model_assets.py'))
if ($FromDirectory) { $arguments += @('--from-directory', $FromDirectory) }
if ($Manifest) { $arguments += @('--manifest', $Manifest) }
if ($VerifyOnly) { $arguments += '--verify-only' }
& $python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Model pack import/verification failed. See docs/MODELS.md.' }
