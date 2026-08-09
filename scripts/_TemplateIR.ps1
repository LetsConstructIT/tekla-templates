# ============================================================================
# Shared JSON IR (intermediate representation) library for Tekla Template Editor
# files (.tpl / .rpt). Dot-sourced by ConvertFrom-TeklaTemplate.ps1 (template ->
# JSON), ConvertTo-TeklaTemplate.ps1 (JSON -> template) and
# tests\Test-TeklaTemplateRoundTrip.ps1 (corpus proof) so all three share ONE emitter
# and ONE quoting decision. Requires _TemplateParser.ps1 to be dot-sourced first.
#
# IR node (JSON object):
#   { "block": "row", "id": "_tmp_0", "props": { ... }, "children": [ ... ] }
#   - "id" omitted when the block has none; "children" omitted when empty.
#   - prop values: JSON number  -> bare number token       (width = 78;)
#                  JSON string  -> quoted OR bare enum, decided by the corpus
#                                  kind census (see Get-StringTokenKind)
#                  JSON true/false -> bare TRUE / FALSE
#                  JSON array   -> tuple                    (location = (0, 2);)
#                  {"ident": "X"} / {"string": "X"} -> explicit form override,
#                                  used when the census decision must be beaten
#                                  (ConvertFrom emits these automatically for the
#                                  rare value whose source quoting disagrees with
#                                  the canonical decision — losslessness by
#                                  construction, not convention)
#
# DETERMINISM CONTRACT: the same IR JSON always emits byte-identical template
# text (CRLF, 4-space indent, one statement per line, '{' / '};' on their own
# lines, blank line before each child block, leading blank line — the exact
# layout TplEd itself writes, so the packed-formatting / comment / bare-LF
# crash classes are unreachable by construction).
# ============================================================================

# --- corpus kind census ------------------------------------------------------

# Load assets\template-grammar.json into a lookup:
#   table[block][prop] = @{ Sigs = @{ sig -> count }; IdentValues = HashSet; TupleSig = string[] }
# Sigs are 'string' | 'ident' | 'number' | 'tuple(...)' as harvested by
# Get-TeklaGrammar.ps1; TupleSig is the element-kind list of the most common
# tuple signature (e.g. location -> @('number','number')).
function Get-TeklaKindTable {
    param([string]$GrammarFile)
    if (-not $GrammarFile) {
        $GrammarFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-grammar.json'
    }
    if (-not (Test-Path $GrammarFile)) {
        throw "Grammar census not found: $GrammarFile  (generate it with scripts\Get-TeklaGrammar.ps1)"
    }
    $g = Get-Content $GrammarFile -Raw | ConvertFrom-Json -AsHashtable
    $table = @{}
    foreach ($kw in $g.blocks.Keys) {
        $props = @{}
        foreach ($k in $g.blocks[$kw].props.Keys) {
            $p = $g.blocks[$kw].props[$k]
            $sigs = @{}
            if ($p.kinds) { foreach ($s in $p.kinds.Keys) { $sigs[$s] = [int]$p.kinds[$s] } }
            $iv = New-Object 'System.Collections.Generic.HashSet[string]'
            if ($p.values) { foreach ($v in $p.values) { [void]$iv.Add([string]$v) } }
            # most common tuple signature, decomposed into element kinds
            $tupleSig = $null
            $bestN = -1
            foreach ($s in $sigs.Keys) {
                if ($s -like 'tuple(*' -and $sigs[$s] -gt $bestN) {
                    $bestN = $sigs[$s]
                    $inner = $s.Substring(6, $s.Length - 7)
                    $tupleSig = if ($inner -eq '') { @() } else { @($inner -split ',') }
                }
            }
            $props[$k] = @{ Sigs = $sigs; IdentValues = $iv; TupleSig = $tupleSig }
        }
        $table[$kw] = $props
    }
    return $table
}

