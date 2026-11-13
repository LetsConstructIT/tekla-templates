<#
.SYNOPSIS
    Lint the HTML document an Excel/HTML report template (*.xls.rpt, *.html.rpt) produces.

.DESCRIPTION
    -Strict and the JSON Schema check that the TEMPLATE is well formed. Neither looks at the
    thing that actually breaks these reports: the HTML DOCUMENT assembled from the text
    blocks. This script composes that document the way Tekla does - per band, lines in
    descending y, objects left-to-right by x - and checks it.

    Checks (E = error, W = warning):

      E  unbalanced / mis-nested tags across the whole document
      E  a repeating `row` band that does not close what it opens - the failure that strikes
         only when a filter excludes the row, so it survives every desk test
      W  a repeating pageheader/pagefooter that does not self-balance (safe only while the
         report fits one page - which is why maxheight must stay huge)
      E  a data row whose cell count does not match the heading row (counting colspan)
      W  a STRING value in a cell without Excel's Text format - "B/1-2" becomes a date,
         "007" loses its zeros. NOTE mso-number-format:general does NOT count: it is the
         coercing default. The Text format is mso-number-format:"\@".
      W  a STRING value not wrapped in replace() - an "&" or "<" in model text injects raw
         markup into the document
      W  maxheight low enough that pagination will split the table

    Exit codes: 0 clean, 2 findings, 1 file could not be processed.
    Templates that emit no HTML are reported as "not an HTML report" and skipped.

.PARAMETER Path
    A template file, or a directory to sweep for *.rpt / *.tpl.

.PARAMETER Strict
    Promote warnings to errors (exit 2 on any finding).

.PARAMETER Quiet
    Summary only, no per-finding detail.

.EXAMPLE
    .\Test-TeklaHtmlReport.ps1 -Path part_list.xls.rpt

.EXAMPLE
    .\Test-TeklaHtmlReport.ps1 -Path C:\TeklaStructures\2026.0\Environments -Quiet
    # sweep every shipped template; only HTML reports are checked
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string] $Path,
    [switch] $Strict,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_TemplateParser.ps1"

# Tags that never nest, so they never affect the stack.
$script:VoidTags  = @('br', 'meta', 'img', 'hr', 'link', 'input', 'col', 'area', 'base', '!doctype')
# Tags a browser/Excel implicitly closes when a sibling or parent boundary arrives.
$script:AutoClose = @{ td = @('td', 'th', 'tr', 'table'); th = @('td', 'th', 'tr', 'table'); tr = @('tr', 'table') }

function New-Finding {
    param([string]$Severity, [string]$Band, [string]$Message)
    [pscustomobject]@{ Severity = $Severity; Band = $Band; Message = $Message }
}

# --- compose the emitted document -------------------------------------------
# One band -> its output lines. Each line is { Markup; Segments } where Segments keeps the
# valuefields so a cell can be tied back to the field it prints.
function Get-BandLines {
    param($Band)
    $objs = @($Band.Children | Where-Object { $_.Keyword -eq 'text' -or $_.Keyword -eq 'valuefield' })
    $items = foreach ($o in $objs) {
        if ($o.Keyword -eq 'text') {
            [pscustomobject]@{
                Y = [double](Get-Num $o 'y1' 0); X = [double](Get-Num $o 'x1' 0)
                Kind = 'text'; Text = (Get-Str $o 'string' ''); Node = $o
            }
        }
        else {
            $loc = Get-Tuple $o 'location' @(0, 0)
            [pscustomobject]@{
                Y = [double]$loc[1]; X = [double]$loc[0]
                Kind = 'field'; Text = ''; Node = $o
            }
        }
    }
    $lines = @()
    foreach ($g in ($items | Group-Object Y | Sort-Object { [double]$_.Name } -Descending)) {
        $segs = @($g.Group | Sort-Object X)
        # Lay each object out AT ITS X, padding the gaps with spaces - exactly what Tekla
        # emits. Concatenating instead fuses a tag split across two text objects
        # (`<TD` + `class=head>`) into the nonexistent tag `<TDclass`.
        $sb = New-Object System.Text.StringBuilder
        foreach ($seg in $segs) {
            $x = [int][math]::Round($seg.X)
            if ($x -gt $sb.Length) { [void]$sb.Append(' ', $x - $sb.Length) }
            if ($seg.Kind -eq 'text') { [void]$sb.Append($seg.Text) }
            else {
                $len = [int](Get-Num $seg.Node 'length' 1)
                [void]$sb.Append("`u{0001}")
                if ($len -gt 1) { [void]$sb.Append(' ', $len - 1) }
            }
        }
        $lines += [pscustomobject]@{ Markup = $sb.ToString(); Segments = $segs }
    }
    , $lines
}

