<#
.SYNOPSIS
    Batch-validate every Tekla Template Editor file (.tpl / .rpt) under one or more
    roots against the template "rules": it must PARSE, and (optionally) it must pass
    the -Strict GRAMMAR check — no invented block types, property keys, or enum values.

.DESCRIPTION
    Reuses the EXACT parser (_TemplateParser.ps1) and grammar validator
    (_TemplateGrammar.ps1) that Render-TeklaTemplate.ps1 -Strict uses, so a file that
    passes here passes there and vice-versa. Each file lands in one of three buckets:

        clean        parsed, opens in TplEd, AND no duplicate/grammar findings
        parse-fail   the tokenizer/parser rejected it (a real syntax/format error)
        tpled-incompat  parses here but Template Editor can't open it — a structural
                     comment, bare-LF line endings, packed formatting, or template
                     notes over 120 chars crashes TplEd on open
        vf-dup       GRAPHICAL template with two same-named valuefields in one row/section
                     — TplEd reports a colliding valuefield name (textual reports exempt)
        grammar      parsed, but has grammar findings (a likely-invented name)

    A per-file summary prints to stdout; every non-clean bucket is listed in full. Exit
    code: 0 = all clean, 1 = any parse failure, 2 = TplEd-incompatible, duplicate
    valuefield names, or grammar findings. The TplEd-incompatibility and valuefield-dup
    checks run even with -NoGrammar (neither is grammar-based).

    NOTE ON GRAMMAR CHECKING: the allow-list is harvested from a shipped corpus. If you
    point this at that same corpus (e.g. a stock install) the grammar check is circular
    and will find nothing — the meaningful signal there is parse conformance. The grammar
    check earns its keep on NEW/hand-written templates validated against a stock allow-list.

.PARAMETER Path
    One or more files or directory roots to check (directories are searched recursively
    for *.tpl / *.rpt). Defaults to the newest install's Environments tree if omitted.

.PARAMETER TeklaRoot
    A Tekla install root whose Environments tree is scanned when -Path is not given.
    Defaults to the newest version found under C:\TeklaStructures.

.PARAMETER GrammarFile
    Allow-list for the grammar check (default: assets\template-grammar.json next to the
    skill). Generate one for another version with Get-TeklaGrammar.ps1.

.PARAMETER NoGrammar
    Skip the grammar check; validate parse-ability only (every file that parses is clean).

.PARAMETER Quiet
    Suppress the per-bucket detail lists; print only the summary counts.

.OUTPUTS
    A summary object: @{ Scanned; Clean; ParseFailures; GrammarFindings; Details }.
    Details is the list of non-clean files with their errors/findings.

.EXAMPLE
    scripts\Test-TeklaTemplates.ps1 -Path C:\TeklaStructures\2026.0\Environments\UK
    # parse + grammar check every template under the UK environment

.EXAMPLE
    scripts\Test-TeklaTemplates.ps1 -Path D:\MyReports -NoGrammar
    # just confirm every hand-authored template parses
#>
[CmdletBinding()]
param(
    [string[]] $Path,
    [string]   $TeklaRoot,
    [string]   $GrammarFile,
    [switch]   $NoGrammar,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\_TemplateParser.ps1"
. "$PSScriptRoot\_TemplateGrammar.ps1"

# --- resolve roots -----------------------------------------------------------
if (-not $Path) {
    if (-not $TeklaRoot) {
        $base = 'C:\TeklaStructures'
        if (Test-Path $base) {
            $newest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d+\.\d+$' } |
                Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
            if ($newest) { $TeklaRoot = $newest.FullName }
        }
    }
    if (-not $TeklaRoot) { throw "No -Path given and no install found under C:\TeklaStructures. Pass -Path or -TeklaRoot." }
    $envDir = Join-Path $TeklaRoot 'Environments'
    $Path = @( (Test-Path $envDir) ? $envDir : $TeklaRoot )
}

# --- gather files ------------------------------------------------------------
$files = New-Object System.Collections.ArrayList
foreach ($p in $Path) {
    if (-not (Test-Path $p)) { throw "Path not found: $p" }
    if (Test-Path $p -PathType Leaf) { [void]$files.Add((Resolve-Path $p).Path); continue }
    Get-ChildItem $p -Recurse -File -Include '*.tpl', '*.rpt' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$files.Add($_.FullName) }
}
$files = @($files | Sort-Object -Unique)

# --- load grammar (unless skipped) -------------------------------------------
$grammar = $null
if (-not $NoGrammar) {
    $grammar = Get-GrammarAllowList -GrammarFile $GrammarFile   # $null + stderr note if missing
    if (-not $grammar) { $NoGrammar = $true }                   # degrade to parse-only, already warned
}

