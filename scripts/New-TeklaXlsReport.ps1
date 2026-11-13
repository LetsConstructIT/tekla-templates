<#
.SYNOPSIS
    Generate a formatted Excel report template (HTML-inside-.xls) from a column spec.

.DESCRIPTION
    Tekla's only way to produce a *formatted* Excel report is a plain TEXTUAL template
    whose text blocks emit HTML + Excel "mso-" CSS; naming the file *.xls.rpt makes Tekla
    write the output as .xls, which Excel opens as a styled worksheet. 96 shipped 2026.0
    templates work this way (Find-TeklaTemplateExamples.ps1 -Feature xls-html).

    Hand-building one means placing ~20 text blocks per column at matching y coordinates,
    where a single missing </TD> silently corrupts the document. This script takes a column
    spec instead and emits the whole template through the JSON IR pipeline, so the things
    that break these reports are handled by construction:

      * every cell is a complete <TD>/value/</TD> triple on one output line
      * <TR> and </TR> are always paired INSIDE the band that emits them, so a filtered-out
        or hidden row can never unbalance the document (see -Sort / -Rule)
      * text columns get the Excel Text format (mso-number-format:"\@") so piece marks like
        "B/1-2" or "01" survive instead of being coerced to dates/numbers
      * text columns are HTML-escaped with replace(), so an "&" or "<" in a project name or
        UDA cannot inject markup
      * maxheight is set high, because pagination splits the HTML mid-table
      * template width is computed from the actual emitted lines

    Output is validated by the standard gates (JSON Schema -> emit -> re-parse -> -Strict),
    so the TplEd crash traps are unreachable. Lint the emitted document itself with
    Test-TeklaHtmlReport.ps1.

    NOT corpus-proven: no shipped template uses replace() or the Text number format (they
    also don't solve the problems those fix). Both are documented behaviour - Template Editor
    for replace(), Excel for "\@" - but verify one generated report in a live Tekla session
    before rolling this out widely. -NoEscape / -NoTextFormat fall back to shipped practice.

.PARAMETER Out
    Output template path. Should end in .xls.rpt (Excel) or .html.rpt (browser/Excel via
    File > Open, no format-mismatch prompt). Tekla writes the part before the last dot as
    the report's output extension.

.PARAMETER Column
    Ordered array of hashtables, one per column:
        Header    (required) column title text
        Formula   (required) the value, e.g. 'GetValue("PROFILE")'
        Type      Text | Number | Integer          (default Text)
        Width     value-field length in characters (default 16 / 12 / 8 by type)
        Decimals  Number only                      (default 1)
        Class     datatype class for units, e.g. Weight / Length
        Combine   SUM | NONE - roll-up when -Sort COMBINE merges rows
        Total     [switch] add a Total() cell for this column in the footer

.PARAMETER ContentType
    Row content type (PART, ASSEMBLY, BOLT, CAST_UNIT, DRAWING, REBAR ...). Default PART.

.PARAMETER Title
    Document <TITLE> and the heading above the table. Default "Report".

.PARAMETER Sort
    Row sorttype: COMBINE (merge identical rows) | DISTINCT | NONE. Default COMBINE.

.PARAMETER Rule
    Row filter rule (template rule language, unescaped). Default none.

.PARAMETER NoProjectBlock
    Omit the project-name / date table above the data table.

.PARAMETER NoEscape
    Do not wrap text columns in replace() HTML-escaping (matches shipped practice - only
    safe when no model text can contain "&" or "<").

.PARAMETER NoTextFormat
    Emit text cells as plain <TD> instead of the Text number format (matches shipped
    practice - lets Excel coerce piece marks to dates).

.PARAMETER Landscape
    Set mso-page-orientation:landscape in the @page rule.

.PARAMETER JsonOut
    Also write the intermediate IR JSON here (for hand-editing and re-emitting).

.EXAMPLE
    .\New-TeklaXlsReport.ps1 -Out part_list.xls.rpt -Title "Part list" -Column `
        @{ Header='Pos';         Formula='GetValue("PART_POS")' },
        @{ Header='Profile';     Formula='GetValue("PROFILE")' },
        @{ Header='Qty';         Formula='GetValue("NUMBER")'; Type='Integer'; Combine='SUM' },
        @{ Header='Weight (kg)'; Formula='GetValue("WEIGHT")'; Type='Number'; Class='Weight'; Combine='SUM'; Total=$true }

.EXAMPLE
    .\New-TeklaXlsReport.ps1 -Out bolts.xls.rpt -ContentType BOLT -Title "Bolt list" -Column `
        @{ Header='Size'; Formula='GetValue("DIAMETER")'; Type='Number'; Decimals=0 },
        @{ Header='Qty';  Formula='GetValue("NUMBER")';   Type='Integer'; Combine='SUM'; Total=$true }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]   $Out,
    [Parameter(Mandatory)][hashtable[]] $Column,
    [string] $ContentType = 'PART',
    [string] $Title       = 'Report',
    [ValidateSet('COMBINE', 'DISTINCT', 'NONE')][string] $Sort = 'COMBINE',
    [string] $Rule        = '',
    [switch] $NoProjectBlock,
    [switch] $NoEscape,
    [switch] $NoTextFormat,
    [switch] $Landscape,
    [string] $JsonOut
)

