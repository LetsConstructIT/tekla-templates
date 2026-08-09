<#
.SYNOPSIS
    Extract the Tekla Structures Template Editor content-attribute catalog from a
    local Tekla installation. Windows PowerShell 5.1+ only — no modules to install.

.DESCRIPTION
    The valid value-field attributes (PART.PROFILE, ASSEMBLY.WEIGHT, ...) are NOT
    a fixed list: they ship with each Tekla version inside
        <TeklaBin>\applications\Tekla\Tools\TplEd\settings\contentattributes_global.lst
    plus companion files for user-defined attributes. Because this changes between
    versions and environments, this script reads the catalog on THIS machine so you
    always get an accurate, version-correct list instead of stale bundled data.

    The .lst file has two parts:
      1. Definitions  : "Name Datatype Justify Cacheable Length Decimals UnitType Unit Precision"
      2. [BINDINGS]   : "CONTENTTYPE = ATTRIBUTE" lines mapping each attribute to the
                        object types (ASSEMBLY, PART, BOLT, ...) that expose it.
    This script parses both and joins them, so you can answer "what can I put in a
    row whose contenttype is ASSEMBLY, and what is WEIGHT's datatype/unit?".

.PARAMETER TeklaRoot
    Root of a Tekla install, e.g. "C:\TeklaStructures\2025.0". If omitted, the newest
    version found under C:\TeklaStructures (or $env:TS_BIN's parent) is used.

.PARAMETER ContentType
    One or more content types to filter by (e.g. ASSEMBLY, PART, BOLT). Case-insensitive.
    Omit to include attributes for every content type.

.PARAMETER Name
    Substring (regex) to match against attribute names, e.g. "WEIGHT" or "^PROFILE".

.PARAMETER IncludeUserDefined
    Also parse contentattributes_userdefined.lst / _customattributes.lst if present
    (project UDAs and custom attributes added on top of the global set).

.PARAMETER Format
    Table (default, console-friendly), Csv, Markdown, or Json.

.PARAMETER OutFile
    Write the output to this path instead of the console (UTF-8).

.EXAMPLE
    # All attributes available to an ASSEMBLY row, as a table
    .\Get-TeklaAttributes.ps1 -ContentType ASSEMBLY

.EXAMPLE
    # Every weight-related attribute across all object types, to CSV
    .\Get-TeklaAttributes.ps1 -Name WEIGHT -Format Csv -OutFile weights.csv

.EXAMPLE
    # Point at a specific version and dump PART attributes as Markdown for a reference doc
    .\Get-TeklaAttributes.ps1 -TeklaRoot "C:\TeklaStructures\2025.0" -ContentType PART -Format Markdown
#>
[CmdletBinding()]
param(
    [string]   $TeklaRoot,
    [string[]] $ContentType,
    [string]   $Name,
    [switch]   $IncludeUserDefined,
    [ValidateSet('Table', 'Csv', 'Markdown', 'Json')]
    [string]   $Format = 'Table',
    [string]   $OutFile
)

$ErrorActionPreference = 'Stop'

function Resolve-TeklaRoot {
    param([string]$Root)
    if ($Root) {
        if (-not (Test-Path $Root)) { throw "TeklaRoot not found: $Root" }
        return $Root
    }
    # Prefer the env var Tekla itself sets, then fall back to newest under C:\TeklaStructures
    if ($env:TS_BIN -and (Test-Path $env:TS_BIN)) {
        return (Get-Item $env:TS_BIN).Parent.Parent.FullName
    }
    $base = 'C:\TeklaStructures'
    if (-not (Test-Path $base)) {
        throw "No -TeklaRoot given and $base does not exist. Pass -TeklaRoot explicitly."
    }
    $newest = Get-ChildItem $base -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if (-not $newest) { throw "No version folders (e.g. 2025.0) found under $base." }
    Write-Verbose "Auto-selected Tekla version: $($newest.Name)"
    return $newest.FullName
}

function Get-CatalogFiles {
    param([string]$Root, [switch]$WithUserDefined)
    $settings = Join-Path $Root 'bin\applications\Tekla\Tools\TplEd\settings'
    if (-not (Test-Path $settings)) {
        throw "Template Editor settings folder not found: $settings"
    }
    $files = @(Join-Path $settings 'contentattributes_global.lst')
    if ($WithUserDefined) {
        foreach ($extra in 'contentattributes_userdefined.lst', 'contentattributes_customattributes.lst') {
            $p = Join-Path $settings $extra
            if (Test-Path $p) { $files += $p }
        }
    }
    $files | Where-Object { Test-Path $_ }
}

function Parse-Catalog {
    param([string]$Path)

    $defs     = @{}   # attribute name -> definition object
    $bindings = @{}   # content type    -> [ordered attribute names]
    $section  = 'DEF'

    foreach ($raw in [System.IO.File]::ReadLines($Path)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('//')) { continue }
        if ($line -like '`[BINDINGS`]*') { $section = 'BIND'; continue }

        if ($section -eq 'DEF') {
            # Whitespace-delimited columns; '*' means "use default / not applicable".
            $c = $line -split '\s+'
            if ($c.Count -lt 2) { continue }
            $defs[$c[0]] = [pscustomobject]@{
                Attribute = $c[0]
                Datatype  = $c[1]
                Justify   = if ($c.Count -gt 2) { $c[2] } else { '' }
                Cacheable = if ($c.Count -gt 3) { $c[3] } else { '' }
                Length    = if ($c.Count -gt 4) { $c[4] } else { '' }
                Decimals  = if ($c.Count -gt 5) { $c[5] } else { '' }
                UnitType  = if ($c.Count -gt 6) { $c[6] } else { '' }
                Unit      = if ($c.Count -gt 7) { $c[7] } else { '' }
                Precision = if ($c.Count -gt 8) { $c[8] } else { '' }
            }
        }
        else {
            # "CONTENTTYPE = ATTRIBUTE"
            $parts = $line -split '\s*=\s*', 2
            if ($parts.Count -ne 2) { continue }
            $ct = $parts[0].Trim()
            $at = ($parts[1] -split '//')[0].Trim()   # strip trailing comments
            if (-not $bindings.ContainsKey($ct)) { $bindings[$ct] = New-Object System.Collections.ArrayList }
            [void]$bindings[$ct].Add($at)
        }
    }
    [pscustomobject]@{ Defs = $defs; Bindings = $bindings }
}

