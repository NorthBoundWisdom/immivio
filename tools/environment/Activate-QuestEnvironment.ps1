$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
if (-not $env:ANDROID_NDK_HOME) {
    $ndk = Get-ChildItem (Join-Path $env:ANDROID_HOME 'ndk') -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)*$' } | Sort-Object { [Version]$_.Name } -Descending | Select-Object -First 1
    if ($ndk) { $env:ANDROID_NDK_HOME = $ndk.FullName }
}
$env:PATH = "$env:ANDROID_HOME/platform-tools;$env:PATH"
if (-not $env:GODOT_EXE) {
    $godot = Get-Command godot -ErrorAction SilentlyContinue
    if ($godot) { $env:GODOT_EXE = $godot.Source }
}