$ErrorActionPreference = 'Stop'

# --- column spec normalisation ----------------------------------------------
$DefaultWidth = @{ Text = 16; Number = 12; Integer = 8 }
$Datatype     = @{ Text = 'STRING'; Number = 'DOUBLE'; Integer = 'INTEGER' }

$cols = @()
$i = 0
foreach ($c in $Column) {
    $i++
    foreach ($k in 'Header', 'Formula') {
        if (-not $c.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$c[$k])) {
            throw "Column $i is missing required key '$k'."
        }
    }
    $type = if ($c.ContainsKey('Type')) { [string]$c.Type } else { 'Text' }
    if ($DefaultWidth.Keys -notcontains $type) {
        throw "Column $i ('$($c.Header)') has Type '$type'; expected Text, Number or Integer."
    }
    $spec = [ordered]@{
        Header   = [string]$c.Header
        Formula  = [string]$c.Formula
        Type     = $type
        Width    = if ($c.ContainsKey('Width'))    { [int]$c.Width }    else { $DefaultWidth[$type] }
        Decimals = if ($c.ContainsKey('Decimals')) { [int]$c.Decimals } else { if ($type -eq 'Number') { 1 } else { $null } }
        Class    = if ($c.ContainsKey('Class'))    { [string]$c.Class } else { '' }
        Total    = [bool]($c.ContainsKey('Total') -and $c.Total)
        Combine  = if ($c.ContainsKey('Combine'))  { ([string]$c.Combine).ToUpper() } else { $null }
        Name     = ''
    }
    if ($spec.Type -eq 'Integer') { $spec.Decimals = $null }
    if ($spec.Total -and $spec.Type -eq 'Text') {
        throw "Column $i ('$($spec.Header)'): Total is only meaningful on a Number/Integer column."
    }
    $cols += , $spec
}
if (-not $cols.Count) { throw "Pass at least one -Column." }

# field names must be unique across the template (TplEd rejects duplicates)
$used = @{}
foreach ($c in $cols) {
    $base = ($c.Header -replace '[^A-Za-z0-9]', '_').Trim('_').ToUpper()
    if (-not $base) { $base = 'COL' }
    $n = $base; $k = 1
    while ($used.ContainsKey($n)) { $k++; $n = "${base}_$k" }
    $used[$n] = $true
    $c.Name = $n
}

# COMBINE merges rows, so every numeric column needs an explicit roll-up decision.
# Default to SUM (the usual intent for a quantity) but say so - a silent wrong total is
# the failure mode this is guarding against.
$autoSum = @()
if ($Sort -eq 'COMBINE') {
    foreach ($c in $cols) {
        if ($c.Type -eq 'Text') { if (-not $c.Combine) { $c.Combine = 'NONE' }; continue }
        if (-not $c.Combine) { $c.Combine = 'SUM'; $autoSum += $c.Header }
    }
}
foreach ($c in $cols) { if (-not $c.Combine) { $c.Combine = 'NONE' } }