# Bands in the order Tekla emits them, not the order they sit in the file.
function Get-OrderedBands {
    param($Root)
    $pick = { param($kw) @($Root.Children | Where-Object { $_.Keyword -eq $kw }) }
    $rows = @()
    function Add-Rows { param($Node) foreach ($c in $Node.Children) { if ($c.Keyword -eq 'row') { $script:__rows += $c; Add-Rows $c } } }
    $script:__rows = @()
    Add-Rows $Root
    $rows = $script:__rows
    @(& $pick 'header') + @(& $pick 'pageheader') + $rows + @(& $pick 'pagefooter') + @(& $pick 'footer')
}

# Blank out HTML comment bodies and <style> content across the whole document, in emit
# order, before any tag scanning. The Excel CSS lives inside `<!--` ... `-->` spanning tens
# of lines; scanned as markup its `<!--` reads as a tag named "!" and its braces as content.
function Clear-NonMarkup {
    param([array]$Lines)
    $inComment = $false
    $inStyle   = $false
    foreach ($ln in $Lines) {
        $s = $ln.Markup
        $sb = New-Object System.Text.StringBuilder
        $i = 0
        while ($i -lt $s.Length) {
            if ($inComment) {
                if ($i + 2 -lt $s.Length -and $s.Substring($i, 3) -eq '-->') { $inComment = $false; [void]$sb.Append('   '); $i += 3; continue }
                [void]$sb.Append(' '); $i++; continue
            }
            if ($inStyle) {
                if ($i + 7 -le $s.Length -and $s.Substring($i, 7) -ieq '</style') { $inStyle = $false; continue }
                if ($i + 4 -le $s.Length -and $s.Substring($i, 4) -eq '<!--') { $inComment = $true; [void]$sb.Append('    '); $i += 4; continue }
                [void]$sb.Append(' '); $i++; continue
            }
            if ($i + 4 -le $s.Length -and $s.Substring($i, 4) -eq '<!--') { $inComment = $true; [void]$sb.Append('    '); $i += 4; continue }
            if ($i + 6 -le $s.Length -and $s.Substring($i, 6) -ieq '<style') {
                # keep the <style ...> tag itself, then swallow its body
                $gt = $s.IndexOf('>', $i)
                if ($gt -lt 0) { [void]$sb.Append($s.Substring($i)); $i = $s.Length; $inStyle = $true; continue }
                [void]$sb.Append($s.Substring($i, $gt - $i + 1)); $i = $gt + 1; $inStyle = $true; continue
            }
            [void]$sb.Append($s[$i]); $i++
        }
        $ln.Markup = $sb.ToString()
    }
}

function Get-Tags {
    param([string]$Markup)
    $out = @()
    foreach ($m in [regex]::Matches($Markup, '<\s*(/?)\s*([A-Za-z!][A-Za-z0-9!]*)([^>]*)>')) {
        $out += [pscustomobject]@{
            Name    = $m.Groups[2].Value.ToLower()
            IsClose = ($m.Groups[1].Value -eq '/')
            Attrs   = $m.Groups[3].Value
            Index   = $m.Index
        }
    }
    , $out
}

