<#
.SYNOPSIS
    Render a Tekla Template Editor file (.tpl / .rpt) to a visual layout preview so
    layout can be checked without opening Template Editor or Tekla. Graphical (.tpl)
    templates render to SVG; textual (.rpt) reports render to a monospaced character
    grid (as text with -AsText, otherwise as an SVG of the same grid).

.DESCRIPTION
    This is a LAYOUT APPROXIMATION, not a reproduction of Tekla's output. No model data
    is available, so font metrics are approximate. By default the preview is tuned to read
    like a real printed page — short realistic sample values fill each field and one
    representative band is drawn per row (see -AllVariants / -RawValues to turn either off).
    The preview exists to catch the spatial mistakes — overlapping columns, fields past the
    template width, short `length` values that truncate, data misaligned under headings,
    table rules (horizontal lineorarcs) cutting through text — before the template is
    loaded into Tekla.

    Three stages: a tolerant tokenizer + block parser (also a syntax checker — real parse
    errors report line numbers), a layout pass that stamps sections/rows and emits draw
    primitives, and a diagnostics pass whose warnings go to stderr AND are drawn into the
    SVG in red. Exit code is 0 even with layout warnings; nonzero only for parse failure.

.PARAMETER Path
    The .tpl or .rpt template file to render.

.PARAMETER Out
    Output SVG path. Defaults to "<input>.preview.svg" next to the input. Ignored with
    -AsText (which writes the grid to stdout).

.PARAMETER Rows
    How many times each data row band is stamped (sample rows). Default 3, but only takes
    effect with -AllVariants; the default single-bar view stamps each row once. Hidden rows
    are always stamped once regardless.

.PARAMETER AllVariants
    Show every rule-guarded variant row and all sample instances instead of the default
    single representative band per row. Needed to inspect a specific bending shape / filter
    branch, since the default collapse keeps only the first ruled row of each content type.

.PARAMETER RawValues
    Show literal formula placeholders (GetValue("PROFILE") -> {PROFILE}) instead of the
    default short sample values. Use it to see exactly which attribute each field reads.

.PARAMETER AsText
    For textual reports, print the plain-text mock report to stdout instead of writing SVG
    (fastest way to eyeball column alignment). On a graphical template this prints the
    diagnostics only.

.PARAMETER Html
    Wrap the SVG in a minimal self-contained HTML page.

.PARAMETER Strict
    Also validate the file's GRAMMAR against the allow-list in assets\template-grammar.json:
    flag any block type, property key, or closed-enum value that no shipped template uses (a
    likely hallucination), with a nearest-match suggestion. ALSO runs a TplEd-portability lint
    on the raw text: a structural // or /* */ comment (one that isn't inside a quoted
    formula/rule string) parses and renders fine here but makes Template Editor crash on open —
    the parser strips comments, so only this lint catches it. Findings print to stderr; exit
    code is 2 when any are found (0 otherwise). The preview still renders regardless.

.PARAMETER GrammarFile
    Override the allow-list path used by -Strict (default: assets\template-grammar.json next
    to the skill). Generate one for another Tekla version with Get-TeklaGrammar.ps1.

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path title_block.tpl
    # -> title_block.preview.svg

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path new_report.rpt -Strict
    # render + flag any invented block/property/enum word (exit 2 if found)

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path part_list.rpt -AsText
    # -> character-grid mock report on stdout, warnings on stderr

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path revisions.tpl -Out preview.svg -AllVariants -Rows 5

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path "Rebar Schedule.tpl" -Out sched.svg
    # default: one-object-per-line preview with realistic short values (matches real output)

.EXAMPLE
    .\Render-TeklaTemplate.ps1 -Path "Rebar Schedule.tpl" -Out full.svg -AllVariants -RawValues
    # every variant row, literal {ATTRIBUTE} placeholders — the exhaustive/raw view
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Path,
    [string] $Out,
    [int]    $Rows = 3,
    [switch] $AllVariants,
    [switch] $RawValues,
    [switch] $AsText,
    [switch] $Html,
    [switch] $Strict,
    [string] $GrammarFile
)

# Single-bar + short-values are ON by default so the preview reads one-object-per-line like a
# real Tekla printout. Two opt-outs restore the raw/exhaustive view:
#
# -AllVariants : DON'T collapse mutually-exclusive rule-guarded sibling rows. By default one
#                representative band per row is drawn and the rule-guarded siblings (e.g. the
#                ~55 bending-shape variants) collapse to the first of each content type, so the
#                page reads like real output. Pass -AllVariants to see EVERY variant row and all
#                sample instances (needed to inspect a specific shape/branch), since the default
#                collapse also hides distinct filter *branches* of the same content type.
# -RawValues   : show the literal {ATTRIBUTE}/{SUM:…} placeholders instead of the default short
#                realistic sample values (SIZE->16, SHAPE->51, DIM_A->300, WEIGHT->9.8, POS->B01,
#                …). Use it when you need to see exactly which attribute each field reads.

$ErrorActionPreference = 'Stop'

# Default-on behaviours (the opt-out switches above invert them). Script-scoped so the
# render/placeholder functions read them directly.
$script:SingleBar   = -not $AllVariants
$script:ShortValues = -not $RawValues

# ============================================================================
# 1. PARSER  —  tokenizer + tolerant recursive block parser
# ============================================================================
# Extracted to a shared module so the preview, the grammar harvester
# (Get-TeklaGrammar.ps1) and the -Strict validator all parse identically.
. "$PSScriptRoot\_TemplateParser.ps1"

# ============================================================================
# Shared: formula -> placeholder text, palette, helpers
# ============================================================================

# A short, plausible sample value for one attribute (last dotted segment), used by -ShortValues
# so the preview approximates real data widths instead of long {ATTRIBUTE} names.
function Get-SampleValue {
    param([string]$Attr)
    $a = ($Attr -replace '"', '').Trim()
    $seg = ($a -split '\.')[-1]                    # last hop: PART.CAST_UNIT_POS -> CAST_UNIT_POS
    $seg = ($seg -replace 'USERDEFINED', '').Trim('_. ')
    $u = $seg.ToUpperInvariant()
    switch -Regex ($u) {
        '^PAGE$'                { '1'; break }
        '^PREFIX$'              { 'B'; break }
        '(^|_)SIZE$'            { '16'; break }
        '(^|_)DIA(METER)?$'     { '16'; break }
        '(^|_)GRADE$'           { 'H'; break }
        '(^|_)SHAPE'            { '51'; break }
        '^DIM_'                 { '300'; break }
        '(^|_)RADIUS$'          { '32'; break }
        '(^|_)LENGTH'           { '1250'; break }
        '(^|_)WEIGHT'           { '9.8'; break }
        '(^|_)VOLUME'           { '0.05'; break }
        '(^|_)AREA'             { '1.2'; break }
        'CPLRSTATE'             { 'COUPLER'; break }
        'CPLRTYPE'              { 'STD'; break }
        'CPLRCODE'              { 'C16'; break }
        '(NUMBER|COUNT|MBR|BARS|NO_OF|NUM_)' { '8'; break }
        '(^|_)POS$'             { 'B01'; break }
        '(^|_)MARK$'            { 'A'; break }
        '(REVISION|^REV$)'      { 'A'; break }
        '(^|_)DATE'             { '01.02.26'; break }
        '(^|_)TIME'            { '09:30'; break }
        '(^|_)NAME$'            { 'Bar'; break }
        '(^|_)CLASS$'           { '7'; break }
        '(^|_)PROFILE$'         { 'D16'; break }
        '(^|_)MATERIAL$'        { 'B500B'; break }
        '(TITLE|OBJECT|BUILDER|INFO)' { 'Beam B1'; break }
        '(^|_)(NUMBER|PHASE)$'  { '2'; break }
        default {
            if ($u -match '^\d') { '12' }
            elseif ($seg.Length -le 3 -and $seg.Length -gt 0) { $seg }   # already short (e.g. "A")
            else { 'Ab1' }
        }
    }
}