if ($Out -notmatch '(?i)\.(xls|html?)\.rpt$') {
    Write-Warning ("'$Out' does not end in .xls.rpt or .html.rpt - Tekla takes the report's " +
                   "output extension from the part before the last dot, so the result will not open as a workbook.")
}

# --- IR building blocks ------------------------------------------------------
$FONT = @{ name = 'Courier New'; color = 153; type = 2; size = 0.8; ratio = 0.75 }
$XOPEN = 0
$XVAL  = 50

function New-Text {
    param([string]$Name, [int]$X, [int]$Y, [string]$String)
    [ordered]@{
        block = 'text'
        props = [ordered]@{
            name = $Name; x1 = $X; y1 = $Y; x2 = $X; y2 = $Y; string = $String
            fontname = $FONT.name; fontcolor = $FONT.color; fonttype = $FONT.type
            fontsize = $FONT.size; fontratio = $FONT.ratio
            fontslant = 0; fontstyle = 0; angle = 0; justify = 'LEFT'; pen = 0
        }
    }
}

function New-Field {
    param(
        [string]$Name, [int]$X, [int]$Y, [string]$Formula, [int]$Length,
        [string]$DType = 'STRING', [string]$Class = '', $Decimals = $null,
        [string]$OnCombine = 'NONE'
    )
    $p = [ordered]@{
        name = $Name; location = @($X, $Y); formula = $Formula
        datatype = $DType; class = $Class
        cacheable = $true; justify = 'LEFT'; visibility = $true; angle = 0; length = $Length
    }
    if ($null -ne $Decimals) { $p.decimals = [int]$Decimals }
    $p.sortdirection = 'NONE'
    $p.fontname = $FONT.name; $p.fontcolor = $FONT.color; $p.fonttype = $FONT.type
    $p.fontsize = $FONT.size; $p.fontratio = $FONT.ratio
    $p.fontstyle = 0; $p.fontslant = 0; $p.pen = 0; $p.oncombine = $OnCombine
    [ordered]@{ block = 'valuefield'; props = $p }
}

function New-Lines {
    param([string]$Prefix, [int]$StartY, [string[]]$Lines)
    $out = @()
    for ($n = 0; $n -lt $Lines.Count; $n++) {
        $out += (New-Text ("{0}{1:d3}" -f $Prefix, $n) $XOPEN ($StartY - $n) $Lines[$n])
    }
    , $out
}

# HTML-escape a value inside the template language. Order matters: "&" first, or it would
# re-escape the ampersands introduced by the later replacements. ">" is not escaped - it is
# only special inside a tag, and every extra call lengthens the formula.
function Add-HtmlEscape {
    param([string]$Formula)
    if ($NoEscape) { return $Formula }
    $f = 'replace(' + $Formula + ', "&", "&amp;")'
    $f = 'replace(' + $f + ', "<", "&lt;")'
    return $f
}

function New-Cell {
    # one HTML cell = one output line: <TD ...> | value | &nbsp;</TD>
    param(
        [string]$Name, [int]$Y, [string]$Open, [string]$Formula, [int]$Length,
        [string]$DType = 'STRING', [string]$Class = '', $Decimals = $null,
        [string]$OnCombine = 'NONE', [string]$Close = '&nbsp;</TD>'
    )
    , @(
        (New-Text "o_$Name" $XOPEN $Y $Open)
        (New-Field $Name $XVAL $Y $Formula $Length $DType $Class $Decimals $OnCombine)
        (New-Text "c_$Name" ($XVAL + $Length) $Y $Close)
    )
}

$TdText = if ($NoTextFormat) { '<TD>' } else { '<TD class=txt>' }

