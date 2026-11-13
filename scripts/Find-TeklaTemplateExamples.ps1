<#
.SYNOPSIS
    Search the shipped Tekla template corpus for a working example that already uses
    the content types, functions, attributes, block types or structural tricks you
    need — instead of reconstructing the pattern from scratch.

.DESCRIPTION
    Loads the JSON index built by Get-TeklaTemplateIndex.ps1 (default
    <skill>\assets\template-index.json) and filters it. All axes AND together; within
    an axis, every value you list must be present (also AND). With NO filters it prints
    a corpus overview (counts by content type, feature and function) so you can see what
    is searchable.

    Answers questions like "show me a template that uses REBAR rows with Sum()":
        Find-TeklaTemplateExamples.ps1 -ContentType REBAR -Function Sum

.PARAMETER ContentType
    Require these row content types (PART, ASSEMBLY, REBAR, DRAWING, REVISION …). Repeatable.

.PARAMETER Function
    Require these formula functions (GetValue, Sum, Total, format, match, TranslatedText …).
    Repeatable. Case-insensitive.

.PARAMETER Attribute
    Require these GetValue() attributes. A bare name matches the attribute itself OR any
    prefixed form ending in it (PROFILE matches PROFILE and ASSEMBLY.PROFILE). Wildcards
    (`*`) match literally against the full attribute. Repeatable.

.PARAMETER BlockType
    Require these block keywords (valuefield, lineorarc, text, picture, group …). Repeatable.

.PARAMETER Feature
    Require these named tricks. Run with no args to see the list under "Features". e.g.
    nested-rows, combine, oncombine-sum, footer-sum, hidden-rows, current-drawing,
    imperial-branch, control-flow, summary-band, single-rebar, revision-table,
    drawing-table, csv-export, xls-html. Repeatable.

.PARAMETER Kind
    Restrict to 'rpt' (reports) or 'tpl' (drawing tables).

.PARAMETER Type
    Restrict to 'TEXTUAL' or 'GRAPHICAL'.

.PARAMETER Text
    Case-insensitive substring matched against the file path and name.

.PARAMETER Show
    Print the FULL record (all axes) for every match, and — for a single match, or with
    -Show on a specific -Text/-Path — the file's location so you can open it.

.PARAMETER Path
    A path substring identifying one template; prints its full record plus its resolved
    on-disk location (and, with -Content, its text).

.PARAMETER Content
    With -Path (or a single match), also print the template file's text.

.PARAMETER Largest
    Rank richest-first (most rows+fields). Default is simplest-first — the smallest clear
    example of the pattern floats to the top.

.PARAMETER Top
    Max matches to list. Default 20. 0 = all.

.PARAMETER Json
    Emit matching records as JSON (for scripting) instead of the formatted list.

.PARAMETER IndexFile
    Index JSON to load. Default <skill>\assets\template-index.json.

.PARAMETER TeklaRoot
    Re-root displayed/opened paths against this install instead of the one the index was
    built from (use when your Tekla is installed somewhere else). Defaults to the index's
    own root, else the newest install under C:\TeklaStructures.

.EXAMPLE
    scripts\Find-TeklaTemplateExamples.ps1 -ContentType REBAR -Function Sum
    # reports/tables that iterate REBAR and total with Sum()

.EXAMPLE
    scripts\Find-TeklaTemplateExamples.ps1 -Feature current-drawing,footer-sum -Kind tpl
    # drawing-embedded BOMs with a grand-total footer

.EXAMPLE
    scripts\Find-TeklaTemplateExamples.ps1 -Attribute ASSEMBLY.WEIGHT -Show
    # every template that reads a related assembly's weight, full detail

.EXAMPLE
    scripts\Find-TeklaTemplateExamples.ps1 -Path CU_BOM.tpl -Content
    # dump one known template's record and text