# Walk tags maintaining $Stack (a List[string], mutated in place - PowerShell arrays behind
# [ref] silently degrade to strings here, which produced phantom tags).
function Invoke-TagWalk {
    param([array]$Lines, [string]$BandName, $Stack, [bool]$Isolated)
    $findings = @()
    $top  = { if ($Stack.Count) { $Stack[$Stack.Count - 1] } else { $null } }
    $pop  = { if ($Stack.Count) { $Stack.RemoveAt($Stack.Count - 1) } }
    foreach ($ln in $Lines) {
        foreach ($t in (Get-Tags $ln.Markup)) {
            if ($script:VoidTags -contains $t.Name) { continue }
            if ($t.IsClose) {
                # implicit closes: </tr> closes an open td, </table> closes tr/td
                while ($Stack.Count -and (& $top) -ne $t.Name -and
                       $script:AutoClose.ContainsKey((& $top)) -and
                       $script:AutoClose[(& $top)] -contains $t.Name) { & $pop }
                if (-not $Stack.Count) {
                    $findings += New-Finding 'E' $BandName "</$($t.Name)> closes a tag that was never opened$(if ($Isolated) { ' in this band' })."
                    continue
                }
                if ((& $top) -ne $t.Name) {
                    $findings += New-Finding 'E' $BandName "</$($t.Name)> closes out of order - <$(& $top)> is still open."
                    continue
                }
                & $pop
            }
            else {
                # a new <td>/<tr> implicitly closes the previous sibling
                while ($Stack.Count -and $script:AutoClose.ContainsKey((& $top)) -and
                       $script:AutoClose[(& $top)] -contains $t.Name) { & $pop }
                [void]$Stack.Add($t.Name)
            }
        }
    }
    , $findings
}

# cells per <TR> in a band, counting colspan
function Get-CellCounts {
    param([array]$Lines)
    $counts = @(); $cur = $null
    foreach ($ln in $Lines) {
        foreach ($t in (Get-Tags $ln.Markup)) {
            if ($t.Name -eq 'tr' -and -not $t.IsClose) { if ($null -ne $cur) { $counts += $cur }; $cur = 0; continue }
            if (($t.Name -eq 'td' -or $t.Name -eq 'th') -and -not $t.IsClose) {
                if ($null -eq $cur) { $cur = 0 }
                $span = 1
                if ($t.Attrs -match '(?i)colspan\s*=\s*["'']?(\d+)') { $span = [int]$Matches[1] }
                $cur += $span
            }
        }
    }
    if ($null -ne $cur) { $counts += $cur }
    , $counts
}

# CSS classes that carry a real Text number format (mso-number-format:"\@" / "@")
function Get-TextFormatClasses {
    param([string]$AllMarkup)
    $classes = @{}
    foreach ($m in [regex]::Matches($AllMarkup, '\.([A-Za-z0-9_-]+)\s*\{([^}]*)\}')) {
        $body = $m.Groups[2].Value
        if ($body -match 'mso-number-format:\s*"\\?@"') { $classes[$m.Groups[1].Value.ToLower()] = $true }
    }
    $classes
}

