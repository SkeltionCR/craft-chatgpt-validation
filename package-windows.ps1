param(
    [Parameter(Mandatory)][ValidateSet('photocraft','vectorcraft','filmcraft','lightcraft','printcraft','effectcraft','designcraft')][string]$App
)
$ErrorActionPreference = 'Stop'
$recipe = $PSScriptRoot
$project = @(Get-Content -LiteralPath (Join-Path $recipe 'projects.json') -Raw | ConvertFrom-Json) | Where-Object repo -eq $App
if (-not $project.validated_run) { throw 'Package requires a previously validated source patch' }
$patch = Join-Path $recipe "patches/$App-chatgpt.patch"
if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash.ToLowerInvariant() -ne $project.patch_sha256) { throw 'Reviewed source checksum mismatch' }
function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
$source = Join-Path $recipe 'package-source'
if (Test-Path -LiteralPath $source) { throw 'Expected a fresh source directory' }
Invoke-Checked -Command git -Arguments @('init',$source)
Invoke-Checked -Command git -Arguments @('-C',$source,'remote','add','origin',"https://github.com/storytold/$App.git")
Invoke-Checked -Command git -Arguments @('-C',$source,'fetch','--depth','1','origin',$project.upstream)
Invoke-Checked -Command git -Arguments @('-C',$source,'checkout','--detach','FETCH_HEAD')
Invoke-Checked -Command git -Arguments @('-C',$source,'apply','--check',$patch)
Invoke-Checked -Command git -Arguments @('-C',$source,'apply',$patch)
if ($project.distribution_patch_sha256) {
    $distributionPatch = Join-Path $recipe "patches/$App-distribution.patch"
    if ((Get-FileHash -LiteralPath $distributionPatch -Algorithm SHA256).Hash.ToLowerInvariant() -ne $project.distribution_patch_sha256) { throw 'Distribution patch checksum mismatch' }
    Invoke-Checked -Command git -Arguments @('-C',$source,'apply','--check',$distributionPatch)
    Invoke-Checked -Command git -Arguments @('-C',$source,'apply',$distributionPatch)
}
Set-Location -LiteralPath $source
Invoke-Checked -Command rustup -Arguments @('toolchain','install','stable','--profile','minimal','--component','clippy','--component','rustfmt')
# Match the upstream Windows packaging convention: the target links its CRT
# statically, while host proc-macros and build scripts keep their normal runtime.
$target = 'x86_64-pc-windows-msvc'
$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = '-C target-feature=+crt-static'
$sdkRoot = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue).KitsRoot10
if ($sdkRoot) {
    $sdkBin = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'bin') -Directory | Where-Object Name -Like '10.*' | Sort-Object Name -Descending | Select-Object -First 1
    if ($sdkBin -and (Test-Path -LiteralPath (Join-Path $sdkBin.FullName 'x64/rc.exe'))) { $env:PATH = (Join-Path $sdkBin.FullName 'x64') + ';' + $env:PATH }
}
if ($App -in @('photocraft','effectcraft')) { [Environment]::SetEnvironmentVariable(($App.ToUpperInvariant()+'_REQUIRE_WINRES'),'1') }
if ($project.distribution_patch_sha256) {
    Invoke-Checked -Command cargo -Arguments @('+stable','fmt','--check')
    Invoke-Checked -Command cargo -Arguments @('+stable','xtask','layers')
    Invoke-Checked -Command cargo -Arguments @('+stable','xtask','assets')
    Invoke-Checked -Command cargo -Arguments @('+stable','clippy','--release','--locked','--target',$target,'-p',"$App-ui-egui",'--all-targets','--','-D','warnings')
    Invoke-Checked -Command cargo -Arguments @('+stable','test','--release','--locked','--target',$target,'-p',"$App-ui-egui",'--lib')
    Write-Output "CRAFT_DISTRIBUTION_UI_CHECKS_PASSED:$App"
}
Invoke-Checked -Command cargo -Arguments @('+stable','build','--release','--locked','--target',$target,'-p',$App,'-p',"$App-cli")
Write-Output "CRAFT_PACKAGE_BUILD_PASSED:$App"
Invoke-Checked -Command cargo -Arguments @('+stable','test','--release','--locked','--target',$target,'-p',$App,'chatgpt')
Write-Output "CRAFT_PACKAGE_AUTH_TESTS_PASSED:$App"
$targetRoot = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $source 'target' }
$bin = Join-Path $targetRoot "$target/release"
Invoke-Checked -Command (Join-Path $bin "$App.exe") -Arguments @('--chatgpt-status')
Invoke-Checked -Command (Join-Path $bin "$App-cli.exe") -Arguments @('--version')
function Assert-Pe([string]$Path,[int]$Subsystem) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($bytes,0x3c)
    if ([BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes,$pe+0x5c) -ne $Subsystem) { throw 'Incorrect architecture or executable subsystem' }
}
Assert-Pe (Join-Path $bin "$App.exe") 2
Assert-Pe (Join-Path $bin "$App-cli.exe") 3
$dist = Join-Path $recipe 'packages'
$stage = Join-Path $recipe "package-stage/$($project.name)"
if (Test-Path -LiteralPath $stage) { throw 'Expected a fresh package directory' }
New-Item -ItemType Directory -Path $stage,$dist -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $bin "$App.exe"),(Join-Path $bin "$App-cli.exe") -Destination $stage
foreach ($name in @('LICENSE','LICENSE.txt','LICENSE-MIT','LICENSE-APACHE','NOTICE','ATTRIBUTION.md')) {
    if (Test-Path -LiteralPath (Join-Path $source $name)) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $stage }
}
foreach ($name in @('ASSETS.md','ATTRIBUTION.toml')) {
    if (Test-Path -LiteralPath (Join-Path $source $name)) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $stage }
}
function Copy-Notices([string]$From,[string]$To) {
    foreach ($notice in @(Get-ChildItem -LiteralPath $From -Recurse -File | Where-Object { $_.Name -match '(?i)(licen[cs]e|copying|notice|^OFL)' })) {
        $relative = [IO.Path]::GetRelativePath($From,$notice.FullName)
        $destination = Join-Path $To $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $notice.FullName -Destination $destination
    }
}
Copy-Notices -From (Join-Path $source 'assets') -To (Join-Path $stage 'licenses/project-assets')
# Preserve dependency notices alongside the binaries, including embedded font licences.
$metadataJson = & cargo +stable metadata --locked --format-version 1
if ($LASTEXITCODE -ne 0) { throw 'Dependency metadata failed' }
$metadata = ($metadataJson -join "`n") | ConvertFrom-Json
$notices = Join-Path $stage 'licenses'
New-Item -ItemType Directory -Path $notices -Force | Out-Null
$licenses = @()
foreach ($dependency in $metadata.packages) {
    $dependencyRoot = Split-Path -Parent $dependency.manifest_path
    $destination = Join-Path $notices "$($dependency.name)-$($dependency.version)"
    Copy-Notices -From $dependencyRoot -To $destination
    $licenses += @{name=$dependency.name;version=$dependency.version;license=$dependency.license;repository=$dependency.repository}
}
$licenses | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'dependency-licenses.json') -Encoding utf8
$instructions = @"
$($project.name) with optional ChatGPT connection - Windows x64

