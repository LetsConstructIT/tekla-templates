# ============================================================================
# Shared -Strict GRAMMAR validator for Tekla Template Editor files (.tpl / .rpt).
# Dot-sourced by Render-TeklaTemplate.ps1 (the -Strict switch) and
# Test-TeklaTemplates.ps1 (batch sweep) so both apply an IDENTICAL grammar check.
# Requires the parse tree produced by _TemplateParser.ps1 (Get-AllBlocks).
#
# Catches an INVENTED block type / property key / enum value — the silent failure
# mode where an LLM writes a plausible-but-nonexistent grammar word (valuefield
# { align=... }) that Tekla ignores and the field renders blank. The allow-list is
# the empirical grammar harvested from the shipped template corpus by
# Get-TeklaGrammar.ps1; anything absent from every shipped template is flagged
# (with a nearest-match suggestion). Findings are reported relative to the harvest
# version — a construct can be legal-but-rare and simply missing from that corpus,
# so treat them as "verify", not "definitely wrong".
#
# It ALSO runs a raw-text portability lint (Find-TplEdIncompatibilities) for
# constructs that TEMPLATE EDITOR ITSELF cannot open — structural comments, bare-LF
# line endings, packed formatting, and template notes over 120 chars.
# This is a separate check because _TemplateParser.ps1 is deliberately more tolerant
# than TplEd: its tokenizer strips // and /* */ comments, so a file with a comment
# BETWEEN blocks parses and renders cleanly here yet makes TplEd crash on open
# (silent stack overflow, no error dialog). TplEd has no comment syntax outside a
# quoted formula/rule string; the lint flags any // or /* */ that isn't inside one.
# ============================================================================

function Get-EditDistance {
    param([string]$A, [string]$B)
    $la = $A.Length; $lb = $B.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }
    $prev = 0..$lb
    for ($i = 1; $i -le $la; $i++) {
        $cur = @($i) + (1..$lb | ForEach-Object { 0 })
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $cur[$j] = [math]::Min([math]::Min($cur[$j - 1] + 1, $prev[$j] + 1), $prev[$j - 1] + $cost)
        }
        $prev = $cur
    }
    return $prev[$lb]
}

# Nearest name in $Candidates to $Name within an edit-distance budget (grows with
# length so long words tolerate more typos). Case-insensitive compare. $null if none.
function Find-Nearest {
    param([string]$Name, [string[]]$Candidates)
    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }
    $budget = [math]::Max(2, [math]::Floor($Name.Length / 3))
    $best = $null; $bestD = [int]::MaxValue
    foreach ($c in $Candidates) {
        $d = Get-EditDistance $Name.ToLowerInvariant() $c.ToLowerInvariant()
        if ($d -lt $bestD) { $bestD = $d; $best = $c }
    }
    if ($bestD -le $budget) { return $best } else { return $null }
}

# Keys that are genuinely CLOSED vocabularies (a fixed keyword set), so an off-list
# value is almost certainly invented. Free-form keys (name, notes, string, value,
# formula, class, unit, file, colorname, field, created, modified) are NOT here — a
# corpus can't tell "closed enum" from "coincidentally few free values", and those
# fields legitimately take novel content. Boolean keys are detected automatically
# below (corpus values ⊆ {TRUE,FALSE}) and need no listing.
$script:EnumKeys = @(
    'justify', 'datatype', 'oncombine', 'sorttype', 'sortdirection', 'type',
    'filldirection', 'fillpolicy', 'fillstartfrom', 'outputpolicy'
)

