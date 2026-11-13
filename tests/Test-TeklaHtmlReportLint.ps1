<#
.SYNOPSIS
    Regression suite for New-TeklaXlsReport.ps1 + Test-TeklaHtmlReport.ps1.

.DESCRIPTION
    Generates a report, asserts the lint passes it, then injects one defect at a time and
    asserts the lint catches each. The lint composes the emitted HTML by hand (band order,
    descending y, x-padded layout, comment/style regions) - subtle enough that it shipped
    with three bugs before this suite existed:
      * an unpadded join fused `<TD` + `class=head>` into the tag `<TDclass`
      * a PowerShell array behind [ref] degraded to a string, so `"html"[-1]` became a tag `l`
      * `<!--` around the CSS was scanned as a tag named `!`
    Run after touching either script.

.EXAMPLE
    tests\Test-TeklaHtmlReportLint.ps1
#>
[CmdletBinding()]
param([string] $WorkDir)

$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("tekla-htmllint-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$pass = 0; $fail = 0
function Assert-Lint {
    param([string]$Name, [string]$File, [int]$ExpectErrors, [int]$MinWarnings = -1)
    $out = & "$scripts\Test-TeklaHtmlReport.ps1" -Path $File -Quiet *>&1 | Out-String
    $e = if ($out -match '\((\d+) error') { [int]$Matches[1] } else { -1 }
    $w = if ($out -match '(\d+) warning') { [int]$Matches[1] } else { -1 }
    $ok = ($e -eq $ExpectErrors) -and ($MinWarnings -lt 0 -or $w -ge $MinWarnings)
    if ($ok) { $script:pass++; Write-Host ("  PASS  {0}  ({1}E {2}W)" -f $Name, $e, $w) -ForegroundColor Green }
    else {
        $script:fail++
        Write-Host ("  FAIL  {0}  expected {1}E{2}, got {3}E {4}W" -f $Name, $ExpectErrors,
            $(if ($MinWarnings -ge 0) { " >=${MinWarnings}W" } else { '' }), $e, $w) -ForegroundColor Red
    }
}

# Patch a generated template by replacing the FIRST occurrence of a literal string.
function Copy-Patched {
    param([string]$From, [string]$To, [string]$Old, [string]$New)
    $t = [IO.File]::ReadAllText($From)
    $i = $t.IndexOf($Old)
    if ($i -lt 0) { throw "fixture drift: '$Old' not found in $From" }
    [IO.File]::WriteAllText($To, $t.Remove($i, $Old.Length).Insert($i, $New))
}

Write-Host "HTML report lint regression"

# --- baseline: a generated report must be clean ------------------------------
$good = Join-Path $WorkDir 'good.xls.rpt'
& "$scripts\New-TeklaXlsReport.ps1" -Out $good -Title 'Part list' -Column `
    @{ Header = 'Pos';         Formula = 'GetValue("PART_POS")' },
    @{ Header = 'Profile';     Formula = 'GetValue("PROFILE")' },
    @{ Header = 'Qty';         Formula = 'GetValue("NUMBER")'; Type = 'Integer'; Combine = 'SUM' },
    @{ Header = 'Weight (kg)'; Formula = 'GetValue("WEIGHT")'; Type = 'Number'; Combine = 'SUM'; Total = $true } `
    2>&1 | Out-Null
Assert-Lint 'generated report is clean' $good 0

# --- defect 1: a repeating row band that no longer closes its <TR> -----------
$d1 = Join-Path $WorkDir 'unclosed.xls.rpt'
$t = [IO.File]::ReadAllText($good)
$i = $t.IndexOf('r_tr_end')
$s = $t.LastIndexOf('        text', $i)
$e = $t.IndexOf('};', $i) + 4
[IO.File]::WriteAllText($d1, $t.Remove($s, $e - $s))
Assert-Lint 'row band missing </TR>' $d1 1

# --- defect 2: a data row wider than the heading row -------------------------
$d2 = Join-Path $WorkDir 'extracell.xls.rpt'
Copy-Patched -From $good -To $d2 -Old 'string = "<TD>";' -New 'string = "<TD colspan=2>";'
Assert-Lint 'data row wider than heading' $d2 1

# --- defect 3: shipped practice - no Text format, no escaping ----------------
$d3 = Join-Path $WorkDir 'legacy.xls.rpt'
& "$scripts\New-TeklaXlsReport.ps1" -Out $d3 -Title 'Legacy' -NoTextFormat -NoEscape -Column `
    @{ Header = 'Pos'; Formula = 'GetValue("PART_POS")' } 2>&1 | Out-Null
Assert-Lint 'legacy mode warns (coercion + escaping)' $d3 0 2

# --- defect 4: maxheight low enough to paginate mid-table -------------------
$d4 = Join-Path $WorkDir 'paginates.xls.rpt'
Copy-Patched -From $good -To $d4 -Old 'maxheight = 100000;' -New 'maxheight = 60;'
Assert-Lint 'low maxheight warns' $d4 0 1

# --- a non-HTML template must be skipped, not flagged -----------------------
$plain = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\skeleton_part_list.rpt'
if (Test-Path $plain) {
    $out = & "$scripts\Test-TeklaHtmlReport.ps1" -Path $plain -Quiet *>&1 | Out-String
    if ($out -match 'not HTML reports\s*:\s*1') { $pass++; Write-Host "  PASS  plain .rpt is skipped" -ForegroundColor Green }
    else { $fail++; Write-Host "  FAIL  plain .rpt should be skipped as not-HTML" -ForegroundColor Red }
}

Write-Host ""
Write-Host ("passed {0}, failed {1}" -f $pass, $fail)
if (-not $PSBoundParameters.ContainsKey('WorkDir')) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
if ($fail) { exit 1 }
exit 0