#>
[CmdletBinding()]
param(
    [string[]] $ContentType,
    [string[]] $Function,
    [string[]] $Attribute,
    [string[]] $BlockType,
    [string[]] $Feature,
    [ValidateSet('rpt', 'tpl')] [string] $Kind,
    [ValidateSet('TEXTUAL', 'GRAPHICAL')] [string] $Type,
    [string]   $Text,
    [switch]   $Show,
    [string]   $Path,
    [switch]   $Content,
    [switch]   $Largest,
    [int]      $Top = 20,
    [switch]   $Json,
    [string]   $IndexFile,
    [string]   $TeklaRoot
)

$ErrorActionPreference = 'Stop'

# --- load index --------------------------------------------------------------
if (-not $IndexFile) { $IndexFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-index.json' }
if (-not (Test-Path $IndexFile)) {
    throw "Index not found: $IndexFile`nBuild it first:  scripts\Get-TeklaTemplateIndex.ps1"
}
$index = Get-Content -LiteralPath $IndexFile -Raw | ConvertFrom-Json
$all = @($index.templates)

# --- resolve the root that displayed/opened paths hang off -------------------
function Resolve-Root {
    if ($TeklaRoot) {
        $e = Join-Path $TeklaRoot 'Environments'
        return (Test-Path $e) ? $e : $TeklaRoot
    }
    foreach ($r in @($index.meta.roots)) { if ($r -and (Test-Path $r)) { return $r } }
    $base = 'C:\TeklaStructures'
    if (Test-Path $base) {
        $newest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if ($newest) {
            $e = Join-Path $newest.FullName 'Environments'
            return (Test-Path $e) ? $e : $newest.FullName
        }
    }
    return $null
}
$root = Resolve-Root
function Resolve-File { param($Rel) if ($root) { $p = Join-Path $root ($Rel -replace '/', '\'); if (Test-Path $p) { return $p } } return $null }

# --- overview mode (no filters) ----------------------------------------------
$hasFilter = $ContentType -or $Function -or $Attribute -or $BlockType -or $Feature -or $Kind -or $Type -or $Text -or $Path
if (-not $hasFilter) {
    Write-Host ("Tekla template index — {0} templates (version {1}, generated {2})" -f `
        $all.Count, $index.meta.version, $index.meta.generated)
    Write-Host ("  {0} reports (.rpt), {1} drawing tables (.tpl)" -f `
        (@($all | Where-Object kind -eq 'rpt').Count), (@($all | Where-Object kind -eq 'tpl').Count))
    function Show-Facet { param($Title, $Facet, $Limit)
        Write-Host "`n$Title"
        $i = 0
        foreach ($p in $Facet.PSObject.Properties) {
            Write-Host ("  {0,-22} {1,5}" -f $p.Name, $p.Value)
            if ($Limit -and (++$i -ge $Limit)) { break }
        }
    }
    Show-Facet 'Content types (row contenttype):' $index.facets.contentTypes 0
    Show-Facet 'Features (structural tricks):'    $index.facets.features 0
    Show-Facet 'Functions (top 25):'              $index.facets.functions 25
    Write-Host "`nFilter with -ContentType / -Function / -Attribute / -Feature / -BlockType / -Kind / -Text."
    Write-Host 'e.g.  -ContentType REBAR -Function Sum      |      -Feature current-drawing,footer-sum -Kind tpl'
    return
}

# --- matchers ----------------------------------------------------------------
function Test-AllIn { param($Have, $Want)   # every Want present in Have (case-insensitive, exact)
    $set = @{}; foreach ($h in $Have) { $set[[string]$h.ToLower()] = 1 }
    foreach ($w in $Want) { if (-not $set.ContainsKey([string]$w.ToLower())) { return $false } }
    return $true
}
function Test-AttrMatch { param($Have, $Want)  # bare name matches suffix ".NAME"; wildcard matches literally
    foreach ($w in $Want) {
        $ok = $false
        foreach ($h in $Have) {
            if ($w -match '[\*\?]') { if ($h -like $w) { $ok = $true; break } }
            elseif ($h -ieq $w -or $h -like "*.$w") { $ok = $true; break }
        }
        if (-not $ok) { return $false }
    }
    return $true
}

$hits = foreach ($t in $all) {
    if ($ContentType -and -not (Test-AllIn $t.contentTypes $ContentType)) { continue }
    if ($Function    -and -not (Test-AllIn $t.functions    $Function))    { continue }
    if ($BlockType   -and -not (Test-AllIn $t.blockTypes   $BlockType))   { continue }
    if ($Feature     -and -not (Test-AllIn $t.features     $Feature))     { continue }
    if ($Attribute   -and -not (Test-AttrMatch $t.attributes $Attribute)) { continue }
    if ($Kind        -and $t.kind -ne $Kind)                             { continue }
    if ($Type        -and $t.type -ne $Type)                             { continue }
    if ($Text        -and ($t.path -notmatch [regex]::Escape($Text)) -and ($t.name -notmatch [regex]::Escape($Text))) { continue }
    if ($Path        -and ($t.path -notmatch [regex]::Escape($Path)))    { continue }
    $t
}

# rank: simplest-first by default (smallest clear example), richest-first with -Largest
$sorted = @(@($hits) | Sort-Object @{ Expression = { $_.rows + $_.fields }; Descending = [bool]$Largest }, @{ Expression = 'path' })

if ($Json) { $sorted | ConvertTo-Json -Depth 6; return }

if ($sorted.Count -eq 0) { Write-Host "No matching templates. Run with no arguments for the searchable facet lists."; return }

# --- detailed record printer -------------------------------------------------
function Write-Record { param($T, [switch]$WithFile)
    Write-Host ("`n{0}   [{1} {2}]  {3} rows, {4} fields, {5} B" -f $T.path, $T.kind, $T.type, $T.rows, $T.fields, $T.bytes)
    if ($T.contentTypes) { Write-Host ("  content : {0}" -f ($T.contentTypes -join ', ')) }
    if ($T.features)     { Write-Host ("  features: {0}" -f ($T.features -join ', ')) }
    if ($T.functions)    { Write-Host ("  funcs   : {0}" -f ($T.functions -join ', ')) }
    if ($T.blockTypes)   { Write-Host ("  blocks  : {0}" -f ($T.blockTypes -join ', ')) }
    if ($T.attributes)   { Write-Host ("  attrs   : {0}" -f ($T.attributes -join ', ')) }
    if ($WithFile) {
        $full = Resolve-File $T.path
        if ($full) { Write-Host ("  file    : {0}" -f $full) }
        else       { Write-Host ("  file    : (not on this machine; path relative to the index root)") }
    }
}

# single-target / -Path / -Show => full detail (+ optional content)
$single = ($sorted.Count -eq 1) -or $Path
if ($Show -or $Path) {
    $list = if ($Top -gt 0 -and -not $single) { $sorted | Select-Object -First $Top } else { $sorted }
    foreach ($t in $list) { Write-Record $t -WithFile }
    if ($Content) {   # dump the top match's text (intended for a single / -Path target)
        $full = Resolve-File $sorted[0].path
        if ($full) {
            Write-Host "`n----- $($sorted[0].path) -----"
            Get-Content -LiteralPath $full -Raw | Write-Host
        } else {
            Write-Host "`n(cannot show content — file not present on this machine)"
        }
    }
    Write-Host ("`n{0} match(es)." -f $sorted.Count)
    return
}

# --- default: compact ranked list -------------------------------------------
$list = if ($Top -gt 0) { $sorted | Select-Object -First $Top } else { $sorted }
foreach ($t in $list) {
    $ct = if ($t.contentTypes) { $t.contentTypes -join ',' } else { '-' }
    $ft = if ($t.features)     { ' | ' + ($t.features -join ',') } else { '' }
    Write-Host ("{0,-6} {1}" -f "[$($t.kind)]", $t.path)
    Write-Host ("        {0}{1}" -f $ct, $ft)
}
$shown = $list.Count
Write-Host ("`n{0} match(es){1}. -Show for full detail, -Path <name> -Content to dump one." -f `
    $sorted.Count, ($(if ($sorted.Count -gt $shown) { " (showing $shown)" } else { '' })))