function Get-Placeholder {
    param([string]$Formula)
    if ([string]::IsNullOrWhiteSpace($Formula)) { return '{ }' }
    $t = $Formula.Trim()
    $m = [regex]::Match($t, '^GetValue\(\s*"(.+)"\s*\)$')
    if ($m.Success) {
        $inner = $m.Groups[1].Value
        $tt = [regex]::Match($inner, 'TranslatedText\(\s*"([^"]+)"')
        if ($tt.Success) {
            if ($script:ShortValues) { return $tt.Groups[1].Value -replace '^albl_', '' }
            return '{~' + $tt.Groups[1].Value + '}'
        }
        if ($script:ShortValues) { return Get-SampleValue $inner }
        return '{' + ($inner -replace '"', '') + '}'
    }
    $s = [regex]::Match($t, '^Sum\(\s*"(.+?)"\s*\)$')
    if ($s.Success) {
        if ($script:ShortValues) { return '42.0' }
        return '{SUM:' + ($s.Groups[1].Value -replace '"', '') + '}'
    }
    # complex formula (if/format/concat): in short mode, sample the first GetValue inside it
    if ($script:ShortValues) {
        $g = [regex]::Match($t, 'GetValue\(\s*"([^"]+)"')
        if ($g.Success) { return Get-SampleValue $g.Groups[1].Value }
        return '12'
    }
    if ($t.Length -gt 18) { $t = $t.Substring(0, 18) + '..' }
    return '{' + $t + '}'
}

# Common palette indexes; 153 = black is the one that matters, rest are best-effort.
$script:Palette = @{
    153 = '#000000'; 152 = '#808080'; 154 = '#c00000'; 155 = '#008000'
    156 = '#0000c0'; 157 = '#b0a000'; 158 = '#a000a0'; 159 = '#008080'
}
function Get-Color { param($Index) $k = [int]$Index; if ($script:Palette.ContainsKey($k)) { $script:Palette[$k] } else { '#555555' } }

function ConvertTo-XmlText {
    param([string]$S)
    if ($null -eq $S) { return '' }
    $S = $S -replace '&', '&amp;'
    $S = $S -replace '<', '&lt;'
    $S = $S -replace '>', '&gt;'
    $S = $S -replace '"', '&quot;'
    return $S
}

# justify NEVER moves an object relative to its anchor point: Template Editor draws both
# text and valuefields rightward from their x. For a valuefield, justify only aligns the
# value INSIDE the length-characters box; for a single-line text it has no visual effect.
# (Verified live in TplEd 2026 and against shipped embed.tpl's "d x l" tiling.)
function Get-Anchor { param([string]$Justify) switch ($Justify) { 'RIGHT' { 'end' } 'CENTERED' { 'middle' } 'CENTER' { 'middle' } default { 'start' } } }

# ============================================================================
# 2 & 3. GRAPHICAL LAYOUT + SVG RENDERER  (sections, rows, nesting, objects)
# ============================================================================

# Graphical-render state (script-scoped so the recursive stamping is simple).
function Reset-RenderState {
    $script:Scale     = 4.0        # px per template unit (~mm)
    $script:PadX      = 24.0
    $script:PadY      = 44.0       # room for the title strip
    $script:Y         = 0.0        # running vertical cursor, template units
    $script:MaxY      = 0.0
    $script:Body      = New-Object System.Text.StringBuilder
    $script:Boxes     = New-Object System.Collections.ArrayList   # valuefield + text extents for diagnostics
    $script:HLines    = New-Object System.Collections.ArrayList   # horizontal lineorarc rules, for the line-through-text check
    $script:Warnings  = New-Object System.Collections.ArrayList
    $script:SeenWarnings = New-Object 'System.Collections.Generic.HashSet[string]'   # dedup key set
    $script:HeaderXs  = New-Object System.Collections.ArrayList   # header/pageheader text anchors (textual alignment)
    $script:YUp = $false   # Template Editor origin is bottom-left (y up); flip local y within each band
    $script:RowSeq = 0     # unique id per row *definition*, so sibling rows don't share a diagnostics band
    $script:IsGraphical = $false   # header-column alignment check applies to textual reports only
}

function OX { param($X) $script:PadX + $X * $script:Scale }
function OY { param($Y) $script:PadY + $Y * $script:Scale }

# Map an object's local y within a band to top-down screen space. Template Editor's
# y-axis points up (origin bottom-left) for BOTH .tpl and .rpt, so a field at local y
# sits (Height - y) from the band top. Output flow (section/row order) is still top-down;
# only the y WITHIN a band is measured from the bottom.
function Get-BandY { param([double]$LocalY, [double]$Height) if ($script:YUp) { $Height - $LocalY } else { $LocalY } }

function Add-Svg { param([string]$S) [void]$script:Body.AppendLine($S) }
function Note-MaxY { param($UnitY) $py = OY $UnitY; if ($py -gt $script:MaxY) { $script:MaxY = $py } }

function Add-Warning {
    param([string]$Message, $Box)
    if ($Box) { $Box.Flagged = $true }   # flag every instance so the red overlay marks them all
    # A repeated data row renders once per sample instance ('REBAR#10.1', '.2', …); the same
    # structural fault would otherwise be reported N times. Collapse on the instance suffix.
    $key = [regex]::Replace($Message, '#(\d+)\.\d+', '#$1')
    if ($script:SeenWarnings.Contains($key)) { return }
    [void]$script:SeenWarnings.Add($key)
    [void]$script:Warnings.Add($Message)
}

