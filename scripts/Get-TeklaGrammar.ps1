<#
.SYNOPSIS
    Harvest the Tekla Template Editor file GRAMMAR (block types and their legal
    property keys / enum value keywords) empirically from the shipped template
    corpus, and emit it as a JSON allow-list.

.DESCRIPTION
    Every .tpl / .rpt file shipped under a Tekla install is, by definition, grammar
    that the real Template Editor accepts. Scanning that whole corpus yields a
    ground-truth map of

        block keyword  ->  { property keys it may carry ; enum values each key takes ;
                             child block keywords it may contain }

    with ZERO invention. The renderer's -Strict validator (Render-TeklaTemplate.ps1)
    loads this map to flag a property key / block type / enum value that never appears
    in any shipped template — i.e. one an LLM most likely hallucinated.

    This is the GRAMMAR (line/field/text block properties), NOT the Tekla content
    attribute catalog (PART.PROFILE etc.) — that comes from Get-TeklaAttributes.ps1.

    Files that fail to parse are counted and skipped (the corpus contains a few
    genuinely malformed or non-template files); they don't abort the harvest.

.PARAMETER TeklaRoot
    A Tekla install root (e.g. C:\TeklaStructures\2026.0) whose Environments tree is
    scanned. Defaults to the newest version found under C:\TeklaStructures.

.PARAMETER Path
    Extra file or directory roots to include in the corpus (searched recursively for
    *.tpl / *.rpt). Repeatable. Use to fold in a firm/project template library.

.PARAMETER OutFile
    Where to write the JSON allow-list. Defaults to
    <skill>\assets\template-grammar.json (the location the -Strict validator loads).

.PARAMETER MinCount
    Also print, to stderr, every (block, key) pair seen in FEWER than this many files
    — a hand-audit aid: a legal-but-rare key and a typo in a shipped file both look
    rare, so a human can eyeball the low-frequency tail. Default 2. Does not affect
    what is written (every observed key is allow-listed).

.PARAMETER MaxValues
    A property key with more than this many distinct bare-identifier values is treated as
    free-form (name, notes, a project palette) and its value list is dropped from the output
    — only closed enums / booleans keep their values, which is all the -Strict validator
    consults. Keeps the allow-list small and free of environment-specific strings. Default 24.

.PARAMETER Quiet
    Suppress per-progress output.

.EXAMPLE
    scripts\Get-TeklaGrammar.ps1
    # harvest newest install -> assets\template-grammar.json

.EXAMPLE
    scripts\Get-TeklaGrammar.ps1 -TeklaRoot C:\TeklaStructures\2024.0 -Path D:\FirmTemplates
    # pin a version and fold in a firm library