function Get-KindEntry {
    param($Table, [string]$Block, [string]$Prop)
    if ($null -eq $Table) { return $null }
    $b = $Table[$Block]
    if ($null -eq $b) { return $null }
    return $b[$Prop]
}

# --- the ONE quoting decision ------------------------------------------------

# Decide how a JSON string prop value is written: 'ident' (bare enum keyword,
# justify = LEFT) or 'string' (quoted, name = "LEFT"). Purely a function of the
# corpus census entry and the value — no file state — so ConvertFrom and
# ConvertTo always agree. ConvertFrom tags the value explicitly whenever the
# source file's actual form differs from this decision.
function Get-StringTokenKind {
    param($Entry, [string]$Value)
    $tokenizable = $Value -match '^[A-Za-z_][A-Za-z0-9_.]*$'
    if (-not $tokenizable) { return 'string' }   # can't be a bare token, ever
    if ($null -eq $Entry) { return 'string' }    # unknown prop: quoted is the safe form
    $hasIdent = $Entry.Sigs.ContainsKey('ident')
    $hasString = $Entry.Sigs.ContainsKey('string')
    if ($hasIdent -and -not $hasString) { return 'ident' }
    if ($hasIdent -and $hasString -and $Entry.IdentValues.Contains($Value)) { return 'ident' }
    return 'string'
}

# Element kind inside a tuple, by position, from the census tuple signature.
function Get-TupleElementKind {
    param($Entry, [int]$Index)
    if ($Entry -and $Entry.TupleSig -and $Index -lt $Entry.TupleSig.Count) { return $Entry.TupleSig[$Index] }
    return $null
}

# --- token formatting --------------------------------------------------------