# Draw one content object (text/valuefield/lineorarc/picture/rectangle/group/graphicalfield) at band offset $baseY.
# $InGroup marks children of a `group` (shape sketches): they draw normally but stay out of
# the line-through-text check, where a label ON a diagram stroke is intentional.
function Draw-GObject {
    param($Obj, [double]$BaseY, [string]$BandKey, [double]$Height, [bool]$Hidden, [bool]$InGroup = $false)

    switch ($Obj.Keyword) {
        'text' {
            $x = Get-Num $Obj 'x1' 0; $ly = Get-Num $Obj 'y1' 0
            $s = Get-Str $Obj 'string' ''
            $fs = Get-Num $Obj 'fontsize' 2.5; $ratio = Get-Num $Obj 'fontratio' 1
            $angle = Get-Num $Obj 'angle' 0
            $col = Get-Color (Get-Num $Obj 'fontcolor' 153)
            $fy = Get-BandY $ly $Height
            $px = OX $x; $py = OY ($BaseY + $fy)
            $fontpx = [math]::Max(6, $fs * $script:Scale)
            # x1 is the LEFT edge of the string no matter what justify says — TplEd never
            # re-anchors a text on its point (justify is a no-op for single-line text)
            $transform = ''
            if ($angle -ne 0) { $transform = " transform=`"rotate($([math]::Round(-$angle,2)) $([math]::Round($px,2)) $([math]::Round($py,2)))`"" }
            Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="{2:0.#}" fill="{3}" text-anchor="start"{4}>{5}</text>' -f `
                    $px, $py, $fontpx, $col, $transform, (ConvertTo-XmlText $s))
            Note-MaxY ($BaseY + $ly)
            # width-extent for the past-width diagnostic (approx glyph width)
            $charW = $fs * $ratio * 0.55
            $textW = $s.Length * $charW
            $x1 = $x
            [void]$script:Boxes.Add([pscustomobject]@{ Kind = 'text'; Band = $BandKey; X1 = $x1; X2 = $x1 + $textW
                    LocalY = $ly; YTop = ($fy - $fs); YBot = $fy; FontSize = $fs; Height = $Height; Anchor = $x
                    Str = $s; Name = (Get-Str $Obj 'name' 'text'); Visible = $true
                    Hidden = $Hidden; InGroup = $InGroup; Rotated = ($angle -ne 0)
                    Px1 = (OX $x1); Py1 = (OY ($BaseY + $fy - $fs)); Px2 = (OX ($x1 + $textW)); Py2 = (OY ($BaseY + $fy)); Flagged = $false })
            if ($BandKey -like 'HDR:*') { [void]$script:HeaderXs.Add([double]$x) }
        }
        'valuefield' {
            $loc = Get-Tuple $Obj 'location' @(0, 0)
            $x = [double]$loc[0]; $ly = if ($loc.Count -gt 1) { [double]$loc[1] } else { 0 }
            $length = Get-Num $Obj 'length' 10
            $fs = Get-Num $Obj 'fontsize' 2.5; $ratio = Get-Num $Obj 'fontratio' 1
            $just = Get-Str $Obj 'justify' 'LEFT'
            $vis = (Get-Str $Obj 'visibility' 'TRUE') -ne 'FALSE'
            $dtype = Get-Str $Obj 'datatype' 'STRING'
            $decimals = Get-Num $Obj 'decimals' 0
            $angle = Get-Num $Obj 'angle' 0
            $ph = Get-Placeholder (Get-Str $Obj 'formula' '')
            $col = Get-Color (Get-Num $Obj 'fontcolor' 153)

            # The field box ALWAYS starts at location.x and spans length character cells
            # to the right (TplEd cell width ≈ 0.67 × fontsize × ratio — measured in TplEd
            # 2026 and consistent with shipped embed.tpl's tiled "d x l" fields). justify
            # only aligns the value inside that fixed box; it never moves the box.
            $charW = $fs * $ratio * 0.67
            $boxW = $length * $charW
            $boxLeft = $x
            $boxRight = $boxLeft + $boxW

            $fy = Get-BandY $ly $Height
            $fontpx = [math]::Max(6, $fs * $script:Scale)
            $topPx = OY ($BaseY + $fy - $fs)
            $leftPx = OX $boxLeft
            $wPx = $boxW * $script:Scale
            $hPx = $fs * $script:Scale

            $dash = if ($vis) { '' } else { ' stroke-dasharray="3,2"' }
            $fill = if ($vis) { '#eef3fb' } else { '#f4f4f4' }
            $stroke = if ($vis) { '#8aa4c8' } else { '#b8b8b8' }
            Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="{4}" stroke="{5}"{6}/>' -f `
                    $leftPx, $topPx, $wPx, $hPx, $fill, $stroke, $dash)

            $anchor = Get-Anchor $just
            $textX = switch ($anchor) { 'end' { $boxRight } 'middle' { ($boxLeft + $boxRight) / 2 } default { $boxLeft } }
            $textPx = OX $textX; $textY = OY ($BaseY + $fy)
            $textCol = if ($vis) { $col } else { '#999999' }
            Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="{2:0.#}" fill="{3}" text-anchor="{4}">{5}</text>' -f `
                    $textPx, $textY, ($fontpx * 0.9), $textCol, $anchor, (ConvertTo-XmlText $ph))
            Note-MaxY ($BaseY + $fy)

            $isNumeric = ($dtype -eq 'DOUBLE' -or $dtype -eq 'INTEGER' -or $dtype -eq 'FLOAT')
            [void]$script:Boxes.Add([pscustomobject]@{ Kind = 'vf'; Band = $BandKey; X1 = $boxLeft; X2 = $boxRight
                    LocalY = $ly; YTop = ($fy - $fs); YBot = $fy; FontSize = $fs; Height = $Height; Anchor = $x; Visible = $vis; Numeric = $isNumeric
                    Length = $length; Decimals = $decimals; Name = (Get-Str $Obj 'name' '?')
                    Hidden = $Hidden; InGroup = $InGroup; Rotated = ($angle -ne 0)
                    Px1 = $leftPx; Py1 = $topPx; Px2 = ($leftPx + $wPx); Py2 = ($topPx + $hPx); Flagged = $false })
        }
        'lineorarc' {
            $x1 = Get-Num $Obj 'x1' 0; $y1 = Get-Num $Obj 'y1' 0
            $x2 = Get-Num $Obj 'x2' 0; $y2 = Get-Num $Obj 'y2' 0
            $bulge = Get-Num $Obj 'bulge' 0
            $col = Get-Color (Get-Num $Obj 'color' 153)
            $lw = [math]::Max(0.6, (Get-Num $Obj 'linewidth' 1) * 0.5)
            $fy1 = Get-BandY $y1 $Height; $fy2 = Get-BandY $y2 $Height
            $p1x = OX $x1; $p1y = OY ($BaseY + $fy1); $p2x = OX $x2; $p2y = OY ($BaseY + $fy2)
            # horizontal table rules feed the line-through-text check; sketch strokes (in
            # groups) and hidden bands stay out of it
            if (-not $InGroup -and -not $Hidden -and $bulge -eq 0 -and [math]::Abs($y1 - $y2) -lt 0.05) {
                [void]$script:HLines.Add([pscustomobject]@{ Band = $BandKey; X1 = [math]::Min($x1, $x2); X2 = [math]::Max($x1, $x2)
                        Y = $fy1; LY = $y1; Name = (Get-Str $Obj 'name' 'line') })
            }
            if ($bulge -eq 0) {
                Add-Svg ('  <line x1="{0:0.##}" y1="{1:0.##}" x2="{2:0.##}" y2="{3:0.##}" stroke="{4}" stroke-width="{5:0.#}"/>' -f `
                        $p1x, $p1y, $p2x, $p2y, $col, $lw)
            }
            else {
                # DXF bulge: b = tan(theta/4). Build an SVG arc between the endpoints.
                $theta = 4 * [math]::Atan([math]::Abs($bulge))
                $dx = $p2x - $p1x; $dy = $p2y - $p1y
                $chord = [math]::Sqrt($dx * $dx + $dy * $dy)
                if ($theta -gt 0.0001 -and $chord -gt 0) {
                    $r = $chord / (2 * [math]::Sin($theta / 2))
                    $large = if ($theta -gt [math]::PI) { 1 } else { 0 }
                    $sweep = if ($bulge -gt 0) { 1 } else { 0 }
                    Add-Svg ('  <path d="M {0:0.##} {1:0.##} A {2:0.##} {2:0.##} 0 {3} {4} {5:0.##} {6:0.##}" fill="none" stroke="{7}" stroke-width="{8:0.#}"/>' -f `
                            $p1x, $p1y, $r, $large, $sweep, $p2x, $p2y, $col, $lw)
                }
            }
            Note-MaxY ($BaseY + [math]::Max($y1, $y2))
        }
        'rectangle' {
            $x1 = Get-Num $Obj 'x1' 0; $y1 = Get-Num $Obj 'y1' 0
            $x2 = Get-Num $Obj 'x2' 0; $y2 = Get-Num $Obj 'y2' 0
            $col = Get-Color (Get-Num $Obj 'color' 153)
            $lw = [math]::Max(0.6, (Get-Num $Obj 'linewidth' 1) * 0.5)
            $filled = (Get-Str $Obj 'filled' 'FALSE') -eq 'TRUE'
            $fy1 = Get-BandY $y1 $Height; $fy2 = Get-BandY $y2 $Height
            $lx = OX ([math]::Min($x1, $x2)); $ty = OY ($BaseY + [math]::Max($fy1, $fy2))
            $w = [math]::Abs($x2 - $x1) * $script:Scale; $h = [math]::Abs($fy2 - $fy1) * $script:Scale
            $fill = if ($filled) { $col } else { 'none' }
            Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="{4}" stroke="{5}" stroke-width="{6:0.#}"/>' -f `
                    $lx, $ty, $w, $h, $fill, $col, $lw)
            Note-MaxY ($BaseY + [math]::Max($y1, $y2))
        }
        'group' {
            # a named bundle of primitives (shape diagrams etc.) — draw each child in place
            foreach ($child in $Obj.Children) {
                Draw-GObject -Obj $child -BaseY $BaseY -BandKey $BandKey -Height $Height -Hidden $Hidden -InGroup $true
            }
        }
        'graphicalfield' {
            $loc = Get-Tuple $Obj 'location' @(0, 0)
            $x = [double]$loc[0]; $ly = if ($loc.Count -gt 1) { [double]$loc[1] } else { 0 }
            $gw = Get-Num $Obj 'width' 30; $gh = Get-Num $Obj 'height' 15
            $fld = Get-Str $Obj 'field' 'graphic'
            $fy = Get-BandY $ly $Height
            $lx = OX $x; $ty = OY ($BaseY + $fy + $gh)
            $w = $gw * $script:Scale; $h = $gh * $script:Scale
            Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="#eae4f2" stroke="#9a86c0" stroke-dasharray="2,2"/>' -f $lx, $ty, $w, $h)
            Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="9" fill="#6a5aa0" text-anchor="middle">[{2}]</text>' -f ($lx + $w / 2), ($ty + $h / 2), (ConvertTo-XmlText $fld))
            Note-MaxY ($BaseY + $ly + $gh)
        }
        'picture' {
            $x1 = Get-Num $Obj 'x1' 0; $y1 = Get-Num $Obj 'y1' 0
            $x2 = Get-Num $Obj 'x2' ($x1 + 20); $y2 = Get-Num $Obj 'y2' ($y1 + 10)
            $nm = Get-Str $Obj 'name' 'picture'
            $fy1 = Get-BandY $y1 $Height; $fy2 = Get-BandY $y2 $Height
            $lx = OX ([math]::Min($x1, $x2)); $ly2 = OY ($BaseY + [math]::Min($fy1, $fy2))
            $w = [math]::Abs($x2 - $x1) * $script:Scale; $h = [math]::Abs($y2 - $y1) * $script:Scale
            if ($w -lt 8) { $w = 40 }; if ($h -lt 8) { $h = 24 }
            Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="#e2e2e2" stroke="#999" stroke-dasharray="2,2"/>' -f $lx, $ly2, $w, $h)
            Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="9" fill="#777" text-anchor="middle">[img: {2}]</text>' -f ($lx + $w / 2), ($ly2 + $h / 2), (ConvertTo-XmlText $nm))
            Note-MaxY ($BaseY + [math]::Max($y1, $y2))
        }
        default {
            # unknown block type -> opaque labelled box, so nothing is silently dropped
            $px = OX 0; $py = OY $BaseY
            Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="40" height="14" fill="#fff4e0" stroke="#d0a040"/>' -f $px, $py)
            Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="9" fill="#a06000">?{2}</text>' -f ($px + 3), ($py + 10), (ConvertTo-XmlText $Obj.Keyword))
        }
    }
}