# --- header: document preamble, CSS, project block, data-table open ----------
$css = @(
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2//EN">'
    '<HTML>'
    '<HEAD>'
    '<META NAME="Generator" CONTENT="Tekla Structures">'
    "<TITLE>$Title</TITLE>"
    '<style type="text/css">'
    '<!--'
    '@page'
    '{margin:0.79in 0.59in 0.79in 0.59in;'
    ('mso-page-orientation:' + $(if ($Landscape) { 'landscape' } else { 'portrait' }) + ';}')
    '.style0'
    '{mso-number-format:general;'
    'font-family:Arial, sans-serif;'
    'font-size:10.0pt;'
    'text-align:left;'
    'vertical-align:middle;'
    'white-space:nowrap;}'
    'td'
    '{mso-style-parent:style0;'
    'border:0.5pt solid windowtext;}'
    '.head'
    '{mso-style-parent:style0;'
    'font-weight:700;'
    'text-align:center;'
    'border:1.0pt solid windowtext;}'
    '.count'
    '{mso-style-parent:style0;'
    'font-weight:700;'
    'border:1.0pt solid windowtext;}'
)
if (-not $NoTextFormat) {
    # Excel's Text format. "general" (used by 29 shipped templates) is the coercing DEFAULT
    # and does not preserve "B/1-2" or a leading zero; "\@" does.
    $css += @(
        '.txt'
        '{mso-style-parent:style0;'
        'mso-number-format:"\@";}'
    )
}
$css += @(
    '-->'
    '</style>'
    '</HEAD>'
    '<BODY>'
)

$hTop = 400
$headerKids = @()
$headerKids += New-Lines 'h' $hTop $css
$y = $hTop - $css.Count

if (-not $NoProjectBlock) {
    $headerKids += New-Lines 'hp' $y @('<TABLE style="border-collapse:collapse">')
    $y--
    $headerKids += (New-Text 'h_proj_lbl' $XOPEN $y '<TR><TD class=head>&nbsp;Project&nbsp;</TD>')
    $y--
    $headerKids += New-Cell -Name 'PROJECT_NAME' -Y $y -Open $TdText `
        -Formula (Add-HtmlEscape 'GetValue("PROJECT.NAME")') -Length 30 -Close '&nbsp;</TD></TR>'
    $y--
    $headerKids += (New-Text 'h_date_lbl' $XOPEN $y '<TR><TD class=head>&nbsp;Date&nbsp;</TD>')
    $y--
    $headerKids += New-Cell -Name 'REPORT_DATE' -Y $y -Open $TdText `
        -Formula 'GetValue("DATE")' -Length 12 -Close '&nbsp;</TD></TR>'
    $y--
    $headerKids += New-Lines 'hq' $y @('</TABLE>', '<BR>')
    $y -= 2
}
# the data table opens ONCE here, so the repeating bands below stay self-balanced
$headerKids += New-Lines 'hz' $y @('<TABLE style="border-collapse:collapse">')
$headerHeight = $hTop + 1

# --- pageheader: the column-title <TR> (self-balanced) -----------------------
$titleLines = @('<TR ALIGN="LEFT" VALIGN="MIDDLE">')
foreach ($c in $cols) { $titleLines += ('<TD class=head>&nbsp;' + $c.Header + '&nbsp;</TD>') }
$titleLines += '</TR>'
$phHeight = $titleLines.Count + 1

