<#
.SYNOPSIS
    Read the Template Editor's own reference data from a local Tekla installation:
    the valid content types, the value-field datatype/unit/precision classes, and the
    list of formula functions documented in the shipped help. Windows PowerShell 5.1+,
    no modules to install.

.DESCRIPTION
    Like Get-TeklaAttributes.ps1 (which extracts the attribute catalog), this pulls the
    *other* version-specific reference lists straight from the install so they are always
    correct for the target machine and version, instead of relying on bundled text:

      -ContentTypes  reads  …\TplEd\settings\contenttypes.lst
                     -> every value that a row's `contenttype` / a value field may use.
      -Datatypes     reads  …\TplEd\settings\valuefieldclasses.lst
                     -> each value-field class (meaning) with its units and precisions,
                        i.e. the arguments to format(value,"meaning","unit","precision").
      -Functions     scans  …\TplEd\Help\Content\tpled_*functions*.html (+ operators)
                     -> the formula/rule functions that this version documents.

    With no switch, all three sections are printed.

.PARAMETER TeklaRoot
    Root of a Tekla install, e.g. "C:\TeklaStructures\2025.0". If omitted, the newest
    version under C:\TeklaStructures (or $env:TS_BIN's parent) is used.

.PARAMETER ContentTypes
    Print the valid content types.

.PARAMETER Datatypes
    Print the value-field datatype/unit/precision classes.

.PARAMETER Functions
    Print the documented formula/rule functions (grouped by family).

.PARAMETER OutFile
    Write output to this path (UTF-8) instead of the console.

.EXAMPLE
    # Everything, auto-detecting the newest install
    .\Get-TeklaTemplateInfo.ps1

.EXAMPLE
    # Just the datatype/unit classes for a pinned version
    .\Get-TeklaTemplateInfo.ps1 -TeklaRoot "C:\TeklaStructures\2025.0" -Datatypes

.EXAMPLE
    # The function list, e.g. to confirm a function exists in this version
    .\Get-TeklaTemplateInfo.ps1 -Functions
#>
[CmdletBinding()]
param(
    [string] $TeklaRoot,
    [switch] $ContentTypes,
    [switch] $Datatypes,
    [switch] $Functions,
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'

function Resolve-TeklaRoot {
    param([string]$Root)
    if ($Root) {
        if (-not (Test-Path $Root)) { throw "TeklaRoot not found: $Root" }
        return $Root
    }
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

function Get-TplEdDir {
    param([string]$Root)
    $d = Join-Path $Root 'bin\applications\Tekla\Tools\TplEd'
    if (-not (Test-Path $d)) { throw "Template Editor folder not found: $d" }
    $d
}

function Get-ContentTypeList {
    param([string]$TplEd)
    $path = Join-Path $TplEd 'settings\contenttypes.lst'
    if (-not (Test-Path $path)) { throw "Not found: $path" }
    [System.IO.File]::ReadLines($path) |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('//') }
}

function Get-DatatypeClasses {
    param([string]$TplEd)
    $path = Join-Path $TplEd 'settings\valuefieldclasses.lst'
    if (-not (Test-Path $path)) { throw "Not found: $path" }
    foreach ($raw in [System.IO.File]::ReadLines($path)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('//')) { continue }
        # "Class = units { precisions }"  (units/precisions optional)
        $parts = $line -split '\s*=\s*', 2
        $name  = $parts[0].Trim()
        if (-not $name) { continue }
        $units = ''; $prec = ''
        if ($parts.Count -eq 2) {
            $rhs = $parts[1]
            # pull out any { ... } precision groups, then whatever's left is units
            $precMatches = [regex]::Matches($rhs, '\{([^}]*)\}') | ForEach-Object { $_.Groups[1].Value.Trim() }
            if ($precMatches) { $prec = ($precMatches -join '; ') }
            $units = ($rhs -replace '\{[^}]*\}', '').Trim() -replace '\s*,\s*', ', '
        }
        [pscustomobject]@{ Class = $name; Units = $units; Precisions = $prec }
    }
}

function Get-DocumentedFunctions {
    param([string]$TplEd)
    $help = Join-Path $TplEd 'Help\Content'
    if (-not (Test-Path $help)) { throw "Help content not found: $help" }
    # Each function has its own leaf page tpled_<family>_<name>.html. Map the family
    # prefix to a readable group; the trailing token is the function name.
    $families = [ordered]@{
        'tpled_attribute_functions_'          = 'Attribute'
        'tpled_value_field_functions_'        = 'Value field'
        'tpled_control_functions_'            = 'Control'
        'tpled_data_type_conversion_functions_' = 'Conversion'
        'tpled_string_operations_'            = 'String'
        'tpled_miscellaneous_functions_'      = 'Math/misc'
        'tpled_statistical_functions_'        = 'Statistical'
    }
    $files = Get-ChildItem $help -Filter 'tpled_*.html' -File
    foreach ($fam in $families.GetEnumerator()) {
        foreach ($f in $files) {
            $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($base -like "$($fam.Key)*") {
                $fn = $base.Substring($fam.Key.Length)
                if ($fn) { [pscustomobject]@{ Family = $fam.Value; Function = $fn } }
            }
        }
    }
    # Trigonometric functions live in one page as a table, not leaf pages.
    if (Test-Path (Join-Path $help 'tpled_trigonometric_functions.html')) {
        foreach ($t in 'sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','atan2') {
            [pscustomobject]@{ Family = 'Trigonometric'; Function = $t }
        }
    }
}

# --- main -------------------------------------------------------------------
$root  = Resolve-TeklaRoot -Root $TeklaRoot
$tpled = Get-TplEdDir -Root $root

# Default: show all sections.
if (-not ($ContentTypes -or $Datatypes -or $Functions)) {
    $ContentTypes = $true; $Datatypes = $true; $Functions = $true
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Template Editor reference — $root")
[void]$sb.AppendLine()

if ($ContentTypes) {
    [void]$sb.AppendLine('## Content types (valid `contenttype` values)')
    foreach ($ct in Get-ContentTypeList -TplEd $tpled) { [void]$sb.AppendLine("  $ct") }
    [void]$sb.AppendLine()
}

if ($Datatypes) {
    [void]$sb.AppendLine('## Value-field datatype/unit/precision classes')
    [void]$sb.AppendLine(('{0,-22} {1}' -f 'Class', 'Units  { precisions }'))
    foreach ($c in Get-DatatypeClasses -TplEd $tpled) {
        $line = '{0,-22} {1}' -f $c.Class, $c.Units
        if ($c.Precisions) { $line += "   { $($c.Precisions) }" }
        [void]$sb.AppendLine("  $line")
    }
    [void]$sb.AppendLine()
}

if ($Functions) {
    [void]$sb.AppendLine('## Documented formula/rule functions')
    $funcs = Get-DocumentedFunctions -TplEd $tpled
    foreach ($grp in ($funcs | Group-Object Family)) {
        $names = ($grp.Group | ForEach-Object { $_.Function } | Sort-Object) -join ', '
        [void]$sb.AppendLine("  $($grp.Name): $names")
    }
    [void]$sb.AppendLine()
}

$out = $sb.ToString()
if ($OutFile) {
    $out | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Wrote reference to $OutFile"
} else {
    $out
}