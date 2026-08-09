<#
.SYNOPSIS
    Prove the JSON IR pipeline is lossless: for every template under the given
    roots, parse -> JSON IR -> canonical emit -> re-parse, then require the two
    parse trees to be IDENTICAL — structure, ids, property order, exact values,
    and even token kinds (bare enum vs quoted string). Also runs the TplEd
    portability lint on every emitted text (must be zero findings — the
    canonical layout makes the crash classes unreachable).

.DESCRIPTION
    This is the determinism proof for ConvertFrom-TeklaTemplate.ps1 /
    ConvertTo-TeklaTemplate.ps1: if every shipped template survives the round
    trip bit-equal at the parse-tree level, the IR loses nothing the parser can
    see, and the emitter's canonical form is semantically transparent.

    Buckets per file:
      ok           round-tripped identically, emitted text lints clean
      parse-fail   the ORIGINAL file does not parse (pre-existing corpus noise,
                   not a pipeline defect; same files Get-TeklaGrammar skips)
      mismatch     round-tripped tree differs from the original (PIPELINE BUG)
      lint         emitted text has TplEd-portability findings (PIPELINE BUG)

    Exit code: 0 = no mismatch/lint, 1 = any pipeline defect.

.PARAMETER Path
    Files or directory roots (recursive *.tpl / *.rpt). Defaults to the newest
    install's Environments tree.

.PARAMETER TeklaRoot
    Tekla install root used when -Path is omitted (default: newest under
    C:\TeklaStructures).

.PARAMETER GrammarFile
    Kind census (default: assets\template-grammar.json).

.PARAMETER SchemaAll
    Additionally validate EVERY file's IR JSON against assets\template-schema.json
    with Test-Json (slow); failures land in the 'schema' bucket. Without this
    switch the schema gate is exercised only by ConvertTo-TeklaTemplate.ps1.

.PARAMETER Quiet
    Only the summary, no per-file detail lists.

.EXAMPLE
    tests\Test-TeklaTemplateRoundTrip.ps1
    # prove losslessness over the whole shipped 2026.0 corpus
#>
[CmdletBinding()]
param(
    [string[]] $Path,
    [string]   $TeklaRoot,
    [string]   $GrammarFile,
    [switch]   $SchemaAll,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
. "$scripts\_TemplateParser.ps1"
. "$scripts\_TemplateIR.ps1"
. "$scripts\_TemplateGrammar.ps1"

# --- resolve corpus (same defaulting as Test-TeklaTemplates.ps1) -------------
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
    if (-not $TeklaRoot) { throw "No corpus. Pass -Path or -TeklaRoot." }
    $env = Join-Path $TeklaRoot 'Environments'
    $Path = @((Test-Path $env) ? $env : $TeklaRoot)
}

$files = New-Object System.Collections.ArrayList
foreach ($r in $Path) {
    if (-not (Test-Path $r)) { throw "Path not found: $r" }
    if (Test-Path $r -PathType Leaf) { [void]$files.Add((Resolve-Path $r).Path); continue }
    Get-ChildItem $r -Recurse -File -Include '*.tpl', '*.rpt' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$files.Add($_.FullName) }
}
$files = @($files | Sort-Object -Unique)

$table = Get-TeklaKindTable -GrammarFile $GrammarFile
$schemaFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-schema.json'
if ($SchemaAll -and -not (Test-Path $schemaFile)) { throw "-SchemaAll needs $schemaFile (run New-TeklaTemplateSchema.ps1)." }

# --- strict tree comparison ---------------------------------------------------
# Returns $null when equal, else a human-readable path to the FIRST difference.
function Compare-TplValue {
    param($A, $B, [string]$Where)
    $aArr = $A -is [array]; $bArr = $B -is [array]
    if ($aArr -ne $bArr) { return "$($Where): tuple vs scalar" }
    if ($aArr) {
        if ($A.Count -ne $B.Count) { return "$($Where): tuple arity $($A.Count) vs $($B.Count)" }
        for ($i = 0; $i -lt $A.Count; $i++) {
            $d = Compare-TplValue $A[$i] $B[$i] "$Where[$i]"
            if ($d) { return $d }
        }
        return $null
    }
    if ($A -is [double] -or $B -is [double]) {
        if (([double]$A) -ne ([double]$B)) { return "$($Where): number $A vs $B" }
        return $null
    }
    if ([string]$A -cne [string]$B) { return "$($Where): '$A' vs '$B'" }
    return $null
}

function Compare-TplKind {
    param($A, $B, [string]$Where)
    $aArr = $A -is [array]; $bArr = $B -is [array]
    if ($aArr -ne $bArr) { return "$($Where): kind tuple vs scalar" }
    if ($aArr) {
        if ($A.Count -ne $B.Count) { return "$($Where): kind arity differs" }
        for ($i = 0; $i -lt $A.Count; $i++) {
            $d = Compare-TplKind $A[$i] $B[$i] "$Where[$i]"
            if ($d) { return $d }
        }
        return $null
    }
    if ([string]$A -cne [string]$B) { return "$($Where): kind '$A' vs '$B' (quoting changed)" }
    return $null
}

