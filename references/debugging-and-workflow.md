# Workflow, file placement, and debugging

## Preview the layout

Catch layout bugs (overlapping columns, fields past template width, misaligned headings, short `length`, horizontal table lines cutting through text/fields — the y-down anchoring mistake) without a running model:

```powershell
scripts\Render-TeklaTemplate.ps1 -Path title_block.tpl         # -> title_block.preview.svg
scripts\Render-TeklaTemplate.ps1 -Path part_list.rpt           # -> part_list.preview.svg (SVG is canonical for .rpt too)
scripts\Render-TeklaTemplate.ps1 -Path part_list.rpt -AsText   # optional: monospaced mock report to stdout
```

- Layout warnings → stderr, drawn in red in the SVG; often name the offending field.
- Also a **parse checker**: syntax error (unbalanced `{}`, unterminated string, stray `=`) exits nonzero with line number; clean parse exits 0.
- Approximation only: formulas render as placeholders (`GetValue("PROFILE")` → `{PROFILE}`), font widths estimated. Judges declared geometry, not real data. Final signoff = report generated in Tekla.

## Where templates live

Search path (first match wins), most specific first:

1. **Model folder** — `<model>\` and `<model>\templates\`
2. **Project / firm folders** — `XS_PROJECT`, `XS_FIRM`
3. **Environment** — `<TeklaRoot>\Environments\<env>\template\`, `...\common\template\`
4. **`XS_TEMPLATE_DIRECTORY`** advanced option

Drop new/edited templates in the **model folder** for testing. Active search path: `XS_TEMPLATE_DIRECTORY` / `XS_TEMPLATE_DIRECTORY_SYSTEM` (File ▸ Settings ▸ Advanced Options ▸ File Locations) or the model's `.ini`.

`scripts\Install-TeklaTemplate.ps1` copies deterministically. Explicit destination: `-ModelFolder <path>` (+ `-IntoTemplatesSubfolder`), `-Destination <path>`, or `-Firm`/`-Project` (reads env vars). Validates extension, supports `-WhatIf`, no overwrite without `-Force` (optional `-Backup`). `-ListTargets` prints candidate folders in search order without copying. After copying, reload the Template Editor list or re-run the report.

Shipped reference templates: `<TeklaRoot>\Environments\common\template\*.rpt` and `...\common\system\*.rpt` / `*.tpl`.

## Editing options

- **Text editing** (this skill's main mode): fast, diffable, scriptable. Best for surgical changes and generating from spec.
- **Template Editor GUI** (`TplEd.exe`): visual layout, attribute picker. Best for pixel-level title-block layout. Interchangeable — same text files.

When editing as text: **start from a working template** (bundled `assets/` or shipped) so `template` header, `version`, and font blocks are valid. Change one thing at a time; reopen in Tekla to confirm parse.

## Opening Template Editor

```
<TeklaRoot>\bin\applications\Tekla\Tools\TplEd\TplEd.exe
```

or `StartTemplateEditor.exe` in the same folder; in Tekla: **Drawings & reports ▸ Template Editor**. Its attribute picker reads the same `contentattributes_*.lst` files the bundled script parses.

## Generating a report to test it

Tekla: **Drawings & reports ▸ Reports** → select objects (or none = whole model) → pick template → Create. Drawing tables (`.tpl`): placed via drawing/table layout or drawing template. No supported headless CLI; test in an open model.

## Debugging by bisection: build up one row at a time

When a template misbehaves in a way inspection can't pin down — TplEd crashes on open, a
field is blank, a total is wrong, a whole section vanishes — and the file has several rows,
nested scopes, and aggregates, **stop staring at the full file**. Rebuild it from a minimal
known-good base, adding **one construct per step**, previewing (and, for crashes, opening in
TplEd) after each. The first step that reproduces the fault names the culprit; the step
before it is your last-good version to diff against.

Bisection beats reading because template faults are **interaction** faults: a `Sum()` that
reads a field in a sibling row, an `oncombine` that only misfires once a parent `COMBINE`
row wraps it, a nested `contenttype` scope that returns nothing. None of these are visible
in a single field — only in how a field behaves once the rows around it exist.

The ladder (a worked example ships in `demo/` — target `CastUnit_Rebar_Count.rpt`, rungs in
`demo/bisect/t1…t7`, a cast-unit rebar count):

1. **Base row** (`t1`) — `template` header + one visible `row` of the outer `contenttype`
   with a single field. Preview it; confirm it's clean. This is your anchor.
2. Add the **fixed chrome** — `pageheader` title field (`t2`), then header `text` columns
   (`t3`). Cheap, rarely the culprit, but rules them out.
3. Add the **nested scope rows** (`t4`) — the hidden `PART` › `REBAR` wrapper rows and the
   inner field they exist to reach (`GetValue("NUMBER")`). This is the usual break point:
   wrong `contenttype`, empty scope, a field reaching across rows.
4. Add the **aggregate that reads them** (`t5`) — `Sum("rebar_num")` in the outer row.
5. Add the **grand total** (`t6`) — `footer` with `Total("total_rebars")`.
6. `t7` = the full report. If every rung was clean but `t7` isn't, the fault is an
   interaction between two of the last additions — split that step finer.

Rules that make it work:

- **One construct per rung, and each rung must be a valid, openable template** — not a
  half-written edit. Preview every rung (`Render-TeklaTemplate.ps1 -Strict`); for a
  suspected crash, actually open the rung in TplEd, since the four open-crash traps
  (structural comment, bare-LF, packed formatting, template notes > 120 chars) are
  invisible to the preview parser.
- **Add in dependency order**: a field before the row that scopes it, an aggregate after
  the field it sums, a `Total()` after the field it totals. Adding out of order fails for
  the wrong reason.
- Keep the rungs. The diff between the last-good and first-bad rung *is* the bug report,
  and the ladder documents the template's structure for the next person.

This is the constructive form of the "change one thing at a time" rule (see *Editing
options* above): when you can't safely subtract from a broken file, build a correct one up
to the point it breaks.

## Debugging: blank field

Check in order:

1. **Wrong attribute name** — re-extract and confirm spelling/case: `Get-TeklaAttributes.ps1 -ContentType PART -Name <fragment>`. Unknown name → empty.
2. **Wrong content type/scope** — bare `GetValue("DIAMETER")` in a `PART` row is empty (belongs to `BOLT`). Nest a BOLT row or use a prefixed hop.
3. **Attribute genuinely unset** (e.g. empty UDA). Guard: `if (IsSet("ATTR")) then … else … endif`.
4. **`StepOver()`** in formula or `rule` suppressed the row.
5. **`formatzeroasempty = TRUE`** prints a legitimate `0` as blank. Set `FALSE` if zero should show.

## Debugging: truncated value / shows `#`

