param([string]$ToolRoot = $(if ($env:THRU3D_TOOL_ROOT) { $env:THRU3D_TOOL_ROOT } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\thru3d-toolchain' }), [string]$SigningDirectory = '', [Security.SecureString]$Password)
& "$PSScriptRoot\Prepare-AndroidSigning.ps1" -BuildType Release -ToolRoot $ToolRoot -SigningDirectory $SigningDirectory -Password $Password
