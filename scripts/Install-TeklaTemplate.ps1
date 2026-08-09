<#
.SYNOPSIS
    Copy finished Template Editor files (.rpt / .tpl) into a location where Tekla will
    find them, deterministically. A template only appears in Tekla once it sits on the
    template search path; this places it there and reports exactly what it did. Windows
    PowerShell 5.1+, no modules to install.

.DESCRIPTION
    Tekla resolves template files along a search path, first match wins, from most
    specific to most general (see references/debugging-and-workflow.md):

      1. Model folder      <model>\  and  <model>\templates\
      2. Firm / project    the folders in the XS_FIRM / XS_PROJECT advanced options
      3. Environment        <TeklaRoot>\Environments\<env>\template\ (+ common\template\)
      4. XS_TEMPLATE_DIRECTORY   an explicit list of template folders

    This script copies one or more templates into a chosen destination on that path. The
    destination is always explicit — the model folder you name, a custom folder, or a
    firm/project folder taken from the environment variable Tekla itself sets — so the same
    inputs always produce the same result. Nothing is auto-guessed.

    It validates the extension, refuses to clobber an existing file unless -Force (with an
    optional timestamped -Backup), supports -WhatIf / -Confirm, and emits one result object
    per file plus a summary. Use -ListTargets to print the candidate destinations (marking
    which exist) without copying anything, so you can see where Tekla will look and pick one.

.PARAMETER Path
    One or more source templates to install. Accepts files, wildcards, and — with -Recurse —
    directories (only *.rpt / *.tpl inside are taken). Required unless -ListTargets.

.PARAMETER ModelFolder
    A Tekla model directory to copy into. The file lands in the model root, or in the
    model's templates\ subfolder with -IntoTemplatesSubfolder. Both are on the search path;
    the subfolder just keeps the model root tidy. This is the simplest, highest-priority
    destination and overrides any same-named shipped template — best for testing.

.PARAMETER IntoTemplatesSubfolder
    With -ModelFolder, copy into <model>\templates\ (created if absent) instead of <model>\.

.PARAMETER Firm
    Copy into the firm template folder, taken from the XS_FIRM environment variable (set by
    the running Tekla environment). Makes the template available to every model using that
    firm folder. Errors if XS_FIRM is not set.

.PARAMETER Project
    Copy into the project template folder, taken from the XS_PROJECT environment variable.
    Errors if XS_PROJECT is not set.

.PARAMETER Destination
    An explicit target folder — a custom template directory, a specific firm/project path,
    or one of the folders printed by -ListTargets.

.PARAMETER Force
    Overwrite an existing file at the destination. Without it, an existing target is left
    untouched and reported as Skipped.

.PARAMETER Backup
    Before overwriting (implies the target exists and -Force), copy the existing file to
    <name>.<yyyyMMdd-HHmmss>.bak next to it, so the previous version is recoverable.

.PARAMETER Recurse
    When a -Path is a directory, search it recursively for *.rpt / *.tpl. Without it, a
    directory is searched one level deep.

.PARAMETER AllowAnyExtension
    Copy files whose extension is not .rpt / .tpl (normally those are skipped with a
    warning, since Tekla will not treat them as templates).

.PARAMETER ListTargets
    Print the candidate template destinations in search order — model folder(s) if
    -ModelFolder is given, plus firm/project/XS_TEMPLATE_DIRECTORY folders from the
    environment and the environment template folders under -TeklaRoot — marking which
    already exist. Copies nothing.

.PARAMETER TeklaRoot
    Root of a Tekla install (e.g. "C:\TeklaStructures\2025.0"), used only by -ListTargets to
    locate the shipped environment template folders. Auto-detects the newest install under
    C:\TeklaStructures if omitted.

.EXAMPLE
    # Test a report in one model (highest priority, overrides shipped templates)
    .\Install-TeklaTemplate.ps1 -Path part_list.rpt -ModelFolder "D:\Models\TowerA"

.EXAMPLE
    # Install several templates into the model's templates\ subfolder, dry-run first
    .\Install-TeklaTemplate.ps1 -Path .\out\*.rpt -ModelFolder "D:\Models\TowerA" -IntoTemplatesSubfolder -WhatIf

.EXAMPLE
    # Roll out firm-wide, keeping a backup of anything replaced
    .\Install-TeklaTemplate.ps1 -Path title_block.tpl -Firm -Force -Backup

