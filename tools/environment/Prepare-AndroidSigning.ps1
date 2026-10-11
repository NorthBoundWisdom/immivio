param(
    [ValidateSet('Debug','Release')][string]$BuildType = 'Debug',
    [string]$ToolRoot = $(if ($env:THRU3D_TOOL_ROOT) { $env:THRU3D_TOOL_ROOT } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\thru3d-toolchain' }),
    [string]$SigningDirectory = '',
    [Security.SecureString]$Password
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $SigningDirectory) { $SigningDirectory = Join-Path $workspace 'keystore/signing' }
$metadataPath = Join-Path $SigningDirectory 'signing-identities.json'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw 'Signing identity metadata missing; no key is generated automatically.' }
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$identity = $metadata.PSObject.Properties[$BuildType.ToLowerInvariant()].Value
if ($metadata.schema_version -ne 1 -or -not $identity -or $identity.certificate_sha256 -notmatch '^[0-9a-f]{64}$' -or $identity.keystore_sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Signing identity metadata invalid.' }
if ($identity.keystore -ne ('thru3d-' + $BuildType.ToLowerInvariant() + '.keystore')) { throw 'Signing identity does not match the requested build type.' }
$keystore = Join-Path $SigningDirectory $identity.keystore
if (-not (Test-Path -LiteralPath $keystore -PathType Leaf)) { throw 'Signing keystore missing; no replacement is generated automatically.' }
if ((Get-FileHash -LiteralPath $keystore).Hash.ToLowerInvariant() -ne $identity.keystore_sha256) { throw 'Signing keystore bytes differ from the tracked identity.' }
$prefix = 'GODOT_ANDROID_KEYSTORE_' + $BuildType.ToUpperInvariant()
$secret = $env:THRU3D_SIGNING_PASSWORD
if (-not $secret -and [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    foreach ($scope in @('User','Machine')) {
        $secret = [Environment]::GetEnvironmentVariable('THRU3D_SIGNING_PASSWORD',$scope)
        if ($secret) { break }
    }
}
if (-not $secret) { $secret = [Environment]::GetEnvironmentVariable($prefix + '_PASSWORD','Process') }
if ($Password -or -not $secret) {
    if (-not $Password) { $Password = Read-Host 'Keystore password' -AsSecureString }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try { $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
if (-not $secret) { throw 'Keystore password is required.' }
$keytool = $null
foreach ($name in @('keytool.exe','keytool')) {
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME ('bin/' + $name)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $keytool = $candidate; break }
    }
}
if (-not $keytool) { $command = Get-Command keytool -ErrorAction SilentlyContinue; if ($command) { $keytool = $command.Source } }
if (-not $keytool) { throw 'Set JAVA_HOME or put keytool on PATH.' }
$previous = $env:THRU3D_VALIDATE_KEY_PASSWORD
try {
    $env:THRU3D_VALIDATE_KEY_PASSWORD = $secret
    $info = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -list -v -storetype PKCS12 -keystore $keystore -alias $identity.alias -storepass:env THRU3D_VALIDATE_KEY_PASSWORD 2>&1
    $exitCode = $LASTEXITCODE
} finally { $env:THRU3D_VALIDATE_KEY_PASSWORD = $previous }
if ($exitCode -ne 0) { throw 'Signing private key cannot be unlocked.' }
$text = $info | Out-String
$certificate = [regex]::Match($text,'(?im)SHA256:\s*([0-9A-F:]{95})').Groups[1].Value.Replace(':','').ToLowerInvariant()
if ($text -notmatch 'PrivateKeyEntry' -or $certificate -ne $identity.certificate_sha256) { throw 'Signing private key certificate does not match the tracked identity.' }
[Environment]::SetEnvironmentVariable($prefix + '_PATH',$keystore,'Process')
[Environment]::SetEnvironmentVariable($prefix + '_USER',$identity.alias,'Process')
[Environment]::SetEnvironmentVariable($prefix + '_PASSWORD',$secret,'Process')
$secret = $null
Write-Output "$BuildType signing identity verified: $certificate"