- `length` (or `decimals`) too small → widen. Numeric overflow of field width is the common cause of `#`.
- Check `x`/`location` doesn't overlap the next column.
- Graphical fields: **`maxnumoflines = 1`** (shipped default) *clips* instead of wrapping — raise it or widen `length`/shrink font.
- Check display `unit`/`class` isn't inflating the number (`mm` needs more width than `m`).

## Debugging: text crosses a table line (graphical)

`location`/`y1` anchor the text **BOTTOM** and y runs **UP** — glyphs occupy `y … y+fontsize`. A baseline computed downward from the band's top line lands the glyph tops across that line (a field at y=4.2, fontsize 2.5 in a 0–6 band tops out at 6.7). Fix: measure the offset up from the band's *bottom* line (here y≈1.8). The preview warns (`Line '…' cuts through …`) when a horizontal `lineorarc` cuts into a text/field span.

## Debugging: won't open / parse error

Almost always a text-editing slip:

- Unbalanced `{ }`; missing `;` after a nested block's closing brace (`};`).
- **Formula quote escaping**: interior quotes must be `\"`.
- Changed `version` in the header — revert to the starting template's value.
- Stray smart-quote/tab from copy-paste. Keep structural parts plain ASCII.
- **Duplicate valuefield names (GRAPHICAL only)**: two `valuefield`s with the same `name` in the *same* row/section collide — TplEd reports a colliding valuefield name. The same name in *different* rows is fine, and textual reports may reuse names freely. `Render-TeklaTemplate.ps1 -Strict` and `Test-TeklaTemplates.ps1` flag this.

Diff against the original (or `assets/` skeleton).

## Debugging: garbled characters

Mojibake in non-ASCII text (°, ², accents) = encoding mismatch. Legacy templates are commonly ANSI/Latin-1; some UTF-8. Save in the source file's encoding, **no BOM**. Prefer `TranslatedText` keys over literal accented strings.

## Version differences

Format grammar is **stable** (2022–2026 parse the same blocks); the **attribute catalog grows** per version — hence extracting from the local install, not bundling a frozen list. Blank report after moving to an older version → re-extract that version's catalog and check the names.