.EXAMPLE
    # Show where Tekla will look for this model, without copying
    .\Install-TeklaTemplate.ps1 -ListTargets -ModelFolder "D:\Models\TowerA"
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ModelFolder')]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('FullName')]
    [string[]] $Path,

    [Parameter(ParameterSetName = 'ModelFolder')]
    [string] $ModelFolder,

    [Parameter(ParameterSetName = 'ModelFolder')]
    [switch] $IntoTemplatesSubfolder,

    [Parameter(ParameterSetName = 'Firm', Mandatory = $true)]
    [switch] $Firm,

    [Parameter(ParameterSetName = 'Project', Mandatory = $true)]
    [switch] $Project,

    [Parameter(ParameterSetName = 'Custom', Mandatory = $true)]
    [string] $Destination,

    [switch] $Force,
    [switch] $Backup,
    [switch] $Recurse,
    [switch] $AllowAnyExtension,

    [switch] $ListTargets,
    [string] $TeklaRoot
)

begin {
    $ErrorActionPreference = 'Stop'
    $script:TemplateExt = @('.rpt', '.tpl')
    $script:Collected   = New-Object System.Collections.ArrayList   # source paths across pipeline
    $script:Results     = New-Object System.Collections.ArrayList

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
        if (-not (Test-Path $base)) { return $null }
        $newest = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            Select-Object -First 1
        if ($newest) { return $newest.FullName }
        return $null
    }

    # Tekla's Template Editor parser assumes Windows CRLF line endings; opening a template
    # saved with bare-LF (Unix) endings crashes it silently (stack overflow, exception
    # 0xc0000409). Every shipped .rpt/.tpl is CRLF. So templates are installed through an
    # EOL-normalizing writer, not a byte copy — whatever lands on the search path is CRLF,
    # no matter how it was authored (the Write/Edit tools emit LF). This also strips any BOM.
    # Safe for template content: the literal two-char \n inside a formula/rule string is
    # backslash+n, not a real newline, so it is untouched; only real line breaks are changed.
    function Copy-TemplateAsCrlf {
        param([string]$Src, [string]$Dst)
        $t = [System.IO.File]::ReadAllText($Src)
        $t = $t -replace "`r`n", "`n" -replace "`r", "`n" -replace "`n", "`r`n"  # any mix -> CRLF
        if (-not $t.StartsWith("`r`n")) { $t = "`r`n" + $t }                     # shipped templates lead with a blank line
        [System.IO.File]::WriteAllText($Dst, $t, (New-Object System.Text.UTF8Encoding($false)))
    }

    # Split a possibly ';'-separated advanced-option value into existing/absent folders.
    function Split-PathList {
        param([string]$Value)
        if (-not $Value) { return @() }
        $Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    function Resolve-Destination {
        switch ($PSCmdlet.ParameterSetName) {
            'Custom' { return $Destination }
            'Firm' {
                if (-not $env:XS_FIRM) { throw "-Firm was given but the XS_FIRM environment variable is not set. Run from a Tekla environment shell, or pass -Destination <firm folder>." }
                $first = (Split-PathList $env:XS_FIRM)[0]
                if (-not $first) { throw "XS_FIRM is set but empty." }
                return $first
            }
            'Project' {
                if (-not $env:XS_PROJECT) { throw "-Project was given but the XS_PROJECT environment variable is not set. Run from a Tekla environment shell, or pass -Destination <project folder>." }
                $first = (Split-PathList $env:XS_PROJECT)[0]
                if (-not $first) { throw "XS_PROJECT is set but empty." }
                return $first
            }
            'ModelFolder' {
                if (-not $ModelFolder) { throw "Give a destination: -ModelFolder <path> (optionally -IntoTemplatesSubfolder), -Destination <path>, -Firm, or -Project." }
                if (-not (Test-Path $ModelFolder -PathType Container)) { throw "Model folder not found: $ModelFolder" }
                if ($IntoTemplatesSubfolder) { return (Join-Path $ModelFolder 'templates') }
                return (Get-Item $ModelFolder).FullName
            }
        }
    }

    # Expand one -Path entry into concrete template source files.
    function Expand-Source {
        param([string]$Entry)
        $out = New-Object System.Collections.ArrayList
        # A directory: take templates inside it.
        if (Test-Path $Entry -PathType Container) {
            $gci = @{ Path = $Entry; File = $true }
            if ($Recurse) { $gci.Recurse = $true }
            Get-ChildItem @gci | Where-Object { $script:TemplateExt -contains $_.Extension.ToLower() } |
                ForEach-Object { [void]$out.Add($_.FullName) }
            return $out
        }
        # A file or a wildcard.
        $items = @(Resolve-Path $Entry -ErrorAction SilentlyContinue)
        if (-not $items) { Write-Warning "No file matched: $Entry"; return $out }
        foreach ($it in $items) {
            if (Test-Path $it.Path -PathType Leaf) { [void]$out.Add($it.Path) }
        }
        return $out
    }
}

process {
    if ($Path) { foreach ($p in $Path) { [void]$script:Collected.Add($p) } }
}

