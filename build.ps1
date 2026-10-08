param(
    [Parameter(Mandatory)]
    [ValidateSet('photocraft','vectorcraft','filmcraft','lightcraft','printcraft','effectcraft','designcraft')]
    [string]$App,
    [switch]$CollectOnly
)
$ErrorActionPreference = 'Stop'
$recipeRoot = $PSScriptRoot
$project = @(Get-Content -LiteralPath (Join-Path $recipeRoot 'projects.json') -Raw | ConvertFrom-Json) | Where-Object { $_.repo -eq $App }
if ($null -eq $project) { throw 'Project is not in the pinned manifest' }
$sourceRoot = Join-Path $recipeRoot 'source'

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE" }
}

if ($CollectOnly) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '.git'))) { return }
    Set-Location -LiteralPath $sourceRoot
    Invoke-Checked -Command git -Arguments @('add','-N','--',"apps/$App/src/chatgpt.rs","apps/$App/src/chatgpt_unsupported.rs",'docs/chatgpt-connection.md')
    $patchFile = Join-Path $recipeRoot 'result.patch'
    # Let Git write UTF-8 directly, preserving actual LF bytes on Windows.
    Invoke-Checked -Command git -Arguments @('diff','--binary',"--output=$patchFile")
    $bytes = [IO.File]::ReadAllBytes($patchFile)
    $encoded = [Convert]::ToBase64String($bytes)
    $checksum = (Get-FileHash -LiteralPath $patchFile -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "CRAFT_PATCH_START:$App`:$checksum"
    for ($offset = 0; $offset -lt $encoded.Length; $offset += 4000) {
        $length = [Math]::Min(4000, $encoded.Length - $offset)
        Write-Output ('CRAFT_PATCH_CHUNK:' + $encoded.Substring($offset,$length))
    }
    Write-Output "CRAFT_PATCH_END:$App"
    $imageFile = Join-Path $recipeRoot 'panel-preview.png'
    if (Test-Path -LiteralPath $imageFile) {
        $imageBytes = [IO.File]::ReadAllBytes($imageFile)
        $imageEncoded = [Convert]::ToBase64String($imageBytes)
        $imageChecksum = (Get-FileHash -LiteralPath $imageFile -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Output "CRAFT_IMAGE_START:$App`:$imageChecksum"
        for ($offset = 0; $offset -lt $imageEncoded.Length; $offset += 4000) {
            $length = [Math]::Min(4000, $imageEncoded.Length - $offset)
            Write-Output ('CRAFT_IMAGE_CHUNK:' + $imageEncoded.Substring($offset,$length))
        }
        Write-Output "CRAFT_IMAGE_END:$App"
    }
    return
}

$inputPatch = Join-Path $recipeRoot "patches/$App-chatgpt.patch"
if ((Get-FileHash -LiteralPath $inputPatch -Algorithm SHA256).Hash.ToLowerInvariant() -ne $project.patch_sha256) {
    throw 'Input patch checksum did not match the reviewed manifest'
}
if (Test-Path -LiteralPath $sourceRoot) { throw 'Expected an empty runner checkout' }
Invoke-Checked -Command git -Arguments @('init',$sourceRoot)
Invoke-Checked -Command git -Arguments @('-C',$sourceRoot,'remote','add','origin',"https://github.com/storytold/$App.git")
Invoke-Checked -Command git -Arguments @('-C',$sourceRoot,'fetch','--depth','1','origin',$project.upstream)
Invoke-Checked -Command git -Arguments @('-C',$sourceRoot,'checkout','--detach','FETCH_HEAD')
Invoke-Checked -Command git -Arguments @('-C',$sourceRoot,'apply','--check',$inputPatch)
Invoke-Checked -Command git -Arguments @('-C',$sourceRoot,'apply',$inputPatch)
Set-Location -LiteralPath $sourceRoot
Invoke-Checked -Command rustup -Arguments @('toolchain','install','stable','--profile','minimal','--component','rustfmt','--component','clippy')
Invoke-Checked -Command rustup -Arguments @('target','add','wasm32-unknown-unknown','--toolchain','stable')
Invoke-Checked -Command cargo -Arguments @('+stable','fmt','--all')
if ($App -eq 'printcraft') {
    # PrintCraft requires this checker in CI. Run its unchanged dependency policy
    # before compilation so policy failures are reported without a cold rebuild.
    Invoke-Checked -Command cargo -Arguments @('+stable','install','cargo-deny','--locked','--version','0.20.2')
    Invoke-Checked -Command cargo -Arguments @('+stable','deny','--log-level','error','check')
}
# This first resolution preserves upstream's existing lockfile pins and adds only
# dependencies required by the reviewed patch. Subsequent checks enforce that lock.
# Use the same workspace feature union as upstream CI to reuse compilation outputs.
$profileArguments = if ($App -in @('filmcraft','effectcraft')) { @('--release') } else { @() }
Write-Output "CRAFT_BUILD_CONFIGURATION:$App`:compiler_jobs=$env:CARGO_BUILD_JOBS`:profile=$($profileArguments -join ',')"
if ($App -in @('filmcraft','effectcraft')) {
    # Report Windows engine regressions before the much larger editor/CLI link.
    # The full workspace checks and upstream CI still run below.
    Invoke-Checked -Command cargo -Arguments @('+stable','test','-p',"$App-engine",'--release')
    Write-Output "CRAFT_ENGINE_TESTS_PASSED:$App"
    if ($App -eq 'filmcraft') {
        Invoke-Checked -Command cargo -Arguments @('+stable','test','-p','filmcraft-export','--release')
        Write-Output 'CRAFT_EXPORT_TESTS_PASSED:filmcraft'
    }
}
if ($App -eq 'effectcraft') {
    # Upstream CI runs Clippy before release tests. Run that pass before the
    # filtered auth tests: the six-hour run rebuilt test artifacts after Clippy,
    # including a second expensive Thin LTO editor/CLI compilation.
    # Preserve every upstream gate and the workspace's release profile.
    Invoke-Checked -Command cargo -Arguments @('+stable','xtask','ci')
    Write-Output 'CRAFT_FULL_CI_PASSED:effectcraft'
    Write-Output 'CRAFT_CLIPPY_PASSED:effectcraft'
    Invoke-Checked -Command cargo -Arguments @('+stable','test','--workspace','chatgpt','--release','--locked')
    Write-Output 'CRAFT_AUTH_TESTS_PASSED:effectcraft'
    $env:CRAFT_SNAPSHOT_PATH = Join-Path $recipeRoot 'panel-preview.png'
    Invoke-Checked -Command cargo -Arguments @('+stable','test','--workspace','chatgpt_panel_offscreen_preview','--release','--locked','--','--ignored')
    Write-Output 'CRAFT_PANEL_PREVIEW_PASSED:effectcraft'
    return
}
Invoke-Checked -Command cargo -Arguments (@('+stable','test','--workspace','chatgpt') + $profileArguments)
Write-Output "CRAFT_AUTH_TESTS_PASSED:$App"
$env:CRAFT_SNAPSHOT_PATH = Join-Path $recipeRoot 'panel-preview.png'
Invoke-Checked -Command cargo -Arguments (@('+stable','test','--workspace','chatgpt_panel_offscreen_preview','--locked') + $profileArguments + @('--','--ignored'))
Write-Output "CRAFT_PANEL_PREVIEW_PASSED:$App"
if ($App -eq 'filmcraft') {
    # Exercise every crate even if one has a Windows fixture regression. Keep the
    # unchanged upstream CI below; this extra pass exposes all failures together.
    Invoke-Checked -Command cargo -Arguments @('+stable','test','--workspace','--release','--locked','--no-fail-fast')
    Write-Output 'CRAFT_WORKSPACE_TESTS_PASSED:filmcraft'
}
Invoke-Checked -Command cargo -Arguments (@('+stable','clippy','--workspace','--all-targets','--locked') + $profileArguments + @('--','-D','warnings'))
Write-Output "CRAFT_CLIPPY_PASSED:$App"
Invoke-Checked -Command cargo -Arguments @('+stable','xtask','ci')
Write-Output "CRAFT_FULL_CI_PASSED:$App"
