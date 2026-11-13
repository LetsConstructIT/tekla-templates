<#
.SYNOPSIS
    Index the shipped Tekla Template Editor corpus so the ~2,700 templates that
    ship with an install become searchable: for every .tpl / .rpt, record which
    content types, formula functions, attributes, block types and structural
    "tricks" it uses, and emit the whole thing as one JSON index.

.DESCRIPTION
    The shipped templates are the best documentation Tekla has, but only if you can
    FIND the one that already does what you want. This sweeps the corpus with the same
    tolerant parser the preview/grammar tools use (_TemplateParser.ps1) and, per file,
    harvests:

        contentTypes  every row's `contenttype`         (PART, ASSEMBLY, REBAR, DRAWING …)
        functions     every  name(  in a formula/rule   (GetValue, Sum, Total, format …)
        attributes    every  GetValue("…")  argument     (PROFILE, ASSEMBLY.WEIGHT …)
        blockTypes    every block keyword used           (valuefield, lineorarc, row …)
        features      named structural tricks (below)    (nested-rows, combine, footer-sum …)

    Named features (derived, so a query can ask "show me a working example of X"):
        nested-rows      a row contains a child row (grouping scope)
        combine/distinct a block sets sorttype = COMBINE / DISTINCT
        oncombine-sum    a valuefield rolls up with oncombine = SUM
        footer-sum       a footer/pagefooter totals with Sum()/Total()
        hidden-rows      a row with visibility = FALSE (grouping scaffold / sort key)
        hidden-fields    a valuefield with visibility = FALSE
        current-drawing  a formula/rule uses the CURRENT_DRAWING. prefix (drawing-embedded report)
        imperial-branch  a formula/rule branches on XS_IMPERIAL
        control-flow     a rule/formula uses StepOut()/StepOver()/StepIn()
        summary-band     a row of contenttype SUMMARY (per-group subtotal)
        single-rebar     a row of contenttype SINGLE_REBAR (per-bar iteration)
        revision-table   a row of contenttype REVISION
        drawing-table    a GRAPHICAL template with a DRAWING row (title block / table)
        csv-export       a text block prints a literal "sep=" line (delimited export)
        xls-html         text blocks emit HTML tags / mso- CSS (Excel or HTML report)
        picture          a picture block (logo / graphic)

    The output feeds Find-TeklaTemplateExamples.ps1. This is the CORPUS INDEX (which file
    uses what); the vocabulary allow-list (which words are legal at all) is a different
    artifact — Get-TeklaGrammar.ps1 -> template-grammar.json.

    Files that fail to parse are counted and skipped (a few shipped files are genuinely
    malformed); they never abort the sweep.

.PARAMETER TeklaRoot
    A Tekla install root (e.g. C:\TeklaStructures\2026.0) whose Environments tree is
    scanned. Defaults to the newest version found under C:\TeklaStructures.

.PARAMETER Path
    Extra file or directory roots to include (searched recursively for *.tpl / *.rpt).
    Repeatable. Use to fold a firm/project template library into the index.

.PARAMETER OutFile
    Where to write the JSON index. Defaults to <skill>\assets\template-index.json
    (the location Find-TeklaTemplateExamples.ps1 loads).

.PARAMETER Quiet
    Suppress progress output.

.EXAMPLE
    scripts\Get-TeklaTemplateIndex.ps1
    # index newest install -> assets\template-index.json

.EXAMPLE
    scripts\Get-TeklaTemplateIndex.ps1 -TeklaRoot C:\TeklaStructures\2024.0 -Path D:\FirmTemplates
    # pin a version and fold in a firm library
#>
[CmdletBinding()]
param(
    [string]   $TeklaRoot,
    [string[]] $Path,
    [string]   $OutFile,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_TemplateParser.ps1"

function Write-Info { param([string]$Msg) if (-not $Quiet) { Write-Host $Msg } }

# Language keywords that look like a function call (`if (`) but are grammar, not functions.
$script:Keywords = @('if','then','else','elseif','endif','and','or','not','null','true','false','mod','div')

# --- resolve corpus roots (same convention as Get-TeklaGrammar.ps1) ----------
if (-not $TeklaRoot) {
    $base = 'C:\TeklaStructures'
    if (Test-Path $base) {
        $newest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            Select-Object -First 1
        if ($newest) { $TeklaRoot = $newest.FullName }
    }
}

$roots = New-Object System.Collections.ArrayList     # each: @{ Base; Label }
if ($TeklaRoot) {
    if (-not (Test-Path $TeklaRoot)) { throw "TeklaRoot not found: $TeklaRoot" }
    $env = Join-Path $TeklaRoot 'Environments'
    $b = (Test-Path $env) ? $env : $TeklaRoot
    [void]$roots.Add(@{ Base = (Resolve-Path $b).Path; Label = 'install' })
}
if ($Path) {
    foreach ($p in $Path) {
        if (-not (Test-Path $p)) { throw "Path not found: $p" }
        [void]$roots.Add(@{ Base = (Resolve-Path $p).Path; Label = 'extra' })
    }
}
if ($roots.Count -eq 0) { throw "No corpus roots. Pass -TeklaRoot or -Path (no install found under C:\TeklaStructures)." }

if (-not $OutFile) { $OutFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-index.json' }

Write-Info "Corpus roots:"
foreach ($r in $roots) { Write-Info "  $($r.Base)" }

# --- gather files, remembering which root each came from (for portable rel paths) ---
$files = New-Object System.Collections.ArrayList   # each: @{ Full; Rel }
$seen  = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $roots) {
    $base = $r.Base
    if (Test-Path $base -PathType Leaf) {
        if ($seen.Add($base.ToLower())) { [void]$files.Add(@{ Full = $base; Rel = (Split-Path $base -Leaf) }) }
        continue
    }
    Get-ChildItem $base -Recurse -File -Include '*.tpl', '*.rpt' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($seen.Add($_.FullName.ToLower())) {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/'
            [void]$files.Add(@{ Full = $_.FullName; Rel = $rel })
        }
    }
}
Write-Info ("Found {0} template files." -f $files.Count)

# --- helpers -----------------------------------------------------------------
$falsey = '^(FALSE|NO|0)$'

function Add-Many { param($Set, $Items) foreach ($x in $Items) { [void]$Set.Add($x) } }

# Does any block in a subtree carry a formula that totals with Sum()/Total()?
function Test-SumsInSubtree {
    param($Node)
    foreach ($n in (Get-AllBlocks $Node)) {
        $f = Get-Str $n 'formula' ''
        if ($f -match '\b(Sum|Total)\s*\(') { return $true }
    }
    return $false
}

function Get-TemplateRecord {
    param([string]$Rel, [string]$Full, [int]$Bytes, $Root)

    $ttype = (Get-Str $Root 'type' '').ToUpper()
    $contentTypes = New-Object 'System.Collections.Generic.HashSet[string]'
    $functions    = New-Object 'System.Collections.Generic.HashSet[string]'
    $attributes   = New-Object 'System.Collections.Generic.HashSet[string]'
    $blockTypes   = New-Object 'System.Collections.Generic.HashSet[string]'
    $features     = New-Object 'System.Collections.Generic.HashSet[string]'
    $rows = 0; $fields = 0

    foreach ($b in (Get-AllBlocks $Root)) {
        [void]$blockTypes.Add($b.Keyword)

        switch ($b.Keyword) {
            'row' {
                $rows++
                $ct = (Get-Str $b 'contenttype' '').ToUpper()
                if ($ct) { [void]$contentTypes.Add($ct) }
                if ((Get-Str $b 'visibility' '') -match $falsey) { [void]$features.Add('hidden-rows') }
                if ($b.Children | Where-Object { $_.Keyword -eq 'row' }) { [void]$features.Add('nested-rows') }
            }
            'valuefield' {
                $fields++
                if ((Get-Str $b 'oncombine' '') -match 'SUM') { [void]$features.Add('oncombine-sum') }
                if ((Get-Str $b 'visibility' '') -match $falsey) { [void]$features.Add('hidden-fields') }
            }
            'picture' { [void]$features.Add('picture') }
            { $_ -eq 'footer' -or $_ -eq 'pagefooter' } {
                if (Test-SumsInSubtree $b) { [void]$features.Add('footer-sum') }
            }
        }

        switch -Regex ((Get-Str $b 'sorttype' '')) {
            'COMBINE'  { [void]$features.Add('combine') }
            'DISTINCT' { [void]$features.Add('distinct') }
        }
        # CSV convention is a text block printing a literal "sep=;" line (see
        # assets/skeleton_csv_export.rpt) — there is no sep property in the grammar.
        if ($b.Keyword -eq 'text' -and (Get-Str $b 'string' '') -match '^sep=') { [void]$features.Add('csv-export') }
        # Excel/HTML reports (*.xls.rpt, *.html.rpt) are ordinary TEXTUAL templates whose
        # text blocks emit HTML tags + Excel mso- CSS, one table cell per output line (see
        # assets/skeleton_xls_report.xls.rpt). Nothing in the grammar marks them.
        if ($b.Keyword -eq 'text' -and (Get-Str $b 'string' '') -match '(?i)<\s*/?\s*(html|head|body|table|tr|td|th|style|meta|br)\b') {
            [void]$features.Add('xls-html')
        }

        # scan formula-language strings for functions, attributes and inline tricks
        foreach ($key in 'formula', 'rule', 'content') {
            $s = Get-Str $b $key ''
            if (-not $s) { continue }
            # rule/formula newlines are the literal two chars \n (also \t, \r); left in place
            # they glue onto the next token ("\nOutput(" -> "nOutput"). Blank them first.
            $s = $s -replace '\\[nrt]', ' '
            foreach ($m in [regex]::Matches($s, '([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
                $fn = $m.Groups[1].Value
                if ($script:Keywords -notcontains $fn.ToLower()) { [void]$functions.Add($fn) }
            }
            foreach ($m in [regex]::Matches($s, 'GetValue\(\s*"([^"]+)"')) {
                [void]$attributes.Add($m.Groups[1].Value)
            }
            if ($s -match 'CURRENT_DRAWING\.') { [void]$features.Add('current-drawing') }
            if ($s -match 'XS_IMPERIAL')       { [void]$features.Add('imperial-branch') }
            if ($s -match '\b(StepOut|StepOver|StepIn)\b') { [void]$features.Add('control-flow') }
        }
    }

    # content-type-derived features
    if ($contentTypes.Contains('REVISION'))     { [void]$features.Add('revision-table') }
    if ($contentTypes.Contains('SUMMARY'))      { [void]$features.Add('summary-band') }
    if ($contentTypes.Contains('SINGLE_REBAR')) { [void]$features.Add('single-rebar') }
    if ($ttype -eq 'GRAPHICAL' -and $contentTypes.Contains('DRAWING')) { [void]$features.Add('drawing-table') }

    [ordered]@{
        path         = $Rel
        name         = [IO.Path]::GetFileNameWithoutExtension($Full)
        kind         = [IO.Path]::GetExtension($Full).TrimStart('.').ToLower()
        type         = $ttype
        env          = ($Rel -split '/', 2)[0]
        rows         = $rows
        fields       = $fields
        bytes        = $Bytes
        contentTypes = @($contentTypes | Sort-Object)
        functions    = @($functions    | Sort-Object)
        attributes   = @($attributes   | Sort-Object)
        blockTypes   = @($blockTypes   | Sort-Object)
        features     = @($features     | Sort-Object)
    }
}

# --- sweep -------------------------------------------------------------------
$records = New-Object System.Collections.ArrayList
$parsed = 0; $failed = 0; $i = 0
$failedFiles = New-Object System.Collections.ArrayList

foreach ($f in $files) {
    $i++
    if (-not $Quiet -and ($i % 200 -eq 0)) { Write-Info ("  ...{0}/{1}" -f $i, $files.Count) }
    try {
        $bytes = (Get-Item -LiteralPath $f.Full).Length
        $text  = [System.IO.File]::ReadAllText($f.Full)
        $root  = Parse-Template -Text $text
        [void]$records.Add((Get-TemplateRecord -Rel $f.Rel -Full $f.Full -Bytes $bytes -Root $root))
        $parsed++
    }
    catch {
        $failed++
        [void]$failedFiles.Add([pscustomobject]@{ File = $f.Rel; Error = $_.Exception.Message })
    }
}

Write-Info ("Parsed {0}, failed {1}." -f $parsed, $failed)

# --- corpus-wide facets (so the finder can show an overview cheaply) ---------
function Get-Facet { param([string]$Field)
    $h = @{}
    foreach ($r in $records) { foreach ($v in $r[$Field]) { $h[$v] = 1 + ($h[$v]) } }
    $o = [ordered]@{}
    foreach ($k in ($h.Keys | Sort-Object { -$h[$_] }, { $_ })) { $o[$k] = $h[$k] }
    $o
}

$version = if ($TeklaRoot) { Split-Path $TeklaRoot -Leaf } else { 'custom' }
$doc = [ordered]@{
    meta = [ordered]@{
        generated    = (Get-Date).ToString('s')
        teklaRoot    = $TeklaRoot
        version      = $version
        roots        = @($roots | ForEach-Object { $_.Base })
        filesScanned = $files.Count
        filesParsed  = $parsed
        filesFailed  = $failed
    }
    facets = [ordered]@{
        contentTypes = Get-Facet 'contentTypes'
        features     = Get-Facet 'features'
        functions    = Get-Facet 'functions'
        kinds        = Get-Facet 'kind'
    }
    templates = @($records)
}

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
# -Compress: this is a generated per-version artifact with ~2,700 entries; pretty-printing
# roughly doubles it for no benefit (the finder reads it, humans query via the finder).
$json = $doc | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Info ""
Write-Info ("Wrote index: {0}" -f $OutFile)
Write-Info ("  {0} templates from {1} of {2} files (version {3})." -f $records.Count, $parsed, $files.Count, $version)

# summary object for pipeline use
[pscustomobject]@{
    OutFile     = $OutFile
    Templates   = $records.Count
    FilesParsed = $parsed
    FilesFailed = $failed
}