end {
    # ---- -ListTargets: report candidate destinations, copy nothing --------------
    if ($ListTargets) {
        Write-Host "Template search order (first match wins). * = folder exists.`n"
        $n = 0
        $emit = {
            param([string]$Label, [string]$Folder)
            if (-not $Folder) { return }
            $script:n = $script:n + 1
            $mark = if (Test-Path $Folder) { '*' } else { ' ' }
            Write-Host ("  {0} {1,-22} {2}" -f $mark, $Label, $Folder)
        }
        $script:n = 0
        if ($ModelFolder) {
            & $emit 'model'            (Get-Item $ModelFolder -ErrorAction SilentlyContinue).FullName
            & $emit 'model\templates'  (Join-Path $ModelFolder 'templates')
        }
        foreach ($f in (Split-PathList $env:XS_PROJECT))          { & $emit 'XS_PROJECT' $f }
        foreach ($f in (Split-PathList $env:XS_FIRM))             { & $emit 'XS_FIRM' $f }
        $root = Resolve-TeklaRoot -Root $TeklaRoot
        if ($root) {
            $envDir = Join-Path $root 'Environments'
            if (Test-Path $envDir) {
                foreach ($e in (Get-ChildItem $envDir -Directory -ErrorAction SilentlyContinue)) {
                    & $emit "env: $($e.Name)" (Join-Path $e.FullName 'template')
                }
            }
        }
        foreach ($f in (Split-PathList $env:XS_TEMPLATE_DIRECTORY)) { & $emit 'XS_TEMPLATE_DIRECTORY' $f }
        if ($script:n -eq 0) { Write-Host "  (no candidates — pass -ModelFolder and/or run from a Tekla environment shell)" }
        Write-Host ""
        return
    }

    # ---- copy mode -------------------------------------------------------------
    if ($script:Collected.Count -eq 0) { throw "No -Path given. Provide one or more .rpt / .tpl files (or -ListTargets)." }

    $dest = Resolve-Destination

    # Gather sources.
    $sources = New-Object System.Collections.ArrayList
    foreach ($entry in $script:Collected) {
        foreach ($f in (Expand-Source $entry)) { [void]$sources.Add($f) }
    }
    $sources = @($sources | Sort-Object -Unique)
    if ($sources.Count -eq 0) { throw "No template files matched the -Path argument(s)." }

    # Ensure destination exists (creating it is part of the install).
    if (-not (Test-Path $dest)) {
        if ($PSCmdlet.ShouldProcess($dest, 'Create destination folder')) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
    }
    elseif (-not (Test-Path $dest -PathType Container)) {
        throw "Destination exists but is not a folder: $dest"
    }

    foreach ($src in $sources) {
        $leaf = Split-Path $src -Leaf
        $ext  = [IO.Path]::GetExtension($leaf).ToLower()
        if (-not $AllowAnyExtension -and ($script:TemplateExt -notcontains $ext)) {
            Write-Warning "Skipping '$leaf': not a template (.rpt/.tpl). Use -AllowAnyExtension to force."
            [void]$script:Results.Add([pscustomobject]@{ Source = $src; Destination = $null; Action = 'Skipped(ext)' })
            continue
        }

        $target = Join-Path $dest $leaf
        $exists = Test-Path $target -PathType Leaf

        if ($exists -and -not $Force) {
            Write-Warning "Exists, not overwriting (use -Force): $target"
            [void]$script:Results.Add([pscustomobject]@{ Source = $src; Destination = $target; Action = 'Skipped(exists)' })
            continue
        }

        $action = if ($exists) { 'Overwrite' } else { 'Copy' }
        if ($PSCmdlet.ShouldProcess($target, "$action from $src")) {
            if ($exists -and $Backup) {
                $bak = "$target.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
                Copy-Item -LiteralPath $target -Destination $bak -Force
                Write-Verbose "Backed up existing to $bak"
            }
            # Template files go through the CRLF normalizer so Tekla can open them; any other
            # file type (-AllowAnyExtension) is copied byte-for-byte so it isn't mangled.
            if ($script:TemplateExt -contains $ext) { Copy-TemplateAsCrlf -Src $src -Dst $target }
            else { Copy-Item -LiteralPath $src -Destination $target -Force }
            [void]$script:Results.Add([pscustomobject]@{ Source = $src; Destination = $target; Action = if ($exists) { 'Overwritten' } else { 'Copied' } })
        }
        else {
            [void]$script:Results.Add([pscustomobject]@{ Source = $src; Destination = $target; Action = "WhatIf:$action" })
        }
    }

    # Summary to the host; the objects go down the pipeline for scripting.
    $copied  = @($script:Results | Where-Object { $_.Action -in 'Copied', 'Overwritten' }).Count
    $skipped = @($script:Results | Where-Object { $_.Action -like 'Skipped*' }).Count
    Write-Host ("`nInstalled {0} template(s) to {1}. {2} skipped." -f $copied, $dest, $skipped)
    if ($copied -gt 0) {
        Write-Host "Reload in Tekla (reopen the Template Editor list, or re-run the report) to pick them up."
    }
    $script:Results
}
