# ============================================================================
# Shared tokenizer + tolerant recursive block parser for Tekla Template Editor
# files (.tpl / .rpt). Dot-sourced by Render-TeklaTemplate.ps1 (preview),
# Get-TeklaGrammar.ps1 (allow-list harvest) and the -Strict validator so all
# three see an IDENTICAL parse tree — a name is only "unknown" to the validator
# if it was also absent when the allow-list was harvested.
#
# Parse tree node: [pscustomobject]@{ Keyword; Id; Line; Props(ordered); Children }
#   Props    = key -> value  (string / double / array-tuple / bare ident)
#   Children = nested blocks (same shape)
# ============================================================================

function Read-Tokens {
    param([string]$Text)
    $toks = New-Object System.Collections.ArrayList
    $i = 0; $n = $Text.Length; $line = 1
    $add = { param($t, $v, $l) [void]$toks.Add([pscustomobject]@{ Type = $t; Value = $v; Line = $l }) }

    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq "`n") { $line++; $i++; continue }
        if ([char]::IsWhiteSpace($c)) { $i++; continue }

        # comments: // to end of line, /* ... */
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }; continue
        }
        if ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '*') {
            $i += 2
            while ($i + 1 -lt $n -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) {
                if ($Text[$i] -eq "`n") { $line++ }; $i++
            }
            $i += 2; continue
        }

        # double-quoted string; \" and \\ are the only escapes that matter (formula quotes)
        if ($c -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $startLine = $line; $i++
            $closed = $false
            while ($i -lt $n) {
                $ch = $Text[$i]
                if ($ch -eq '\') {
                    if ($i + 1 -lt $n) {
                        $nx = $Text[$i + 1]
                        if ($nx -eq '"' -or $nx -eq '\') { [void]$sb.Append($nx); $i += 2; continue }
                    }
                    [void]$sb.Append($ch); $i++; continue
                }
                if ($ch -eq '"') { $i++; $closed = $true; break }
                if ($ch -eq "`n") { $line++ }
                [void]$sb.Append($ch); $i++
            }
            if (-not $closed) { throw "Parse error line ${startLine}: unterminated string." }
            & $add 'String' $sb.ToString() $startLine
            continue
        }

        # identifier / enum keyword (letters, digits, _ and . after first)
        if ($c -match '[A-Za-z_]') {
            $start = $i
            while ($i -lt $n -and $Text[$i] -match '[A-Za-z0-9_.]') { $i++ }
            & $add 'Ident' $Text.Substring($start, $i - $start) $line
            continue
        }

        # number (optionally signed, decimal, with scientific exponent e.g. 8.4e-05)
        if ($c -match '[0-9]' -or ($c -eq '-' -and $i + 1 -lt $n -and $Text[$i + 1] -match '[0-9.]')) {
            $start = $i
            if ($Text[$i] -eq '-') { $i++ }
            while ($i -lt $n -and $Text[$i] -match '[0-9.]') { $i++ }
            if ($i -lt $n -and ($Text[$i] -eq 'e' -or $Text[$i] -eq 'E')) {
                $j = $i + 1
                if ($j -lt $n -and ($Text[$j] -eq '+' -or $Text[$j] -eq '-')) { $j++ }
                if ($j -lt $n -and $Text[$j] -match '[0-9]') {
                    $i = $j
                    while ($i -lt $n -and $Text[$i] -match '[0-9]') { $i++ }
                }
            }
            & $add 'Number' $Text.Substring($start, $i - $start) $line
            continue
        }

        if ('{}()=;,'.Contains([string]$c)) { & $add 'Punct' ([string]$c) $line; $i++; continue }

        # unknown character: skip tolerantly (keeps old/varied shipped templates parseable)
        $i++
    }
    & $add 'EOF' '' $line
    return $toks
}

# Parser state is script-scoped for a simple recursive descent.
function New-Parser { param($Tokens) $script:PTok = $Tokens; $script:PPos = 0 }
function Peek-Tok  { $script:PTok[$script:PPos] }
function Next-Tok  { $t = $script:PTok[$script:PPos]; $script:PPos++; return $t }
function Expect-Punct {
    param([string]$P)
    $t = Next-Tok
    if (-not ($t.Type -eq 'Punct' -and $t.Value -eq $P)) {
        throw "Parse error line $($t.Line): expected '$P' but found '$($t.Value)'."
    }
    return $t
}

