param(
    [Parameter(Mandatory = $true)][string]$FlutterSdk,
    [Parameter(Mandatory = $true)][string]$AndroidSdk,
    [string]$JavaHome
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutterRoot = (Resolve-Path $FlutterSdk).Path
$androidRoot = (Resolve-Path $AndroidSdk).Path
$flutter = Join-Path $flutterRoot 'bin/flutter.bat'
if (-not (Test-Path $flutter)) { throw "Flutter SDK not found: $flutter" }
if ($JavaHome) {
    $env:JAVA_HOME = (Resolve-Path $JavaHome).Path
    $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
}
$env:ANDROID_SDK_ROOT = $androidRoot
$env:ANDROID_HOME = $androidRoot
$env:PATH = "$flutterRoot\bin;$androidRoot\platform-tools;$env:PATH"

function Escape-Property([string]$value) {
    return $value.Replace('\', '/').Replace(':', '\:')
}
$propertiesPath = Join-Path $root 'android/local.properties'
$existing = @()
if (Test-Path $propertiesPath) {
    $existing = @(Get-Content $propertiesPath | Where-Object { $_ -notmatch '^(flutter\.sdk|sdk\.dir)=' })
}
$lines = @($existing) + @(
    "flutter.sdk=$(Escape-Property $flutterRoot)",
    "sdk.dir=$(Escape-Property $androidRoot)"
)
[IO.File]::WriteAllLines($propertiesPath, [string[]]$lines, [Text.UTF8Encoding]::new($false))

# The wrapper is obtained from this installed Flutter SDK, not from a random JAR mirror.
$jar = Join-Path $root 'android/gradle/wrapper/gradle-wrapper.jar'
$unix = Join-Path $root 'android/gradlew'
$windows = Join-Path $root 'android/gradlew.bat'
if (-not ((Test-Path $jar) -and (Test-Path $unix) -and (Test-Path $windows))) {
    $seed = Join-Path ([IO.Path]::GetTempPath()) ('baocode-wrapper-' + [Guid]::NewGuid().ToString('N'))
    Push-Location $root
    try {
        & $flutter create --no-pub --platforms=android --project-name wrapper_seed $seed
        if ($LASTEXITCODE -ne 0) { throw 'Flutter could not generate the wrapper seed project' }
        foreach ($relative in @('gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar')) {
            $source = Join-Path (Join-Path $seed 'android') $relative
            $target = Join-Path (Join-Path $root 'android') $relative
            if (-not (Test-Path $source)) { throw "Generated wrapper file is missing: $source" }
            if (-not (Test-Path $target)) { Copy-Item $source $target }
        }
    } finally { Pop-Location }
    Write-Host "Wrapper seed kept for inspection: $seed"
}
Push-Location $root
try {
    & $flutter --version
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed; check Flutter/Dart versions and network access' }
} finally { Pop-Location }
Write-Host 'Project-local Android paths are configured. No system PATH or SDK licenses were changed.'
Write-Host 'Use this Flutter SDK to run analyze, targeted tests, then build a debug APK.'
