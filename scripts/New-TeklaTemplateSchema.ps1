<#
.SYNOPSIS
    Generate a JSON Schema (draft 2020-12) for the Tekla template JSON IR from
    the empirically harvested grammar census (assets\template-grammar.json).

.DESCRIPTION
    Deterministic derivation — the schema is a pure function of the census:

      block type   -> a $defs entry { block: const, id, props, children }
      prop         -> typed by its observed token kinds:
                        number            -> {"type":"number"}
                        quoted string     -> {"type":"string"}
                        bare ident, closed vocabulary (the same EnumKeys the
                          -Strict validator enforces)      -> {"enum":[...]}
                        bare ident, boolean (TRUE/FALSE)   -> boolean | "TRUE"/"FALSE"
                        bare ident, open (names, fields)   -> {"type":"string"}
                        tuple             -> array with element type + observed
                                             min/max arity
                      every prop also accepts the explicit override object
                      {"ident": "X"} / {"string": "X"} / {"number": n}.
      required     -> props present in 100% of that block's corpus instances
                      (what Template Editor itself always writes).
      children     -> only the child block types observed under that parent.

    Open-world caution (deliberate): free-content strings — formulas, names,
    rules, attribute references — are NOT enumerated, so USERDEFINED.* /
    ADVANCED_OPTION.* content is never rejected. The schema gates STRUCTURE;
    semantic checks stay with Render-TeklaTemplate.ps1 -Strict.

.PARAMETER GrammarFile
    The census produced by Get-TeklaGrammar.ps1
    (default: assets\template-grammar.json next to the skill).

.PARAMETER OutFile
    Where to write the schema (default: assets\template-schema.json — the
    location ConvertTo-TeklaTemplate.ps1 loads).

.EXAMPLE
    scripts\New-TeklaTemplateSchema.ps1
    # assets\template-grammar.json -> assets\template-schema.json