# Draw every direct content object of a band; also emit the band outline + label.
function Draw-GBand {
    param($Node, [double]$BaseY, [string]$BandKey, [double]$Height, [bool]$Hidden, [string]$Label)

    $wUnits = $script:TemplateWidth
    $topPx = OY $BaseY; $hPx = $Height * $script:Scale; $wPx = $wUnits * $script:Scale
    if ($Hidden) {
        Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="none" stroke="#c07070" stroke-dasharray="4,3"/>' -f (OX 0), $topPx, $wPx, $hPx)
    }
    if ($Label) {
        Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="8" fill="#b06060">{2}</text>' -f ((OX 0) + 2), ($topPx + 9), (ConvertTo-XmlText $Label))
    }

    $maxLocalY = 0.0
    foreach ($obj in $Node.Children) {
        if ($obj.Keyword -eq 'row') { continue }
        Draw-GObject -Obj $obj -BaseY $BaseY -BandKey $BandKey -Height $Height -Hidden $Hidden
        $ly = if ($obj.Keyword -eq 'valuefield') { $t = Get-Tuple $obj 'location' @(0, 0); if ($t.Count -gt 1) { [double]$t[1] } else { 0 } } else { Get-Num $obj 'y1' 0 }
        if ($ly -gt $maxLocalY) { $maxLocalY = $ly }
    }
    # below-height diagnostic: content sits past the band's declared height
    if ($Height -gt 0 -and $maxLocalY -gt $Height + 0.5) {
        Add-Warning ("Row/section '$Label$BandKey' content at y=$maxLocalY exceeds its height=$Height (overlaps the next band).")
    }
    Note-MaxY ($BaseY + $Height)
}

function Get-DirectContent { param($Node) $Node.Children | Where-Object { $_.Keyword -ne 'row' } }

# -SingleBar: collapse mutually-exclusive rule-guarded sibling rows to one representative per
# content type, so the preview reads one-object-per-line like real output. Rows with no rule
# (headings, hidden grouping wrappers, static bands) are always kept.
function Select-SiblingRows {
    param($Rows)
    $list = @($Rows | Where-Object { $null -ne $_ })   # normalize: empty pipeline -> @(), never @($null)
    if (-not $script:SingleBar) { return $list }
    $seenRuled = New-Object 'System.Collections.Generic.HashSet[string]'
    $out = New-Object System.Collections.ArrayList
    foreach ($r in $list) {
        $rule = Get-Str $r 'rule' ''
        if ([string]::IsNullOrWhiteSpace($rule)) { [void]$out.Add($r); continue }
        $ct = Get-Str $r 'contenttype' (Get-Str $r 'name' 'row')
        if ($seenRuled.Add($ct)) { [void]$out.Add($r) }   # first ruled row of this type wins
    }
    return @($out)
}

# Number of sample bands to stamp for one (visible) row definition.
function Get-RowSampleCount { param([bool]$Hidden) if ($Hidden -or $script:SingleBar) { 1 } else { $script:Rows } }

# Recursively stamp a data row band (with nesting + hidden-row handling).
function Draw-GRow {
    param($Row)
    $hidden = (Get-Str $Row 'visibility' 'TRUE') -eq 'FALSE'
    $height = Get-Num $Row 'height' 1
    $contentType = Get-Str $Row 'contenttype' (Get-Str $Row 'name' 'row')
    $count = Get-RowSampleCount $hidden
    $script:RowSeq++            # distinct per row definition so sibling rows aren't cross-compared
    $defId = $script:RowSeq

    for ($i = 1; $i -le $count; $i++) {
        $direct = @(Get-DirectContent $Row)
        $childRows = @(Select-SiblingRows (Get-ChildBlocks $Row 'row'))
        $bandKey = "$($contentType)#$defId.$i"
        $label = if ($hidden) { "(hidden row: $contentType)" } else { '' }

        if ($direct.Count -gt 0) {
            $bandTop = $script:Y
            Draw-GBand -Node $Row -BaseY $bandTop -BandKey $bandKey -Height $height -Hidden $hidden -Label $label
            $script:Y = $bandTop + $height
        }
        if ($childRows.Count -gt 0) {
            $grpTop = $script:Y
            foreach ($c in $childRows) { Draw-GRow -Row $c }
            if ($hidden -and $direct.Count -eq 0) {
                # bracket the whole group so the (hidden) grouping level stays visible
                $gt = OY $grpTop; $gb = OY $script:Y
                Add-Svg ('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="none" stroke="#c07070" stroke-dasharray="4,3"/>' -f ((OX 0) - 6), $gt, ($script:TemplateWidth * $script:Scale + 12), ($gb - $gt))
                Add-Svg ('  <text x="{0:0.##}" y="{1:0.##}" font-size="8" fill="#b06060">{2}</text>' -f ((OX 0) - 4), ($gt - 2), (ConvertTo-XmlText $label))
            }
        }
        if ($direct.Count -eq 0 -and $childRows.Count -eq 0) {
            $script:Y = $script:Y + $height
        }
    }
}