# --- main -------------------------------------------------------------------
$root  = Resolve-TeklaRoot -Root $TeklaRoot
$files = Get-CatalogFiles -Root $root -WithUserDefined:$IncludeUserDefined
Write-Verbose "Parsing: $($files -join '; ')"

$defs     = @{}
$bindings = @{}
foreach ($f in $files) {
    $parsed = Parse-Catalog -Path $f
    foreach ($k in $parsed.Defs.Keys)     { $defs[$k] = $parsed.Defs[$k] }
    foreach ($k in $parsed.Bindings.Keys) {
        if (-not $bindings.ContainsKey($k)) { $bindings[$k] = New-Object System.Collections.ArrayList }
        [void]$bindings[$k].AddRange($parsed.Bindings[$k])
    }
}

# Build flat rows: one per (contenttype, attribute), enriched with the definition.
$rows = New-Object System.Collections.Generic.List[object]
$wantCT = if ($ContentType) { $ContentType | ForEach-Object { $_.ToUpper() } } else { $null }

foreach ($ct in ($bindings.Keys | Sort-Object)) {
    if ($wantCT -and ($ct.ToUpper() -notin $wantCT)) { continue }
    foreach ($attr in $bindings[$ct]) {
        # A "#N" suffix (NUMBER#1 INTEGER vs NUMBER#2 CHARACTER) disambiguates homonyms that
        # differ only by datatype. It is catalog-only bookkeeping: Tekla resolves it from the
        # content type / prefix, and no shipped template writes it. Strip it before both
        # filtering and output, so -Name matches the name the user types in a formula.
        $display = $attr -replace '#\d+$', ''
        if ($Name -and ($display -notmatch $Name)) { continue }
        # Dotted attributes (HISTORY.OWNER) key off the part after the dot for the def lookup.
        $defKey = if ($defs.ContainsKey($attr)) { $attr } else { ($attr -split '\.')[-1] }
        $d = $defs[$defKey]
        $rows.Add([pscustomobject]@{
            ContentType = $ct
            Attribute   = $display
            Datatype    = if ($d) { $d.Datatype } else { '?' }
            Unit        = if ($d) { $d.Unit }     else { '' }
            Decimals    = if ($d) { $d.Decimals } else { '' }
            Length      = if ($d) { $d.Length }   else { '' }
        })
    }
}

if ($rows.Count -eq 0) {
    Write-Warning "No attributes matched. Content types present: $(( $bindings.Keys | Sort-Object ) -join ', ')"
    return
}

# --- render -----------------------------------------------------------------
$out = switch ($Format) {
    'Json'     { $rows | ConvertTo-Json -Depth 3 }
    'Csv'      { $rows | ConvertTo-Csv -NoTypeInformation }
    'Markdown' {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('| Content type | Attribute | Datatype | Unit | Dec | Len |')
        [void]$sb.AppendLine('|---|---|---|---|---|---|')
        foreach ($r in $rows) {
            [void]$sb.AppendLine("| $($r.ContentType) | $($r.Attribute) | $($r.Datatype) | $($r.Unit) | $($r.Decimals) | $($r.Length) |")
        }
        $sb.ToString()
    }
    default    { $rows | Format-Table -AutoSize | Out-String }
}

if ($OutFile) {
    $out | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Wrote $($rows.Count) rows to $OutFile"
} else {
    $out
}