#>
[CmdletBinding()]
param(
    [string] $GrammarFile,
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'
$assets = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
if (-not $GrammarFile) { $GrammarFile = Join-Path $assets 'template-grammar.json' }
if (-not $OutFile) { $OutFile = Join-Path $assets 'template-schema.json' }
if (-not (Test-Path $GrammarFile)) { throw "Grammar census not found: $GrammarFile (run scripts\Get-TeklaGrammar.ps1 first)" }

$g = Get-Content $GrammarFile -Raw | ConvertFrom-Json -AsHashtable

# Keys with genuinely CLOSED vocabularies — keep in lockstep with
# $script:EnumKeys in _TemplateGrammar.ps1 (the -Strict validator).
$enumKeys = @(
    'justify', 'datatype', 'oncombine', 'sorttype', 'sortdirection', 'type',
    'filldirection', 'fillpolicy', 'fillstartfrom', 'outputpolicy'
)

$overrideRef = [ordered]@{ '$ref' = '#/$defs/formOverride' }

# Build the anyOf type list for one prop from its census entry.
function New-PropSchema {
    param([string]$Key, $P)
    $forms = New-Object System.Collections.ArrayList
    $sigs = @{}
    if ($P.kinds) { foreach ($s in $P.kinds.Keys) { $sigs[$s] = [int]$P.kinds[$s] } }
    $vals = @($P.values)

    if ($sigs.ContainsKey('number')) { [void]$forms.Add([ordered]@{ type = 'number' }) }

    if ($sigs.ContainsKey('ident')) {
        $isBool = ($vals.Count -gt 0) -and (@($vals | Where-Object { $_ -notin @('TRUE', 'FALSE') }).Count -eq 0)
        if ($isBool) {
            [void]$forms.Add([ordered]@{ type = 'boolean' })
            [void]$forms.Add([ordered]@{ enum = @('TRUE', 'FALSE') })
        }
        elseif (($enumKeys -contains $Key) -and $vals.Count -ge 2) {
            [void]$forms.Add([ordered]@{ enum = @($vals) })
        }
        else {
            [void]$forms.Add([ordered]@{ type = 'string' })
        }
    }
    if ($sigs.ContainsKey('string')) {
        if (-not ($forms | Where-Object { $_['type'] -eq 'string' })) {
            $s = [ordered]@{ type = 'string' }
            # 'notes' (template block only) is a fixed 120-char buffer in TplEd — a longer
            # value crashes it on open. Mirror of the Find-TplEdIncompatibilities lint.
            if ($Key -eq 'notes') { $s.maxLength = 120 }
            [void]$forms.Add($s)
        }
    }

    # tuple forms: one array schema covering every observed signature
    $tupleSigs = @($sigs.Keys | Where-Object { $_ -like 'tuple(*' })
    if ($tupleSigs.Count -gt 0) {
        $minA = [int]::MaxValue; $maxA = 0
        $elKinds = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($ts in $tupleSigs) {
            $inner = $ts.Substring(6, $ts.Length - 7)
            $els = if ($inner -eq '') { @() } else { @($inner -split ',') }
            if ($els.Count -lt $minA) { $minA = $els.Count }
            if ($els.Count -gt $maxA) { $maxA = $els.Count }
            foreach ($e in $els) { [void]$elKinds.Add($e) }
        }
        $itemTypes = New-Object System.Collections.ArrayList
        if ($elKinds.Contains('number')) { [void]$itemTypes.Add('number') }
        if ($elKinds.Contains('string') -or $elKinds.Contains('ident')) { [void]$itemTypes.Add('string'); [void]$itemTypes.Add('boolean') }
        if ($itemTypes.Count -eq 0) { [void]$itemTypes.Add('number') }
        $itemSchema = if ($itemTypes.Count -eq 1) { [ordered]@{ type = $itemTypes[0] } } else { [ordered]@{ type = @($itemTypes) } }
        $arr = [ordered]@{ type = 'array'; items = $itemSchema }
        if ($minA -ne [int]::MaxValue) { $arr.minItems = $minA; $arr.maxItems = $maxA }
        [void]$forms.Add($arr)
    }

    if ($forms.Count -eq 0) { [void]$forms.Add([ordered]@{ type = 'string' }) }  # census had no kind info (pre-kinds grammar)
    [void]$forms.Add($overrideRef)
    return [ordered]@{ anyOf = @($forms.ToArray()) }
}

# --- $defs -------------------------------------------------------------------
$defs = [ordered]@{
    formOverride = [ordered]@{
        type          = 'object'
        description   = 'Explicit token-form override: force bare-identifier, quoted-string, or number emission for one value.'
        minProperties = 1
        maxProperties = 1
        properties    = [ordered]@{
            ident  = [ordered]@{ type = 'string'; pattern = '^[A-Za-z_][A-Za-z0-9_.]*$' }
            string = [ordered]@{ type = 'string' }
            number = [ordered]@{ type = 'number' }
        }
        additionalProperties = $false
    }
}

foreach ($kw in ($g.blocks.Keys | Sort-Object)) {
    $b = $g.blocks[$kw]
    $propSchemas = [ordered]@{}
    $required = New-Object System.Collections.ArrayList
    foreach ($k in ($b.props.Keys | Sort-Object)) {
        $p = $b.props[$k]
        $propSchemas[$k] = New-PropSchema -Key $k -P $p
        if ([int]$p.count -ge [int]$b.count) { [void]$required.Add($k) }
    }

    $nodeProps = [ordered]@{
        block = [ordered]@{ const = $kw }
        id    = [ordered]@{ type = @('string', 'number') }
        props = [ordered]@{
            type                 = 'object'
            properties           = $propSchemas
            additionalProperties = $false
        }
    }
    if ($required.Count -gt 0) { $nodeProps.props.required = @($required.ToArray() | Sort-Object) }

    $childKws = @($b.children.Keys | Sort-Object)
    if ($childKws.Count -gt 0) {
        $nodeProps.children = [ordered]@{
            type  = 'array'
            items = [ordered]@{ oneOf = @($childKws | ForEach-Object { [ordered]@{ '$ref' = "#/`$defs/$_" } }) }
        }
    }

    $def = [ordered]@{
        type                 = 'object'
        properties           = $nodeProps
        required             = @('block')
        additionalProperties = $false
    }
    if ($kw -eq 'template') { $def.properties['$schema'] = [ordered]@{ type = 'string' } }
    $defs[$kw] = $def
}

if (-not $defs.Contains('template')) { throw "Census has no 'template' block — is $GrammarFile a real harvest?" }

$schema = [ordered]@{
    '$schema'   = 'https://json-schema.org/draft/2020-12/schema'
    '$id'       = 'https://local/tekla-template-ir.schema.json'
    title       = 'Tekla Template Editor file — JSON intermediate representation'
    description = "Generated by New-TeklaTemplateSchema.ps1 from $(Split-Path $GrammarFile -Leaf) " +
                  "(corpus: Tekla $($g.meta.version), $($g.meta.filesParsed) shipped templates, harvested $($g.meta.generated)). " +
                  'Do not edit by hand — regenerate after re-harvesting the grammar.'
    '$ref'      = '#/$defs/template'
    '$defs'     = $defs
}

$json = $schema | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))
[Console]::Error.WriteLine("Wrote $OutFile  ($($defs.Count - 1) block defs)")

[pscustomobject]@{ OutFile = $OutFile; BlockDefs = $defs.Count - 1 }