function Render-Graphical {
    param($Root, [string]$OutPath)
    Reset-RenderState
    $script:YUp = $true      # Template Editor origin is bottom-left (y up)
    $script:IsGraphical = $true
    $script:TemplateWidth = Get-Num $Root 'width' 100
    $margins = Get-Tuple $Root 'margins' @(0, 0, 0, 0)
    $script:Y = if ($margins.Count -ge 1) { [double]$margins[0] } else { 0 }

    $topRows = Select-SiblingRows (@($Root.Children | Where-Object { $_.Keyword -eq 'row' }))
    foreach ($sec in $Root.Children) {
        switch ($sec.Keyword) {
            { $_ -in 'header', 'pageheader', 'footer' } {
                $h = Get-Num $sec 'height' 4
                $bandKey = if ($_ -in 'header', 'pageheader') { "HDR:$($sec.Keyword)" } else { "SEC:$($sec.Keyword)" }
                $top = $script:Y
                # faint separator + section label
                Add-Svg ('  <line x1="{0:0.##}" y1="{1:0.##}" x2="{2:0.##}" y2="{1:0.##}" stroke="#e5e5e5" stroke-width="0.5"/>' -f (OX 0), (OY $top), (OX $script:TemplateWidth))
                Draw-GBand -Node $sec -BaseY $top -BandKey $bandKey -Height $h -Hidden $false -Label ''
                $script:Y = $top + $h
            }
            'row' { if ($topRows -contains $sec) { Draw-GRow -Row $sec } }
            default { }   # non-section top-level keys already captured as Props
        }
    }

    Invoke-Diagnostics
    $svg = Build-Svg -Root $Root
    Write-Diagnostics
    if ($AsText) { return $null }   # graphical + -AsText prints only diagnostics
    Write-Output-File -Content $svg -OutPath $OutPath -Html:$Html
}

# ============================================================================
# 4. TEXTUAL LAYOUT  ->  character grid  (also rendered as an SVG grid)
# ============================================================================

function Set-GridChars {
    param([System.Collections.ArrayList]$Grid, [int]$LineIdx, [int]$Col, [string]$Text)
    if ($Col -lt 0) { $Text = $Text.Substring([math]::Min(-$Col, $Text.Length)); $Col = 0 }
    while ($Grid.Count -le $LineIdx) { [void]$Grid.Add((New-Object System.Text.StringBuilder)) }
    $sb = $Grid[$LineIdx]
    while ($sb.Length -lt $Col + $Text.Length) { [void]$sb.Append(' ') }
    for ($k = 0; $k -lt $Text.Length; $k++) { $sb[$Col + $k] = $Text[$k] }
}

function Place-TextualObject {
    param([System.Collections.ArrayList]$Grid, $Obj, [int]$BaseLine, [string]$BandKey, [double]$Height)

    # y-up: line index runs 0 (top) .. Height-1 (bottom), so a field at local y (from the
    # bottom) prints on line (Height-1) - y. No-op for the usual single-line band.
    $flipLine = { param($ly) if ($script:YUp) { [int]([math]::Max(0, $Height - 1) - $ly) } else { [int]$ly } }

    if ($Obj.Keyword -eq 'text') {
        $x = [int](Get-Num $Obj 'x1' 0); $ly = [int](Get-Num $Obj 'y1' 0)
        $s = Get-Str $Obj 'string' ''
        # x1 is always the LEFT edge — justify never re-anchors a text on its point
        $col = $x
        $tline = & $flipLine $ly
        Set-GridChars -Grid $Grid -LineIdx ($BaseLine + $tline) -Col $col -Text $s
        [void]$script:Boxes.Add([pscustomobject]@{ Kind = 'text'; Band = $BandKey; X1 = $col; X2 = ($col + $s.Length)
                FX1 = $col; FX2 = ($col + $s.Length); YTop = $tline; YBot = ($tline + 1); Str = $s
                LocalY = $ly; Height = $Height; Anchor = $x; Visible = $true; Name = (Get-Str $Obj 'name' '?'); Flagged = $false })
        if ($BandKey -like 'HDR:*') { [void]$script:HeaderXs.Add([double]$x) }
    }
    elseif ($Obj.Keyword -eq 'valuefield') {
        $loc = Get-Tuple $Obj 'location' @(0, 0)
        $x = [int]$loc[0]; $ly = if ($loc.Count -gt 1) { [int]$loc[1] } else { 0 }
        $length = [int](Get-Num $Obj 'length' 10)
        $just = Get-Str $Obj 'justify' 'LEFT'
        $vis = (Get-Str $Obj 'visibility' 'TRUE') -ne 'FALSE'
        $dtype = Get-Str $Obj 'datatype' 'STRING'
        $decimals = Get-Num $Obj 'decimals' 0
        $ph = Get-Placeholder (Get-Str $Obj 'formula' '')

        $truncated = $false
        $shown = $ph
        if ($shown.Length -gt $length) { $shown = $shown.Substring(0, [math]::Max(0, $length)); $truncated = $true }
        $pad = $length - $shown.Length
        if ($pad -gt 0) {
            if ($just -eq 'RIGHT') { $shown = (' ' * $pad) + $shown }
            elseif ($just -match 'CENTER') { $l = [int]($pad / 2); $shown = (' ' * $l) + $shown + (' ' * ($pad - $l)) }
            else { $shown = $shown + (' ' * $pad) }
        }
        if (-not $vis) { $shown = '-' * $length }   # hidden key: show as a dashed cell so it is visible
        $fline = & $flipLine $ly
        Set-GridChars -Grid $Grid -LineIdx ($BaseLine + $fline) -Col $x -Text $shown

        $isNumeric = ($dtype -eq 'DOUBLE' -or $dtype -eq 'INTEGER' -or $dtype -eq 'FLOAT')
        # The field box always starts at location.x and spans length cells rightward;
        # justify only aligns the value inside it (already applied to $shown above).
        [void]$script:Boxes.Add([pscustomobject]@{ Kind = 'vf'; Band = $BandKey; X1 = $x; X2 = ($x + $length)
                FX1 = $x; FX2 = ($x + $length)
                LocalY = $ly; YTop = $fline; YBot = ($fline + 1); Height = $Height; Anchor = $x; Visible = $vis; Numeric = $isNumeric
                Length = $length; Decimals = $decimals; Name = (Get-Str $Obj 'name' '?'); Truncated = $truncated; Flagged = $false })
    }
}