#>
[CmdletBinding()]
param(
    [string]   $TeklaRoot,
    [string[]] $Path,
    [string]   $OutFile,
    [int]      $MinCount = 2,
    [int]      $MaxValues = 24,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_TemplateParser.ps1"

function Write-Info { param([string]$Msg) if (-not $Quiet) { Write-Host $Msg } }

# --- resolve corpus roots ----------------------------------------------------
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

$roots = New-Object System.Collections.ArrayList
if ($TeklaRoot) {
    if (-not (Test-Path $TeklaRoot)) { throw "TeklaRoot not found: $TeklaRoot" }
    $env = Join-Path $TeklaRoot 'Environments'
    [void]$roots.Add((Test-Path $env) ? $env : $TeklaRoot)
}
if ($Path) { foreach ($p in $Path) { if (-not (Test-Path $p)) { throw "Path not found: $p" }; [void]$roots.Add((Resolve-Path $p).Path) } }
if ($roots.Count -eq 0) { throw "No corpus roots. Pass -TeklaRoot or -Path (no install found under C:\TeklaStructures)." }

if (-not $OutFile) { $OutFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-grammar.json' }

Write-Info "Corpus roots:"
foreach ($r in $roots) { Write-Info "  $r" }

# --- gather files ------------------------------------------------------------
$files = New-Object System.Collections.ArrayList
foreach ($r in $roots) {
    if (Test-Path $r -PathType Leaf) { [void]$files.Add($r); continue }
    Get-ChildItem $r -Recurse -File -Include '*.tpl', '*.rpt' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$files.Add($_.FullName) }
}
$files = $files | Sort-Object -Unique
Write-Info ("Found {0} template files." -f $files.Count)

# --- harvest -----------------------------------------------------------------
# blocks[keyword] = @{ Count; Props=@{ key = @{ Count; Values=HashSet } }; Children=@{ childKw = Count } }
$blocks = @{}
$parsed = 0; $failed = 0; $i = 0
$failedFiles = New-Object System.Collections.ArrayList

# Flatten a PropKinds entry to a signature string: 'string' | 'ident' | 'number' |
# 'tuple(number,number)' (tuples recurse). The signature keys the per-prop kind
# census that the canonical emitter (_TemplateIR.ps1) uses to decide quoting.
function Get-KindSig {
    param($K)
    if ($K -is [array]) { return 'tuple(' + (($K | ForEach-Object { Get-KindSig $_ }) -join ',') + ')' }
    return [string]$K
}

function Record-Block {
    param($Node)
    $kw = $Node.Keyword
    if (-not $blocks.ContainsKey($kw)) {
        $blocks[$kw] = @{ Count = 0; Props = @{}; Children = @{} }
    }
    $b = $blocks[$kw]
    $b.Count++
    foreach ($k in $Node.Props.Keys) {
        if (-not $b.Props.ContainsKey($k)) {
            $b.Props[$k] = @{ Count = 0; Values = (New-Object 'System.Collections.Generic.HashSet[string]'); Kinds = @{} }
        }
        $p = $b.Props[$k]
        $p.Count++
        # census of source token kinds — how this prop is WRITTEN in shipped files
        # (bare enum keyword vs quoted string vs number vs tuple shape)
        $sig = Get-KindSig $Node.PropKinds[$k]
        if (-not $p.Kinds.ContainsKey($sig)) { $p.Kinds[$sig] = 0 }
        $p.Kinds[$sig]++
        # only a BARE identifier token is an enum keyword (LEFT / CENTERED / TRUE ...);
        # a quoted string that merely looks like one (contenttype = "PART") is content,
        # not grammar vocabulary, and is excluded now that the parser reports kinds.
        $v = $Node.Props[$k]
        if ($sig -eq 'ident' -and $v -is [string] -and $v -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            [void]$p.Values.Add($v)
        }
    }
    foreach ($c in $Node.Children) {
        if (-not $b.Children.ContainsKey($c.Keyword)) { $b.Children[$c.Keyword] = 0 }
        $b.Children[$c.Keyword]++
    }
}

foreach ($f in $files) {
    $i++
    if (-not $Quiet -and ($i % 200 -eq 0)) { Write-Info ("  ...{0}/{1}" -f $i, $files.Count) }
    try {
        $text = [System.IO.File]::ReadAllText($f)
        $root = Parse-Template -Text $text
        foreach ($node in (Get-AllBlocks $root)) { Record-Block $node }
        $parsed++
    }
    catch {
        $failed++
        [void]$failedFiles.Add([pscustomobject]@{ File = $f; Error = $_.Exception.Message })
    }
}

Write-Info ("Parsed {0}, failed {1}." -f $parsed, $failed)

# --- shape the JSON ----------------------------------------------------------
$version = if ($TeklaRoot) { Split-Path $TeklaRoot -Leaf } else { 'custom' }
$outBlocks = [ordered]@{}
foreach ($kw in ($blocks.Keys | Sort-Object)) {
    $b = $blocks[$kw]
    $props = [ordered]@{}
    foreach ($k in ($b.Props.Keys | Sort-Object)) {
        $p = $b.Props[$k]
        # A key with more than -MaxValues distinct bare-identifier values is a free-form
        # field (name, notes, a project palette), not a closed enum — store no value list
        # for it (empty = "don't enum-check"). This keeps the allow-list small and free of
        # environment-specific strings; closed enums/booleans (all tiny) are kept in full.
        $vals = if ($p.Values.Count -le $MaxValues) { @($p.Values | Sort-Object) } else { @() }
        $kinds = [ordered]@{}
        foreach ($sig in ($p.Kinds.Keys | Sort-Object)) { $kinds[$sig] = $p.Kinds[$sig] }
        $props[$k] = [ordered]@{
            count  = $p.Count
            values = $vals
            kinds  = $kinds
        }
    }
    $children = [ordered]@{}
    foreach ($ck in ($b.Children.Keys | Sort-Object)) { $children[$ck] = $b.Children[$ck] }
    $outBlocks[$kw] = [ordered]@{
        count    = $b.Count
        props    = $props
        children = $children
    }
}

$doc = [ordered]@{
    meta = [ordered]@{
        generated    = (Get-Date).ToString('s')
        teklaRoot    = $TeklaRoot
        version      = $version
        extraPaths   = @($Path)
        filesScanned = $files.Count
        filesParsed  = $parsed
        filesFailed  = $failed
        blockTypes   = $outBlocks.Count
    }
    blocks = $outBlocks
}

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$json = $doc | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Info ""
Write-Info ("Wrote allow-list: {0}" -f $OutFile)
Write-Info ("  {0} block types, from {1} of {2} files (version {3})." -f $outBlocks.Count, $parsed, $files.Count, $version)

# --- low-frequency audit tail (stderr) ---------------------------------------
if ($MinCount -gt 1) {
    $rare = foreach ($kw in ($blocks.Keys | Sort-Object)) {
        foreach ($k in ($blocks[$kw].Props.Keys | Sort-Object)) {
            $c = $blocks[$kw].Props[$k].Count
            if ($c -lt $MinCount) { "{0,-18} {1,-24} seen in {2} file(s)" -f $kw, $k, $c }
        }
    }
    if ($rare) {
        [Console]::Error.WriteLine("`nLow-frequency (block, key) pairs (< $MinCount files) — audit for shipped-template typos:")
        foreach ($line in $rare) { [Console]::Error.WriteLine("  $line") }
    }
}

# summary object for pipeline use
[pscustomobject]@{
    OutFile      = $OutFile
    BlockTypes   = $outBlocks.Count
    FilesParsed  = $parsed
    FilesFailed  = $failed
}