function Format-TplNumber {
    param([double]$V)
    if ([double]::IsNaN($V) -or [double]::IsInfinity($V)) { throw "Cannot emit non-finite number '$V'." }
    if ($V -eq [math]::Truncate($V) -and [math]::Abs($V) -lt 1e15) {
        return ([long]$V).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    # 'R' is shortest-round-trippable on .NET Core; the tokenizer accepts its E notation
    return $V.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Quote a string value with the MINIMAL escaping the TplEd tokenizer round-trips:
# '"' must become '\"'; a '\' is escaped to '\\' only when the next character is
# '"' or '\' or it is the last character (a lone backslash before an ordinary
# character stays literal — that is how shipped files write Windows paths).
function Format-TplString {
    param([string]$V)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    for ($i = 0; $i -lt $V.Length; $i++) {
        $c = $V[$i]
        if ($c -eq '"') { [void]$sb.Append('\"'); continue }
        if ($c -eq '\') {
            $isLast = ($i -eq $V.Length - 1)
            $next = if ($isLast) { $null } else { $V[$i + 1] }
            if ($isLast -or $next -eq '"' -or $next -eq '\') { [void]$sb.Append('\\') } else { [void]$sb.Append('\') }
            continue
        }
        [void]$sb.Append($c)
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Test-TplIdent {
    param([string]$V)
    return $V -match '^[A-Za-z_][A-Za-z0-9_.]*$'
}

# Render one IR prop value (or tuple element) to its token text.
#   $Kind: $null = decide from census; 'ident' / 'string' / 'number' = explicit.
function Format-TplToken {
    param($Value, $Entry, [string]$Kind, [string]$Where)
    # explicit override object {"ident": "X"} / {"string": "X"} / {"number": 1.5}
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($keys.Count -ne 1 -or $keys[0] -notin @('ident', 'string', 'number')) {
            throw "$($Where): an override object must have exactly one key of 'ident'|'string'|'number' (got: $($keys -join ', '))."
        }
        return (Format-TplToken -Value $Value[$keys[0]] -Entry $Entry -Kind $keys[0] -Where $Where)
    }
    if ($Value -is [bool]) { return ($Value ? 'TRUE' : 'FALSE') }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return (Format-TplNumber ([double]$Value))
    }
    if ($Value -is [string]) {
        switch ($Kind) {
            'number' { return (Format-TplNumber ([double]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture))) }
            'ident'  {
                if (-not (Test-TplIdent $Value)) { throw "$($Where): '$Value' cannot be a bare identifier token." }
                return $Value
            }
            'string' { return (Format-TplString $Value) }
            default  {
                if ($Value -in @('TRUE', 'FALSE') -and $Entry -and $Entry.Sigs.ContainsKey('ident') -and -not $Entry.Sigs.ContainsKey('string')) {
                    return $Value   # ident-only bool prop written as JSON string
                }
                $k = Get-StringTokenKind -Entry $Entry -Value $Value
                if ($k -eq 'ident') { return $Value }
                return (Format-TplString $Value)
            }
        }
    }
    if ($null -eq $Value) { throw "$($Where): null is not a valid template value." }
    throw "$($Where): unsupported JSON value type '$($Value.GetType().Name)'."
}

function Format-TplTuple {
    param($Values, $Entry, [string]$Where)
    $parts = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $v = $Values[$i]
        $elKind = $null
        if ($v -is [string] -and -not ($v -is [System.Collections.IDictionary])) {
            $ek = Get-TupleElementKind -Entry $Entry -Index $i
            if ($ek -in @('ident', 'string', 'number')) { $elKind = $ek }
        }
        [void]$parts.Add((Format-TplToken -Value $v -Entry $Entry -Kind $elKind -Where "$Where[$i]"))
    }
    return '(' + ($parts -join ', ') + ')'
}

# --- parse tree -> IR --------------------------------------------------------

# Convert a _TemplateParser.ps1 node to an IR ordered dictionary, consulting the
# census so that any value whose source form differs from the canonical decision
# gets an explicit {"ident"/"string": ...} tag (lossless round trip).
function ConvertTo-TeklaIRNode {
    param($Node, $Table)
    $ir = [ordered]@{ block = [string]$Node.Keyword }
    if ($null -ne $Node.Id -and [string]$Node.Id -ne '') { $ir.id = [string]$Node.Id }
    $props = [ordered]@{}
    foreach ($k in $Node.Props.Keys) {
        $entry = Get-KindEntry $Table $Node.Keyword $k
        $props[$k] = ConvertTo-TeklaIRValue -Value $Node.Props[$k] -Kind $Node.PropKinds[$k] -Entry $entry
    }
    if ($props.Count -gt 0) { $ir.props = $props }
    if ($Node.Children.Count -gt 0) {
        $ir.children = @($Node.Children | ForEach-Object { ConvertTo-TeklaIRNode -Node $_ -Table $Table })
    }
    return $ir
}

function ConvertTo-TeklaIRValue {
    param($Value, $Kind, $Entry, [int]$TupleIndex = -1)
    if ($Kind -is [array]) {
        # tuple: convert element-wise; element positions consult the census tuple signature
        $out = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $Value.Count; $i++) {
            [void]$out.Add((ConvertTo-TeklaIRValue -Value $Value[$i] -Kind $Kind[$i] -Entry $Entry -TupleIndex $i))
        }
        return , @($out.ToArray())
    }
    switch ([string]$Kind) {
        'number' {
            $d = [double]$Value
            if ($d -eq [math]::Truncate($d) -and [math]::Abs($d) -lt 1e15) { return [long]$d }
            return $d
        }
        'ident' {
            if ($Value -in @('TRUE', 'FALSE')) { return ($Value -eq 'TRUE') }   # JSON boolean; emitter always writes bare TRUE/FALSE
            $decision = if ($TupleIndex -ge 0) {
                $ek = Get-TupleElementKind -Entry $Entry -Index $TupleIndex
                if ($ek) { $ek } else { 'string' }
            } else { Get-StringTokenKind -Entry $Entry -Value $Value }
            if ($decision -eq 'ident') { return [string]$Value }
            return [ordered]@{ ident = [string]$Value }
        }
        'string' {
            if ($TupleIndex -ge 0) {
                $ek = Get-TupleElementKind -Entry $Entry -Index $TupleIndex
                $decision = if ($ek) { $ek } else { 'string' }
            }
            else { $decision = Get-StringTokenKind -Entry $Entry -Value $Value }
            if ($decision -eq 'string') { return [string]$Value }
            return [ordered]@{ string = [string]$Value }
        }
        default { throw "Internal: unknown source token kind '$Kind'." }
    }
}

