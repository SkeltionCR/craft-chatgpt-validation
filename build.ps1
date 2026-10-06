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
Invoke-Checked -Command cargo -Arguments @('+stable','generate-lockfile')
Invoke-Checked -Command cargo -Arguments @('+stable','test','-p',$App,'chatgpt','--locked')
Invoke-Checked -Command cargo -Arguments @('+stable','clippy','-p',$App,'--all-targets','--locked','--','-D','warnings')
Invoke-Checked -Command cargo -Arguments @('+stable','xtask','ci')
