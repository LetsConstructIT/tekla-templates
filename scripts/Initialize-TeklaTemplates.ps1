<#
.SYNOPSIS
    One-shot local setup for the tekla-templates skill: build the data assets that are
    derived from your own Tekla install and therefore not shipped in the repo.

.DESCRIPTION
    Everything the skill needs beyond the repo itself is generated from the Tekla
    Structures installation on this machine:

        assets\template-grammar.json   block/property/enum allow-list   (-Strict validation)
        assets\template-schema.json    JSON Schema for the IR           (pure function of the grammar)
        assets\template-index.json     searchable corpus index          (Find-TeklaTemplateExamples.ps1)

    This script finds the install, works out which of the three are missing or stale, and
    builds only those — so it is safe to re-run. Takes ~2 minutes on a cold clone (grammar
    ~30 s, schema ~2 s, index ~65 s) and needs doing once per Tekla version.

    Optional fourth asset — attribute MEANINGS, not just names:

        references\attribute-definitions.md   one line per documented attribute

    built from Trimble's "Template attributes" PDF (e.g. TS_TEA_2026_en_Template_attributes.pdf),
    which each user downloads for their own version and language. Pass -AttributePdf, or drop
    the PDF in the skill folder or your Downloads folder and it is picked up automatically.
    It never affects readiness/exit codes. See Get-TeklaAttributeDefinitions.ps1.

    Skipping setup is not fatal: authoring, preview, and install all work without these
    files. What degrades is -Strict grammar validation, the JSON-IR schema gate, and the
    shipped-corpus search.

.PARAMETER TeklaRoot
    A Tekla install root (e.g. C:\TeklaStructures\2026.0). Default: the newest version
    found under C:\TeklaStructures, then under the Program Files "Tekla Structures"
    folders.

.PARAMETER Path
    Extra template roots to fold into the grammar and index (a firm or project library).
    Repeatable. Also the escape hatch when there is no local Tekla install but you do have
    a copy of the shipped templates.

.PARAMETER AttributePdf
    Trimble's "Template attributes in drawing and report templates" PDF. Builds
    references\attribute-definitions.md from it (~1 s). Default: the newest
    TS_TEA_*Template_attributes*.pdf in the skill folder or ~\Downloads, if any.

.PARAMETER Force
    Rebuild assets that already exist. Without it, present-and-current assets are left
    alone and only missing ones are built. Required to refresh assets that were built from
    a different Tekla version than the one detected now.

.PARAMETER Check
    Report status only — build nothing. Exit code 0 = ready, 1 = setup needed.

.PARAMETER Quiet
    Suppress the per-step progress output of the generators; keep the final summary.

.OUTPUTS
    A status object per asset (Asset, Path, State, Version, Generated) plus a summary line.
    Exit codes: 0 = everything present and current, 1 = something is still missing.

.EXAMPLE
    scripts\Initialize-TeklaTemplates.ps1
    # first-run setup: builds whatever is missing, against the newest local Tekla

.EXAMPLE
    scripts\Initialize-TeklaTemplates.ps1 -Check
    # is this clone ready? no building

.EXAMPLE
    scripts\Initialize-TeklaTemplates.ps1 -TeklaRoot C:\TeklaStructures\2024.0 -Force
    # rebuild all three against a pinned version (after a Tekla upgrade/downgrade)