function Place-TextualBand {
    param([System.Collections.ArrayList]$Grid, $Node, [int]$BaseLine, [string]$BandKey, [double]$Height, [string]$Label)
    if ($Label) { Set-GridChars -Grid $Grid -LineIdx $BaseLine -Col 0 -Text $Label }
    $maxLocalY = 0.0
    foreach ($obj in $Node.Children) {
        if ($obj.Keyword -eq 'row') { continue }
        Place-TextualObject -Grid $Grid -Obj $obj -BaseLine $BaseLine -BandKey $BandKey -Height $Height
        $ly = if ($obj.Keyword -eq 'valuefield') { $t = Get-Tuple $obj 'location' @(0, 0); if ($t.Count -gt 1) { [double]$t[1] } else { 0 } } else { Get-Num $obj 'y1' 0 }
        if ($ly -gt $maxLocalY) { $maxLocalY = $ly }
    }
    if ($Height -gt 0 -and $maxLocalY -gt $Height - 1 + 0.5) {
        Add-Warning ("Row/section '$BandKey' content at line $maxLocalY exceeds its height=$Height lines.")
    }
}

function Place-TextualRow {
    param([System.Collections.ArrayList]$Grid, $Row)
    $hidden = (Get-Str $Row 'visibility' 'TRUE') -eq 'FALSE'
    $height = [int](Get-Num $Row 'height' 1)
    $contentType = Get-Str $Row 'contenttype' (Get-Str $Row 'name' 'row')
    $count = Get-RowSampleCount $hidden
    for ($i = 1; $i -le $count; $i++) {
        $direct = @(Get-DirectContent $Row)
        $childRows = @(Select-SiblingRows (Get-ChildBlocks $Row 'row'))
        $bandKey = "$($contentType)#$i"
        if ($direct.Count -gt 0) {
            $label = if ($hidden) { "" } else { '' }
            Place-TextualBand -Grid $Grid -Node $Row -BaseLine $script:Line -BandKey $bandKey -Height $height -Label $label
            if ($hidden) { Set-GridChars -Grid $Grid -LineIdx $script:Line -Col ($script:TextWidth + 2) -Text "(hidden: $contentType)" }
            $script:Line += $height
        }
        if ($childRows.Count -gt 0) {
            if ($hidden -and $direct.Count -eq 0) {
                Set-GridChars -Grid $Grid -LineIdx $script:Line -Col ($script:TextWidth + 2) -Text "(group: $contentType)"
            }
            foreach ($c in $childRows) { Place-TextualRow -Grid $Grid -Row $c }
        }
        if ($direct.Count -eq 0 -and $childRows.Count -eq 0) { $script:Line += $height }
    }
}

function Render-Textual {
    param($Root, [string]$OutPath)
    Reset-RenderState
    $script:YUp = $true      # Template Editor origin is bottom-left (y up) for reports too
    $script:TextWidth = [int](Get-Num $Root 'width' 78)
    $script:Line = 0
    $grid = New-Object System.Collections.ArrayList

    $topRows = Select-SiblingRows (@($Root.Children | Where-Object { $_.Keyword -eq 'row' }))
    foreach ($sec in $Root.Children) {
        switch ($sec.Keyword) {
            { $_ -in 'header', 'pageheader', 'footer' } {
                $h = [int](Get-Num $sec 'height' 4)
                $bandKey = if ($_ -in 'header', 'pageheader') { "HDR:$($sec.Keyword)" } else { "SEC:$($sec.Keyword)" }
                Place-TextualBand -Grid $grid -Node $sec -BaseLine $script:Line -BandKey $bandKey -Height $h -Label ''
                $script:Line += $h
            }
            'row' { if ($topRows -contains $sec) { Place-TextualRow -Grid $grid -Row $sec } }
            default { }
        }
    }

    Invoke-Diagnostics
    Write-Diagnostics

    # build plain-text lines
    $lines = @($grid | ForEach-Object { $_.ToString().TrimEnd() })
    $ruler = ('.' * $script:TextWidth)
    if ($script:TextWidth -ge 10) {
        $rc = New-Object System.Text.StringBuilder
        for ($c = 0; $c -lt $script:TextWidth; $c += 10) { [void]$rc.Append(('{0,-10}' -f $c)) }
        $ruler = $rc.ToString()
    }

    if ($AsText) {
        Write-Output $ruler
        Write-Output ('|' + ('-' * ($script:TextWidth)) + '|  (width=' + $script:TextWidth + ')')
        foreach ($ln in $lines) { Write-Output $ln }
        return
    }

    $svg = Build-TextualSvg -Root $Root -Lines $lines -Ruler $ruler
    Write-Output-File -Content $svg -OutPath $OutPath -Html:$Html
}

# ============================================================================
# 5. DIAGNOSTICS
# ============================================================================