# Walk the parse tree; return a list of grammar findings (strings, each line-anchored).
function Invoke-StrictValidation {
    param($Root, $Grammar)
    $findings = New-Object System.Collections.ArrayList
    $knownBlocks = @($Grammar.blocks.PSObject.Properties.Name)
    foreach ($node in (Get-AllBlocks $Root)) {
        $kw = $node.Keyword
        if ($knownBlocks -notcontains $kw) {
            $sug = Find-Nearest $kw $knownBlocks
            $hint = if ($sug) { " — did you mean '$sug'?" } else { ' (not seen in the shipped corpus)' }
            [void]$findings.Add("line $($node.Line): unknown block type '$kw'$hint")
            continue   # its properties can't be checked against a block we don't know
        }
        $blockDef = $Grammar.blocks.$kw
        $knownKeys = @($blockDef.props.PSObject.Properties.Name)
        foreach ($k in $node.Props.Keys) {
            $ln = if ($node.PropLines.Contains($k)) { $node.PropLines[$k] } else { $node.Line }
            if ($knownKeys -notcontains $k) {
                $sug = Find-Nearest $k $knownKeys
                $hint = if ($sug) { " — did you mean '$sug'?" } else { " (not a known property of '$kw')" }
                [void]$findings.Add("line ${ln}: '$k' is not a known property of '$kw'$hint")
                continue
            }
            # enum value check — only for a bare-identifier value on a closed-vocabulary key.
            $v = $node.Props[$k]
            if (-not ($v -is [string]) -or $v -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
            $vals = @($blockDef.props.$k.values)
            if ($vals.Count -eq 0) { continue }
            $isBool = @($vals | Where-Object { $_ -notin @('TRUE', 'FALSE') }).Count -eq 0
            if ($isBool) {
                if ($v -notin @('TRUE', 'FALSE')) {
                    [void]$findings.Add("line ${ln}: '$v' is not valid for boolean '$kw.$k' (known: TRUE, FALSE)")
                }
            }
            elseif (($script:EnumKeys -contains $k) -and ($vals.Count -ge 2) -and ($vals -notcontains $v)) {
                $sug = Find-Nearest $v $vals
                $hint = if ($sug) { " — did you mean '$sug'?" } else { " (known: $($vals -join ', '))" }
                [void]$findings.Add("line ${ln}: '$v' is not a known value for '$kw.$k'$hint")
            }
        }
    }
    return $findings
}

# Raw-text portability lint: find constructs that TplEd cannot open. Operates on the
# ORIGINAL file text (not the parse tree) because the parser strips exactly the thing
# we're hunting. Currently: structural // and /* */ comments — legal ONLY inside a
# quoted formula/rule string in TplEd; anywhere else they crash it silently. We scan
# char-by-char skipping quoted strings (same escape rules as the tokenizer), so a //
# inside "if (...) then // note\n ..." is correctly ignored and only a bare structural
# comment is reported. One finding per line.
function Find-TplEdIncompatibilities {
    param([string]$Text)
    $findings = New-Object System.Collections.ArrayList
    $reported = New-Object 'System.Collections.Generic.HashSet[int]'
    $i = 0; $n = $Text.Length; $line = 1

    # Bare-LF (Unix) line endings crash Template Editor on OPEN — its parser assumes Windows
    # CRLF and stack-overflows silently (exception 0xc0000409, no dialog) on lone \n. Every
    # shipped .rpt/.tpl is CRLF. Flag the first \n not preceded by \r. (Callers pass raw file
    # bytes via ReadAllText, so CR survives; a lone \n here means a genuine bare-LF ending.)
    for ($k = 0; $k -lt $n; $k++) {
        if ($Text[$k] -eq "`n" -and ($k -eq 0 -or $Text[$k - 1] -ne "`r")) {
            $ln = 1; for ($j = 0; $j -lt $k; $j++) { if ($Text[$j] -eq "`n") { $ln++ } }
            [void]$findings.Add("line ${ln}: bare LF (Unix) line ending — Template Editor requires CRLF and will fail to OPEN this file (silent crash, exception 0xc0000409). Save/convert the file with Windows (CRLF) line endings; Install-TeklaTemplate.ps1 does this automatically on install.")
            break
        }
    }

    # Packed / compact formatting crashes Template Editor on OPEN (silent stack overflow,
    # exception 0xc0000409). TplEd's hand-rolled parser requires ONE statement per line and
    # the block keyword + '{' on their own lines. Across all 2,689 shipped 2026.0 templates
    # there is NOT ONE line packing two assignments or opening a block inline — it is entirely
    # non-canonical. The parser here (like any tokenizer) is whitespace-insensitive, so a
    # packed file previews clean yet crashes TplEd; only this raw-text lint catches it. We flag
    # (a) a ';' followed by another 'ident =' on the same physical line, and (b) a block
    # keyword whose '{' is followed by a property on the same line. Quoted strings are blanked
    # first (same escape rules as the tokenizer) so a ';' inside a formula/rule is never
    # counted. One finding per line; corpus-validated false-positive-free (0 shipped hits).
    $blockKw = 'applicationattribute|circle|footer|graphicalfield|group|header|lineorarc|pagefooter|pageheader|picture|polyline|rectangle|row|symbol|template|text|userattribute|valuefield'
    $physical = $Text -split "`n"
    for ($k = 0; $k -lt $physical.Length; $k++) {
        $bare = [regex]::Replace($physical[$k], '"(\\.|[^"\\])*"', '""')
        $ln = $k + 1
        if ($bare -match ';\s*[A-Za-z_]\w*\s*=') {
            [void]$findings.Add("line ${ln}: two statements on one line (';' followed by another 'name =') — Template Editor requires ONE statement per line and will fail to OPEN this file (silent crash, exception 0xc0000409). No shipped template packs statements; put each 'name = value;' on its own line.")
        }
        elseif ($bare -match "\b(?:$blockKw)\b\s*(?:_\w+\s*)?\{\s*[A-Za-z_]") {
            [void]$findings.Add("line ${ln}: block opened inline (keyword and '{' share a line with a property) — Template Editor requires the keyword and '{' on their own lines and will fail to OPEN this file (silent crash, exception 0xc0000409). No shipped template opens a block inline; put '{' and each property on separate lines.")
        }
        # Template notes length: TplEd stores the template header's notes in a fixed
        # 120-char buffer — a longer value crashes it on open (confirmed live). 'notes'
        # exists ONLY on the template block, so a line-anchored match is exact. Length is
        # counted on the UNESCAPED value (what TplEd stores: \" and \\ are one char).
        # Checked on the RAW line ($bare has the value blanked out).
        if ($physical[$k] -match '^\s*notes\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$') {
            $len = [regex]::Replace($Matches[1], '\\(.)', '$1').Length
            if ($len -gt 120) {
                [void]$findings.Add("line ${ln}: template notes is $len chars — Template Editor limits 'notes' to 120 chars and will fail to OPEN this file (silent crash) beyond that. Shorten the notes to 120 chars or fewer; move longer documentation outside the template.")
            }
        }
    }

    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq "`n") { $line++; $i++; continue }
        if ($c -eq '"') {
            # skip the quoted string; \" and \\ are escapes (formula quotes)
            $i++
            while ($i -lt $n) {
                $ch = $Text[$i]
                if ($ch -eq '\' -and $i + 1 -lt $n) { $i += 2; continue }
                if ($ch -eq '"') { $i++; break }
                if ($ch -eq "`n") { $line++ }
                $i++
            }
            continue
        }
        if ($c -eq '/' -and $i + 1 -lt $n -and ($Text[$i + 1] -eq '/' -or $Text[$i + 1] -eq '*')) {
            $kind = if ($Text[$i + 1] -eq '/') { '//' } else { '/*' }
            if (-not $reported.Contains($line)) {
                [void]$reported.Add($line)
                [void]$findings.Add("line ${line}: '$kind' comment outside a quoted string — Template Editor has no structural comment syntax and will fail to OPEN this file (silent crash, no error). Comments are valid only INSIDE a formula/rule string; delete it or move it inside the quotes.")
            }
            # advance past the comment body so its contents aren't mis-scanned
            if ($kind -eq '//') { while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ } }
            else { $i += 2; while ($i + 1 -lt $n -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { if ($Text[$i] -eq "`n") { $line++ }; $i++ }; $i += 2 }
            continue
        }
        $i++
    }
    return $findings
}