#>
[CmdletBinding()]
param(
    [string]   $TeklaRoot,
    [string[]] $Path,
    [string]   $AttributePdf,
    [switch]   $Force,
    [switch]   $Check,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

$skillDir  = Split-Path $PSScriptRoot -Parent
$assetsDir = Join-Path $skillDir 'assets'

function Write-Step { param([string]$Msg) Write-Host $Msg }
function Write-Note { param([string]$Msg) if (-not $Quiet) { Write-Host $Msg } }

# --- locate the Tekla install ------------------------------------------------
function Find-TeklaRoot {
    $bases = @(
        'C:\TeklaStructures'
        (Join-Path $env:ProgramW6432 'Tekla Structures')
        (Join-Path ${env:ProgramFiles(x86)} 'Tekla Structures')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($base in $bases) {
        $newest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' -and (Test-Path (Join-Path $_.FullName 'Environments')) } |
            Sort-Object { [version]($_.Name -replace '^(\d+\.\d+).*$', '$1') } -Descending |
            Select-Object -First 1
        if ($newest) { return $newest.FullName }
    }
    return $null
}

if ($TeklaRoot) {
    if (-not (Test-Path $TeklaRoot)) {
        Write-Host "TeklaRoot not found: $TeklaRoot"
        Write-Host 'Pass the folder of a Tekla version, e.g. -TeklaRoot "C:\TeklaStructures\2026.0",'
        Write-Host 'or omit -TeklaRoot to auto-detect the newest install.'
        exit 1
    }
    $TeklaRoot = (Resolve-Path $TeklaRoot).Path
} else {
    $TeklaRoot = Find-TeklaRoot
}

$detectedVersion = if ($TeklaRoot) { Split-Path $TeklaRoot -Leaf } else { $null }

# --- current state of each asset ---------------------------------------------
function Get-AssetMeta {
    param([string]$File)
    if (-not (Test-Path $File)) { return $null }
    try {
        # both generated assets carry meta.version / meta.generated; the schema does not
        $json = Get-Content $File -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $json.meta
    } catch { return $null }
}

$grammarFile = Join-Path $assetsDir 'template-grammar.json'
$schemaFile  = Join-Path $assetsDir 'template-schema.json'
$indexFile   = Join-Path $assetsDir 'template-index.json'

$defsFile    = Join-Path $skillDir 'references\attribute-definitions.md'

# The PDF is per version: Tekla "2026.0" ↔ TS_TEA_2026_…pdf. Auto-pick prefers the matching
# year, then the newest year; an explicit -AttributePdf always wins.
$teklaYear = if ($detectedVersion -match '^(\d{4})') { $Matches[1] } else { $null }
$pdfYear   = { param($name) if ($name -match 'TS_TEA_(\d{4})') { $Matches[1] } else { '0' } }
if (-not $AttributePdf) {
    $AttributePdf = @($skillDir, (Join-Path $HOME 'Downloads')) |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -File -Filter 'TS_TEA_*Template_attributes*.pdf' -ErrorAction SilentlyContinue } |
        Sort-Object @{ e = { (& $pdfYear $_.Name) -eq $teklaYear }; Descending = $true },
                    @{ e = { & $pdfYear $_.Name }; Descending = $true },
                    @{ e = 'LastWriteTime'; Descending = $true } |
        Select-Object -First 1 -ExpandProperty FullName
} elseif (-not (Test-Path $AttributePdf)) {
    Write-Host "AttributePdf not found: $AttributePdf"
    exit 1
}
$defsSource = if (Test-Path $defsFile) {
    (Get-Content $defsFile -TotalCount 8 | Where-Object { $_ -like 'Source:*' } | Select-Object -First 1) -replace '^Source:\s*', ''
} else { $null }
$defsYear  = if ($defsSource -match 'Tekla Structures (\d{4})') { $Matches[1] } else { $null }
$defsState = if (-not (Test-Path $defsFile)) { 'missing' }
             elseif ($teklaYear -and $defsYear -and $defsYear -ne $teklaYear) { 'stale' }
             else { 'present' }

$grammarMeta = Get-AssetMeta $grammarFile
$indexMeta   = Get-AssetMeta $indexFile

function Get-State {
    param([string]$File, $Meta)
    if (-not (Test-Path $File)) { return 'missing' }
    if ($detectedVersion -and $Meta -and $Meta.version -and
        $Meta.version -ne 'custom' -and $Meta.version -ne $detectedVersion) { return 'stale' }
    return 'present'
}

$grammarState = Get-State $grammarFile $grammarMeta
$indexState   = Get-State $indexFile   $indexMeta
$schemaState  = if (-not (Test-Path $schemaFile)) { 'missing' }
                elseif ($grammarState -eq 'present' -and
                        (Get-Item $schemaFile).LastWriteTime -lt (Get-Item $grammarFile).LastWriteTime) { 'stale' }
                else { 'present' }

Write-Step ''
Write-Step 'tekla-templates — local setup'
Write-Step ('  skill folder : {0}' -f $skillDir)
Write-Step ('  Tekla install: {0}' -f ($TeklaRoot ?? '(none found)'))
if ($Path) { foreach ($p in $Path) { Write-Step ('  extra corpus : {0}' -f $p) } }
Write-Step ''
foreach ($a in @(
    @{ n = 'template-grammar.json'; s = $grammarState; m = $grammarMeta }
    @{ n = 'template-schema.json';  s = $schemaState;  m = $null }
    @{ n = 'template-index.json';   s = $indexState;   m = $indexMeta }
)) {
    $detail = if ($a.m -and $a.m.version) { " (built from {0}, {1})" -f $a.m.version, $a.m.generated } else { '' }
    Write-Step ('  [{0,-7}] {1}{2}' -f $a.s, $a.n, $detail)
}
Write-Step ('  [{0,-7}] attribute-definitions.md (optional){1}' -f $defsState,
    ($defsSource ? " ($defsSource)" : ($AttributePdf ? " — will build from $(Split-Path $AttributePdf -Leaf)" : ' — needs the Template attributes PDF, -AttributePdf')))
Write-Step ''

if ($Check) {
    $ready = @($grammarState, $schemaState, $indexState) -notcontains 'missing'
    if ($ready) {
        if (@($grammarState, $schemaState, $indexState) -contains 'stale') {
            Write-Step 'Usable, but built from a different Tekla version than the one installed.'
            Write-Step 'Refresh with:  scripts\Initialize-TeklaTemplates.ps1 -Force'
        } else {
            Write-Step 'Ready — all data assets present and current.'
        }
        exit 0
    }
    Write-Step 'Setup needed. Run:  scripts\Initialize-TeklaTemplates.ps1'
    exit 1
}

# --- optional: attribute definitions (independent of the Tekla install) ------
# Cheap (~1 s), so a stale file is refreshed automatically — but only from a PDF whose year
# matches the install; never replace current definitions with another version's.
$pdfMatches = $AttributePdf -and $teklaYear -and ((& $pdfYear (Split-Path $AttributePdf -Leaf)) -eq $teklaYear)
$buildDefs  = $AttributePdf -and (
    $PSBoundParameters.ContainsKey('AttributePdf') -or $Force -or
    $defsState -eq 'missing' -or ($defsState -eq 'stale' -and $pdfMatches))
if ($buildDefs) {
    Write-Step ("-> attribute definitions from {0}" -f (Split-Path $AttributePdf -Leaf))
    if ($teklaYear -and -not $pdfMatches) {
        Write-Step ("   note: PDF is not for Tekla {0} — meanings may differ; pass a TS_TEA_{0}_… PDF when you have one" -f $teklaYear)
    }
    try {
        $null = & (Join-Path $PSScriptRoot 'Get-TeklaAttributeDefinitions.ps1') -Pdf $AttributePdf
    } catch {
        Write-Step ("   FAILED (optional, setup continues): {0}" -f $_.Exception.Message)
    }
} elseif ($defsState -eq 'missing') {
    Write-Note '-> attribute definitions: no PDF found, skipped (optional; -AttributePdf <pdf>)'
} elseif ($defsState -eq 'stale') {
    Write-Step ("-> attribute definitions: built from {0}, install is {1}; no matching PDF found (-AttributePdf <pdf>)" -f $defsYear, $teklaYear)
}

# --- decide what to build ----------------------------------------------------
$buildGrammar = ($grammarState -eq 'missing') -or ($Force -and $TeklaRoot) -or ($grammarState -eq 'stale' -and $Force)
$buildIndex   = ($indexState   -eq 'missing') -or ($Force -and $TeklaRoot) -or ($indexState   -eq 'stale' -and $Force)
$buildSchema  = ($schemaState  -ne 'present') -or $buildGrammar -or $Force

if (-not ($buildGrammar -or $buildIndex -or $buildSchema)) {
    $note = if (@($grammarState, $indexState) -contains 'stale') {
        "Nothing to build. Assets exist but came from another Tekla version — rerun with -Force to refresh."
    } else { 'Nothing to build — already set up.' }
    Write-Step $note
    exit 0
}

if (-not $TeklaRoot -and -not $Path -and ($buildGrammar -or $buildIndex)) {
    Write-Step 'No Tekla Structures installation found on this machine.'
    Write-Step 'The grammar and corpus index are harvested from the templates shipped with Tekla,'
    Write-Step 'so one of these is needed:'
    Write-Step '  - install Tekla Structures on this PC, then re-run this script'
    Write-Step '  - point at a non-default location:  -TeklaRoot "D:\TeklaStructures\2026.0"'
    Write-Step '  - harvest from a copy of the templates: -Path "\\server\tekla\Environments"'
    Write-Step ''
    Write-Step 'Everything except -Strict grammar checks, the JSON-IR schema gate, and'
    Write-Step 'shipped-corpus search works without them.'
    exit 1
}

# --- build -------------------------------------------------------------------
$common = @{}
if ($TeklaRoot) { $common.TeklaRoot = $TeklaRoot }
if ($Path)      { $common.Path      = $Path }
if ($Quiet)     { $common.Quiet     = $true }

$failed = @()

function Invoke-Step {
    # NB: not $Args — that name collides with PowerShell's automatic $args array
    param([string]$Label, [string]$Script, [hashtable]$Splat)
    Write-Step ("-> {0}" -f $Label)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = & (Join-Path $PSScriptRoot $Script) @Splat
        $sw.Stop()
        Write-Step ("   done in {0:n0}s" -f $sw.Elapsed.TotalSeconds)
        return $true
    } catch {
        $sw.Stop()
        Write-Step ("   FAILED: {0}" -f $_.Exception.Message)
        return $false
    }
}

