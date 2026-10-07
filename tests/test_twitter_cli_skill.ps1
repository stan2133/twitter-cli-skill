# =====================================================================
# Unit tests for the twitter-cli skill (SKILL.md + machine environment)
# Run:  powershell -ExecutionPolicy Bypass -File tests\test_twitter_cli_skill.ps1
# Optional live API probe (requires valid cookies + proxy):
#        powershell -ExecutionPolicy Bypass -File tests\test_twitter_cli_skill.ps1 -Live
# =====================================================================
param(
    [switch]$Live
)

$ErrorActionPreference = 'Stop'

$SkillDir  = Split-Path -Parent (Split-Path -Parent $PSCommandPath)  # repo root = skill folder
$SkillFile = Join-Path $SkillDir 'SKILL.md'
$SkillName = Split-Path -Leaf $SkillDir

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Assert-True {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) {
        Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
        $script:Passed++
    } else {
        Write-Host ("  [FAIL] {0}  {1}" -f $Name, $Detail) -ForegroundColor Red
        $script:Failed++
    }
}

function Assert-Skip {
    param([string]$Name, [string]$Reason)
    Write-Host ("  [SKIP] {0}  ({1})" -f $Name, $Reason) -ForegroundColor Yellow
    $script:Skipped++
}

Write-Host "=== twitter-cli skill unit tests ==="
Write-Host ("Skill dir : {0}" -f $SkillDir)

# ---------------------------------------------------------------------
Write-Host "`n[Group 1] Skill file structure"
Assert-True (Test-Path $SkillFile) "SKILL.md exists" $SkillFile

if (-not (Test-Path $SkillFile)) {
    Write-Host "SKILL.md missing - cannot continue." -ForegroundColor Red
    exit 1
}

$Raw   = Get-Content $SkillFile -Raw -Encoding UTF8
$Lines = Get-Content $SkillFile -Encoding UTF8

# --- frontmatter block ------------------------------------------------
$fmMatch = [regex]::Match($Raw, '(?s)^---\r?\n(.*?)\r?\n---\r?\n')
Assert-True $fmMatch.Success "Frontmatter block present (--- ... ---)"

$Frontmatter = if ($fmMatch.Success) { $fmMatch.Groups[1].Value } else { '' }
$Body        = if ($fmMatch.Success) { $Raw.Substring($fmMatch.Index + $fmMatch.Length) } else { $Raw }

$nameMatch = [regex]::Match($Frontmatter, '(?m)^name:\s*(\S+)\s*$')
Assert-True $nameMatch.Success "Frontmatter has 'name:' field"

