<#
.SYNOPSIS
    Build references\attribute-definitions.md — what each template attribute MEANS — from
    Trimble's "Template attributes in drawing and report templates" PDF.

.DESCRIPTION
    Get-TeklaAttributes.ps1 proves an attribute EXISTS (name, datatype, unit, content-type
    bindings) but says nothing about its meaning, and the install carries no usable
    descriptions (the .ail file mostly restates the name). Trimble publishes the meanings
    as a PDF per version and language, e.g. TS_TEA_2026_en_Template_attributes.pdf
    (Tekla User Assistance → "Template attributes" → download as PDF).

    This script turns that PDF into one grep-able line per documented section:

        - **WELD_ACTUAL_LENGTH1, WELD_ACTUAL_LENGTH2** — §21.21, p.171 — Shows the actual …

    The output is Trimble's copyrighted text, so it is generated locally and gitignored —
    never commit or redistribute it. Re-run per Tekla version / language.

    Text extraction uses pdftotext (xpdf/poppler). Git for Windows ships one at
    <Git>\mingw64\bin\pdftotext.exe, which is found automatically; -PdfToText overrides,
    and -TextFile accepts text you extracted yourself (pdftotext -enc UTF-8, NOT -layout).

    Self-check: the section numbers parsed from the body are compared with the PDF's table
    of contents; any section present in one but not the other is reported.

.PARAMETER Pdf
    Path to the Template attributes PDF.

.PARAMETER TextFile
    Already-extracted text (pdftotext -enc UTF-8 <pdf> <txt>) instead of -Pdf.

.PARAMETER OutFile
    Default: <skill>\references\attribute-definitions.md

.PARAMETER PdfToText
    Explicit path to pdftotext.exe.

.EXAMPLE
    scripts\Get-TeklaAttributeDefinitions.ps1 -Pdf "$HOME\Downloads\TS_TEA_2026_en_Template_attributes.pdf"
#>
[CmdletBinding(DefaultParameterSetName = 'Pdf')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Pdf')]  [string] $Pdf,
    [Parameter(Mandatory, ParameterSetName = 'Text')] [string] $TextFile,
    [string] $OutFile,
    [string] $PdfToText
)

$ErrorActionPreference = 'Stop'
$skillDir = Split-Path $PSScriptRoot -Parent
if (-not $OutFile) { $OutFile = Join-Path $skillDir 'references\attribute-definitions.md' }