# Semantic schema lint: within a GRAPHICAL template (drawing table / title block), two
# `valuefield` blocks that are DIRECT SIBLINGS of the same parent must not share a
# `name`. Template Editor references graphical valuefields by name (the "Sorting and
# drawing order" pane), so a same-name pair in one row/section collides — TplEd reports
# "Colliding valuefield name 'X'". Scope is empirical and deliberately narrow to stay
# false-positive-free against the shipped corpus: across 180 shipped GRAPHICAL templates
# there are ZERO sibling-name collisions, whereas TEXTUAL reports freely reuse names
# (they're columns — e.g. TS_Report_Inquire_*.rpt repeat "Length"/"Width" in one row),
# so the check is GRAPHICAL-only. The same name in DIFFERENT rows/sections is legitimate
# (e.g. Steel_Beam.tpl's "Profile" in two rows) and is NOT flagged — only same-parent
# collisions are. Case-sensitive match (conservative). One finding per colliding name.
function Find-DuplicateValueFieldNames {
    param($Root)
    $findings = New-Object System.Collections.ArrayList
    if ((Get-Str $Root 'type' 'GRAPHICAL') -ne 'GRAPHICAL') { return $findings }  # textual reports may reuse names
    foreach ($blk in (Get-AllBlocks $Root)) {
        $vf = @($blk.Children | Where-Object { $_.Keyword -ieq 'valuefield' -and $_.Props['name'] })
        if ($vf.Count -lt 2) { continue }
        foreach ($g in ($vf | Group-Object -CaseSensitive { $_.Props['name'] })) {
            if ($g.Count -lt 2) { continue }
            $lines = @($g.Group | ForEach-Object { $_.Line } | Sort-Object)
            $where = if ($blk.Props['name']) { "$($blk.Keyword) '$($blk.Props['name'])'" } else { $blk.Keyword }
            [void]$findings.Add("line $($lines[1]): duplicate valuefield name '$($g.Name)' — $($g.Count) valuefields share it in the same $where (lines $($lines -join ', ')). Template Editor references graphical valuefields by name, so same-name siblings collide. Rename so each is unique within its row/section.")
        }
    }
    return $findings
}