This is a locally modified open-source build based on $($project.name).
Run $App.exe to open the editor. Use ChatGPT connection at the bottom right
to connect your own account. Account connection is optional.
This build does not implement AI editing. It is not an official signed release.

Original source: https://github.com/storytold/$App
Base commit: $($project.upstream)
Reviewed patch SHA-256: $($project.patch_sha256)
Distribution UI patch SHA-256: $($project.distribution_patch_sha256)
Prior full validation: $($project.validated_run)
Build: https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID

The package uses a static C runtime. Application settings remain in the normal
per-user location; no portable-mode marker is included. Your existing documents
and application settings are not part of this package.
"@
$instructions | Set-Content -LiteralPath (Join-Path $stage 'READ-ME.txt') -Encoding utf8
$files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    @{path=[IO.Path]::GetRelativePath($stage,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();bytes=$_.Length}
})
@{app=$App;name=$project.name;platform='windows-x64';upstream=$project.upstream;patch_sha256=$project.patch_sha256;distribution_patch_sha256=$project.distribution_patch_sha256;build_run=$env:GITHUB_RUN_ID;build_commit=$env:GITHUB_SHA;prior_full_validation=$project.validated_run;files=$files;static_crt=$true;auth_smoke='passed';auth_tests='passed';signed=$false} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'package-manifest.json') -Encoding utf8
$archive = Join-Path $dist "$App-chatgpt-windows-x64.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $archive -CompressionLevel Optimal
((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($archive)) | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
Write-Output "CRAFT_PACKAGE_READY:$App"