# --- IR -> canonical template text -------------------------------------------

# Validate + emit. The output layout is fixed: see DETERMINISM CONTRACT above.
function ConvertTo-TeklaTemplateText {
    param($Ir, $Table)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("`r`n")   # canonical leading blank line (every shipped file has it)
    Write-TeklaIRBlock -Ir $Ir -Depth 0 -Table $Table -Sb $sb -Path 'template'
    return $sb.ToString()
}

function Write-TeklaIRBlock {
    param($Ir, [int]$Depth, $Table, $Sb, [string]$Path)
    if ($Ir -isnot [System.Collections.IDictionary]) { throw "$($Path): a block must be a JSON object." }
    $allowed = @('block', 'id', 'props', 'children')
    if ($Depth -eq 0) { $allowed += '$schema' }   # tolerate a $schema pointer on the root
    foreach ($k in $Ir.Keys) {
        if ($k -notin $allowed) { throw "$($Path): unknown key '$k' (allowed: $($allowed -join ', '))." }
    }
    $kw = $Ir['block']
    if (-not ($kw -is [string]) -or -not (Test-TplIdent $kw)) { throw "$($Path): 'block' must be an identifier string (got '$kw')." }

    $ind = '    ' * $Depth
    $head = $ind + $kw
    if ($Ir.Contains('id')) {
        $id = [string]$Ir['id']
        if ($id -notmatch '^[A-Za-z_][A-Za-z0-9_.]*$' -and $id -notmatch '^-?[0-9][0-9.]*$') {
            throw "$($Path): id '$id' is not a bare token (identifier or number)."
        }
        $head += ' ' + $id
    }
    [void]$Sb.Append($head).Append("`r`n")
    [void]$Sb.Append($ind).Append('{').Append("`r`n")

    $props = $Ir['props']
    if ($null -ne $props) {
        if ($props -isnot [System.Collections.IDictionary]) { throw "$($Path): 'props' must be a JSON object." }
        foreach ($k in $props.Keys) {
            if (-not (Test-TplIdent $k)) { throw "$($Path): prop key '$k' is not a valid identifier." }
            $entry = Get-KindEntry $Table $kw $k
            $v = $props[$k]
            $tok = if ($v -is [System.Collections.IList] -and $v -isnot [string]) {
                Format-TplTuple -Values $v -Entry $entry -Where "$Path.$k"
            }
            else {
                Format-TplToken -Value $v -Entry $entry -Kind $null -Where "$Path.$k"
            }
            [void]$Sb.Append($ind).Append('    ').Append($k).Append(' = ').Append($tok).Append(';').Append("`r`n")
        }
    }

    $children = $Ir['children']
    if ($null -ne $children) {
        if ($children -isnot [System.Collections.IList]) { throw "$($Path): 'children' must be a JSON array." }
        $ci = 0
        foreach ($child in $children) {
            [void]$Sb.Append("`r`n")   # blank line before each child block
            $ckw = if ($child -is [System.Collections.IDictionary]) { $child['block'] } else { '?' }
            Write-TeklaIRBlock -Ir $child -Depth ($Depth + 1) -Table $Table -Sb $Sb -Path "$Path.children[$ci]($ckw)"
            $ci++
        }
    }
    [void]$Sb.Append($ind).Append('};').Append("`r`n")
}

# --- JSON serialization helpers ----------------------------------------------

function ConvertTo-TeklaIRJson {
    param($Ir)
    return ($Ir | ConvertTo-Json -Depth 100)
}

function Read-TeklaIRJson {
    param([string]$JsonText)
    return ($JsonText | ConvertFrom-Json -AsHashtable -Depth 100)
}