# --- get text ------------------------------------------------------------------
function Find-PdfToText {
    $cmd = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $git = Get-Command git -ErrorAction SilentlyContinue
    $roots = @()
    if ($git) { $roots += (Split-Path (Split-Path $git.Source -Parent) -Parent) }   # <Git>\cmd\git.exe → <Git>
    $roots += @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) |
        Where-Object { $_ } | ForEach-Object { Join-Path $_ 'Git' }
    $roots += Join-Path $env:LOCALAPPDATA 'Programs\Git'
    foreach ($r in $roots | Select-Object -Unique) {
        foreach ($rel in 'mingw64\bin\pdftotext.exe', 'usr\bin\pdftotext.exe') {
            $p = Join-Path $r $rel
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

if ($PSCmdlet.ParameterSetName -eq 'Pdf') {
    if (-not (Test-Path $Pdf)) { throw "PDF not found: $Pdf" }
    $Pdf = (Resolve-Path $Pdf).Path
    if (-not $PdfToText) { $PdfToText = Find-PdfToText }
    if (-not $PdfToText) {
        throw ("pdftotext not found. It ships with Git for Windows (<Git>\mingw64\bin\pdftotext.exe). " +
               "Install Git for Windows, pass -PdfToText <path>, or extract the text yourself " +
               "(pdftotext -enc UTF-8 <pdf> <txt>) and pass -TextFile.")
    }
    $tmp = [IO.Path]::GetTempFileName()
    try {
        & $PdfToText -enc UTF-8 $Pdf $tmp
        if ($LASTEXITCODE -ne 0) { throw "pdftotext failed (exit $LASTEXITCODE) on $Pdf" }
        $raw = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    $sourceName = Split-Path $Pdf -Leaf
} else {
    $raw = [IO.File]::ReadAllText((Resolve-Path $TextFile).Path, [Text.Encoding]::UTF8)
    $sourceName = Split-Path $TextFile -Leaf
}

$lines = $raw -split "`r?`n"

# --- front matter: product version, publication date, TOC section numbers -------
$product = ($lines | Select-Object -First 20 | Where-Object { $_ -match '^\s*Tekla Structures \S+' } | Select-Object -First 1)
$product = if ($product) { $product.Trim() } else { 'Tekla Structures (version not detected)' }
$pubDate = ($lines | Select-Object -First 20 | Where-Object { $_ -match '^\s*(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}\s*$' } | Select-Object -First 1)
$pubDate = if ($pubDate) { $pubDate.Trim() } else { '' }

# body starts at the first chapter heading "N Template attributes - A" that sits on its own line
$isChapter = { param($l) $l -match '^\f?(\d{1,2}) Template attributes - ([A-Z])\s*$' }
$bodyStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if (& $isChapter $lines[$i]) { $bodyStart = $i; break } }
if ($bodyStart -lt 0) { throw 'No chapter heading like "2 Template attributes - A" found — is this the Template attributes PDF (and extracted without -layout)?' }

# pdftotext emits TOC section numbers either on their own lines ("2.1 2.2 2.3 …", titles elsewhere)
# or inline with the title ("8.1 GROUP_POS ....... 81 8.2 …") — accept both
$tocSections = [Collections.Generic.HashSet[string]]::new()
foreach ($l in $lines[0..($bodyStart - 1)]) {
    $toks = if ($l -match '^\s*(\d{1,2}\.\d{1,3}\s*)+$') { $l.Trim() -split '\s+' }
            else { [regex]::Matches($l, '(?:^\f?|\d\s)(\d{1,2}\.\d{1,3}) [A-Za-z]') | ForEach-Object { $_.Groups[1].Value } }
    foreach ($t in $toks) { if ($t -notmatch '^1\.') { [void]$tocSections.Add($t) } }
}

# --- body: sections, minus page furniture ----------------------------------------
# A page ends with:  "Template attributes - X" / "" / "<page>" / "" / <running head 1–2 lines> / ""
# and the next page's first line starts with \f. Everything from the footer label to the \f is dropped,
# and the footer's page number is attributed to the sections that were open on that page.
$sections = [Collections.Generic.List[object]]::new()
$cur = $null
$chapter = $null
$pending = [Collections.Generic.List[object]]::new()   # sections started on the current page

function Join-Ident([string]$s) { ($s -replace '(?<=[A-Za-z0-9]_) (?=[A-Za-z0-9])', '').Trim() }

$i = $bodyStart
$n = $lines.Count
while ($i -lt $n) {
    $line = $lines[$i]

    # a chapter opens a new page (\f); the first one that isn't "Template attributes - X"
    # (Disclaimer, Index) ends the body
    if ($chapter -and $line -match '^\f\d{1,2} \S' -and -not (& $isChapter $line)) { break }

    $m = [regex]::Match($line, '^\f?(\d{1,2}) Template attributes - ([A-Z])\s*$')
    if ($m.Success) { $chapter = $m.Groups[1].Value; $i++; continue }

    # page footer → skip to the line that starts the next page
    if ($line -match '^Template attributes - [A-Z]\s*$' -or $line -match '^Template attributes in drawing and report\s*$') {
        $j = $i + 1
        while ($j -lt $n -and $lines[$j].Trim() -eq '') { $j++ }
        if ($j -lt $n -and $lines[$j].Trim() -match '^\d+$') {
            $page = [int]$lines[$j].Trim()
            foreach ($s in $pending) { $s.Page = $page }
            $pending.Clear()
            $k = $j + 1
            while ($k -lt $n -and -not $lines[$k].StartsWith("`f")) { $k++ }
            $i = $k                                    # resume on the next page's first line
            continue
        }
    }

    $line = $line.TrimStart("`f")
    $h = [regex]::Match($line, '^(\d{1,2})\.(\d{1,3}) (\S.*)$')
    if ($h.Success -and $chapter -and $h.Groups[1].Value -eq $chapter) {
        $title = $h.Groups[3].Value.Trim()
        # wrapped heading: "… AREA_" / "…," continued on the next line
        while ($title -match '[_,]$' -and ($i + 1) -lt $n -and $lines[$i + 1] -match '^[A-Za-z0-9_., ]+$') {
            $i++; $title = $title + ' ' + $lines[$i].Trim()
        }
        $cur = [pscustomobject]@{
            Section = '{0}.{1}' -f $h.Groups[1].Value, $h.Groups[2].Value
            Names   = Join-Ident $title
            Page    = $null
            Text    = [Text.StringBuilder]::new()
        }
        $sections.Add($cur); $pending.Add($cur)
        $i++; continue
    }

    if ($cur -and $line.Trim() -ne '') { [void]$cur.Text.Append(' ').Append($line.Trim()) }
    $i++
}

if ($sections.Count -eq 0) { throw 'No attribute sections parsed — unexpected PDF layout.' }

# --- self-check against the TOC ----------------------------------------------------
$bodySet = [Collections.Generic.HashSet[string]]::new([string[]]@($sections | ForEach-Object Section))
$missingFromBody = @($tocSections | Where-Object { -not $bodySet.Contains($_) })
$notInToc        = @($bodySet     | Where-Object { -not $tocSections.Contains($_) })

# --- write -----------------------------------------------------------------------------
$nameCount = ($sections | ForEach-Object { ($_.Names -split ',\s*').Count } | Measure-Object -Sum).Sum
$sb = [Text.StringBuilder]::new()
$null = $sb.AppendLine('# Template attribute definitions')
$null = $sb.AppendLine('')
$null = $sb.AppendLine("<!-- GENERATED by scripts/Get-TeklaAttributeDefinitions.ps1 — do not edit; re-run it instead. -->")
$null = $sb.AppendLine("<!-- Trimble's copyrighted text, built locally from the user's own PDF. Gitignored: never commit or redistribute. -->")
$null = $sb.AppendLine('')
$null = $sb.AppendLine(('Source: `{0}` — {1}{2}. Generated {3}. {4} sections, {5} attribute names.' -f
    $sourceName, $product, ($pubDate ? ", $pubDate" : ''), (Get-Date -Format 'yyyy-MM-dd'), $sections.Count, $nameCount))
$null = $sb.AppendLine('')
$null = $sb.AppendLine('**How to use.** Search, never read whole: grep for the bare attribute name (drop prefixes such as')
$null = $sb.AppendLine('`ASSEMBLY.`/`MAINPART.`/`REBAR.`). The heading match is `\*\*[^*]*NAME` — plain `NAME` also hits')
$null = $sb.AppendLine('"See also" mentions in other entries. Wildcard families are documented under their pattern')
$null = $sb.AppendLine('(`BOUNDING_BOX_xxx`, `CC_DIAMETER_xxx`, `CRANK_xxx`, `DIM_A ... DIM_G`), so if the exact name misses,')
$null = $sb.AppendLine('search its stem. Figures, example screenshots and icon-only values are not in the text — when an')
$null = $sb.AppendLine('entry says "see the example below" or reads garbled, open the PDF at the given page.')
$null = $sb.AppendLine('Not listed here ≠ invalid: existence is decided by `Get-TeklaAttributes.ps1`; this file only says')
$null = $sb.AppendLine('what a documented attribute means. An attribute absent here has an **unverified** meaning.')
$null = $sb.AppendLine('')
foreach ($s in $sections) {
    $text = ($s.Text.ToString() -replace '\s+', ' ').Trim()
    $text = $text -replace '(?<=[A-Z0-9]_) (?=[A-Z0-9])', ''        # re-join identifiers broken at line ends
    if (-not $text) { $text = '(no text in the PDF — content is a figure/table only; see the page)' }
    $page = if ($s.Page) { ", p.$($s.Page)" } else { '' }
    $null = $sb.AppendLine(('- **{0}** — §{1}{2} — {3}' -f $s.Names, $s.Section, $page, $text))
}

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[IO.File]::WriteAllText($OutFile, $sb.ToString(), [Text.UTF8Encoding]::new($false))

Write-Host ('Wrote {0}' -f $OutFile)
Write-Host ('  {0}{1} — {2} sections, {3} attribute names, {4:n0} KB' -f $product, ($pubDate ? ", $pubDate" : ''),
    $sections.Count, $nameCount, ((Get-Item $OutFile).Length / 1KB))
if ($tocSections.Count) {
    if ($missingFromBody.Count -or $notInToc.Count) {
        if ($missingFromBody.Count) { Write-Warning ('In the TOC but not parsed from the body: ' + ($missingFromBody -join ', ')) }
        if ($notInToc.Count)        { Write-Warning ('Parsed from the body but not in the TOC: ' + ($notInToc -join ', ')) }
    } else {
        Write-Host ('  matches the table of contents ({0} sections)' -f $tocSections.Count)
    }
} else {
    Write-Warning 'Table of contents not recognised — completeness not checked.'
}

[pscustomobject]@{
    OutFile  = $OutFile
    Product  = $product
    Sections = $sections.Count
    Names    = $nameCount
    TocMissing = $missingFromBody
}