function Compare-TplNode {
    param($A, $B, [string]$Where)
    if ($A.Keyword -cne $B.Keyword) { return "$($Where): keyword '$($A.Keyword)' vs '$($B.Keyword)'" }
    if ([string]$A.Id -cne [string]$B.Id) { return "$($Where): id '$($A.Id)' vs '$($B.Id)'" }
    $ak = @($A.Props.Keys); $bk = @($B.Props.Keys)
    if ($ak.Count -ne $bk.Count) { return "$($Where): prop count $($ak.Count) vs $($bk.Count)" }
    for ($i = 0; $i -lt $ak.Count; $i++) {
        if ($ak[$i] -cne $bk[$i]) { return "$($Where): prop #$i '$($ak[$i])' vs '$($bk[$i])'" }
        $k = $ak[$i]
        $d = Compare-TplValue $A.Props[$k] $B.Props[$k] "$Where.$k"
        if ($d) { return $d }
        $d = Compare-TplKind $A.PropKinds[$k] $B.PropKinds[$k] "$Where.$k"
        if ($d) { return $d }
    }
    if ($A.Children.Count -ne $B.Children.Count) { return "$($Where): child count $($A.Children.Count) vs $($B.Children.Count)" }
    for ($i = 0; $i -lt $A.Children.Count; $i++) {
        $d = Compare-TplNode $A.Children[$i] $B.Children[$i] "$Where/$($A.Children[$i].Keyword)[$i]"
        if ($d) { return $d }
    }
    return $null
}

# --- sweep -------------------------------------------------------------------
$ok = 0
$parseFail = New-Object System.Collections.ArrayList
$mismatch = New-Object System.Collections.ArrayList
$lintBad = New-Object System.Collections.ArrayList
$schemaBad = New-Object System.Collections.ArrayList
$i = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($f in $files) {
    $i++
    if (-not $Quiet -and ($i % 200 -eq 0)) { [Console]::Error.WriteLine("  ...$i/$($files.Count) ($([int]$sw.Elapsed.TotalSeconds)s)") }
    try {
        $text = [System.IO.File]::ReadAllText($f)
        $orig = Parse-Template -Text $text
    }
    catch {
        [void]$parseFail.Add([pscustomobject]@{ File = $f; Error = $_.Exception.Message })
        continue
    }
    try {
        $ir = ConvertTo-TeklaIRNode -Node $orig -Table $table
        if ($SchemaAll) {
            $json = ConvertTo-TeklaIRJson -Ir $ir
            if (-not (Test-Json -Json $json -SchemaFile $schemaFile -ErrorAction SilentlyContinue)) {
                [void]$schemaBad.Add([pscustomobject]@{ File = $f; Error = 'IR JSON fails schema validation' })
            }
        }
        $emitted = ConvertTo-TeklaTemplateText -Ir $ir -Table $table
        $back = Parse-Template -Text $emitted
        $diff = Compare-TplNode $orig $back 'template'
        if ($diff) {
            [void]$mismatch.Add([pscustomobject]@{ File = $f; Error = $diff })
            continue
        }
        $lint = @(Find-TplEdIncompatibilities -Text $emitted)
        if ($lint.Count -gt 0) {
            [void]$lintBad.Add([pscustomobject]@{ File = $f; Error = ($lint -join ' | ') })
            continue
        }
        $ok++
    }
    catch {
        [void]$mismatch.Add([pscustomobject]@{ File = $f; Error = "pipeline threw: $($_.Exception.Message)" })
    }
}
$sw.Stop()

# --- report ------------------------------------------------------------------
"Round-trip sweep: $($files.Count) files in $([int]$sw.Elapsed.TotalSeconds)s"
"  ok          $ok"
"  parse-fail  $($parseFail.Count)   (original unparseable — corpus noise, not pipeline)"
"  mismatch    $($mismatch.Count)"
"  lint        $($lintBad.Count)"
if ($SchemaAll) { "  schema      $($schemaBad.Count)" }

if (-not $Quiet) {
    foreach ($bucket in @(@('PARSE-FAIL', $parseFail), @('MISMATCH', $mismatch), @('LINT', $lintBad), @('SCHEMA', $schemaBad))) {
        $name = $bucket[0]; $list = $bucket[1]
        if ($list.Count -gt 0) {
            ""
            "${name}:"
            foreach ($e in $list) { "  $($e.File)"; "      $($e.Error)" }
        }
    }
}

$bad = $mismatch.Count + $lintBad.Count + $schemaBad.Count
exit (($bad -gt 0) ? 1 : 0)