if ($nameMatch.Success) {
    Assert-True ($nameMatch.Groups[1].Value -eq $SkillName) "name matches directory name" ("name='{0}' dir='{1}'" -f $nameMatch.Groups[1].Value, $SkillName)
    Assert-True ($nameMatch.Groups[1].Value -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') "name is valid kebab-case" $nameMatch.Groups[1].Value
    Assert-True ($nameMatch.Groups[1].Value.Length -ge 2 -and $nameMatch.Groups[1].Value.Length -le 64) "name length 2-64"
}

$descMatch = [regex]::Match($Frontmatter, '(?m)^description:\s*(.+)$')
Assert-True $descMatch.Success "Frontmatter has 'description:' field"
if ($descMatch.Success) {
    $desc = $descMatch.Groups[1].Value.Trim()
    Assert-True ($desc.Length -gt 20) "description is substantive (>20 chars)" ("len={0}" -f $desc.Length)
    Assert-True ($desc.Length -le 1024) "description not overlong (<=1024)" ("len={0}" -f $desc.Length)
    Assert-True (-not $desc.Contains(': ')) "description avoids colon-space (YAML quoting hazard)"
    Assert-True (-not $desc.Contains('<') -and -not $desc.Contains('>')) "description avoids angle brackets"
}

# ---------------------------------------------------------------------
Write-Host "`n[Group 2] Required skill content"
# Credential-safety pattern must be documented
Assert-True ($Raw -match 'GetEnvironmentVariable') "Documents registry-based credential reading"
Assert-True ($Raw -match 'dangerouslyDisableSandbox') "Documents sandbox bypass requirement"
Assert-True ($Raw -match '(?i)token\s+refresh|refresh.*token|Token Validity') "Has token refresh / validity guidance"
Assert-True ($Raw -match '(?i)not_authenticated|401|403') "Documents auth-failure signals"
Assert-True ($Raw -match [regex]::Escape('TWITTER_PROXY')) "Documents proxy env var"
# Must NOT contain real credentials (cookie values are 32+ hex chars)
$secretHit = [regex]::Match($Raw, '(?i)(auth_token|ct0)\s*[=:]\s*["'']?[0-9a-f]{32}')
Assert-True (-not $secretHit.Success) "No hardcoded cookie secrets in SKILL.md" ("found near: {0}" -f $secretHit.Value)

# ---------------------------------------------------------------------
Write-Host "`n[Group 3] PowerShell code blocks parse cleanly"
$psBlocks = [regex]::Matches($Raw, '(?s)```powershell\r?\n(.*?)```')
if ($psBlocks.Count -eq 0) {
    Assert-Skip "PS code block syntax" "no powershell blocks found"
} else {
    foreach ($b in $psBlocks) {
        $code  = $b.Groups[1].Value
        $snippet = ($code -split "`n" | Select-Object -First 1)
        if ($snippet.Length -gt 60) { $snippet = $snippet.Substring(0, 60) + '...' }
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "Block parses: $snippet" ($errors | Select-Object -First 1 | ForEach-Object { $_.Message })
    }
}

# ---------------------------------------------------------------------
Write-Host "`n[Group 4] Machine environment (this host)"
$cliExe = 'C:\Users\Administrator\.local\bin\twitter.exe'
Assert-True (Test-Path $cliExe) "twitter.exe installed at documented path" $cliExe

$tok = [Environment]::GetEnvironmentVariable('TWITTER_AUTH_TOKEN', 'User')
$ct0 = [Environment]::GetEnvironmentVariable('TWITTER_CT0', 'User')
$pxy = [Environment]::GetEnvironmentVariable('TWITTER_PROXY', 'User')

Assert-True (-not [string]::IsNullOrEmpty($tok)) "User env TWITTER_AUTH_TOKEN present (value not printed)"
Assert-True (-not [string]::IsNullOrEmpty($ct0)) "User env TWITTER_CT0 present (value not printed)"
Assert-True (-not [string]::IsNullOrEmpty($pxy)) "User env TWITTER_PROXY present"
if (-not [string]::IsNullOrEmpty($pxy)) {
    Assert-True ($pxy -match '^https?://') "TWITTER_PROXY is a valid URL" $pxy
}

# ---------------------------------------------------------------------
Write-Host "`n[Group 5] Live auth probe (opt-in)"
if ($Live) {
    if ([string]::IsNullOrEmpty($tok) -or [string]::IsNullOrEmpty($ct0)) {
        Assert-Skip "Live probe" "credentials not set"
    } else {
        $env:TWITTER_AUTH_TOKEN = $tok
        $env:TWITTER_CT0       = $ct0
        $env:TWITTER_PROXY     = $pxy
        # EAP=Stop turns the CLI's harmless stderr warning into a terminating
        # error in PS5.1 - relax it around the call and merge stderr into stdout.
        $ErrorActionPreference = 'Continue'
        $out = (& $cliExe -c bookmarks --max 1 2>&1 | Out-String)
        $ErrorActionPreference = 'Stop'
        $code = $LASTEXITCODE
        # CLI exit code can be -1 due to harmless stderr warnings; judge by JSON body.
        # Output = stderr banner/warnings + pretty JSON array, so anchor-free matching.
        $joined = ($out -join '')
        $bodyOk = ($joined -match '"ok"\s*:\s*true') -or ($joined -match '"author"\s*:') -or ($joined -match '(?m)^\s*\[\s*$')
        Assert-True ($bodyOk) "Live probe: auth accepted (exit=$code)"
    }
} else {
    Assert-Skip "Live probe" "pass -Live to enable"
}

# ---------------------------------------------------------------------
Write-Host "`n=== Summary ==="
Write-Host ("Passed: {0}  Failed: {1}  Skipped: {2}" -f $script:Passed, $script:Failed, $script:Skipped)
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