# Print metadata generated by Tekla itself, not model text - it cannot contain markup, so
# demanding replace() around it would be noise.
$script:SafeAttrs = @('DATE', 'TIME', 'PAGE', 'PAGES', 'ROW_IN_PAGE', 'ROW_IN_ALLPAGES', 'TODAY')
function Test-SafeSource {
    param([string]$Formula)
    $attrs = [regex]::Matches($Formula, 'GetValue\(\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value.ToUpper() }
    if (-not $attrs) { return $false }
    foreach ($a in $attrs) { if ($script:SafeAttrs -notcontains $a) { return $false } }
    return $true
}

function Test-CellIsText {
    param([string]$OpenTag, [hashtable]$TextClasses)
    if ($OpenTag -match 'mso-number-format:\s*\\?"\\?@\\?"') { return $true }
    if ($OpenTag -match '(?i)class\s*=\s*["'']?([A-Za-z0-9_-]+)') {
        if ($TextClasses.ContainsKey($Matches[1].ToLower())) { return $true }
    }
    return $false
}

function Test-OneTemplate {
    param([string]$File)

    $text = [System.IO.File]::ReadAllText($File)
    try { $root = Parse-Template -Text $text }
    catch { return [pscustomobject]@{ File = $File; Status = 'parse-fail'; Findings = @(New-Finding 'E' '-' $_.Exception.Message) } }

    $bands = Get-OrderedBands $root
    $composed = @()
    foreach ($b in $bands) { $composed += , [pscustomobject]@{ Band = $b; Lines = (Get-BandLines $b) } }

    $allMarkup = -join ($composed | ForEach-Object { $_.Lines | ForEach-Object { $_.Markup + "`n" } })
    if ($allMarkup -notmatch '(?i)<\s*/?\s*(html|body|table|tr|td|th|style)\b') {
        return [pscustomobject]@{ File = $File; Status = 'not-html'; Findings = @() }
    }

    $findings = @()
    # class definitions are read from the RAW markup (they live inside the comment/style
    # region that the next step blanks out)
    $textClasses = Get-TextFormatClasses $allMarkup
    Clear-NonMarkup -Lines @($composed | ForEach-Object { $_.Lines })

    # --- document-level nesting ---
    $stack = New-Object 'System.Collections.Generic.List[string]'
    foreach ($c in $composed) {
        $findings += Invoke-TagWalk -Lines $c.Lines -BandName $c.Band.Keyword -Stack $stack -Isolated $false
    }
    if ($stack.Count) {
        $findings += New-Finding 'E' 'document' "never closed: $(($stack | ForEach-Object { "<$_>" }) -join ', ')."
    }

    # --- per-band self-balance for repeating bands ---
    foreach ($c in $composed) {
        $kw = $c.Band.Keyword
        if ($kw -notin 'row', 'pageheader', 'pagefooter') { continue }
        $local = New-Object 'System.Collections.Generic.List[string]'
        $null = Invoke-TagWalk -Lines $c.Lines -BandName $kw -Stack $local -Isolated $true
        if ($local.Count) {
            $name = Get-Str $c.Band 'name' $kw
            $open = ($local | ForEach-Object { "<$_>" }) -join ', '
            if ($kw -eq 'row') {
                $findings += New-Finding 'E' "$kw '$name'" ("repeating band leaves $open open. If a rule or filter ever excludes " +
                    "this row, the document loses its closing tag(s). Emit the opener from the header/footer instead.")
            }
            else {
                $findings += New-Finding 'W' "$kw '$name'" ("repeating band leaves $open open - correct only while the report " +
                    "stays on one page. Keep maxheight large, or move the opener into the header.")
            }
        }
    }

    # --- cell counts: data rows vs the heading row ---
    $headCounts = @()
    foreach ($c in $composed) { if ($c.Band.Keyword -eq 'pageheader') { $headCounts += Get-CellCounts $c.Lines } }
    $expected = ($headCounts | Sort-Object -Descending | Select-Object -First 1)
    if ($expected) {
        foreach ($c in $composed) {
            if ($c.Band.Keyword -ne 'row') { continue }
            $name = Get-Str $c.Band 'name' 'row'
            foreach ($n in (Get-CellCounts $c.Lines)) {
                if ($n -gt $expected) {
                    # extra cells widen the table and push every following column across
                    $findings += New-Finding 'E' "row '$name'" "emits $n cells but the heading row has $expected - the extra cell(s) shift the columns."
                }
                elseif ($n -lt $expected) {
                    # legal HTML, and sometimes deliberate (a summary line) - but it under-fills the grid
                    $findings += New-Finding 'W' "row '$name'" "emits $n cells against a heading of $expected - the row under-fills the table. Use colspan if that is intended."
                }
            }
        }
    }

    # --- per-field checks: Excel coercion + HTML escaping ---
    foreach ($c in $composed) {
        $bandName = "$($c.Band.Keyword) '$(Get-Str $c.Band 'name' '')'"
        foreach ($ln in $c.Lines) {
            $openTag = ''
            foreach ($seg in $ln.Segments) {
                if ($seg.Kind -eq 'text') {
                    $tds = [regex]::Matches($seg.Text, '(?i)<\s*t[dh][^>]*>')
                    if ($tds.Count) { $openTag = $tds[$tds.Count - 1].Value }
                    continue
                }
                $node = $seg.Node
                $dt = (Get-Str $node 'datatype' '').ToUpper()
                if ($dt -ne 'STRING' -and $dt -ne 'CHARACTER' -and $dt -ne 'TEXT') { continue }
                $fname = Get-Str $node 'name' '?'
                if ($openTag -and -not (Test-CellIsText -OpenTag $openTag -TextClasses $textClasses)) {
                    $findings += New-Finding 'W' $bandName ("text field '$fname' is in a cell without Excel's Text format " +
                        '(mso-number-format:"\@") - Excel may reinterpret values like "B/1-2" or "007".')
                }
                $formula = Get-Str $node 'formula' ''
                if ($formula -notmatch 'replace\s*\(' -and -not (Test-SafeSource $formula)) {
                    $findings += New-Finding 'W' $bandName ("text field '$fname' is not HTML-escaped - an '&' or '<' in the " +
                        'model value will corrupt the document. Wrap it: replace(replace(<formula>, "&", "&amp;"), "<", "&lt;").')
                }
            }
        }
    }

    # --- pagination ---
    $maxh = Get-Num $root 'maxheight' 0
    if ($maxh -lt 10000) {
        $findings += New-Finding 'W' 'template' "maxheight = $maxh - pagination will split the HTML mid-table. Shipped HTML reports use 100000."
    }

    [pscustomobject]@{ File = $File; Status = 'checked'; Findings = $findings }
}

# --- drive -------------------------------------------------------------------
if (-not (Test-Path $Path)) { Write-Error "Not found: $Path"; exit 1 }
$item = Get-Item -LiteralPath $Path
$files = if ($item.PSIsContainer) {
    Get-ChildItem -LiteralPath $Path -Recurse -Include '*.rpt', '*.tpl' -File | Select-Object -ExpandProperty FullName
}
else { @($item.FullName) }

$checked = 0; $clean = 0; $withFindings = 0; $skipped = 0; $failed = 0
$errCount = 0; $warnCount = 0

foreach ($f in $files) {
    $r = Test-OneTemplate -File $f
    if ($r.Status -eq 'not-html')   { $skipped++; continue }
    if ($r.Status -eq 'parse-fail') { $failed++;  continue }
    $checked++

    $e = @($r.Findings | Where-Object { $_.Severity -eq 'E' }).Count
    $w = @($r.Findings | Where-Object { $_.Severity -eq 'W' }).Count
    $errCount += $e; $warnCount += $w
    if ($r.Findings.Count) { $withFindings++ } else { $clean++ }

    if (-not $Quiet -and $r.Findings.Count) {
        Write-Host ""
        Write-Host $r.File -ForegroundColor Cyan
        foreach ($fd in ($r.Findings | Sort-Object { if ($_.Severity -eq 'E') { 0 } else { 1 } })) {
            $col = if ($fd.Severity -eq 'E') { 'Red' } else { 'Yellow' }
            Write-Host ("  [{0}] {1}: {2}" -f $fd.Severity, $fd.Band, $fd.Message) -ForegroundColor $col
        }
    }
}

Write-Host ""
Write-Host ("HTML reports checked : {0}" -f $checked)
Write-Host ("  clean              : {0}" -f $clean)
Write-Host ("  with findings      : {0}  ({1} error(s), {2} warning(s))" -f $withFindings, $errCount, $warnCount)
if ($skipped) { Write-Host ("not HTML reports     : {0}  (skipped)" -f $skipped) }
if ($failed)  { Write-Host ("parse failures       : {0}" -f $failed) }

if ($errCount -gt 0 -or ($Strict -and $warnCount -gt 0)) { exit 2 }
exit 0