# --- validate ----------------------------------------------------------------
$parseFail   = New-Object System.Collections.ArrayList
$grammarFail = New-Object System.Collections.ArrayList
$tpledFail   = New-Object System.Collections.ArrayList
$dupFail     = New-Object System.Collections.ArrayList
$clean = 0

foreach ($f in $files) {
    $raw = [System.IO.File]::ReadAllText($f)
    try {
        $tree = Parse-Template -Text $raw
    }
    catch {
        [void]$parseFail.Add([pscustomobject]@{ File = $f; Error = $_.Exception.Message })
        continue
    }
    # TplEd portability lint runs regardless of -NoGrammar (it's not grammar-based): a
    # structural comment parses fine here but crashes Template Editor on open.
    $port = @(Find-TplEdIncompatibilities -Text $raw)
    if ($port.Count -gt 0) {
        [void]$tpledFail.Add([pscustomobject]@{ File = $f; Findings = $port })
        continue
    }
    # Duplicate valuefield-name check (graphical templates): a TplEd schema rule, not
    # grammar-based, so it runs regardless of -NoGrammar. A file can also have grammar
    # findings, so this bucket is independent — 'clean' requires neither.
    $dups = @(Find-DuplicateValueFieldNames -Root $tree)
    if ($dups.Count -gt 0) {
        [void]$dupFail.Add([pscustomobject]@{ File = $f; Findings = $dups })
    }
    $findings = if ($NoGrammar) { @() } else { @(Invoke-StrictValidation -Root $tree -Grammar $grammar) }
    if ($findings.Count -gt 0) {
        [void]$grammarFail.Add([pscustomobject]@{ File = $f; Findings = $findings })
    }
    if ($dups.Count -eq 0 -and $findings.Count -eq 0) { $clean++ }
}

# --- report ------------------------------------------------------------------
$mode = if ($NoGrammar) { 'parse only' } else { "parse + grammar (v$($grammar.meta.version))" }
Write-Host ("Checked {0} template(s) [{1}]" -f $files.Count, $mode)
Write-Host ("  clean:              {0}" -f $clean)
Write-Host ("  parse failures:     {0}" -f $parseFail.Count)
Write-Host ("  TplEd-incompatible: {0}" -f $tpledFail.Count)
Write-Host ("  valuefield dup names: {0}" -f $dupFail.Count)
if (-not $NoGrammar) { Write-Host ("  grammar findings:   {0}" -f $grammarFail.Count) }

if (-not $Quiet -and $parseFail.Count) {
    Write-Host "`n===== PARSE FAILURES ====="
    foreach ($p in $parseFail) {
        Write-Host ("`n[{0}]" -f $p.File)
        Write-Host ("   {0}" -f $p.Error)
    }
}
if (-not $Quiet -and $tpledFail.Count) {
    Write-Host "`n===== TEMPLATE EDITOR WILL NOT OPEN (comments / LF endings / packing / notes > 120) ====="
    foreach ($t in $tpledFail) {
        Write-Host ("`n[{0}]" -f $t.File)
        foreach ($fd in $t.Findings) { Write-Host ("   # {0}" -f $fd) }
    }
}
if (-not $Quiet -and $dupFail.Count) {
    Write-Host "`n===== DUPLICATE VALUEFIELD NAMES (graphical templates) ====="
    foreach ($d in $dupFail) {
        Write-Host ("`n[{0}]" -f $d.File)
        foreach ($fd in $d.Findings) { Write-Host ("   # {0}" -f $fd) }
    }
}
if (-not $Quiet -and $grammarFail.Count) {
    Write-Host "`n===== GRAMMAR FINDINGS ====="
    foreach ($g in $grammarFail) {
        Write-Host ("`n[{0}]" -f $g.File)
        foreach ($fd in $g.Findings) { Write-Host ("   # {0}" -f $fd) }
    }
}

# --- summary object + exit code ----------------------------------------------
$result = [pscustomobject]@{
    Scanned          = $files.Count
    Clean            = $clean
    ParseFailures    = $parseFail.Count
    TplEdIncompatible = $tpledFail.Count
    DuplicateValueFieldNames = $dupFail.Count
    GrammarFindings  = $grammarFail.Count
    Details          = @($parseFail) + @($tpledFail) + @($dupFail) + @($grammarFail)
}
$result

# Exit: 1 = a file our parser can't read; 2 = a file that parses but won't open in
# TplEd, has colliding valuefield names, or has grammar findings; 0 = all clean.
if ($parseFail.Count -gt 0)                            { exit 1 }
elseif ($tpledFail.Count -gt 0 -or $dupFail.Count -gt 0 -or $grammarFail.Count -gt 0) { exit 2 }
else                                                   { exit 0 }