# Reads a value AND its source token kind: 'string' (was double-quoted), 'ident'
# (bare enum keyword like TRUE / LEFT), 'number', or — for a tuple — an array of the
# element kinds. The kind is what a canonical emitter needs to reproduce quoting
# exactly (the value alone can't distinguish `justify = LEFT` from `name = "LEFT"`).
# Returns @{ V = value; K = kind }.
function Read-ValueKinded {
    $t = Next-Tok
    switch ($t.Type) {
        'String' { return @{ V = $t.Value; K = 'string' } }
        'Number' { return @{ V = [double]::Parse($t.Value, [System.Globalization.CultureInfo]::InvariantCulture); K = 'number' } }
        'Ident'  { return @{ V = $t.Value; K = 'ident' } }
        'Punct'  {
            if ($t.Value -eq '(') {
                $arr = New-Object System.Collections.ArrayList
                $kinds = New-Object System.Collections.ArrayList
                if ((Peek-Tok).Type -eq 'Punct' -and (Peek-Tok).Value -eq ')') {
                    [void](Next-Tok)
                    return @{ V = @($arr.ToArray()); K = @($kinds.ToArray()) }
                }
                while ($true) {
                    $el = Read-ValueKinded
                    [void]$arr.Add($el.V)
                    [void]$kinds.Add($el.K)
                    $sep = Next-Tok
                    if ($sep.Type -eq 'Punct' -and $sep.Value -eq ')') { break }
                    if ($sep.Type -eq 'Punct' -and $sep.Value -eq ',') { continue }
                    throw "Parse error line $($sep.Line): expected ',' or ')' in tuple, found '$($sep.Value)'."
                }
                return @{ V = @($arr.ToArray()); K = @($kinds.ToArray()) }
            }
        }
    }
    throw "Parse error line $($t.Line): unexpected value token '$($t.Value)'."
}

function Read-Value {
    $kv = Read-ValueKinded
    if ($kv.V -is [array]) { return , $kv.V }
    return $kv.V
}

# Reads a block body given its keyword/id already consumed; expects '{' next.
function Read-BlockBody {
    param([string]$Keyword, $Id, [int]$Line)
    Expect-Punct '{' | Out-Null
    $node = [pscustomobject]@{
        Keyword   = $Keyword
        Id        = $Id
        Line      = $Line
        Props     = [ordered]@{}
        PropLines = [ordered]@{}   # key -> source line, for precise validator diagnostics
        PropKinds = [ordered]@{}   # key -> token kind ('string'|'ident'|'number'|kind[] for tuples), for the canonical emitter
        Children  = (New-Object System.Collections.ArrayList)
    }
    while ($true) {
        $p = Peek-Tok
        if ($p.Type -eq 'Punct' -and $p.Value -eq '}') { [void](Next-Tok); break }
        if ($p.Type -eq 'Punct' -and $p.Value -eq ';') { [void](Next-Tok); continue }  # tolerate stray ';'
        if ($p.Type -eq 'EOF') { throw "Parse error line $($p.Line): unexpected end of file (unbalanced '{' opened near line $Line)." }

        $head = Next-Tok
        if ($head.Type -ne 'Ident') {
            throw "Parse error line $($head.Line): expected a key or block keyword, found '$($head.Value)'."
        }
        $nx = Peek-Tok
        if ($nx.Type -eq 'Punct' -and $nx.Value -eq '=') {
            [void](Next-Tok)                 # '='
            $kv = Read-ValueKinded
            Expect-Punct ';' | Out-Null
            $node.Props[$head.Value] = $kv.V
            $node.PropLines[$head.Value] = $head.Line
            $node.PropKinds[$head.Value] = $kv.K
        }
        else {
            # nested block: optional id token (identifier or number), then '{ ... }'
            $cid = $null
            $pt = Peek-Tok
            if ($pt.Type -eq 'Ident' -or $pt.Type -eq 'Number') { $cid = (Next-Tok).Value }
            $child = Read-BlockBody -Keyword $head.Value -Id $cid -Line $head.Line
            [void]$node.Children.Add($child)
        }
    }
    # optional trailing ';' after a nested block's closing brace
    $after = Peek-Tok
    if ($after.Type -eq 'Punct' -and $after.Value -eq ';') { [void](Next-Tok) }
    return $node
}

function Parse-Template {
    param([string]$Text)
    New-Parser (Read-Tokens $Text)
    $head = Next-Tok
    if ($head.Type -ne 'Ident') { throw "Parse error line $($head.Line): expected 'template', found '$($head.Value)'." }
    $id = $null
    $pt = Peek-Tok
    if ($pt.Type -eq 'Ident' -or $pt.Type -eq 'Number') { $id = (Next-Tok).Value }
    return Read-BlockBody -Keyword $head.Value -Id $id -Line $head.Line
}

# --- property accessors ------------------------------------------------------
function Get-Prop  { param($Node, [string]$Name) if ($Node.Props.Contains($Name)) { $Node.Props[$Name] } else { $null } }
function Get-Num   { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { $Default } else { [double]$v } }
function Get-Str   { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { $Default } else { [string]$v } }
function Get-Tuple { param($Node, [string]$Name, $Default) $v = Get-Prop $Node $Name; if ($null -eq $v) { return $Default }; if ($v -is [array]) { return $v } else { return @($v) } }

function Get-ChildBlocks { param($Node, [string[]]$Keywords) $Node.Children | Where-Object { $Keywords -contains $_.Keyword } }

# Walk every block in the tree (depth-first, includes the root).
function Get-AllBlocks {
    param($Node)
    $Node
    foreach ($c in $Node.Children) { Get-AllBlocks $c }
}