# --- row: one <TR> per object, one <TD> per column (self-balanced) -----------
$rowKids = @()
$ry = $cols.Count + 1
$rowKids += (New-Text 'r_tr' $XOPEN $ry '<TR ALIGN="LEFT" VALIGN="MIDDLE">')
foreach ($c in $cols) {
    $ry--
    $open = if ($c.Type -eq 'Text') { $TdText } else { '<TD>' }
    $formula = if ($c.Type -eq 'Text') { Add-HtmlEscape $c.Formula } else { $c.Formula }
    $rowKids += New-Cell -Name $c.Name -Y $ry -Open $open -Formula $formula -Length $c.Width `
        -DType $Datatype[$c.Type] -Class $c.Class -Decimals $c.Decimals -OnCombine $c.Combine
}
$ry--
$rowKids += (New-Text 'r_tr_end' $XOPEN $ry '</TR>')
$rowHeight = $cols.Count + 3

# --- footer: totals <TR>, then close the table and the document --------------
$totalCols = @($cols | Where-Object { $_.Total })
$footKids = @()
$fy = $cols.Count + 2
if ($totalCols.Count) {
    $footKids += (New-Text 'f_tr' $XOPEN $fy '<TR ALIGN="LEFT" VALIGN="MIDDLE">')
    $fy--
    foreach ($c in $cols) {
        if ($c.Total) {
            $footKids += New-Cell -Name ("TOT_" + $c.Name) -Y $fy -Open '<TD class=count>' `
                -Formula ('Total("' + $c.Name + '")') -Length $c.Width `
                -DType $Datatype[$c.Type] -Class $c.Class -Decimals $c.Decimals
        }
        else {
            $footKids += (New-Text ("f_pad_" + $c.Name) $XOPEN $fy '<TD class=count>&nbsp;</TD>')
        }
        $fy--
    }
    $footKids += (New-Text 'f_tr_end' $XOPEN $fy '</TR>')
    $fy--
}
$footKids += New-Lines 'fz' $fy @('</TABLE>', '</BODY>', '</HTML>')
$footHeight = $cols.Count + 6

# --- assemble ----------------------------------------------------------------
$bands = @(
    [ordered]@{ block = 'header';     props = [ordered]@{ name = 'HEADER'; height = $headerHeight }; children = $headerKids }
    [ordered]@{ block = 'pageheader'; props = [ordered]@{ name = 'PAGEHEADER'; height = $phHeight; outputpolicy = 'NONE' }
                children = (New-Lines 'p' ($titleLines.Count) $titleLines) }
    [ordered]@{ block = 'row'
                props = [ordered]@{
                    name = $ContentType; height = $rowHeight; visibility = $true
                    usecolumns = $false; rule = $Rule; contenttype = $ContentType; sorttype = $Sort
                }
                children = $rowKids }
    [ordered]@{ block = 'footer';     props = [ordered]@{ name = 'FOOTER'; height = $footHeight }; children = $footKids }
)

# template width from the widest emitted line, so a long header never overflows
$maxLine = 0
foreach ($b in $bands) {
    foreach ($k in $b.children) {
        $p = $k.props
        $end = if ($k.block -eq 'text') { [int]$p.x1 + $p.string.Length } else { [int]$p.location[0] + [int]$p.length }
        if ($end -gt $maxLine) { $maxLine = $end }
    }
}

$ir = [ordered]@{
    block = 'template'
    props = [ordered]@{
        name          = [IO.Path]::GetFileNameWithoutExtension($Out) -replace '\.(xls|html?)$', ''
        type          = 'TEXTUAL'
        width         = $maxLine + 4
        maxheight     = 100000     # pagination would split the HTML mid-table
        columns       = @(1, 1)
        gap           = 1
        fillpolicy    = 'EVEN'
        filldirection = 'HORIZONTAL'
        fillstartfrom = 'TOPLEFT'
        margins       = @(0, 0, 0, 0)
        gridxspacing  = 1
        gridyspacing  = 1
        version       = 5.2
        created       = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        modified      = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        notes         = "Excel report (HTML in .xls) generated by New-TeklaXlsReport.ps1."
    }
    children = $bands
}

$json = $ir | ConvertTo-Json -Depth 12
if ($JsonOut) {
    [System.IO.File]::WriteAllText($JsonOut, $json, (New-Object System.Text.UTF8Encoding($false)))
    [Console]::Error.WriteLine("Wrote IR JSON $JsonOut")
}

& "$PSScriptRoot\ConvertTo-TeklaTemplate.ps1" -Json $json -Out $Out -Strict
$emitExit = $LASTEXITCODE

# --- report the decisions the caller should know about -----------------------
if ($autoSum.Count) {
    [Console]::Error.WriteLine("NOTE: -Sort COMBINE merges rows; applied oncombine=SUM to: $($autoSum -join ', ').")
    [Console]::Error.WriteLine("      Pass Combine='NONE' on any column where a sum is wrong (a diameter, a level).")
}
if ($NoEscape)     { [Console]::Error.WriteLine("NOTE: -NoEscape - model text goes into the HTML raw; '&' or '<' in a value will corrupt the document.") }
if ($NoTextFormat) { [Console]::Error.WriteLine("NOTE: -NoTextFormat - Excel may coerce text columns (piece marks to dates, dropped leading zeros).") }

exit $emitExit