function Invoke-Diagnostics {
    $tol = 0.5
    $groups = $script:Boxes | Group-Object Band
    foreach ($g in $groups) {
        $vfs = @($g.Group | Where-Object { $_.Kind -eq 'vf' -and $_.Visible } | Sort-Object X1)
        for ($a = 0; $a -lt $vfs.Count; $a++) {
            for ($b = $a + 1; $b -lt $vfs.Count; $b++) {
                $xOverlap = $vfs[$b].X1 -lt $vfs[$a].X2 - $tol -and $vfs[$b].X2 -gt $vfs[$a].X1 + $tol
                # Only a real collision if the fields also share vertical space. Graphical
                # title blocks stack fields at different y locations, so an X-range overlap
                # between two fields on different lines is not a collision.
                $yOverlap = $vfs[$b].YTop -lt $vfs[$a].YBot - $tol -and $vfs[$b].YBot -gt $vfs[$a].YTop + $tol
                if ($xOverlap -and $yOverlap) {
                    Add-Warning ("Columns collide in '$($g.Name)': field '$($vfs[$a].Name)' [$([math]::Round($vfs[$a].X1,1))..$([math]::Round($vfs[$a].X2,1))] overlaps '$($vfs[$b].Name)' [$([math]::Round($vfs[$b].X1,1))..$([math]::Round($vfs[$b].X2,1))].") $vfs[$a]
                    $vfs[$b].Flagged = $true
                }
            }
        }
    }

    # GRAPHICAL: a horizontal table rule (lineorarc) cutting through a text/field's glyph
    # band. `location`/`y1` anchor the text BOTTOM (y-up), so a baseline computed top-down
    # lands the glyphs across the rule above — the classic Y-down authoring mistake.
    # Vertical extents are exact (fontsize is declared; no glyph estimate involved), so the
    # only tolerance is $cut: the rule must penetrate the span from BOTH sides, which keeps
    # legal underlines (rule at the baseline) and cell edges (rule at the glyph top) quiet.
    # Group children (shape sketches) are excluded on both sides, as are rotated texts,
    # whose axis-aligned span is meaningless. Short text (<3 chars) is skipped like in the
    # textual label check: sweeping the 2025.0 corpus showed those are diagram annotations
    # ('CT', 'CB') deliberately placed on leader lines drawn loose in the band. Value
    # fields are always checked — they are table data, never decoration.
    if ($script:IsGraphical -and $script:HLines.Count -gt 0) {
        $cut = 0.25
        $linesByBand = $script:HLines | Group-Object Band -AsHashTable -AsString
        foreach ($box in $script:Boxes) {
            if ($box.Kind -ne 'vf' -and $box.Kind -ne 'text') { continue }
            if (-not $box.Visible -or $box.Hidden -or $box.InGroup -or $box.Rotated) { continue }
            if ($box.Kind -eq 'text') {
                $s = [string]$box.Str
                if ($s.Trim().Length -lt 3 -or $s -notmatch '[A-Za-z0-9]') { continue }
            }
            $lines = $linesByBand[$box.Band]
            if (-not $lines) { continue }
            $what = if ($box.Kind -eq 'vf') { "field '$($box.Name)'" } else { "text '$($box.Str)'" }
            foreach ($l in $lines) {
                $xOverlap = ($l.X1 -lt $box.X2 - $tol) -and ($l.X2 -gt $box.X1 + $tol)
                $cutsThrough = ($l.Y -gt $box.YTop + $cut) -and ($l.Y -lt $box.YBot - $cut)
                if ($xOverlap -and $cutsThrough) {
                    $bot = [math]::Round($box.LocalY, 2); $top = [math]::Round($box.LocalY + $box.FontSize, 2)
                    Add-Warning ("Line '$($l.Name)' at y=$([math]::Round($l.LY, 2)) cuts through $what (spans y=$bot..$top) in '$($box.Band)' — y anchors the text BOTTOM (y-up); lower the text or move the line.") $box
                }
            }
        }
    }

    # Label/field overlap in a TEXTUAL report's footer. Template Editor rejects a text label
    # that lands on top of a value field ("Found overlapping objects"), which the column check
    # above never catches (it compares field-to-field only). Scoped to the footer, where a
    # total label overlapping its right-justified total is the classic mistake and the signal
    # is clean; report headers pack column labels tight against field extents by design, so
    # they are left out to avoid false alarms. Textual only - field extents are exact character
    # counts there; the graphical glyph-width estimate is too rough to judge overlap reliably.
    # Deliberately conservative - a real label (>=3 chars incl. a letter/digit) and a
    # multi-character overlap - so unit tags ("(mm)"), separators ("x","-",":") and dashed
    # rules ("----") don't trip it. Uses the box extents (FX1/FX2 — left edge at the
    # object's x, spanning rightward); text-vs-text is left alone (decorative overlaps
    # are legal).
    if (-not $script:IsGraphical) {
        $ovMin = 3.0        # need a solid multi-char overlap, not a 1-2 char abutment ("Page:" + page no.)
        $wideField = 24     # fields wider than this are banner/message fields (Instructions,
                            # PROJECTMESSAGE) that titles sit within by design, not columns
        foreach ($g in $groups) {
            if ($g.Name -notlike 'SEC:*') { continue }   # footer only (SEC: prefix); see note above
            $items = @($g.Group | Where-Object { $_.Visible -and ($_.Kind -eq 'vf' -or $_.Kind -eq 'text') -and $_.PSObject.Properties['FX1'] } | Sort-Object FX1)
            for ($a = 0; $a -lt $items.Count; $a++) {
                for ($b = $a + 1; $b -lt $items.Count; $b++) {
                    if ($items[$a].Kind -eq $items[$b].Kind) { continue }   # only text-vs-field pairs
                    $lbl = if ($items[$a].Kind -eq 'text') { $items[$a] } else { $items[$b] }
                    $fld = if ($items[$a].Kind -eq 'vf')   { $items[$a] } else { $items[$b] }
                    $s = [string]$lbl.Str
                    if ($s.Length -lt 3 -or $s -notmatch '[A-Za-z0-9]') { continue }   # decorative/unit text: skip
                    if (($fld.FX2 - $fld.FX1) -gt $wideField) { continue }             # banner/message field: skip
                    $ov = [math]::Min($lbl.FX2, $fld.FX2) - [math]::Max($lbl.FX1, $fld.FX1)
                    $yOverlap = $items[$b].YTop -lt $items[$a].YBot - $tol -and $items[$b].YBot -gt $items[$a].YTop + $tol
                    if ($ov -ge $ovMin -and $yOverlap) {
                        Add-Warning ("Label/field overlap in '$($g.Name)': text '$s' [$([math]::Round($lbl.FX1,1))..$([math]::Round($lbl.FX2,1))] overlaps field '$($fld.Name)' [$([math]::Round($fld.FX1,1))..$([math]::Round($fld.FX2,1))].") $fld
                    }
                }
            }
        }
    }

    # extends past template width
    $w = if ($script:TemplateWidth) { $script:TemplateWidth } else { $script:TextWidth }
    foreach ($box in $script:Boxes) {
        if ($box.X2 -gt $w + $tol) {
            $nm = if ($box.PSObject.Properties['Name']) { $box.Name } else { $box.Kind }
            Add-Warning ("'$nm' in '$($box.Band)' extends to $([math]::Round($box.X2,1)), past template width $w (will be clipped).") $box
        }
    }
    # numeric field too narrow for its decimals
    foreach ($box in ($script:Boxes | Where-Object { $_.Kind -eq 'vf' -and $_.Numeric })) {
        if ($box.Decimals -gt 0 -and $box.Length -lt $box.Decimals + 2) {
            Add-Warning ("Numeric field '$($box.Name)' in '$($box.Band)' has length=$($box.Length) but decimals=$($box.Decimals) — too narrow, risks '#'-fill.") $box
        }
    }
    # NB: we deliberately do NOT warn when the placeholder text is wider than `length`.
    # The placeholder is our invention ({PART_POS}), not the real value — its width says
    # nothing about whether real data truncates. Only `length` vs decimals/position is real.

    # textual: value field x doesn't line up under any header text x. Only meaningful for
    # column-based textual reports — graphical tables/schedules place fields absolutely
    # (usecolumns=FALSE), so "not under a header" is expected, not a fault.
    if (-not $script:IsGraphical -and $script:HeaderXs.Count -gt 0) {
        $hx = @($script:HeaderXs | Sort-Object -Unique)
        foreach ($box in ($script:Boxes | Where-Object { $_.Kind -eq 'vf' -and $_.Visible -and $_.Band -notlike 'HDR:*' -and $_.Band -notlike 'SEC:*' })) {
            $match = $false
            foreach ($x in $hx) { if ([math]::Abs($x - $box.Anchor) -le 1) { $match = $true; break } }
            if (-not $match) {
                Add-Warning ("Field '$($box.Name)' at x=$($box.Anchor) does not line up under any header column (data may print off-heading).") $box
            }
        }
    }
}

function Write-Diagnostics {
    if ($script:Warnings.Count -eq 0) {
        [Console]::Error.WriteLine("OK: no layout warnings.")
        return
    }
    [Console]::Error.WriteLine("$($script:Warnings.Count) layout warning(s):")
    foreach ($w in $script:Warnings) { [Console]::Error.WriteLine("  ! $w") }
}

# ============================================================================
# 6. SVG assembly + output
# ============================================================================