# Load the allow-list; resolve default location next to the skill's assets.
function Get-GrammarAllowList {
    param([string]$GrammarFile)
    if (-not $GrammarFile) {
        $GrammarFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\template-grammar.json'
    }
    if (-not (Test-Path $GrammarFile)) {
        [Console]::Error.WriteLine("STRICT: grammar allow-list not found at $GrammarFile")
        [Console]::Error.WriteLine("        Generate it first:  scripts\Get-TeklaGrammar.ps1")
        [Console]::Error.WriteLine("        Skipping grammar validation.")
        return $null
    }
    try {
        return (Get-Content $GrammarFile -Raw | ConvertFrom-Json)
    }
    catch {
        [Console]::Error.WriteLine("STRICT: could not read grammar allow-list ($GrammarFile): $($_.Exception.Message)")
        return $null
    }
}

# Run strict validation and report to stderr. Returns $true if any findings (caller sets exit code).
# Pass -Text (the raw file) to also run the TplEd portability lint; it runs independently of the
# grammar allow-list, so it fires even when the allow-list is missing.
function Write-StrictValidation {
    param($Root, [string]$GrammarFile, [string]$Text)
    $any = $false

    # 1. TplEd portability lint (raw text) — the "won't even open" class, most severe.
    if ($Text) {
        $port = @(Find-TplEdIncompatibilities -Text $Text)
        if ($port.Count -gt 0) {
            [Console]::Error.WriteLine("STRICT: $($port.Count) TplEd-compatibility issue(s) — Template Editor will fail to open this file:")
            foreach ($f in $port) { [Console]::Error.WriteLine("  # $f") }
            $any = $true
        }
    }

    # 2. Valuefield-name collision (graphical templates) — a TplEd schema rule, parse-tree
    #    based but independent of the allow-list, so it runs even when the grammar is missing.
    $dups = @(Find-DuplicateValueFieldNames -Root $Root)
    if ($dups.Count -gt 0) {
        [Console]::Error.WriteLine("STRICT: $($dups.Count) duplicate valuefield name(s) — Template Editor will report colliding valuefield names:")
        foreach ($f in $dups) { [Console]::Error.WriteLine("  # $f") }
        $any = $true
    }

    # 3. Grammar allow-list check (parse-tree based).
    $grammar = Get-GrammarAllowList -GrammarFile $GrammarFile
    if ($grammar) {
        $findings = Invoke-StrictValidation -Root $Root -Grammar $grammar
        $ver = if ($grammar.meta.version) { $grammar.meta.version } else { '?' }
        if ($findings.Count -eq 0) {
            [Console]::Error.WriteLine("STRICT: no unknown block types / properties (grammar v$ver, $($grammar.meta.blockTypes) block types).")
        }
        else {
            [Console]::Error.WriteLine("STRICT: $($findings.Count) grammar finding(s) vs shipped corpus v${ver} — a name absent from every shipped template (likely invented):")
            foreach ($f in $findings) { [Console]::Error.WriteLine("  # $f") }
            $any = $true
        }
    }
    return $any
}