if ($buildGrammar) {
    if (Invoke-Step 'grammar allow-list (~30 s)' 'Get-TeklaGrammar.ps1' $common) {
        $buildSchema = $true          # schema is a pure function of the grammar
    } else {
        $failed += 'template-grammar.json'
        $buildSchema = $false         # no point deriving a schema from a stale/absent grammar
    }
} else {
    Write-Note '-> grammar allow-list: already present, skipped (-Force rebuilds)'
}

if ($buildSchema) {
    if (-not (Invoke-Step 'JSON schema (~2 s)' 'New-TeklaTemplateSchema.ps1' @{})) {
        $failed += 'template-schema.json'
    }
} else {
    Write-Note '-> JSON schema: already current, skipped'
}

if ($buildIndex) {
    if (-not (Invoke-Step 'corpus index (~65 s)' 'Get-TeklaTemplateIndex.ps1' $common)) {
        $failed += 'template-index.json'
    }
} else {
    Write-Note '-> corpus index: already present, skipped (-Force rebuilds)'
}

# --- summary -----------------------------------------------------------------
Write-Step ''
foreach ($f in @($grammarFile, $schemaFile, $indexFile)) {
    Write-Step ('  [{0,-7}] {1}' -f ((Test-Path $f) ? 'ok' : 'missing'), (Split-Path $f -Leaf))
}
Write-Step ''

if ($failed.Count) {
    Write-Step ("Setup incomplete — could not build: {0}" -f ($failed -join ', '))
    Write-Step 'Everything else still works; re-run this script to retry.'
    exit 1
}

Write-Step ("Setup complete{0}. The skill is ready to use." -f ($detectedVersion ? " for Tekla $detectedVersion" : ''))
exit 0