function Build-Svg {
    param($Root)
    $wPx = [math]::Ceiling($script:TemplateWidth * $script:Scale + 2 * $script:PadX)
    $warnPanelH = if ($script:Warnings.Count) { 18 + $script:Warnings.Count * 14 + 8 } else { 0 }
    $hPx = [math]::Ceiling($script:MaxY + $script:PadY + $warnPanelH)

    $name = Get-Str $Root 'name' '(unnamed)'
    $type = Get-Str $Root 'type' 'GRAPHICAL'
    $cols = Get-Tuple $Root 'columns' @(1, 1)
    $colNote = if ($cols.Count -ge 2 -and ([double]$cols[0] -ne 1)) { "  |  columns=($($cols[0]),$($cols[1])) — preview shows a SINGLE column" } else { '' }
    $valNote = if ($script:ShortValues) { 'sample values' } else { 'formulas shown as placeholders' }
    $rowNote = if ($script:SingleBar) { '1 representative band per row (single-bar)' } else { "$($script:Rows) sample row(s)" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="0 0 {0} {1}" font-family="Segoe UI, Arial, sans-serif">' -f $wPx, $hPx))
    [void]$sb.AppendLine('  <rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    # title strip
    [void]$sb.AppendLine(('  <text x="{0}" y="18" font-size="13" font-weight="bold" fill="#222">{1}</text>' -f $script:PadX, (ConvertTo-XmlText "$name  [$type]")))
    [void]$sb.AppendLine(('  <text x="{0}" y="33" font-size="10" fill="#777">Layout approximation — {1}, {2}{3}</text>' -f $script:PadX, $valNote, $rowNote, (ConvertTo-XmlText $colNote)))
    # template bounds
    [void]$sb.AppendLine(('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="none" stroke="#c8c8c8"/>' -f (OX 0), (OY 0), ($script:TemplateWidth * $script:Scale), ($script:MaxY - (OY 0))))
    [void]$sb.Append($script:Body.ToString())

    # red overlay marks on flagged boxes
    foreach ($box in ($script:Boxes | Where-Object { $_.Flagged -and $_.PSObject.Properties['Px1'] })) {
        [void]$sb.AppendLine(('  <rect x="{0:0.##}" y="{1:0.##}" width="{2:0.##}" height="{3:0.##}" fill="none" stroke="#d00000" stroke-width="1.5"/>' -f $box.Px1, $box.Py1, ($box.Px2 - $box.Px1), ($box.Py2 - $box.Py1)))
    }
    # width guide line
    [void]$sb.AppendLine(('  <line x1="{0:0.##}" y1="{1:0.##}" x2="{0:0.##}" y2="{2:0.##}" stroke="#d0b0b0" stroke-width="0.5" stroke-dasharray="2,3"/>' -f (OX $script:TemplateWidth), (OY 0), $script:MaxY))

    # warnings panel
    if ($script:Warnings.Count) {
        $py = $script:MaxY + 20
        [void]$sb.AppendLine(('  <text x="{0}" y="{1:0.##}" font-size="11" font-weight="bold" fill="#d00000">{2} layout warning(s):</text>' -f $script:PadX, $py, $script:Warnings.Count))
        $py += 15
        foreach ($w in $script:Warnings) {
            [void]$sb.AppendLine(('  <text x="{0}" y="{1:0.##}" font-size="10" fill="#b00000">! {2}</text>' -f $script:PadX, $py, (ConvertTo-XmlText $w)))
            $py += 14
        }
    }
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Build-TextualSvg {
    param($Root, [string[]]$Lines, [string]$Ruler)
    $charPx = 7.2; $lineH = 15.0; $padX = 16.0; $padY = 46.0
    $name = Get-Str $Root 'name' '(unnamed)'
    $cols = Get-Tuple $Root 'columns' @(1, 1)
    $colNote = if ($cols.Count -ge 2 -and ([double]$cols[0] -ne 1)) { "  |  columns=($($cols[0]),$($cols[1])) — single column shown" } else { '' }

    $bodyLines = @($Ruler) + $Lines
    $warnPanelH = if ($script:Warnings.Count) { 18 + $script:Warnings.Count * 14 + 8 } else { 0 }
    $wPx = [math]::Ceiling(($script:TextWidth + 2) * $charPx + 2 * $padX)
    $hPx = [math]::Ceiling($padY + $bodyLines.Count * $lineH + 10 + $warnPanelH)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{1}" viewBox="0 0 {0} {1}" font-family="Consolas, monospace">' -f $wPx, $hPx))
    [void]$sb.AppendLine('  <rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    [void]$sb.AppendLine(('  <text x="{0}" y="20" font-size="13" font-weight="bold" fill="#222" font-family="Segoe UI, Arial, sans-serif">{1}</text>' -f $padX, (ConvertTo-XmlText "$name  [TEXTUAL]")))
    [void]$sb.AppendLine(('  <text x="{0}" y="35" font-size="10" fill="#777" font-family="Segoe UI, Arial, sans-serif">Layout approximation — {1} sample row(s), width={2} chars{3}</text>' -f $padX, $script:Rows, $script:TextWidth, (ConvertTo-XmlText $colNote)))
    # right margin guide
    $guideX = $padX + $script:TextWidth * $charPx
    [void]$sb.AppendLine(('  <line x1="{0:0.##}" y1="{1}" x2="{0:0.##}" y2="{2:0.##}" stroke="#e0c0c0" stroke-width="0.5" stroke-dasharray="2,3"/>' -f $guideX, ($padY - 12), ($padY + $bodyLines.Count * $lineH)))

    $y = $padY
    $first = $true
    foreach ($ln in $bodyLines) {
        $fill = if ($first) { '#aaaaaa' } else { '#111111' }
        [void]$sb.AppendLine(('  <text x="{0:0.##}" y="{1:0.##}" font-size="12" fill="{2}" xml:space="preserve">{3}</text>' -f $padX, $y, $fill, (ConvertTo-XmlText $ln)))
        $y += $lineH; $first = $false
    }
    if ($script:Warnings.Count) {
        $py = $y + 12
        [void]$sb.AppendLine(('  <text x="{0}" y="{1:0.##}" font-size="11" font-weight="bold" fill="#d00000" font-family="Segoe UI, Arial, sans-serif">{2} layout warning(s):</text>' -f $padX, $py, $script:Warnings.Count))
        $py += 15
        foreach ($w in $script:Warnings) {
            [void]$sb.AppendLine(('  <text x="{0}" y="{1:0.##}" font-size="10" fill="#b00000" font-family="Segoe UI, Arial, sans-serif">! {2}</text>' -f $padX, $py, (ConvertTo-XmlText $w)))
            $py += 14
        }
    }
    [void]$sb.AppendLine('</svg>')
    return $sb.ToString()
}

function Write-Output-File {
    param([string]$Content, [string]$OutPath, [switch]$Html)
    if ($Html) {
        $Content = "<!doctype html><html><head><meta charset=`"utf-8`"><title>Template preview</title></head><body style=`"margin:0;background:#f0f0f0`">$Content</body></html>"
        if ($OutPath -notmatch '\.html?$') { $OutPath = [IO.Path]::ChangeExtension($OutPath, '.html') }
    }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutPath, $Content, $enc)
    Write-Host "Wrote preview to $OutPath"
}

# ============================================================================
# 7. STRICT GRAMMAR VALIDATION  (-Strict)
# ============================================================================
# The validator (Invoke-StrictValidation / Write-StrictValidation and helpers) lives
# in a shared module so the -Strict switch here and the batch sweep
# (Test-TeklaTemplates.ps1) apply an IDENTICAL grammar check. See the module header
# for what it catches and how findings relate to the harvested corpus version.
. "$PSScriptRoot\_TemplateGrammar.ps1"

# ============================================================================
# MAIN
# ============================================================================

# Allow dot-sourcing (for tests/sweeps) to load the functions without rendering.
if ($env:TEKLA_RENDER_NOMAIN) { return }

if (-not (Test-Path $Path)) { throw "Template file not found: $Path" }
$script:Rows = [math]::Max(1, $Rows)

$text = [System.IO.File]::ReadAllText((Resolve-Path $Path))
try {
    $root = Parse-Template -Text $text
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

$type = Get-Str $root 'type' 'GRAPHICAL'
if (-not $Out) { $Out = [IO.Path]::ChangeExtension((Resolve-Path $Path).Path, $null).TrimEnd('.') + '.preview.svg' }

# Grammar validation runs before rendering so its findings print even if a later
# layout stage warns. It never blocks the preview — the render always happens.
$strictFindings = $false
if ($Strict) { $strictFindings = Write-StrictValidation -Root $root -GrammarFile $GrammarFile -Text $text }

if ($type -eq 'TEXTUAL') {
    Render-Textual -Root $root -OutPath $Out
}
else {
    Render-Graphical -Root $root -OutPath $Out
}
# Exit 1 = parse failure (above); 2 = strict grammar findings; 0 = clean.
if ($strictFindings) { exit 2 } else { exit 0 }
